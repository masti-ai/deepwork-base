#!/bin/bash
# GT Mesh — Dynamic Mail Router
# Runs on every sync cycle. Routes incoming mail to the right local agent.
#
# Routing logic:
#   1. Extract context from message (subject + body keywords)
#   2. Match to a rig/project → route to that rig's crew manager
#   3. If no rig match or mesh/coordination topic → route to mayor
#   4. If target agent is dead → fall back to next available agent
#   5. Auto-reply to status/ping requests
#   6. Log everything to .mesh-inbox-pending.log
#
# Usage: mesh-mail-handler.sh [--auto-reply]

GT_ROOT="${GT_ROOT:-$HOME/gt}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" 2>/dev/null | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
INBOX_FILE="$GT_ROOT/.mesh-inbox-pending.log"
AUTO_REPLY=false
[ "$1" = "--auto-reply" ] && AUTO_REPLY=true

if [ ! -f "$MESH_YAML" ]; then
  exit 0
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

[ ! -d "$CLONE_DIR/.dolt" ] && exit 0

cd "$CLONE_DIR"

# Count unread
UNREAD_COUNT=$(dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)
[ "${UNREAD_COUNT:-0}" -eq 0 ] && exit 0

# ─── Routing Table ───
# Maps keywords → tmux session name
# Format: "keyword_pattern:session_name"
# Order matters — first match wins. More specific patterns first.
ROUTE_TABLE=(
  # Rig-specific routing
  "planogram|vap-|ai-planogram|villa_ai_planogram|vap:vap-crew-manager"
  "alc|vaa-|alc-ai|villa_alc|vaa:vaa-crew-manager"
  "arcade|gta-|gt_arcade|gta:gta-crew-manager"
  # Mesh/coordination always to mayor
  "mesh|config|pack|improve|sync|invite|peer|gtconfig:hq-mayor"
  # Generic work/task/bead routing — try mayor
  "task|bead|issue|pr|review|deploy|release:hq-mayor"
)

# ─── Helper: check if a tmux session is alive ───
_session_alive() {
  local session="$1"
  tmux has-session -t "$session" 2>/dev/null || return 1
  local dead=$(tmux list-panes -t "$session" -F '#{pane_dead}' 2>/dev/null | head -1)
  [ "$dead" = "0" ] && return 0
  return 1
}

# ─── Helper: find best route for a message ───
_route_message() {
  local text="$1"  # subject + body combined, lowercased

  # Check each route pattern
  for entry in "${ROUTE_TABLE[@]}"; do
    local pattern="${entry%%:*}"
    local target="${entry##*:}"

    # Convert pipe-separated pattern to grep alternation
    if echo "$text" | grep -qiE "$pattern"; then
      # Found a match — check if target is alive
      if _session_alive "$target"; then
        echo "$target"
        return 0
      fi
    fi
  done

  # No specific match — find any alive manager
  # Priority: mayor > rig managers
  for fallback in hq-mayor vap-crew-manager vaa-crew-manager gta-crew-manager; do
    if _session_alive "$fallback"; then
      echo "$fallback"
      return 0
    fi
  done

  # Nothing alive
  echo ""
  return 1
}

# ─── Process messages ───
MESSAGES=$(dolt sql -q "SELECT CONCAT(id, '|', from_gt, '|', priority, '|', subject) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL ORDER BY priority ASC, created_at DESC;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//')

while IFS='|' read -r msg_id from_gt priority subject; do
  [ -z "$msg_id" ] && continue

  # Get body for routing context (first 200 chars)
  body_snippet=$(dolt sql -q "SELECT LEFT(body, 200) FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1 | sed 's/^"//;s/"$//')

  # Combine subject + body for keyword matching
  match_text=$(echo "$subject $body_snippet" | tr '[:upper:]' '[:lower:]')

  # Find the right agent
  target=$(_route_message "$match_text")

  # Log to pending inbox
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [P${priority:-2}] from:$from_gt subject:$subject routed:${target:-NONE} id:$msg_id" >> "$INBOX_FILE"

  if [ -n "$target" ]; then
    # Nudge the target agent
    gt nudge "$target" "[MESH MAIL] P${priority:-2} from $from_gt: $subject — check with: gt-mesh inbox" 2>/dev/null
  fi

  # Auto-reply to status/ping requests
  if [ "$AUTO_REPLY" = true ]; then
    subject_lower=$(echo "$subject" | tr '[:upper:]' '[:lower:]')
    case "$subject_lower" in
      *status*check*|*ping*|*are*you*alive*|*heartbeat*)
        PEERS=$(dolt sql -q "SELECT COUNT(*) FROM peers WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)
        ACTIVE_AGENTS=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -cE '(manager|mayor)')
        REPLY_BODY="Auto-reply from $GT_ID: Online. Peers: ${PEERS:-?}. Active agents: ${ACTIVE_AGENTS:-0}. Sync: $(date -u +%H:%M:%S UTC)."
        REPLY_ID="msg-auto-$(date +%s)-${RANDOM}"
        REPLY_ESC=$(echo "$REPLY_BODY" | sed "s/'/''/g")
        dolt sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, subject, body, priority, created_at)
          VALUES ('$REPLY_ID', '$GT_ID', 'mayor/', '$from_gt', 'RE: $subject', '$REPLY_ESC', 2, NOW());" 2>/dev/null
        dolt sql -q "UPDATE messages SET read_at = NOW() WHERE id = '$msg_id';" 2>/dev/null
        ;;
    esac
  fi

done <<< "$MESSAGES"

# Commit any auto-replies
if [ "$AUTO_REPLY" = true ]; then
  dolt add . 2>/dev/null
  if dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
    dolt commit -m "mesh: $GT_ID auto-replied to messages" --allow-empty 2>/dev/null || true
    dolt push 2>/dev/null || true
  fi
fi

cd "$GT_ROOT"
