# PrayU App 유지보수 문서

이 Flutter 프로젝트는 PrayU의 네이티브 모바일 셸입니다. 제품 경험과
비즈니스 로직은 대부분 웹앱에서 운영하고, 이 앱은 웹만으로 처리하기 어려운
기기 기능과 스토어 배포 영역을 책임집니다.

## 책임 분리

### 앱이 책임지는 것

앱은 작고 명확한 네이티브 어댑터 역할을 유지합니다.

- `flutter_inappwebview`로 PrayU 웹앱을 로드합니다.
- 웹이 앱 환경을 구분할 수 있도록 user agent에 `prayu-ios` 또는
  `prayu-android`를 추가합니다.
- WebView 쿠키, local storage, cache, session data를 유지합니다.
- OneSignal을 초기화하고, 웹 로그인 이후 네이티브 푸시 구독을 user id와
  연결합니다.
- 푸시 알림 클릭을 받아 웹앱으로 이동할 URL을 전달합니다.
- custom scheme deep link와 universal/app link를 처리합니다.
- 웹앱이 호출할 수 있는 네이티브 기능을 JavaScript handler로 제공합니다.
- Android `intent://` URL을 처리하고, 실패 시 browser fallback URL을
  WebView에 로드합니다.
- 이미지 저장, 공유, 푸시, 링크 연동에 필요한 네이티브 권한과 설정을
  관리합니다.
- WebView 초기 로드가 실패했을 때 네트워크 오류 화면을 제공합니다.
- 앱 버전, 빌드 번호, signing, 네이티브 플랫폼 설정, splash, launcher icon,
  스토어 릴리즈 동작을 관리합니다.

### 웹이 책임지는 것

웹앱은 제품의 소스 오브 트루스입니다.

- 화면, 라우팅, 콘텐츠, 사용자 여정.
- 제품 정책과 비즈니스 규칙.
- 인증 UI와 로그인 흐름.
- 앱 리뷰, 햅틱, 이미지 다운로드, 공유 같은 네이티브 기능을 언제 요청할지.
- 푸시 알림과 딥링크에서 사용할 URL 생성.
- 앱에서 보내는 `window.postMessage` 이벤트 처리.
- 새 네이티브 권한, SDK 변경, 스토어 심사가 필요 없는 기능 배포.

웹 업데이트만으로 안전하게 배포할 수 있는 변경은 웹에서 처리합니다. 네이티브
SDK, 권한, 스토어 노출 동작, 앱/웹 bridge 계약, 딥링크, 푸시, 플랫폼별 동작이
바뀌면 앱 업데이트로 처리합니다.

## 런타임 설정

앱은 `main()`에서 기본적으로 `.env`를 로드합니다.

현재 코드에서 사용하는 환경 변수 키:

- `ENV`
- `BASE_URL`
- `ONESIGNAL_APP_ID`
- `FACEBOOK_APP_ID`

현재 저장소에 있는 환경 파일:

- `.env`
- `.env.staging`
- `.env.prod`

환경 변수 값, signing 정보, key 값은 문서나 답변에 노출하지 않습니다. 키 이름과
기대 동작만 문서화합니다.

## 현재 네이티브 기능 표면

앱의 주요 진입점은 `lib/main.dart`입니다.

### WebView

초기 WebView URL은 `BASE_URL`이고, 값이 없으면 `https://www.prayu.site`를
사용합니다.

중요한 WebView 설정:

- JavaScript 활성화.
- multiple window 지원.
- download start handling 활성화.
- URL override handling 활성화.
- third-party cookie 활성화.
- cache, DOM storage, database storage 활성화.
- shared cookie 활성화.
- user agent에 `prayu-ios` 또는 `prayu-android` 추가.

초기 로드와 fallback 로드에는 `Accept-Language: ko-KR` header를 사용합니다.

### 푸시 알림

OneSignal은 `ONESIGNAL_APP_ID`로 초기화합니다.

앱 동작:

- OneSignal 언어를 한국어로 설정합니다.
- 알림 권한이 아직 결정되지 않았으면 권한을 요청합니다.
- 앱 시작과 resume 시점에 알림을 정리합니다.
- 푸시 클릭 listener를 등록합니다.
- `onLogin` JavaScript handler에서 `OneSignal.login(userId)`를 호출합니다.
- 로그인 후 push subscription을 opt-in 합니다.
- OneSignal tag로 `userId`를 추가합니다.

푸시 클릭 payload는 `additionalData.url`을 포함해야 합니다. URL이 있으면 앱은
다음 메시지를 WebView에 전달합니다.

```js
window.postMessage({
  type: 'PUSH_NOTIFICATION_NAVIGATION',
  url: '<url>'
}, '*')
```

웹앱은 이 메시지를 받아 실제 라우팅을 수행합니다.

### 딥링크

앱은 다음 링크를 처리합니다.

- custom scheme: `prayu://...`
- PrayU 도메인의 HTTPS app/universal link

custom scheme은 path와 query를 `BASE_URL` 뒤에 붙여 웹 URL로 변환합니다.
`*.prayu.site` HTTPS 링크는 원래 URL 그대로 WebView에 전달합니다.

Android와 iOS 양쪽에 설정된 도메인:

- `www.prayu.site`
- `staging.prayu.site`
- `app.prayu.site`
- `*.prayu.site`

도메인을 변경할 때는 앱 설정뿐 아니라 웹 도메인의 asset links,
apple-app-site-association 설정도 함께 확인합니다.

### Android Intent URL

Android `intent://` URL은 네이티브 method channel로 처리합니다.

- Channel: `com.team.visioneer.prayu/intent`
- Method: `handleIntent`

Android가 intent 실행에 실패하면 `S.browser_fallback_url`을 추출해서 WebView에
로드합니다.

## JavaScript Bridge 계약

웹앱은 `window.flutter_inappwebview`를 통해 네이티브 기능을 호출합니다. 이
handler들은 앱/웹 사이의 호환성 계약입니다. 웹 배포와 함께 조율하지 않았다면
handler 이름, 인자 형태, 응답 형태를 깨지 않도록 합니다.

### `onLogin`

목적: 로그인한 웹 user id를 OneSignal 사용자와 연결합니다.

입력:

```js
[userId]
```

성공 응답:

```js
{ status: 'success', userId: '<userId>' }
```

실패 응답:

```js
{ status: 'error', message: '<error>' }
```

### `requestAppReview`

목적: 네이티브 인앱 리뷰 요청을 실행합니다.

입력: 필수 인자 없음.

응답:

```js
{ status: 'success', message: 'Review requested.' }
{ status: 'unavailable', message: 'In-app review is not available.' }
```

### `triggerHapticFeedback`

목적: 네이티브 햅틱 피드백을 실행합니다.

입력:

```js
[type]
```

지원 타입:

- `lightImpact`
- `mediumImpact`
- `heavyImpact`
- `selectionClick`
- `vibrate`

응답:

```js
{ status: 'success', message: 'Haptic feedback triggered.' }
```

### `shareInstagramStory`

목적: 이미지를 다운로드한 뒤 Instagram Story 공유를 엽니다.

입력:

```js
[photoUrl]
```

`FACEBOOK_APP_ID`를 사용합니다. 값이 없으면 `error`를 반환합니다.

성공 응답:

```js
{ status: 'success', message: 'Instagram story sharing initiated.' }
```

실패 응답:

```js
{ status: 'error', message: '<error>' }
```

### `downloadImages`

목적: 원격 이미지 하나 또는 여러 개를 기기 갤러리에 저장합니다.

입력:

```js
[imageUrl]
[imageUrls, maxConcurrent]
```

동작:

- 단일 URL 문자열 또는 URL 문자열 배열을 받습니다.
- 단일 이미지는 기본 `maxConcurrent = 1`입니다.
- 여러 이미지는 기본 `maxConcurrent = 3`입니다.
- 명시된 동시 다운로드 수는 `1..10` 범위로 제한합니다.
- 실제 저장은 `ImageDownloadService.downloadMultipleImagesToGallery`가
  수행합니다.

대표 응답:

```js
{
  status: 'success' | 'error',
  message: '<summary>',
  total: 0,
  success: 0,
  failed: 0,
  results: []
}
```

### `openAppSettings`

목적: 사용자가 권한을 조정할 수 있도록 네이티브 앱 설정 화면을 엽니다.

응답:

```js
{ status: 'success' | 'error', message: '<localized message>' }
```

### `getAppVersion`

목적: 웹앱이 설치된 앱 버전을 확인할 수 있게 합니다.

성공 응답:

```js
{
  status: 'success',
  version: '<semantic version>',
  buildNumber: '<build number>',
  appName: '<app name>',
  packageName: '<package id>',
  platform: 'ios' | 'android'
}
```

실패 응답:

```js
{ status: 'error', message: '<error>' }
```

## 네이티브 플랫폼 설정

### Android

중요 파일:

- `android/app/build.gradle`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/team/visioneer/prayu/MainActivity.kt`
- `android/key.properties`
- `android/app/key.jks`

현재 Android 설정:

- Application id: `com.team.visioneer.prayu`
- Namespace: `com.team.visioneer.prayu`
- Compile SDK: 35
- Target SDK: 35
- Minimum SDK: 21
- Java/Kotlin target: 11
- Release signing은 `android/key.properties`를 읽습니다.
- Facebook app id는 `key.properties`에서 읽어 resource로 주입합니다.

중요 권한과 연동:

- Internet access.
- Android 13+ broad media read 권한(`READ_MEDIA_IMAGES`,
  `READ_MEDIA_VIDEO`)은 사용하지 않습니다. PrayU 앱은 갤러리 전체를 지속적으로
  읽는 앱이 아니며, 원격 이미지 저장과 공유 중심의 네이티브 셸입니다.
- API 29 이하 이미지 저장용 `WRITE_EXTERNAL_STORAGE` 권한. `READ_EXTERNAL_STORAGE`는
  현재 기능에 필요하지 않아 사용하지 않습니다.
- OneSignal notification icon metadata.
- 소셜 공유용 FileProvider.
- Facebook SDK metadata와 provider.
- App link와 custom scheme intent filter.
- Kakao, Instagram, Facebook, Telegram, WhatsApp, Twitter, Android intent 처리를
  위한 package/query visibility.

### iOS

중요 파일:

- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/OneSignalNotificationServiceExtension/*`
- `ios/Podfile`

현재 iOS 설정:

- Display name: `PrayU`
- Push background mode: `remote-notification`
- OneSignal notification service extension.
- PrayU link용 associated domains.
- Custom URL scheme: `prayu`
- `FACEBOOK_APP_ID` 기반 Facebook URL scheme.
- 사진 라이브러리 사용 문구.
- 소셜 앱 query scheme.
- Non-exempt encryption flag false.

`ios/Runner.xcodeproj/project.pbxproj`는 조심해서 다룹니다. Xcode가 object
version, formatting, signing team, build phase 배열을 자동으로 바꿀 수 있습니다.
이런 diff는 실제 앱 동작 변경과 분리해서 검토합니다.

## 버전 관리

Flutter 앱 버전은 `pubspec.yaml`에서 관리합니다.

이 문서를 작성한 시점의 버전:

```yaml
version: 1.3.2+20
```

별도 릴리즈 규칙이 생기기 전까지는 다음 기준을 사용합니다.

- 웹만 바뀐 경우: 앱 버전 변경 없음.
- 앱 bridge, 네이티브 SDK, 권한, 딥링크, 푸시, signing, 스토어 노출 동작 변경:
  version과 build number를 함께 올립니다.
- 사용자 노출 변경 없이 재심사나 내부 빌드가 필요한 경우: 최소 build number를
  올립니다.

## 릴리즈 체크리스트

앱 업데이트 배포 전 확인합니다.

- working tree에 관련 없는 local change가 없는지 확인합니다.
- `.env`가 의도한 환경을 가리키는지 확인합니다.
- `pubspec.yaml`의 version/build number를 확인합니다.
- 의존성 변경 후 `flutter pub get`을 실행합니다.
- `flutter analyze`를 실행합니다.
- 테스트가 있거나 동작을 바꿨다면 `flutter test`를 실행합니다.
- Android release build를 확인합니다.
- iOS release build 또는 최소 `flutter build ios --release --no-codesign`을
  확인합니다.
- 실제 Android 기기에서 smoke test를 합니다.
- 실제 iOS 기기에서 smoke test를 합니다.

수동 smoke test 항목:

- 앱이 올바른 웹 URL을 엽니다.
- 로그인 세션이 앱 재시작 후에도 유지됩니다.
- WebView user agent에 `prayu-ios` 또는 `prayu-android`가 포함됩니다.
- `onLogin`이 OneSignal 사용자 연결을 수행합니다.
- 푸시 알림 권한 요청 흐름이 정상 동작합니다.
- 푸시 클릭이 웹앱의 기대 URL로 이동합니다.
- `prayu://` 딥링크가 앱을 열고 WebView를 이동시킵니다.
- HTTPS app/universal link가 앱을 열고 WebView를 이동시킵니다.
- Android `intent://` 링크가 대상 앱 또는 fallback URL로 연결됩니다.
- 앱 리뷰 요청이 crash 없이 처리됩니다.
- 햅틱 handler가 success를 반환합니다.
- 유효한 이미지 URL로 Instagram Story 공유가 동작합니다.
- 이미지 1개 저장과 여러 이미지 저장이 모두 동작합니다.
- 권한 거부 상황에서 웹/앱이 복구 가능한 흐름을 제공합니다.
- 네트워크 실패 시 retry 화면이 표시됩니다.

## 웹과 조율해야 하는 변경

다음을 바꿀 때는 웹앱 변경과 함께 조율합니다.

- JavaScript handler 이름.
- Handler 인자 형태.
- Handler 응답 형태.
- `window.postMessage` event type 또는 payload 형태.
- 앱 user agent marker.
- 푸시 알림 또는 딥링크 URL 형식.
- App link/universal link 도메인.
- 필수 환경 변수 키.

## 현재 유지보수 메모

- `README.md`는 아직 기본 Flutter 템플릿이며, 현재 프로덕션 앱 구조를 설명하지
  않습니다.
- `ios/Runner.xcodeproj/project.pbxproj`에는 현재 working tree local change가
  있습니다. iOS와 무관한 작업을 시작하기 전에 별도로 확인합니다.
- 이 앱은 의도적으로 얇은 셸입니다. 네이티브 플랫폼 요구사항이 아니라면 제품
  규칙을 Flutter로 옮기지 않습니다.

## 정책 대응 기록

### 2026-05-26: Google Play 사진 및 동영상 권한 정책 대응

Play Console에서 versionCode 19가 `READ_MEDIA_IMAGES`와 `READ_MEDIA_VIDEO`를
사용한다고 경고했습니다. PrayU 앱의 현재 Android 기능은 사용자의 사진/동영상
라이브러리를 지속적으로 읽는 것이 아니라, 웹에서 전달한 원격 이미지 URL을
다운로드해 갤러리에 저장하거나 공유하는 흐름입니다.

조치:

- `android/app/src/main/AndroidManifest.xml`에서 `READ_MEDIA_IMAGES` 제거.
- `android/app/src/main/AndroidManifest.xml`에서 `READ_MEDIA_VIDEO` 제거.
- `android/app/src/main/AndroidManifest.xml`에서 불필요한 `READ_EXTERNAL_STORAGE`
  제거.
- `pubspec.yaml` version을 `1.3.2+20`으로 올려 Play Console에 새 AAB를 제출할
  수 있게 함.

향후 사용자가 직접 기기 사진/동영상을 선택해 업로드하는 기능이 필요하면 broad
media read 권한을 다시 추가하기보다 Android system photo picker 기반 접근을
우선 검토합니다.
