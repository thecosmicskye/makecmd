#!/usr/bin/env bash
#
# ratelimit.sh - Rate limiting functions for makecmd
#
# This module provides rate limiting to prevent API abuse

# Rate limit configuration
readonly RATE_LIMIT_DIR="${HOME}/.makecmd/ratelimit"
readonly DEFAULT_RATE_LIMIT=30  # requests per minute
readonly DEFAULT_BURST_LIMIT=5  # burst allowance
readonly TOKEN_BUCKET_FILE="${RATE_LIMIT_DIR}/tokens"
readonly LAST_CHECK_FILE="${RATE_LIMIT_DIR}/last_check"

# Initialize rate limiting
init_rate_limit() {
    # Create rate limit directory
    mkdir -p "$RATE_LIMIT_DIR"
    chmod 700 "$RATE_LIMIT_DIR"
    
    # Initialize token bucket if it doesn't exist
    if [[ ! -f "$TOKEN_BUCKET_FILE" ]]; then
        echo "$DEFAULT_BURST_LIMIT" > "$TOKEN_BUCKET_FILE"
        chmod 600 "$TOKEN_BUCKET_FILE"
    fi
    
    # Initialize last check time
    if [[ ! -f "$LAST_CHECK_FILE" ]]; then
        date +%s > "$LAST_CHECK_FILE"
        chmod 600 "$LAST_CHECK_FILE"
    fi
}

# Check if request is allowed under rate limit
check_rate_limit() {
    local rate_limit="${1:-$DEFAULT_RATE_LIMIT}"
    local burst_limit="${2:-$DEFAULT_BURST_LIMIT}"
    
    # Initialize if needed
    init_rate_limit
    
    # Get current time
    local current_time=$(date +%s)
    
    # Read last check time and current tokens
    local last_check=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo "$current_time")
    local current_tokens=$(cat "$TOKEN_BUCKET_FILE" 2>/dev/null || echo "$burst_limit")
    
    # Calculate time elapsed
    local time_elapsed=$((current_time - last_check))
    
    # Calculate tokens to add (rate per second)
    local tokens_per_second=$(echo "scale=4; $rate_limit / 60" | bc 2>/dev/null || echo "0.5")
    local tokens_to_add=$(echo "scale=0; $time_elapsed * $tokens_per_second" | bc 2>/dev/null || echo "0")
    
    # Update token count (cap at burst limit)
    current_tokens=$(echo "$current_tokens + $tokens_to_add" | bc 2>/dev/null || echo "$current_tokens")
    if [[ $(echo "$current_tokens > $burst_limit" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        current_tokens=$burst_limit
    fi
    
    # Check if we have tokens available
    if [[ $(echo "$current_tokens >= 1" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        # Consume one token
        current_tokens=$(echo "$current_tokens - 1" | bc 2>/dev/null || echo "0")
        
        # Update files
        echo "$current_tokens" > "$TOKEN_BUCKET_FILE"
        echo "$current_time" > "$LAST_CHECK_FILE"
        
        log "DEBUG" "Rate limit check passed. Tokens remaining: $current_tokens"
        return 0
    else
        # Rate limit exceeded
        local wait_time=$(echo "scale=0; 60 / $rate_limit" | bc 2>/dev/null || echo "2")
        log "WARN" "Rate limit exceeded. Please wait $wait_time seconds."
        return 1
    fi
}

# Get current rate limit status
get_rate_limit_status() {
    local rate_limit="${1:-$DEFAULT_RATE_LIMIT}"
    local burst_limit="${2:-$DEFAULT_BURST_LIMIT}"
    
    # Initialize if needed
    init_rate_limit
    
    # Read current tokens
    local current_tokens=$(cat "$TOKEN_BUCKET_FILE" 2>/dev/null || echo "$burst_limit")
    
    echo "Rate Limit Status:"
    echo "  Current tokens: $current_tokens"
    echo "  Burst limit: $burst_limit"
    echo "  Rate limit: $rate_limit requests/minute"
}

# Reset rate limit (for testing or admin use)
reset_rate_limit() {
    local burst_limit="${1:-$DEFAULT_BURST_LIMIT}"
    
    echo "$burst_limit" > "$TOKEN_BUCKET_FILE"
    date +%s > "$LAST_CHECK_FILE"
    
    log "INFO" "Rate limit reset. Tokens: $burst_limit"
}

# Clean up old rate limit data
cleanup_rate_limit() {
    # Remove rate limit files older than 1 day
    if [[ -d "$RATE_LIMIT_DIR" ]]; then
        find "$RATE_LIMIT_DIR" -type f -mtime +1 -delete 2>/dev/null || true
    fi
}