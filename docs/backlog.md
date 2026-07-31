# PrayU-App 백로그

이 레포(Flutter WebView 셸)에서 해야 할 일의 **원본 목록**.
세션 기록은 휘발되므로 **여기에 없으면 없는 것**이다.

관련 백로그: [PrayU-web/docs/backlog.md](../../PrayU-web/docs/backlog.md) · [PrayU-Api/docs/backlog.md](../../PrayU-Api/docs/backlog.md)

> **기록 규칙**: 작업 중 후속 이슈를 발견하면 그 자리에서 여기에 추가한다.
> 상세 설계는 별도 `docs/*-plan.md`로 만들고 여기서는 한 줄 + 링크. 완료 시 삭제하지 말고 "완료"로 옮긴다.

---

## 보류 중 (사용자 재요청 대기) — 딥링크·푸시 리다이렉트·리뷰 API

계획: [deeplink-push-review-plan.md](plans/deeplink-push-review-plan.md)

진단된 원인:
- **https 딥링크가 앱을 안 엶** — 네이티브 설정은 완비됐으나 웹에 배포된 검증 파일이 빈 상태 (`assetlinks.json`의 지문 배열 `[]`, AASA의 `details: []`)
- **콜드 스타트 URL 유실** — 푸시/딥링크 모두 `webViewController != null`일 때만 이동하고 아니면 조용히 버림
- **커스텀 스킴 파싱 버그** — `prayu://group/123`에서 `group`이 `uri.host`인데 코드는 `uri.path`만 사용
- **iOS 빌드 실패** — Apple 팀 양도 시 App Group은 이전되지 않아 새 팀이 기존 그룹 ID를 못 쓴다. 새 그룹 ID로 교체 필요

사용자 수동 단계: Play 앱 서명 SHA-256 기입, Apple 포털에 새 App Group 등록, **APNs 키 재발급 후 OneSignal 업로드**(안 하면 빌드가 성공해도 iOS 푸시 미전송)

## 확인 필요

- [ ] `viewport-fit=cover` 도입(web #464) 후 **WebView 렌더링 회귀 확인** — 상하단 잘림 없는지, 핵심 플로우(로그인·그룹·기도카드·공유) 정상인지
- [ ] 현재 작업 브랜치(`codex/support-16kb-page-size`)의 미커밋 `ios/Runner.xcodeproj/project.pbxproj` 변경(팀 ID 전환) 정리

## 완료

(아직 없음 — 이 레포는 최근 코드 변경 없음)
