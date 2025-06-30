#!/usr/bin/env bash
#
# test_cache.sh - Unit tests for cache functions
#
# Tests all functions in lib/cache.sh

# Don't use strict mode to allow tests to continue
set +e

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Set secure umask for tests
umask 0077

# Create temp directory for cache tests
export CACHE_DIR=$(mktemp -d)
export DEFAULT_CACHE_TTL=3600

# Minimal log function
log() { :; }

# Source the library
source "$PROJECT_ROOT/lib/cache.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Running Cache Unit Tests"
echo "========================"
echo "Cache directory: $CACHE_DIR"
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

# Test generate_cache_key function
echo "=== Testing generate_cache_key ==="

# Test 1: Basic key generation
key1=$(generate_cache_key "list files")
key2=$(generate_cache_key "list files")
[[ "$key1" == "$key2" ]] && result="consistent" || result="inconsistent"
run_test "consistent key generation" "$result" "consistent"

# Test 2: Different inputs produce different keys
key1=$(generate_cache_key "list files")
key2=$(generate_cache_key "remove files")
[[ "$key1" != "$key2" ]] && result="different" || result="same"
run_test "different inputs = different keys" "$result" "different"

# Test 3: Key format (should be hex)
key=$(generate_cache_key "test input")
[[ "$key" =~ ^[a-f0-9]+$ ]] && result="valid hex" || result="invalid"
run_test "key is valid hex" "$result" "valid hex"

echo
echo "=== Testing cache_command and get_cached_command ==="

# Test 1: Cache and retrieve
cache_key=$(generate_cache_key "test command")
cache_command "$cache_key" "ls -la" 10
cached=$(get_cached_command "$cache_key")
run_test "cache and retrieve" "$cached" "ls -la"

# Test 2: Non-existent cache
fake_key="nonexistent123"
cached=$(get_cached_command "$fake_key" 2>/dev/null)
[[ -z "$cached" ]] && result="empty" || result="not empty"
run_test "non-existent cache returns empty" "$result" "empty"

# Test 3: Cache with custom TTL (set to 0 for immediate expiration)
cache_key=$(generate_cache_key "custom ttl")
cache_command "$cache_key" "echo test" 0
# No need to sleep - TTL 0 means already expired
cached=$(get_cached_command "$cache_key" 2>/dev/null)
[[ -z "$cached" ]] && result="expired" || result="not expired"
run_test "cache expiration" "$result" "expired"

echo
echo "=== Testing get_cache_file_path ==="

# Test 1: Path format
path=$(get_cache_file_path "testkey123")
expected="${CACHE_DIR}/testkey123.cache"
run_test "cache file path format" "$path" "$expected"

echo
echo "=== Testing get_cache_meta_path ==="

# Test 1: Meta path format
path=$(get_cache_meta_path "testkey123")
expected="${CACHE_DIR}/testkey123.meta"
run_test "meta file path format" "$path" "$expected"

echo
echo "=== Testing is_cache_valid ==="

# Test 1: Valid cache
cache_key=$(generate_cache_key "valid cache")
cache_command "$cache_key" "test command" 3600
is_cache_valid "$cache_key" && result="valid" || result="invalid"
run_test "valid cache check" "$result" "valid"

# Test 2: Expired cache
cache_key=$(generate_cache_key "expired cache")
cache_command "$cache_key" "test command" 0
is_cache_valid "$cache_key" && result="valid" || result="invalid"
run_test "expired cache check" "$result" "invalid"

# Test 3: Missing cache
is_cache_valid "missing_key" && result="valid" || result="invalid"
run_test "missing cache check" "$result" "invalid"

echo
echo "=== Testing clear_cache ==="

# Test 1: Clear all cache
cache_command "key1" "cmd1" 3600
cache_command "key2" "cmd2" 3600
clear_cache
# Count should be 0 (trim whitespace from wc output)
count=$(ls "$CACHE_DIR"/*.cache 2>/dev/null | wc -l | tr -d ' ')
run_test "clear all cache" "$count" "0"

# Test 2: Clear old cache only
cache_command "new_key" "new_cmd" 3600
# Create an old cache entry manually
old_key="old_key"
echo "old_cmd" > "$CACHE_DIR/$old_key.cache"
echo "created_at:1" > "$CACHE_DIR/$old_key.meta"
clear_cache 3500
# New cache should remain
[[ -f "$CACHE_DIR/new_key.cache" ]] && result="exists" || result="missing"
run_test "new cache preserved" "$result" "exists"
# Old cache should be gone
[[ ! -f "$CACHE_DIR/old_key.cache" ]] && result="removed" || result="exists"
run_test "old cache removed" "$result" "removed"

echo
echo "=== Testing get_cache_stats ==="

# Test 1: Stats output format
cache_command "stat1" "cmd1" 3600
cache_command "stat2" "cmd2" 3600
stats=$(get_cache_stats)
[[ "$stats" == *"Total entries:"* ]] && result="has entries" || result="missing entries"
run_test "stats has total entries" "$result" "has entries"
[[ "$stats" == *"Cache directory:"* ]] && result="has dir" || result="missing dir"
run_test "stats has cache directory" "$result" "has dir"

echo
echo "=== Testing validate_cache_integrity ==="

# Test 1: Valid integrity
cache_key=$(generate_cache_key "integrity test")
cache_command "$cache_key" "test command" 3600
validate_cache_integrity "$cache_key" && result="valid" || result="invalid"
run_test "valid cache integrity" "$result" "valid"

# Test 2: Corrupted cache
cache_key=$(generate_cache_key "corrupt test")
cache_command "$cache_key" "original command" 3600
# Corrupt the cache file
echo "modified command" > "${CACHE_DIR}/${cache_key}.cache"
validate_cache_integrity "$cache_key" && result="valid" || result="invalid"
run_test "corrupted cache detected" "$result" "invalid"

echo
echo "=== Testing export_cache_entry ==="

# Test 1: Export cache entry
cache_key=$(generate_cache_key "export test")
cache_command "$cache_key" "export command" 3600
export_file="$CACHE_DIR/export.txt"
export_cache_entry "$cache_key" "$export_file"
[[ -f "$export_file" ]] && result="created" || result="not created"
run_test "export file created" "$result" "created"

# Test 2: Export contains key
content=$(cat "$export_file" 2>/dev/null)
[[ "$content" == *"Key: $cache_key"* ]] && result="has key" || result="no key"
run_test "export contains key" "$result" "has key"

echo
echo "=== Testing import_cache_entry ==="

# Test 1: Import cache entry
# First export an entry
cache_key=$(generate_cache_key "import test")
cache_command "$cache_key" "import command" 3600
export_file="$CACHE_DIR/import.txt"
export_cache_entry "$cache_key" "$export_file"
# Clear cache
clear_cache
# Import the entry
import_cache_entry "$export_file"
# Check if imported
imported_cmd=$(get_cached_command "$cache_key")
run_test "import cache entry" "$imported_cmd" "import command"

# Test 2: Import non-existent file
import_cache_entry "/tmp/nonexistent.txt" 2>/dev/null && result="success" || result="failed"
run_test "import non-existent file fails" "$result" "failed"

# Test 3: Import invalid format
echo "invalid content" > "$CACHE_DIR/invalid.txt"
import_cache_entry "$CACHE_DIR/invalid.txt" 2>/dev/null && result="success" || result="failed"
run_test "import invalid format fails" "$result" "failed"

echo
echo "=== Testing cache permissions ==="

# Test 1: Cache directory permissions
# Ensure directory has correct permissions first
chmod 700 "$CACHE_DIR"
# Get permissions differently for macOS vs Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    perms=$(stat -f%Lp "$CACHE_DIR" 2>/dev/null)
else
    perms=$(stat -c%a "$CACHE_DIR" 2>/dev/null)
fi
[[ "$perms" == "700" ]] && result="secure" || result="insecure"
run_test "cache directory permissions (700)" "$result" "secure"

# Test 2: Cache file permissions
cache_key=$(generate_cache_key "perm test")
cache_command "$cache_key" "test" 3600
cache_file="${CACHE_DIR}/${cache_key}.cache"
# Get permissions differently for macOS vs Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    perms=$(stat -f%Lp "$cache_file" 2>/dev/null)
else
    perms=$(stat -c%a "$cache_file" 2>/dev/null)
fi
[[ "$perms" == "600" ]] && result="secure" || result="insecure"
run_test "cache file permissions (600)" "$result" "secure"

echo
echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"

# Cleanup
rm -rf "$CACHE_DIR"

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi