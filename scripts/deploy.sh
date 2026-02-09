#!/bin/bash
# ==============================================
# 배포 스크립트 — Lightsail 인스턴스에서 실행됩니다
# GitHub Actions가 SSH로 접속하여 이 스크립트를 실행합니다
#
# 동작 흐름:
# 1. 프로젝트 폴더로 이동
# 2. Git에서 최신 코드 가져오기 (git pull)
# 3. 의존성 설치 (npm install)
# 4. PM2로 서버 재시작
# ==============================================

set -e  # 에러 발생 시 즉시 스크립트 중단

# 프로젝트가 설치된 경로 (Lightsail 인스턴스 내 경로)
APP_DIR="/home/ubuntu/book-shop"

echo "🚀 book-shop 배포를 시작합니다..."

# 1단계: 프로젝트 폴더로 이동
cd "$APP_DIR"
echo "📂 프로젝트 폴더: $APP_DIR"

# 2단계: 최신 코드 가져오기
echo "📥 최신 코드를 가져오는 중..."
git pull origin main

# 3단계: 의존성 설치
echo "📦 의존성 설치 중..."
npm install --production

# 4단계: PM2로 서버 재시작
echo "🔄 서버를 재시작하는 중..."
pm2 restart ecosystem.config.js --env production 2>/dev/null || pm2 start ecosystem.config.js --env production

# 5단계: PM2 프로세스 목록 저장 (서버 재부팅 시 자동 시작을 위해)
pm2 save

# 6단계: Nginx 설정 동기화 및 리로드
# 프로젝트의 Nginx 설정 파일이 변경되었을 수 있으므로 항상 동기화
if command -v nginx &> /dev/null; then
  echo "🔄 Nginx 설정을 동기화하는 중..."
  sudo cp "$APP_DIR/nginx/bookshop.conf" /etc/nginx/sites-available/bookshop
  sudo ln -sf /etc/nginx/sites-available/bookshop /etc/nginx/sites-enabled/bookshop

  # 설정 문법 검사 후 리로드 또는 시작
  if sudo nginx -t 2>/dev/null; then
    sudo systemctl restart nginx
    echo "✅ Nginx 재시작 완료"
  else
    echo "⚠️ Nginx 설정에 문제가 있습니다. 이전 설정으로 계속 동작합니다."
  fi
fi

# 7단계: 헬스체크 (서버가 정상 응답하는지 확인)
echo "🏥 헬스체크 중..."
sleep 3

echo "--- Node.js 내부 헬스체크 (port 4000) ---"
if curl -sf http://127.0.0.1:4000/api/books > /dev/null 2>&1; then
  echo "✅ Node.js 서버 정상 응답"
else
  echo "❌ Node.js 서버 응답 없음"
  echo "--- PM2 에러 로그 ---"
  pm2 logs book-shop --lines 30 --nostream 2>&1 || true
fi

echo "--- Nginx 상태 ---"
sudo systemctl status nginx --no-pager 2>&1 || true
echo "--- Nginx 에러 로그 (최근 10줄) ---"
sudo tail -10 /var/log/nginx/error.log 2>&1 || true
echo "--- SSL 인증서 만료일 ---"
sudo openssl x509 -enddate -noout -in /etc/letsencrypt/live/bookshop.aifac.click/fullchain.pem 2>&1 || echo "인증서 파일 없음"
echo "--- 포트 443 리스닝 확인 ---"
sudo ss -tlnp | grep ':443' 2>&1 || echo "443 포트 리스닝 없음"

echo ""
echo "✅ book-shop 배포가 완료되었습니다!"
echo "📊 현재 PM2 상태:"
pm2 list
