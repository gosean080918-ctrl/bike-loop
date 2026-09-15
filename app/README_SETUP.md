# BikeReclaim 앱 — 셋업 가이드 (Supabase판, 2026-07-15)

현재 코드 = 기획안 확정판 반영: Supabase 직결 + 카카오맵.
백엔드(Supabase 프로젝트 bikereclaim1)는 이미 적용 완료 상태다 (../supabase/README.md).

## 1. Flutter 프로젝트 생성 (플랫폼 폴더)

```bash
cd BikeReclaim/app
flutter create --org com.bikereclaim --project-name bike_reclaim .
flutter pub get
```

## 2. 키 입력 — `lib/const/value/constants.dart`

- `kSupabaseUrl` — 입력 완료 (https://xpkifseyiphyvoppcsui.supabase.co)
- `kSupabaseAnonKey` — Supabase 대시보드 ⚙Settings → API Keys 의
  anon public 키(`eyJ...`) 또는 Publishable 키(`sb_publishable_...`)
- `kKakaoJsKey` — 카카오디벨로퍼스 JavaScript 키
  (developers.kakao.com → 앱 생성 → 플랫폼에 Android 패키지명/iOS 번들ID 등록)

## 3. 플랫폼 권한

**android/app/src/main/AndroidManifest.xml** (`<manifest>` 안):
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.CAMERA" />
```
`<application>`에 `android:usesCleartextTraffic="true"` 추가 (kakao_map_plugin).
minSdkVersion 21+ 확인.

**ios/Runner/Info.plist**:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>방치 자전거 위치를 기록하기 위해 위치 권한이 필요합니다.</string>
<key>NSCameraUsageDescription</key>
<string>방치 자전거 사진 촬영을 위해 카메라 권한이 필요합니다.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>사진 선택을 위해 갤러리 접근 권한이 필요합니다.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key><true/>
  <key>NSAllowsArbitraryLoadsInWebContent</key><true/>
</dict>
<key>io.flutter.embedded_views_preview</key><true/>
```

## 4. 실행

```bash
flutter run
```

## 이메일 확인 설정 (개발 편의)

Supabase 기본값은 회원가입 시 이메일 확인 요구. 개발 중엔 꺼두면 편하다:
대시보드 → Authentication → Sign In / Up → Email → "Confirm email" 끄기.

## 관리자 계정 만들기

앱에서 회원가입 후, SQL Editor에서:
```sql
update public.profiles set role = 'admin'
where id = (select id from auth.users where email = '관리자이메일');
```

## 구현 범위 (일반 유저 = 기획안 4.1 전부)

| 기능 | 상태 |
|------|------|
| AUTH-01/02 스플래시·로그인/가입 | 구현 |
| RPT-01 사진 촬영/업로드 | 구현 |
| RPT-02 GPS 자동 + 지도에서 위치 조정 | 구현 (중앙핀 방식) |
| RPT-03 상태 5종 선택 + 설명 | 구현 |
| RPT-04 제출 (+30m 중복 확인 다이얼로그) | 구현 |
| RPT-05 지도 분포 (클러스터) | 구현 |
| RPT-06 내 신고 이력/상태 | 구현 |
| 관리자 기능 (ADM-*) | 미구현 — 단계3 |

빌드 미검증 상태. 에러 나면 메시지를 Claude에게 전달할 것.
