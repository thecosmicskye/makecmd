#!/usr/bin/env bash
#
# cache.sh - Caching functions for makecmd
#
# This module provides secure caching functionality with TTL support

# Lock file management
readonly LOCK_TIMEOUT=5  # seconds
readonly LOCK_SUFFIX=".lock"

# Function to acquire lock with timeout
acquire_lock() {
    local lockfile="$1"
    local timeout="${2:-$LOCK_TIMEOUT}"
    local pid=$$
    local lockpid_file="${lockfile}/pid"
    local start_time=$(date +%s)
    
    # Try to acquire lock with timeout
    while true; do
        # Atomic lock creation with PID
        if mkdir "$lockfile" 2>/dev/null; then
            # Write our PID to the lock
            echo "$pid" > "$lockpid_file"
            return 0
        fi
        
        # Check if lock is stale
        if [[ -d "$lockfile" ]] && [[ -f "$lockpid_file" ]]; then
            local lock_pid=$(cat "$lockpid_file" 2>/dev/null || echo "")
            
            # Check if the process that holds the lock is still running
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Process is dead, remove stale lock
                rm -rf "$lockfile" 2>/dev/null || true
                continue
            fi
            
            # Check lock age
            local lock_age=$(($(date +%s) - $(stat -f%m "$lockfile" 2>/dev/null || stat -c%Y "$lockfile" 2>/dev/null || echo 0)))
            if [[ $lock_age -gt 60 ]]; then
                # Remove very old lock regardless of PID
                rm -rf "$lockfile" 2>/dev/null || true
                continue
            fi
        fi
        
        # Check timeout
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi
        
        # Wait with exponential backoff
        local wait_time=$(awk "BEGIN {print 0.05 + $elapsed * 0.01}")
        sleep "$wait_time"
    done
}

# Function to release lock
release_lock() {
    local lockfile="$1"
    local pid=$$
    local lockpid_file="${lockfile}/pid"
    
    # Only release if we own the lock
    if [[ -f "$lockpid_file" ]]; then
        local lock_pid=$(cat "$lockpid_file" 2>/dev/null || echo "")
        if [[ "$lock_pid" == "$pid" ]]; then
            rm -rf "$lockfile" 2>/dev/null || true
        fi
    fi
}

# Function to generate cache key
generate_cache_key() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        log "ERROR" "Empty input for cache key generation" 2>/dev/null || true
        # Return empty string instead of failing
        echo ""
        return 0
    fi
    
    # Use SHA256 for cache key generation
    if command -v sha256sum > /dev/null 2>&1; then
        echo "$input" | sha256sum | cut -d' ' -f1
    elif command -v shasum > /dev/null 2>&1; then
        echo "$input" | shasum -a 256 | cut -d' ' -f1
    elif command -v openssl > /dev/null 2>&1; then
        # Use OpenSSL as fallback for SHA256
        echo -n "$input" | openssl dgst -sha256 | awk '{print $2}'
    else
        # No secure hashing available - generate a random key instead
        log "ERROR" "No secure hash command available (sha256sum, shasum, or openssl)" 2>/dev/null || true
        # Generate a unique key based on timestamp and random data
        echo "$(date +%s)_$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
}

# Function to get cache file path
get_cache_file_path() {
    local cache_key="$1"
    echo "${CACHE_DIR}/${cache_key}.cache"
}

# Function to get cache metadata file path
get_cache_meta_path() {
    local cache_key="$1"
    echo "${CACHE_DIR}/${cache_key}.meta"
}

# Function to check if cache entry is valid
is_cache_valid() {
    local cache_key="$1"
    local cache_file=$(get_cache_file_path "$cache_key")
    local meta_file=$(get_cache_meta_path "$cache_key")
    
    # Check if both files exist
    if [[ ! -f "$cache_file" ]] || [[ ! -f "$meta_file" ]]; then
        return 1
    fi
    
    # Read metadata
    local created_at=$(cat "$meta_file" 2>/dev/null | grep "created_at:" | cut -d':' -f2)
    local ttl=$(cat "$meta_file" 2>/dev/null | grep "ttl:" | cut -d':' -f2)
    
    # Default TTL if not specified
    ttl=${ttl:-$DEFAULT_CACHE_TTL}
    
    # Check if cache has expired
    local current_time=$(date +%s)
    local expire_time=$((created_at + ttl))
    
    # TTL of 0 means immediate expiration
    if [[ $ttl -eq 0 ]] || [[ $current_time -ge $expire_time ]]; then
        log "DEBUG" "Cache expired for key: $cache_key"
        # Clean up expired cache
        rm -f "$cache_file" "$meta_file"
        return 1
    fi
    
    return 0
}

# Function to get cached command
get_cached_command() {
    local cache_key="$1"
    local cache_file=$(get_cache_file_path "$cache_key")
    local lockfile="${cache_file}${LOCK_SUFFIX}"
    
    # Acquire lock
    if ! acquire_lock "$lockfile"; then
        log "WARN" "Failed to acquire lock for cache read: $cache_key"
        return 1
    fi
    
    # Ensure lock is released on exit
    trap "release_lock '$lockfile'" EXIT INT TERM
    
    if ! is_cache_valid "$cache_key"; then
        release_lock "$lockfile"
        trap - EXIT INT TERM
        return 1
    fi
    
    # Read and validate cached command
    if [[ -f "$cache_file" ]]; then
        local cached_command=$(cat "$cache_file" 2>/dev/null)
        
        # Validate the cached command is not empty
        if [[ -n "$cached_command" ]]; then
            log "DEBUG" "Cache hit for key: $cache_key"
            echo "$cached_command"
            release_lock "$lockfile"
            trap - EXIT INT TERM
            return 0
        fi
    fi
    
    release_lock "$lockfile"
    trap - EXIT INT TERM
    return 1
}

# Function to cache command
cache_command() {
    local cache_key="$1"
    local command="$2"
    local ttl="${3:-$DEFAULT_CACHE_TTL}"
    
    local cache_file=$(get_cache_file_path "$cache_key")
    local meta_file=$(get_cache_meta_path "$cache_key")
    local lockfile="${cache_file}${LOCK_SUFFIX}"
    
    # Ensure cache directory exists with proper permissions
    mkdir -p "$CACHE_DIR"
    
    # Set restrictive permissions on cache directory
    chmod 700 "$CACHE_DIR"
    
    # Acquire lock
    if ! acquire_lock "$lockfile"; then
        log "WARN" "Failed to acquire lock for cache write: $cache_key"
        return 1
    fi
    
    # Ensure lock is released on exit
    trap "release_lock '$lockfile'" EXIT INT TERM
    
    # Write command to cache file atomically
    local temp_file="${cache_file}.tmp.$$"
    if ! echo "$command" > "$temp_file" 2>/dev/null; then
        release_lock "$lockfile"
        trap - EXIT INT TERM
        log "ERROR" "Failed to write cache file"
        return 1
    fi
    chmod 600 "$temp_file"
    
    # Atomic rename
    if ! mv -f "$temp_file" "$cache_file" 2>/dev/null; then
        rm -f "$temp_file" 2>/dev/null || true
        release_lock "$lockfile"
        trap - EXIT INT TERM
        log "ERROR" "Failed to move cache file"
        return 1
    fi
    
    # Calculate command hash
    local cmd_hash=""
    if command -v sha256sum > /dev/null 2>&1; then
        cmd_hash=$(echo "$command" | sha256sum | cut -d' ' -f1)
    elif command -v shasum > /dev/null 2>&1; then
        cmd_hash=$(echo "$command" | shasum -a 256 | cut -d' ' -f1)
    elif command -v openssl > /dev/null 2>&1; then
        cmd_hash=$(echo -n "$command" | openssl dgst -sha256 | awk '{print $2}')
    else
        # No hash available, use a placeholder
        cmd_hash="no_hash_available"
    fi
    
    # Write metadata atomically
    local temp_meta="${meta_file}.tmp.$$"
    if ! cat > "$temp_meta" << EOF
created_at:$(date +%s)
ttl:$ttl
command_hash:$cmd_hash
pid:$$
EOF
    then
        rm -f "$temp_file" "$temp_meta" 2>/dev/null || true
        release_lock "$lockfile"
        trap - EXIT INT TERM
        log "ERROR" "Failed to write metadata file"
        return 1
    fi
    chmod 600 "$temp_meta"
    
    # Atomic rename
    if ! mv -f "$temp_meta" "$meta_file" 2>/dev/null; then
        rm -f "$temp_meta" 2>/dev/null || true
        release_lock "$lockfile"
        trap - EXIT INT TERM
        log "ERROR" "Failed to move metadata file"
        return 1
    fi
    
    release_lock "$lockfile"
    trap - EXIT INT TERM
    
    log "DEBUG" "Cached command with key: $cache_key"
}

# Function to clear cache
clear_cache() {
    local older_than="${1:-0}"  # Clear entries older than N seconds
    
    if [[ "$older_than" -eq 0 ]]; then
        # Clear all cache
        rm -f "${CACHE_DIR}"/*.cache "${CACHE_DIR}"/*.meta
        log "INFO" "Cleared all cache entries"
    else
        # Clear old entries
        local current_time=$(date +%s)
        local cleared=0
        
        for meta_file in "${CACHE_DIR}"/*.meta; do
            if [[ -f "$meta_file" ]]; then
                local created_at=$(cat "$meta_file" 2>/dev/null | grep "created_at:" | cut -d':' -f2)
                if [[ -n "$created_at" ]]; then
                    local age=$((current_time - created_at))
                    if [[ $age -gt $older_than ]]; then
                        local cache_key=$(basename "$meta_file" .meta)
                        rm -f "$(get_cache_file_path "$cache_key")" "$meta_file"
                        ((cleared++))
                    fi
                fi
            fi
        done
        
        log "INFO" "Cleared $cleared old cache entries"
    fi
}

# Function to get cache statistics
get_cache_stats() {
    local total_entries=0
    local total_size=0
    local expired_entries=0
    
    for cache_file in "${CACHE_DIR}"/*.cache; do
        if [[ -f "$cache_file" ]]; then
            ((total_entries++))
            local size=$(stat -f%z "$cache_file" 2>/dev/null || stat -c%s "$cache_file" 2>/dev/null || echo 0)
            total_size=$((total_size + size))
            
            local cache_key=$(basename "$cache_file" .cache)
            if ! is_cache_valid "$cache_key"; then
                ((expired_entries++))
            fi
        fi
    done
    
    cat << EOF
Cache Statistics:
  Total entries: $total_entries
  Total size: $total_size bytes
  Expired entries: $expired_entries
  Cache directory: $CACHE_DIR
EOF
}

# Function to validate cache integrity
validate_cache_integrity() {
    local cache_key="$1"
    local cache_file=$(get_cache_file_path "$cache_key")
    local meta_file=$(get_cache_meta_path "$cache_key")
    
    if [[ ! -f "$cache_file" ]] || [[ ! -f "$meta_file" ]]; then
        return 1
    fi
    
    # Read stored hash
    local stored_hash=$(cat "$meta_file" 2>/dev/null | grep "command_hash:" | cut -d':' -f2)
    
    # Calculate current hash
    local current_hash=""
    if command -v sha256sum > /dev/null 2>&1; then
        current_hash=$(cat "$cache_file" 2>/dev/null | sha256sum | cut -d' ' -f1)
    elif command -v shasum > /dev/null 2>&1; then
        current_hash=$(cat "$cache_file" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    elif command -v openssl > /dev/null 2>&1; then
        current_hash=$(cat "$cache_file" 2>/dev/null | openssl dgst -sha256 | awk '{print $2}')
    else
        # Cannot verify integrity without hash
        log "WARN" "Cannot verify cache integrity without hash command"
        return 0
    fi
    
    if [[ "$stored_hash" != "$current_hash" ]]; then
        log "WARN" "Cache integrity check failed for key: $cache_key"
        # Remove corrupted cache
        rm -f "$cache_file" "$meta_file"
        return 1
    fi
    
    return 0
}

# Function to export cache entry
export_cache_entry() {
    local cache_key="$1"
    local output_file="$2"
    
    if ! is_cache_valid "$cache_key"; then
        return 1
    fi
    
    local cache_file=$(get_cache_file_path "$cache_key")
    local meta_file=$(get_cache_meta_path "$cache_key")
    
    cat > "$output_file" << EOF
# makecmd cache export
# Key: $cache_key
# Metadata:
$(cat "$meta_file")
# Command:
$(cat "$cache_file")
EOF
    
    chmod 600 "$output_file"
}

# Function to import cache entry
import_cache_entry() {
    local import_file="$1"
    
    if [[ ! -f "$import_file" ]]; then
        log "ERROR" "Import file not found: $import_file"
        return 1
    fi
    
    # Extract cache key
    local cache_key=$(grep "^# Key:" "$import_file" | cut -d':' -f2 | tr -d ' ')
    
    if [[ -z "$cache_key" ]]; then
        log "ERROR" "Invalid import file format"
        return 1
    fi
    
    # Extract and cache command - use a simpler approach
    local command=$(grep -A 1000 "^# Command:" "$import_file" | tail -n +2)
    
    if [[ -n "$command" ]]; then
        cache_command "$cache_key" "$command"
        return 0
    fi
    
    return 1
}