#!/usr/bin/env bash
#
# validation.sh - Input validation functions for makecmd
#
# This module provides comprehensive input validation for all public functions

# Validation error codes
readonly E_VALIDATION_FAILED=100
readonly E_INVALID_PARAMETER=101
readonly E_MISSING_PARAMETER=102
readonly E_TYPE_MISMATCH=103

# Function to validate string parameter
validate_string() {
    local param_name="$1"
    local param_value="$2"
    local required="${3:-true}"
    local max_length="${4:-0}"
    local pattern="${5:-}"
    
    # Check if required
    if [[ "$required" == "true" ]] && [[ -z "$param_value" ]]; then
        log "ERROR" "Missing required parameter: $param_name"
        return $E_MISSING_PARAMETER
    fi
    
    # Check length
    if [[ $max_length -gt 0 ]] && [[ ${#param_value} -gt $max_length ]]; then
        log "ERROR" "Parameter $param_name exceeds maximum length of $max_length"
        return $E_VALIDATION_FAILED
    fi
    
    # Check pattern
    if [[ -n "$pattern" ]] && [[ -n "$param_value" ]]; then
        if ! echo "$param_value" | grep -qE "$pattern"; then
            log "ERROR" "Parameter $param_name does not match required pattern"
            return $E_VALIDATION_FAILED
        fi
    fi
    
    return 0
}

# Function to validate integer parameter
validate_integer() {
    local param_name="$1"
    local param_value="$2"
    local min_value="${3:--999999999}"
    local max_value="${4:-999999999}"
    
    # Check if integer
    if ! [[ "$param_value" =~ ^-?[0-9]+$ ]]; then
        log "ERROR" "Parameter $param_name must be an integer"
        return $E_TYPE_MISMATCH
    fi
    
    # Check range
    if [[ $param_value -lt $min_value ]] || [[ $param_value -gt $max_value ]]; then
        log "ERROR" "Parameter $param_name must be between $min_value and $max_value"
        return $E_VALIDATION_FAILED
    fi
    
    return 0
}

# Function to validate boolean parameter
validate_boolean() {
    local param_name="$1"
    local param_value="$2"
    
    if ! [[ "$param_value" =~ ^(true|false|yes|no|1|0)$ ]]; then
        log "ERROR" "Parameter $param_name must be a boolean value"
        return $E_TYPE_MISMATCH
    fi
    
    return 0
}

# Function to validate file path
validate_file_path() {
    local param_name="$1"
    local param_value="$2"
    local must_exist="${3:-false}"
    local must_be_writable="${4:-false}"
    
    # Basic path validation
    if [[ -z "$param_value" ]]; then
        log "ERROR" "Parameter $param_name cannot be empty"
        return $E_MISSING_PARAMETER
    fi
    
    # Check for dangerous paths
    if [[ "$param_value" == "/" ]] || [[ "$param_value" == "/*" ]]; then
        log "ERROR" "Parameter $param_name contains dangerous path"
        return $E_VALIDATION_FAILED
    fi
    
    # Check existence
    if [[ "$must_exist" == "true" ]] && [[ ! -e "$param_value" ]]; then
        log "ERROR" "Path does not exist: $param_value"
        return $E_VALIDATION_FAILED
    fi
    
    # Check writability
    if [[ "$must_be_writable" == "true" ]]; then
        local dir=$(dirname "$param_value")
        if [[ ! -w "$dir" ]]; then
            log "ERROR" "Directory is not writable: $dir"
            return $E_VALIDATION_FAILED
        fi
    fi
    
    return 0
}

# Function to validate enum parameter
validate_enum() {
    local param_name="$1"
    local param_value="$2"
    shift 2
    local valid_values=("$@")
    
    for valid in "${valid_values[@]}"; do
        if [[ "$param_value" == "$valid" ]]; then
            return 0
        fi
    done
    
    log "ERROR" "Parameter $param_name must be one of: ${valid_values[*]}"
    return $E_VALIDATION_FAILED
}

# Wrapped functions with validation

# Validated sanitize_input
sanitize_input_validated() {
    local input="$1"
    
    # Validate input
    validate_string "input" "$input" true $MAX_INPUT_LENGTH || return $?
    
    # Call original function
    sanitize_input "$input"
}

# Validated cache_command
cache_command_validated() {
    local cache_key="$1"
    local command="$2"
    local ttl="${3:-$DEFAULT_CACHE_TTL}"
    
    # Validate parameters
    validate_string "cache_key" "$cache_key" true 64 "^[a-fA-F0-9]+$" || return $?
    validate_string "command" "$command" true 1000 || return $?
    validate_integer "ttl" "$ttl" 0 86400 || return $?
    
    # Call original function
    cache_command "$cache_key" "$command" "$ttl"
}

# Validated load_config
load_config_validated() {
    local config_file="$1"
    
    # Validate parameters
    validate_file_path "config_file" "$config_file" true false || return $?
    
    # Check file permissions
    local perms=$(get_file_perms "$config_file")
    if [[ "$perms" != "600" ]] && [[ "$perms" != "644" ]]; then
        log "WARN" "Config file has insecure permissions: $perms"
    fi
    
    # Call original function
    load_config "$config_file"
}

# Validated set_config
set_config_validated() {
    local key="$1"
    local value="$2"
    
    # Validate key
    validate_enum "key" "$key" \
        "output_mode" "cache_ttl" "safe_mode" "debug" \
        "timeout" "max_input_length" "log_level" "color_output" \
        "prefill_shell" "clipboard_command" "rate_limit" "burst_limit" || return $?
    
    # Value validation is done by validate_config_option
    # Call original function
    set_config "$key" "$value"
}

# Validated sanitize_path
sanitize_path_validated() {
    local path="$1"
    
    # Basic validation
    validate_string "path" "$path" true 1024 || return $?
    
    # Check for null bytes
    if echo "$path" | grep -q $'\0'; then
        log "ERROR" "Path contains null bytes"
        return $E_VALIDATION_FAILED
    fi
    
    # Call original function
    sanitize_path "$path"
}

# Function to validate all inputs at startup
validate_startup_config() {
    local errors=0
    
    log "INFO" "Validating configuration..."
    
    # Validate bash version
    local bash_major="${BASH_VERSION%%.*}"
    local bash_minor="${BASH_VERSION#*.}"
    bash_minor="${bash_minor%%.*}"
    
    if [[ "$bash_major" -lt 3 ]] || ([[ "$bash_major" -eq 3 ]] && [[ "$bash_minor" -lt 2 ]]); then
        log "ERROR" "Bash version 3.2 or higher required (found: $BASH_VERSION)"
        ((errors++))
    fi
    
    # Validate required directories
    for dir in "$LOG_DIR" "$CACHE_DIR"; do
        if ! validate_file_path "directory" "$dir" false true; then
            ((errors++))
        fi
    done
    
    # Validate configuration values
    validate_integer "MAX_INPUT_LENGTH" "$MAX_INPUT_LENGTH" 1 10000 || ((errors++))
    validate_integer "CLAUDE_TIMEOUT" "$CLAUDE_TIMEOUT" 1 600 || ((errors++))
    validate_integer "DEFAULT_CACHE_TTL" "$DEFAULT_CACHE_TTL" 0 86400 || ((errors++))
    
    # Validate output mode
    validate_enum "OUTPUT_MODE" "$OUTPUT_MODE" "auto" "prefill" "clipboard" "stdout" || ((errors++))
    
    # Validate dependencies (skip claude check here - done in check_dependencies)
    # Claude availability is checked later in check_dependencies function
    
    # Platform-specific validation
    if ! validate_platform_requirements; then
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log "ERROR" "Configuration validation failed with $errors errors"
        return $E_CONFIG_ERROR
    fi
    
    log "INFO" "Configuration validation successful"
    return 0
}

# Function to create validation report
create_validation_report() {
    local output_file="${1:-${HOME}/.makecmd/validation_report.txt}"
    
    {
        echo "makecmd Validation Report"
        echo "========================"
        echo "Generated: $(date)"
        echo
        echo "System Information:"
        echo "  Platform: $PLATFORM"
        echo "  Bash Version: $BASH_VERSION"
        echo "  User: $(whoami)"
        echo
        echo "Configuration:"
        echo "  Output Mode: $OUTPUT_MODE"
        echo "  Cache TTL: $DEFAULT_CACHE_TTL"
        echo "  Safe Mode: $SAFE_MODE"
        echo "  Debug: $DEBUG"
        echo "  Max Input Length: $MAX_INPUT_LENGTH"
        echo "  Timeout: $CLAUDE_TIMEOUT"
        echo
        echo "Directory Permissions:"
        echo "  Log Directory: $(ls -ld "$LOG_DIR" 2>/dev/null || echo "Not found")"
        echo "  Cache Directory: $(ls -ld "$CACHE_DIR" 2>/dev/null || echo "Not found")"
        echo
        echo "Dependencies:"
        for cmd in claude sed grep awk tr cat mkdir rm mv; do
            if command -v "$cmd" > /dev/null 2>&1; then
                echo "  $cmd: $(command -v "$cmd")"
            else
                echo "  $cmd: NOT FOUND"
            fi
        done
        echo
        echo "Optional Dependencies:"
        for cmd in sha256sum shasum openssl pbcopy xclip xsel jq; do
            if command -v "$cmd" > /dev/null 2>&1; then
                echo "  $cmd: $(command -v "$cmd")"
            else
                echo "  $cmd: Not installed"
            fi
        done
        echo
        echo "Validation Status:"
        if validate_startup_config > /dev/null 2>&1; then
            echo "  Overall: PASSED"
        else
            echo "  Overall: FAILED"
        fi
    } > "$output_file"
    
    chmod 600 "$output_file"
    echo "Validation report saved to: $output_file"
}