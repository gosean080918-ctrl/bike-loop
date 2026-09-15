# BikeReclaim 최적화 서버 (BE-03)

파일 5개짜리 초미니 FastAPI. 엔드포인트는 `POST /optimize` 하나
(+ `GET /health`). OR-Tools CVRP — PoC(analysis-server/poc_nyc311) 이식판.

## 로컬 실행

```bash
cd server
pip install -r requirements.txt
uvicorn main:app --reload
# http://127.0.0.1:8000/docs 에서 스웨거 UI로 바로 테스트 가능
```

테스트: `python test_optimize.py` (3개 시나리오, 통과 확인됨 2026-07-17)

## 요청 예시

```json
POST /optimize
{
  "depot": {"lat": 33.306, "lng": 126.286},
  "vehicle_count": 1,
  "vehicle_capacity": 20,
  "work_minutes": 240,
  "service_minutes": 5,
  "stops": [
    {"report_id": "uuid-1", "lat": 33.31, "lng": 126.29, "demand": 1,
     "priority": 2, "required": false}
  ]
}
```

응답: 차량별 방문 순서(seq)·ETA·적재량, 이월된 지점(dropped_report_ids),
총 거리/시간. 앱(관리자 화면)은 이 결과를 collection_jobs / job_stops에 저장.

## 지원 제약 (기획안 5장)

차량 수/적재량, 작업 가능 시간, 지점별 작업시간, 우선순위(이월 방지 가중),
필수 수거 지점(required), 출발지/복귀지 분리. 대형 지점 방문 분할과
용량 초과분 이월은 자동 처리(PoC 교훈).

## 배포 (Cloud Run 예시)

```bash
gcloud run deploy bikereclaim-optimizer --source . --region asia-northeast3 \
  --allow-unauthenticated
```

Railway/Fly는 Dockerfile 자동 인식. 비밀키 없음(현재 버전은 키가 필요 없다 —
BE-05에서 카카오 길찾기 행렬 붙일 때만 KAKAO_REST_KEY 환경변수 추가).

## 한계 / 다음 단계

- 거리·시간이 하버사인 직선 근사 → BE-05에서 카카오 자동차 길찾기 행렬로 교체
- 인증 없음(MVP) → 배포 후엔 앱에서만 아는 간단한 토큰 헤더 추가 권장
