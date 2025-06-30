#!/usr/bin/env bash
#
# validator.sh - Command validation functions for makecmd
#
# This module validates generated commands for safety and security

# Function to validate generated command
validate_command() {
    local command="$1"
    local safe_mode="${2:-false}"
    
    # Basic validation - empty command
    if [[ -z "$command" ]]; then
        log "ERROR" "Empty command generated"
        return 1
    fi
    
    # Check command length
    if [[ ${#command} -gt 1000 ]]; then
        log "ERROR" "Command too long (>1000 chars)"
        return 1
    fi
    
    # Check for dangerous commands
    if ! check_dangerous_commands "$command" "$safe_mode"; then
        return 1
    fi
    
    # Check for dangerous patterns
    if ! check_dangerous_patterns "$command"; then
        return 1
    fi
    
    # Check for suspicious constructs
    if ! check_suspicious_constructs "$command"; then
        return 1
    fi
    
    # Validate command structure
    if ! validate_command_structure "$command"; then
        return 1
    fi
    
    # Additional checks for safe mode
    if [[ "$safe_mode" == "true" ]]; then
        if ! validate_safe_mode "$command"; then
            return 1
        fi
    fi
    
    return 0
}

# Function to check for dangerous commands
check_dangerous_commands() {
    local command="$1"
    local safe_mode="$2"
    
    # List of absolutely forbidden commands
    local forbidden_commands=(
        "rm -rf /"
        "rm -rf /*"
        "rm -rf ~"
        "rm -rf ~/*"
        "rm -rf ."
        "rm -rf ./*"
        "rm -rf *"
        "dd if=/dev/zero"
        "dd if=/dev/random"
        "mkfs"
        "format"
        ":(){:|:&};:"  # Fork bomb
        "chmod -R 777 /"
        "chmod -R 000 /"
        "chown -R"
        ">"  # Pure redirection that could overwrite files
    )
    
    # Check for exact matches
    for forbidden in "${forbidden_commands[@]}"; do
        if [[ "$command" == *"$forbidden"* ]]; then
            log "ERROR" "Dangerous command detected: $forbidden"
            return 1
        fi
    done
    
    # Pattern-based dangerous command detection
    local dangerous_patterns=(
        "rm.*-rf.*/"                # Recursive force remove on root
        "rm.*-fr.*/"                # Alternative syntax
        "dd.*of=/dev/[sh]d"         # Direct disk write
        "mkfs\."                    # Any mkfs command
        "format.*"                  # Format commands
        "kill.*-9.*[0-9]"          # Kill with SIGKILL
        "killall"                   # Kill all processes
        "shutdown"                  # System shutdown
        "reboot"                    # System reboot
        "halt"                      # System halt
        "poweroff"                  # Power off
        "init 0"                    # Change runlevel
        "telinit"                   # Change runlevel
        "systemctl.*stop"           # Stop system services
        "service.*stop"             # Stop services
        "curl.*\|.*sh"             # Curl pipe to shell
        "wget.*\|.*sh"             # Wget pipe to shell
        "curl.*\|.*bash"           # Curl pipe to bash
        "wget.*\|.*bash"           # Wget pipe to bash
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        if echo "$command" | grep -qE "$pattern"; then
            log "ERROR" "Dangerous pattern detected: $pattern"
            return 1
        fi
    done
    
    # Additional restrictions in safe mode
    if [[ "$safe_mode" == "true" ]]; then
        local safe_mode_forbidden=(
            "sudo"
            "su"
            "chmod"
            "chown"
            "mount"
            "umount"
            "fdisk"
            "parted"
            "apt"
            "apt-get"
            "yum"
            "dnf"
            "pacman"
            "brew"
            "npm install -g"
            "pip install"
            "gem install"
        )
        
        for forbidden in "${safe_mode_forbidden[@]}"; do
            if [[ "$command" == *"$forbidden"* ]]; then
                log "ERROR" "Command forbidden in safe mode: $forbidden"
                return 1
            fi
        done
    fi
    
    return 0
}

# Function to check for dangerous patterns
check_dangerous_patterns() {
    local command="$1"
    
    # Check for multiple commands chained together
    if echo "$command" | grep -qE '(;|\|\||&&)'; then
        log "WARN" "Command chaining detected"
        # Allow some safe chaining patterns
        if ! is_safe_chaining "$command"; then
            return 1
        fi
    fi
    
    # Check for background execution
    if echo "$command" | grep -qE '&[[:space:]]*$'; then
        log "ERROR" "Background execution detected"
        return 1
    fi
    
    # Check for subshell execution
    if echo "$command" | grep -qE '\$\(|`'; then
        log "ERROR" "Subshell execution detected"
        return 1
    fi
    
    # Check for process substitution
    if echo "$command" | grep -qE '<\(|>\('; then
        log "ERROR" "Process substitution detected"
        return 1
    fi
    
    # Check for here documents
    if echo "$command" | grep -qE '<<|<<<'; then
        log "ERROR" "Here document detected"
        return 1
    fi
    
    return 0
}

# Function to check if command chaining is safe
is_safe_chaining() {
    local command="$1"
    
    # Allow safe patterns like: command && echo "done"
    # or: test -f file && cat file
    local safe_chains=(
        ".*&&[[:space:]]*echo[[:space:]]"
        ".*&&[[:space:]]*printf[[:space:]]"
        ".*\|\|[[:space:]]*echo[[:space:]]"
        ".*\|\|[[:space:]]*printf[[:space:]]"
        "test[[:space:]].*&&[[:space:]]*"
        "\\[[[:space:]].*\\][[:space:]]*&&[[:space:]]*"
    )
    
    for pattern in "${safe_chains[@]}"; do
        if echo "$command" | grep -qE "$pattern"; then
            return 0
        fi
    done
    
    return 1
}

# Function to check for suspicious constructs
check_suspicious_constructs() {
    local command="$1"
    
    # Check for attempts to modify system files
    local system_paths=(
        "/etc"
        "/boot"
        "/sys"
        "/proc"
        "/dev"
        "/usr/bin"
        "/usr/sbin"
        "/bin"
        "/sbin"
        "/lib"
        "/lib64"
    )
    
    for path in "${system_paths[@]}"; do
        if echo "$command" | grep -qE "(>|>>)[[:space:]]*$path"; then
            log "ERROR" "Attempt to modify system path: $path"
            return 1
        fi
    done
    
    # Check for environment variable manipulation
    if echo "$command" | grep -qE '(export|unset)[[:space:]]+[A-Z_]+'; then
        log "WARN" "Environment variable manipulation detected"
        # Allow some safe environment variables
        if ! is_safe_env_var "$command"; then
            return 1
        fi
    fi
    
    # Check for alias or function definitions
    if echo "$command" | grep -qE '(alias|function)[[:space:]]+'; then
        log "ERROR" "Alias or function definition detected"
        return 1
    fi
    
    return 0
}

# Function to check if environment variable is safe
is_safe_env_var() {
    local command="$1"
    
    # List of safe environment variables
    local safe_vars=(
        "EDITOR"
        "VISUAL"
        "PAGER"
        "LESS"
        "GREP_OPTIONS"
        "LS_COLORS"
    )
    
    for var in "${safe_vars[@]}"; do
        if echo "$command" | grep -qE "(export|unset)[[:space:]]+$var"; then
            return 0
        fi
    done
    
    return 1
}

# Function to validate command structure
validate_command_structure() {
    local command="$1"
    
    # Check if command starts with a valid command name
    local first_word=$(echo "$command" | awk '{print $1}')
    
    # Must start with alphanumeric or /
    if ! echo "$first_word" | grep -qE '^[a-zA-Z0-9/_.-]+$'; then
        log "ERROR" "Invalid command structure: $first_word"
        return 1
    fi
    
    # Check for balanced quotes
    local single_quotes=$(echo "$command" | tr -cd "'" | wc -c)
    local double_quotes=$(echo "$command" | tr -cd '"' | wc -c)
    
    if [[ $((single_quotes % 2)) -ne 0 ]]; then
        log "ERROR" "Unbalanced single quotes"
        return 1
    fi
    
    if [[ $((double_quotes % 2)) -ne 0 ]]; then
        log "ERROR" "Unbalanced double quotes"
        return 1
    fi
    
    # Check for balanced parentheses
    local open_parens=$(echo "$command" | tr -cd '(' | wc -c)
    local close_parens=$(echo "$command" | tr -cd ')' | wc -c)
    
    if [[ $open_parens -ne $close_parens ]]; then
        log "ERROR" "Unbalanced parentheses"
        return 1
    fi
    
    return 0
}

# Function for additional safe mode validation
validate_safe_mode() {
    local command="$1"
    
    # In safe mode, only allow read-only operations
    local allowed_commands=(
        "ls"
        "cat"
        "head"
        "tail"
        "grep"
        "find"
        "wc"
        "sort"
        "uniq"
        "awk"
        "sed"
        "cut"
        "tr"
        "echo"
        "printf"
        "date"
        "pwd"
        "whoami"
        "hostname"
        "uname"
        "df"
        "du"
        "ps"
        "top"
        "which"
        "type"
        "file"
        "stat"
        "md5sum"
        "sha256sum"
    )
    
    local first_command=$(echo "$command" | awk '{print $1}' | sed 's/^.*\///')
    local allowed=false
    
    for cmd in "${allowed_commands[@]}"; do
        if [[ "$first_command" == "$cmd" ]]; then
            allowed=true
            break
        fi
    done
    
    if [[ "$allowed" == "false" ]]; then
        log "ERROR" "Command not allowed in safe mode: $first_command"
        return 1
    fi
    
    # No output redirection in safe mode
    if echo "$command" | grep -qE '>'; then
        log "ERROR" "Output redirection not allowed in safe mode"
        return 1
    fi
    
    # No pipes to potentially dangerous commands
    if echo "$command" | grep -qE '\|'; then
        log "ERROR" "Pipes not allowed in safe mode"
        return 1
    fi
    
    return 0
}

# Function to get risk level of command
get_command_risk_level() {
    local command="$1"
    
    # High risk indicators
    if echo "$command" | grep -qE '(rm|delete|format|dd|kill|chmod|chown)'; then
        echo "HIGH"
        return
    fi
    
    # Medium risk indicators
    if echo "$command" | grep -qE '(mv|cp|touch|mkdir|wget|curl|apt|yum)'; then
        echo "MEDIUM"
        return
    fi
    
    # Low risk - read-only operations
    echo "LOW"
}

# Function to generate safety warning
generate_safety_warning() {
    local command="$1"
    local risk_level=$(get_command_risk_level "$command")
    
    case "$risk_level" in
        HIGH)
            echo "⚠️  WARNING: This command could be destructive. Please review carefully before executing."
            ;;
        MEDIUM)
            echo "⚠️  CAUTION: This command will modify your system. Please verify before executing."
            ;;
        LOW)
            echo "ℹ️  This appears to be a safe, read-only command."
            ;;
    esac
}