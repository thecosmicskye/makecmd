#!/usr/bin/env bash
#
# sanitizer.sh - Input and output sanitization functions for makecmd
#
# This module provides comprehensive sanitization for both user input
# and Claude Code output to prevent command injection and execution

# Function to sanitize user input
sanitize_input() {
    local input="$1"
    local sanitized=""
    
    # Remove leading/trailing whitespace
    input=$(echo "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # Remove null bytes
    input=$(echo "$input" | tr -d '\0')
    
    # Remove control characters except space and tab
    input=$(echo "$input" | tr -cd '[:print:]\t')
    
    # Escape dangerous shell metacharacters
    # This escapes: ; | & $ ` ( ) { } [ ] < > \ " '
    # Using a single sed command with multiple expressions for efficiency
    sanitized=$(echo "$input" | sed -e 's/\\/\\\\/g' \
                                    -e 's/\$/\\$/g' \
                                    -e 's/;/\\;/g' \
                                    -e 's/|/\\|/g' \
                                    -e 's/&/\\&/g' \
                                    -e 's/`/\\`/g' \
                                    -e 's/(/\\(/g' \
                                    -e 's/)/\\)/g' \
                                    -e 's/{/\\{/g' \
                                    -e 's/}/\\}/g' \
                                    -e 's/\[/\\[/g' \
                                    -e 's/\]/\\]/g' \
                                    -e 's/</\\</g' \
                                    -e 's/>/\\>/g' \
                                    -e 's/"/\\"/g' \
                                    -e "s/'/\\\\'/g")
    
    # Remove newlines, carriage returns, and other line terminators
    sanitized=$(echo "$sanitized" | tr -d '\n\r\f\v')
    
    # Limit length (should already be checked, but double-check)
    sanitized="${sanitized:0:500}"
    
    # Validate UTF-8 encoding
    if ! echo "$sanitized" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
        log "WARN" "Invalid UTF-8 in input, cleaning"
        sanitized=$(echo "$sanitized" | iconv -f UTF-8 -t UTF-8 -c)
    fi
    
    echo "$sanitized"
}

# Function to sanitize Claude's output
sanitize_claude_output() {
    local output="$1"
    local sanitized=""
    
    # First, remove any potential markdown code blocks
    output=$(echo "$output" | sed -e 's/^```[a-zA-Z]*//' -e 's/```$//')
    
    # Remove ALL newlines, carriage returns, and line feeds
    # This is critical to prevent command execution
    output=$(printf '%s' "$output" | tr -d '\n\r\f\v')
    
    # Remove ANSI escape sequences
    output=$(echo "$output" | sed -e 's/'$'\033''\[[0-9;]*[mGKH]//g')
    
    # Remove backticks and command substitution patterns - more comprehensive
    output=$(echo "$output" | sed -e 's/`[^`]*`//g' -e 's/\$([^)]*)//g' -e 's/\${[^}]*}//g')
    
    # Remove any remaining control characters
    output=$(echo "$output" | tr -cd '[:print:]')
    
    # Trim whitespace
    output=$(echo "$output" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # Remove multiple spaces
    output=$(echo "$output" | tr -s ' ')
    
    # Remove semicolons at the end (common execution trigger)
    output=$(echo "$output" | sed -e 's/;[[:space:]]*$//')
    
    # Remove any pipe at the end (trim whitespace first)
    output=$(echo "$output" | sed -e 's/[[:space:]]*$//' -e 's/|$//')
    
    # Remove any ampersand at the end (background execution)
    output=$(echo "$output" | sed -e 's/&[[:space:]]*$//')
    
    # Check for and remove common execution patterns
    # Remove things like: && command, || command, ; command
    output=$(echo "$output" | sed -e 's/[;&|]\{1,2\}[[:space:]]*[^[:space:]]*$//')
    
    # Final safety check - ensure single line
    if [[ $(echo "$output" | wc -l) -gt 1 ]]; then
        log "WARN" "Multi-line output detected, taking first line only"
        output=$(echo "$output" | head -n1)
    fi
    
    sanitized="$output"
    
    echo "$sanitized"
}

# Function to validate shell metacharacters
validate_metacharacters() {
    local input="$1"
    
    # Check for unescaped dangerous metacharacters
    # Returns 1 if unescaped metacharacters found, 0 if clean
    # Check for dangerous characters one by one to avoid regex complexity
    for char in ';' '&' '|' '`' '$' '(' ')' '{' '}' '[' ']' '<' '>'; do
        if [[ "$input" == *"$char"* ]] && [[ "$input" != *"\\$char"* ]]; then
            return 1
        fi
    done
    
    return 0
}

# Function to check for command injection attempts
check_injection_attempts() {
    local input="$1"
    
    # Common injection patterns (note: this returns 0 for injection, 1 for clean)
    local injection_patterns=(
        '\$\('           # Command substitution
        '`'              # Backtick command substitution
        '\$\{'           # Variable expansion
        ';'              # Command chaining with semicolon
        '&&'             # Command chaining with &&
        '\|\|'           # Command chaining with ||
        '\|'             # Pipe
        '>'              # Output redirection
        '<'              # Input redirection
        '>>'             # Append redirection
        '&[[:space:]]*$' # Background execution at end
    )
    
    for pattern in "${injection_patterns[@]}"; do
        if echo "$input" | grep -qE "$pattern"; then
            log "WARN" "Potential injection attempt detected: $pattern"
            return 0  # Return 0 to indicate injection found
        fi
    done
    
    return 1  # Return 1 to indicate clean (no injection)
}

# Function to escape special characters for safe display
escape_for_display() {
    local input="$1"
    
    # Escape characters that could affect terminal display
    input=$(echo "$input" | sed 's/\\/\\\\/g')  # Escape backslashes first
    input=$(echo "$input" | sed 's/"/\\"/g')    # Escape double quotes
    input=$(echo "$input" | sed "s/'/\\\\'/g")  # Escape single quotes
    
    echo "$input"
}

# Function to strip ANSI color codes
strip_ansi_codes() {
    local input="$1"
    echo "$input" | sed 's/\x1b\[[0-9;]*[mGKH]//g'
}

# Function to validate character encoding
validate_encoding() {
    local input="$1"
    
    # Check if input is valid UTF-8
    if echo "$input" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to sanitize path inputs
sanitize_path() {
    local path="$1"
    local resolved_path=""
    
    # Remove any attempt at path traversal
    path=$(echo "$path" | sed -e 's/\.\.//g')
    
    # Remove trailing slashes
    path=$(echo "$path" | sed -e 's/\/*$//')
    
    # Remove any shell metacharacters from paths
    path=$(echo "$path" | tr -d ';&|`$(){}[]<>')
    
    # If path exists, resolve symlinks to prevent symlink attacks
    if [[ -e "$path" ]]; then
        # Use readlink -f for full resolution (GNU) or Python as fallback
        if command -v readlink > /dev/null 2>&1 && readlink -f / > /dev/null 2>&1; then
            resolved_path=$(readlink -f "$path" 2>/dev/null || echo "$path")
        elif command -v python3 > /dev/null 2>&1; then
            resolved_path=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$path" 2>/dev/null || echo "$path")
        elif command -v python > /dev/null 2>&1; then
            resolved_path=$(python -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$path" 2>/dev/null || echo "$path")
        else
            resolved_path="$path"
        fi
        
        # Ensure resolved path doesn't escape expected boundaries
        # Check if path is trying to escape to system directories
        local dangerous_paths=("/etc" "/sys" "/proc" "/dev" "/boot" "/lib" "/bin" "/sbin" "/usr/bin" "/usr/sbin" "/private/etc" "/private/var")
        for dangerous in "${dangerous_paths[@]}"; do
            if [[ "$resolved_path" == "$dangerous"* ]]; then
                log "WARN" "Path resolution attempted to access system directory: $resolved_path"
                # Return empty string to indicate rejection
                echo ""
                return 1
            fi
        done
        
        echo "$resolved_path"
    else
        echo "$path"
    fi
}

# Function to check for sensitive information
check_sensitive_info() {
    local input="$1"
    
    # Patterns for sensitive information
    local sensitive_patterns=(
        '.*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd].*'
        '.*[Aa][Pp][Ii].*[Kk][Ee][Yy].*'
        '.*[Ss][Ee][Cc][Rr][Ee][Tt].*'
        '.*[Tt][Oo][Kk][Ee][Nn].*'
        '.*[Aa][Uu][Tt][Hh].*'
        '.*[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll].*'
    )
    
    for pattern in "${sensitive_patterns[@]}"; do
        if echo "$input" | grep -qiE "$pattern"; then
            log "WARN" "Potential sensitive information detected"
            return 1
        fi
    done
    
    return 0
}