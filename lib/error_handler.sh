#!/usr/bin/env bash
#
# error_handler.sh - Comprehensive error handling and recovery for makecmd
#
# This module provides error recovery, retry logic, and graceful degradation

# Error recovery states
# Using bash 3.2 compatible approach
if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    declare -A ERROR_COUNTS
    declare -A LAST_ERROR_TIME
else
    # Fallback for bash 3.x - use separate variables
    ERROR_COUNTS_claude_timeout=0
    ERROR_COUNTS_rate_limit=0
    ERROR_COUNTS_api_error=0
    LAST_ERROR_TIME_claude_timeout=0
    LAST_ERROR_TIME_rate_limit=0
    LAST_ERROR_TIME_api_error=0
fi
readonly MAX_RETRIES=3
readonly RETRY_DELAY_BASE=1  # Base delay in seconds
readonly ERROR_THRESHOLD=5   # Errors before circuit breaker
readonly CIRCUIT_BREAK_TIME=300  # 5 minutes

# Function to handle recoverable errors with retry
handle_recoverable_error() {
    local error_type="$1"
    local error_code="$2"
    local error_message="$3"
    local retry_func="${4:-}"
    
    # Initialize error count if needed
    ERROR_COUNTS["$error_type"]=${ERROR_COUNTS["$error_type"]:-0}
    
    # Check circuit breaker
    if is_circuit_open "$error_type"; then
        log "ERROR" "Circuit breaker open for $error_type"
        return $E_CIRCUIT_BREAKER_OPEN
    fi
    
    # Increment error count
    ((ERROR_COUNTS["$error_type"]++))
    LAST_ERROR_TIME["$error_type"]=$(date +%s)
    
    # Log error
    log "WARN" "Recoverable error: $error_type - $error_message (attempt ${ERROR_COUNTS["$error_type"]})"
    
    # Check if we should retry
    if [[ ${ERROR_COUNTS["$error_type"]} -le $MAX_RETRIES ]] && [[ -n "$retry_func" ]]; then
        local delay=$(calculate_backoff_delay ${ERROR_COUNTS["$error_type"]})
        log "INFO" "Retrying in ${delay}s..."
        sleep "$delay"
        
        # Execute retry function
        if $retry_func; then
            # Reset error count on success
            ERROR_COUNTS["$error_type"]=0
            return 0
        fi
    fi
    
    # Check if circuit should break
    if [[ ${ERROR_COUNTS["$error_type"]} -ge $ERROR_THRESHOLD ]]; then
        log "ERROR" "Error threshold reached for $error_type, opening circuit breaker"
        open_circuit_breaker "$error_type"
    fi
    
    return $error_code
}

# Function to calculate exponential backoff delay
calculate_backoff_delay() {
    local attempt="$1"
    local max_delay=30
    
    # Exponential backoff with jitter
    local delay=$((RETRY_DELAY_BASE * (2 ** (attempt - 1))))
    local jitter=$((RANDOM % 1000))  # 0-999ms
    delay=$(awk "BEGIN {print $delay + $jitter/1000}")
    
    # Cap at max delay
    if (( $(echo "$delay > $max_delay" | bc -l) )); then
        delay=$max_delay
    fi
    
    echo "$delay"
}

# Circuit breaker functions
is_circuit_open() {
    local error_type="$1"
    local current_time=$(date +%s)
    local break_file="${HOME}/.makecmd/circuit_breaker/${error_type}.break"
    
    if [[ -f "$break_file" ]]; then
        local break_time=$(cat "$break_file" 2>/dev/null || echo 0)
        local elapsed=$((current_time - break_time))
        
        if [[ $elapsed -lt $CIRCUIT_BREAK_TIME ]]; then
            return 0  # Circuit is open
        else
            # Circuit timeout, close it
            close_circuit_breaker "$error_type"
        fi
    fi
    
    return 1  # Circuit is closed
}

open_circuit_breaker() {
    local error_type="$1"
    local break_dir="${HOME}/.makecmd/circuit_breaker"
    
    mkdir -p "$break_dir"
    date +%s > "${break_dir}/${error_type}.break"
}

close_circuit_breaker() {
    local error_type="$1"
    local break_file="${HOME}/.makecmd/circuit_breaker/${error_type}.break"
    
    rm -f "$break_file"
    ERROR_COUNTS["$error_type"]=0
}

# Function to handle critical errors with graceful degradation
handle_critical_error() {
    local error_code="$1"
    local error_message="$2"
    local fallback_action="${3:-}"
    
    log "ERROR" "Critical error: $error_message"
    
    # Attempt graceful degradation
    if [[ -n "$fallback_action" ]]; then
        log "INFO" "Attempting fallback: $fallback_action"
        case "$fallback_action" in
            "use_cache")
                # Try to use cached results
                return $E_FALLBACK_CACHE
                ;;
            "offline_mode")
                # Switch to offline mode
                return $E_FALLBACK_OFFLINE
                ;;
            "basic_mode")
                # Fallback to basic functionality
                return $E_FALLBACK_BASIC
                ;;
            *)
                log "WARN" "Unknown fallback action: $fallback_action"
                ;;
        esac
    fi
    
    # Save error state for debugging
    save_error_state "$error_code" "$error_message"
    
    return $error_code
}

# Function to save error state for debugging
save_error_state() {
    local error_code="$1"
    local error_message="$2"
    local state_dir="${HOME}/.makecmd/error_states"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local state_file="${state_dir}/error_${timestamp}_${error_code}.state"
    
    mkdir -p "$state_dir"
    
    cat > "$state_file" << EOF
Error Code: $error_code
Error Message: $error_message
Timestamp: $(date)
User: $(whoami)
Working Directory: $(pwd)
Shell: $SHELL
Bash Version: $BASH_VERSION

Environment Variables:
$(env | grep -E '^(PATH|HOME|SHELL|USER|TERM)=' | sort)

System Info:
$(uname -a)

Recent Commands:
$(tail -n 20 ~/.makecmd/logs/makecmd.log 2>/dev/null || echo "No log available")
EOF
    
    chmod 600 "$state_file"
    
    # Clean up old error states (keep last 10)
    ls -t "$state_dir"/error_*.state 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
}

# Function to validate system state before operations
validate_system_state() {
    local errors=0
    
    # Check disk space
    local cache_dir_space=$(df -k "${CACHE_DIR}" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$cache_dir_space" ]] && [[ $cache_dir_space -lt 1024 ]]; then
        log "WARN" "Low disk space in cache directory: ${cache_dir_space}KB available"
        ((errors++))
    fi
    
    # Check if Claude is accessible
    if ! command -v claude > /dev/null 2>&1; then
        log "ERROR" "Claude command not found"
        ((errors++))
    fi
    
    # Check directory permissions
    for dir in "$LOG_DIR" "$CACHE_DIR"; do
        if [[ ! -w "$dir" ]]; then
            log "ERROR" "Cannot write to directory: $dir"
            ((errors++))
        fi
    done
    
    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    if command -v bc > /dev/null 2>&1; then
        if (( $(echo "$load_avg > 10" | bc -l) )); then
            log "WARN" "High system load: $load_avg"
        fi
    fi
    
    return $errors
}

# Function to perform cleanup on error
cleanup_on_error() {
    local exit_code="$1"
    
    # Remove temporary files
    find /tmp -name "makecmd.*" -mmin +60 -delete 2>/dev/null || true
    
    # Release any held locks
    find "${CACHE_DIR}" -name "*.lock" -type d -mmin +5 -exec rmdir {} \; 2>/dev/null || true
    
    # Flush logs
    sync
    
    # Report error metrics if enabled
    if [[ "${ENABLE_METRICS:-false}" == "true" ]]; then
        report_error_metrics "$exit_code"
    fi
}

# Function to report error metrics
report_error_metrics() {
    local exit_code="$1"
    local metrics_file="${HOME}/.makecmd/metrics/errors.json"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    mkdir -p "$(dirname "$metrics_file")"
    
    # Append error metric
    cat >> "$metrics_file" << EOF
{"timestamp": "$timestamp", "exit_code": $exit_code, "error_type": "$(get_error_type $exit_code)"}
EOF
}

# Function to get error type from exit code
get_error_type() {
    local exit_code="$1"
    
    case $exit_code in
        $E_INVALID_INPUT) echo "invalid_input" ;;
        $E_CLAUDE_ERROR) echo "claude_error" ;;
        $E_DANGEROUS_COMMAND) echo "dangerous_command" ;;
        $E_TIMEOUT) echo "timeout" ;;
        $E_CONFIG_ERROR) echo "config_error" ;;
        $E_DEPENDENCY_ERROR) echo "dependency_error" ;;
        *) echo "unknown" ;;
    esac
}

# Additional error codes for fallback modes
readonly E_FALLBACK_CACHE=50
readonly E_FALLBACK_OFFLINE=51
readonly E_FALLBACK_BASIC=52
readonly E_CIRCUIT_BREAKER_OPEN=53