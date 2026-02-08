// ============================================
// 📦 1단계: 필요한 패키지 불러오기
// ============================================
// dotenv: .env 파일의 환경변수를 읽어오는 패키지
// 반드시 맨 위에서 실행해야 다른 코드에서 process.env를 사용할 수 있어요
require('dotenv').config();

// ============================================
// ✅ 1-1단계: 환경변수 검증
// ============================================
// 서버 시작 전에 필수 환경변수가 모두 설정되었는지 확인합니다
// 누락된 환경변수가 있으면 에러 메시지를 출력하고 서버를 종료해요
function validateEnvironment() {
  // 필수 환경변수 목록
  const required = ['DATABASE_URL', 'JWT_SECRET', 'TOSS_SECRET_KEY'];

  // 설정되지 않은 환경변수 찾기
  const missing = required.filter(key => !process.env[key]);

  if (missing.length > 0) {
    console.error('❌ 필수 환경변수가 설정되지 않았습니다:', missing.join(', '));
    console.error('💡 .env.example 파일을 참고하여 .env 파일을 생성해주세요.');
    console.error('   1. cp .env.example .env');
    console.error('   2. .env 파일을 열어 실제 값으로 수정');
    process.exit(1);  // 서버 종료 (에러 코드 1)
  }

  // 추가: 환경변수 값 형식 검증
  // JWT_SECRET은 최소 32자 이상이어야 안전해요 (256비트)
  if (process.env.JWT_SECRET.length < 32) {
    console.error(`❌ JWT_SECRET은 최소 32자 이상이어야 합니다 (현재: ${process.env.JWT_SECRET.length}자)`);
    console.error('💡 다음 명령어로 안전한 키를 생성하세요:');
    console.error('   node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');
    process.exit(1);
  }

  // DATABASE_URL은 postgresql:// 또는 postgres://로 시작해야 해요
  if (!process.env.DATABASE_URL.startsWith('postgres://') && !process.env.DATABASE_URL.startsWith('postgresql://')) {
    console.error('❌ DATABASE_URL 형식이 올바르지 않습니다 (postgres:// 또는 postgresql://로 시작해야 함)');
    process.exit(1);
  }

  console.log('✅ 모든 필수 환경변수가 설정되었습니다');
  console.log('✅ 환경변수 값 검증 통과');
}

// 환경변수 검증 실행
validateEnvironment();

// ============================================
// ✅ 1-2단계: 비밀번호 강도 검증 함수
// ============================================
// 안전한 비밀번호 정책을 적용하는 함수예요
// 요구사항: 최소 8자, 대문자 1개 이상, 숫자 1개 이상, 특수문자 1개 이상
function validatePasswordStrength(password) {
  const minLength = 8;
  const hasUpperCase = /[A-Z]/.test(password);          // 대문자 포함 확인
  const hasLowerCase = /[a-z]/.test(password);          // 소문자 포함 확인
  const hasNumber = /\d/.test(password);                // 숫자 포함 확인
  const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);  // 특수문자 포함 확인

  if (password.length < minLength) {
    return { valid: false, error: '비밀번호는 8자 이상이어야 합니다' };
  }
  if (!hasUpperCase) {
    return { valid: false, error: '비밀번호에 대문자가 포함되어야 합니다' };
  }
  if (!hasNumber) {
    return { valid: false, error: '비밀번호에 숫자가 포함되어야 합니다' };
  }
  if (!hasSpecialChar) {
    return { valid: false, error: '비밀번호에 특수문자(!@#$%^&* 등)가 포함되어야 합니다' };
  }

  return { valid: true };
}

const express = require('express');        // 웹 서버를 쉽게 만들어주는 프레임워크
const { Pool } = require('pg');            // PostgreSQL 데이터베이스 연결 도구
const bcrypt = require('bcrypt');          // 비밀번호를 안전하게 암호화하는 도구
const jwt = require('jsonwebtoken');       // JWT 토큰을 만들고 검증하는 도구
const path = require('path');              // 파일 경로를 다루는 Node.js 내장 모듈
const fs = require('fs');                  // 파일 시스템 모듈 (logs 폴더 생성용)
const rateLimit = require('express-rate-limit');  // Rate limiting (브루트포스 공격 방지)
const validator = require('validator');    // 입력값 검증 (이메일 형식 등)
const helmet = require('helmet');          // 보안 HTTP 헤더 설정

// Express 앱 생성 (우리 서버의 본체)
const app = express();
const PORT = process.env.PORT || 3000;

// ============================================
// 📚 1-2단계: 상품 마스터 데이터
// ============================================
// 결제 금액 검증을 위해 서버에서도 책 정보를 가지고 있어야 해요
// 현재는 하드코딩이지만, 향후 데이터베이스 테이블로 이관 권장
// ⚠️ 주의: 가격 변경 시 index.html과 여기 두 곳 모두 수정해야 합니다
const BOOKS = [
  { id: 1, title: "모던 자바스크립트 Deep Dive", author: "이웅모", price: 45000, category: "프로그래밍" },
  { id: 2, title: "클린 코드", author: "로버트 C. 마틴", price: 29700, category: "프로그래밍" },
  { id: 3, title: "데미안", author: "헤르만 헤세", price: 8100, category: "소설" },
  { id: 4, title: "사피엔스", author: "유발 하라리", price: 19800, category: "교양" },
  { id: 5, title: "리액트를 다루는 기술", author: "김민준", price: 39600, category: "프로그래밍" },
  { id: 6, title: "아몬드", author: "손원평", price: 10800, category: "소설" },
  { id: 7, title: "트렌드 코리아 2026", author: "김난도", price: 17100, category: "경제/경영" },
  { id: 8, title: "역행자", author: "자청", price: 15750, category: "자기계발" },
  { id: 9, title: "파이썬 알고리즘 인터뷰", author: "박상길", price: 34200, category: "프로그래밍" },
  { id: 10, title: "돈의 심리학", author: "모건 하우절", price: 16200, category: "경제/경영" },
  { id: 11, title: "미움받을 용기", author: "기시미 이치로", price: 14400, category: "자기계발" },
  { id: 12, title: "작별인사", author: "김영하", price: 13500, category: "소설" },
];

// 빠른 조회를 위한 Map 생성 (id → book 객체)
// Map을 사용하면 O(1) 시간 복잡도로 상품을 찾을 수 있어요
const BOOKS_MAP = new Map(BOOKS.map(book => [book.id, book]));

// ============================================
// 💳 토스페이먼츠 결제 설정
// ============================================
// 시크릿키를 Basic Auth 형식으로 인코딩해요
// 토스페이먼츠 API는 "시크릿키:" (콜론 포함)를 Base64로 인코딩한 값을 요구해요
// 이 값은 결제 승인 요청 시 Authorization 헤더에 사용됩니다
const TOSS_SECRET_KEY = process.env.TOSS_SECRET_KEY;
const encryptedSecretKey = 'Basic ' + Buffer.from(TOSS_SECRET_KEY + ':').toString('base64');

// ============================================
// ⚙️ 2단계: 미들웨어 설정
// ============================================
// 미들웨어 = 요청이 처리되기 전에 먼저 실행되는 함수

// 1) helmet: 보안 관련 HTTP 헤더를 자동으로 설정해줘요
// (X-Frame-Options, X-Content-Type-Options, Strict-Transport-Security 등)
// 이를 통해 XSS, 클릭재킹 등의 공격을 방어할 수 있어요
//
// ⚠️ CSP(Content Security Policy)를 프로젝트에 맞게 설정해야 해요!
// 기본값은 'self'만 허용해서 CDN 스크립트(React, Babel 등)를 차단해요
// 이 프로젝트는 빌드 도구 없이 CDN으로 라이브러리를 로드하므로 명시적 허용 필요
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: [
        "'self'",
        "'unsafe-inline'",   // 인라인 스크립트 허용 (Tailwind config, Babel 코드)
        "'unsafe-eval'",     // eval 허용 (Babel standalone이 JSX 변환에 사용)
        "https://unpkg.com",             // React, ReactDOM, Babel CDN
        "https://cdn.tailwindcss.com",   // Tailwind CSS CDN
        "https://js.tosspayments.com",   // 토스페이먼츠 SDK
      ],
      styleSrc: ["'self'", "'unsafe-inline'", "https://cdn.tailwindcss.com"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'", "https://api.tosspayments.com"],
      frameSrc: ["'self'", "https://*.tosspayments.com"],  // 토스 결제 위젯 iframe
      fontSrc: ["'self'", "https:"],
      upgradeInsecureRequests: null,  // HTTP 서버이므로 HTTPS 강제 업그레이드 비활성화
    },
  },
}));

// 2) express.json(): 클라이언트가 보낸 JSON 데이터를 자동으로 파싱(분석)해줘요
// 예: {"email": "test@test.com"} → req.body.email로 접근 가능
// limit: '1mb' → 최대 1MB까지만 허용 (DoS 공격 방지)
app.use(express.json({ limit: '1mb' }));

// ============================================
// 🛡️ 2-1단계: Rate Limiting 설정
// ============================================
// 브루트포스 공격(무차별 대입 공격)을 방어하기 위해
// 같은 IP에서 너무 많은 요청을 보내면 일시적으로 차단해요

// 로그인 API 전용 Rate Limiter (더 엄격하게 제한)
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15분 시간 창
  max: 5,  // 15분 동안 같은 IP에서 최대 5회 시도만 허용
  message: { error: '너무 많은 로그인 시도입니다. 15분 후 다시 시도해주세요.' },
  standardHeaders: true,   // Rate limit 정보를 응답 헤더에 포함 (RateLimit-* 헤더)
  legacyHeaders: false,    // X-RateLimit-* 헤더는 사용 안 함 (구버전 호환 불필요)
});

// 결제 API 전용 Rate Limiter (조금 덜 엄격)
const paymentLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15분 시간 창
  max: 10,  // 15분 동안 같은 IP에서 최대 10회 결제 요청만 허용
  message: { error: '너무 많은 결제 요청입니다. 잠시 후 다시 시도해주세요.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// ============================================
// 🗄️ 3단계: 데이터베이스 연결
// ============================================
// Pool: 데이터베이스 연결을 여러 개 만들어두고 재사용하는 방식
// (매번 새로 연결하면 느리니까, 미리 만들어둔 연결을 돌려쓰는 거예요)

// SSL 설정 결정 (환경에 따라 다르게 설정)
// - 개발 환경: 인증서 검증 비활성화 (편의성 우선)
// - 프로덕션 환경: 인증서 검증 활성화 (보안 우선)
const isProduction = process.env.NODE_ENV === 'production';

// SSL 설정: 연결 문자열에 sslmode=require가 있으면 SSL 사용
const sslConfig = process.env.DATABASE_URL.includes('sslmode=require')
  ? {
      rejectUnauthorized: isProduction,
      // 프로덕션에서는 true (인증서 검증), 개발에서는 false (검증 생략)
    }
  : false;  // SSL을 사용하지 않는 연결 (로컬 PostgreSQL 등)

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: sslConfig,
});

// 현재 SSL 설정 로그 출력 (서버 시작 시 확인용)
console.log(`🔒 데이터베이스 SSL 설정: ${
  sslConfig === false
    ? 'SSL 미사용 (로컬 연결)'
    : (sslConfig.rejectUnauthorized
        ? 'SSL 검증 활성화 (프로덕션)'
        : 'SSL 검증 비활성화 (개발)')
}`);

// ============================================
// 🏗️ 4단계: 데이터베이스 테이블 자동 생성
// ============================================
// 서버가 시작될 때 users 테이블이 없으면 자동으로 만들어줘요
async function initDB() {
  // logs 폴더가 없으면 자동 생성 (PM2 로그 파일용)
  // recursive: true 옵션으로 이미 폴더가 있어도 에러 안 남
  if (!fs.existsSync('./logs')) {
    fs.mkdirSync('./logs', { recursive: true });
    console.log('📁 logs 폴더가 생성되었습니다');
  }
  const createTableQuery = `
    CREATE TABLE IF NOT EXISTS app_users (
      id SERIAL PRIMARY KEY,               -- 자동 증가하는 고유 번호
      email VARCHAR(255) UNIQUE NOT NULL,   -- 이메일 (중복 불가)
      password VARCHAR(255) NOT NULL,       -- 암호화된 비밀번호
      created_at TIMESTAMP DEFAULT NOW()    -- 가입 시각 (자동 기록)
    );
    -- 기존 테이블에 name 컬럼이 있으면 제거
    ALTER TABLE app_users DROP COLUMN IF EXISTS name;

    -- 주문(orders) 테이블
    -- 결제가 완료된 주문 정보를 저장하는 테이블이에요
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,                              -- 주문 고유 번호 (내부용)
      user_id INTEGER NOT NULL REFERENCES app_users(id),  -- 주문한 사용자 (app_users 테이블 참조)
      order_id VARCHAR(255) UNIQUE NOT NULL,               -- 토스페이먼츠 주문 ID (우리가 생성)
      payment_key VARCHAR(255) UNIQUE,                     -- 토스페이먼츠 결제 키 (토스가 발급)
      order_name VARCHAR(500) NOT NULL,                    -- 주문명 (예: "모던 자바스크립트 외 2건")
      total_amount INTEGER NOT NULL,                       -- 총 결제 금액 (원)
      status VARCHAR(50) DEFAULT 'READY',                  -- 주문 상태 (READY, DONE, CANCELED)
      method VARCHAR(100),                                 -- 결제 수단 (카드, 계좌이체 등)
      items JSONB NOT NULL DEFAULT '[]',                   -- 주문 상품 목록 (JSON 배열)
      payment_response JSONB,                              -- 토스 API 응답 원본 (환불 등에 활용)
      created_at TIMESTAMP DEFAULT NOW(),                  -- 주문 생성 시각
      approved_at TIMESTAMP                                -- 결제 승인 시각
    );
  `;
  await pool.query(createTableQuery);
  console.log('✅ 데이터베이스 테이블 준비 완료');
}

// ============================================
// 🔐 5단계: JWT 인증 미들웨어
// ============================================
// "이 사람이 로그인한 사용자가 맞는지" 확인하는 함수
// 보호가 필요한 API에 이 미들웨어를 붙이면, 로그인한 사람만 접근할 수 있어요
//
// 흐름: 요청 → authenticateToken 확인 → 통과하면 next() → 실제 API 실행
function authenticateToken(req, res, next) {
  // 요청 헤더에서 "Authorization: Bearer 토큰값" 형태의 값을 가져옴
  const authHeader = req.headers['authorization'];
  // "Bearer eyJhbG..." → ["Bearer", "eyJhbG..."] → "eyJhbG..." (토큰만 추출)
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: '로그인이 필요합니다' });
  }

  // 토큰이 유효한지 검증 (서명 확인 + 만료일 확인)
  jwt.verify(token, process.env.JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(401).json({ error: '유효하지 않은 토큰입니다' });
    }
    // 토큰 안에 들어있던 사용자 정보를 req.user에 저장
    // 이후 API에서 req.user.id, req.user.email로 접근 가능
    req.user = decoded;
    next(); // 다음 단계(실제 API)로 넘어가기
  });
}

// ============================================
// 💰 5-1단계: 결제 금액 검증 함수
// ============================================
// 클라이언트가 보낸 주문 정보가 실제 가격과 일치하는지 검증합니다
// 이 검증을 통해 악의적인 사용자가 금액을 조작하는 것을 방지해요
//
// 매개변수:
//   - items: 주문 상품 목록 [{ bookId, title, author, price, quantity }]
//   - expectedTotal: 클라이언트가 주장하는 총 결제 금액
//
// 반환값:
//   - { valid: true, calculatedTotal: 123000 } (검증 성공)
//   - { valid: false, error: "에러 메시지", calculatedTotal: 실제금액 } (검증 실패)
function validatePaymentAmount(items, expectedTotal) {
  // 1. 입력값 기본 검증
  if (!Array.isArray(items) || items.length === 0) {
    return { valid: false, error: '주문 상품이 없습니다' };
  }

  let calculatedSubtotal = 0;

  // 2. 각 상품의 가격을 서버의 마스터 데이터로 재계산
  for (const item of items) {
    const { bookId, quantity, price: clientPrice } = item;

    // 필수 필드 확인
    if (!bookId || !quantity || quantity <= 0) {
      return { valid: false, error: '잘못된 주문 상품 정보입니다' };
    }

    // 서버의 마스터 데이터에서 실제 가격 조회
    const masterBook = BOOKS_MAP.get(bookId);
    if (!masterBook) {
      return {
        valid: false,
        error: `존재하지 않는 상품입니다 (ID: ${bookId})`,
      };
    }

    // 가격 검증: 클라이언트가 보낸 가격과 서버의 가격이 일치하는지 확인
    const serverPrice = masterBook.price;
    if (clientPrice !== serverPrice) {
      return {
        valid: false,
        error: `"${masterBook.title}"의 가격이 일치하지 않습니다 (서버: ${serverPrice}원, 클라이언트: ${clientPrice}원)`,
      };
    }

    // 소계 누적 (가격 × 수량)
    calculatedSubtotal += serverPrice * quantity;
  }

  // 3. 배송비 계산 (3만원 이상 무료, 미만 3,000원)
  const shippingFee = calculatedSubtotal >= 30000 ? 0 : 3000;
  const calculatedTotal = calculatedSubtotal + shippingFee;

  // 4. 최종 금액 비교
  if (calculatedTotal !== expectedTotal) {
    return {
      valid: false,
      error: `결제 금액이 일치하지 않습니다 (계산된 금액: ${calculatedTotal}원, 요청 금액: ${expectedTotal}원)`,
      calculatedTotal,
    };
  }

  // 검증 성공!
  return { valid: true, calculatedTotal };
}

// ============================================
// 📝 6단계: 회원가입 API
// ============================================
// POST /api/register
// 흐름: 입력 검증 → 이메일 중복 확인 → 비밀번호 암호화 → DB 저장
app.post('/api/register', async (req, res) => {
  try {
    const { email, password } = req.body;

    // --- 입력값 검증 ---
    if (!email || !password) {
      return res.status(400).json({ error: '이메일, 비밀번호를 모두 입력해주세요' });
    }

    // 이메일 형식 검증 (validator 라이브러리 사용)
    // 예: "invalid-email" → 차단, "test@example.com" → 통과
    if (!validator.isEmail(email)) {
      return res.status(400).json({ error: '올바른 이메일 형식이 아닙니다' });
    }

    // 비밀번호 강도 검증 (8자 이상, 대문자, 숫자, 특수문자 필수)
    const passwordCheck = validatePasswordStrength(password);
    if (!passwordCheck.valid) {
      return res.status(400).json({ error: passwordCheck.error });
    }

    // --- 이메일 중복 확인 ---
    // $1은 "플레이스홀더"로, 뒤의 [email] 값으로 대체돼요
    // 이렇게 하면 SQL 인젝션 공격을 방지할 수 있어요
    const existingUser = await pool.query(
      'SELECT id FROM app_users WHERE email = $1',
      [email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: '이미 가입된 이메일입니다' });
    }

    // --- 비밀번호 암호화 ---
    // bcrypt.hash(원본비밀번호, 솔트라운드)
    // 솔트라운드 10 = 2^10번 해싱 반복 (보안과 속도의 적절한 균형)
    // "1234" → "$2b$10$xYz..." 같은 형태로 변환 (원본 복원 불가)
    const hashedPassword = await bcrypt.hash(password, 10);

    // --- DB에 사용자 저장 ---
    // RETURNING: INSERT 후 방금 저장된 데이터를 바로 돌려받는 PostgreSQL 기능
    const result = await pool.query(
      'INSERT INTO app_users (email, password) VALUES ($1, $2) RETURNING id, email',
      [email, hashedPassword]
    );

    // 201 = "Created" (새로운 리소스가 성공적으로 만들어짐)
    res.status(201).json({
      message: '회원가입이 완료되었습니다',
      user: result.rows[0]
    });

  } catch (error) {
    console.error('회원가입 오류:', error);
    res.status(500).json({ error: '서버 오류가 발생했습니다' });
  }
});

// ============================================
// 🔑 7단계: 로그인 API
// ============================================
// POST /api/login
// 흐름: Rate limiting 확인 → 사용자 조회 → 비밀번호 비교 → JWT 토큰 발급
// loginLimiter: 같은 IP에서 15분에 5회까지만 시도 가능 (브루트포스 공격 방지)
app.post('/api/login', loginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: '이메일과 비밀번호를 입력해주세요' });
    }

    // --- 이메일로 사용자 조회 ---
    const result = await pool.query(
      'SELECT * FROM app_users WHERE email = $1',
      [email]
    );

    if (result.rows.length === 0) {
      // 보안: "이메일이 없다"고 하면 공격자가 이메일 존재 여부를 알 수 있어요
      // 그래서 이메일/비밀번호 중 뭐가 틀렸는지 구분하지 않아요
      return res.status(401).json({ error: '이메일 또는 비밀번호가 올바르지 않습니다' });
    }

    const user = result.rows[0];

    // --- 비밀번호 비교 ---
    // bcrypt.compare: 입력된 비밀번호를 같은 방식으로 해싱해서 DB의 해시와 비교
    const isValid = await bcrypt.compare(password, user.password);

    if (!isValid) {
      return res.status(401).json({ error: '이메일 또는 비밀번호가 올바르지 않습니다' });
    }

    // --- JWT 토큰 생성 ---
    // jwt.sign(토큰에 담을 데이터, 비밀키, 옵션)
    // expiresIn: '7d' = 7일 후 만료 (만료되면 다시 로그인해야 해요)
    const token = jwt.sign(
      { id: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.json({
      message: '로그인 성공',
      token,  // 클라이언트가 이 토큰을 저장해두고, 이후 요청마다 보내줘야 해요
      user: { id: user.id, email: user.email }
    });

  } catch (error) {
    console.error('로그인 오류:', error);
    res.status(500).json({ error: '서버 오류가 발생했습니다' });
  }
});

// ============================================
// 👤 8단계: 내 정보 조회 API
// ============================================
// GET /api/me
// authenticateToken 미들웨어가 먼저 실행돼서 로그인 확인을 해줘요
app.get('/api/me', authenticateToken, async (req, res) => {
  try {
    // req.user는 authenticateToken에서 토큰을 디코딩해서 넣어준 데이터
    const result = await pool.query(
      'SELECT id, email, created_at FROM app_users WHERE id = $1',
      [req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: '사용자를 찾을 수 없습니다' });
    }

    res.json({ user: result.rows[0] });

  } catch (error) {
    console.error('사용자 조회 오류:', error);
    res.status(500).json({ error: '서버 오류가 발생했습니다' });
  }
});

// ============================================
// 💳 9단계: 결제 승인 API
// ============================================
// POST /api/payments/confirm
// 흐름: Rate limiting 확인 → 인증 확인 → 요청 검증 → 금액 검증 (중요!) → 토스페이먼츠 결제 승인 API 호출 → DB에 주문 저장
//
// 토스페이먼츠 결제 과정:
// 1. 프론트엔드에서 결제 위젯으로 결제 진행
// 2. 결제 성공 시 /success?paymentKey=...&orderId=...&amount=... 로 리다이렉트
// 3. 프론트엔드가 이 API를 호출하여 결제를 "승인" (이 단계에서 실제 결제 확정!)
// 4. 서버가 금액을 검증한 후 토스페이먼츠 API에 승인 요청 → 성공하면 DB에 주문 저장
// paymentLimiter: 같은 IP에서 15분에 10회까지만 결제 요청 가능
app.post('/api/payments/confirm', paymentLimiter, authenticateToken, async (req, res) => {
  try {
    const { paymentKey, orderId, amount, items } = req.body;

    // --- 입력값 검증 ---
    if (!paymentKey || !orderId || !amount) {
      return res.status(400).json({ error: 'paymentKey, orderId, amount는 필수입니다' });
    }

    // items 필수 검증 추가 (금액 검증을 위해 반드시 필요)
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: '주문 상품 정보가 필요합니다' });
    }

    // ===== 🔒 결제 금액 검증 (보안 핵심!) =====
    const validation = validatePaymentAmount(items, amount);

    if (!validation.valid) {
      // 검증 실패: 해킹 시도일 수 있으므로 자세히 로그 기록
      console.error('⚠️ 결제 금액 검증 실패:', {
        userId: req.user.id,
        userEmail: req.user.email,
        orderId,
        error: validation.error,
        requestedAmount: amount,
        calculatedAmount: validation.calculatedTotal,
        items,
        timestamp: new Date().toISOString(),
      });

      return res.status(400).json({
        error: '결제 금액이 올바르지 않습니다',
        detail: validation.error,
      });
    }

    // 검증 성공 로그
    console.log('✅ 결제 금액 검증 성공:', {
      userId: req.user.id,
      userEmail: req.user.email,
      orderId,
      validatedAmount: validation.calculatedTotal,
      itemCount: items.length,
    });
    // ===== 금액 검증 끝 =====

    // --- 토스페이먼츠 결제 승인 API 호출 ---
    // 이 요청이 성공하면 실제로 결제가 확정되고 금액이 차감돼요
    // Node 20에서는 fetch가 내장되어 있어서 별도 패키지 없이 사용 가능해요
    const tossResponse = await fetch('https://api.tosspayments.com/v1/payments/confirm', {
      method: 'POST',
      headers: {
        'Authorization': encryptedSecretKey,  // Basic Auth (시크릿키 Base64 인코딩)
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      }),
    });

    const tossResult = await tossResponse.json();

    // 토스페이먼츠 API에서 에러를 반환한 경우
    if (!tossResponse.ok) {
      console.error('토스페이먼츠 결제 승인 실패:', tossResult);
      return res.status(tossResponse.status).json({
        error: '결제 승인에 실패했습니다',
        code: tossResult.code,
        message: tossResult.message,
      });
    }

    // --- DB에 주문 저장 ---
    // 결제 승인이 성공한 경우에만 orders 테이블에 기록해요
    await pool.query(
      `INSERT INTO orders (user_id, order_id, payment_key, order_name, total_amount, status, method, items, payment_response, approved_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())`,
      [
        req.user.id,                       // 로그인한 사용자 ID
        tossResult.orderId,                 // 주문 ID
        tossResult.paymentKey,              // 결제 키
        tossResult.orderName,               // 주문명
        tossResult.totalAmount,             // 총 결제 금액
        tossResult.status,                  // 결제 상태 (보통 'DONE')
        tossResult.method,                  // 결제 수단 (카드, 계좌이체 등)
        JSON.stringify(items || []),         // 주문 상품 목록
        JSON.stringify(tossResult),          // 토스 API 응답 원본 저장
      ]
    );

    // 클라이언트에 결제 결과 반환
    res.json({
      message: '결제가 완료되었습니다',
      orderId: tossResult.orderId,
      totalAmount: tossResult.totalAmount,
      method: tossResult.method,
      status: tossResult.status,
      approvedAt: tossResult.approvedAt,
    });

  } catch (error) {
    console.error('결제 승인 오류:', error);
    res.status(500).json({ error: '서버 오류가 발생했습니다' });
  }
});

// ============================================
// 📋 10단계: 주문 내역 조회 API
// ============================================
// GET /api/orders
// 로그인한 사용자의 주문 내역을 최신순으로 보여줘요
app.get('/api/orders', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, order_id, order_name, total_amount, status, method, items, created_at, approved_at
       FROM orders
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [req.user.id]
    );

    res.json({ orders: result.rows });

  } catch (error) {
    console.error('주문 내역 조회 오류:', error);
    res.status(500).json({ error: '서버 오류가 발생했습니다' });
  }
});

// ============================================
// 🌐 11단계: index.html 서빙
// ============================================
// API가 아닌 모든 요청에 대해 index.html을 보내줘요
// (React가 클라이언트에서 화면을 그리는 SPA 방식)
// express.static() 대신 이 방식을 쓰는 이유:
// → .env, server.js 같은 민감한 파일이 외부에 노출되지 않아요
// Express 5에서는 와일드카드(*)에 이름이 필요해요: {*splat}
// 이 라우트는 API 라우트 뒤에 있어서, /api/... 요청은 여기까지 오지 않아요
app.get('/{*splat}', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

// ============================================
// 🚀 12단계: 서버 시작!
// ============================================
// initDB()로 테이블을 먼저 준비한 후, 서버를 실행해요
initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`🚀 북샵 서버가 http://localhost:${PORT} 에서 실행 중입니다`);
  });
}).catch((error) => {
  console.error('서버 시작 실패:', error);
});
