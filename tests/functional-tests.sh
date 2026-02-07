#!/bin/bash

# ============================================
# 북샵 프로젝트 - 기능 테스트 스크립트
# ============================================
# 모든 API 엔드포인트와 주요 기능이 정상 작동하는지 자동 테스트
#
# 사용법:
#   1. 서버 시작: npm start
#   2. 새 터미널에서: bash tests/functional-tests.sh
#
# 요구사항:
#   - curl: HTTP 요청
#   - jq: JSON 파싱
# ============================================

set -e  # 에러 시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BASE_URL="http://localhost:3000"
PASS=0
FAIL=0
TEST_EMAIL="test_$(date +%s)@example.com"  # 타임스탬프로 고유한 이메일 생성
TEST_PASSWORD="Test123!@#"

# 헬퍼 함수
print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_test() {
  echo -n "🧪 $1 ... "
}

print_pass() {
  echo -e "${GREEN}✅ 통과${NC}"
  ((PASS++)) || true  # set -e 에러 방지
}

print_fail() {
  echo -e "${RED}❌ 실패${NC}: $1"
  ((FAIL++)) || true  # set -e 에러 방지
}

# ============================================
# 1. 회원가입 테스트
# ============================================
test_register() {
  print_header "1. 회원가입 테스트"

  # 1-1. 정상 가입
  print_test "정상 회원가입"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

  if echo "$RESPONSE" | jq -e '.user.id' > /dev/null 2>&1; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 1-2. 중복 이메일
  print_test "중복 이메일 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

  if echo "$RESPONSE" | jq -e '.error' | grep -q "이미 가입된" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 1-3. 짧은 비밀번호
  print_test "짧은 비밀번호 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d '{"email":"short@example.com","password":"12345"}')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "8자 이상" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 1-4. 필수 필드 누락
  print_test "필수 필드 누락 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d '{"email":"missing@example.com"}')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "모두 입력" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi
}

# ============================================
# 2. 로그인 테스트
# ============================================
test_login() {
  print_header "2. 로그인 테스트"

  # 2-1. 정상 로그인
  print_test "정상 로그인 (JWT 발급)"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

  TOKEN=$(echo "$RESPONSE" | jq -r '.token' 2>/dev/null)

  if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
    export AUTH_TOKEN="$TOKEN"
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 2-2. 잘못된 이메일
  print_test "존재하지 않는 이메일"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d '{"email":"nonexistent@example.com","password":"Test123!@#"}')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "올바르지 않습니다" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 2-3. 잘못된 비밀번호
  print_test "잘못된 비밀번호"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"WrongPassword!\"}")

  if echo "$RESPONSE" | jq -e '.error' | grep -q "올바르지 않습니다" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi
}

# ============================================
# 3. 인증 API 테스트
# ============================================
test_authenticated_apis() {
  print_header "3. 인증 API 테스트"

  # 3-1. 내 정보 조회 (인증)
  print_test "내 정보 조회 (인증)"
  RESPONSE=$(curl -s -X GET $BASE_URL/api/me \
    -H "Authorization: Bearer $AUTH_TOKEN")

  if echo "$RESPONSE" | jq -e '.user.email' | grep -q "$TEST_EMAIL" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 3-2. 토큰 없이 접근
  print_test "토큰 없이 접근 차단"
  RESPONSE=$(curl -s -X GET $BASE_URL/api/me)

  if echo "$RESPONSE" | jq -e '.error' | grep -q "로그인이 필요" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 3-3. 잘못된 토큰으로 접근
  print_test "잘못된 토큰 차단"
  RESPONSE=$(curl -s -X GET $BASE_URL/api/me \
    -H "Authorization: Bearer invalid-token-xyz")

  if echo "$RESPONSE" | jq -e '.error' | grep -q "유효하지 않은" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 3-4. 주문 내역 조회 (인증)
  print_test "주문 내역 조회 (인증)"
  RESPONSE=$(curl -s -X GET $BASE_URL/api/orders \
    -H "Authorization: Bearer $AUTH_TOKEN")

  if echo "$RESPONSE" | jq -e '.orders' > /dev/null 2>&1; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi
}

# ============================================
# 4. 결제 금액 검증 테스트
# ============================================
test_payment_validation() {
  print_header "4. 결제 금액 검증 테스트"

  # 4-1. 금액 조작 시도
  print_test "금액 조작 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/payments/confirm \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d '{
      "paymentKey": "test-key",
      "orderId": "test-'$(date +%s)'",
      "amount": 1000,
      "items": [
        {"bookId": 1, "title": "모던 자바스크립트 Deep Dive", "author": "이웅모", "price": 45000, "quantity": 1}
      ]
    }')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "결제 금액이 올바르지 않습니다" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 4-2. 가격 조작 시도
  print_test "가격 조작 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/payments/confirm \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d '{
      "paymentKey": "test-key",
      "orderId": "test-'$(date +%s)'",
      "amount": 103,
      "items": [
        {"bookId": 1, "title": "모던 자바스크립트 Deep Dive", "author": "이웅모", "price": 100, "quantity": 1}
      ]
    }')

  if echo "$RESPONSE" | jq -e '.detail' | grep -q "가격이 일치하지 않습니다" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 4-3. 존재하지 않는 상품
  print_test "존재하지 않는 상품 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/payments/confirm \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d '{
      "paymentKey": "test-key",
      "orderId": "test-'$(date +%s)'",
      "amount": 99999,
      "items": [
        {"bookId": 999, "title": "존재하지 않는 책", "author": "알 수 없음", "price": 99999, "quantity": 1}
      ]
    }')

  if echo "$RESPONSE" | jq -e '.detail' | grep -q "존재하지 않는 상품" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi

  # 4-4. 음수 수량
  print_test "음수 수량 차단"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/payments/confirm \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d '{
      "paymentKey": "test-key",
      "orderId": "test-'$(date +%s)'",
      "amount": -45000,
      "items": [
        {"bookId": 1, "title": "모던 자바스크립트 Deep Dive", "author": "이웅모", "price": 45000, "quantity": -1}
      ]
    }')

  if echo "$RESPONSE" | jq -e '.detail' | grep -q "잘못된 주문 상품 정보" 2>/dev/null; then
    print_pass
  else
    print_fail "$RESPONSE"
  fi
}

# ============================================
# 실행
# ============================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║     북샵 프로젝트 - 기능 테스트 시작      ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# jq 설치 확인
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ jq가 설치되지 않았습니다${NC}"
  echo "설치 방법: brew install jq"
  exit 1
fi

# 서버 연결 확인
if ! curl -s $BASE_URL > /dev/null; then
  echo -e "${RED}❌ 서버에 연결할 수 없습니다${NC}"
  echo "서버를 먼저 시작하세요: npm start"
  exit 1
fi

# 테스트 실행
test_register
test_login
test_authenticated_apis
test_payment_validation

# ============================================
# 결과 요약
# ============================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║          테스트 결과 요약                  ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ 통과: $PASS${NC}"
echo -e "${RED}❌ 실패: $FAIL${NC}"
echo "총 테스트: $((PASS + FAIL))"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}🎉 모든 기능 테스트를 통과했습니다!${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  $FAIL개의 테스트가 실패했습니다.${NC}"
  exit 1
fi
