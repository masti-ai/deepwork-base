#!/bin/bash
#===============================================================================
# health-check.sh - Scalar Agent for Service Health Monitoring
#===============================================================================
# Purpose: Pings all services on specified ports and outputs status JSON.
#          Designed for monitoring dashboard integration and alerting.
#
# Usage: ./health-check.sh [--help] [--timeout SECONDS]
#
# Services checked:
#   - Port 3000:  Planogram Dashboard (Next.js)
#   - Port 3100:  Command Center Dashboard
#   - Port 3200:  (reserved for future use)
#   - Port 3300:  Gitea Git Server
#   - Port 4000:  LiteLLM API Proxy
#   - Port 8003:  Planogram API (FastAPI)
#   - Port 8006:  ALC AI API (FastAPI)
#
# Output JSON structure:
#   {
#     "timestamp": "2026-03-10T12:00:00Z",
#     "overall_status": "healthy|degraded|critical",
#     "checks": [
#       {
#         "name": "gitea",
#         "host": "localhost",
#         "port": 3300,
#         "status": "up",
#         "response_ms": 45,
#         "error": null
#       }
#     ],
#     "summary": {
#       "total": 7,
#       "up": 7,
#       "down": 0,
#       "degraded": 0
#     }
#   }
#
# Dependencies: bash, nc (netcat) or /dev/tcp for port checking
#
# Author: deepwork-eng-2 (Kimi K2)
# Bead: hq-u539p
#===============================================================================

set -euo pipefail

# Configuration
TIMEOUT="${TIMEOUT:-5}"
HOST="${HEALTH_CHECK_HOST:-localhost}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Service definitions: "name|port|description|health_endpoint"
declare -a SERVICES=(
    "planogram-dashboard|3000|Planogram Dashboard (Next.js)|/"
    "command-center|3100|Command Center Dashboard|/"
    "gitea|3300|Gitea Git Server|/api/v1/version"
    "litellm|4000|LiteLLM API Proxy|/"
    "planogram-api|8003|Planogram API (FastAPI)|/health"
    "alc-ai-api|8006|ALC AI API (FastAPI)|/health"
)

# Help message
if [[ "${1:-}" == "--help" ]]; then
    sed -n '/^#/,/^#$/p' "$0" | sed 's/^# //; s/^#//'
    exit 0
fi

# Parse timeout argument
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Check if a port is open using /dev/tcp (no external dependencies)
check_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    # Use /dev/tcp for pure bash solution
    if timeout "$timeout" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
        echo "up"
    else
        echo "down"
    fi
}

# Check service with timing
check_service() {
    local name="$1"
    local port="$2"
    local description="$3"
    local endpoint="$4"
    
    local start_time end_time duration_ms
    local status error_msg
    
    start_time=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    
    # Check if port is open
    port_status=$(check_port "$HOST" "$port" "$TIMEOUT")
    
    end_time=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    
    # Calculate duration in milliseconds
    if [[ ${#start_time} -gt 10 ]]; then
        # Nanoseconds available
        duration_ms=$(( (end_time - start_time) / 1000000 ))
    else
        # Fallback to seconds
        duration_ms=$(( (end_time - start_time) * 1000 ))
    fi
    
    if [[ "$port_status" == "up" ]]; then
        status="up"
        error_msg="null"
    else
        status="down"
        error_msg="\"Connection refused or timeout (${TIMEOUT}s)\""
        duration_ms=0
    fi
    
    echo "{\"name\": \"$name\", \"port\": $port, \"description\": \"$description\", \"status\": \"$status\", \"response_ms\": $duration_ms, \"error\": $error_msg}"
}

# Run checks in parallel (background processes)
declare -a check_results=()

for service_def in "${SERVICES[@]}"; do
    IFS='|' read -r name port description endpoint <<< "$service_def"
    
    # Run check and store result
    result=$(check_service "$name" "$port" "$description" "$endpoint")
    check_results+=("$result")
done

# Count results
up_count=0
down_count=0

for result in "${check_results[@]}"; do
    if [[ "$result" == *'"status": "up"'* ]]; then
        ((up_count++)) || true
    else
        ((down_count++)) || true
    fi
done

total_count=${#check_results[@]}

# Determine overall status
if [[ $down_count -eq 0 ]]; then
    overall_status="healthy"
elif [[ $down_count -lt $((total_count / 2)) ]]; then
    overall_status="degraded"
else
    overall_status="critical"
fi

# Output JSON
if command -v jq &>/dev/null; then
    # Use jq for pretty formatting
    {
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"overall_status\": \"$overall_status\","
        echo "  \"checks\": ["
        
        first=true
        for result in "${check_results[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    $result"
        done
        
        echo ""
        echo "  ],"
        echo "  \"summary\": {"
        echo "    \"total\": $total_count,"
        echo "    \"up\": $up_count,"
        echo "    \"down\": $down_count,"
        echo "    \"degraded\": 0"
        echo "  }"
        echo "}"
    } | jq .
else
    # Manual JSON output
    echo "{"
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"overall_status\": \"$overall_status\","
    echo "  \"checks\": ["
    
    first=true
    for result in "${check_results[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "    $result"
    done
    
    echo ""
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"total\": $total_count,"
    echo "    \"up\": $up_count,"
    echo "    \"down\": $down_count,"
    echo "    \"degraded\": 0"
    echo "  }"
    echo "}"
fi
