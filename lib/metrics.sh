#!/usr/bin/env bash
#
# metrics.sh - Performance monitoring and metrics collection for makecmd
#
# This module provides performance tracking and metrics reporting

# Metrics storage
readonly METRICS_DIR="${HOME}/.makecmd/metrics"
readonly METRICS_FILE="${METRICS_DIR}/metrics.json"
readonly METRICS_RETENTION_DAYS=30

# Performance timers
declare -A PERF_TIMERS
declare -A PERF_COUNTERS

# Initialize metrics
init_metrics() {
    mkdir -p "$METRICS_DIR"
    
    # Initialize daily metrics file
    local date_stamp=$(date +%Y%m%d)
    METRICS_FILE="${METRICS_DIR}/metrics_${date_stamp}.json"
    
    # Clean old metrics
    cleanup_old_metrics
}

# Start performance timer
start_timer() {
    local timer_name="$1"
    PERF_TIMERS["$timer_name"]=$(date +%s%N)
}

# Stop timer and record metric
stop_timer() {
    local timer_name="$1"
    local metadata="${2:-{}}"
    
    if [[ -z "${PERF_TIMERS[$timer_name]}" ]]; then
        log "WARN" "Timer $timer_name was not started"
        return 1
    fi
    
    local start_time=${PERF_TIMERS[$timer_name]}
    local end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    # Record metric
    record_performance_metric "$timer_name" "$duration_ms" "$metadata"
    
    # Clean up timer
    unset PERF_TIMERS["$timer_name"]
    
    echo "$duration_ms"
}

# Record performance metric
record_performance_metric() {
    local operation="$1"
    local duration_ms="$2"
    local metadata="${3:-{}}"
    local timestamp=$(get_iso_date)
    
    local metric=$(cat << EOF
{
  "timestamp": "$timestamp",
  "type": "performance",
  "operation": "$operation",
  "duration_ms": $duration_ms,
  "metadata": $metadata
}
EOF
)
    
    echo "$metric" >> "$METRICS_FILE"
}

# Increment counter
increment_counter() {
    local counter_name="$1"
    local increment="${2:-1}"
    
    PERF_COUNTERS["$counter_name"]=$((${PERF_COUNTERS["$counter_name"]:-0} + increment))
}

# Record counter metric
record_counter_metric() {
    local counter_name="$1"
    local value="${2:-${PERF_COUNTERS[$counter_name]:-0}}"
    local metadata="${3:-{}}"
    local timestamp=$(get_iso_date)
    
    local metric=$(cat << EOF
{
  "timestamp": "$timestamp",
  "type": "counter",
  "name": "$counter_name",
  "value": $value,
  "metadata": $metadata
}
EOF
)
    
    echo "$metric" >> "$METRICS_FILE"
}

# Record custom metric
record_metric() {
    local metric_type="$1"
    local metric_name="$2"
    local metric_value="$3"
    local metadata="${4:-{}}"
    local timestamp=$(get_iso_date)
    
    local metric=$(cat << EOF
{
  "timestamp": "$timestamp",
  "type": "$metric_type",
  "name": "$metric_name",
  "value": "$metric_value",
  "metadata": $metadata
}
EOF
)
    
    echo "$metric" >> "$METRICS_FILE"
}

# Get metrics summary
get_metrics_summary() {
    local period="${1:-today}"  # today, week, month
    local metric_type="${2:-all}"  # all, performance, counter, etc.
    
    local files=()
    
    case "$period" in
        today)
            files=("${METRICS_DIR}/metrics_$(date +%Y%m%d).json")
            ;;
        week)
            for i in {0..6}; do
                local date=$(date -d "-$i days" +%Y%m%d 2>/dev/null || date -v-${i}d +%Y%m%d)
                files+=("${METRICS_DIR}/metrics_${date}.json")
            done
            ;;
        month)
            for i in {0..29}; do
                local date=$(date -d "-$i days" +%Y%m%d 2>/dev/null || date -v-${i}d +%Y%m%d)
                files+=("${METRICS_DIR}/metrics_${date}.json")
            done
            ;;
    esac
    
    # Aggregate metrics
    local total_operations=0
    local total_duration=0
    local error_count=0
    local cache_hits=0
    local cache_misses=0
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if command -v jq > /dev/null 2>&1; then
                # Use jq for parsing if available
                total_operations=$((total_operations + $(jq -r 'select(.type=="performance") | 1' "$file" 2>/dev/null | wc -l)))
                total_duration=$((total_duration + $(jq -r 'select(.type=="performance") | .duration_ms' "$file" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')))
                error_count=$((error_count + $(jq -r 'select(.type=="counter" and .name=="errors") | .value' "$file" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')))
                cache_hits=$((cache_hits + $(jq -r 'select(.type=="counter" and .name=="cache_hits") | .value' "$file" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')))
                cache_misses=$((cache_misses + $(jq -r 'select(.type=="counter" and .name=="cache_misses") | .value' "$file" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')))
            else
                # Fallback to grep/awk
                total_operations=$((total_operations + $(grep '"type": "performance"' "$file" 2>/dev/null | wc -l)))
            fi
        fi
    done
    
    # Calculate averages
    local avg_duration=0
    if [[ $total_operations -gt 0 ]]; then
        avg_duration=$((total_duration / total_operations))
    fi
    
    local cache_rate=0
    local total_cache=$((cache_hits + cache_misses))
    if [[ $total_cache -gt 0 ]]; then
        cache_rate=$((cache_hits * 100 / total_cache))
    fi
    
    # Output summary
    cat << EOF
Metrics Summary ($period)
========================
Total Operations: $total_operations
Average Duration: ${avg_duration}ms
Error Count: $error_count
Cache Hit Rate: ${cache_rate}%
Cache Hits: $cache_hits
Cache Misses: $cache_misses

Top Operations by Count:
$(get_top_operations "${files[@]}")

Slowest Operations:
$(get_slowest_operations "${files[@]}")
EOF
}

# Get top operations by count
get_top_operations() {
    local files=("$@")
    
    if command -v jq > /dev/null 2>&1; then
        cat "${files[@]}" 2>/dev/null | \
            jq -r 'select(.type=="performance") | .operation' | \
            sort | uniq -c | sort -rn | head -5
    else
        echo "jq required for detailed analysis"
    fi
}

# Get slowest operations
get_slowest_operations() {
    local files=("$@")
    
    if command -v jq > /dev/null 2>&1; then
        cat "${files[@]}" 2>/dev/null | \
            jq -r 'select(.type=="performance") | "\(.duration_ms)ms \(.operation)"' | \
            sort -rn | head -5
    else
        echo "jq required for detailed analysis"
    fi
}

# Export metrics
export_metrics() {
    local output_file="$1"
    local format="${2:-json}"  # json, csv, prometheus
    
    case "$format" in
        json)
            cat "${METRICS_DIR}"/metrics_*.json > "$output_file" 2>/dev/null
            ;;
        csv)
            export_metrics_csv "$output_file"
            ;;
        prometheus)
            export_metrics_prometheus "$output_file"
            ;;
        *)
            log "ERROR" "Unknown export format: $format"
            return 1
            ;;
    esac
}

# Export metrics as CSV
export_metrics_csv() {
    local output_file="$1"
    
    echo "timestamp,type,name,value,operation,duration_ms" > "$output_file"
    
    if command -v jq > /dev/null 2>&1; then
        cat "${METRICS_DIR}"/metrics_*.json 2>/dev/null | \
            jq -r '"\(.timestamp),\(.type),\(.name // ""),\(.value // ""),\(.operation // ""),\(.duration_ms // "")"' \
            >> "$output_file"
    fi
}

# Export metrics in Prometheus format
export_metrics_prometheus() {
    local output_file="$1"
    local timestamp=$(date +%s)000
    
    {
        echo "# HELP makecmd_operations_total Total number of operations"
        echo "# TYPE makecmd_operations_total counter"
        echo "makecmd_operations_total $(get_total_operations) $timestamp"
        
        echo "# HELP makecmd_errors_total Total number of errors"
        echo "# TYPE makecmd_errors_total counter"
        echo "makecmd_errors_total $(get_total_errors) $timestamp"
        
        echo "# HELP makecmd_duration_seconds Operation duration in seconds"
        echo "# TYPE makecmd_duration_seconds histogram"
        
        if command -v jq > /dev/null 2>&1; then
            cat "${METRICS_DIR}"/metrics_*.json 2>/dev/null | \
                jq -r 'select(.type=="performance") | "makecmd_duration_seconds{operation=\"\(.operation)\"} \(.duration_ms/1000)"'
        fi
    } > "$output_file"
}

# Get total operations count
get_total_operations() {
    cat "${METRICS_DIR}"/metrics_*.json 2>/dev/null | \
        grep '"type": "performance"' | wc -l
}

# Get total errors count
get_total_errors() {
    if command -v jq > /dev/null 2>&1; then
        cat "${METRICS_DIR}"/metrics_*.json 2>/dev/null | \
            jq -r 'select(.type=="counter" and .name=="errors") | .value' | \
            awk '{sum+=$1} END {print sum+0}'
    else
        echo "0"
    fi
}

# Clean up old metrics
cleanup_old_metrics() {
    find "$METRICS_DIR" -name "metrics_*.json" -mtime +$METRICS_RETENTION_DAYS -delete 2>/dev/null || true
}

# Real-time metrics monitoring
monitor_metrics() {
    local refresh_interval="${1:-5}"
    
    while true; do
        clear
        echo "makecmd Metrics Monitor - $(date)"
        echo "================================"
        get_metrics_summary "today"
        echo
        echo "Press Ctrl+C to exit"
        sleep "$refresh_interval"
    done
}

# Health check based on metrics
health_check() {
    local threshold_error_rate="${1:-10}"  # Max error rate percentage
    local threshold_avg_duration="${2:-5000}"  # Max avg duration in ms
    
    local summary=$(get_metrics_summary "today")
    
    # Extract values
    local total_ops=$(echo "$summary" | grep "Total Operations:" | awk '{print $3}')
    local error_count=$(echo "$summary" | grep "Error Count:" | awk '{print $3}')
    local avg_duration=$(echo "$summary" | grep "Average Duration:" | awk '{print $3}' | tr -d 'ms')
    
    local health_status="healthy"
    local health_issues=()
    
    # Check error rate
    if [[ $total_ops -gt 0 ]]; then
        local error_rate=$((error_count * 100 / total_ops))
        if [[ $error_rate -gt $threshold_error_rate ]]; then
            health_status="unhealthy"
            health_issues+=("High error rate: ${error_rate}%")
        fi
    fi
    
    # Check average duration
    if [[ $avg_duration -gt $threshold_avg_duration ]]; then
        health_status="degraded"
        health_issues+=("Slow performance: ${avg_duration}ms average")
    fi
    
    # Output health status
    cat << EOF
{
  "status": "$health_status",
  "timestamp": "$(get_iso_date)",
  "metrics": {
    "total_operations": $total_ops,
    "error_count": $error_count,
    "average_duration_ms": $avg_duration
  },
  "issues": [$(printf '"%s",' "${health_issues[@]}" | sed 's/,$//')] 
}
EOF
}