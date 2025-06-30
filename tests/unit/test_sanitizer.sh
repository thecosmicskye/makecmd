#!/usr/bin/env bash
#
# test_sanitizer.sh - Unit tests for sanitizer functions
#
# Tests all functions in lib/sanitizer.sh

# Don't use strict mode to allow tests to continue
set +e

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Minimal log function
log() { :; }

# Source the library
source "$PROJECT_ROOT/lib/sanitizer.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Running Sanitizer Unit Tests"
echo "============================"
echo

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper function
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
        echo "  Expected: '$expected'"
        echo "  Got: '$result'"
        ((TESTS_FAILED++))
    fi
}

# Test sanitize_input function
echo "=== Testing sanitize_input ==="

# Test 1: Basic input
result=$(sanitize_input "hello world")
run_test "basic input" "$result" "hello world"

# Test 2: Command substitution
result=$(sanitize_input '$(whoami)')
run_test "command substitution" "$result" '\$\(whoami\)'

# Test 3: Backticks
result=$(sanitize_input '`date`')
run_test "backticks" "$result" '\`date\`'

# Test 4: Semicolon
result=$(sanitize_input 'ls; rm file')
run_test "semicolon" "$result" 'ls\; rm file'

# Test 5: Pipe
result=$(sanitize_input 'cat file | grep text')
run_test "pipe" "$result" 'cat file \| grep text'

# Test 6: Background execution
result=$(sanitize_input 'sleep 10 &')
run_test "background execution" "$result" 'sleep 10 \&'

# Test 7: All special characters
result=$(sanitize_input '$;|&`(){}[]<>"'"'")
run_test "all special chars" "$result" '\$\;\|\&\`\(\)\{\}\[\]\<\>\"'"\\'"

# Test 8: Newlines and carriage returns
result=$(sanitize_input $'line1\nline2\rline3')
run_test "newlines removed" "$result" "line1line2line3"

# Test 9: Leading/trailing whitespace
result=$(sanitize_input "  hello world  ")
run_test "whitespace trimmed" "$result" "hello world"

# Test 10: Long input truncation
long_input=$(printf 'a%.0s' {1..600})
result=$(sanitize_input "$long_input")
[[ ${#result} -le 500 ]] && test_result="truncated" || test_result="not truncated"
run_test "long input truncation" "$test_result" "truncated"

echo
echo "=== Testing sanitize_claude_output ==="

# Test 1: Markdown code blocks
result=$(sanitize_claude_output '```bash
ls -la
```')
run_test "markdown removal" "$result" "ls -la"

# Test 2: Newlines (only first line should be taken)
result=$(sanitize_claude_output $'ls\nrm -rf /')
# Check if result has no newlines
[[ "$result" != *$'\n'* ]] && test_result="no newlines" || test_result="has newlines"
run_test "newline removal" "$test_result" "no newlines"

# Test 3: Backticks in output (backticks and their content should be removed)
result=$(sanitize_claude_output 'ls `whoami`')
[[ "$result" != *'`'* ]] && test_result="no backticks" || test_result="has backticks"
run_test "backticks removed" "$test_result" "no backticks"

# Test 4: Command substitution (should be removed)
result=$(sanitize_claude_output 'echo $(date)')
[[ "$result" != *'$('* ]] && test_result="no subshell" || test_result="has subshell"
run_test "command substitution removed" "$test_result" "no subshell"

# Test 5: ANSI escape sequences
result=$(sanitize_claude_output $'ls \033[0;31mfile\033[0m')
run_test "ANSI codes removed" "$result" "ls file"

# Test 6: Trailing semicolon
result=$(sanitize_claude_output 'ls -la;')
run_test "trailing semicolon removed" "$result" "ls -la"

# Test 7: Trailing pipe (should be removed, may have trailing space)
result=$(sanitize_claude_output 'ls |')
# Trim any trailing spaces from result
result=$(echo "$result" | sed 's/[[:space:]]*$//')
[[ "$result" == "ls" ]] && test_result="pipe removed" || test_result="pipe not removed"
run_test "trailing pipe removed" "$test_result" "pipe removed"

# Test 8: Multiple spaces
result=$(sanitize_claude_output 'ls    -la     file')
run_test "multiple spaces collapsed" "$result" "ls -la file"

echo
echo "=== Testing validate_metacharacters ==="

# Test 1: Clean input
validate_metacharacters "ls -la" && result="valid" || result="invalid"
run_test "clean input validation" "$result" "valid"

# Test 2: Unescaped semicolon
validate_metacharacters "ls; rm" && result="valid" || result="invalid"
run_test "unescaped semicolon" "$result" "invalid"

# Test 3: Escaped semicolon
validate_metacharacters "ls\; rm" && result="valid" || result="invalid"
run_test "escaped semicolon" "$result" "valid"

echo
echo "=== Testing check_injection_attempts ==="

# Test 1: Clean command (returns 1 for clean)
check_injection_attempts "ls -la" && result="injection" || result="clean"
run_test "clean command" "$result" "clean"

# Test 2: Command substitution (returns 0 for injection)
check_injection_attempts '$(whoami)' && result="injection" || result="clean"
run_test "command substitution detection" "$result" "injection"

# Test 3: Pipe (returns 0 for injection)
check_injection_attempts "ls | grep" && result="injection" || result="clean"
run_test "pipe detection" "$result" "injection"

echo
echo "=== Testing escape_for_display ==="

# Test 1: Double quotes
result=$(escape_for_display 'say "hello"')
run_test "escape double quotes" "$result" 'say \"hello\"'

# Test 2: Single quotes
result=$(escape_for_display "it's working")
run_test "escape single quotes" "$result" "it\'s working"

# Test 3: Backslashes
result=$(escape_for_display 'path\to\file')
run_test "escape backslashes" "$result" 'path\\to\\file'

echo
echo "=== Testing strip_ansi_codes ==="

# Test 1: ANSI color codes
result=$(strip_ansi_codes $'\033[0;31mred text\033[0m')
run_test "strip color codes" "$result" "red text"

# Test 2: Multiple ANSI codes
result=$(strip_ansi_codes $'\033[1m\033[31mbold red\033[0m')
run_test "strip multiple codes" "$result" "bold red"

echo
echo "=== Testing validate_encoding ==="

# Test 1: Valid UTF-8
validate_encoding "hello world" && result="valid" || result="invalid"
run_test "valid UTF-8" "$result" "valid"

# Test 2: ASCII
validate_encoding "test123" && result="valid" || result="invalid"
run_test "ASCII encoding" "$result" "valid"

echo
echo "=== Testing sanitize_path ==="

# Test 1: Path traversal - should block access to system directories
result=$(sanitize_path "../../../etc/passwd")
# The enhanced sanitize_path should return empty string when trying to access system dirs
run_test "path traversal blocked" "$result" ""

# Test 2: Shell metacharacters in path
result=$(sanitize_path "file;name|test")
run_test "metacharacters in path" "$result" "filenametest"

# Test 3: Leading slashes (not removed by current implementation)
result=$(sanitize_path "///home/user/file")
run_test "leading slashes" "$result" "///home/user/file"

# Test 4: Trailing slashes
result=$(sanitize_path "home/user/")
run_test "trailing slashes removal" "$result" "home/user"

echo
echo "=== Testing check_sensitive_info ==="

# Test 1: Password mention
check_sensitive_info "my password is 123" && result="clean" || result="sensitive"
run_test "password detection" "$result" "sensitive"

# Test 2: API key mention
check_sensitive_info "API_KEY=abc123" && result="clean" || result="sensitive"
run_test "API key detection" "$result" "sensitive"

# Test 3: Clean input
check_sensitive_info "list all files" && result="clean" || result="sensitive"
run_test "clean input - no sensitive info" "$result" "clean"

# Test 4: Token mention
check_sensitive_info "auth token: xyz" && result="clean" || result="sensitive"
run_test "token detection" "$result" "sensitive"

echo
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi