# PrayU-App 딥링크·푸시 리다이렉트·리뷰 API 개선 계획

## Context

PrayU는 웹앱 중심 제품이며 Flutter 앱(PrayU-App)은 WebView 셸로 최소한으로 유지한다.
현재 딥링크·푸시 클릭 리다이렉트가 동작하지 않고 리뷰 API 핸들링이 불완전하다. 조사로 확인된 원인:

1. **https 딥링크로 앱이 안 열림**: 네이티브 설정(intent-filter, entitlements)은 완비됐으나 웹에 배포된 OS 검증 파일이 빈 상태 — `assetlinks.json`의 `sha256_cert_fingerprints: []`, `apple-app-site-association`의 `details: []`. iOS/Android 모두 도메인-앱 연결 검증 실패.
2. **콜드 스타트 URL 유실**: 푸시 클릭·딥링크 모두 `webViewController != null`일 때만 navigate하고 아니면 조용히 버림 ([main.dart:552](../../lib/main.dart:552), [main.dart:541](../../lib/main.dart:541)). WebView가 있어도 웹 리스너 등록 전 postMessage는 유실.
3. **커스텀 스킴 파싱 버그**: `prayu://group/123`에서 `group`은 `uri.host`로 파싱되는데 코드는 `uri.path`만 사용 → `https://…/123`으로 잘못 변환 ([main.dart:99](../../lib/main.dart:99)).
4. **requestAppReview 불완전**: 네이티브가 `requestReview()`를 await하지 않고 무조건 success 반환; 웹 호출부([GroupMenuBtn.tsx:189](../../../PrayU-web/src/components/group/GroupMenuBtn.tsx:189))는 try/catch·null 체크 없음.

**사용자 결정사항**:
- 딥링크 대상 도메인은 **app.prayu.site 단독** (app.prayu.site로 마이그레이션 진행 중). www/staging/와일드카드 선언은 제거.
- Play 앱 서명 키 SHA-256은 사용자가 나중에 직접 기입 (PLACEHOLDER로 배치).

**확보된 값**:
- Apple Team ID: `2UR3HRG384` (pbxproj에서 확인)
- 업로드 키 SHA-256: `61:D4:39:2F:40:2A:8D:71:9F:2E:55:75:14:D9:7F:68:E0:F8:C9:BD:A4:38:4D:EB:07:61:65:28:F4:A9:6E:C6` (로컬 key.jks에서 확인)
- app.prayu.site는 이미 같은 Vercel 프로젝트에서 200으로 서빙 중 (빈 AASA 확인됨) — 파일만 채우면 즉시 유효
- prod BASE_URL은 `https://www.prayu.site/` (trailing slash 있음 — 정규화 필요). staging은 `https://prayu-staging.vercel.app/`

---

## Part 1. PrayU-web 변경 (웹 배포만으로 효력, 선행)

### 1-A. `public/.well-known/apple-app-site-association`

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["2UR3HRG384.com.team.visioneer.prayu"],
        "components": [
          { "/": "/auth/*", "exclude": true, "comment": "OAuth 콜백은 브라우저 세션 유지" },
          { "/": "*" }
        ]
      }
    ]
  }
}
```
- `/auth/*` 제외: Safari에서 카카오 OAuth 진행 중 콜백 URL이 앱으로 하이재킹되어 로그인 흐름이 끊기는 것 방지. 앱 내 WebView 내비게이션은 UL을 트리거하지 않으므로 앱 내 OAuth에는 영향 없음.

### 1-B. `public/.well-known/assetlinks.json`

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.team.visioneer.prayu",
      "sha256_cert_fingerprints": [
        "REPLACE_WITH_PLAY_APP_SIGNING_SHA256",
        "61:D4:39:2F:40:2A:8D:71:9F:2E:55:75:14:D9:7F:68:E0:F8:C9:BD:A4:38:4D:EB:07:61:65:28:F4:A9:6E:C6"
      ]
    }
  }
]
```
- **사용자 수동 단계**: Play Console → 설정 → 앱 서명 → "앱 서명 키 인증서" SHA-256을 복사해 PLACEHOLDER 교체 후 웹 재배포. 이 값이 실제 사용자 기기 검증에 쓰이는 필수 값 (업로드 키 지문은 내부 테스트 빌드용 보조).
- `dist/`는 빌드 산출물이므로 `public/`만 수정하면 다음 빌드에 반영됨.

### 1-C. `src/components/group/GroupMenuBtn.tsx` — `onClickAppReview` 방어 코드 (189행 부근)

```ts
if (window.flutter_inappwebview?.callHandler) {
  try {
    const result = (await window.flutter_inappwebview.callHandler(
      "requestAppReview"
    )) as { status?: string } | null;
    if (result?.status !== "success") requestStorePage();
  } catch {
    requestStorePage();
  }
} else {
  requestStorePage();
}
```

### 1-D. `src/AppInit/AppInit.tsx` — **변경 없음**
- 리스너 cleanup은 이미 존재(40–43행). `PUSH_NOTIFICATION_NAVIGATION` 리스너는 **구버전 앱 셸 호환을 위해 유지** (신버전 앱은 postMessage에 의존하지 않게 됨). 신버전 보급 후 제거 검토.

## Part 2. PrayU-App 변경 (앱 업데이트 필요)

### 2-A. `lib/main.dart` — pending URL 메커니즘 (핵심)

상태 필드 추가:
```dart
String baseUrl = (dotenv.env['BASE_URL'] ?? 'https://www.prayu.site')
    .replaceAll(RegExp(r'/+$'), '');  // trailing slash 정규화
String? _pendingUrl;
bool _webViewReady = false;
```

`_performWebViewNavigation`(postMessage 주입)을 삭제하고 `_navigateOrQueue`로 대체:
```dart
Future<void> _navigateOrQueue(String url) async {
  if (webViewController != null && _webViewReady && mounted) {
    await webViewController!.loadUrl(
      urlRequest: URLRequest(url: WebUri(url), headers: {'Accept-Language': 'ko-KR'}),
    );
  } else {
    _pendingUrl = url;  // 단일 슬롯, 마지막 값 승리
  }
}
```
- postMessage → loadUrl 전환 근거: 웹 리스너도 어차피 `window.location.href`(전체 리로드)라 postMessage의 이점이 없고, 리스너 등록 타이밍 레이스와 JS 문자열 이스케이프 문제가 함께 사라짐.

InAppWebView에 `onLoadStop` 추가 — 첫 로드 완료 시 pending flush:
```dart
onLoadStop: (controller, url) async {
  if (!_webViewReady) {
    _webViewReady = true;
    final pending = _pendingUrl;
    _pendingUrl = null;
    if (pending != null) {
      await controller.loadUrl(urlRequest: URLRequest(
        url: WebUri(pending), headers: {'Accept-Language': 'ko-KR'}));
    }
  }
},
```
- flush로 발생하는 두 번째 onLoadStop은 pending이 null이라 무해 (이중 내비게이션 없음).
- NetworkErrorView의 `onRetry`(179행 setState)에서 `_webViewReady = false` 리셋 한 줄 추가 — 에러 후 재시도 rebuild 시 WebView가 재생성되므로.

### 2-B. `lib/main.dart` — `_handleDeepLink` 수정 (파싱 버그 + 호스트 재작성)

```dart
void _handleDeepLink(Uri uri) {
  try {
    String? path;
    if (uri.scheme == 'prayu') {
      path = '/${uri.host}${uri.path}'.replaceFirst(RegExp(r'^/+'), '/');
    } else if (uri.scheme == 'https' &&
        (uri.host == 'prayu.site' || uri.host.endsWith('.prayu.site'))) {
      path = uri.path;
    }
    if (path == null) return;
    String webUrl = '$baseUrl$path';
    if (uri.query.isNotEmpty) webUrl += '?${uri.query}';
    _navigateOrQueue(webUrl);
  } catch (e) {
    debugPrint('Error parsing deep link: $e');
  }
}
```
- **호스트 재작성**: 어떤 prayu.site 호스트로 들어와도 path+query만 취해 `baseUrl`에 붙임. staging 빌드에 prod 링크가 와도 올바른 환경으로 매핑되고, www→app 마이그레이션 중에도 링크가 항상 셸이 설정된 환경으로 이동. `.env.prod`의 BASE_URL을 app.prayu.site로 바꾸는 시점(마이그레이션 완료)과 무관하게 동작.

### 2-C. `lib/main.dart` — `_handlePushNotificationClicked` 수정

```dart
Future<void> _handlePushNotificationClicked(OSNotificationClickEvent event) async {
  final rawUrl = event.notification.additionalData?['url'] as String?;
  if (rawUrl == null) return;
  final uri = Uri.tryParse(rawUrl);
  if (uri != null && uri.scheme.startsWith('http') && uri.host.endsWith('prayu.site')) {
    _handleDeepLink(uri);        // 호스트 재작성 경로 공유
  } else {
    _navigateOrQueue(rawUrl);    // 상대경로 등은 그대로 큐잉
  }
}
```
- 조건 분기 제거 → 콜드 스타트에서 자동 큐잉, 유실 없음.

### 2-D. `lib/main.dart` — requestAppReview 핸들러 보강 (265행)

```dart
callback: (args) async {
  try {
    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
      return {'status': 'success', 'message': 'Review requested.'};
    }
    return {'status': 'unavailable', 'message': 'In-app review is not available.'};
  } catch (e) {
    return {'status': 'error', 'message': e.toString()};
  }
},
```
- iOS 쿼터로 다이얼로그가 조용히 안 뜨는 건 OS가 신호를 주지 않아 감지 불가 — "요청 제출 성공" 의미로 유지. 스토어 폴백은 웹(`requestStorePage`)이 담당, 네이티브 `openStoreListing`은 추가하지 않음 (셸 최소화).

### 2-E. `android/app/src/main/AndroidManifest.xml` — 호스트 정리

- https intent-filter를 **app.prayu.site 단독**으로 정리 (www/staging/`*.prayu.site` 필터 제거). `prayu://` 커스텀 스킴 필터는 유지.
- 근거: 사용자 의도가 app.prayu.site 단독 딥링크. 검증 파일을 서빙 못 하는 호스트 선언은 `pm get-app-links`에 영구 실패로 남아 디버깅 오염.

### 2-F. `ios/Runner/Info.plist` + `ios/Runner/Runner.entitlements` — 호스트 정리

- associated domains를 `applinks:app.prayu.site` 단독으로 정리. `CFBundleURLTypes`의 `prayu` 스킴 유지. `FlutterDeepLinkingEnabled` 유지.

### 2-G. `lib/main.dart` — 설정 중복 제거 (저위험 정리)

- `initialSettings`(191행)와 `onWebViewCreated`의 `setSettings`(228행)에 중복된 `InAppWebViewSettings`를 필드로 추출하고, onWebViewCreated에서는 userAgent만 갱신해 재적용.

## Part 3. iOS 계정 양도에 따른 OneSignal App Group 수리 (앱 업데이트에 포함)

**진단 (사용자 확인 완료)**: App Store Connect로 앱을 새 팀(2UR3HRG384)에 양도했으나, **App Group은 Apple 정책상 양도되지 않고 기존 팀(63B3RKAA2H)에 남습니다.** 현재 entitlements 2곳이 참조하는 `group.com.team.visioneer.prayu.onesignal`을 새 팀이 등록할 수 없어 자동 서명이 App Group 에러로 실패 — "OneSignal이 기존 앱으로 인식되는" 증상의 실체.

### 3-A. 새 App Group ID로 교체

새 그룹 ID: `group.com.team.visioneer.prayu.onesignal.v2` (기존 팀 소유 ID와 충돌하지 않는 이름)

1. **사용자 수동 단계**: Apple Developer 포털(새 팀) → Certificates, Identifiers & Profiles → Identifiers → App Groups에 위 ID 등록. (Xcode 자동 서명이 등록해주는 경우도 있으나 포털 등록이 확실)
2. `ios/Runner/Runner.entitlements` — `com.apple.security.application-groups` 값을 새 ID로 교체
3. `ios/OneSignalNotificationServiceExtension/OneSignalNotificationServiceExtension.entitlements` — 동일 교체
4. `ios/Runner/Info.plist` **및** `ios/OneSignalNotificationServiceExtension/Info.plist`에 다음 키 추가 (OneSignal은 기본값으로 `group.{bundle_id}.onesignal`을 찾으므로 커스텀 그룹명을 명시해야 함):
   ```xml
   <key>OneSignal_app_groups_key</key>
   <string>group.com.team.visioneer.prayu.onesignal.v2</string>
   ```
- 부작용: App Group에 캐시되던 OneSignal 공유 데이터(뱃지 카운트 등)가 초기화됨 — 무시 가능한 수준.

### 3-B. 양도 후속 확인 사항 (빌드 외, 사용자 수동)

- **APNs 인증 키 재발급**: 기존 팀의 APNs 키/인증서는 양도 후 무효. 새 팀에서 APNs Auth Key(.p8) 발급 → OneSignal 대시보드 → Settings → Platforms → Apple iOS에 업로드. 이걸 안 하면 빌드가 성공해도 iOS 푸시가 전송되지 않음.
- uncommitted pbxproj의 팀 변경(63B3RKAA2H → 2UR3HRG384)은 이번 작업에 포함해 커밋.

## 마이그레이션 참고 (이번 변경 범위 밖, 별도 결정)

- `.env.prod`의 `BASE_URL`을 `https://app.prayu.site`로 바꾸는 시점은 웹 마이그레이션 완료 시. 2-B의 호스트 재작성 덕에 딥링크 동작은 이 전환과 독립적.
- www.prayu.site → app.prayu.site 리다이렉트 도입 시에도 딥링크는 app 도메인 기준이라 영향 없음.

## 배포 순서

1. **웹 먼저 배포**: 검증 파일 2개 + GroupMenuBtn → Vercel. (사용자가 Play 서명 키 SHA-256 기입 후 재배포)
2. **앱 업데이트**: main.dart + Manifest/entitlements → 스토어 심사.
3. iOS는 AASA를 **앱 설치/업데이트 시점에 캐시**하므로, 웹 배포 후 테스트 시 앱 삭제 후 재설치 필요.

## 인수테스트 가이드 (운영 영향 최소화 순서로, 사용자 직접 수행)

각 단계는 이전 단계 합격 후에만 진행. 실패 시 해당 단계에서 멈추면 프로덕션은 영향받지 않음.

### Stage 0 — 사전 준비 (프로덕션 영향 없음)
| 항목 | 방법 | 합격 기준 |
|---|---|---|
| Play 서명 키 지문 | Play Console → 설정 → 앱 서명 → "앱 서명 키 인증서" SHA-256 복사 → assetlinks.json에 기입 | 값 기입 완료 |
| 새 App Group 등록 | Apple Developer(새 팀) → Identifiers → App Groups → `group.com.team.visioneer.prayu.onesignal.v2` 등록 | 포털에 표시됨 |
| APNs 키 재발급 | 새 팀에서 .p8 발급 → OneSignal 대시보드 Apple iOS 설정에 업로드 | OneSignal에서 "Configured" 표시. ※ 양도 후 기존 키는 이미 무효라 현재 iOS 푸시가 깨져 있을 가능성 — 업로드는 수리이지 리스크가 아님 |

### Stage 1 — 웹 배포 (저위험: 검증 파일은 현재 빈 상태=이미 고장이므로 채우는 것만으로 악화 불가)
1. PR 생성 → **Vercel preview URL**에서 선확인:
   - `curl -s https://<preview>.vercel.app/.well-known/assetlinks.json` → 지문 2개 포함 JSON
   - `curl -s https://<preview>.vercel.app/.well-known/apple-app-site-association` → appIDs에 `2UR3HRG384.com.team.visioneer.prayu`
2. 프로덕션 배포 후:
   - 위 curl 2종을 `https://app.prayu.site/...`로 재확인
   - `curl -s https://app-site-association.cdn-apple.com/a/v1/app.prayu.site` — Apple CDN 반영 (수분~수시간 걸릴 수 있음, 다음 단계 전 필수)
3. **회귀 확인 (기존 사용자 관점)**:
   - 데스크톱/모바일 브라우저에서 그룹 메뉴 → 앱 리뷰 버튼 → 스토어 페이지로 이동 (크래시 없음)
   - **현재 스토어에 있는 구버전 앱**에서 푸시 클릭 이동이 여전히 동작 (웹 리스너를 유지했으므로 동작해야 함) — 본인 계정으로 OneSignal 테스트 푸시 1건
   - 합격 기준: 기존 흐름 전부 이상 없음. 여기까지는 앱 미배포 상태라 언제든 웹 롤백 가능.

### Stage 2 — 앱 스테이징 빌드, 본인 기기 테스트 (스토어 미배포)
`scripts/build_ios_staging.sh` / `scripts/build_android_staging.sh`(BASE_URL=prayu-staging.vercel.app) 또는 로컬 `flutter run --release`로 본인 기기에 설치 후:

| # | 시나리오 | 방법 | 합격 기준 |
|---|---|---|---|
| 1 | iOS 빌드 자체 | Xcode Archive 또는 build_ios | **App Group 서명 에러 없이 빌드 성공** (Part 3 검증) |
| 2 | 커스텀 스킴 (웜) | 앱 켜둔 채 Safari/메모에서 `prayu://group/<실제id>` 탭 (Android: `adb shell am start -a android.intent.action.VIEW -d "prayu://group/<id>"`) | `/group/<id>` 페이지 도착 — **`/<id>`가 아님** (파싱 버그 수정 확인) |
| 3 | 커스텀 스킴 (콜드) | 앱 완전 종료(태스크 스와이프) 후 #2 반복 | 앱 실행 → 첫 로드 후 자동으로 목적지 도착 (URL 유실 없음) |
| 4 | 푸시 클릭 (웜/콜드) | OneSignal 대시보드에서 **본인 userId만 타겟**으로 `additionalData.url` 포함 테스트 발송, 웜/콜드 각각 클릭 | 두 경우 모두 목적지 도착 |
| 5 | 네트워크 에러 경로 | 비행기 모드로 콜드 스타트 + 딥링크 → 에러 화면 → 네트워크 복구 → 재시도 | pending URL로 도착 |
| 6 | 앱 리뷰 | 그룹 메뉴 → 앱 리뷰 버튼 | 리뷰 다이얼로그 표시 또는 스토어 이동, 크래시 없음 (iOS는 쿼터로 다이얼로그가 안 뜰 수 있음 — 크래시 없으면 합격) |
| 7 | 기본 회귀 | 로그인 → 그룹 → 기도카드 → 공유/이미지 저장 | 기존과 동일 동작 |

### Stage 3 — 스토어 내부 테스트 트랙 (프로덕션 서명으로 최종 확정)
유니버설 링크/앱 링크는 **스토어 서명·설치 경로**에 의존하므로 이 단계가 결정적:
- **Android**: 내부 테스트 트랙 업로드 → 내부 테스터로 설치 (Play App Signing 서명 적용됨) →
  `adb shell pm get-app-links com.team.visioneer.prayu` → `app.prayu.site: verified` 확인 →
  카카오톡/메모에서 `https://app.prayu.site/group/<id>` 탭 → **브라우저가 아닌 앱**으로 열림
- **iOS**: TestFlight 업로드 → 설치 (설치 시점에 AASA를 Apple CDN에서 새로 캐시) →
  메모 앱에 `https://app.prayu.site/group/<id>` 입력 후 탭 (또는 롱프레스 → "PrayU에서 열기" 노출 확인) → 앱으로 열림
- 푸시: TestFlight/내부 테스트 빌드에서 본인 타겟 푸시 수신 + 클릭 이동 재확인 (새 APNs 키 검증)
- 합격 기준: 위 전부 통과. 실패 시 스토어 공개 전이므로 사용자 영향 0.

### Stage 4 — 프로덕션 릴리스 + 모니터링
- Android는 **단계적 출시(10~20%)**로 시작 권장
- 릴리스 후 24~48시간: OneSignal 대시보드 전송/클릭 지표, Sentry 신규 에러, 스토어 리뷰 크래시 리포트 확인
- 최종 확정 기준: 실사용자 기기에서 푸시 클릭 유입이 목적지 페이지 조회로 이어지는지 (analytics의 `클릭_알림_확인` 및 그룹 페이지 진입 이벤트 추이)

## 검증 방법

웹 배포 직후:
```bash
curl -s https://app.prayu.site/.well-known/assetlinks.json
curl -s https://app.prayu.site/.well-known/apple-app-site-association
curl -s https://app-site-association.cdn-apple.com/a/v1/app.prayu.site   # Apple CDN 반영 확인
```

Android:
```bash
adb shell pm verify-app-links --re-verify com.team.visioneer.prayu
adb shell pm get-app-links com.team.visioneer.prayu        # app.prayu.site: verified 기대
adb shell am start -a android.intent.action.VIEW -d "https://app.prayu.site/group/<실제id>"
adb shell am start -a android.intent.action.VIEW -d "prayu://group/<실제id>"
```

iOS:
```bash
xcrun simctl openurl booted "prayu://group/<실제id>"
xcrun simctl openurl booted "https://app.prayu.site/group/<실제id>"
```

테스트 매트릭스 (플랫폼 × 콜드/웜):
1. OneSignal 대시보드에서 `additionalData.url` 포함 테스트 푸시 → 콜드 스타트: 목적지 도착(유실 없음) / 웜: 목적지 리로드
2. `prayu://group/<id>` → `/group/<id>` 도착 확인 (**`/<id>`가 아님** = 파싱 버그 수정 검증)
3. https 유니버설 링크 → 브라우저가 아닌 앱으로 열림
4. 비행기 모드 콜드 스타트 + 딥링크 → NetworkErrorView → 복구·재시도 → pending URL 도착
5. 연속 딥링크 2회 → 마지막 URL만 표시
6. 앱 리뷰 버튼: 정상/예외/구버전 셸(핸들러 없음) 각각에서 다이얼로그 또는 스토어 이동, 크래시 없음
7. 웹 단독(브라우저) 환경에서 GroupMenuBtn 리뷰 버튼 → 스토어 페이지 이동 (회귀 확인)

빌드 검증: PrayU-App `flutter analyze`, PrayU-web `npm run lint && npm run build` (기존 경고 4개는 알려진 상태).

App Group 수리 검증 (Part 3):
1. Apple Developer 포털에 새 그룹 등록 후 `flutter build ios --release` (또는 Xcode Archive) — App Group 서명 에러 소멸 확인
2. 실기기에서 OneSignal 테스트 푸시 수신 확인 (APNs 키 업로드 후) — 알림 이미지/뱃지 등 확장 동작 포함
3. 푸시 클릭 → 앱 진입 → 목적지 도착 (Part 2 매트릭스 1번과 통합 검증)
