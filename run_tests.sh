#!/usr/bin/env bash
#
# run_tests.sh - Test runner for makecmd
#
# Runs all test suites and reports results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Test results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo -e "${BLUE}${BOLD}makecmd Test Suite${NC}"
echo "=================="
echo

# Run unit tests
echo -e "${BOLD}Unit Tests${NC}"
echo "----------"

# Run sanitizer tests
echo "Running sanitizer tests..."
((TOTAL_SUITES++))
if "$SCRIPT_DIR/tests/unit/test_sanitizer.sh"; then
    ((PASSED_SUITES++))
else
    ((FAILED_SUITES++))
fi
echo

# Run validator tests
echo "Running validator tests..."
((TOTAL_SUITES++))
if "$SCRIPT_DIR/tests/unit/test_validator.sh"; then
    ((PASSED_SUITES++))
else
    ((FAILED_SUITES++))
fi
echo

# Run cache tests
echo "Running cache tests..."
((TOTAL_SUITES++))
if "$SCRIPT_DIR/tests/unit/test_cache.sh"; then
    ((PASSED_SUITES++))
else
    ((FAILED_SUITES++))
fi
echo

# Run config tests
echo "Running config tests..."
((TOTAL_SUITES++))
if "$SCRIPT_DIR/tests/unit/test_config.sh"; then
    ((PASSED_SUITES++))
else
    ((FAILED_SUITES++))
fi
echo

# Run security tests
echo -e "${BOLD}Security Tests${NC}"
echo "--------------"
((TOTAL_SUITES++))
if "$SCRIPT_DIR/tests/security/test_injection.sh"; then
    ((PASSED_SUITES++))
else
    ((FAILED_SUITES++))
fi
echo

# Run integration tests
echo -e "${BOLD}Integration Tests${NC}"
echo "-----------------"
((TOTAL_SUITES++))
if "$SCRIPT_DIR/tests/integration/test_basic.sh"; then
    ((PASSED_SUITES++))
else
    ((FAILED_SUITES++))
fi
echo

# Overall summary
echo -e "${BOLD}Overall Summary${NC}"
echo "==============="
echo "Test suites run:    $TOTAL_SUITES"
echo -e "Test suites passed: ${GREEN}$PASSED_SUITES${NC}"
echo -e "Test suites failed: ${RED}$FAILED_SUITES${NC}"

if [[ $FAILED_SUITES -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}All test suites passed!${NC}"
    exit 0
else
    echo -e "\n${RED}${BOLD}Some test suites failed!${NC}"
    exit 1
fi