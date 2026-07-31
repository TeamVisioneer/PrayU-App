# PrayU-App

PrayU 웹앱을 WebView로 감싸는 Flutter 하이브리드 셸. 상세 유지보수 가이드는 `APP_MAINTENANCE.md`·`AGENTS.md`, 워크스페이스 공통 규칙은 상위 `../CLAUDE.md` 참조.

## 작업 착수 규칙

- **docs/ 구조**: `guides/`(절차·참조) · `plans/`(진행 중 계획) · `archive/`(구현 완료 — 갱신하지 않는다). 상세: `../CLAUDE.md`
- **docs 먼저, 코드는 그 다음.** 피처/개선 작업 시작 시 코드부터 수정하지 않는다. 설계·계획 문서를 먼저 작성(또는 기존 문서 갱신)하고 방향 확인 후 구현한다.
