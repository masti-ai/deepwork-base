#!/bin/bash
#===============================================================================
# bead-counter.sh - Scalar Agent for Counting Open Beads
#===============================================================================
# Purpose: Counts open beads per rig and outputs a JSON summary.
#          Designed to run via cron every hour for monitoring bead workload.
#
# Usage: ./bead-counter.sh [--help]
#
# Output: JSON to stdout with the following structure:
#   {
#     "timestamp": "2026-03-10T12:00:00Z",
#     "total_open": 42,
#     "by_rig": {
#       "ai-planogram": 15,
#       "alc-ai-villa": 10,
#       ...
#     },
#     "by_priority": {
#       "urgent": 2,
#       "high": 10,
#       "normal": 25,
#       "low": 5
#     }
#   }
#
# Dependencies: bash, find, jq (optional - falls back to manual JSON)
#
# Author: deepwork-eng-2 (Kimi K2)
# Bead: hq-u539p
#===============================================================================

set -euo pipefail

# Help message
if [[ "${1:-}" == "--help" ]]; then
    sed -n '/^#/,/^#$/p' "$0" | sed 's/^# //; s/^#//'
    exit 0
fi

# Configuration
BEADS_DIR="${BEADS_DIR:-/workspace/gt/.beads}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize counters
declare -A rig_counts
declare -A priority_counts
total_open=0

# Priority mapping (extract from bead files)
get_priority() {
    local bead_file="$1"
    # Try to extract priority from bead metadata
    if [[ -f "$bead_file" ]]; then
        # Check for priority in common locations
        grep -i "priority" "$bead_file" 2>/dev/null | head -1 | sed 's/.*://; s/[^a-zA-Z]//g' | tr '[:upper:]' '[:lower:]' || echo "normal"
    else
        echo "normal"
    fi
}

# Count beads per rig
if [[ -d "$BEADS_DIR" ]]; then
    # Find all bead files (typically .yaml, .yml, .json, or no extension)
    while IFS= read -r -d '' bead_file; do
        # Extract rig from path or filename
        rig=$(basename "$(dirname "$bead_file")" 2>/dev/null || echo "unknown")
        
        # Skip backup and temp files
        if [[ "$rig" == "backup" ]] || [[ "$rig" == .dolt* ]] || [[ "$rig" == .git* ]]; then
            continue
        fi
        
        # Increment counters
        ((total_open++)) || true
        ((rig_counts[$rig]++)) || true
        
        # Try to determine priority
        priority=$(get_priority "$bead_file")
        case "$priority" in
            urgent|p0) ((priority_counts[urgent]++)) || true ;;
            high|p1) ((priority_counts[high]++)) || true ;;
            low|p3) ((priority_counts[low]++)) || true ;;
            *) ((priority_counts[normal]++)) || true ;;
        esac
        
    done < <(find "$BEADS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "bead*" \) -print0 2>/dev/null || true)
fi

# Also check /workspace/gt/beads directory
if [[ -d "/workspace/gt/beads" ]]; then
    while IFS= read -r -d '' bead_file; do
        rig=$(basename "$(dirname "$bead_file")" 2>/dev/null || echo "unknown")
        ((total_open++)) || true
        ((rig_counts[$rig]++)) || true
        priority=$(get_priority "$bead_file")
        case "$priority" in
            urgent|p0) ((priority_counts[urgent]++)) || true ;;
            high|p1) ((priority_counts[high]++)) || true ;;
            low|p3) ((priority_counts[low]++)) || true ;;
            *) ((priority_counts[normal]++)) || true ;;
        esac
    done < <(find /workspace/gt/beads -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) -print0 2>/dev/null || true)
fi

# Build JSON output
if command -v jq &>/dev/null; then
    # Use jq for proper JSON formatting
    jq -n \
        --arg timestamp "$TIMESTAMP" \
        --argjson total "${total_open:-0}" \
        '{
            timestamp: $timestamp,
            total_open: $total,
            by_rig: {},
            by_priority: {
                urgent: 0,
                high: 0,
                normal: 0,
                low: 0
            }
        }' | jq --argjson rigs "$(for key in "${!rig_counts[@]}"; do echo "{\"$key\": ${rig_counts[$key]}}"; done | jq -s 'add // {}')" '.by_rig = $rigs' | jq --argjson priorities "$(for key in "${!priority_counts[@]}"; do echo "{\"$key\": ${priority_counts[$key]}}"; done | jq -s 'add // {}')" '.by_priority = $priorities'
else
    # Manual JSON construction (fallback)
    echo "{"
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"total_open\": $total_open,"
    
    # Build by_rig object
    echo "  \"by_rig\": {"
    first=true
    for rig in "${!rig_counts[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        printf '    "%s": %d' "$rig" "${rig_counts[$rig]}"
    done
    echo ""
    echo "  },"
    
    # Build by_priority object
    echo "  \"by_priority\": {"
    printf '    "urgent": %d,\n' "${priority_counts[urgent]:-0}"
    printf '    "high": %d,\n' "${priority_counts[high]:-0}"
    printf '    "normal": %d,\n' "${priority_counts[normal]:-0}"
    printf '    "low": %d\n' "${priority_counts[low]:-0}"
    echo "  }"
    echo "}"
fi
