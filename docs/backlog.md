# PrayU-App 백로그

이 레포(Flutter WebView 셸)에서 해야 할 일의 **원본 목록**.
세션 기록은 휘발되므로 **여기에 없으면 없는 것**이다.

관련 백로그: [PrayU-web/docs/backlog.md](../../PrayU-web/docs/backlog.md) · [PrayU-Api/docs/backlog.md](../../PrayU-Api/docs/backlog.md)

> **기록 규칙**: 작업 중 후속 이슈를 발견하면 그 자리에서 여기에 추가한다.
> 상세 설계는 별도 `docs/plans/*.md`로 만들고 여기서는 한 줄 + 링크.

---

## 🔎 코드 결함 대장 — 리팩터 준비 (2026-08-19)

대장: [guides/app-audit-ledger.md](guides/app-audit-ledger.md) — 소스 직접 정독 1차 감사(17건).

기존 셸 코드에 결함이 다수. 우선순위 로드맵:
- [ ] **R1 WebView 네비게이션 코어 재작성** (W1 onCreateWindow·W2 스킴 라우팅·W3 JS주입·W4 딥링크파싱) — 카카오 앱전환 Phase 1과 동일 토대
- [ ] **R2 환경/빌드 정합** (E1 env flavor 미배선·E2 .env 번들·E3 빌드 게이트) — 운영 안전 · 계획: [plans/r2-env-flavor.md](plans/r2-env-flavor.md)
- [ ] **R3 네이티브/설정 정리** (N1 handleIntent 크래시·N2 불필요 위치권한·N3 cleartext 등)

## ~~카카오톡 앱 전환 로그인 복원~~ — **완결 (2026-08-23): web 단독(B안)으로 해결, App 작업 불필요**

계획: [plans/kakao-app-switch-restore.md](plans/kakao-app-switch-restore.md) (보류 확정 상태로 보존)

원탭 UX 는 **web 의 세션 핸드오프 릴레이(B안)** 로 복원되어 prod 출고됨(web `v0.16.0` + Api `v1.0.0`, 2026-08-23).
**구버전 앱 WebView 포함** 전 환경에서 원탭 동작 — 실기기 검증 완료. 상세: [PrayU-web archive/kakao-login-handoff.md](../../PrayU-web/docs/archive/kakao-login-handoff.md)

- [x] ~~Phase 0 스파이크~~ — 발사 성립 확인이 B안 설계의 근거가 됨 (복귀는 릴레이로 대체)
- **C안(신버전 앱 `prayu://` 딥링크 복귀)은 불채택 확정** — Supabase 가 implicit flow 를 조일 때의 **회귀 경로로만 보존**
- App WebView 결함(`onCreateWindow` 새 창, 딥링크 W3/W4 등)은 로그인과 분리된 **품질 트랙**으로 잔존 → 아래 결함 대장 R1

## 애플 로그인 실패 (별개 이슈, 조사 중)

prod에서 애플 로그인이 "OS 승인 후 앱 무반응". 원인은 앱이 아니라 **Supabase Apple provider의 client secret(JWT) 만료 유력** — web/App 코드 무관. [web security 대장]에 갱신 절차 정리 예정.
