# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

온라인 서점 "북샵" — Express 5 백엔드 + React 18 프론트엔드(CDN 방식) 단일 파일 구조의 풀스택 웹 애플리케이션.

## 개발 명령어

```bash
# 서버 실행 (개발, 포트 3000)
node server.js

# 프로덕션 실행 (PM2, 포트 4000)
pm2 start ecosystem.config.js --env production

# 의존성 설치
npm install
```

테스트 프레임워크는 아직 설정되어 있지 않음.

## 아키텍처

두 파일(`server.js`, `index.html`)로 구성된 단일 파일 풀스택 구조.

### 백엔드 (`server.js`)
- Express 5 서버, 포트는 `process.env.PORT || 3000` (프로덕션 PM2: 4000)
- PostgreSQL(Supabase) 연결 — `pg` Pool, SSL 필수 (`rejectUnauthorized: false`)
- JWT 인증: `authenticateToken` 미들웨어로 보호 API 접근 제어
- API 엔드포인트:
  - `POST /api/register` — 회원가입 (bcrypt 해싱, 비밀번호 6자 이상)
  - `POST /api/login` — 로그인 (JWT 발급, 7일 만료)
  - `GET /api/me` — 내 정보 조회 (인증 필요)
  - `POST /api/payments/confirm` — 토스페이먼츠 결제 승인 (인증 필요, 토스 API 호출 + DB 저장)
  - `GET /api/orders` — 주문 내역 조회 (인증 필요, 최신순 50건)
- SPA 라우팅: `GET /{*splat}` 와일드카드로 `index.html` 서빙 (static 미들웨어 미사용 — `.env`, `server.js` 노출 방지 목적)
- 서버 시작 시 `initDB()`로 `app_users`, `orders` 테이블 자동 생성 (CREATE TABLE IF NOT EXISTS)
- 토스페이먼츠 결제: 시크릿키 Basic Auth 인코딩, confirm API로 결제 승인

### 프론트엔드 (`index.html`)
- 빌드 도구 없이 CDN으로 React 18 + Babel + Tailwind CSS 로드
- 단일 HTML 파일 안에 `<script type="text/babel">`로 모든 React 컴포넌트 작성
- 책 데이터(`BOOKS`)는 클라이언트 하드코딩 (서버 API 아님)
- 주요 컴포넌트: `App`, `BookCard`, `CartPanel`, `CheckoutPage`, `SuccessPage`, `FailPage`, `BookDetail`, `LoginModal`, `RegisterModal`, `StarRating`
- 토스페이먼츠 SDK v2 (`/v2/standard`) CDN 로드, 결제 위젯으로 결제 수단 선택 + 약관 동의 처리
- SPA 라우팅: `currentPage` state로 home/checkout/success/fail 페이지 전환
- Tailwind 커스텀 색상: `primary`(#2563eb), `secondary`(#f59e0b), `accent`(#10b981)

### 데이터베이스 스키마
```sql
app_users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,        -- bcrypt 해시
  created_at TIMESTAMP DEFAULT NOW()
)

orders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES app_users(id),
  order_id VARCHAR(255) UNIQUE NOT NULL, -- 프론트엔드 생성 주문 ID
  payment_key VARCHAR(255) UNIQUE,       -- 토스페이먼츠 결제 키
  order_name VARCHAR(500) NOT NULL,
  total_amount INTEGER NOT NULL,
  status VARCHAR(50) DEFAULT 'READY',    -- READY, DONE, CANCELED
  method VARCHAR(100),                   -- 카드, 계좌이체 등
  items JSONB DEFAULT '[]',              -- 주문 상품 목록
  payment_response JSONB,                -- 토스 API 응답 원본
  created_at TIMESTAMP DEFAULT NOW(),
  approved_at TIMESTAMP
)
```

### 배포
- AWS Lightsail (Ubuntu 24.04, ap-northeast-2), PM2 프로세스 매니저 사용
- 인스턴스 경로: `/home/ubuntu/book-shop`
- GitHub Actions: main 브랜치 push 시 SSH로 자동 배포 (`scripts/deploy.sh`)
- 배포 흐름: `git pull` → `npm install --production` → `pm2 restart`
- 필요한 GitHub Secrets: `LIGHTSAIL_HOST`, `LIGHTSAIL_USERNAME`, `LIGHTSAIL_SSH_KEY`
- 방화벽 개방 포트: 22(SSH), 80(HTTP), 4000(앱)

## 환경 변수 (.env)

- `DATABASE_URL` — PostgreSQL 연결 문자열 (Supabase pooler)
- `JWT_SECRET` — JWT 서명 비밀키
- `PORT` — 서버 포트 (선택, 기본 3000, 프로덕션 4000)
- `TOSS_SECRET_KEY` — 토스페이먼츠 시크릿키 (결제 승인 API 인증용)
