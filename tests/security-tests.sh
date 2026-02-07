#!/bin/bash

# ============================================
# 북샵 프로젝트 - 보안 테스트 스크립트
# ============================================
# OWASP Top 10 기준 보안 취약점 테스트
#
# 사용법:
#   1. 서버 시작: npm start
#   2. 새 터미널에서: bash tests/security-tests.sh
# ============================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BASE_URL="http://localhost:3000"
PASS=0
FAIL=0
WARN=0

# 헬퍼 함수
print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_test() {
  echo -n "🔒 $1 ... "
}

print_pass() {
  echo -e "${GREEN}✅ 안전${NC}"
  ((PASS++)) || true  # set -e 에러 방지
}

print_fail() {
  echo -e "${RED}❌ 취약${NC}: $1"
  ((FAIL++)) || true  # set -e 에러 방지
}

print_warn() {
  echo -e "${YELLOW}⚠️ 취약${NC}: $1"
  ((WARN++)) || true  # set -e 에러 방지
}

# ============================================
# 1. SQL 인젝션 테스트
# ============================================
test_sql_injection() {
  print_header "1. SQL 인젝션 테스트"

  # 1-1. 로그인 SQL 인젝션
  print_test "로그인 SQL 인젝션"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d '{"email":"'\'' OR '\''1'\''='\''1","password":"anything"}')

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    print_pass
  else
    print_fail "SQL 인젝션 가능!"
  fi

  # 1-2. 회원가입 SQL 인젝션
  print_test "회원가입 SQL 인젝션"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d '{"email":"admin'\''--","password":"Test123!@#"}')

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    print_pass
  else
    print_fail "SQL 인젝션 가능!"
  fi
}

# ============================================
# 2. 인증 우회 테스트
# ============================================
test_auth_bypass() {
  print_header "2. 인증 우회 테스트"

  # 2-1. JWT 없이 접근
  print_test "JWT 없이 보호된 API 접근"
  RESPONSE=$(curl -s -X GET $BASE_URL/api/me)

  if echo "$RESPONSE" | jq -e '.error' | grep -q "로그인이 필요" 2>/dev/null; then
    print_pass
  else
    print_fail "인증 없이 접근 가능!"
  fi

  # 2-2. 잘못된 JWT
  print_test "잘못된 JWT로 접근"
  RESPONSE=$(curl -s -X GET $BASE_URL/api/me \
    -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature")

  if echo "$RESPONSE" | jq -e '.error' | grep -q "유효하지 않은" 2>/dev/null; then
    print_pass
  else
    print_fail "잘못된 JWT로 접근 가능!"
  fi

  # 2-3. JWT 변조
  print_test "JWT 변조"
  # 정상 로그인
  LOGIN_RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"Test123!@#"}')

  VALID_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)

  if [ "$VALID_TOKEN" != "null" ] && [ -n "$VALID_TOKEN" ]; then
    # 토큰의 마지막 문자 변경
    MODIFIED_TOKEN="${VALID_TOKEN:0:-1}X"

    RESPONSE=$(curl -s -X GET $BASE_URL/api/me \
      -H "Authorization: Bearer $MODIFIED_TOKEN")

    if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
      print_pass
    else
      print_fail "변조된 JWT로 접근 가능!"
    fi
  else
    print_warn "테스트 사용자 없음 (먼저 회원가입 필요)"
  fi
}

# ============================================
# 3. 브루트포스 공격 테스트
# ============================================
test_brute_force() {
  print_header "3. 브루트포스 공격 테스트"

  print_test "로그인 브루트포스 (6회 시도)"

  # 6회 연속 시도
  for i in {1..6}; do
    curl -s -X POST $BASE_URL/api/login \
      -H "Content-Type: application/json" \
      -d '{"email":"test@example.com","password":"wrongpassword"}' > /dev/null 2>&1
    sleep 0.1
  done

  # 7번째 시도
  RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"wrongpassword"}')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "너무 많은" 2>/dev/null; then
    print_pass
  else
    print_warn "Rate limiting 미설정 (수정 필요)"
  fi
}

# ============================================
# 4. 금액 조작 테스트
# ============================================
test_price_manipulation() {
  print_header "4. 금액 조작 테스트"

  # 로그인하여 토큰 얻기
  LOGIN_RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"Test123!@#"}')

  TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)

  if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    print_warn "로그인 실패 (테스트 사용자 없음)"
    return
  fi

  # 4-1. 금액 인하
  print_test "금액 인하 시도"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/payments/confirm \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
      "paymentKey": "security-test",
      "orderId": "sec-'$(date +%s)'",
      "amount": 1000,
      "items": [
        {"bookId": 1, "title": "모던 자바스크립트 Deep Dive", "author": "이웅모", "price": 45000, "quantity": 1}
      ]
    }')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "올바르지 않습니다" 2>/dev/null; then
    print_pass
  else
    print_fail "금액 조작 가능!"
  fi

  # 4-2. 배송비 제거
  print_test "배송비 제거 시도"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/payments/confirm \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
      "paymentKey": "security-test",
      "orderId": "sec-'$(date +%s)'",
      "amount": 8100,
      "items": [
        {"bookId": 3, "title": "데미안", "author": "헤르만 헤세", "price": 8100, "quantity": 1}
      ]
    }')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "올바르지 않습니다" 2>/dev/null; then
    print_pass
  else
    print_fail "배송비 제거 가능!"
  fi
}

# ============================================
# 5. 입력값 검증 테스트
# ============================================
test_input_validation() {
  print_header "5. 입력값 검증 테스트"

  # 5-1. 이메일 형식 검증
  print_test "이메일 형식 검증"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d '{"email":"invalid-email","password":"Test123!@#"}')

  if echo "$RESPONSE" | jq -e '.error' | grep -q "올바른 이메일" 2>/dev/null; then
    print_pass
  else
    print_warn "이메일 형식 검증 없음 (수정 필요)"
  fi

  # 5-2. 비밀번호 정책
  print_test "비밀번호 정책 검증"
  RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d '{"email":"weak@example.com","password":"123456"}')

  if echo "$RESPONSE" | jq -e '.error' | grep -qE "(대문자|숫자|특수문자|8자)" 2>/dev/null; then
    print_pass
  else
    print_warn "약한 비밀번호 정책 (수정 필요)"
  fi
}

# ============================================
# 실행
# ============================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║     북샵 프로젝트 - 보안 테스트 시작      ║"
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
test_sql_injection
test_auth_bypass
test_brute_force
test_price_manipulation
test_input_validation

# ============================================
# 결과 요약
# ============================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║          보안 테스트 결과 요약             ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ 안전: $PASS${NC}"
echo -e "${YELLOW}⚠️ 취약 (수정 가능): $WARN${NC}"
echo -e "${RED}❌ 치명적 취약점: $FAIL${NC}"
echo "총 테스트: $((PASS + WARN + FAIL))"
echo ""

if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo -e "${GREEN}🎉 모든 보안 테스트를 통과했습니다!${NC}"
  exit 0
elif [ $FAIL -eq 0 ]; then
  echo -e "${YELLOW}⚠️  $WARN개의 개선 가능한 취약점이 있습니다.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAIL개의 치명적 취약점이 발견되었습니다!${NC}"
  exit 1
fi
