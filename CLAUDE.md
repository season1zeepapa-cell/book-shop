# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

온라인 서점 "북샵" — Express 5 백엔드 + React 18 프론트엔드(CDN 방식) 단일 파일 구조의 풀스택 웹 애플리케이션.
핵심 파일 2개: `server.js`(백엔드 ~1140줄), `index.html`(프론트엔드 ~2740줄).

## 개발 명령어

```bash
npm install           # 의존성 설치
node server.js        # 개발 서버 (PORT=3000)
npm run dev           # NODE_ENV=development으로 실행
pm2 start ecosystem.config.js --env production  # 프로덕션 (PORT=4000)
```

테스트 프레임워크 미설정. 변경 후 `node server.js` + `curl http://localhost:3000` 으로 수동 확인.

## 반드시 지켜야 할 규칙

### JSX 구조 검증 (화이트스크린 방지)
- **삼항 연산자 내에서 형제 요소가 2개 이상이면 반드시 `<>...</>` Fragment로 감싸기.** 누락 시 Babel 파싱 실패 → 화이트스크린.
- index.html 수정 후 반드시 `node server.js` 로컬 확인 후 push. Babel이 런타임에 JSX를 파싱하므로 빌드 타임 에러가 없음.

### 프론트엔드 CDN 제약
- 빌드 도구 없음. `<script type="text/babel">` 블록에서 React 컴포넌트 직접 작성.
- import/export 불가. 모든 컴포넌트는 같은 스크립트 블록 안에 순서대로 정의.
- Tailwind 설정은 HTML `<head>`의 `<script>` 블록에서 `tailwind.config` 객체로 정의 (별도 config 파일 없음).

### CSP (Content Security Policy)
- Helmet CSP에 `'unsafe-inline'`, `'unsafe-eval'` 필수 — Babel CDN이 런타임에 eval 사용.
- 외부 리소스(CDN, SDK) 추가 시 `server.js`의 Helmet CSP 설정에도 해당 도메인 추가 필요.

### 상품 캐시 동기화
- 상품 변경(등록/수정/삭제/시딩) 후 반드시 `refreshBooksCache()` 호출.
- `BOOKS_MAP_CACHE`는 결제 금액 검증에 사용됨 — 캐시 미갱신 시 결제 실패.

### Express 5 문법
- SPA catch-all 라우트: `/{*splat}` (Express 4의 `*`와 다름).
- 이 라우트는 반드시 모든 API 라우트 뒤에 위치해야 함.

## 아키텍처

### 백엔드 (`server.js`)

Express 5, PostgreSQL(Supabase), JWT 인증, 역할 기반 접근 제어.

**미들웨어:**
- `authenticateToken` → `req.user = { id, email, role }`
- `requireAdmin` → `authenticateToken` 후 `role === 'admin'` 확인
- `loginLimiter`(15분/5회), `paymentLimiter`(15분/10회)

**API 엔드포인트:**

| 메서드 | 경로 | 미들웨어 | 설명 |
|--------|------|----------|------|
| POST | /api/register | - | 회원가입 (비밀번호 8자+대/소/숫자/특수) |
| POST | /api/login | loginLimiter | 로그인 (JWT 7일, role 포함) |
| GET | /api/me | auth | 내 정보 조회 |
| GET | /api/books | - | 활성 상품 목록 (캐시) |
| POST | /api/payments/confirm | paymentLimiter + auth | 토스페이먼츠 결제 승인 |
| GET | /api/orders | auth | 내 주문 내역 (최대 50건) |
| GET | /api/admin/books | auth + admin | 전체 상품 (비활성 포함) |
| POST | /api/admin/books | auth + admin | 상품 등록 |
| PUT | /api/admin/books/:id | auth + admin | 상품 수정 |
| DELETE | /api/admin/books/:id | auth + admin | 상품 소프트 삭제 |
| GET | /api/admin/orders | auth + admin | 주문 관리 (페이지네이션, 상태 필터) |
| PATCH | /api/admin/orders/:id/status | auth + admin | 주문 상태 변경 |
| GET | /api/admin/books/search | auth + admin | Google Books 검색 프록시 |
| POST | /api/admin/books/seed-google | auth + admin | Google Books 50권 자동 시딩 |
| GET | /{*splat} | - | SPA 라우팅 (index.html 서빙) |

**결제 흐름:** 클라이언트 토스 SDK → `/api/payments/confirm` → `validatePaymentAmount()`(서버 캐시 가격 재검증) → 토스 API 승인

**initDB():** 서버 시작 시 테이블 자동 생성 + `ADMIN_EMAIL` 계정 관리자 승격.

### 프론트엔드 (`index.html`)

CDN: React 18 + Babel Standalone + Tailwind CSS + TossPayments SDK v2.

**라우팅:** `currentPage` state 기반 (`'home'` | `'checkout'` | `'success'` | `'fail'` | `'mypage'` | `'admin'`)

**App 컴포넌트 핵심 state:**
- `books`, `cart`(localStorage 영속), `user`(null이면 비로그인), `currentPage`
- `selectedCategory`, `searchQuery`, `visibleCount`(모바일 5 / PC 8, 5개씩 추가)
- `showLogin`, `showRegister`, `selectedBook`, `isCartOpen`, `toast`

**반응형 전략 (Tailwind `sm:` = 640px):**
- 모바일 카드 / PC 테이블: `sm:hidden` + `hidden sm:block`
- 바텀시트(모바일) / 센터 모달(PC): `items-end sm:items-center` + `rounded-t-2xl sm:rounded-2xl`
- 헤더: 모바일 2줄(로그인 시) / PC 1줄
- 상품 그리드: `grid-cols-2 sm:grid-cols-3 lg:grid-cols-4`

**CSS 애니메이션 (style 태그):**
- `slideIn`(장바구니), `slideUp`(모바일 모달), `fadeIn`(PC 모달), `overlayFadeIn`(오버레이)

**localStorage 사용:**
- `cart`: 장바구니 (결제 리다이렉트 생존용)
- `token`: JWT (자동 로그인)

### 데이터베이스 스키마

```sql
app_users (id, email, password, role DEFAULT 'user', created_at)
orders (id, user_id→app_users, order_id, payment_key, order_name, total_amount, status, method, items JSONB, payment_response JSONB, created_at, approved_at)
books (id, title, author, price, original_price, image, category, rating, description, badge, is_active DEFAULT true, created_at, updated_at)
```

주문 상태: `READY` → `DONE` → `SHIPPING` → `DELIVERED` | `CANCELED`

### 보안

- **Helmet CSP:** React/Tailwind/Babel CDN + 토스페이먼츠 도메인 허용, `unsafe-inline`/`unsafe-eval` 필수
- **SPA 서빙:** `express.static()` 미사용 → `.env`, `server.js` 노출 방지
- **결제 금액:** 서버 캐시 가격으로 재검증 후 토스 API 호출 (클라이언트 조작 방지)

### 배포

- **AWS Lightsail** (Ubuntu, ap-northeast-2) + PM2(PORT=4000) + Nginx(HTTPS 리버스 프록시)
- **도메인:** bookshop.aifac.click (Let's Encrypt SSL)
- **자동 배포:** main push → GitHub Actions → SSH → `scripts/deploy.sh` (git pull → npm install → pm2 restart → nginx reload)
- **GitHub Secrets:** `LIGHTSAIL_HOST`, `LIGHTSAIL_USERNAME`, `LIGHTSAIL_SSH_KEY`

## 환경 변수 (.env)

| 변수 | 설명 | 필수 |
|------|------|------|
| DATABASE_URL | PostgreSQL 연결 문자열 (Supabase) | O |
| JWT_SECRET | JWT 서명 비밀키 (32자+) | O |
| TOSS_SECRET_KEY | 토스페이먼츠 시크릿키 | O |
| PORT | 서버 포트 (기본 3000, 프로덕션 4000) | X |
| NODE_ENV | development / production | X |
| ADMIN_EMAIL | 자동 관리자 승격 이메일 | X |
| GOOGLE_BOOKS_API_KEY | Google Books API (상품 검색/시딩) | X |
