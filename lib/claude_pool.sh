#!/usr/bin/env bash
#
# claude_pool.sh - Connection pooling and retry logic for Claude API
#
# This module provides connection management and intelligent retry

# Connection pool settings
readonly POOL_SIZE=3
readonly MAX_RETRIES=3
readonly RETRY_DELAY_BASE=1
readonly CONNECTION_TIMEOUT=30
readonly KEEPALIVE_INTERVAL=60

# Connection state tracking
declare -A CONNECTION_STATES  # idle, busy, failed
declare -A CONNECTION_LAST_USED
declare -A CONNECTION_REQUEST_COUNT
declare -A CONNECTION_ERROR_COUNT

# Initialize connection pool
init_connection_pool() {
    local pool_dir="${HOME}/.makecmd/pool"
    mkdir -p "$pool_dir"
    
    for i in $(seq 1 $POOL_SIZE); do
        CONNECTION_STATES["conn_$i"]="idle"
        CONNECTION_LAST_USED["conn_$i"]=$(date +%s)
        CONNECTION_REQUEST_COUNT["conn_$i"]=0
        CONNECTION_ERROR_COUNT["conn_$i"]=0
    done
    
    log "INFO" "Initialized connection pool with $POOL_SIZE connections"
}

# Get available connection
get_connection() {
    local timeout="${1:-5}"
    local start_time=$(date +%s)
    
    while true; do
        # Find idle connection
        for conn_id in "${!CONNECTION_STATES[@]}"; do
            if [[ "${CONNECTION_STATES[$conn_id]}" == "idle" ]]; then
                CONNECTION_STATES[$conn_id]="busy"
                CONNECTION_LAST_USED[$conn_id]=$(date +%s)
                log "DEBUG" "Acquired connection: $conn_id"
                echo "$conn_id"
                return 0
            fi
        done
        
        # Check timeout
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            log "WARN" "Connection pool exhausted, timeout waiting for connection"
            return 1
        fi
        
        # Wait briefly and retry
        sleep 0.1
    done
}

# Release connection
release_connection() {
    local conn_id="$1"
    local success="${2:-true}"
    
    if [[ -z "$conn_id" ]] || [[ -z "${CONNECTION_STATES[$conn_id]}" ]]; then
        log "ERROR" "Invalid connection ID: $conn_id"
        return 1
    fi
    
    if [[ "$success" == "false" ]]; then
        ((CONNECTION_ERROR_COUNT[$conn_id]++))
        
        # Mark as failed if too many errors
        if [[ ${CONNECTION_ERROR_COUNT[$conn_id]} -ge 3 ]]; then
            CONNECTION_STATES[$conn_id]="failed"
            log "WARN" "Connection $conn_id marked as failed after ${CONNECTION_ERROR_COUNT[$conn_id]} errors"
            
            # Schedule reconnection
            schedule_reconnection "$conn_id"
        else
            CONNECTION_STATES[$conn_id]="idle"
        fi
    else
        CONNECTION_STATES[$conn_id]="idle"
        CONNECTION_ERROR_COUNT[$conn_id]=0
    fi
    
    log "DEBUG" "Released connection: $conn_id (success: $success)"
}

# Schedule reconnection for failed connection
schedule_reconnection() {
    local conn_id="$1"
    
    # Simple reconnection - mark as idle after delay
    (
        sleep 30
        CONNECTION_STATES[$conn_id]="idle"
        CONNECTION_ERROR_COUNT[$conn_id]=0
        log "INFO" "Connection $conn_id recovered"
    ) &
}

# Call Claude with connection pooling and retry
call_claude_pooled() {
    local prompt="$1"
    local max_retries="${2:-$MAX_RETRIES}"
    local retry_count=0
    local output=""
    local success=false
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Get connection from pool
        local conn_id=$(get_connection 10)
        if [[ -z "$conn_id" ]]; then
            log "ERROR" "Failed to acquire connection from pool"
            return $E_CLAUDE_ERROR
        fi
        
        # Track request
        ((CONNECTION_REQUEST_COUNT[$conn_id]++))
        
        # Start timer for metrics
        start_timer "claude_api_call"
        
        # Make API call with timeout
        local temp_file=$(mktemp)
        local error_file="${temp_file}.err"
        
        if timeout "$CONNECTION_TIMEOUT" claude <<< "$prompt" > "$temp_file" 2>"$error_file"; then
            output=$(cat "$temp_file")
            success=true
            
            # Record success metrics
            local duration=$(stop_timer "claude_api_call" "{\"connection\":\"$conn_id\",\"retry\":$retry_count}")
            log_performance "claude_api_call" "$duration" "{\"success\":true}"
            
            # Release connection as successful
            release_connection "$conn_id" true
            
            # Clean up and return
            rm -f "$temp_file" "$error_file"
            echo "$output"
            return 0
        else
            local exit_code=$?
            local error_msg=$(cat "$error_file" 2>/dev/null || echo "Unknown error")
            
            # Record failure metrics
            stop_timer "claude_api_call"
            increment_counter "claude_errors"
            
            # Log error
            log "WARN" "Claude API call failed (attempt $((retry_count + 1))): $error_msg"
            
            # Release connection as failed
            release_connection "$conn_id" false
            
            # Handle specific errors
            case $exit_code in
                124)  # Timeout
                    handle_recoverable_error "claude_timeout" $E_TIMEOUT "API timeout" || true
                    ;;
                127)  # Command not found
                    rm -f "$temp_file" "$error_file"
                    return $E_DEPENDENCY_ERROR
                    ;;
            esac
            
            # Calculate backoff delay
            local delay=$(calculate_backoff_delay $((retry_count + 1)))
            log "INFO" "Retrying in ${delay}s..."
            sleep "$delay"
        fi
        
        rm -f "$temp_file" "$error_file"
        ((retry_count++))
    done
    
    # All retries failed
    log "ERROR" "All retries exhausted for Claude API call"
    handle_critical_error $E_CLAUDE_ERROR "Claude API unavailable after $max_retries attempts" "use_cache"
    return $E_CLAUDE_ERROR
}

# Get connection pool statistics
get_pool_stats() {
    local idle_count=0
    local busy_count=0
    local failed_count=0
    local total_requests=0
    local total_errors=0
    
    for conn_id in "${!CONNECTION_STATES[@]}"; do
        case "${CONNECTION_STATES[$conn_id]}" in
            idle) ((idle_count++)) ;;
            busy) ((busy_count++)) ;;
            failed) ((failed_count++)) ;;
        esac
        
        total_requests=$((total_requests + ${CONNECTION_REQUEST_COUNT[$conn_id]:-0}))
        total_errors=$((total_errors + ${CONNECTION_ERROR_COUNT[$conn_id]:-0}))
    done
    
    cat << EOF
Connection Pool Statistics
=========================
Pool Size: $POOL_SIZE
Idle: $idle_count
Busy: $busy_count
Failed: $failed_count

Total Requests: $total_requests
Total Errors: $total_errors
Error Rate: $(awk "BEGIN {if($total_requests>0) printf \"%.1f%%\", $total_errors*100/$total_requests; else print \"0%\"}")

Per-Connection Stats:
EOF
    
    for conn_id in "${!CONNECTION_STATES[@]}"; do
        echo "  $conn_id: ${CONNECTION_STATES[$conn_id]} (requests: ${CONNECTION_REQUEST_COUNT[$conn_id]}, errors: ${CONNECTION_ERROR_COUNT[$conn_id]})"
    done
}

# Health check for connection pool
check_pool_health() {
    local healthy_threshold="${1:-50}"  # Minimum percentage of healthy connections
    
    local healthy_count=0
    local total_count=0
    
    for conn_id in "${!CONNECTION_STATES[@]}"; do
        ((total_count++))
        if [[ "${CONNECTION_STATES[$conn_id]}" != "failed" ]]; then
            ((healthy_count++))
        fi
    done
    
    local health_percentage=$((healthy_count * 100 / total_count))
    
    if [[ $health_percentage -ge $healthy_threshold ]]; then
        echo "healthy"
        return 0
    else
        echo "degraded"
        return 1
    fi
}

# Keepalive for connections
keepalive_connections() {
    while true; do
        local current_time=$(date +%s)
        
        for conn_id in "${!CONNECTION_STATES[@]}"; do
            if [[ "${CONNECTION_STATES[$conn_id]}" == "idle" ]]; then
                local last_used=${CONNECTION_LAST_USED[$conn_id]}
                local idle_time=$((current_time - last_used))
                
                if [[ $idle_time -ge $KEEPALIVE_INTERVAL ]]; then
                    # Send keepalive
                    log "DEBUG" "Sending keepalive for $conn_id"
                    CONNECTION_LAST_USED[$conn_id]=$current_time
                fi
            fi
        done
        
        sleep 30
    done
}

# Graceful shutdown of connection pool
shutdown_connection_pool() {
    log "INFO" "Shutting down connection pool"
    
    # Wait for busy connections to complete
    local timeout=30
    local start_time=$(date +%s)
    
    while true; do
        local busy_count=0
        
        for conn_id in "${!CONNECTION_STATES[@]}"; do
            if [[ "${CONNECTION_STATES[$conn_id]}" == "busy" ]]; then
                ((busy_count++))
            fi
        done
        
        if [[ $busy_count -eq 0 ]]; then
            break
        fi
        
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            log "WARN" "Timeout waiting for connections to complete"
            break
        fi
        
        log "INFO" "Waiting for $busy_count busy connections..."
        sleep 1
    done
    
    # Clear connection states
    unset CONNECTION_STATES
    unset CONNECTION_LAST_USED
    unset CONNECTION_REQUEST_COUNT
    unset CONNECTION_ERROR_COUNT
    
    log "INFO" "Connection pool shutdown complete"
}

# Initialize pool on module load
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Module is being run directly (for testing)
    init_connection_pool
    get_pool_stats
else
    # Module is being sourced
    init_connection_pool
fi