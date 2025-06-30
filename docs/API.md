# makecmd Library API Documentation

## Overview

The makecmd library consists of modular bash scripts that provide security, caching, configuration, and utility functions. All modules require Bash 3.2 or higher.

## Core Modules

### platform.sh - Platform Compatibility Layer

Provides cross-platform compatibility functions for macOS, Linux, and Windows (WSL).

#### Functions

##### `detect_platform()`
Returns the current platform identifier.
- **Returns**: `macos`, `linux`, `windows`, `freebsd`, or `unknown`
- **Example**: `PLATFORM=$(detect_platform)`

##### `get_file_mtime(file)`
Get file modification time (cross-platform).
- **Parameters**: 
  - `file`: Path to file
- **Returns**: Modification time in seconds since epoch
- **Example**: `mtime=$(get_file_mtime "/path/to/file")`

##### `calculate_sha256(input)`
Calculate SHA256 hash using available commands.
- **Parameters**:
  - `input`: String to hash
- **Returns**: SHA256 hash hex string
- **Example**: `hash=$(calculate_sha256 "my data")`

##### `run_with_timeout(timeout_secs, command)`
Run command with timeout (cross-platform).
- **Parameters**:
  - `timeout_secs`: Timeout in seconds
  - `command`: Command to execute
- **Returns**: Command exit code or 124 on timeout
- **Example**: `run_with_timeout 30 "long_running_command"`

### sanitizer.sh - Input/Output Sanitization

Provides comprehensive sanitization for security.

#### Functions

##### `sanitize_input(input)`
Sanitize user input by escaping shell metacharacters.
- **Parameters**:
  - `input`: Raw user input
- **Returns**: Sanitized input safe for processing
- **Validation**: Use `sanitize_input_validated()` for input validation
- **Example**: `clean=$(sanitize_input "$user_input")`

##### `sanitize_claude_output(output)`
Sanitize Claude's output to prevent command injection.
- **Parameters**:
  - `output`: Raw Claude output
- **Returns**: Single-line sanitized command
- **Example**: `command=$(sanitize_claude_output "$claude_response")`

##### `sanitize_path(path)`
Sanitize file paths and resolve symlinks.
- **Parameters**:
  - `path`: File path to sanitize
- **Returns**: Sanitized path or empty on security violation
- **Validation**: Use `sanitize_path_validated()` for validation
- **Example**: `safe_path=$(sanitize_path "$user_path")`

### validator.sh - Command Validation

Validates commands for safety and security.

#### Functions

##### `validate_command(command, safe_mode)`
Validate command for dangerous patterns.
- **Parameters**:
  - `command`: Command to validate
  - `safe_mode`: Boolean - restrict to read-only operations
- **Returns**: 0 if valid, 1 if dangerous
- **Example**: `validate_command "$cmd" "true" || exit`

##### `get_command_risk_level(command)`
Assess risk level of command.
- **Parameters**:
  - `command`: Command to assess
- **Returns**: `high`, `medium`, or `low`
- **Example**: `risk=$(get_command_risk_level "$cmd")`

##### `generate_safety_warning(command)`
Generate appropriate safety warning.
- **Parameters**:
  - `command`: Command to warn about
- **Returns**: Formatted warning message
- **Example**: `echo "$(generate_safety_warning "$cmd")"`

### cache.sh - Caching System

Provides secure caching with TTL and locking.

#### Functions

##### `generate_cache_key(input)`
Generate cache key from input.
- **Parameters**:
  - `input`: Input string
- **Returns**: SHA256 hash key
- **Example**: `key=$(generate_cache_key "$query")`

##### `cache_command(cache_key, command, ttl)`
Cache a command with TTL.
- **Parameters**:
  - `cache_key`: Cache key from generate_cache_key
  - `command`: Command to cache
  - `ttl`: Time-to-live in seconds (default: 3600)
- **Validation**: Use `cache_command_validated()` for validation
- **Example**: `cache_command "$key" "$cmd" 3600`

##### `get_cached_command(cache_key)`
Retrieve cached command if valid.
- **Parameters**:
  - `cache_key`: Cache key
- **Returns**: Cached command or empty if not found/expired
- **Example**: `cmd=$(get_cached_command "$key")`

### config.sh - Configuration Management

Handles configuration file loading and management.

#### Functions

##### `load_config(config_file)`
Load configuration from file.
- **Parameters**:
  - `config_file`: Path to config file
- **Validation**: Use `load_config_validated()` for validation
- **Example**: `load_config "$HOME/.makecmdrc"`

##### `set_config(key, value)`
Set configuration value at runtime.
- **Parameters**:
  - `key`: Configuration key
  - `value`: Configuration value
- **Validation**: Use `set_config_validated()` for validation
- **Returns**: 0 on success, 1 on validation failure
- **Example**: `set_config "debug" "true"`

##### `get_config(key)`
Get configuration value.
- **Parameters**:
  - `key`: Configuration key
- **Returns**: Configuration value or empty
- **Example**: `debug_mode=$(get_config "debug")`

### logger.sh - Structured Logging

Provides structured logging with rotation.

#### Functions

##### `log(level, message)`
Log a message (backward compatible).
- **Parameters**:
  - `level`: `DEBUG`, `INFO`, `WARN`, or `ERROR`
  - `message`: Log message
- **Example**: `log "INFO" "Operation completed"`

##### `log_with_context(level, message, key1, value1, ...)`
Log with structured context.
- **Parameters**:
  - `level`: Log level
  - `message`: Log message
  - `key/value pairs`: Context data
- **Example**: `log_with_context "INFO" "User action" "user" "$USER" "action" "generate"`

##### `set_log_level(level)`
Set minimum log level.
- **Parameters**:
  - `level`: `DEBUG`, `INFO`, `WARN`, or `ERROR`
- **Example**: `set_log_level "DEBUG"`

### metrics.sh - Performance Monitoring

Tracks performance metrics and health.

#### Functions

##### `start_timer(timer_name)`
Start a performance timer.
- **Parameters**:
  - `timer_name`: Unique timer identifier
- **Example**: `start_timer "api_call"`

##### `stop_timer(timer_name, metadata)`
Stop timer and record metric.
- **Parameters**:
  - `timer_name`: Timer identifier
  - `metadata`: Optional JSON metadata
- **Returns**: Duration in milliseconds
- **Example**: `duration=$(stop_timer "api_call" '{"endpoint":"claude"}')`

##### `increment_counter(counter_name, increment)`
Increment a counter metric.
- **Parameters**:
  - `counter_name`: Counter identifier
  - `increment`: Amount to increment (default: 1)
- **Example**: `increment_counter "cache_hits"`

##### `health_check(error_threshold, duration_threshold)`
Perform health check based on metrics.
- **Parameters**:
  - `error_threshold`: Max error rate percentage (default: 10)
  - `duration_threshold`: Max average duration in ms (default: 5000)
- **Returns**: JSON health status
- **Example**: `health_check 5 3000`

### error_handler.sh - Error Recovery

Provides error handling and recovery mechanisms.

#### Functions

##### `handle_recoverable_error(error_type, error_code, message, retry_func)`
Handle recoverable errors with retry logic.
- **Parameters**:
  - `error_type`: Error category
  - `error_code`: Exit code
  - `message`: Error message
  - `retry_func`: Function to retry (optional)
- **Returns**: 0 on recovery, error code on failure
- **Example**: `handle_recoverable_error "api_timeout" 4 "Timeout" "call_api"`

##### `handle_critical_error(error_code, message, fallback_action)`
Handle critical errors with fallback.
- **Parameters**:
  - `error_code`: Exit code
  - `message`: Error message
  - `fallback_action`: `use_cache`, `offline_mode`, or `basic_mode`
- **Returns**: Fallback exit code
- **Example**: `handle_critical_error 2 "API unavailable" "use_cache"`

### validation.sh - Input Validation

Provides comprehensive input validation.

#### Functions

##### `validate_string(name, value, required, max_length, pattern)`
Validate string parameter.
- **Parameters**:
  - `name`: Parameter name
  - `value`: Parameter value
  - `required`: `true` or `false`
  - `max_length`: Maximum length (0 = unlimited)
  - `pattern`: Optional regex pattern
- **Returns**: 0 if valid, error code otherwise
- **Example**: `validate_string "input" "$input" true 500 '^[a-zA-Z0-9 ]+$'`

##### `validate_integer(name, value, min, max)`
Validate integer parameter.
- **Parameters**:
  - `name`: Parameter name
  - `value`: Parameter value
  - `min`: Minimum value
  - `max`: Maximum value
- **Returns**: 0 if valid, error code otherwise
- **Example**: `validate_integer "timeout" "$timeout" 1 600`

##### `validate_file_path(name, path, must_exist, must_be_writable)`
Validate file path.
- **Parameters**:
  - `name`: Parameter name
  - `path`: File path
  - `must_exist`: `true` or `false`
  - `must_be_writable`: `true` or `false`
- **Returns**: 0 if valid, error code otherwise
- **Example**: `validate_file_path "config" "$file" true false`

## Error Codes

### Standard Error Codes
- `E_SUCCESS` (0): Success
- `E_INVALID_INPUT` (1): Invalid input provided
- `E_CLAUDE_ERROR` (2): Claude API error
- `E_DANGEROUS_COMMAND` (3): Dangerous command blocked
- `E_TIMEOUT` (4): Operation timeout
- `E_CONFIG_ERROR` (5): Configuration error
- `E_DEPENDENCY_ERROR` (6): Missing dependency

### Validation Error Codes
- `E_VALIDATION_FAILED` (100): General validation failure
- `E_INVALID_PARAMETER` (101): Invalid parameter value
- `E_MISSING_PARAMETER` (102): Required parameter missing
- `E_TYPE_MISMATCH` (103): Parameter type mismatch

### Fallback Error Codes
- `E_FALLBACK_CACHE` (50): Falling back to cache
- `E_FALLBACK_OFFLINE` (51): Falling back to offline mode
- `E_FALLBACK_BASIC` (52): Falling back to basic mode
- `E_CIRCUIT_BREAKER_OPEN` (53): Circuit breaker is open

## Usage Examples

### Basic Command Generation
```bash
# Load required libraries
source /usr/local/lib/makecmd/platform.sh
source /usr/local/lib/makecmd/sanitizer.sh
source /usr/local/lib/makecmd/validator.sh

# Process user input
input="list all python files"
clean_input=$(sanitize_input_validated "$input")
cache_key=$(generate_cache_key "$clean_input")

# Check cache first
if command=$(get_cached_command "$cache_key"); then
    echo "Using cached command: $command"
else
    # Generate new command
    command=$(call_claude "$clean_input")
    command=$(sanitize_claude_output "$command")
    
    # Validate and cache
    if validate_command "$command" "false"; then
        cache_command "$cache_key" "$command"
    fi
fi
```

### Error Handling Example
```bash
# Retry on timeout
function api_call() {
    timeout 30 claude <<< "$prompt"
}

if ! output=$(api_call); then
    handle_recoverable_error "api_timeout" $? "API timeout" "api_call"
fi
```

### Performance Tracking Example
```bash
# Track operation performance
start_timer "command_generation"

# Do work...
generate_command "$input"

duration=$(stop_timer "command_generation" '{"cached":"false"}')
echo "Operation took ${duration}ms"
```

## Best Practices

1. **Always validate inputs** - Use the validated wrapper functions
2. **Handle errors gracefully** - Use error_handler functions
3. **Track performance** - Use metrics for monitoring
4. **Log important events** - Use structured logging
5. **Check platform compatibility** - Use platform.sh functions
6. **Implement timeouts** - Prevent hanging operations
7. **Use caching wisely** - Balance freshness vs performance

## Thread Safety

Most functions are not thread-safe. Use file locking (via cache.sh locking functions) when accessing shared resources from multiple processes.

## Performance Considerations

- Cache operations use SHA256 hashing (fallback to OpenSSL)
- File operations are atomic where possible
- Exponential backoff prevents thundering herd
- Circuit breakers prevent cascade failures
- Log rotation prevents disk space issues

## Security Notes

- All paths are sanitized and symlinks resolved
- System directories are protected from access
- Shell metacharacters are escaped
- Commands are validated before execution
- Sensitive information is detected and logged