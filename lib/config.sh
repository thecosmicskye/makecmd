#!/usr/bin/env bash
#
# config.sh - Configuration management for makecmd
#
# This module handles loading and parsing configuration files

# Default configuration values
# Using individual variables for bash 3.2 compatibility
CONFIG_output_mode="auto"
CONFIG_cache_ttl="3600"
CONFIG_safe_mode="false"
CONFIG_debug="false"
CONFIG_timeout="30"
CONFIG_max_input_length="500"
CONFIG_log_level="INFO"
CONFIG_color_output="true"
CONFIG_prefill_shell="auto"
CONFIG_clipboard_command="auto"
CONFIG_rate_limit="30"
CONFIG_burst_limit="5"

# Function to load configuration file
load_config() {
    local config_file="$1"
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log "DEBUG" "No config file found at: $config_file"
        return 0
    fi
    
    # Check file permissions
    local perms=$(stat -f%p "$config_file" 2>/dev/null || stat -c%a "$config_file" 2>/dev/null)
    if [[ -n "$perms" ]]; then
        # Remove file type bits, keep only permission bits
        perms=$((perms & 0777))
        if [[ $perms -ne 600 ]] && [[ $perms -ne 644 ]]; then
            log "WARN" "Config file has insecure permissions: $perms"
            echo -e "${YELLOW}Warning: Config file should have 600 or 644 permissions${NC}" >&2
        fi
    fi
    
    # Parse config file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Trim whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Remove quotes if present
        value=$(echo "$value" | sed 's/^["'\'']\(.*\)["'\'']$/\1/')
        
        # Validate and set configuration
        if validate_config_option "$key" "$value"; then
            # Safe assignment without eval
            case "$key" in
                output_mode)       CONFIG_output_mode="$value" ;;
                cache_ttl)         CONFIG_cache_ttl="$value" ;;
                safe_mode)         CONFIG_safe_mode="$value" ;;
                debug)             CONFIG_debug="$value" ;;
                timeout)           CONFIG_timeout="$value" ;;
                max_input_length)  CONFIG_max_input_length="$value" ;;
                log_level)         CONFIG_log_level="$value" ;;
                color_output)      CONFIG_color_output="$value" ;;
                prefill_shell)     CONFIG_prefill_shell="$value" ;;
                clipboard_command) CONFIG_clipboard_command="$value" ;;
                rate_limit)        CONFIG_rate_limit="$value" ;;
                burst_limit)       CONFIG_burst_limit="$value" ;;
                *)
                    log "WARN" "Unknown config option: $key"
                    continue
                    ;;
            esac
            log "DEBUG" "Config: $key = $value"
        else
            log "WARN" "Invalid config option: $key = $value"
        fi
    done < "$config_file"
    
    # Apply loaded configuration
    apply_config
}

# Function to validate configuration option
validate_config_option() {
    local key="$1"
    local value="$2"
    
    case "$key" in
        output_mode)
            [[ "$value" =~ ^(auto|prefill|clipboard|stdout)$ ]]
            ;;
        cache_ttl)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -ge 0 ]]
            ;;
        safe_mode|debug|color_output)
            [[ "$value" =~ ^(true|false)$ ]]
            ;;
        timeout)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]] && [[ $value -le 600 ]]
            ;;
        max_input_length)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]] && [[ $value -le 10000 ]]
            ;;
        log_level)
            [[ "$value" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]]
            ;;
        prefill_shell)
            [[ "$value" =~ ^(auto|zsh|bash|none)$ ]]
            ;;
        clipboard_command)
            [[ "$value" =~ ^(auto|pbcopy|xclip|xsel|clip|none)$ ]]
            ;;
        rate_limit)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]] && [[ $value -le 120 ]]
            ;;
        burst_limit)
            [[ "$value" =~ ^[0-9]+$ ]] && [[ $value -gt 0 ]] && [[ $value -le 20 ]]
            ;;
        *)
            # Unknown option
            return 1
            ;;
    esac
}

# Function to apply configuration
apply_config() {
    # Apply global variables from config
    [[ -n "${CONFIG_output_mode:-}" ]] && OUTPUT_MODE="${CONFIG_output_mode}"
    [[ -n "${CONFIG_cache_ttl:-}" ]] && DEFAULT_CACHE_TTL="${CONFIG_cache_ttl}"
    [[ -n "${CONFIG_safe_mode:-}" ]] && [[ "${CONFIG_safe_mode}" == "true" ]] && SAFE_MODE=true
    [[ -n "${CONFIG_debug:-}" ]] && [[ "${CONFIG_debug}" == "true" ]] && DEBUG=true
    [[ -n "${CONFIG_timeout:-}" ]] && CLAUDE_TIMEOUT="${CONFIG_timeout}"
    [[ -n "${CONFIG_max_input_length:-}" ]] && MAX_INPUT_LENGTH="${CONFIG_max_input_length}"
    
    # Set color output
    if [[ "${CONFIG_color_output:-}" == "false" ]]; then
        RED=""
        YELLOW=""
        GREEN=""
        BLUE=""
        BOLD=""
        NC=""
    fi
}

# Function to generate default config file
generate_default_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    cat > "$config_file" << 'EOF'
# makecmd configuration file
#
# This file contains configuration options for makecmd
# Lines starting with # are comments
# Format: key = value

# Output mode: auto, prefill, clipboard, stdout
output_mode = auto

# Cache time-to-live in seconds (0 to disable caching)
cache_ttl = 3600

# Safe mode: restrict to read-only commands
safe_mode = false

# Debug mode: enable verbose logging
debug = false

# Claude timeout in seconds (max 600)
timeout = 30

# Maximum input length
max_input_length = 500

# Log level: DEBUG, INFO, WARN, ERROR
log_level = INFO

# Color output
color_output = true

# Preferred shell for pre-fill: auto, zsh, bash, none
prefill_shell = auto

# Clipboard command: auto, pbcopy, xclip, xsel, clip, none
clipboard_command = auto

# Rate limiting: requests per minute (1-120)
rate_limit = 30

# Burst limit: maximum requests in burst (1-20)
burst_limit = 5

# Custom prompt template (advanced users only)
# Use {input} as placeholder for sanitized input
# prompt_template = "Convert to shell command: {input}"

# Blocked commands (comma-separated)
# blocked_commands = "rm -rf,dd,format"

# Additional safe commands for safe mode (comma-separated)
# safe_mode_commands = "git,docker,kubectl"
EOF
    
    chmod 600 "$config_file"
    log "INFO" "Generated default config file: $config_file"
}

# Function to validate config file syntax
validate_config_file() {
    local config_file="$1"
    local line_num=0
    local errors=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Check format
        if ! echo "$line" | grep -qE '^[[:space:]]*[a-z_]+[[:space:]]*=[[:space:]]*.*$'; then
            echo "Error on line $line_num: Invalid format - $line" >&2
            ((errors++))
        fi
    done < "$config_file"
    
    return $errors
}

# Function to get config value
get_config() {
    local key="$1"
    
    # Safe config retrieval without indirect expansion
    case "$key" in
        output_mode)       echo "${CONFIG_output_mode:-}" ;;
        cache_ttl)         echo "${CONFIG_cache_ttl:-}" ;;
        safe_mode)         echo "${CONFIG_safe_mode:-}" ;;
        debug)             echo "${CONFIG_debug:-}" ;;
        timeout)           echo "${CONFIG_timeout:-}" ;;
        max_input_length)  echo "${CONFIG_max_input_length:-}" ;;
        log_level)         echo "${CONFIG_log_level:-}" ;;
        color_output)      echo "${CONFIG_color_output:-}" ;;
        prefill_shell)     echo "${CONFIG_prefill_shell:-}" ;;
        clipboard_command) echo "${CONFIG_clipboard_command:-}" ;;
        rate_limit)        echo "${CONFIG_rate_limit:-}" ;;
        burst_limit)       echo "${CONFIG_burst_limit:-}" ;;
        *)                 echo "" ;;
    esac
}

# Function to set config value (runtime only)
set_config() {
    local key="$1"
    local value="$2"
    
    if validate_config_option "$key" "$value"; then
        # Safe assignment without eval
        case "$key" in
            output_mode)       CONFIG_output_mode="$value" ;;
            cache_ttl)         CONFIG_cache_ttl="$value" ;;
            safe_mode)         CONFIG_safe_mode="$value" ;;
            debug)             CONFIG_debug="$value" ;;
            timeout)           CONFIG_timeout="$value" ;;
            max_input_length)  CONFIG_max_input_length="$value" ;;
            log_level)         CONFIG_log_level="$value" ;;
            color_output)      CONFIG_color_output="$value" ;;
            prefill_shell)     CONFIG_prefill_shell="$value" ;;
            clipboard_command) CONFIG_clipboard_command="$value" ;;
            rate_limit)        CONFIG_rate_limit="$value" ;;
            burst_limit)       CONFIG_burst_limit="$value" ;;
            *)
                return 1
                ;;
        esac
        apply_config
        return 0
    fi
    
    return 1
}

# Function to list all configuration
list_config() {
    echo "Current configuration:"
    echo "  cache_ttl= ${CONFIG_cache_ttl:-}"
    echo "  clipboard_command= ${CONFIG_clipboard_command:-}"
    echo "  color_output= ${CONFIG_color_output:-}"
    echo "  debug= ${CONFIG_debug:-}"
    echo "  log_level= ${CONFIG_log_level:-}"
    echo "  max_input_length= ${CONFIG_max_input_length:-}"
    echo "  output_mode= ${CONFIG_output_mode:-}"
    echo "  prefill_shell= ${CONFIG_prefill_shell:-}"
    echo "  safe_mode= ${CONFIG_safe_mode:-}"
    echo "  timeout= ${CONFIG_timeout:-}"
    echo "  rate_limit= ${CONFIG_rate_limit:-}"
    echo "  burst_limit= ${CONFIG_burst_limit:-}"
}

# Function to export configuration
export_config() {
    local output_file="$1"
    
    {
        echo "# makecmd configuration export"
        echo "# Generated on $(date)"
        echo ""
        echo "cache_ttl = ${CONFIG_cache_ttl:-}"
        echo "clipboard_command = ${CONFIG_clipboard_command:-}"
        echo "color_output = ${CONFIG_color_output:-}"
        echo "debug = ${CONFIG_debug:-}"
        echo "log_level = ${CONFIG_log_level:-}"
        echo "max_input_length = ${CONFIG_max_input_length:-}"
        echo "output_mode = ${CONFIG_output_mode:-}"
        echo "prefill_shell = ${CONFIG_prefill_shell:-}"
        echo "safe_mode = ${CONFIG_safe_mode:-}"
        echo "timeout = ${CONFIG_timeout:-}"
        echo "rate_limit = ${CONFIG_rate_limit:-}"
        echo "burst_limit = ${CONFIG_burst_limit:-}"
    } > "$output_file"
    
    chmod 600 "$output_file"
}

# Function to merge configuration files
merge_config() {
    local primary_config="$1"
    local secondary_config="$2"
    
    # Load primary config first
    if [[ -f "$primary_config" ]]; then
        load_config "$primary_config"
    fi
    
    # Override with secondary config
    if [[ -f "$secondary_config" ]]; then
        load_config "$secondary_config"
    fi
}

# Function to check for config updates
check_config_updates() {
    local config_file="$1"
    local last_modified_file="${HOME}/.makecmd/.config_last_modified"
    
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    local current_mtime=$(stat -f%m "$config_file" 2>/dev/null || stat -c%Y "$config_file" 2>/dev/null)
    
    if [[ -f "$last_modified_file" ]]; then
        local last_mtime=$(cat "$last_modified_file")
        if [[ "$current_mtime" != "$last_mtime" ]]; then
            log "INFO" "Config file has been updated"
            echo "$current_mtime" > "$last_modified_file"
            return 1
        fi
    else
        mkdir -p "$(dirname "$last_modified_file")"
        echo "$current_mtime" > "$last_modified_file"
    fi
    
    return 0
}