#!/bin/bash

# ============================================
# 북샵 프로젝트 - 성능 테스트 스크립트
# ============================================
# 동시 접속, 응답 시간, 부하 테스트
#
# 사용법:
#   1. 서버 시작: npm start
#   2. 새 터미널에서: bash tests/performance-tests.sh
#
# 요구사항:
#   - curl: HTTP 요청
#   - jq: JSON 파싱
#   - ab (Apache Bench): 부하 테스트 (선택사항)
# ============================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_URL="http://localhost:3000"
PASS=0
WARN=0
FAIL=0

# 테스트용 토큰 (실제 로그인으로 얻어야 함)
TEST_EMAIL="perf_test_$(date +%s)@example.com"
TEST_PASSWORD="Test123!@#"

# 헬퍼 함수
print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_test() {
  echo -n "⚡ $1 ... "
}

print_pass() {
  echo -e "${GREEN}✅ 양호${NC} ($1)"
  ((PASS++)) || true  # set -e 에러 방지
}

print_warn() {
  echo -e "${YELLOW}⚠️ 주의${NC}: $1"
  ((WARN++)) || true  # set -e 에러 방지
}

print_fail() {
  echo -e "${RED}❌ 느림${NC}: $1"
  ((FAIL++)) || true  # set -e 에러 방지
}

print_info() {
  echo -e "${BLUE}ℹ️ $1${NC}"
}

# ============================================
# 0. 사전 준비 - 테스트 사용자 생성 및 로그인
# ============================================
setup_test_user() {
  print_header "0. 테스트 환경 준비"

  print_info "테스트 사용자 생성 중..."

  # 회원가입
  REGISTER_RESPONSE=$(curl -s -X POST $BASE_URL/api/register \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

  if echo "$REGISTER_RESPONSE" | jq -e '.user.id' > /dev/null 2>&1; then
    print_info "✅ 테스트 사용자 생성 완료"
  else
    print_info "⚠️ 사용자 생성 실패 (이미 존재할 수 있음)"
  fi

  # 로그인하여 토큰 획득
  LOGIN_RESPONSE=$(curl -s -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

  TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)

  if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
    export AUTH_TOKEN="$TOKEN"
    print_info "✅ 인증 토큰 획득 완료"
  else
    print_info "❌ 로그인 실패 - 인증이 필요한 테스트를 건너뜁니다"
  fi
}

# ============================================
# 1. 응답 시간 테스트
# ============================================
test_response_time() {
  print_header "1. 응답 시간 테스트"

  # 1-1. 메인 페이지 응답 시간
  print_test "메인 페이지 (GET /)"
  RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" $BASE_URL)
  RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc)

  if (( $(echo "$RESPONSE_TIME < 0.5" | bc -l) )); then
    print_pass "${RESPONSE_TIME}초 (${RESPONSE_TIME_MS}ms)"
  elif (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
    print_warn "${RESPONSE_TIME}초 (느림)"
  else
    print_fail "${RESPONSE_TIME}초 (매우 느림)"
  fi

  # 1-2. 로그인 API 응답 시간
  print_test "로그인 API (POST /api/login)"
  RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" \
    -X POST $BASE_URL/api/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")
  RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc)

  if (( $(echo "$RESPONSE_TIME < 0.5" | bc -l) )); then
    print_pass "${RESPONSE_TIME}초 (${RESPONSE_TIME_MS}ms)"
  elif (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
    print_warn "${RESPONSE_TIME}초 (느림)"
  else
    print_fail "${RESPONSE_TIME}초 (매우 느림)"
  fi

  # 1-3. 내 정보 조회 API 응답 시간
  if [ -n "$AUTH_TOKEN" ]; then
    print_test "내 정보 조회 API (GET /api/me)"
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      $BASE_URL/api/me)
    RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc)

    if (( $(echo "$RESPONSE_TIME < 0.3" | bc -l) )); then
      print_pass "${RESPONSE_TIME}초 (${RESPONSE_TIME_MS}ms)"
    elif (( $(echo "$RESPONSE_TIME < 0.5" | bc -l) )); then
      print_warn "${RESPONSE_TIME}초 (느림)"
    else
      print_fail "${RESPONSE_TIME}초 (매우 느림)"
    fi

    # 1-4. 주문 내역 조회 API 응답 시간
    print_test "주문 내역 조회 API (GET /api/orders)"
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      $BASE_URL/api/orders)
    RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc)

    if (( $(echo "$RESPONSE_TIME < 0.5" | bc -l) )); then
      print_pass "${RESPONSE_TIME}초 (${RESPONSE_TIME_MS}ms)"
    elif (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
      print_warn "${RESPONSE_TIME}초 (느림)"
    else
      print_fail "${RESPONSE_TIME}초 (매우 느림)"
    fi
  else
    print_info "토큰 없음 - 인증 API 응답 시간 테스트 건너뜀"
  fi
}

# ============================================
# 2. 동시 접속 테스트 (curl 기반)
# ============================================
test_concurrent_requests() {
  print_header "2. 동시 접속 테스트"

  print_test "동시 50개 요청 (메인 페이지)"

  # 임시 파일 준비
  TEMP_DIR=$(mktemp -d)
  RESULTS_FILE="$TEMP_DIR/results.txt"

  # 동시에 50개 요청 보내기
  START_TIME=$(date +%s.%N)

  for i in {1..50}; do
    (
      RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" $BASE_URL 2>/dev/null)
      echo "$RESPONSE_TIME" >> "$RESULTS_FILE"
    ) &
  done

  # 모든 백그라운드 작업 대기
  wait

  END_TIME=$(date +%s.%N)
  TOTAL_TIME=$(echo "$END_TIME - $START_TIME" | bc)

  # 평균 응답 시간 계산
  if [ -f "$RESULTS_FILE" ] && [ -s "$RESULTS_FILE" ]; then
    AVG_TIME=$(awk '{ total += $1; count++ } END { print total/count }' "$RESULTS_FILE")
    AVG_TIME_MS=$(echo "$AVG_TIME * 1000" | bc)

    print_info "총 소요 시간: ${TOTAL_TIME}초"
    print_info "평균 응답 시간: ${AVG_TIME}초 (${AVG_TIME_MS}ms)"

    if (( $(echo "$AVG_TIME < 0.5" | bc -l) )); then
      print_pass "평균 ${AVG_TIME}초"
    elif (( $(echo "$AVG_TIME < 1.0" | bc -l) )); then
      print_warn "평균 ${AVG_TIME}초 (느림)"
    else
      print_fail "평균 ${AVG_TIME}초 (매우 느림)"
    fi
  else
    print_fail "테스트 실패 (결과 파일 없음)"
  fi

  # 정리
  rm -rf "$TEMP_DIR"
}

# ============================================
# 3. 순차 대량 요청 테스트
# ============================================
test_sequential_requests() {
  print_header "3. 순차 대량 요청 테스트"

  print_test "100회 연속 요청 (로그인 API)"

  START_TIME=$(date +%s.%N)
  SUCCESS_COUNT=0
  FAIL_COUNT=0

  for i in {1..100}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST $BASE_URL/api/login \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" 2>/dev/null)

    if [ "$HTTP_CODE" == "200" ]; then
      ((SUCCESS_COUNT++))
    else
      ((FAIL_COUNT++))
    fi
  done

  END_TIME=$(date +%s.%N)
  TOTAL_TIME=$(echo "$END_TIME - $START_TIME" | bc)
  AVG_TIME=$(echo "$TOTAL_TIME / 100" | bc -l)

  print_info "총 소요 시간: ${TOTAL_TIME}초"
  print_info "평균 응답 시간: ${AVG_TIME}초"
  print_info "성공: ${SUCCESS_COUNT}회, 실패: ${FAIL_COUNT}회"

  if [ $SUCCESS_COUNT -eq 100 ]; then
    print_pass "100% 성공 (평균 ${AVG_TIME}초)"
  elif [ $SUCCESS_COUNT -ge 95 ]; then
    print_warn "${SUCCESS_COUNT}% 성공"
  else
    print_fail "${SUCCESS_COUNT}% 성공 (안정성 문제)"
  fi
}

# ============================================
# 4. Apache Bench 부하 테스트 (선택사항)
# ============================================
test_with_apache_bench() {
  print_header "4. Apache Bench 부하 테스트"

  # ab 설치 확인
  if ! command -v ab &> /dev/null; then
    print_info "⚠️ Apache Bench(ab)가 설치되지 않았습니다 - 이 테스트를 건너뜁니다"
    print_info "설치 방법 (macOS): ab는 기본 설치되어 있지만, Xcode Command Line Tools가 필요할 수 있습니다"
    print_info "설치 방법 (Ubuntu): sudo apt-get install apache2-utils"
    return
  fi

  print_test "1000개 요청 / 동시 100명 (GET /)"

  # ab 실행 (타임아웃 60초)
  AB_OUTPUT=$(ab -n 1000 -c 100 -t 60 $BASE_URL/ 2>&1)

  # 결과 파싱
  REQUESTS_PER_SEC=$(echo "$AB_OUTPUT" | grep "Requests per second" | awk '{print $4}')
  TIME_PER_REQUEST=$(echo "$AB_OUTPUT" | grep "Time per request" | head -1 | awk '{print $4}')
  FAILED_REQUESTS=$(echo "$AB_OUTPUT" | grep "Failed requests" | awk '{print $3}')

  print_info "초당 요청 수: ${REQUESTS_PER_SEC} req/sec"
  print_info "평균 응답 시간: ${TIME_PER_REQUEST}ms"
  print_info "실패한 요청: ${FAILED_REQUESTS}개"

  # 성능 평가
  if [ "$FAILED_REQUESTS" == "0" ] && (( $(echo "$REQUESTS_PER_SEC > 50" | bc -l) )); then
    print_pass "${REQUESTS_PER_SEC} req/sec"
  elif [ "$FAILED_REQUESTS" == "0" ]; then
    print_warn "${REQUESTS_PER_SEC} req/sec (낮은 처리량)"
  else
    print_fail "${FAILED_REQUESTS}개 요청 실패"
  fi
}

# ============================================
# 실행
# ============================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║     북샵 프로젝트 - 성능 테스트 시작      ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# bc 설치 확인 (macOS에서 소수점 계산용)
if ! command -v bc &> /dev/null; then
  echo -e "${RED}❌ bc가 설치되지 않았습니다${NC}"
  echo "설치 방법: brew install bc"
  exit 1
fi

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
setup_test_user
test_response_time
test_concurrent_requests
test_sequential_requests
test_with_apache_bench

# ============================================
# 결과 요약
# ============================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║          성능 테스트 결과 요약             ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ 양호: $PASS${NC}"
echo -e "${YELLOW}⚠️ 주의: $WARN${NC}"
echo -e "${RED}❌ 느림: $FAIL${NC}"
echo "총 테스트: $((PASS + WARN + FAIL))"
echo ""

if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo -e "${GREEN}🎉 모든 성능 테스트를 통과했습니다!${NC}"
  exit 0
elif [ $FAIL -eq 0 ]; then
  echo -e "${YELLOW}⚠️  $WARN개의 주의 항목이 있습니다.${NC}"
  exit 0
else
  echo -e "${RED}❌ $FAIL개의 성능 문제가 발견되었습니다!${NC}"
  exit 1
fi
