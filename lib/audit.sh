#!/usr/bin/env bash
#
# audit.sh - Audit logging functions for makecmd
#
# This module provides audit logging for all generated commands

# Audit log configuration
readonly AUDIT_LOG_DIR="${HOME}/.makecmd/audit"
readonly AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/audit.log"
readonly AUDIT_ROTATION_SIZE=10485760  # 10MB
readonly AUDIT_MAX_FILES=5

# Initialize audit logging
init_audit_log() {
    # Create audit directory with restrictive permissions
    mkdir -p "$AUDIT_LOG_DIR"
    chmod 700 "$AUDIT_LOG_DIR"
    
    # Create audit log file if it doesn't exist
    if [[ ! -f "$AUDIT_LOG_FILE" ]]; then
        touch "$AUDIT_LOG_FILE"
        chmod 600 "$AUDIT_LOG_FILE"
    fi
    
    # Rotate log if needed
    rotate_audit_log
}

# Log audit entry
log_audit() {
    local event_type="$1"
    local input="$2"
    local output="$3"
    local status="$4"
    local additional_info="${5:-}"
    
    # Initialize if needed
    init_audit_log
    
    # Get current timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get user info
    local user="${USER:-unknown}"
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    
    # Create audit entry
    local audit_entry=$(cat << EOF
{
  "timestamp": "$timestamp",
  "event_type": "$event_type",
  "user": "$user",
  "hostname": "$hostname",
  "input": "$(echo "$input" | sed 's/"/\\"/g')",
  "output": "$(echo "$output" | sed 's/"/\\"/g')",
  "status": "$status",
  "additional_info": "$additional_info",
  "pid": $$
}
EOF
)
    
    # Write to audit log
    echo "$audit_entry" >> "$AUDIT_LOG_FILE" 2>/dev/null || {
        log "ERROR" "Failed to write audit log"
        return 1
    }
    
    return 0
}

# Log command generation audit
log_command_audit() {
    local input="$1"
    local command="$2"
    local cached="${3:-false}"
    local safe_mode="${4:-false}"
    
    local status="success"
    local additional_info="cached=$cached,safe_mode=$safe_mode"
    
    log_audit "command_generation" "$input" "$command" "$status" "$additional_info"
}

# Log error audit
log_error_audit() {
    local input="$1"
    local error_type="$2"
    local error_message="$3"
    
    log_audit "error" "$input" "" "failed" "error_type=$error_type,message=$error_message"
}

# Log security event audit
log_security_audit() {
    local event="$1"
    local input="$2"
    local details="$3"
    
    log_audit "security" "$input" "" "blocked" "event=$event,details=$details"
}

# Rotate audit logs
rotate_audit_log() {
    if [[ ! -f "$AUDIT_LOG_FILE" ]]; then
        return 0
    fi
    
    # Check file size
    local file_size=$(stat -f%z "$AUDIT_LOG_FILE" 2>/dev/null || stat -c%s "$AUDIT_LOG_FILE" 2>/dev/null || echo "0")
    
    if [[ $file_size -gt $AUDIT_ROTATION_SIZE ]]; then
        # Rotate logs
        for ((i=$((AUDIT_MAX_FILES-1)); i>=1; i--)); do
            if [[ -f "${AUDIT_LOG_FILE}.$i" ]]; then
                mv "${AUDIT_LOG_FILE}.$i" "${AUDIT_LOG_FILE}.$((i+1))"
            fi
        done
        
        # Move current log to .1
        mv "$AUDIT_LOG_FILE" "${AUDIT_LOG_FILE}.1"
        
        # Create new log file
        touch "$AUDIT_LOG_FILE"
        chmod 600 "$AUDIT_LOG_FILE"
        
        # Remove old logs
        if [[ -f "${AUDIT_LOG_FILE}.$((AUDIT_MAX_FILES+1))" ]]; then
            rm -f "${AUDIT_LOG_FILE}.$((AUDIT_MAX_FILES+1))"
        fi
        
        log "INFO" "Rotated audit log"
    fi
}

# Search audit logs
search_audit_log() {
    local search_term="$1"
    local days="${2:-7}"  # Default to last 7 days
    
    # Calculate date range
    local since_date=$(date -v-${days}d '+%Y-%m-%d' 2>/dev/null || date -d "$days days ago" '+%Y-%m-%d' 2>/dev/null)
    
    echo "Searching audit logs for: $search_term (last $days days)"
    echo "Since: $since_date"
    echo
    
    # Search in all audit log files
    for log_file in "$AUDIT_LOG_FILE"*; do
        if [[ -f "$log_file" ]]; then
            grep -i "$search_term" "$log_file" 2>/dev/null | \
            while IFS= read -r line; do
                # Parse JSON and check date
                local timestamp=$(echo "$line" | grep -o '"timestamp": "[^"]*"' | cut -d'"' -f4)
                if [[ "$timestamp" > "$since_date" ]]; then
                    echo "$line"
                fi
            done
        fi
    done
}

# Get audit statistics
get_audit_stats() {
    local days="${1:-7}"  # Default to last 7 days
    
    echo "Audit Statistics (last $days days)"
    echo "================================="
    
    local total_commands=0
    local cached_commands=0
    local errors=0
    local security_events=0
    
    # Calculate date range
    local since_date=$(date -v-${days}d '+%Y-%m-%d' 2>/dev/null || date -d "$days days ago" '+%Y-%m-%d' 2>/dev/null)
    
    # Process all audit log files
    for log_file in "$AUDIT_LOG_FILE"*; do
        if [[ -f "$log_file" ]]; then
            while IFS= read -r line; do
                local timestamp=$(echo "$line" | grep -o '"timestamp": "[^"]*"' | cut -d'"' -f4)
                if [[ "$timestamp" > "$since_date" ]]; then
                    local event_type=$(echo "$line" | grep -o '"event_type": "[^"]*"' | cut -d'"' -f4)
                    
                    case "$event_type" in
                        command_generation)
                            ((total_commands++))
                            if echo "$line" | grep -q '"cached=true"'; then
                                ((cached_commands++))
                            fi
                            ;;
                        error)
                            ((errors++))
                            ;;
                        security)
                            ((security_events++))
                            ;;
                    esac
                fi
            done < "$log_file"
        fi
    done
    
    echo "Total commands generated: $total_commands"
    echo "Cached commands used: $cached_commands"
    echo "Errors encountered: $errors"
    echo "Security events: $security_events"
    
    if [[ $total_commands -gt 0 ]]; then
        local cache_rate=$((cached_commands * 100 / total_commands))
        echo "Cache hit rate: ${cache_rate}%"
    fi
}