#!/bin/bash
# GT Mesh — Worker Inbox Delivery
# Pulls messages from DoltHub and INJECTS them into the active tmux session.
# Works for both Kimi Code and MiniMax sessions.
#
# Runs on WORKERS only (inside Docker containers).
# Cron: */3 * * * * (every 3 min)
#
# Flow:
#   1. Pull from DoltHub
#   2. Find unread messages for this GT
#   3. For each message: inject into tmux session via send-keys
#   4. Mark as read, commit, push

set -o pipefail

GT_ROOT="${GT_ROOT:-/workspace/gt}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
LOCK="/tmp/worker-inbox.lock"
LOG="/tmp/worker-inbox-deliver.log"
DELIVERED_LOG="/tmp/worker-delivered-msgs.log"

# Use absolute path for dolt (cron PATH may not include /usr/local/bin)
DOLT="/usr/local/bin/dolt"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG"
}

# Prevent concurrent runs
if [ -f "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 180 ] && exit 0
  rm -f "$LOCK"
fi
touch "$LOCK"
trap "rm -f $LOCK" EXIT

if [ ! -f "$MESH_YAML" ]; then
  log "[error] mesh.yaml not found at $MESH_YAML"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
DOLTHUB_DB="deepwork/gt-agent-mail"

touch "$DELIVERED_LOG"

# Ensure clone exists
if [ ! -d "$CLONE_DIR/.dolt" ]; then
  log "[setup] Cloning $DOLTHUB_DB..."
  rm -rf "$CLONE_DIR"
  timeout 90 "$DOLT" clone "$DOLTHUB_DB" "$CLONE_DIR" 2>>"$LOG"
  if [ $? -ne 0 ]; then
    log "[error] Clone failed"
    exit 1
  fi
  log "[setup] Clone created at $CLONE_DIR"
fi

cd "$CLONE_DIR" || { log "[error] Cannot cd to $CLONE_DIR"; exit 1; }

# Commit any local changes before pull
timeout 15 "$DOLT" add . 2>/dev/null
if timeout 10 "$DOLT" diff --staged --stat 2>/dev/null | grep -qi "row"; then
  timeout 15 "$DOLT" commit -m "worker: pre-pull commit from $GT_ID" --allow-empty 2>/dev/null || true
fi

# Pull latest
timeout 45 "$DOLT" pull 2>>"$LOG"
PULL_RC=$?

# Auto-resolve conflicts
for table in peers messages; do
  if timeout 5 "$DOLT" conflicts cat "$table" >/dev/null 2>&1; then
    timeout 10 "$DOLT" conflicts resolve --theirs "$table" 2>/dev/null
    timeout 10 "$DOLT" add . 2>/dev/null
    timeout 10 "$DOLT" commit -m "worker: auto-resolve $table conflict (theirs)" 2>/dev/null || true
    log "[conflict] Resolved $table with theirs-wins"
  fi
done

# Update heartbeat
timeout 10 "$DOLT" sql -q "UPDATE peers SET last_seen = NOW() WHERE gt_id = '$GT_ID';" 2>/dev/null || true

# Find unread message IDs only (avoids CSV parsing of complex fields)
MSG_IDS=$(timeout 10 "$DOLT" sql -q "SELECT id FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL ORDER BY priority ASC, created_at ASC LIMIT 10;" -r csv 2>/dev/null | tail -n +2)

if [ -z "$MSG_IDS" ]; then
  # Commit heartbeat and push
  timeout 15 "$DOLT" add . 2>/dev/null
  if timeout 10 "$DOLT" diff --staged --stat 2>/dev/null | grep -qi "row"; then
    timeout 15 "$DOLT" commit -m "worker: heartbeat from $GT_ID" 2>/dev/null
  fi
  timeout 30 "$DOLT" push 2>/dev/null || true
  log "[inbox] No new messages"
  exit 0
fi

DELIVERED=0

while IFS= read -r msg_id; do
  [ -z "$msg_id" ] && continue

  # Skip already delivered
  if grep -qF "$msg_id" "$DELIVERED_LOG" 2>/dev/null; then
    timeout 5 "$DOLT" sql -q "UPDATE messages SET read_at = NOW() WHERE id = '$msg_id';" 2>/dev/null
    continue
  fi

  # Fetch each field individually (safe — no CSV parsing of multi-field rows)
  from_gt=$(timeout 5 "$DOLT" sql -q "SELECT from_gt FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  subject=$(timeout 5 "$DOLT" sql -q "SELECT subject FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  priority=$(timeout 5 "$DOLT" sql -q "SELECT priority FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)
  body=$(timeout 5 "$DOLT" sql -q "SELECT body FROM messages WHERE id = '$msg_id';" -r csv 2>/dev/null | tail -n +2 | head -1)

  # Determine target session
  TARGET_SESSION="worker1"
  if ! tmux has-session -t "$TARGET_SESSION" 2>/dev/null; then
    # Try other session names
    for s in worker kimi minimax main; do
      if tmux has-session -t "$s" 2>/dev/null; then
        TARGET_SESSION="$s"
        break
      fi
    done
  fi

  if ! tmux has-session -t "$TARGET_SESSION" 2>/dev/null; then
    log "[error] No tmux session found for delivery"
    continue
  fi

  # Sanitize for file names and tmux
  SAFE_ID=$(echo "$msg_id" | tr -cd 'a-zA-Z0-9_-')
  CLEAN_SUBJECT=$(echo "$subject" | tr -d '"' | tr -d "'" | tr -d '`' | head -c 200)
  CLEAN_BODY=$(echo "$body" | tr -d '"' | tr -d "'" | tr -d '`' | head -c 2000)

  # Write message to a temp file the agent can read
  MSG_FILE="/tmp/mesh-msg-${SAFE_ID}.txt"
  cat > "$MSG_FILE" << 'MSGEOF_HEADER'
=== MESH MAIL ===
MSGEOF_HEADER
  echo "From: $from_gt [P${priority}]" >> "$MSG_FILE"
  echo "Subject: $CLEAN_SUBJECT" >> "$MSG_FILE"
  echo "" >> "$MSG_FILE"
  echo "$CLEAN_BODY" >> "$MSG_FILE"
  echo "" >> "$MSG_FILE"
  echo "=== END (ID: $msg_id) ===" >> "$MSG_FILE"

  # Inject into the Kimi/MiniMax session
  # Strategy: send a short instruction pointing to the message file
  INJECT_MSG="You have new mesh mail from $from_gt [P${priority}]: $CLEAN_SUBJECT. Read full message: cat $MSG_FILE"

  # Clear any partial input, then inject
  tmux send-keys -t "$TARGET_SESSION" "" 2>/dev/null
  sleep 0.5
  tmux send-keys -t "$TARGET_SESSION" "$INJECT_MSG" Enter 2>/dev/null

  log "[delivered] $msg_id from $from_gt: $CLEAN_SUBJECT"
  echo "$msg_id" >> "$DELIVERED_LOG"
  DELIVERED=$((DELIVERED + 1))

  # Mark as read in DoltHub
  timeout 5 "$DOLT" sql -q "UPDATE messages SET read_at = NOW() WHERE id = '$msg_id';" 2>/dev/null

  # Small delay between messages to avoid flooding
  sleep 2

done <<< "$MSG_IDS"

# Commit and push all changes
timeout 15 "$DOLT" add . 2>/dev/null
if timeout 10 "$DOLT" diff --staged --stat 2>/dev/null | grep -qi "row"; then
  timeout 15 "$DOLT" commit -m "worker: delivered $DELIVERED msgs to $GT_ID" 2>/dev/null
fi
timeout 30 "$DOLT" push 2>/dev/null || log "[warn] Push deferred"

log "[done] Delivered $DELIVERED messages"
