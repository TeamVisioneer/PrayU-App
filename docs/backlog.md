# PrayU-App 백로그

이 레포(Flutter WebView 셸)에서 해야 할 일의 **원본 목록**.
세션 기록은 휘발되므로 **여기에 없으면 없는 것**이다.

관련 백로그: [PrayU-web/docs/backlog.md](../../PrayU-web/docs/backlog.md) · [PrayU-Api/docs/backlog.md](../../PrayU-Api/docs/backlog.md)

> **기록 규칙**: 작업 중 후속 이슈를 발견하면 그 자리에서 여기에 추가한다.
> 상세 설계는 별도 `docs/plans/*.md`로 만들고 여기서는 한 줄 + 링크. 완료 시 삭제하지 말고 "완료"로 옮긴다.

---

## 🔎 코드 결함 대장 — 리팩터 준비 (2026-08-19)

대장: [guides/app-audit-ledger.md](guides/app-audit-ledger.md) — 소스 직접 정독 1차 감사(21건) + 브리지 전수 인벤토리.

기존 셸 코드에 결함이 다수. 우선순위 로드맵:
- [ ] **R1 WebView 내비게이션 코어 재작성** (W1 onCreateWindow·W2 스킴 라우팅·W3 JS주입·W4 딥링크 파싱) —
  W3·W4 는 아래 "딥링크·푸시" 계획의 진단과 **같은 결함**이다 (두 경로로 교차 확인됨). 두 트랙을 묶어 한 PR 로 잡는 것 권장
- [ ] **R2 환경/빌드 정합** (E1 env flavor 미배선·E2 .env 번들·E3 빌드 게이트) — 운영 안전 · 계획: [plans/r2-env-flavor.md](plans/r2-env-flavor.md)
- [ ] **R3 네이티브/기능/설정 정리** (N1 handleIntent 크래시·N2 불필요 위치권한·N3 cleartext·S1 인스타 공유·S2 리뷰·B1 UA 레이스·D1 죽은 코드)

## 보류 중 (사용자 재요청 대기) — 딥링크·푸시 리다이렉트·리뷰 API

계획: [deeplink-push-review-plan.md](plans/deeplink-push-review-plan.md)

진단된 원인:
- **https 딥링크가 앱을 안 엶** — 네이티브 설정은 완비됐으나 웹에 배포된 검증 파일이 빈 상태 (`assetlinks.json`의 지문 배열 `[]`, AASA의 `details: []`)
  · 참고: 이 빈 검증 파일이 카카오 원탭 스파이크(2026-08-22)에서 **유니버설 링크 미발화**의 원인이었을 가능성이 높다
- **콜드 스타트 URL 유실** — 푸시/딥링크 모두 `webViewController != null`일 때만 이동하고 아니면 조용히 버림
- **커스텀 스킴 파싱 버그** — `prayu://group/123`에서 `group`이 `uri.host`인데 코드는 `uri.path`만 사용 (= 결함 대장 **W4**)
- **iOS 빌드 실패** — Apple 팀 양도 시 App Group은 이전되지 않아 새 팀이 기존 그룹 ID를 못 쓴다. 새 그룹 ID로 교체 필요

사용자 수동 단계: Play 앱 서명 SHA-256 기입, Apple 포털에 새 App Group 등록, **APNs 키 재발급 후 OneSignal 업로드**(안 하면 빌드가 성공해도 iOS 푸시 미전송)

## 확인 필요

- [ ] 🔴 **Android 개발자 인증 등록 확인 (Play Console 얼러트, 기한 2026-09-30)** — Google 의 새 요구사항: 패키지명·서명 키가 개발자 계정에 등록돼야 한다.
  PrayU 는 **Play 앱 서명(Google 관리 키) 사용 + Play 외부 배포 없음**(2026-09-07 코드 실측: APK 링크 0건)이라 **자동 등록 대상(99%)** 일 가능성이 높다 — 그래도 눈으로 확인한다.
  사람 작업: Play Console 홈 → "Android 개발자 인증" 페이지 → `com.team.visioneer.prayu` 옆 상태가 **등록됨**인지 확인 → 아니면 그 자리에서 등록.
  참고: 로컬 `key.jks` 는 **업로드 키**라 Play 배포만 하면 추가 등록 불필요(앱 서명 키는 Google 이 자동 등록). 외부 배포(APK 직접 배포·타 스토어)를 시작할 때만 그 서명 키를 추가 등록.
  9/30 강제는 브라질·인니·싱가포르·태국 참여 스토어부터, 전 세계는 2027~ — 한국 사용자 즉시 영향은 없으나 Play 삭제 경고 문구가 있으니 기한 전 확인.
  근거: https://developer.android.com/developer-verification/guides/faq (2026-07-15 갱신)
- [ ] `viewport-fit=cover` 도입(web #464) 후 **WebView 렌더링 회귀 확인** — 상하단 잘림 없는지, 핵심 플로우(로그인·그룹·기도카드·공유) 정상인지
- [ ] 현재 작업 브랜치(`codex/support-16kb-page-size`)의 미커밋 `ios/Runner.xcodeproj/project.pbxproj` 변경(팀 ID 전환) 정리

## 완료

### ~~카카오톡 앱 전환 로그인 복원~~ — 2026-08-23, web 단독(B안)으로 해결. App 작업 불필요

계획: [plans/kakao-app-switch-restore.md](plans/kakao-app-switch-restore.md) (보류 확정 상태로 보존)

원탭 UX 는 **web 의 세션 핸드오프 릴레이(B안)** 로 복원되어 prod 출고됨(web `v0.16.0` + Api `v1.0.0`).
**구버전 앱 WebView 포함** 전 환경에서 원탭 동작 — 실기기 검증 완료. 상세: [PrayU-web archive/kakao-login-handoff.md](../../PrayU-web/docs/archive/kakao-login-handoff.md)

- **C안(신버전 앱 `prayu://` 딥링크 복귀)은 불채택 확정** — Supabase 가 implicit flow 를 조일 때의 **회귀 경로로만 보존**
- App WebView 결함(`onCreateWindow` 새 창, 딥링크 W3/W4 등)은 로그인과 분리된 품질 트랙(위 결함 대장 R1)으로 잔존

### ~~애플 로그인 prod 장애~~ — 2026-08-22 복구 (App 무관: Supabase Apple client secret 만료)

secret 재발급·교체로 해소. 다음 만료 2027-02-18. 상세: [PrayU-web archive/2026-08-auth-incident-retrospective.md](../../PrayU-web/docs/archive/2026-08-auth-incident-retrospective.md)
