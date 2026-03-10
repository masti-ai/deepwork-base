#!/bin/bash
#===============================================================================
# commit-stats.sh - Scalar Agent for Commit Statistics
#===============================================================================
# Purpose: Counts commits per author per repo in last 24h from Gitea API.
#          Outputs JSON for dashboard integration.
#
# Usage: ./commit-stats.sh [--help] [--days N]
#
# Options:
#   --help      Show this help message
#   --days N    Look back N days (default: 1)
#   --json      Output JSON (default)
#   --table     Output ASCII table instead of JSON
#
# Output JSON structure:
#   {
#     "timestamp": "2026-03-10T12:00:00Z",
#     "period": {
#       "days": 1,
#       "since": "2026-03-09T12:00:00Z",
#       "until": "2026-03-10T12:00:00Z"
#     },
#     "stats": [
#       {
#         "repo": "ai-planogram",
#         "org": "Deepwork-AI",
#         "commits": [
#           {
#             "author": "deepwork-eng-1",
#             "count": 5,
#             "emails": ["eng1@deepwork.ai"]
#           }
#         ],
#         "total_commits": 5
#       }
#     ],
#     "summary": {
#       "total_repos_with_commits": 3,
#       "total_commits": 15,
#       "unique_authors": ["deepwork-eng-1", "deepwork-eng-2"]
#     }
#   }
#
# Environment variables:
#   GITEA_URL    - Gitea API base URL (default: http://localhost:3300/api/v1)
#   GITEA_TOKEN  - Gitea API token (optional)
#   GITEA_USER   - Gitea username for basic auth (optional)
#   GITEA_PASS   - Gitea password for basic auth (optional)
#
# Dependencies: bash, curl, jq (optional)
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
DAYS=1
OUTPUT_FORMAT="json"

# Help message
if [[ "${1:-}" == "--help" ]]; then
    sed -n '/^#/,/^#$/p' "$0" | sed 's/^# //; s/^#//'
    exit 0
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            DAYS="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --table)
            OUTPUT_FORMAT="table"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Calculate date range
SINCE=$(date -u -d "${DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-${DAYS}d +"%Y-%m-%dT%H:%M:%SZ")
UNTIL=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP="$UNTIL"

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

# Fetch commits for a repo within date range
fetch_commits() {
    local owner="$1"
    local repo="$2"
    local since="$3"
    local until="$4"
    
    # Gitea API: GET /repos/{owner}/{repo}/commits
    local url="$GITEA_URL/repos/$owner/$repo/commits?since=$since&until=$until&limit=100"
    
    if [[ -n "$AUTH" ]]; then
        curl -s $AUTH "$url" 2>/dev/null || echo "[]"
    else
        curl -s "$url" 2>/dev/null || echo "[]"
    fi
}

# Main data collection
declare -A author_counts
declare -A repo_author_counts
declare -a all_authors=()

# Known organizations
orgs=("Deepwork-AI")

for org in "${orgs[@]}"; do
    repos_json=$(fetch_repos "$org")
    
    # Parse repo names
    if command -v jq &>/dev/null; then
        repo_names=$(echo "$repos_json" | jq -r '.[].name' 2>/dev/null || true)
    else
        repo_names=$(echo "$repos_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//; s/"$//' || true)
    fi
    
    for repo in $repo_names; do
        [[ -z "$repo" ]] && continue
        
        commits_json=$(fetch_commits "$org" "$repo" "$SINCE" "$UNTIL")
        
        if command -v jq &>/dev/null; then
            # Parse with jq
            while IFS= read -r commit; do
                [[ -z "$commit" ]] && continue
                
                author=$(echo "$commit" | jq -r '.author.login // .commit.author.name // "unknown"')
                email=$(echo "$commit" | jq -r '.commit.author.email // ""')
                
                # Update counts
                author_key="${org}/${repo}/${author}"
                ((repo_author_counts[$author_key]++)) || true
                ((author_counts[$author]++)) || true
                
                # Track unique authors
                if [[ ! " ${all_authors[@]} " =~ " ${author} " ]]; then
                    all_authors+=("$author")
                fi
            done < <(echo "$commits_json" | jq -c '.[]' 2>/dev/null || true)
        else
            # Manual parsing
            commit_authors=$(echo "$commits_json" | grep -o '"login":"[^"]*"' | sed 's/"login":"//; s/"$//' || true)
            
            for author in $commit_authors; do
                author_key="${org}/${repo}/${author}"
                ((repo_author_counts[$author_key]++)) || true
                ((author_counts[$author]++)) || true
                
                if [[ ! " ${all_authors[@]} " =~ " ${author} " ]]; then
                    all_authors+=("$author")
                fi
            done
        fi
    done
done

# Calculate totals
total_commits=0
for count in "${author_counts[@]}"; do
    total_commits=$((total_commits + count))
done

# Count repos with commits
repos_with_commits=0
for key in "${!repo_author_counts[@]}"; do
    repos_with_commits=$((repos_with_commits + 1))
done

# Output
if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    # ASCII table output
    echo "============================================================"
    echo "           COMMIT STATISTICS (Last $DAYS day(s))"
    echo "============================================================"
    echo "Period: $SINCE to $UNTIL"
    echo ""
    printf "%-25s %10s\n" "Author" "Commits"
    echo "------------------------------------------------------------"
    
    for author in "${!author_counts[@]}"; do
        printf "%-25s %10d\n" "$author" "${author_counts[$author]}"
    done
    
    echo "------------------------------------------------------------"
    printf "%-25s %10d\n" "TOTAL" "$total_commits"
    echo "============================================================"
    echo ""
    echo "Unique authors: ${#all_authors[@]}"
    echo "Generated: $TIMESTAMP"
else
    # JSON output
    if command -v jq &>/dev/null; then
        # Build structured JSON with jq
        {
            echo "{"
            echo "  \"timestamp\": \"$TIMESTAMP\","
            echo "  \"period\": {"
            echo "    \"days\": $DAYS,"
            echo "    \"since\": \"$SINCE\","
            echo "    \"until\": \"$UNTIL\""
            echo "  },"
            echo "  \"stats\": ["
            
            # Group by repo
            prev_repo=""
            first_repo=true
            
            for key in "${!repo_author_counts[@]}"; do
                IFS='/' read -r org repo author <<< "$key"
                count="${repo_author_counts[$key]}"
                
                repo_full="$org/$repo"
                
                if [[ "$repo_full" != "$prev_repo" ]]; then
                    if [[ "$first_repo" == "true" ]]; then
                        first_repo=false
                    else
                        echo "      ]"
                        echo "    },"
                    fi
                    
                    echo "    {"
                    echo "      \"repo\": \"$repo\","
                    echo "      \"org\": \"$org\","
                    echo "      \"commits\": ["
                    prev_repo="$repo_full"
                    first_author=true
                fi
                
                if [[ "$first_author" == "true" ]]; then
                    first_author=false
                else
                    echo ","
                fi
                
                echo "        {"
                echo "          \"author\": \"$author\","
                echo "          \"count\": $count,"
                echo "          \"emails\": []"
                echo -n "        }"
            done
            
            if [[ -n "$prev_repo" ]]; then
                echo ""
                echo "      ],"
                echo "      \"total_commits\": $total_commits"
                echo "    }"
            fi
            
            echo "  ],"
            echo "  \"summary\": {"
            echo "    \"total_repos_with_commits\": $repos_with_commits,"
            echo "    \"total_commits\": $total_commits,"
            echo "    \"unique_authors\": [$(printf '\"%s\",' "${all_authors[@]}" | sed 's/,$//')]"
            echo "  }"
            echo "}"
        } | jq . 2>/dev/null || cat
    else
        # Simplified JSON without jq
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"period\": {"
        echo "    \"days\": $DAYS,"
        echo "    \"since\": \"$SINCE\","
        echo "    \"until\": \"$UNTIL\""
        echo "  },"
        echo "  \"by_author\": {"
        
        first=true
        for author in "${!author_counts[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": %d' "$author" "${author_counts[$author]}"
        done
        
        echo ""
        echo "  },"
        echo "  \"summary\": {"
        echo "    \"total_commits\": $total_commits,"
        echo "    \"unique_authors\": ${#all_authors[@]}"
        echo "  }"
        echo "}"
    fi
fi
