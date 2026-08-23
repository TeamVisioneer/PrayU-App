# R2 — 환경(flavor) 배선 정상화

> 상태: **설계·승인 대기** (2026-08-19) — 결함 대장 R2. 코드 리스크 낮음, 운영 안전 효과 큼.
> 대장: [../guides/app-audit-ledger.md](../guides/app-audit-ledger.md) (E1·E2·E3)

## 왜 지금 하나

현재 **staging/prod 환경이 실제로 배선돼 있지 않다.** 그래서 이후 모든 staging 테스트(카카오 포함)의 신뢰성이 여기에 달려 있다.

근거(대장 E1):
- `lib/main.dart:19` `await dotenv.load();` — **fileName 없음 → 항상 `.env`만** 로드
- `scripts/build_android_prod.sh` = `flutter build appbundle`, `build_android_staging.sh` = `flutter build apk --debug` — **env 선택 없음**
- `scripts/build_ios_prod.sh` = `... -dart-define=ENV=prod` — (a) 코드가 `String.fromEnvironment`를 안 읽어 **무시**, (b) 단일 대시 오타
- `.env`엔 현재 prod 값이 켜져 있고 staging은 주석 처리 → **환경을 `.env` 손편집으로 결정** → staging 빌드가 prod 설정을 실을 수 있음
- `.env.staging`/`.env.prod`는 존재·번들되나 **로드 안 됨**, 게다가 **`FACEBOOK_APP_ID` 키가 빠져 있음**(인스타 공유 S1과 연결)

## 결정 — 방식 ② (dart-define + 파일 선택) 권장

| 방식 | 내용 | 트레이드오프 |
|---|---|---|
| ① 스크립트 복사 | 빌드 전 `.env.<flavor>` → `.env` 복사, 코드는 `.env` 로드 유지 | 코드 변경 최소지만 **추적 파일 변형** + 스크립트 안 돌리면 틀림 |
| **② dart-define(권장)** | `--dart-define=ENV=<flavor>` → 코드가 `dotenv.load('.env.$env')` | **빌드 명령에 환경이 명시**돼 실수 없음. iOS 스크립트가 이미 이 의도(대시/코드만 미완). 단 두 env 파일 다 번들 |

②의 "두 파일 번들"은 문제 아님 — 여기 값들(`BASE_URL`·`ONESIGNAL_APP_ID`·`FACEBOOK_APP_ID`)은 **원래 클라이언트에 노출되는 공개 식별자**라 시크릿 유출이 아님(E2 심각도 낮음). 핵심은 "맞는 env를 로드"하는 정확성(E1).

## 파일 매니페스트

| 파일 | 변경 |
|---|---|
| `lib/main.dart` | `main()`에서 `const env = String.fromEnvironment('ENV', defaultValue: 'staging');` 후 `await dotenv.load(fileName: resolveEnvFileName(env));`. 선택 로직은 **순수 함수 `resolveEnvFileName(String)`로 추출**(테스트용) — 허용값 `staging`/`prod`만, 그 외엔 staging fallback |
| `.env.staging`, `.env.prod` | **전 키 채우기**(`ENV`·`BASE_URL`·`ONESIGNAL_APP_ID`·`FACEBOOK_APP_ID`) — **실제 환경값은 사용자가 입력**(시크릿/식별자 취급, 내가 값 생성 안 함). staging엔 `staging.prayu.site`/staging OneSignal, prod엔 prod 값 |
| `pubspec.yaml` | `assets`를 `.env.staging`·`.env.prod`로 정리(단일 `.env` 로드 중단). 로컬 기본은 staging |
| `scripts/*.sh` | 전 빌드/런 스크립트에 `--dart-define=ENV=<flavor>` 통일 — iOS **단일 대시 오타 수정**, android prod/staging 스크립트에 flavor 추가, `run_prod.sh`도 확인 |
| `android/app/build.gradle` | (E3) `key.properties` 없을 때 **debug 빌드는 통과**하도록 완화 — release 서명에만 요구. `throw`를 release 전용 분기로 |
| `test/env_resolve_test.dart` **(신규)** | `resolveEnvFileName` 단위 테스트(staging/prod/이상값 fallback). 기존 템플릿 `test/widget_test.dart`(카운터 예시)는 제거 또는 교체 |

## 새 빌드/실행 방법 (변경 후)

```bash
flutter run --dart-define=ENV=staging      # 로컬/시뮬 (기본 staging)
flutter build appbundle --dart-define=ENV=prod   # android prod
flutter build ios --release --dart-define=ENV=prod
```

## 검증

- **내가 자동으로:**
  1. `flutter analyze` 통과
  2. `flutter test` — `resolveEnvFileName` 단위 테스트 green
  3. **iOS 시뮬레이터 스모크**: `flutter run --dart-define=ENV=staging` → 웹뷰가 **staging `BASE_URL`을 로드**하는지 로그/스크린샷으로 확인(= E1 실제 수정 증명). `ENV=prod`로 바꿔 prod 로드 대조
- **사용자(실기기 불필요, 값 입력 필요):**
  - `.env.staging`/`.env.prod`에 실제 값 채움(특히 누락된 `FACEBOOK_APP_ID`)
- **회귀:** 앱 기동·웹뷰 로드·기존 브리지(onLogin 등) 정상, App 없는 브라우저 무관

## 리스크

- env 파일 값 누락 시 해당 env에서 기능 결함(예: `FACEBOOK_APP_ID` 없으면 인스타 공유 실패) → 값 채움이 선행.
- 빌드 명령이 바뀌므로 **CI/수동 빌드 절차 갱신** 필요(스크립트에 반영하되 사용자 숙지).
- `.env` 단일 파일에 의존하던 로컬 관습이 바뀜 → 기본 staging fallback으로 로컬 편의 유지.

## 다음 단계 결정

- 방식 **②(dart-define)** 로 확정할지, ①(스크립트 복사)을 선호하는지 — **빌드 습관이 바뀌므로 확인 필요.**
- 확정되면 구현 → `flutter analyze`/`flutter test`/시뮬 스모크까지 내가 돌리고, 값 입력만 사용자.
