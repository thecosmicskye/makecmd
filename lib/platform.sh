#!/usr/bin/env bash
#
# platform.sh - Platform compatibility layer for makecmd
#
# This module provides cross-platform compatibility functions

# Detect platform
detect_platform() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        msys*|cygwin*|mingw*) echo "windows" ;;
        freebsd*) echo "freebsd" ;;
        *)        echo "unknown" ;;
    esac
}

# Platform detection
readonly PLATFORM=$(detect_platform)
readonly IS_MACOS=$([[ "$PLATFORM" == "macos" ]] && echo true || echo false)
readonly IS_LINUX=$([[ "$PLATFORM" == "linux" ]] && echo true || echo false)
readonly IS_WINDOWS=$([[ "$PLATFORM" == "windows" ]] && echo true || echo false)

# Function to get file modification time (cross-platform)
get_file_mtime() {
    local file="$1"
    
    if [[ "$IS_MACOS" == "true" ]] || [[ "${IS_FREEBSD:-false}" == "true" ]]; then
        stat -f%m "$file" 2>/dev/null
    else
        stat -c%Y "$file" 2>/dev/null
    fi
}

# Function to get file permissions (cross-platform)
get_file_perms() {
    local file="$1"
    
    if [[ "$IS_MACOS" == "true" ]] || [[ "${IS_FREEBSD:-false}" == "true" ]]; then
        stat -f%p "$file" 2>/dev/null | tail -c 4
    else
        stat -c%a "$file" 2>/dev/null
    fi
}

# Function to get file size (cross-platform)
get_file_size() {
    local file="$1"
    
    if [[ "$IS_MACOS" == "true" ]] || [[ "${IS_FREEBSD:-false}" == "true" ]]; then
        stat -f%z "$file" 2>/dev/null
    else
        stat -c%s "$file" 2>/dev/null
    fi
}

# Function to resolve symlinks (cross-platform)
resolve_symlink() {
    local path="$1"
    
    if command -v readlink > /dev/null 2>&1; then
        if readlink -f / > /dev/null 2>&1; then
            # GNU readlink
            readlink -f "$path" 2>/dev/null
        else
            # BSD readlink
            local resolved="$path"
            while [[ -L "$resolved" ]]; do
                resolved=$(readlink "$resolved")
            done
            echo "$resolved"
        fi
    elif command -v realpath > /dev/null 2>&1; then
        realpath "$path" 2>/dev/null
    elif command -v python3 > /dev/null 2>&1; then
        python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$path" 2>/dev/null
    else
        echo "$path"
    fi
}

# Function to get clipboard command (cross-platform)
get_clipboard_command() {
    if [[ "$IS_MACOS" == "true" ]]; then
        echo "pbcopy"
    elif [[ "$IS_LINUX" == "true" ]]; then
        if command -v xclip > /dev/null 2>&1; then
            echo "xclip -selection clipboard"
        elif command -v xsel > /dev/null 2>&1; then
            echo "xsel --clipboard --input"
        else
            echo ""
        fi
    elif [[ "$IS_WINDOWS" == "true" ]]; then
        echo "clip"
    else
        echo ""
    fi
}

# Function to get SHA256 command (cross-platform)
get_sha256_command() {
    if command -v sha256sum > /dev/null 2>&1; then
        echo "sha256sum"
    elif command -v shasum > /dev/null 2>&1; then
        echo "shasum -a 256"
    elif command -v openssl > /dev/null 2>&1; then
        echo "openssl dgst -sha256"
    else
        echo ""
    fi
}

# Function to calculate SHA256 hash (cross-platform)
calculate_sha256() {
    local input="$1"
    local sha_cmd=$(get_sha256_command)
    
    if [[ -z "$sha_cmd" ]]; then
        log "ERROR" "No SHA256 command available"
        return 1
    fi
    
    case "$sha_cmd" in
        "sha256sum")
            echo "$input" | sha256sum | cut -d' ' -f1
            ;;
        "shasum -a 256")
            echo "$input" | shasum -a 256 | cut -d' ' -f1
            ;;
        "openssl dgst -sha256")
            echo -n "$input" | openssl dgst -sha256 | awk '{print $2}'
            ;;
    esac
}

# Function to get process info (cross-platform)
get_process_info() {
    local pid="$1"
    
    if [[ "$IS_MACOS" == "true" ]]; then
        ps -p "$pid" -o comm= 2>/dev/null
    else
        ps -p "$pid" -o cmd= 2>/dev/null
    fi
}

# Function to check if process is running (cross-platform)
is_process_running() {
    local pid="$1"
    
    if [[ "$IS_WINDOWS" == "true" ]]; then
        tasklist /FI "PID eq $pid" 2>/dev/null | grep -q "$pid"
    else
        kill -0 "$pid" 2>/dev/null
    fi
}

# Function to get system load (cross-platform)
get_system_load() {
    if [[ "$IS_MACOS" == "true" ]] || [[ "$IS_LINUX" == "true" ]]; then
        uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' '
    elif [[ "$IS_WINDOWS" == "true" ]]; then
        # Windows doesn't have load average, use CPU usage instead
        wmic cpu get loadpercentage /value 2>/dev/null | grep -oE '[0-9]+' || echo "0"
    else
        echo "0"
    fi
}

# Function to get available memory in KB (cross-platform)
get_available_memory() {
    if [[ "$IS_MACOS" == "true" ]]; then
        vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.' | awk '{print $1 * 4}'
    elif [[ "$IS_LINUX" == "true" ]]; then
        awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to create temp directory (cross-platform)
create_temp_dir() {
    local prefix="${1:-makecmd}"
    
    if command -v mktemp > /dev/null 2>&1; then
        if [[ "$IS_MACOS" == "true" ]]; then
            mktemp -d -t "${prefix}.XXXXXX"
        else
            mktemp -d -t "${prefix}.XXXXXX" 2>/dev/null || mktemp -d
        fi
    else
        local temp_dir="/tmp/${prefix}.$$"
        mkdir -p "$temp_dir"
        echo "$temp_dir"
    fi
}

# Function to get date in ISO format (cross-platform)
get_iso_date() {
    if command -v gdate > /dev/null 2>&1; then
        # GNU date on macOS (from coreutils)
        gdate -u +%Y-%m-%dT%H:%M:%SZ
    elif date --version 2>&1 | grep -q GNU; then
        # GNU date
        date -u +%Y-%m-%dT%H:%M:%SZ
    else
        # BSD date
        date -u +%Y-%m-%dT%H:%M:%SZ
    fi
}

# Function to calculate date offset (cross-platform)
date_offset() {
    local offset="$1"  # e.g., "-1 day", "+2 hours"
    
    if command -v gdate > /dev/null 2>&1; then
        gdate -d "$offset" +%s
    elif date --version 2>&1 | grep -q GNU; then
        date -d "$offset" +%s
    else
        # BSD date - more limited
        case "$offset" in
            *day*)
                local days=$(echo "$offset" | grep -oE '[+-]?[0-9]+')
                date -v "${days}d" +%s 2>/dev/null || date +%s
                ;;
            *hour*)
                local hours=$(echo "$offset" | grep -oE '[+-]?[0-9]+')
                date -v "${hours}H" +%s 2>/dev/null || date +%s
                ;;
            *)
                date +%s
                ;;
        esac
    fi
}

# Function to get timeout command (cross-platform)
get_timeout_command() {
    if command -v timeout > /dev/null 2>&1; then
        echo "timeout"
    elif command -v gtimeout > /dev/null 2>&1; then
        echo "gtimeout"
    else
        echo ""
    fi
}

# Function to run command with timeout (cross-platform)
run_with_timeout() {
    local timeout_secs="$1"
    shift
    local command="$@"
    
    local timeout_cmd=$(get_timeout_command)
    
    if [[ -n "$timeout_cmd" ]]; then
        $timeout_cmd "$timeout_secs" $command
    else
        # Fallback implementation using background process
        ( $command ) & 
        local pid=$!
        local count=0
        
        while [[ $count -lt $timeout_secs ]]; do
            if ! is_process_running $pid; then
                wait $pid
                return $?
            fi
            sleep 1
            ((count++))
        done
        
        # Timeout reached
        kill -TERM $pid 2>/dev/null || true
        sleep 1
        kill -KILL $pid 2>/dev/null || true
        return 124  # Same as GNU timeout
    fi
}

# Function to validate platform requirements
validate_platform_requirements() {
    local errors=0
    
    # Check bash version
    if [[ "${BASH_VERSION%%.*}" -lt 3 ]]; then
        log "ERROR" "Bash version 3.2 or higher required (found: $BASH_VERSION)"
        ((errors++))
    fi
    
    # Check required commands
    local required_commands=("sed" "grep" "awk" "tr" "cut" "cat" "mkdir" "rm" "mv")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            log "ERROR" "Required command not found: $cmd"
            ((errors++))
        fi
    done
    
    # Check for hash command
    if [[ -z "$(get_sha256_command)" ]]; then
        log "WARN" "No SHA256 command available - caching will be limited"
    fi
    
    # Platform-specific checks
    case "$PLATFORM" in
        macos)
            # Check for macOS specific requirements
            if ! command -v sw_vers > /dev/null 2>&1; then
                log "WARN" "Cannot detect macOS version"
            fi
            ;;
        linux)
            # Check for Linux specific requirements
            if [[ ! -f /proc/version ]]; then
                log "WARN" "Cannot detect Linux version"
            fi
            ;;
        windows)
            # Check for Windows specific requirements
            log "WARN" "Windows support is experimental"
            ;;
    esac
    
    return $errors
}