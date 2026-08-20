"""Studio 간선 입력 보완 로직 및 매장 적재(add_dataset) 단위 테스트."""

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

import app.models  # noqa: F401  # 모든 모델을 Base.metadata에 등록
from app.models.base import Base
from app.models.building import Floor
from app.models.place import Store
from scripts.seed.seed_navigation import add_dataset, edge_geometry_and_length


# 간선 경로선이 생략되면 양 끝 노드 좌표로 보완하는지 검증한다.
def test_간선_경로선이_없으면_노드_좌표로_보완한다():
    geometry, length_m = edge_geometry_and_length(
        {"id": "AB", "from": "A", "to": "B"},
        {
            "A": {"x": 0.0, "y": 0.0},
            "B": {"x": 3.0, "y": 4.0},
        },
    )

    assert length_m == pytest.approx(5.0)
    assert geometry == [
        {"x": 0.0, "y": 0.0},
        {"x": 3.0, "y": 4.0},
    ]


# 간선 거리가 생략되면 경로선의 구간별 길이 합을 계산하는지 검증한다.
def test_간선_거리가_없으면_경로선_전체_길이를_계산한다():
    _, length_m = edge_geometry_and_length(
        {
            "id": "AB",
            "from": "A",
            "to": "B",
            "geometry_local_m": [
                {"x": 0.0, "y": 0.0},
                {"x": 3.0, "y": 4.0},
                {"x": 6.0, "y": 4.0},
            ],
        },
        {},
    )

    assert length_m == pytest.approx(8.0)


# --- add_dataset의 search_facets 배선 검증 ---
# 값 계산(파생·오버레이)은 다루지 않는다. seed dict에 실려 온 값을
# 컬럼에 그대로 옮기는 배선만 검증한다.


@pytest.fixture
def db_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


def _minimal_dataset(stores: list[dict], floor: dict | None = None) -> dict:
    return {
        "building": {
            "id": "test-building",
            "name": "테스트 빌딩",
            "floor": floor or {"id": "FL-1F", "name": "1F", "level": 1},
        },
        "nodes": [],
        "edges": [],
        "stores": stores,
        "pois": [],
    }


def _base_store(store_id: str, **overrides: object) -> dict:
    store = {
        "id": store_id,
        "name": f"매장-{store_id}",
        "category": "패션",
        "subcategory": "캐주얼·스트리트",
        "centroid": {"local_m": {"x": 1.0, "y": 2.0}},
    }
    store.update(overrides)
    return store


# search_facets가 있는 store dict를 시드하면 컬럼에 그대로 저장되는지 검증한다.
def test_search_facets가_있으면_컬럼에_그대로_저장된다(db_session):
    facets = {"styles": ["캐주얼"]}
    add_dataset(
        db_session,
        _minimal_dataset([_base_store("PO-1", search_facets=facets)]),
    )
    db_session.flush()

    store = db_session.scalars(select(Store).where(Store.id == "PO-1")).one()

    assert store.search_facets == facets


# search_facets 키가 없는 store dict는 컬럼이 None으로 저장되는지 검증한다.
def test_search_facets_키가_없으면_None이다(db_session):
    add_dataset(db_session, _minimal_dataset([_base_store("PO-2")]))
    db_session.flush()

    store = db_session.scalars(select(Store).where(Store.id == "PO-2")).one()

    assert store.search_facets is None


# search_facets 배선을 추가해도 기존 필드(카테고리·좌표 등) 적재가 그대로인지 검증한다.
def test_기존_필드_적재는_그대로다(db_session):
    add_dataset(
        db_session,
        _minimal_dataset(
            [
                _base_store(
                    "PO-3",
                    name="나이키 라이즈",
                    category="패션",
                    subcategory="캐주얼·스트리트",
                    entrance_local_m={"x": 3.0, "y": 4.0},
                    entrance_node_id=None,
                    polygon_local_m=[{"x": 0.0, "y": 0.0}],
                )
            ]
        ),
    )
    db_session.flush()

    store = db_session.scalars(select(Store).where(Store.id == "PO-3")).one()

    assert store.name == "나이키 라이즈"
    assert store.category == "패션"
    assert store.subcategory == "캐주얼·스트리트"
    assert store.centroid_x_m == 1.0
    assert store.centroid_y_m == 2.0
    assert store.entrance_x_m == 3.0
    assert store.entrance_y_m == 4.0
    assert store.polygon == [{"x": 0.0, "y": 0.0}]


# --- Floor.non_walkable_polygons_local_m 배선 검증 ---
# 못 걷는 면은 순수 표시용이라 길찾기와 무관하다. seed dict의 값이 컬럼까지
# 그대로 흐르는지만 본다.


def test_못_걷는_면이_있으면_층_컬럼에_그대로_저장된다(db_session):
    shapes = [{"id": "OB-1", "kind": "void", "polygon_local_m": [{"x": 0.0, "y": 0.0}]}]
    add_dataset(
        db_session,
        _minimal_dataset(
            [],
            floor={"id": "FL-1F", "name": "1F", "level": 1, "non_walkable_polygons_local_m": shapes},
        ),
    )
    db_session.flush()

    floor = db_session.scalars(select(Floor).where(Floor.id == "FL-1F")).one()

    assert floor.non_walkable_polygons_local_m == shapes


# B2처럼 못 걷는 면이 0개인 층이 실제로 있다. 컬럼이 None이어도 시드가 통과해야 한다.
def test_못_걷는_면_키가_없으면_None이다(db_session):
    add_dataset(db_session, _minimal_dataset([]))
    db_session.flush()

    floor = db_session.scalars(select(Floor).where(Floor.id == "FL-1F")).one()

    assert floor.non_walkable_polygons_local_m is None
