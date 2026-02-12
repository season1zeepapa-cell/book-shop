# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

온라인 서점 "북샵" — Express 5 백엔드 + React 18 프론트엔드(CDN 방식) 단일 파일 구조의 풀스택 웹 애플리케이션.
두 파일(`server.js`, `index.html`)에 모든 서버/클라이언트 코드가 들어있음.

## 개발 명령어

```bash
npm install           # 의존성 설치
npm start             # 서버 실행 (node server.js)
npm run dev           # 개발 모드 (NODE_ENV=development)
npm run prod          # 프로덕션 모드 (NODE_ENV=production)
pm2 start ecosystem.config.js --env production  # PM2 프로덕션 (PORT=4000)
```

**테스트** (쉘 스크립트 기반, 서버 실행 상태에서 별도 터미널 필요):
```bash
bash tests/functional-tests.sh    # API 기능 테스트
bash tests/security-tests.sh      # 보안 테스트
bash tests/performance-tests.sh   # 성능 테스트
```

## 규칙

- **단일 파일 구조 유지**: `server.js`(백엔드 전체)와 `index.html`(프론트엔드 전체)로 분리. 새 파일 생성 지양.
- **대용량 파일 주의**: `server.js`(~1,265줄), `index.html`(~3,010줄). 수정 시 정확한 위치 확인 필수.
- **CDN 추가 시 CSP 업데이트**: 새 외부 라이브러리 CDN 추가 시 `server.js`의 Helmet CSP 설정(~130행)도 함께 수정.
- **상품 캐시 갱신**: 상품 데이터 변경 API 추가/수정 시 `refreshBooksCache()` 호출 필수.
- **SPA 라우팅**: `express.static()` 미사용. 파일 서빙은 `/{*splat}` 캐치올 라우트로 `index.html`만 전달.
- **Google Books 이미지 URL**: 안정 형식 사용 필수 — `https://books.google.com/books/publisher/content/images/frontcover/{BOOK_ID}?fife=w400-h600` (기존 `/books/content?id=...` 형식은 시간 경과 시 만료됨)

## 아키텍처

### 백엔드 (`server.js`) — 코드 영역 가이드

| 영역 | 대략적 위치 | 설명 |
|------|-------------|------|
| 환경변수 검증 | ~1-48행 | 필수 변수 확인, JWT_SECRET 32자 검증 |
| 비밀번호 강도 검증 | ~51-76행 | `validatePassword()` — 8자+대/소/숫자/특수 |
| 모듈 import | ~78-87행 | express, pg, bcrypt, jwt, helmet 등 |
| 상품 캐시 시스템 | ~100-113행 | `BOOKS_CACHE`, `BOOKS_MAP_CACHE`, `refreshBooksCache()` |
| Helmet CSP 설정 | ~130-170행 | CDN 허용 목록 (새 CDN 추가 시 여기 수정) |
| Rate Limiter | ~172-184행 | `loginLimiter`(15분/5회), `paymentLimiter`(15분/10회) |
| DB 연결/초기화 | ~190-302행 | PostgreSQL Pool, `initDB()` 테이블 자동 생성 |
| JWT 미들웨어 | ~311-344행 | `authenticateToken`, `requireAdmin` |
| 결제 금액 검증 | ~359-413행 | `validatePaymentAmount()` — 배송비: 3만원 이상 무료, 미만 3,000원 |
| API 엔드포인트 | ~420-1251행 | 전체 REST API (아래 표 참고) |
| SPA 캐치올 라우트 | ~1251행 | `/{*splat}` → index.html 서빙 |
| 서버 시작 | ~1258-1265행 | `initDB()` → `app.listen(PORT)` |

**미들웨어 체인:**
- `authenticateToken` — JWT 검증 → `req.user = { id, email, role }`
- `requireAdmin` — `authenticateToken` 후 `role === 'admin'` 확인

**API 엔드포인트:**

| 메서드 | 경로 | 미들웨어 | 설명 |
|--------|------|----------|------|
| POST | /api/register | - | 회원가입 (비밀번호 8자+대/소/숫자/특수) |
| POST | /api/login | loginLimiter | 로그인 (JWT 7일 만료, role 포함) |
| GET | /api/me | auth | 내 정보 조회 |
| PUT | /api/me/password | auth | 비밀번호 변경 (현재 비밀번호 확인) |
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
| POST | /api/admin/books/refresh-images | auth + admin | 이미지 URL을 안정 형식으로 일괄 변환 |
| GET | /{*splat} | - | SPA 라우팅 (index.html 서빙) |

**결제 보안:** `validatePaymentAmount()` — 서버 캐시 가격으로 금액 재검증 후 토스 API 호출. 배송비 로직: 총액 30,000원 이상 무료, 미만 시 3,000원 추가.

**initDB():** 서버 시작 시 `app_users`, `orders`, `books` 테이블 자동 생성 + `ADMIN_EMAIL` 계정 관리자 승격.

### 프론트엔드 (`index.html`)

빌드 도구 없이 CDN(React 18 + Babel + Tailwind CSS + TossPayments SDK v2) 로드.
`<script type="text/babel">`로 모든 React 컴포넌트 작성.

**페이지 라우팅:** `currentPage` state 기반
- `'home'` — 메인 (기본)
- `'checkout'` — 결제
- `'success'` / `'fail'` — 결제 결과
- `'mypage'` — 마이페이지 (로그인 필요)
- `'admin'` — 관리자 페이지 (role='admin' 필요)

**주요 컴포넌트:**
- `HeroSection` — 최근 등록 5권 자동 롤링 배너 (3.5초)
- `BookCard` / `StarRating` — 상품 카드 + 별점
- `CartPanel` — 장바구니 슬라이드 패널
- `BookDetail` — 상품 상세 모달
- `LoginModal` / `RegisterModal` — 인증 (비밀번호 강도 실시간 표시)
- `CheckoutPage` / `SuccessPage` / `FailPage` — 결제 흐름
- `MyPage` — 일반 회원 주문 내역 (상태 필터, 주문 상세 펼침)
- `AdminPage` → `AdminBooks` + `AdminOrders` — 관리자 탭
- `BookFormModal` — 상품 등록/수정 폼 (Google Books 검색 자동 채우기)

**상품 더보기:** `visibleCount` state. 모바일 5개 / PC(640px+) 8개 기본, 5개씩 추가.

**Tailwind 커스텀 색상:** `primary`(#2563eb), `secondary`(#f59e0b), `accent`(#10b981)

**이미지 처리:** `getBookImage()` 함수가 Google Books 기존 URL을 안정 형식으로 자동 변환. `handleImgError()`로 실패 시 SVG 플레이스홀더 표시.

### 데이터베이스 스키마

```sql
app_users (id, email, password, role DEFAULT 'user', created_at)
orders (id, user_id→app_users, order_id, payment_key, order_name, total_amount, status, method, items JSONB, payment_response JSONB, created_at, approved_at)
books (id, title, author, price, original_price, image, category, rating, description, badge, is_active DEFAULT true, created_at, updated_at)
```

주문 상태: `READY` → `DONE` → `SHIPPING` → `DELIVERED` | `CANCELED`

### 보안

- **Helmet:** CSP에 React/Tailwind/Babel CDN + 토스페이먼츠 허용
- **Rate Limiting:** 로그인 15분/5회, 결제 15분/10회
- **Trust Proxy:** `app.set('trust proxy', 1)` (Nginx 리버스 프록시)
- **SPA 서빙:** `express.static()` 미사용 — `.env`, `server.js` 노출 방지
- **Google Books API 키:** 서버 프록시로만 사용 (클라이언트 노출 방지)

### 배포

- **AWS Lightsail** (Ubuntu, ap-northeast-2) + PM2 + Nginx(HTTPS 리버스 프록시)
- **도메인:** bookshop.aifac.click (Let's Encrypt SSL)
- **GitHub Actions:** main push → SSH → `scripts/deploy.sh`
- **GitHub Secrets:** `LIGHTSAIL_HOST`, `LIGHTSAIL_USERNAME`, `LIGHTSAIL_SSH_KEY`
- **Nginx 설정:** `nginx/bookshop.conf` — deploy.sh에서 매 배포 시 자동 동기화
- **서버 경로:** `/home/ubuntu/book-shop`

**배포 흐름:** `git push main` → GitHub Actions → SSH → `deploy.sh` (git pull → npm install --production → pm2 restart → nginx 설정 동기화 → 헬스체크)

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
