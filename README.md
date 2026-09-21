# BIKE LOOP

방치된 자전거를 **신고 → 검토 → 최적 수거경로 생성 → 수거 → 재고관리 → 통계**까지
한 흐름으로 처리하는 앱입니다. 전국(대한민국) 서비스.

> **LOOP의 두 가지 뜻**
> ① 차량이 보관소를 출발해 여러 지점을 돌고 돌아오는 **순환 경로**
> ② 버려질 자전거가 수리·기부를 거쳐 다시 쓰이는 **자원의 순환**

---

## 무엇을 해결하나

| 기존 방식의 문제 | BIKE LOOP |
|---|---|
| 신고 위치가 "○○학교 근처"처럼 모호 | 지도 좌표 + 주소로 정확히 접수 |
| 같은 자전거를 여러 명이 신고 | 30m 반경 자동 중복 확인 (PostGIS) |
| 신고 순서대로 수거 → 같은 길 왕복 | OR-Tools로 최적 방문 순서 계산 |
| 창고 재고가 장부 없이 방치 | 관리번호 자동 부여 + 상태 추적 |
| 성과를 숫자로 못 보여줌 | 재생률·이동거리 대시보드 |

---

## 구조

```
[Flutter 앱]  ──  [Supabase]              (데이터 · 사진 · 로그인 · 권한)
      │           PostgreSQL + PostGIS
      │           + Auth + Storage + RLS
      │
      ├────────  [FastAPI on Cloud Run]   (최적 경로 계산만 담당)
      │           Python + Google OR-Tools
      │
      └────────  [카카오]                  (지도 · 주소 · 도로 경로)
```

**원칙: CRUD에는 서버를 두지 않는다.** 저장·조회는 앱이 Supabase와 직접 통신하고,
권한은 RLS로 DB에서 강제합니다. 서버는 파이썬이 꼭 필요한 경로 최적화 하나만 담당합니다.

---

## 폴더

```
app/                Flutter 앱
  lib/const/        모델 · 상수(regions.dart = 시도 17곳 보관소)
  lib/service/      auth · report · admin · location · settings
  lib/ui/route|tab/ 화면
server/             FastAPI (/optimize · /address · /search)
  engine.py         핫스팟 클러스터링 + 긴급도 + CVRP
supabase/           스키마 · RLS · RPC · 마이그레이션 SQL (01~06 순서로 적용)
analysis-server/    NYC 311 데이터로 방법론 검증한 PoC
docs/               대회용 설명서(HTML)
blueprint.txt       ★ 단일 진실 원천 — 기능 목록 · 설계 결정 · 작업 로그
```

---

## 핵심 로직

- **경로 최적화** — Google OR-Tools CVRP. 적재량·작업시간·출발/복귀·필수방문 지점을 제약으로 반영
- **클러스터링** — 30m 내 자전거는 한 덩어리로 묶어 한 번만 정차
- **긴급도** — 방치 기간에 따라 Critical(90일+) / High(60일+) / Medium(30일+) / Normal
- **중복 탐색** — PostGIS `ST_DWithin`으로 실제 지상거리 30m 판정
- **관리번호** — `{시도}_{시군구}_{YYYYMMDD}_{순번}` DB 트리거 자동 채번
- **지역 검증** — 출발지와 수거 대상의 시도가 다르면 경로 생성 전 경고·정정

---

## 실행

### 1. 데이터베이스
Supabase 프로젝트 생성 후 SQL Editor에서 `supabase/` 안의 파일을 **01 → 06 순서**로 실행합니다.

### 2. 서버 (선택 — 이미 Cloud Run에 배포되어 있음)
```bash
cd server
pip install -r requirements.txt
cp .env.example .env      # 카카오 REST 키 입력
uvicorn main:app --reload
```

### 3. 앱
```bash
cd app
flutter pub get
flutter run                       # 개발
flutter build apk --release       # 안드로이드 배포본
```

`app/lib/const/value/constants.dart`에서 Supabase URL·키, 카카오 JS 키, 서버 주소를 설정합니다.

> **관리자 지정**은 SQL로:
> `update profiles set role='admin' where id='<uuid>';`

---

## 키 관리 원칙

이 저장소는 공개되어 있습니다. **코드에 보이는 키는 모두 "공개돼도 되는 키"** 이며,
실제로 위험한 키는 저장소에 없습니다(커밋 이력에도 없습니다).

| 키 | 위치 | 왜 공개돼도 되나 |
|---|---|---|
| Supabase publishable(anon) | 앱 코드 | 권한은 RLS가 DB에서 강제. 이 키만으로는 남의 데이터를 못 읽음 |
| 카카오 **JS** 키 | 앱 코드 | 등록된 플랫폼(패키지명·키해시)에서만 동작 |
| 카카오 **REST** 키 | **서버 `.env`만** | 유출 시 과금 위험 — 저장소에 없음 |
| Supabase `service_role` | **사용 안 함** | 필요 없도록 설계 |

`.gitignore`가 `.env` 계열을 차단합니다. **`server/.env`를 강제로 커밋하지 마세요.**

### 서버는 인증이 필요합니다

최적화 서버(`/optimize` `/address` `/search`)는 **로그인한 앱 사용자만** 호출할 수 있습니다.
앱이 보낸 Supabase 액세스 토큰을 서버가 검증하고(`server/auth.py`),
사용자별로 분당 호출 횟수도 제한합니다. 토큰 없이 부르면 401이 돌아옵니다.

```bash
curl "https://<서버주소>/search?q=jeju"
# {"detail":"로그인이 필요합니다 (missing token)"}
```

이 구조 덕분에 서버 주소가 공개되어도 카카오 API 할당량이 소모되지 않습니다.

### 직접 돌려보려면

이 저장소를 그대로 받아도 **제 Supabase/서버에는 붙지 않습니다**(권한이 막혀 있습니다).
본인 환경에서 실행하려면 Supabase 프로젝트를 만들고 `supabase/01~07` SQL을 적용한 뒤,
`app/lib/const/value/constants.dart`의 주소와 키를 본인 것으로 바꾸면 됩니다.

---

## 검증

앱을 만들기 전 **뉴욕시 311 방치 자전거 신고 2,930건**(2020–2021)으로 방법론을 먼저 검증했습니다.

- 핫스팟 분석(KDE + Getis-Ord Gi*) — 브롱크스 Port Morris가 최상위 (z = 4.04)
- CVRP — 트럭 3대로 180대 수거 시 총 82.1km
- 월별 계절성 확인 (졸업·이사 시즌 가설과 일치)

여기서 얻은 교훈(용량 초과 시 방문 분할, 미수거분 이월)을 운영 코드에 반영했습니다.
자세한 내용은 `analysis-server/poc_nyc311/RESULTS.md`.

---

## 현재 상태

MVP 10단계 전부 구현·실기기 검증 완료. 전국 확장 적용(2026-08).

**다음 단계** — 다중 차량 지원 · 실제 도로거리 기반 계산 · 완료 사진 ·
핫스팟 예측 모델 · 지자체별 관리자 계정 분리

---

## 만든 사람

한정규 · 최적화 로직 자문 이강혁

## 라이선스

MIT — 자세한 내용은 [LICENSE](LICENSE) 참고.
브랜드 요소(BIKE LOOP 이름·로고)와 운영 데이터는 라이선스 대상이 아닙니다.
