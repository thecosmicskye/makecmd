#!/usr/bin/env bash
#
# test_basic.sh - Basic integration tests for makecmd

# Don't use strict mode to allow tests to continue
set +e

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAKECMD="$PROJECT_ROOT/makecmd"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Running makecmd Integration Tests"
echo "================================="
echo

TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Help command
run_test "help command" "$MAKECMD --help"

# Test 2: Version command
run_test "version command" "$MAKECMD --version"

# Test 3: Dry run flag
run_test "dry run flag" "$MAKECMD --dry-run --help"

# Test 4: Multiple flags
run_test "multiple flags" "$MAKECMD -d -s -n --help"

# Test 5: Invalid option handling
if $MAKECMD --invalid-option 2>/dev/null; then
    echo -e "Testing invalid option handling... ${RED}FAIL${NC} (should have failed)"
    ((TESTS_FAILED++))
else
    echo -e "Testing invalid option handling... ${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
fi

# Test 6: Config file handling
TEST_DIR=$(mktemp -d)
run_test "config loading" "HOME=$TEST_DIR $MAKECMD --help"
rm -rf "$TEST_DIR"

# Test 7: Directory creation
TEST_DIR=$(mktemp -d)
HOME="$TEST_DIR" $MAKECMD --help >/dev/null 2>&1
if [[ -d "$TEST_DIR/.makecmd/cache" ]]; then
    echo -e "Testing cache directory creation... ${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "Testing cache directory creation... ${RED}FAIL${NC}"
    ((TESTS_FAILED++))
fi

if [[ -d "$TEST_DIR/.makecmd/logs" ]]; then
    echo -e "Testing log directory creation... ${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "Testing log directory creation... ${RED}FAIL${NC}"
    ((TESTS_FAILED++))
fi
rm -rf "$TEST_DIR"

# Test 8: Input validation
echo -n "Testing input length validation... "
long_input=$(printf 'a%.0s' {1..1000})
if echo "$long_input" | $MAKECMD --dry-run 2>&1 | grep -q "Input too long"; then
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((TESTS_FAILED++))
fi

echo
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi