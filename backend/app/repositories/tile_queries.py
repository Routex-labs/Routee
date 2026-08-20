# 건물 층 지도를 MVT(Mapbox Vector Tile) 바이트로 렌더링하는 Query 함수.
# geo_transform은 DB 컬럼으로 저장하지 않고, 요청마다 해당 건물 Node들의
# (x_m, y_m, lat, lng) 실측 대응점으로 즉석 피팅한다. 실측 앵커가 3개
# 미만이면(예: test-center처럼 합성 데이터) 임의 앵커에 1m=1m로 배치하는
# 합성 대응점으로 대체한다 — None을 반환해 지도에 아무것도 못 그리게 두는
# 대신, 위치는 가짜지만 형태/크기는 정확한 지도를 보여준다.

from __future__ import annotations

import hashlib
import logging
import math
import threading
from pathlib import Path

import mapbox_vector_tile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.geo.tiling import build_floor_tile_layers, tile_bounds
from app.models import Building, Floor, Poi, Store
from app.repositories.building_queries import _default_floor, _find_floor
from app.repositories.geo_transform import fit_building_geo_transform
from app.repositories.tile_cache import BoundedTileCache

logger = logging.getLogger(__name__)


# (building_id, floor_name, z, x, y, revision) → MVT 바이트 캐시.
#
# MVT 인코딩은 CPU-바운드(층 하나 9개 타일 인코딩에 ~1s 이상)라, 클라이언트가 층을
# 전환할 때 MapLibre가 격자 여러 개를 병렬 요청하면 uvicorn 단일 워커가 직렬로
# 처리하며 뒤쪽 타일이 3~4초 이상 걸린다. 그 사이 MapLibre 네이티브 OkHttp의
# keep-alive 소켓 재사용/취소 경쟁으로 "Socket closed"가 튀고, 실패한 타일은
# MapLibre가 잠시 재요청하지 않아 해당 층 오버레이가 빈 채로 남는 증상이 있었다.
# 타일 바이트는 (건물 데이터, 층, z, x, y) 조합에 대해 결정적이라 프로세스
# 메모리에 캐싱해도 안전하다 — 첫 요청 후 나머지는 마이크로초 반환이라 병렬
# 요청 폭풍이 사라진다.
#
# 예전 구현은 무제한 전역 dict였다 — 오래 사는 배포 프로세스에서 조합이 쌓이면
# 메모리가 상한 없이 커졌다. 이제 바이트·항목 수 상한을 둔 BoundedTileCache로
# 바꿔 LRU로 축출하고, 같은 키 동시 요청은 single-flight로 한 번만 인코딩한다.
_TILE_CACHE = BoundedTileCache(
    max_entries=settings.tile_cache_max_entries,
    max_bytes=settings.tile_cache_max_bytes,
)

# 캐시 무효화 revision — 왜 graph_revision이 아니라 DB 파일 세대인가.
#
#   "재시드하면 프로세스가 재시작되니 stale 걱정이 없다"는 전제는 이 저장소의
#   개발 절차에서 성립하지 않는다(AGENTS.md 참고). reset_and_seed는 별도
#   프로세스로 돌고 uvicorn은 --reload-dir app으로 app/ 코드만 감시하므로,
#   재시드는 DB 파일만 바꿀 뿐 리로드를 트리거하지 않는다. 그대로 두면 서버가
#   시드 이전 타일을 계속 내보낸다.
#
#   타일이 그리는 것은 stores·POI·footprint·못 걷는 면(+geo transform)다. 반면
#   app/graph/revision.py의 graph_revision(nodes, edges)은 길찾기 그래프의
#   노드·간선만 해싱하므로, 매장 이름/폴리곤 편집 같은 "타일에는 보이지만
#   그래프에는 없는" 변경을 잡지 못한다. 그래서 타일의 revision으로는 그래프
#   체크섬 대신 DB 파일 세대 (경로, mtime_ns)를 쓴다 — 재시드가 곧 mtime 변경
#   이므로 모든 타일 입력 변경을 정확히 포괄한다. 경로까지 넣는 이유는 서로
#   다른 DB가 우연히 같은 mtime을 가질 수 있어서다(테스트가 임시 DB를 갈아끼울
#   때 실제로 일어난다).
_CACHE_GENERATION: tuple[str, int] | None = None

# 워밍업 데몬 스레드와 요청 처리 스레드가 세대 전역을 함께 만지므로 교체는 락으로 묶는다.
_CACHE_LOCK = threading.Lock()

# 매장 라벨 좌표 memo — revision 하나에 대한 {store_id: (lng, lat)}.
#
# 왜 필요한가 — label_point(격자 탐색)가 타일 생성 비용의 대부분인데, 결과는
# 매장 폴리곤 + 건물 단위 affine 변환에만 의존해 z/x/y와 무관하다(근거는
# build_floor_tile_layers의 store_label_memo 파라미터 주석). 즉 같은 매장을
# 타일마다·줌마다 다시 계산할 이유가 없어, (store_id, revision) 단위로 프로세스
# 메모리에 한 번만 계산한다.
#
# 무효화는 타일 LRU 캐시(_TILE_CACHE)와 같은 축이다 — revision(=DB 파일 세대)이
# 바뀌면 타일 캐시 키가 갈리듯 이 memo도 통째로 버린다. revision을 항목 키가
# 아니라 memo 전체의 소유 키로 두는 이유는, 낡은 세대의 좌표가 새 세대 dict에
# 섞여 남는 일 자체를 없애기 위해서다(항목 수백 개 × 좌표 2개라 재계산도 싸다).
#
# 동시성 — 교체(revision 전환)만 락으로 묶는다. 항목 get/set은 여러 렌더 스레드가
# 락 없이 하지만, 값이 결정적이라(같은 입력 → 같은 좌표) 경쟁해 봐야 같은 값을
# 두 번 계산해 넣는 것이 최악이다. 메모리는 실데이터 기준 매장 781개 × float 2개로
# 수십 KB 수준이라 상한을 따로 두지 않는다.
_LABEL_MEMO_LOCK = threading.Lock()
_LABEL_MEMO_REVISION: str | None = None
_LABEL_MEMO: dict[str, tuple[float, float]] = {}


def _label_memo_for(revision: str) -> dict[str, tuple[float, float]]:
    global _LABEL_MEMO_REVISION, _LABEL_MEMO
    with _LABEL_MEMO_LOCK:
        if revision != _LABEL_MEMO_REVISION:
            _LABEL_MEMO_REVISION = revision
            _LABEL_MEMO = {}
        return _LABEL_MEMO


# 캐시 세대를 구한다. settings.database_url이 아니라 세션이 실제로 물고 있는
# 엔진에서 경로를 얻는다 — 테스트는 임시 DB 엔진을 get_db 오버라이드로 주입할 뿐
# settings는 건드리지 않으므로, 전역 설정을 보면 엉뚱한 파일을 보게 된다.
#
# sqlite 파일이 아니면(메모리 DB나 다른 백엔드) None을 돌려준다. 무효화 근거가
# 없는 상태에서 세대를 지어내면 조용히 낡은 타일을 내보내게 되므로, 그때는
# 세대 판정을 아예 건너뛴다.
def _cache_generation(session: Session) -> tuple[str, int] | None:
    # get_bind()는 Engine 또는 Connection을 준다. .engine은 Engine이면 자기 자신,
    # Connection이면 소속 Engine이라 어느 쪽이든 같은 URL에 닿는다.
    url = session.get_bind().engine.url
    if url.get_backend_name() != "sqlite" or not url.database:
        return None
    try:
        return url.database, Path(url.database).stat().st_mtime_ns
    except OSError:
        return None


# DB가 바뀌었으면(=재시드) 타일 캐시를 통째로 버려 메모리를 즉시 회수한다.
# revision을 캐시 키에도 넣지만(아래), 이 선제 무효화는 낡은 세대의 바이트가
# LRU 축출을 기다리며 상주하지 않게 한다.
def _invalidate_if_reseeded(session: Session) -> None:
    global _CACHE_GENERATION

    generation = _cache_generation(session)
    if generation is None:
        return

    with _CACHE_LOCK:
        if generation != _CACHE_GENERATION:
            _CACHE_GENERATION = generation
            _TILE_CACHE.invalidate_all()


# 캐시 키에 실을 revision 토큰. DB 세대가 있으면 "경로@mtime_ns", 없으면
# (메모리 DB 등 무효화 근거 없음) 고정 토큰. 세대가 바뀌면 토큰이 바뀌어 기존
# 키가 더는 조회되지 않으므로, 선제 무효화와 별개로도 stale 타일이 안 나간다.
def _cache_revision(session: Session) -> str:
    generation = _cache_generation(session)
    if generation is None:
        return "no-generation"
    path, mtime_ns = generation
    return f"{path}@{mtime_ns}"


# 클라이언트가 타일 URL에 붙일 revision 토큰.
#
# 왜 필요한가 — 타일은 `max-age`가 지나면 재검증(304)을 하러 온다. 본문은 안
# 오지만 왕복은 그대로라, 층을 오갈 때마다 수십 건이 서버까지 닿는다. URL에
# revision을 넣으면 내용이 바뀔 때 URL 자체가 바뀌므로 `immutable`을 붙여
# **재검증조차 하지 않게** 만들 수 있다.
#
# `_cache_revision`을 그대로 쓰지 않는 이유는 두 가지다. 그 값은 서버 파일
# 경로를 담고 있어 밖으로 내보낼 것이 아니고, URL에 넣기에도 길다. 짧은
# 불투명 해시로 접는다 — 클라이언트는 "바뀌었는지"만 알면 된다.
def tile_revision(session: Session) -> str:
    return hashlib.blake2b(_cache_revision(session).encode(), digest_size=8).hexdigest()


# 캐시를 거치지 않는 순수 렌더. 건물/층이 없으면 None.
def _render_tile_bytes(
    session: Session,
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
    # 매장 라벨 좌표 memo(없으면 매번 계산). render_floor_tile이 revision에 묶인
    # dict를 넘긴다 — 그래야 재시드 후 낡은 좌표가 재사용되지 않는다.
    store_label_memo: dict[str, tuple[float, float]] | None = None,
) -> bytes | None:
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None

    building = session.get(Building, building_id)
    if building is None:
        return None

    # 좌표 변환과 타일 경계 — 무엇을 그릴지 고르는 기준.
    transform = fit_building_geo_transform(session, building_id)
    bounds = tile_bounds(z, x, y)

    stores = session.scalars(select(Store).where(Store.floor_id == floor.id)).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()

    layers = build_floor_tile_layers(
        building,
        stores=stores,
        pois=pois,
        transform=transform,
        bounds=bounds,
        footprint_local_m=floor.footprint_local_m,
        non_walkable_local_m=floor.non_walkable_polygons_local_m,
        store_label_memo=store_label_memo,
    )

    return mapbox_vector_tile.encode(
        layers,
        default_options={
            "quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north),
        },
    )


# 층 지도를 MVT 바이트로 렌더링한다(캐시 경유). 건물/층이 없으면 None.
def render_floor_tile(
    session: Session,
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
) -> bytes | None:
    _invalidate_if_reseeded(session)

    revision = _cache_revision(session)
    cache_key = (building_id, floor_name, z, x, y, revision)
    label_memo = _label_memo_for(revision)
    return _TILE_CACHE.get_or_render(
        cache_key,
        lambda: _render_tile_bytes(session, building_id, floor_name, z, x, y, store_label_memo=label_memo),
    )


# 캐시 메트릭(hit/miss/coalesced/eviction/current_bytes 등). 관측·07번 배선용.
def tile_cache_metrics() -> dict[str, int]:
    return _TILE_CACHE.metrics()


# 워밍업 진행 상태 — 준비(readiness)와 분리한다.
#
# 워밍업은 성능 최적화(첫 요청 소켓 폭주 제거)일 뿐, 실패해도 서비스는 lazy
# 캐시로 정상 동작한다. 따라서 워밍 실패를 readiness 실패로 오인하면 안 된다.
# 06번은 상태 조회 함수만 노출하고, /health readiness 배선은 07번이 이 값을
# 어떻게 쓸지(예: "실패여도 ready") 결정한다.
#   idle    — 아직 시작 안 함
#   running — 워밍 스레드가 도는 중
#   done    — 정상 완료
#   failed  — 예외로 중단(서비스는 계속 lazy 폴백)
_WARM_STATUS = "idle"
_WARM_STATUS_LOCK = threading.Lock()


def _set_warm_status(status: str) -> None:
    global _WARM_STATUS
    with _WARM_STATUS_LOCK:
        _WARM_STATUS = status


# 현재 워밍업 상태 문자열. readiness와 독립적으로 조회된다(07번 배선용).
def tile_cache_warm_status() -> str:
    with _WARM_STATUS_LOCK:
        return _WARM_STATUS


# 클라이언트가 실내 MVT 소스를 등록하는 zoom 범위 전체.
#
# 클라이언트(client/lib/screens/outdoor_map/entry/indoor_entry_zoom.dart)의
# indoorTilesMinZoom=15 / indoorTilesMaxZoom=18과 맞춰야 한다. 여기가 좁으면
# 덮지 못한 zoom의 타일만 캐시를 못 타서 요청마다 새로 5개 쿼리를 낸다.
#
# z=15가 필요한 이유는 실내 이탈 임계값이 카메라 zoom 15.6이기 때문이다.
# MapLibre가 요청하는 타일 z는 카메라 zoom의 내림이라 15.6에서는 z=15를
# 부른다. 예전에는 이 목록이 (16, 17, 18)이라 야외에서 실내로 진입·이탈하는
# 구간의 타일이 전부 워밍업 밖이었다.
_WARM_ZOOMS: tuple[int, ...] = (15, 16, 17, 18)
# 화면이 건물 중심을 벗어나 있어도 인접 타일까지 커버되도록 bbox 밖으로 몇 장
# 더 확장해 warmup한다. 1이면 8방향 인접, 2면 24방향. 실측 사용 패턴이 대체로
# 건물 중심 근처라 1로 충분하다.
_WARM_TILE_PADDING = 1


def _lnglat_to_tile(lng: float, lat: float, z: int) -> tuple[int, int]:
    n = 2**z
    x = int((lng + 180.0) / 360.0 * n)
    lat_rad = math.radians(max(min(lat, 85.05112878), -85.05112878))
    y = int((1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


# 이 건물에서 워밍업할 층을 고른다. 기본은 전 층이다.
#
# 예전 기본은 앱이 처음 여는 층(지상 1층) 하나였다 — 층 하나 워밍에 1초대가
# 걸리던 시절의 절충이다. 라벨 계산 병목 제거(볼록 4각형 조기 탈출 + 라벨
# memo) 후에는 전 층 워밍이 수 초·1MB 미만이라 절충할 이유가 없어졌다
# (수치 근거는 config.tile_warm_default_floor_only 주석). 층 전환 첫 방문의
# 타일 격자 병렬 요청도 전부 캐시 히트가 된다. 기본 층만 워밍하려면
# NAV_TILE_WARM_DEFAULT_FLOOR_ONLY=1로 조인다.
def _floors_to_warm(floors: list[Floor]) -> list[Floor]:
    if not settings.tile_warm_default_floor_only:
        return floors
    default_name = _default_floor(floors)
    if default_name is None:
        return floors
    selected = [floor for floor in floors if floor.name == default_name]
    return selected or floors


def _warm_tile_cache(session_factory) -> None:
    """워밍 대상 (건물, 층, z, x, y) 조합의 MVT 바이트를 미리 생성해 캐시에 채운다.

    클라이언트가 층을 전환하면 MapLibre가 격자 여러 개를 병렬 요청하는데,
    첫 방문 때는 각 인코딩이 CPU 바운드라 uvicorn 단일 워커에서 직렬 처리되며
    수 초씩 걸린다. 그 사이 클라이언트 쪽에서 소켓이 취소·재사용되며 "Socket
    closed"가 튀고 몇몇 타일이 로드되지 않는다. 기동 직후에 여기서 미리 인코딩
    해두면 사용자 첫 요청부터 캐시 히트라 즉시 반환된다.

    대상 층은 _floors_to_warm이 고른다(기본: 앱이 처음 여는 층만).
    """
    _set_warm_status("running")
    session = session_factory()
    try:
        buildings = session.scalars(select(Building)).all()
        for building in buildings:
            transform = fit_building_geo_transform(session, building.id)
            footprint = building.footprint_local_m or []
            if not footprint:
                continue
            # local_m → WGS84 로 변환한 bbox를 구해, 이를 덮는 web mercator 타일 범위 계산.
            wgs = [transform.apply(p["x"], p["y"]) for p in footprint]
            lats = [lat for lat, _ in wgs]
            lngs = [lng for _, lng in wgs]
            min_lat, max_lat = min(lats), max(lats)
            min_lng, max_lng = min(lngs), max(lngs)
            all_floors = session.scalars(select(Floor).where(Floor.building_id == building.id)).all()
            floors = _floors_to_warm(list(all_floors))
            for z in _WARM_ZOOMS:
                x0, y_north = _lnglat_to_tile(min_lng, max_lat, z)
                x1, y_south = _lnglat_to_tile(max_lng, min_lat, z)
                for x in range(x0 - _WARM_TILE_PADDING, x1 + _WARM_TILE_PADDING + 1):
                    for y in range(y_north - _WARM_TILE_PADDING, y_south + _WARM_TILE_PADDING + 1):
                        if x < 0 or y < 0 or x >= 2**z or y >= 2**z:
                            continue
                        for floor in floors:
                            render_floor_tile(session, building.id, floor.name, z, x, y)
        logger.info("[tile-warmup] MVT 캐시 준비 완료: %d개 항목", tile_cache_metrics()["entries"])
        _set_warm_status("done")
    except Exception as error:  # pragma: no cover — 워밍 실패는 조용히 degrade
        logger.warning("[tile-warmup] 실패(무시하고 lazy 캐시로 폴백): %s", error)
        _set_warm_status("failed")
    finally:
        session.close()


def warm_tile_cache_in_background(session_factory) -> threading.Thread:
    """MVT 캐시 워밍을 데몬 스레드로 미리 돌린다.

    daemon=True — 워밍이 남아 있어도 서버 종료를 막지 않는다. 워밍 중 사용자
    요청이 들어와도 같은 키는 single-flight로 한 번만 인코딩되고(BoundedTileCache),
    값이 결정적이라 어떤 스레드가 인코딩하든 같은 bytes다 —
    같은 (building, floor, z, x, y, revision)에 대해 결과가 동일하다.
    """
    thread = threading.Thread(
        target=_warm_tile_cache,
        args=(session_factory,),
        name="mvt-tile-warmup",
        daemon=True,
    )
    thread.start()
    return thread
