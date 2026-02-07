# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

온라인 서점 "북샵" — Express 5 백엔드 + React 18 프론트엔드(CDN 방식) 단일 파일 구조의 풀스택 웹 애플리케이션.

## 개발 명령어

```bash
# 서버 실행 (개발)
node server.js

# 프로덕션 실행 (PM2)
pm2 start ecosystem.config.js --env production

# 의존성 설치
npm install
```

테스트 프레임워크는 아직 설정되어 있지 않음.

## 아키텍처

### 백엔드 (`server.js`)
- Express 5 서버, 포트는 `process.env.PORT || 3000` (프로덕션 PM2: 4000)
- PostgreSQL(Supabase) 연결 — `pg` Pool, SSL 필수
- JWT 인증: `authenticateToken` 미들웨어로 보호 API 접근 제어
- API 엔드포인트:
  - `POST /api/register` — 회원가입 (bcrypt 해싱)
  - `POST /api/login` — 로그인 (JWT 발급, 7일 만료)
  - `GET /api/me` — 내 정보 조회 (인증 필요)
- SPA 라우팅: `GET /{*splat}` 와일드카드로 `index.html` 서빙 (static 미들웨어 미사용 — 보안 목적)
- 서버 시작 시 `initDB()`로 `app_users` 테이블 자동 생성

### 프론트엔드 (`index.html`)
- 빌드 도구 없이 CDN으로 React 18 + Babel + Tailwind CSS 로드
- 단일 HTML 파일 안에 `<script type="text/babel">`로 모든 React 컴포넌트 작성
- 책 데이터(`BOOKS`)는 클라이언트 하드코딩 (서버 API 아님)
- 주요 컴포넌트: `App`, `BookCard`, `CartPanel`, `BookDetail`, `LoginModal`, `RegisterModal`, `StarRating`
- Tailwind 커스텀 색상: `primary`(#2563eb), `secondary`(#f59e0b), `accent`(#10b981)

### 배포
- AWS Lightsail 대상, PM2 프로세스 매니저 사용
- GitHub Actions: main 브랜치 push 시 SSH로 자동 배포 (`scripts/deploy.sh`)
- 필요한 GitHub Secrets: `LIGHTSAIL_HOST`, `LIGHTSAIL_USERNAME`, `LIGHTSAIL_SSH_KEY`

## 환경 변수 (.env)

- `DATABASE_URL` — PostgreSQL 연결 문자열
- `JWT_SECRET` — JWT 서명 비밀키
- `PORT` — 서버 포트 (선택, 기본 3000)
