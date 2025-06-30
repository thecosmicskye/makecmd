#!/usr/bin/env bash
#
# compat.sh - Compatibility shim for bash 3.2
#
# Provides workarounds for bash 3.2 compatibility

# Check if we have bash 4+ features
readonly BASH_MAJOR="${BASH_VERSION%%.*}"
readonly HAS_ASSOC_ARRAYS=$([[ "$BASH_MAJOR" -ge 4 ]] && echo true || echo false)

# Simple key-value store for bash 3.2
# Uses global variables as a fallback for associative arrays
kv_set() {
    local key="$1"
    local value="$2"
    local prefix="${3:-KV}"
    
    # Sanitize key to be a valid variable name
    key=$(echo "$key" | tr -cd 'a-zA-Z0-9_')
    
    if [[ "$HAS_ASSOC_ARRAYS" == "true" ]]; then
        # Use associative array if available
        eval "${prefix}[$key]=\"$value\""
    else
        # Use individual variables for bash 3.2
        eval "${prefix}_${key}=\"$value\""
    fi
}

kv_get() {
    local key="$1"
    local prefix="${2:-KV}"
    
    # Sanitize key
    key=$(echo "$key" | tr -cd 'a-zA-Z0-9_')
    
    if [[ "$HAS_ASSOC_ARRAYS" == "true" ]]; then
        eval "echo \"\${${prefix}[$key]:-}\""
    else
        eval "echo \"\${${prefix}_${key}:-}\""
    fi
}

kv_exists() {
    local key="$1"
    local prefix="${2:-KV}"
    
    # Sanitize key
    key=$(echo "$key" | tr -cd 'a-zA-Z0-9_')
    
    if [[ "$HAS_ASSOC_ARRAYS" == "true" ]]; then
        eval "[[ -n \"\${${prefix}[$key]+x}\" ]]"
    else
        eval "[[ -n \"\${${prefix}_${key}+x}\" ]]"
    fi
}

kv_unset() {
    local key="$1"
    local prefix="${2:-KV}"
    
    # Sanitize key
    key=$(echo "$key" | tr -cd 'a-zA-Z0-9_')
    
    if [[ "$HAS_ASSOC_ARRAYS" == "true" ]]; then
        eval "unset ${prefix}[$key]"
    else
        eval "unset ${prefix}_${key}"
    fi
}

# Initialize associative arrays if supported
init_kv_store() {
    local store_name="$1"
    
    if [[ "$HAS_ASSOC_ARRAYS" == "true" ]]; then
        eval "declare -gA $store_name"
    fi
    # For bash 3.2, we just use individual variables
}

# Compatibility wrapper for declare -A
declare_assoc_array() {
    local array_name="$1"
    
    if [[ "$HAS_ASSOC_ARRAYS" == "true" ]]; then
        eval "declare -gA $array_name"
    else
        # No-op for bash 3.2, will use kv_* functions instead
        :
    fi
}

# Wrapper for array operations
array_set() {
    local array_name="$1"
    local key="$2"
    local value="$3"
    
    kv_set "$key" "$value" "$array_name"
}

array_get() {
    local array_name="$1"
    local key="$2"
    
    kv_get "$key" "$array_name"
}

# Test for required features
test_bash_features() {
    local missing_features=()
    
    # Test for required builtins
    if ! command -v printf > /dev/null 2>&1; then
        missing_features+=("printf")
    fi
    
    # Test for [[ ]] construct
    if ! [[ 1 -eq 1 ]] 2>/dev/null; then
        missing_features+=("[[]]")
    fi
    
    # Test for $(()) arithmetic
    if ! (( 1 + 1 )) 2>/dev/null; then
        missing_features+=("arithmetic")
    fi
    
    # Test for arrays
    local test_array=()
    test_array+=("test")
    if [[ "${#test_array[@]}" -ne 1 ]]; then
        missing_features+=("arrays")
    fi
    
    if [[ ${#missing_features[@]} -gt 0 ]]; then
        echo "Error: Missing required bash features: ${missing_features[*]}" >&2
        return 1
    fi
    
    return 0
}