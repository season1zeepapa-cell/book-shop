# 📚 북샵 - 온라인 서점

Express 5 + React 18 기반의 풀스택 온라인 서점 웹 애플리케이션입니다. 토스페이먼츠 결제 시스템이 통합되어 있으며, JWT 인증과 PostgreSQL 데이터베이스를 사용합니다.

## ✨ 주요 기능

- 📖 **책 목록 조회 및 검색** - 카테고리별 필터링, 제목/저자 검색
- 🛒 **장바구니 시스템** - 상품 추가/수량 조절/삭제, 실시간 금액 계산
- 💳 **토스페이먼츠 결제** - 안전한 온라인 결제 (카드, 계좌이체 등)
- 🔐 **회원 인증** - JWT 기반 회원가입/로그인 시스템
- 📦 **주문 내역 관리** - 사용자별 주문 내역 조회
- 🚀 **배송비 자동 계산** - 3만원 이상 무료배송

## 🛠 기술 스택

### 백엔드
- **Node.js** + **Express 5** - 웹 서버 프레임워크
- **PostgreSQL** (Supabase) - 관계형 데이터베이스
- **JWT** - 토큰 기반 인증
- **bcrypt** - 비밀번호 암호화
- **토스페이먼츠 API** - 결제 시스템

### 프론트엔드
- **React 18** (CDN) - UI 라이브러리
- **Tailwind CSS** (CDN) - 유틸리티 우선 CSS 프레임워크
- **Babel** - JSX 변환

### 배포
- **AWS Lightsail** - 클라우드 호스팅
- **PM2** - 프로세스 매니저
- **GitHub Actions** - CI/CD 자동 배포

## 📦 설치 및 실행

### 1. 저장소 클론

```bash
git clone <repository-url>
cd book-shop
```

### 2. 의존성 설치

```bash
npm install
```

### 3. 환경변수 설정

`.env.example` 파일을 복사하여 `.env` 파일을 생성합니다:

```bash
cp .env.example .env
```

`.env` 파일을 열어 다음 값들을 실제 값으로 수정하세요:

```env
# PostgreSQL 연결 문자열 (Supabase 대시보드에서 확인)
DATABASE_URL=postgresql://user:password@host:port/database

# JWT 비밀키 (아래 명령어로 생성)
JWT_SECRET=<생성된-랜덤-문자열>

# 토스페이먼츠 시크릿키 (개발자센터에서 확인)
TOSS_SECRET_KEY=test_sk_your_key_here

# 서버 포트 (선택사항, 기본값 3000)
PORT=3000

# 환경 구분 (development 또는 production)
NODE_ENV=development
```

**JWT 비밀키 생성 방법:**
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### 4. 서버 실행

#### 개발 모드
```bash
npm run dev
# 또는
npm start
```

서버가 `http://localhost:3000`에서 실행됩니다.

#### 프로덕션 모드 (테스트용)
```bash
npm run prod
```

#### PM2로 프로덕션 실행
```bash
pm2 start ecosystem.config.js --env production
```

## 🗂 프로젝트 구조

```
book-shop/
├── server.js              # Express 백엔드 서버
├── index.html             # React 프론트엔드 (SPA)
├── package.json           # 의존성 및 스크립트
├── ecosystem.config.js    # PM2 설정
├── .env                   # 환경변수 (Git에 미포함)
├── .env.example           # 환경변수 템플릿
├── .gitignore             # Git 제외 파일 목록
├── CLAUDE.md              # 프로젝트 상세 문서
├── README.md              # 이 파일
├── scripts/
│   └── deploy.sh          # 배포 스크립트
└── .github/
    └── workflows/
        └── deploy.yml     # GitHub Actions 워크플로우
```

## 📡 API 엔드포인트

### 인증 관련
- `POST /api/register` - 회원가입
- `POST /api/login` - 로그인
- `GET /api/me` - 내 정보 조회 (인증 필요)

### 결제 관련
- `POST /api/payments/confirm` - 결제 승인 (인증 필요)
- `GET /api/orders` - 주문 내역 조회 (인증 필요)

### 기타
- `GET /*` - SPA 라우팅 (index.html 서빙)

## 🔒 보안 개선 내역

### 2026-02-08 보안 업데이트
다음 3가지 심각도 높은 보안 이슈를 개선했습니다:

#### 1. 환경변수 관리 개선
- ✅ `.env.example` 파일 추가 - 새 개발자 온보딩 간소화
- ✅ 환경변수 자동 검증 - 서버 시작 시 필수 변수 확인

#### 2. 결제 금액 검증 강화
- ✅ 서버 측 금액 재계산 - 클라이언트가 보낸 금액을 서버에서 검증
- ✅ 상품 가격 검증 - 마스터 데이터와 비교하여 가격 조작 차단
- ✅ 배송비 자동 계산 - 서버에서 정확한 최종 금액 산출
- ✅ 해킹 시도 로깅 - 검증 실패 시 상세 로그 기록

#### 3. SSL 인증서 검증 개선
- ✅ 환경별 SSL 설정 - 개발/프로덕션 환경 자동 구분
- ✅ 프로덕션 보안 강화 - SSL 인증서 검증 활성화

#### 4. 추가 개선 사항
- ✅ npm scripts 추가 - start, dev, prod 명령어
- ✅ logs 폴더 자동 생성 - PM2 로그 파일 경로 자동 생성
- ✅ README.md 작성 - 프로젝트 문서화

## 🚀 배포

### 자동 배포 (GitHub Actions)

`main` 브랜치에 push하면 자동으로 AWS Lightsail에 배포됩니다.

**필요한 GitHub Secrets:**
- `LIGHTSAIL_HOST` - Lightsail 인스턴스 공인 IP
- `LIGHTSAIL_USERNAME` - SSH 사용자명 (보통 ubuntu)
- `LIGHTSAIL_SSH_KEY` - SSH 프라이빗 키

### 수동 배포

서버에 SSH 접속 후:

```bash
cd /home/ubuntu/book-shop
bash scripts/deploy.sh
```

## 📝 데이터베이스 스키마

### app_users 테이블
```sql
CREATE TABLE app_users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,  -- bcrypt 해시
  created_at TIMESTAMP DEFAULT NOW()
);
```

### orders 테이블
```sql
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES app_users(id),
  order_id VARCHAR(255) UNIQUE NOT NULL,
  payment_key VARCHAR(255) UNIQUE,
  order_name VARCHAR(500) NOT NULL,
  total_amount INTEGER NOT NULL,
  status VARCHAR(50) DEFAULT 'READY',
  method VARCHAR(100),
  items JSONB DEFAULT '[]',
  payment_response JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  approved_at TIMESTAMP
);
```

## 🧪 테스트

### 환경변수 검증 테스트
```bash
# .env 파일 없이 서버 시작 시도
mv .env .env.backup
npm start
# 예상: "필수 환경변수가 설정되지 않았습니다" 에러
mv .env.backup .env
```

### SSL 설정 테스트
```bash
# 개발 모드
NODE_ENV=development npm start
# 로그: "SSL 검증 비활성화 (개발)"

# 프로덕션 모드
NODE_ENV=production npm start
# 로그: "SSL 검증 활성화 (프로덕션)"
```

### 결제 금액 검증 테스트

브라우저 개발자 도구에서 다음 코드를 실행하여 금액 조작 시도:

```javascript
const token = localStorage.getItem('token');

fetch('/api/payments/confirm', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token,
  },
  body: JSON.stringify({
    paymentKey: 'test-key',
    orderId: 'test-' + Date.now(),
    amount: 1000,  // 조작된 금액
    items: [
      { bookId: 1, title: '모던 자바스크립트 Deep Dive', price: 45000, quantity: 1 }
    ]
  })
})
.then(r => r.json())
.then(console.log);
```

예상 응답:
```json
{
  "error": "결제 금액이 올바르지 않습니다",
  "detail": "결제 금액이 일치하지 않습니다 (계산된 금액: 48000원, 요청 금액: 1000원)"
}
```

## 🤝 기여

버그 리포트나 기능 제안은 Issue를 통해 알려주세요.

## 📄 라이선스

ISC

## 📞 문의

프로젝트 관련 문의사항이 있으시면 Issue를 생성해주세요.

---

**🎓 학습 목적으로 제작된 프로젝트입니다.**

이 프로젝트는 초보자를 위한 학습용으로, 모든 코드에 상세한 한국어 주석이 포함되어 있습니다. 프로덕션 환경에 배포하기 전에 추가적인 보안 검토를 권장합니다.

---

**Created with ❤️ by the book-shop team**
