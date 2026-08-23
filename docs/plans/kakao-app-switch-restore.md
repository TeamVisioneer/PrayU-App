# 카카오톡 앱 전환 로그인 복원 (web 원탭 발사 + App WebView 스킴 처리)

> 상태: **보류 — B안(세션 핸드오프 릴레이)으로 방향 확정** (2026-08-22). 앱 업데이트 없이 해결하기로 사용자 결정 →
> 구현은 [PrayU-web/docs/plans/kakao-login-handoff.md](../../../PrayU-web/docs/plans/kakao-login-handoff.md) 로 진행.
> 이 문서의 C안(PKCE+`prayu://`+신버전 앱)은 **B 실패 시 회귀 경로**로 보존. App 결함(W1 등)은 품질 트랙(R1~R3, 결함 대장)으로 분리.
> (이전 상태: 설계·스코프 2026-08-19 · 목표 격상 2026-08-22)
> 관련: web [docs/plans/kakao-oauth-migration.md](../../../PrayU-web/docs/plans/kakao-oauth-migration.md) (signInWithOAuth 전환, prod v0.15.2 배포됨)

## 목표 확정 (2026-08-22 사용자 결정)

**"우리 로그인 버튼 원탭 → 카카오톡 앱 → 자동 복귀"** 가 목표다. 카카오 웹 로그인 페이지 안의
"카카오톡으로 로그인" 버튼에 기대는 안(추가 탭 1회)은 **최종 상태로 불채택** — 사용자에게 낯선 화면이다. 단 폴백으론 유지.

**주 접근 (원탭)**: web `KakaoLoginBtn`에서
`signInWithOAuth({ options: { skipBrowserRedirect: true } })` 로 **Supabase가 생성한 authorize URL(state 포함)만 획득**
→ 그 URL을 카카오톡 앱 스킴(iOS `kakaokompassauth://` 계열 / Android `intent://`)으로 감싸 직접 발사
→ 카카오톡 승인 → code+state 가 Supabase 콜백으로 → 표준 OAuth 완결. (예전 JS SDK `throughTalk` 가 하던 일을 Supabase authorize URL 로 재현하는 것 — id_token 차단과 무관한 합법 경로)
카카오톡 미설치·데스크탑·발사 실패 시 기존 웹 리다이렉트로 폴백.

이 로직은 **web 코드**에 위치하므로 앱 WebView 뿐 아니라 **일반 모바일 브라우저 사용자도 원탭 혜택**을 받는다.
→ 이 계획은 **web 짝 PR**(KakaoLoginBtn 발사 로직)이 추가로 필요해졌다. App 쪽(스킴 통과·onCreateWindow·복귀)은 기존 스코프 유지.

**Phase 0 스파이크 검증 항목(갱신)**: ① Supabase authorize URL 을 스킴에 실어 카카오톡이 정상 처리하는지(발사)
② 승인 후 리다이렉트 체인이 어디에 열리는지 — 시스템 브라우저로 새는지, `*.prayu.site` 유니버설 링크/앱 링크로 **우리 앱 복귀가 실제 발화하는지**(복귀 — 최대 리스크)
③ 일반 모바일 브라우저(사파리/크롬)에서도 동일 발사·복귀가 성립하는지

## 발사 메커니즘 조사 결과 (2026-08-22, kakao.min.js 2.7.2 소스 분석)

SDK `throughTalk` 의 실체 (`t1.kakaocdn.net/kakao_js_sdk/2.7.2` 직접 분석):

- **iOS**: `https://talk-apps.kakao.com/scheme/<encodeURIComponent(스킴URL)>&web=<encodeURIComponent(웹폴백URL)>` — **유니버설 링크**로 카카오톡을 연다 (커스텀 스킴의 WKWebView 제약 회피)
- **Android**: `intent://...` URI 를 `top.location.href` 로 발사 (크롬/웹뷰 판별 후) — **우리 앱 셸의 기존 `intent:` 핸들러가 받는 형식**
- 톡 미설치/미지원 환경(인스타·FB 인앱브라우저 등) 판별과 웹 폴백이 SDK 안에 내장돼 있음
- ⚠️ 미확정: 미니파이 코드라 **로그인용 스킴 본체의 정확한 포맷**(예: `kakaotalk://capri/...`)은 미추출 — 스파이크에서 실기기 로깅으로 캡처하거나 비압축 SDK 소스로 확정

**핵심 제약 (설계에 반영)**: Supabase `signInWithOAuth({skipBrowserRedirect:true})` 가 주는 URL 은 **Supabase `/authorize`** 이고,
kauth URL 로의 302 는 cross-origin redirect 라 **클라이언트에서 읽을 수 없다**. state 는 GoTrue 서명이라 자체 조립도 불가.
→ 스킴에 실을 수 있는 건 Supabase authorize URL 뿐이며, **카카오톡이 그걸 내부 웹뷰에서 열어 302 를 따라가 주는지**가 성립 조건 (스파이크 ①).
불성립 시 폴백: 카카오 웹 페이지 경유(현행) + App 에서 그 페이지의 톡 버튼을 살리는 원안(스킴 통과·onCreateWindow)으로 축소.

## 최종 설계 (2026-08-22 스파이크 결과 반영 — 확정)

**Phase 0 스파이크 결과**: ① 발사 성립(카카오톡이 inappbrowser 스킴의 Supabase URL 수용, 인증 완결) ② **복귀 실패** —
체인이 카카오톡 인앱브라우저 안에서 끝나고 세션도 거기 생김(implicit fragment 특성) ③ 유니버설 링크는 302 체인에서 미발화.

**전제(사용자 결정)**: 구버전 앱 사용자에게 업데이트를 강제할 수 없다 — **구버전은 현행 동작 그대로 무손상**이어야 한다.

### 구 흐름이 복귀됐던 원리의 재현

구 JS SDK 흐름의 복귀 성공 요인 = (1) 우리 도메인 콜백 (2) **`?code=` 쿼리 운반**(딥링크에서 생존) (3) 앱이 수신해 WebView 전달.
(1)은 필수 아님(최종 redirectTo 는 우리 통제) → **(2)+(3)을 Supabase 문법으로 재현**한다:

- **(2) = PKCE 전환** (`supabase/client.ts` `flowType: 'pkce'`): 토큰 프래그먼트 대신 `?code=` 쿼리로 복귀.
  code→세션 교환은 시작 컨텍스트의 code_verifier 필요 → "앱에서 시작→앱에서 완료"와 정합. 전역 설정이라 애플/이메일 포함 전 로그인 검증 필요
- **(3) = `prayu://login-redirect?code=` 복귀** + 신버전 앱의 딥링크 핸들러가 host·query 보존해 WebView 전달.
  커스텀 스킴은 302 체인에서도 유니버설 링크보다 발화 확실

### 컨텍스트별 최종 동작 (게이팅 매트릭스)

| 컨텍스트 | 발사 | redirectTo | 복귀 | 비고 |
|---|---|---|---|---|
| **신버전 앱** (UA 마커 `prayu-dl2`) | 톡 원탭 발사 | `prayu://login-redirect?...` | 카카오톡 → OS → 앱 → WebView `?code` 교환 | 원탭 완성 |
| **구버전 앱** | 안 함 (게이팅) | `https://<도메인>/login-redirect` | 같은 WebView 내 완결 | **현행 그대로 — 무손상** |
| 모바일 브라우저 | 안 함 (스파이크 (b) 회귀 방지) | https | kauth 페이지(카카오 톡버튼=폴링 복귀) → 같은 브라우저 | 카카오 표준 UX |
| 데스크탑 | 안 함 | https | 동일 | 현행 |

게이팅 근거: 구버전 앱 딥링크 핸들러는 `prayu://login-redirect` 의 **host 를 버리는 결함(W4)** 이 있어 `prayu://` 복귀를 처리
못 한다 — 마커 게이팅은 안전장치가 아니라 필수. 신버전 앱이 마커를 달고 나오면 web 재배포 없이 원탭이 자동 활성화된다.

### 전달 순서 (PR)

1. **PR A — web (즉시)**: ① `flowType: 'pkce'` ② 발사 게이팅을 `UA.includes("prayu-dl2")` 로 축소(현존 사용자 전원 = 웹 플로우 복원
   → 스파이크 (b) 상태가 prod 로 가는 것 차단) ③ `kakaoTalkLaunch` 유틸은 잔존(마커 등장 시 활성). staging 에서 카카오/애플/이메일 전 로그인 검증
2. **PR B — App**: 딥링크 핸들러 재작성(host+query(+fragment) 보존 — W4·W3 해소) · UA 마커 `prayu-dl2` 를 **initialSettings 에**(B1 레이스 해소) ·
   (같은 PR 권장) `onCreateWindow`(W1). 발사 자체는 앱 코드 불요 — iOS 유니버설 링크·Android `intent:` 기존 경로로 동작
3. **App 릴리스 후**: web 변경 없이 신버전 사용자부터 원탭 — 점진 활성화
- 선행 확인(대시보드): staging/prod Supabase Redirect URLs 에 `prayu://*` (prod 는 확인됨, staging 추가 필요)

## web 단계 파일 매니페스트 (1차 발사 구현 — [PrayU-Web#511](https://github.com/TeamVisioneer/PrayU-Web/pull/511) merge, staging)

> #511 은 스파이크용 1차 구현(전 모바일 발사)이다. 스파이크 (b) 결과로 **PR A(게이팅+PKCE)가 이 상태를 덮어야 prod 가능** — 위 "전달 순서" 참조.
> PR A 변경: `supabase/client.ts`(flowType pkce) · `kakaoTalkLaunch.ts`(`canLaunchKakaoTalk` 를 마커 게이팅으로) — KakaoLoginBtn 은 무변경.
> PR B 변경(App): `lib/main.dart` `_handleDeepLink`(host+query 보존) · `_performWebViewNavigation`(이스케이프, W3) · UA 마커 initialSettings(B1) · `onCreateWindow`(W1).

| 파일 | 내용 |
|---|---|
| `src/lib/kakaoTalkLaunch.ts` (신규) | 순수 함수 모음: `canLaunchKakaoTalk()`(모바일 OS + 미지원 인앱브라우저 제외 판별) · `buildTalkLaunchUrl(authorizeUrl, webFallbackUrl)`(iOS 유니버설 링크 / Android intent URI 조립 — SDK 포맷 재현). 스킴 포맷은 스파이크 확정값으로 채움 |
| `src/components/auth/KakaoLoginBtn.tsx` | `canLaunchKakaoTalk()` 이면 `signInWithOAuth({options:{skipBrowserRedirect:true}})` 로 URL 획득 → `buildTalkLaunchUrl` 발사. 아니면/실패 시 **현행 그대로 웹 리다이렉트** (회귀 없음). analytics: 발사/폴백 구분 이벤트 |
| `src/components/kakao/Kakao.d.ts` | 변경 없음(JS SDK 로그인 API 미사용 — 공유는 기존대로) |

- merge 순서: **web 먼저**(폴백 내장이라 단독 배포 안전 — Android 앱·모바일 브라우저는 즉시 혜택 가능성) → App(iOS 스킴·onCreateWindow·복귀)은 최종
- 검증: 실기기 없이는 불가 — staging(web main merge) + 실기기 dev 빌드로 Phase 0 와 함께 검증

## 왜 지금 하나

2026-08-19, Supabase가 `signInWithIdToken`(kakao id_token grant)을 차단해 web 카카오 로그인을 **`signInWithOAuth`(서버사이드 웹 OAuth)** 로 전환했다. 그 결과 앱 WebView에서:

1. **카카오톡 앱 전환(간편로그인) UX가 사라짐** — 기존엔 카카오 JS SDK(`throughTalk`)가 카카오톡 앱으로 넘겨 원탭 로그인이 됐는데, 이제 Kakao **웹 authorize 페이지**에 머문다. Supabase Kakao OAuth는 **웹 로그인 전용**이라, 앱 전환은 **App WebView가 카카오 앱 스킴을 직접 처리**해야만 산다.
2. **'새 창'으로 뜸** (사용자 보고) — 아래 `onCreateWindow` 미구현이 직접 원인.

기존의 "카카오톡 네이티브 로그인 → id_token → `signInWithIdToken`" 경로는 **Supabase가 막은 그 경로**라 되돌릴 수 없다. 그래서 복원은 App WebView 레이어에서 한다.

## 현재 코드 (조사 완료)

| 지점 | 현재 상태 |
|---|---|
| `lib/main.dart:186-496` InAppWebView | `supportMultipleWindows: true` + `javaScriptCanOpenWindowsAutomatically: true` 인데 **`onCreateWindow` 미구현** → 팝업/`target=_blank`/`window.open` 처리 안 됨(= '새 창' 증상). 새 창에선 `shouldOverrideUrlLoading`도 안 걸려 스킴 분기 자체가 무력화 |
| `lib/main.dart:518-539` `_shouldOverrideUrlLoading` | **`intent:` 스킴만** 분기(Android `MethodChannel handleIntent` → `Intent.parseUri`). 그 외 스킴(`kakaotalk`/`kakaokompassauth`/`kakaolink`/`kakaoplus`)은 `ALLOW`로 흘러 WebView가 못 열고 실패. **iOS는 스킴 처리 전무**(MethodChannel Android 전용, AppDelegate 비어있음) |
| `pubspec.yaml:17` `url_launcher: 6.3.1` | 의존성 존재하나 **코드 사용 0** → iOS/Android 공통 `launchUrl(externalApplication)`로 즉시 재사용 가능 |
| `AndroidManifest.xml:106-127` `<queries>` / `Info.plist:59-63` `LSApplicationQueriesSchemes` | `com.kakao.talk` + `kakaokompassauth`/`kakaolink`/`kakaoplus` 등록됨 → 앱 설치확인·오픈 권한 확보. (`kakaotalk` 스킴은 iOS query 목록에 없음 — 실제 사용 시 추가 검토) |
| `lib/main.dart:73-123` `_handleDeepLink` / `:541-550` `_performWebViewNavigation` | `app_links` + `prayu://` 커스텀 스킴 + `*.prayu.site` Universal/App Links 복귀 인프라 **완비** → 로그인 후 복귀에 재사용 가능 |

## 핵심 불확실성 — Phase 0에서 먼저 판정

스킴으로 카카오톡을 **여는 것**은 쉽다(url_launcher). 관건은 **카카오톡 승인 후 OAuth 흐름이 우리 앱 WebView로 복귀**하느냐다:

- 카카오톡이 승인 후 kauth 계속 흐름 → Supabase 콜백 → `redirectTo` 로 이어질 때, 그 복귀가 **시스템 브라우저로 새면 흐름이 깨진다.**
- 복귀를 우리 앱으로 붙잡으려면 `redirectTo`를 `prayu://` 또는 `https://*.prayu.site`(둘 다 앱이 이미 캡처)로 잡아야 할 수 있고, 이는 **web/Supabase redirect 설정에도 영향**을 준다.

→ **실기기 스파이크로 성립 여부를 먼저 확인**하고 Phase 1 설계를 확정한다. 성립 안 하면 대안(웹 로그인 유지 + `onCreateWindow`만 수리)으로 축소.

## 단계

### Phase 0 — 타당성 스파이크 (선행 필수, 코드 최소)
- 실기기 iOS/Android에서: Kakao 웹 authorize의 "카카오톡으로 로그인" → `kakaokompassauth://` 를 `url_launcher(externalApplication)`로 오픈 → 카카오톡 승인 → **복귀가 우리 WebView로 이어져 세션까지 생성되는지** 확인.
- `redirectTo`를 (a) 현행 https(`*.prayu.site/login-redirect`) vs (b) `prayu://` 딥링크로 바꿨을 때 각각 복귀가 성립하는지 비교.
- 산출물: "성립/조건/불성립" 판정 → Phase 1 확정.

### Phase 1 — WebView 스킴 + 새 창 처리 (main.dart 중심)

| 파일 | 변경 |
|---|---|
| `lib/main.dart` `_shouldOverrideUrlLoading` | `intent:` 외에 `kakaotalk`/`kakaokompassauth`/`kakaolink`/`kakaoplus`(+선택 `tel`/`mailto`) 감지 → `launchUrl(uri, mode: LaunchMode.externalApplication)` 후 `NavigationActionPolicy.CANCEL`. iOS/Android 공통 `url_launcher`로 통일(순수 커스텀 스킴은 `Intent.parseUri` 부적합) |
| `lib/main.dart` `onCreateWindow` **(신규)** | 새 창 첫 요청 URL 가로채기: 스킴이면 앱 오픈 후 창 취소, http(s)면 메인 `controller.loadUrl`로 흡수. 필요시 `onCloseWindow`. **'새 창' 증상 해소의 핵심** |
| `ios/Runner/Info.plist` `LSApplicationQueriesSchemes` | 실제 `kakaotalk://` 스킴을 쓰게 되면 `kakaotalk` 추가 검토 |
| (web/Supabase, 선택) `redirectTo` | Phase 0 결과에 따라 앱 컨텍스트에서 `prayu://`/`*.prayu.site` 복귀로 분기. web `KakaoLoginBtn`에 App 감지 분기가 필요할 수 있음 → 그때 web 짝 작업 |

### Phase 2 — 복귀/세션 연속성
- 앱 전환→복귀 시 WebView 세션/쿠키 반영 확인(`thirdPartyCookiesEnabled`/`sharedCookiesEnabled` 이미 true). 필요시 `didChangeAppLifecycleState` resume 시 재확인/리로드(현재는 OneSignal clear만).

## 리스크

- **`onCreateWindow` 미구현이 전제 결함** — 이걸 안 넣으면 스킴 분기를 확장해도 새 창 컨텍스트에서 안 걸릴 수 있음. (이것만으로도 '새 창' 증상은 독립적으로 수리 가치 있음)
- **KakaoTalk 복귀가 시스템 브라우저로 샐 위험** → Phase 0에서 판정. 이게 최대 불확실성.
- **iOS 커스텀 스킴 확인 팝업 vs Universal Link** — `prayu://`는 구현 간단하나 "앱에서 열까요" 팝업, `*.prayu.site` Universal Link는 매끄러우나 apple-app-site-association 서버 검증 의존(associated-domains는 이미 설정됨).
- **web 짝 영향** — `redirectTo`를 앱용으로 분기하면 web 코드 소폭 변경 → App·web 짝 작업 필요(App 먼저 검증 후 web 반영).
- **App 없는 브라우저 환경 회귀 금지** — 스킴 분기는 App WebView 전용 경로라 브라우저엔 영향 없음(확인).

## 검증 (end-to-end)

1. 실기기 iOS/Android: 카카오 로그인 → **카카오톡 앱 전환** → 승인 → **앱으로 복귀 + 세션 생성**.
2. 카카오톡 **미설치** 기기: 웹 로그인으로 폴백 정상.
3. '새 창으로 뜸' 증상 해소 확인.
4. 비앱(모바일 브라우저) 회귀 없음.

## 관련 문서

- web: [kakao-oauth-migration.md](../../../PrayU-web/docs/plans/kakao-oauth-migration.md) — signInWithOAuth 전환(원인·prod v0.15.1)
- App 유지보수: [../../APP_MAINTENANCE.md](../../APP_MAINTENANCE.md)
