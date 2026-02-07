// ============================================
// 📦 1단계: 필요한 패키지 불러오기
// ============================================
// dotenv: .env 파일의 환경변수를 읽어오는 패키지
// 반드시 맨 위에서 실행해야 다른 코드에서 process.env를 사용할 수 있어요
require('dotenv').config();

const express = require('express');   // 웹 서버를 쉽게 만들어주는 프레임워크
const { Pool } = require('pg');       // PostgreSQL 데이터베이스 연결 도구
const bcrypt = require('bcrypt');     // 비밀번호를 안전하게 암호화하는 도구
const jwt = require('jsonwebtoken');  // JWT 토큰을 만들고 검증하는 도구
const path = require('path');         // 파일 경로를 다루는 Node.js 내장 모듈

// Express 앱 생성 (우리 서버의 본체)
const app = express();
const PORT = process.env.PORT || 3000;

// ============================================
// ⚙️ 2단계: 미들웨어 설정
// ============================================
// 미들웨어 = 요청이 처리되기 전에 먼저 실행되는 함수
// express.json(): 클라이언트가 보낸 JSON 데이터를 자동으로 파싱(분석)해줘요
// 예: {"email": "test@test.com"} → req.body.email로 접근 가능
app.use(express.json());

// ============================================
// 🗄️ 3단계: 데이터베이스 연결
// ============================================
// Pool: 데이터베이스 연결을 여러 개 만들어두고 재사용하는 방식
// (매번 새로 연결하면 느리니까, 미리 만들어둔 연결을 돌려쓰는 거예요)
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // Supabase는 SSL(보안 연결)을 요구해요
  ssl: { rejectUnauthorized: false }
});

// ============================================
// 🏗️ 4단계: 데이터베이스 테이블 자동 생성
// ============================================
// 서버가 시작될 때 users 테이블이 없으면 자동으로 만들어줘요
async function initDB() {
  const createTableQuery = `
    CREATE TABLE IF NOT EXISTS app_users (
      id SERIAL PRIMARY KEY,               -- 자동 증가하는 고유 번호
      email VARCHAR(255) UNIQUE NOT NULL,   -- 이메일 (중복 불가)
      password VARCHAR(255) NOT NULL,       -- 암호화된 비밀번호
      created_at TIMESTAMP DEFAULT NOW()    -- 가입 시각 (자동 기록)
    );
    -- 기존 테이블에 name 컬럼이 있으면 제거
    ALTER TABLE app_users DROP COLUMN IF EXISTS name;
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

    // 비밀번호 최소 길이 검증
    if (password.length < 6) {
      return res.status(400).json({ error: '비밀번호는 6자 이상이어야 합니다' });
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
// 흐름: 사용자 조회 → 비밀번호 비교 → JWT 토큰 발급
app.post('/api/login', async (req, res) => {
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
// 🌐 9단계: index.html 서빙
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
// 🚀 10단계: 서버 시작!
// ============================================
// initDB()로 테이블을 먼저 준비한 후, 서버를 실행해요
initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`🚀 북샵 서버가 http://localhost:${PORT} 에서 실행 중입니다`);
  });
}).catch((error) => {
  console.error('서버 시작 실패:', error);
});
