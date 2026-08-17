# calibration

건물별 좌표 정합 입력 데이터. 이 폴더의 파일은 소스 오브 트루스가 아니라
"어떻게 정합을 뽑았는지"를 재현할 수 있게 남겨둔 원본 관측치다. 여기 값을 바꾸고
재정합 스크립트를 다시 돌리면 studio JSON의 `local_m_to_wgs84` 아핀이 갱신된다.

## 지금 있는 것

- `thehyundai-seoul-gcps.json` — 더현대 서울 GCP 4점(건물 북/서/남/동 꼭지점).
  VWorld data API `LT_C_SPBD`(파크원, `bd_mgt_sn` 1156011000100220000000002) 폴리곤의 극점.

**정렬 기준은 "지금 배경으로 깔리는 타일"이다.** 클라이언트는 `VWORLD_API_KEY`가 있으면
VWorld Base를, 없으면 OSM으로 폴백한다(`outdoor_map_screen.dart`). 두 좌표계는 더현대에서
코너마다 2~5 m 다르고, 그 차이가 그대로 "실내 도면 외곽선이 배경 건물과 어긋남"으로 보인다.
2026-08-17에 OSM(way 874639191) → VWorld로 갈아 끼운 이유가 이것이다.

## GCP 다시 뽑는 법

1. 건물 외곽 꼭지점의 lat/lng를 확보한다. 극점 4~6점(방위 N/W/S/E 또는 순서 1, 2, 3, ...)을 잡는다.
   - **기본: VWorld data API의 건물 폴리곤**을 받아 극점을 뽑는다. `data=LT_C_SPBD`,
     `geomFilter=POINT(경도 위도)`, `crs=EPSG:4326`, `geometry=true`.
   - OSM 타일로 배포한다면(`VWORLD_API_KEY` 미설정) 대신 OSM에서 대상 건물 way를 찾아
     (Overpass 등) 극점 좌표를 뽑는다.

2. 이 폴더 JSON 형식(`gcps[]`의 `label`/`compass`/`outdoor.lat`·`lng`)에 맞춰 값을 채워 덮어쓴다.

3. 재정합 실행 (dry-run):
   ```
   cd backend
   python -m scripts.transform.refit_building_wgs84 \
       --studio resources/studio/thehyundai-seoul-dabeeo \
       --gcps resources/calibration/thehyundai-seoul-gcps.json
   ```
   잔차와 새 아핀을 출력한다. 자동 매칭이 이상하면 `--map "N=1,W=2,S=3,E=4"`처럼 명시.

4. 결과 만족스러우면 `--write`로 studio JSON들의 아핀을 덮어쓰기.

5. **DB에 반영한다** — `python -m scripts.seed.reset_and_seed`. 배포 백엔드에 태우려면
   그 뒤 Cloud Run 재배포까지 해야 폰에서 보인다([GCP 배포](../../../docs/guide/gcp-instance.md)).
   클라이언트는 고칠 것이 없다(진입 판정도 이 외곽선을 그대로 본다 —
   [실내 진입·이탈 규칙](../../../docs/client/indoor-entry-rules.md) 1절).
