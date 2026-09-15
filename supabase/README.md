# Supabase 설정 가이드 (단계2 — BE-01/02/04)

SQL 3개 파일이 백엔드의 전부다 (경로 최적화 `/optimize` 서버 제외).
구문 검증 완료(PostgreSQL 16 파서, 50 statements).

## 적용 순서

1. https://supabase.com → 새 프로젝트 생성 (리전: Northeast Asia 권장)
2. **Storage → New bucket**: 이름 `report-photos`, Public 체크 해제
3. **SQL Editor**에서 순서대로 실행:
   - `01_schema.sql` — PostGIS + 테이블 5개 + 트리거
   - `02_rls.sql` — RLS 정책 + Storage 정책
   - `03_functions.sql` — 중복탐색 RPC + 지도범위 RPC + 통계 뷰 3개
4. 관리자 계정 지정 (앱에서 회원가입 후, SQL Editor에서):
   ```sql
   update public.profiles set role = 'admin' where id = '<해당 유저 uuid>';
   ```

## 앱에서 쓰는 키 (Settings → API)

- `Project URL` + `anon public` 키 → Flutter에 넣는다 (RLS가 지키므로 안전)
- `service_role` 키는 **절대 앱에 넣지 않는다**

## 권한 설계 요약

| 동작 | 일반(user) | 관리자(admin) |
|------|-----------|---------------|
| 신고 조회(지도) | O | O |
| 신고 생성 | 본인 명의, submitted만 | O |
| 신고 상태 변경(승인/반려/중복/배정) | X | O |
| 수거 작업/방문순서/재고 | X | O |
| 사진 업로드 | 본인 폴더(`{uid}/...`)만 | 동일 |
| 프로필 role 변경 | X (컬럼 권한 차단) | X — service_role만 |

## 앱 호출 예시 (supabase_flutter)

```dart
// 신고 제출
await supabase.from('reports').insert({
  'reporter_id': supabase.auth.currentUser!.id,
  'photo_url': url, 'lat': lat, 'lng': lng,
  'condition': 'long_term', 'description': desc,
});

// 제출 전 중복 확인 (30m 반경)
final dup = await supabase.rpc('find_nearby_reports',
    params: {'p_lat': lat, 'p_lng': lng, 'p_radius_m': 30});

// 지도 범위 조회
final list = await supabase.rpc('reports_in_bounds', params: {
  'p_min_lat': sw.lat, 'p_min_lng': sw.lng,
  'p_max_lat': ne.lat, 'p_max_lng': ne.lng});

// 대시보드
final stats = await supabase.from('v_stats_daily').select().limit(30);
```

## condition / state 코드 ↔ 한글 라벨

- condition: long_term=장기방치의심, damaged=파손, obstruction=통행방해,
  parts_missing=부품분실, other=기타
- bikes.state: storage=보관, repair=수리, donation=기부, reuse=재사용, disposal=폐기
