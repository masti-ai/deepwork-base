#!/bin/bash
#===============================================================================
# pr-status.sh - Scalar Agent for PR Status Monitoring
#===============================================================================
# Purpose: Checks all Gitea repos for open PRs and outputs a markdown table.
#          Can be used for dashboards, notifications, or reports.
#
# Usage: ./pr-status.sh [--help] [--json]
#
# Output formats:
#   Default: Markdown table to stdout
#   --json:  JSON array to stdout
#
# Environment variables:
#   GITEA_URL    - Gitea API base URL (default: http://localhost:3300/api/v1)
#   GITEA_TOKEN  - Gitea API token (optional)
#   GITEA_USER   - Gitea username for basic auth (optional)
#   GITEA_PASS   - Gitea password for basic auth (optional)
#
# Dependencies: bash, curl, jq (optional for JSON output)
#
# Author: deepwork-eng-2 (Kimi K2)
# Bead: hq-u539p
#===============================================================================

set -euo pipefail

# Configuration
GITEA_URL="${GITEA_URL:-http://localhost:3300/api/v1}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
GITEA_USER="${GITEA_USER:-}"
GITEA_PASS="${GITEA_PASS:-}"
OUTPUT_JSON=false

# Help message
if [[ "${1:-}" == "--help" ]]; then
    sed -n '/^#/,/^#$/p' "$0" | sed 's/^# //; s/^#//'
    exit 0
fi

# Parse arguments
if [[ "${1:-}" == "--json" ]]; then
    OUTPUT_JSON=true
fi

# Build curl auth options
build_auth() {
    if [[ -n "$GITEA_TOKEN" ]]; then
        echo "-H Authorization: token $GITEA_TOKEN"
    elif [[ -n "$GITEA_USER" && -n "$GITEA_PASS" ]]; then
        echo "-u $GITEA_USER:$GITEA_PASS"
    else
        echo ""
    fi
}

AUTH=$(build_auth)

# Fetch organizations (or use known org)
fetch_orgs() {
    local url="$GITEA_URL/orgs"
    if [[ -n "$AUTH" ]]; then
        curl -s $AUTH "$url" 2>/dev/null || echo "[]"
    else
        curl -s "$url" 2>/dev/null || echo "[]"
    fi
}

# Fetch repos for an org
fetch_repos() {
    local org="$1"
    local url="$GITEA_URL/orgs/$org/repos"
    if [[ -n "$AUTH" ]]; then
        curl -s $AUTH "$url" 2>/dev/null || echo "[]"
    else
        curl -s "$url" 2>/dev/null || echo "[]"
    fi
}

# Fetch open PRs for a repo
fetch_prs() {
    local owner="$1"
    local repo="$2"
    local url="$GITEA_URL/repos/$owner/$repo/pulls?state=open&limit=100"
    if [[ -n "$AUTH" ]]; then
        curl -s $AUTH "$url" 2>/dev/null || echo "[]"
    else
        curl -s "$url" 2>/dev/null || echo "[]"
    fi
}

# Main execution
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Array to store PR data
declare -a pr_list=()

# Known organizations to check
orgs=("Deepwork-AI")

for org in "${orgs[@]}"; do
    # Get repos for this org
    repos_json=$(fetch_repos "$org")
    
    # Parse repo names
    if command -v jq &>/dev/null; then
        repo_names=$(echo "$repos_json" | jq -r '.[].name' 2>/dev/null || true)
    else
        # Manual parsing fallback
        repo_names=$(echo "$repos_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//; s/"$//' || true)
    fi
    
    for repo in $repo_names; do
        # Skip empty lines
        [[ -z "$repo" ]] && continue
        
        # Fetch PRs for this repo
        prs_json=$(fetch_prs "$org" "$repo")
        
        if command -v jq &>/dev/null; then
            # Parse with jq
            while IFS= read -r pr; do
                [[ -z "$pr" ]] && continue
                
                number=$(echo "$pr" | jq -r '.number')
                title=$(echo "$pr" | jq -r '.title' | head -c 50)
                author=$(echo "$pr" | jq -r '.user.login')
                head_branch=$(echo "$pr" | jq -r '.head.label')
                created_at=$(echo "$pr" | jq -r '.created_at' | cut -d'T' -f1)
                
                pr_list+=("$org|$repo|$number|$title|$author|$head_branch|$created_at")
            done < <(echo "$prs_json" | jq -c '.[]' 2>/dev/null || true)
        else
            # Manual parsing (simplified)
            # Extract PR numbers and iterate
            pr_numbers=$(echo "$prs_json" | grep -o '"number":[0-9]*' | sed 's/"number"://' || true)
            
            for pr_num in $pr_numbers; do
                # Extract PR details (simplified extraction)
                pr_data=$(echo "$prs_json" | grep -A 20 "\"number\":$pr_num" | head -20)
                title=$(echo "$pr_data" | grep '"title":' | head -1 | sed 's/.*"title":"//; s/".*//' | head -c 50 || echo "N/A")
                author=$(echo "$pr_data" | grep '"login":' | head -1 | sed 's/.*"login":"//; s/".*//' || echo "N/A")
                head_branch=$(echo "$pr_data" | grep '"head":' -A 5 | grep '"label":' | head -1 | sed 's/.*"label":"//; s/".*//' || echo "N/A")
                created_at=$(echo "$pr_data" | grep '"created_at":' | head -1 | sed 's/.*"created_at":"//; s/T.*//' || echo "N/A")
                
                pr_list+=("$org|$repo|$pr_num|$title|$author|$head_branch|$created_at")
            done
        fi
    done
done

# Output results
if [[ "$OUTPUT_JSON" == "true" ]]; then
    # JSON output
    if command -v jq &>/dev/null; then
        # Build JSON array
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"total_open_prs\": ${#pr_list[@]},"
        echo "  \"pull_requests\": ["
        
        first=true
        for pr in "${pr_list[@]}"; do
            IFS='|' read -r org repo number title author branch created <<< "$pr"
            
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            
            printf '    {"org": "%s", "repo": "%s", "number": %s, "title": "%s", "author": "%s", "branch": "%s", "created": "%s"}' \
                "$org" "$repo" "$number" "$title" "$author" "$branch" "$created"
        done
        
        echo ""
        echo "  ]"
        echo "}"
    else
        # Simple JSON without jq
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"total_open_prs\": ${#pr_list[@]},"
        echo "  \"pull_requests\": ["
        
        first=true
        for pr in "${pr_list[@]}"; do
            IFS='|' read -r org repo number title author branch created <<< "$pr"
            
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            
            # Escape quotes in title
            title_escaped=$(echo "$title" | sed 's/"/\\"/g')
            printf '    {\"org\": \"%s\", \"repo\": \"%s\", \"number\": %s, \"title\": \"%s\", \"author\": \"%s\", \"branch\": \"%s\", \"created\": \"%s\"}' \
                "$org" "$repo" "$number" "$title_escaped" "$author" "$branch" "$created"
        done
        
        echo ""
        echo "  ]"
        echo "}"
    fi
else
    # Markdown table output
    echo "# Open Pull Requests Report"
    echo ""
    echo "Generated: $TIMESTAMP"
    echo ""
    echo "| Repository | PR # | Title | Author | Branch | Created |"
    echo "|------------|------|-------|--------|--------|---------|"
    
    for pr in "${pr_list[@]}"; do
        IFS='|' read -r org repo number title author branch created <<< "$pr"
        
        # Truncate long titles
        if [[ ${#title} -ge 47 ]]; then
            title="${title:0:47}..."
        fi
        
        # Escape pipe characters in title
        title=$(echo "$title" | sed 's/|/\\|/g')
        
        echo "| $org/$repo | #$number | $title | @$author | \`$branch\` | $created |"
    done
    
    echo ""
    echo "**Total Open PRs: ${#pr_list[@]}**"
fi
