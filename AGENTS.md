# AGENTS.md

이 저장소는 PrayU의 Flutter 모바일 셸입니다. 이 파일은 Codex가 이 코드베이스에서
작업할 때 따라야 하는 로컬 지침입니다.

## 프로젝트 역할

앱은 네이티브 기능을 책임합니다. 웹앱은 제품 화면, 라우팅, 콘텐츠, 비즈니스
로직을 책임합니다.

제품 동작은 가능하면 웹에서 바꿉니다. 네이티브 권한, 푸시 알림, 앱 리뷰,
WebView 동작, 앱/웹 bridge handler, 딥링크, 소셜 공유, 갤러리 접근, signing,
versioning, 스토어 릴리즈 동작이 관련될 때 이 앱을 수정합니다.

앱 동작을 바꾸기 전에는 `APP_MAINTENANCE.md`를 읽습니다.

## Working Tree 안전 규칙

- 편집 전에 `git status --short --branch`를 확인합니다.
- 내가 만들지 않은 local change를 되돌리지 않습니다.
- iOS project file diff는 분리해서 조심스럽게 검토합니다.
- secret, signing key, provisioning profile, 환경 변수 값을 commit하지 않습니다.
- 최종 답변이나 commit된 문서에 `.env`, `android/key.properties`, signing credential
  값을 노출하지 않습니다.

## 중요 파일

- `lib/main.dart`: WebView shell, OneSignal setup, 딥링크, JavaScript handler,
  Android intent fallback.
- `lib/services/image_download_service.dart`: 이미지 다운로드와 갤러리 저장.
- `lib/widgets/network_error_view.dart`: 네이티브 네트워크 retry 화면.
- `pubspec.yaml`: Flutter SDK constraint, dependencies, assets, 앱 version.
- `android/app/build.gradle`: Android app id, SDK level, signing, Facebook app id
  resource wiring.
- `android/app/src/main/AndroidManifest.xml`: 권한, app link, custom scheme, social
  app query, provider.
- `android/app/src/main/kotlin/com/team/visioneer/prayu/MainActivity.kt`: Android
  `intent://` 처리를 위한 method channel.
- `ios/Runner/Info.plist`: iOS 권한, URL scheme, associated domain, Facebook 설정,
  앱 metadata.
- `ios/Runner/Runner.entitlements`: push, app group, associated domain entitlement.
- `ios/OneSignalNotificationServiceExtension`: OneSignal rich notification
  extension.

## 앱/웹 Bridge 규칙

JavaScript handler는 웹앱이 사용하는 공개 API로 취급합니다. 웹앱도 같은 계약으로
업데이트하지 않는 한 handler 이름, 인자 형태, 응답 형태를 유지합니다.

현재 handler:

- `onLogin`
- `requestAppReview`
- `triggerHapticFeedback`
- `shareInstagramStory`
- `downloadImages`
- `openAppSettings`
- `getAppVersion`

앱은 푸시/딥링크 이동을 위해 `window.postMessage`로
`PUSH_NOTIFICATION_NAVIGATION` type을 웹앱에 보냅니다.

## 코딩 지침

- 기존 Flutter 스타일을 따르고 변경 범위를 작게 유지합니다.
- `lib/main.dart`는 앱 셸 orchestration 중심으로 유지합니다. 새 네이티브 bridge
  로직이 커지면 service 파일로 분리합니다.
- JavaScript handler는 `status` 필드를 포함한 structured map을 반환합니다.
- 기존 웹 호출을 깨는 변경보다 additive bridge 변경을 선호합니다.
- 진단 로그는 `debugPrint`를 사용하고, secret이나 민감한 사용자 데이터를 남기지
  않습니다.
- 양쪽 플랫폼에서 기대되는 기능은 Android/iOS 설정을 함께 확인합니다.
- 네이티브 플랫폼 연동상 필요한 경우가 아니라면 비즈니스 규칙을 Flutter에 넣지
  않습니다.
- Android에서 일회성/간헐적 사진 접근이 필요하면 `READ_MEDIA_IMAGES` 또는
  `READ_MEDIA_VIDEO`를 추가하기 전에 system photo picker를 먼저 검토합니다.
- Android 갤러리 저장 기능은 현재 `gal` 패키지를 사용하며, API 29 이하 대응용
  `WRITE_EXTERNAL_STORAGE`만 manifest에 남깁니다. 읽기 권한은 기능상 필요할 때만
  추가합니다.

## 검증

변경 위험도에 맞춰 가장 작은 검증을 수행하되, 실제 신뢰를 줄 수 있어야 합니다.

권장 명령:

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build ios --release --no-codesign
```

의존성 변경 후:

```bash
flutter pub get
```

푸시 알림, 앱 리뷰, universal/app link, Android intent, Instagram Story 공유,
이미지 저장, 권한 흐름은 실제 기기 수동 테스트가 필요합니다.

## 버전 관리

앱 버전은 `pubspec.yaml`에 있습니다.

- 웹만 바뀌면 앱 버전 bump가 필요 없습니다.
- 네이티브 동작, bridge, SDK, 권한, 푸시, 딥링크, signing, 스토어 노출 동작 변경은
  version/build number를 올립니다.
- 재심사는 보통 최소 build number bump가 필요합니다.

## 릴리즈 전 확인

- 올바른 `.env` target인지 확인합니다.
- 올바른 `ONESIGNAL_APP_ID`인지 확인합니다.
- `FACEBOOK_APP_ID` wiring이 맞는지 확인합니다.
- Android signing config가 로컬에 있는지 확인합니다.
- iOS signing team과 entitlement가 의도한 값인지 확인합니다.
- App link/universal link가 웹 도메인에도 설정되어 있는지 확인합니다.

## 문서화

앱/웹 계약이나 릴리즈 절차를 바꾸면 같은 변경에서 `APP_MAINTENANCE.md`도
업데이트합니다.
