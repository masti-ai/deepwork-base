#!/bin/bash
# GT Mesh — Skill-based bead routing
#
# Routes beads to mesh nodes based on skill matching.
# Finds the best node to handle a bead based on required skills.
#
# Usage:
#   mesh-route.sh <bead-id>              Find best node for bead
#   mesh-route.sh <bead-id> --execute    Route and dispatch to best node
#   mesh-route.sh skills                 List this node's skills
#   mesh-route.sh peers                  Show skills of all peers
#   mesh-route.sh match <skill1,skill2>  Find nodes matching skill set

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

# Parse skills from mesh.yaml
_get_node_skills() {
  local yaml_file="$1"
  awk '/^skills:/{found=1;next} /^[^ ]/{found=0} found && /^  - /{gsub(/^  - /,""); print}' "$yaml_file" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

# Get skills for this node
_get_my_skills() {
  _get_node_skills "$MESH_YAML"
}

# Get skills for a peer from DoltHub
_get_peer_skills() {
  local peer_id="$1"
  cd "$CLONE_DIR" 2>/dev/null || return
  dolt sql -q "SELECT skills FROM mesh_nodes WHERE gt_id = '$peer_id';" -r csv 2>/dev/null | tail -n +2 | head -1
}

# Get bead requirements (skills needed)
_get_bead_requirements() {
  local bead_id="$1"
  cd "$CLONE_DIR" 2>/dev/null || return
  
  # First check shared_beads table for skill_requirements field
  local skills
  skills=$(dolt sql -q "SELECT skill_requirements FROM shared_beads WHERE bead_id = '$bead_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  
  if [ -n "$skills" ] && [ "$skills" != "NULL" ]; then
    echo "$skills"
    return
  fi
  
  # Fallback: try to infer from title/description/labels
  local title
  local labels
  title=$(dolt sql -q "SELECT title FROM shared_beads WHERE bead_id = '$bead_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  labels=$(dolt sql -q "SELECT labels FROM shared_beads WHERE bead_id = '$bead_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  
  # Infer skills from keywords
  local inferred=""
  echo "$title $labels" | grep -qi "python" && inferred="${inferred}python,"
  echo "$title $labels" | grep -qi "typescript\|ts\|javascript\|js" && inferred="${inferred}typescript,"
  echo "$title $labels" | grep -qi "react\|frontend" && inferred="${inferred}react,"
  echo "$title $labels" | grep -qi "ml\|machine.learning\|ai\|model" && inferred="${inferred}ml,"
  echo "$title $labels" | grep -qi "infra\|devops\|aws\|kubernetes\|docker" && inferred="${inferred}infra,"
  echo "$title $labels" | grep -qi "go\|golang" && inferred="${inferred}go,"
  echo "$title $labels" | grep -qi "rust" && inferred="${inferred}rust,"
  echo "$title $labels" | grep -qi "java" && inferred="${inferred}java,"
  
  echo "$inferred" | sed 's/,$//'
}

# Calculate skill match score (0-100)
_calc_match_score() {
  local node_skills="$1"
  local required_skills="$2"
  
  [ -z "$required_skills" ] && echo "50" && return
  
  local total_required=0
  local matched=0
  
  IFS=',' read -ra REQ <<< "$required_skills"
  for skill in "${REQ[@]}"; do
    skill=$(echo "$skill" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    [ -z "$skill" ] && continue
    total_required=$((total_required + 1))
    
    # Check if node has this skill
    if echo "$node_skills" | tr '[:upper:]' '[:lower:]' | grep -qw "$skill"; then
      matched=$((matched + 1))
    fi
  done
  
  [ "$total_required" -eq 0 ] && echo "50" && return
  
  # Calculate percentage
  echo "$(( (matched * 100) / total_required ))"
}

# Find best matching node for a bead
_find_best_node() {
  local bead_id="$1"
  
  # Get bead requirements
  local requirements
  requirements=$(_get_bead_requirements "$bead_id")
  
  echo "Bead: $bead_id"
  echo "Required skills: ${requirements:-<none specified>}"
  echo ""
  
  # Check this node
  local my_skills
  my_skills=$(_get_my_skills)
  local my_score
  my_score=$(_calc_match_score "$my_skills" "$requirements")
  
  echo "Matching nodes:"
  printf "  %-20s %3s%%  %s\n" "NODE" "MATCH" "SKILLS"
  printf "  %-20s %3s%%  %s\n" "----" "-----" "------"
  printf "  %-20s %3s%%  %s\n" "$GT_ID (you)" "$my_score" "$my_skills"
  
  # Check peers
  cd "$CLONE_DIR" 2>/dev/null || return
  local peers
  peers=$(dolt sql -q "SELECT gt_id, skills FROM mesh_nodes WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2)
  
  local best_node="$GT_ID"
  local best_score="$my_score"
  
  while IFS=',' read -r peer_id peer_skills; do
    [ -z "$peer_id" ] && continue
    [ "$peer_id" = "$GT_ID" ] && continue
    
    local score
    score=$(_calc_match_score "$peer_skills" "$requirements")
    printf "  %-20s %3s%%  %s\n" "$peer_id" "$score" "$peer_skills"
    
    if [ "$score" -gt "$best_score" ]; then
      best_score="$score"
      best_node="$peer_id"
    fi
  done <<< "$peers"
  
  echo ""
  echo "Best match: $best_node ($best_score% skill match)"
  
  if [ "$best_node" = "$GT_ID" ]; then
    echo "This bead should be handled by YOU ($GT_ID)"
  else
    echo "This bead should be routed to: $best_node"
  fi
}

# Route bead to best node
_route_bead() {
  local bead_id="$1"
  
  echo "Routing bead: $bead_id"
  echo ""
  
  # For now, just find the best node and suggest routing
  # In future, this could automatically send mesh mail to the best node
  _find_best_node "$bead_id"
  
  echo ""
  echo "To dispatch this bead to the best-matching node:"
  echo "  gt mesh send <best-node>/mayor -s 'ROUTE: $bead_id' -m 'Please handle bead $bead_id based on skill match'"
}

# List all peers and their skills
_list_peer_skills() {
  echo "Mesh Node Skills Registry"
  echo "========================="
  echo ""
  printf "  %-20s %s\n" "NODE" "SKILLS"
  printf "  %-20s %s\n" "----" "------"
  
  # This node
  local my_skills
  my_skills=$(_get_my_skills)
  printf "  %-20s %s (you)\n" "$GT_ID" "$my_skills"
  
  # Peers from DoltHub
  cd "$CLONE_DIR" 2>/dev/null || return
  local peers
  peers=$(dolt sql -q "SELECT gt_id, skills FROM mesh_nodes WHERE status = 'active' ORDER BY gt_id;" -r csv 2>/dev/null | tail -n +2)
  
  while IFS=',' read -r peer_id peer_skills; do
    [ -z "$peer_id" ] && continue
    [ "$peer_id" = "$GT_ID" ] && continue
    printf "  %-20s %s\n" "$peer_id" "${peer_skills:-<no skills declared>}"
  done <<< "$peers"
}

# Find nodes matching specific skills
_match_skills() {
  local required="$1"
  
  echo "Finding nodes with skills: $required"
  echo ""
  printf "  %-20s %3s %s\n" "NODE" "SCORE" "MATCHING SKILLS"
  printf "  %-20s %3s %s\n" "----" "-----" "---------------"
  
  # Check this node
  local my_skills
  my_skills=$(_get_my_skills)
  local my_score
  my_score=$(_calc_match_score "$my_skills" "$required")
  printf "  %-20s %3s%% %s\n" "$GT_ID" "$my_score" "$my_skills"
  
  # Check peers
  cd "$CLONE_DIR" 2>/dev/null || return
  local peers
  peers=$(dolt sql -q "SELECT gt_id, skills FROM mesh_nodes WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2)
  
  while IFS=',' read -r peer_id peer_skills; do
    [ -z "$peer_id" ] && continue
    [ "$peer_id" = "$GT_ID" ] && continue
    
    local score
    score=$(_calc_match_score "$peer_skills" "$required")
    [ "$score" -gt 0 ] && printf "  %-20s %3s%% %s\n" "$peer_id" "$score" "$peer_skills"
  done <<< "$peers"
}

# Main command dispatch
SUBCMD="${1:-help}"
shift 2>/dev/null || true

case "$SUBCMD" in
  skills)
    echo "This node's skills:"
    _get_my_skills
    ;;
    
  peers)
    _list_peer_skills
    ;;
    
  match)
    SKILLS="$1"
    if [ -z "$SKILLS" ]; then
      echo "Usage: gt mesh route match <skill1,skill2,...>"
      exit 1
    fi
    _match_skills "$SKILLS"
    ;;
    
  help|--help|-h)
    echo "GT Mesh — Skill-based bead routing"
    echo ""
    echo "Usage: gt mesh route <command> [options]"
    echo ""
    echo "Commands:"
    echo "  <bead-id>          Find best node for bead based on skill matching"
    echo "  skills             Show this node's declared skills"
    echo "  peers              Show skills of all mesh nodes"
    echo "  match <skills>     Find nodes matching comma-separated skill list"
    echo "  help               Show this help"
    echo ""
    echo "Examples:"
    echo "  gt mesh route gt-001              # Find best node for bead gt-001"
    echo "  gt mesh route skills              # Show my skills"
    echo "  gt mesh route match python,react  # Find nodes with python AND react"
    echo ""
    echo "Skills are declared in mesh.yaml under the 'skills:' section."
    ;;
    
  *)
    # Assume it's a bead ID
    BEAD_ID="$SUBCMD"
    _route_bead "$BEAD_ID"
    ;;
esac
