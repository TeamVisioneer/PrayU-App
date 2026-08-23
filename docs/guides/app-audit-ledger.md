# PrayU-App 결함 대장 (코드 감사)

> 상태: **확정** (2026-08-19, web 연동 교차검증 완료) · 계속 갱신하는 대장(guides/)
> 배경: 기존 셸 코드는 과거 주먹구구 작성분이라 "있는 그대로 신뢰하지 않고 동작·목적 적합성부터 검증"한다.
> 이 문서는 **소스 직접 정독** 결과다(서브에이전트 요약 아님). 감사 대상: `lib/**`(main.dart 562 / image_download_service 278 / network_error_view 59), 네이티브(MainActivity.kt, AppDelegate.swift, NotificationService.swift), 설정(AndroidManifest, Info.plist, build.gradle, pubspec, scripts/*.sh).

## 심각도 범례
- **HIGH**: 실제 사용자/운영 흐름을 깨거나 보안·배포 사고로 이어짐
- **MED**: 특정 조건에서 오작동/리스크, 또는 앱심사·유지보수 위험
- **LOW**: 정합성·정리·잠재 버그(현재는 무해에 가까움)

## 동작 검증 요약 (의도대로 도는가)
| 기능 | 판정 | 비고 |
|---|---|---|
| 카카오 로그인 앱 전환 | ❌ 현재 불가 | W1·W2 (WebView가 카카오 스킴/새 창 미처리) |
| 딥링크·푸시 라우팅 | ⚠️ 취약 | 경로는 배선됨(web 수신 `AppInit.tsx:19`) — App측 W3(JS 주입)·W4(host 유실)가 리스크 |
| staging/prod 환경 분리 | ❌ 미배선 | E1 (`.env` 수동 토글로만 결정) |
| 이미지 저장 핸들러 | ✅ 대체로 견고 | 배치+권한 처리 있음(저위험) |
| 인스타 공유 | ⚠️ 조건부 | FACEBOOK_APP_ID가 env flavor(E1)에 얽힘 |
| OneSignal 로그인 태깅 | ✅ 동작 | userId만 사용, escaping 무관 |

---

## 브리지·기능 전수 인벤토리 (앱이 지금 하는 일)

앱 = web WebView 셸 + 네이티브 브리지. 현재 역할 전수(놓친 것 없이):

| # | 역할 | 트리거 / 위치 | 판정 |
|---|---|---|---|
| 1 | 웹뷰 셸 로딩(baseUrl, `Accept-Language: ko-KR`) | main.dart:187-190 | ✅ |
| 2 | **앱 감지 UA 주입** (`PrayU App` + `prayu-ios/android`) | main.dart:204, 223-227 | ⚠️ B1 (isApp OK, isIOS/android 레이스) |
| 3 | `onLogin` → OneSignal 유저 연결·구독·태깅 | JS handler:245 | ✅ |
| 4 | 푸시 init·권한요청·resume clearAll·클릭 라우팅 | :60-70, 152-157, 552-561 | ✅ (라우팅은 W3 취약) |
| 5 | iOS 리치푸시 확장(이미지/버튼) | ios NotificationService.swift | ✅ 표준 보일러플레이트 |
| 6 | iOS Live Activities `setupDefault()` | :70 | ❌ **죽은 코드** — web에 Live Activity 사용 0건(교차검증) → D1 |
| 7 | 딥링크·App Links 라우팅(`prayu://`, `*.prayu.site`) | :73-123 | ⚠️ W4 |
| 8 | `requestAppReview` 인앱 리뷰 | JS handler:265 | ⚠️ S2 |
| 9 | `triggerHapticFeedback` 햅틱 | JS handler:285 | ✅ |
| 10 | `shareInstagramStory` 인스타 스토리 공유(FB SDK) | JS handler:306 | ⚠️ S1 |
| 11 | `downloadImages` 갤러리 저장(단일/다중) | JS handler:356 | ✅ 저위험 |
| 12 | `openAppSettings` 설정 앱 열기 | JS handler:451 | ✅ |
| 13 | `getAppVersion` 앱 버전 정보 | JS handler:472 | ❌ **죽은 브리지** — web 미호출(주석만) → D1 |
| 14 | 뒤로가기 처리(PopScope → webview goBack / 앱 종료) | :161-169 | ✅ |
| 15 | 네트워크 에러 뷰 + 재시도 | :208-220, network_error_view.dart | ⚠️ W5 |
| 16 | `intent:` 스킴 네이티브 처리 | :523, MainActivity.kt | ⚠️ W2/N1 (Android 전용) |
| 17 | 상태바/시스템 UI 모드 · 스플래시 | :131-135, flutter_native_splash | ⚠️ N5 |
| 18 | Facebook SDK 초기화(인스타 공유 attribution용) | AppDelegate.swift, build.gradle, Info.plist | ✅ (S1과 연동) |

> **추가로 역할 하는 것 없음**을 이 전수로 확정. FB SDK(18)는 로그인용이 아니라 **인스타 공유 attribution** 목적으로만 존재(코드상 FB 로그인 호출 없음).

---

## 결함 목록

### WebView / 네비게이션 (핵심 — 카카오 앱전환 토대와 동일)
| ID | 심각 | 파일:라인 | 현상 / 의도대로? | 리팩터 방향 |
|---|---|---|---|---|
| W1 | HIGH | main.dart:196 (설정) / 핸들러 없음 | `supportMultipleWindows:true`인데 **`onCreateWindow` 미구현** → 새 창/팝업(`target=_blank`·`window.open`) 유실. 새 창 컨텍스트에선 `shouldOverrideUrlLoading`도 안 걸림. 사용자 보고 "새 창으로 뜸"의 원인 | `onCreateWindow`(+`onCloseWindow`) 구현: 새 창 첫 URL을 스킴이면 앱 오픈, http면 메인 컨트롤러로 흡수 |
| W2 | HIGH | main.dart:518-539 / AppDelegate.swift:1-20 / MainActivity.kt | `shouldOverrideUrlLoading`이 **`intent:` 스킴만** 처리. 카카오 스킴(`kakaokompassauth` 등)·`tel`·`mailto` 미처리. **iOS는 네이티브 스킴 경로 전무**(AppDelegate 비어있음, `handleIntent`는 Android 전용) | 외부 스킴 라우팅을 `url_launcher`로 **양 플랫폼 통일**, 스킴 화이트리스트 분기 |
| W3 | HIGH | main.dart:541-550 | `_performWebViewNavigation`이 URL을 **이스케이프 없이** `evaluateJavascript` 문자열에 삽입. `'`·개행 포함 URL이면 깨지고 주입 위험. 딥링크/푸시 복귀가 전부 이 경로 | `callAsyncJavaScript`(args 전달) 또는 `jsonEncode(url)`로 안전화 |
| W4 | MED | main.dart:103-114 | `_handleDeepLink`가 `prayu://` → `baseUrl + uri.path`로 만들며 **host 세그먼트 유실**(`prayu://group/123`→`baseUrl/123`). 실제 딥링크 포맷 의존 | 링크 포맷 확정 후 host+path 온전 조합, 케이스 테스트 |
| W5 | MED | main.dart:208-220 | `onReceivedError`에 **`isForMainFrame` 확인 없음** → 서브리소스(차단된 애널리틱스·이미지) 실패로 전체 네트워크에러 화면 전환 가능 | 메인 프레임 실패에만 에러뷰; 서브리소스 무시 |
| W6 | LOW | main.dart:521 | `navigationAction.request.url!` 강제 언랩 → null이면 크래시 | null 가드 |
| W7 | LOW | main.dart:191-206, 228-243 | `InAppWebViewSettings`를 두 곳에서 **중복 정의**(초기+onWebViewCreated 재설정) → 동기화 부담 | 단일 소스로 통합, userAgent만 갱신 |
| W8 | LOW | main.dart:115 | Universal link 매칭 `host.endsWith('.prayu.site')` → apex `prayu.site` 누락(서브도메인만). 앱 baseUrl 기본이 `www.`라 실사용 무해 | 필요 시 apex 포함 규칙 |

### 환경 / 빌드 (운영 안전)
| ID | 심각 | 파일:라인 | 현상 / 의도대로? | 리팩터 방향 |
|---|---|---|---|---|
| E1 | HIGH | main.dart:19 · scripts/*.sh | **env flavor 미배선.** `dotenv.load()`가 항상 `.env`만 로드. `build_android_prod.sh`=`flutter build appbundle`·`build_android_staging.sh`=`apk --debug`로 **env 선택 없음**. iOS `-dart-define=ENV=prod`는 (a)코드가 `fromEnvironment` 안 읽어 무시 (b)단일 대시 오타. → **staging/prod를 `.env` 수동 주석 토글로 결정** → staging 빌드가 prod 설정 실을 위험 | flavor를 실제 배선: (안①) 스크립트에서 `.env.<flavor>`→`.env` 복사 통일, 또는 (안②) `--dart-define`+`String.fromEnvironment`로 파일 선택. 하나로 통일 |
| E2 | MED | pubspec.yaml:36-38 | `.env`·`.env.staging`·`.env.prod` **3종 모두 flutter assets 번들** → 미사용 파일 + 환경 시크릿 동봉(앱 언팩 시 노출) | 로드하는 1개만 번들, 나머지 제외. 시크릿은 빌드시 주입 검토 |
| E3 | MED | android/app/build.gradle:10-14 | `key.properties` 없으면 **모든 빌드 실패**(디버그·CI 포함) — release 서명용 파일을 전 빌드가 요구 | debug는 keystore 없이도 빌드되게 분기 |

### 네이티브 / 권한 / 설정
| ID | 심각 | 파일:라인 | 현상 / 의도대로? | 리팩터 방향 |
|---|---|---|---|---|
| N1 | MED | MainActivity.kt:19-21 | `handleIntent`에서 `url==null`이면 `result.success(false)` 후 **`return` 없이** try로 떨어져 `result.success` 재호출 → "Reply already submitted" 크래시(엣지) | null 분기에 `return` 추가 |
| N2 | MED | ios/Runner/Info.plist:57-58 | `NSLocationWhenInUseUsageDescription`("위치 접근") 선언돼 있으나 **위치 사용 코드 없음** → 불필요 권한, App Store 심사 지적 리스크 | 미사용이면 제거 |
| N3 | MED | AndroidManifest.xml:13 | `usesCleartextTraffic="true"` → 평문 HTTP 허용(보안 약화) | 필요 근거 없으면 `false` |
| N4 | LOW | Info.plist:39-44 | 모바일 세로 제품인데 **landscape 방향 허용** → WebView 레이아웃 틀어질 수 있음 | portrait 고정 검토 |
| N5 | LOW | Info.plist:52-53 vs main.dart:131-135 | 상태바 처리 상충: plist `UIStatusBarHidden=true` vs Dart `edgeToEdge`+아이콘 밝기 지정 | 한쪽으로 통일 |
| N6 | LOW | AndroidManifest.xml:66-73 | App Links가 개별 호스트(www/staging/app) + `*.prayu.site` 와일드카드 **중복**(와일드카드 autoVerify는 각 서브도메인 assetlinks 필요) | 규칙 정리 |

### 기능 브리지 (인스타 공유 · 리뷰 · 앱 감지)
| ID | 심각 | 파일:라인 | 현상 / 의도대로? | 리팩터 방향 |
|---|---|---|---|---|
| S1 | MED | main.dart:306-353 | `shareInstagramStory`: (a) `fileName = photoUrl.split('/').last` → URL 쿼리스트링 포함 시 **잘못된 파일명**(`img.jpg?token=…`) (b) `FACEBOOK_APP_ID`가 env flavor(E1)에 의존인데 `.env.staging/.env.prod`엔 **그 키가 없음** → flavor 배선 시 공유 깨짐 (c) temp 파일 미정리 (d) `http.get` 타임아웃·크기제한 없음 | 파일명 정규화(쿼리 제거), FB키 소스 명확화(빌드 주입), temp 정리, 다운로드 방어 |
| S2 | LOW | main.dart:265-282 | `requestAppReview`: OS가 프롬프트를 억제해도 `status:'success'` 반환 → **성공≠실제 노출**. web이 노출 여부로 오해 가능 | 반환 의미를 "요청함"으로 명확화(노출 보장 불가 명시) |
| B1 | MED | main.dart:204 vs 223-227 | **확정(교차검증)**: web은 UA 문자열로만 앱 감지(`AppInit.tsx:10-13`, `flutter_inappwebview`는 감지에 안 씀). `isApp`은 `PrayU App`(initialSettings)로 초기부터 OK지만, **`isIOS`/`isAndroid`는 `prayu-ios/android` 마커(onWebViewCreated 설정)에 의존 → 첫 로드 레이스**로 iOS 전용 UI(예: 애플 로그인 버튼 `isApp&&isIOS`)가 첫 화면에 안 뜰 수 있음 | `prayu-ios/android`를 `initialSettings.applicationNameForUserAgent`에 함께 넣어 초기 로드부터 보장 |
| D1 | LOW | main.dart:70, 472 / web global.d.ts:8-17 | **죽은 코드(교차검증)**: `getAppVersion` 핸들러 web 미호출(주석 블록만), `LiveActivities.setupDefault()` web Live Activity 사용 0건, web `webkit/Android.openAppSettings` 타입 미사용 | 제거하거나 실사용 연결 여부 결정 |

---

## 리팩터 준비 — 제안 로드맵

우선순위는 (1) 지금 깨져 있고 사용자·운영에 직접 닿는 것 → (2) 안전/정합 → (3) 정리.

- **R1. WebView 네비게이션 코어 재작성** — W1·W2·W3·W4(+W6·W7). **카카오 앱전환 복원([plans/kakao-app-switch-restore.md](../plans/kakao-app-switch-restore.md))의 토대와 동일** → 이 리팩터가 곧 카카오 Phase 1. 외부 스킴 라우팅을 `url_launcher`로 통일 + `onCreateWindow` 신설 + JS 브리지 안전화 + 딥링크 파싱 교정.
- **R2. 환경/빌드 정합** — E1·E2·E3. flavor 실제 배선(스크립트 통일 or dart-define), 시크릿 취급, 빌드 게이트 완화. **운영 안전상 R1과 병행 우선.**
- **R3. 네이티브/기능/설정 정리** — N1~N6, W5·W8, **S1(인스타 공유)·S2(리뷰)·B1(앱 감지 UA)·D1(죽은 코드)**. 크래시(N1)·불필요 권한(N2)·cleartext(N3)·기능 브리지 견고화·죽은 코드 제거·잔여 정합.
  - B1 확정: web은 **UA 문자열로만** 감지(`flutter_inappwebview` 미사용) → `prayu-ios/android` 마커를 `initialSettings`에 통합하면 해소.

## 검증 방법(리팩터 시)
- 실기기 iOS/Android: 로그인(카카오 앱전환)·딥링크 진입·푸시 진입·이미지 저장·공유·네트워크 에러 폴백 회귀.
- **App 없는 브라우저 환경에서도 web이 안 깨지는지**(브리지 부재 대비) 병행 확인.
- flavor: staging 빌드가 실제 staging 설정을 싣는지(E1 수정 후) 번들 검사.

## 관련
- 카카오 앱전환: [plans/kakao-app-switch-restore.md](../plans/kakao-app-switch-restore.md)
- web 카카오 OAuth 전환: [../../PrayU-web/docs/plans/kakao-oauth-migration.md](../../../PrayU-web/docs/plans/kakao-oauth-migration.md)
- **web 후속(별개 레포)**: push-nav 수신 핸들러(`AppInit.tsx:19-28`)가 `event.origin` 미검증 + `window.location.href` 전체 리로드(SPA 상태 초기화). App측 W3(브리지 안전화)와 짝 → web backlog 대상.
- **web 후속(중복 감지)**: 여러 페이지가 `navigator.userAgent.match(/prayu/i)`로 스토어 안 거치고 앱 판별(`MainHeader.tsx:35`, `BibleCardSharePage.tsx:107` 등) → `isApp` 스토어로 일원화 검토.
