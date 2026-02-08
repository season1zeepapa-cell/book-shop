#!/bin/bash
# ==============================================
# 서버 초기 설정 스크립트
# ==============================================
# AWS Lightsail 인스턴스에서 최초 1회 실행하세요
#
# 이 스크립트가 하는 일:
# 1. Node.js 22 LTS 설치
# 2. PM2 설치
# 3. Nginx 설치 및 설정
# 4. Let's Encrypt SSL 인증서 발급
# 5. 프로젝트 클론 및 설정
#
# 사용법:
#   ssh ubuntu@서버IP
#   bash setup-server.sh
# ==============================================

set -e

DOMAIN="bookshop.aifac.click"
APP_DIR="/home/ubuntu/book-shop"

echo "=========================================="
echo " 북샵 서버 초기 설정을 시작합니다"
echo "=========================================="

# 1단계: 시스템 업데이트
echo ""
echo "📦 [1/6] 시스템 패키지 업데이트..."
sudo apt update && sudo apt upgrade -y

# 2단계: Node.js 22 LTS 설치
echo ""
echo "📦 [2/6] Node.js 22 LTS 설치..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt install -y nodejs
fi
echo "  Node.js 버전: $(node -v)"
echo "  npm 버전: $(npm -v)"

# 3단계: PM2 설치
echo ""
echo "📦 [3/6] PM2 설치..."
if ! command -v pm2 &> /dev/null; then
    sudo npm install -g pm2
fi
echo "  PM2 버전: $(pm2 -v)"

# 4단계: Nginx 설치
echo ""
echo "📦 [4/6] Nginx 설치 및 설정..."
if ! command -v nginx &> /dev/null; then
    sudo apt install -y nginx
fi

# Nginx 설정 파일 복사
sudo cp "$APP_DIR/nginx/bookshop.conf" /etc/nginx/sites-available/bookshop
sudo ln -sf /etc/nginx/sites-available/bookshop /etc/nginx/sites-enabled/bookshop
sudo rm -f /etc/nginx/sites-enabled/default

# Nginx 설정 테스트
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
echo "  Nginx 상태: $(sudo systemctl is-active nginx)"

# 5단계: Let's Encrypt SSL 인증서 발급
echo ""
echo "📦 [5/6] Let's Encrypt SSL 인증서 발급..."
if ! command -v certbot &> /dev/null; then
    sudo apt install -y certbot python3-certbot-nginx
fi

# SSL 인증서가 이미 있는지 확인
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "  SSL 인증서를 새로 발급합니다..."
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN
else
    echo "  SSL 인증서가 이미 존재합니다. 갱신을 확인합니다..."
    sudo certbot renew --dry-run
fi

# 인증서 자동 갱신 타이머 확인
sudo systemctl enable certbot.timer
echo "  인증서 자동 갱신: 활성화됨"

# 6단계: 앱 설정 및 시작
echo ""
echo "📦 [6/6] 앱 설정 및 시작..."
cd "$APP_DIR"
npm install --production

# .env 파일 확인
if [ ! -f ".env" ]; then
    echo ""
    echo "⚠️  .env 파일이 없습니다!"
    echo "  다음 명령어로 .env 파일을 생성하세요:"
    echo "  cp .env.example .env"
    echo "  nano .env  # 실제 값으로 수정"
    echo ""
fi

# PM2로 서버 시작
pm2 restart ecosystem.config.js --env production 2>/dev/null || pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup systemd -u ubuntu --hp /home/ubuntu 2>/dev/null || true

# Nginx 최종 리로드
sudo nginx -t && sudo systemctl reload nginx

echo ""
echo "=========================================="
echo " 설정 완료!"
echo "=========================================="
echo ""
echo " 🌐 사이트: https://$DOMAIN"
echo " 📊 PM2 상태: pm2 list"
echo " 📋 로그 확인: pm2 logs book-shop"
echo ""
echo " ⚠️  AWS Lightsail 방화벽에서 다음 포트를 열어야 합니다:"
echo "    - TCP 80  (HTTP → HTTPS 리다이렉트)"
echo "    - TCP 443 (HTTPS)"
echo "    - TCP 22  (SSH)"
echo ""
