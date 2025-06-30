#!/usr/bin/env bash
#
# logger.sh - Structured logging with rotation for makecmd
#
# This module provides structured logging with automatic rotation

# Logging configuration
readonly LOG_MAX_SIZE=10485760  # 10MB
readonly LOG_MAX_FILES=5
readonly LOG_DATE_FORMAT='+%Y-%m-%d %H:%M:%S'
readonly LOG_FILE_FORMAT='%Y%m%d'

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Map string levels to numeric (bash 3.2 compatible)
# We'll use a function instead of associative array
get_log_level() {
    case "$1" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO) echo $LOG_LEVEL_INFO ;;
        WARN) echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *) echo $LOG_LEVEL_INFO ;;
    esac
}

# Current log level (default INFO)
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

# Structured logging function
log_structured() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    
    # Check if we should log this level
    local numeric_level=$(get_log_level "$level")
    if [[ $numeric_level -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi
    
    # Get timestamp
    local timestamp=$(date "$LOG_DATE_FORMAT")
    local iso_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Get caller info
    local caller_info="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    
    # Create structured log entry
    local log_entry=$(cat << EOF
{
  "timestamp": "$iso_timestamp",
  "level": "$level",
  "message": "$message",
  "caller": "$caller_info",
  "pid": $$,
  "user": "$(whoami)",
  "context": $context
}
EOF
)
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Check if log rotation is needed
    check_log_rotation
    
    # Write to log file
    local log_file="${LOG_DIR}/makecmd.log"
    if ! echo "$log_entry" >> "$log_file" 2>/dev/null; then
        # Fallback to stderr if can't write to file
        echo "[$timestamp] [$level] $message" >&2
    fi
    
    # Also output to stderr for ERROR and WARN in debug mode
    if [[ "$level" == "ERROR" ]] || ([[ "$DEBUG" == "true" ]] && [[ "$level" == "WARN" ]]); then
        echo "[$timestamp] [$level] $message" >&2
    fi
}

# Backward compatible log function
log() {
    local level="$1"
    shift
    local message="$*"
    
    # Convert to structured format with empty context
    log_structured "$level" "$message" "{}"
}

# Enhanced log function with context
log_with_context() {
    local level="$1"
    local message="$2"
    shift 2
    
    # Build context from remaining arguments
    local context="{"
    local first=true
    
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            context+=","
        fi
        
        # Escape JSON values
        value=$(echo "$value" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
        context+="\"$key\":\"$value\""
    done
    
    context+="}"
    
    log_structured "$level" "$message" "$context"
}

# Function to check and perform log rotation
check_log_rotation() {
    local log_file="${LOG_DIR}/makecmd.log"
    
    # Check if log file exists
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi
    
    # Get file size
    local file_size=$(get_file_size "$log_file")
    
    # Check if rotation is needed
    if [[ $file_size -ge $LOG_MAX_SIZE ]]; then
        rotate_logs
    fi
}

# Function to rotate logs
rotate_logs() {
    local log_file="${LOG_DIR}/makecmd.log"
    local timestamp=$(date "+$LOG_FILE_FORMAT")
    
    # Find the next available rotation number
    local rotation_num=1
    while [[ -f "${log_file}.${timestamp}.${rotation_num}" ]]; do
        ((rotation_num++))
    done
    
    # Rotate the current log
    if mv "$log_file" "${log_file}.${timestamp}.${rotation_num}" 2>/dev/null; then
        log_structured "INFO" "Log rotated to ${log_file}.${timestamp}.${rotation_num}" "{}"
        
        # Compress old log
        if command -v gzip > /dev/null 2>&1; then
            gzip "${log_file}.${timestamp}.${rotation_num}" &
        fi
        
        # Clean up old logs
        cleanup_old_logs
    fi
}

# Function to clean up old log files
cleanup_old_logs() {
    local log_dir="$LOG_DIR"
    local log_pattern="makecmd.log.*"
    
    # Count log files
    local log_count=$(find "$log_dir" -name "$log_pattern" -type f 2>/dev/null | wc -l)
    
    # Remove oldest files if over limit
    if [[ $log_count -gt $LOG_MAX_FILES ]]; then
        local files_to_remove=$((log_count - LOG_MAX_FILES))
        
        # Find and remove oldest files
        find "$log_dir" -name "$log_pattern" -type f -print0 2>/dev/null | \
            xargs -0 ls -t | \
            tail -n "$files_to_remove" | \
            xargs rm -f
    fi
}

# Function to set log level
set_log_level() {
    local level="$1"
    local numeric_level=$(get_log_level "$level")
    
    case "$level" in
        DEBUG|INFO|WARN|ERROR)
            CURRENT_LOG_LEVEL=$numeric_level
            log_structured "INFO" "Log level set to $level" "{}"
            ;;
        *)
            log_structured "WARN" "Invalid log level: $level" "{}"
            ;;
    esac
}

# Audit logging functions
log_command_audit() {
    local input="$1"
    local command="$2"
    local cached="$3"
    local safe_mode="$4"
    
    log_with_context "INFO" "Command generated" \
        "input" "$input" \
        "command" "$command" \
        "cached" "$cached" \
        "safe_mode" "$safe_mode" \
        "session_id" "${SESSION_ID:-unknown}"
}

log_security_audit() {
    local event_type="$1"
    local input="$2"
    local details="$3"
    
    log_with_context "WARN" "Security event" \
        "event_type" "$event_type" \
        "input" "$input" \
        "details" "$details" \
        "source_ip" "${SSH_CLIENT%% *}" \
        "session_id" "${SESSION_ID:-unknown}"
}

log_error_audit() {
    local input="$1"
    local error_type="$2"
    local error_details="$3"
    
    log_with_context "ERROR" "Error occurred" \
        "input" "$input" \
        "error_type" "$error_type" \
        "error_details" "$error_details" \
        "session_id" "${SESSION_ID:-unknown}"
}

# Performance logging
log_performance() {
    local operation="$1"
    local duration="$2"
    local details="${3:-}"
    
    log_with_context "INFO" "Performance metric" \
        "operation" "$operation" \
        "duration_ms" "$duration" \
        "details" "$details"
}

# Function to parse logs
parse_logs() {
    local log_file="${LOG_DIR}/makecmd.log"
    local filter="${1:-}"
    local limit="${2:-100}"
    
    if [[ ! -f "$log_file" ]]; then
        echo "No log file found"
        return 1
    fi
    
    if [[ -n "$filter" ]]; then
        # Filter logs by level or content
        grep -E "\"level\": \"$filter\"|\"message\": \".*$filter.*\"" "$log_file" | \
            tail -n "$limit" | \
            jq -r '[.timestamp, .level, .message] | @tsv' 2>/dev/null || \
            grep "$filter" "$log_file" | tail -n "$limit"
    else
        # Show recent logs
        tail -n "$limit" "$log_file" | \
            jq -r '[.timestamp, .level, .message] | @tsv' 2>/dev/null || \
            tail -n "$limit" "$log_file"
    fi
}

# Function to export logs
export_logs() {
    local output_file="$1"
    local start_date="${2:-}"
    local end_date="${3:-}"
    
    local log_file="${LOG_DIR}/makecmd.log"
    
    if [[ ! -f "$log_file" ]]; then
        log "ERROR" "No log file found"
        return 1
    fi
    
    # Create temporary file for filtered logs
    local temp_file=$(mktemp)
    
    if [[ -n "$start_date" ]] && [[ -n "$end_date" ]]; then
        # Filter by date range
        awk -v start="$start_date" -v end="$end_date" \
            '$0 ~ /"timestamp":/ {
                match($0, /"timestamp": "([^"]+)"/, arr);
                if (arr[1] >= start && arr[1] <= end) print
            }' "$log_file" > "$temp_file"
    else
        # Export all logs
        cp "$log_file" "$temp_file"
    fi
    
    # Compress and save
    if command -v gzip > /dev/null 2>&1; then
        gzip -c "$temp_file" > "$output_file"
    else
        mv "$temp_file" "$output_file"
    fi
    
    rm -f "$temp_file"
    
    log "INFO" "Logs exported to $output_file"
}

# Initialize logging
init_logging() {
    # Set log level from config
    if [[ -n "${CONFIG_log_level:-}" ]]; then
        set_log_level "${CONFIG_log_level}"
    fi
    
    # Create session ID if not exists
    if [[ -z "${SESSION_ID:-}" ]]; then
        SESSION_ID="$(date +%s)-$$-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' ')"
        export SESSION_ID
    fi
    
    # Log session start
    log_with_context "INFO" "Session started" \
        "version" "$VERSION" \
        "platform" "$PLATFORM" \
        "bash_version" "$BASH_VERSION"
}