#!/bin/bash
# GT Mesh — Worker Idle Notifier
# If the worker has no in-progress beads and no unread messages,
# send a "need work" message to gt-local (mayor).
#
# Runs on WORKERS only (inside Docker containers).
# Cron: */10 * * * * (every 10 min)
#
# Throttle: only sends once per 30 min to avoid spam.

set -o pipefail

GT_ROOT="${GT_ROOT:-/workspace/gt}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"
LOCK="/tmp/worker-idle.lock"
LOG="/tmp/worker-idle.log"
LAST_SENT="/tmp/worker-idle-last-sent"
DOLT="/usr/local/bin/dolt"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%S) $1" >> "$LOG"
}

# Prevent concurrent runs
if [ -f "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 120 ] && exit 0
  rm -f "$LOCK"
fi
touch "$LOCK"
trap "rm -f $LOCK" EXIT

# Throttle: don't send more than once per 30 min
if [ -f "$LAST_SENT" ]; then
  LAST_TS=$(stat -c %Y "$LAST_SENT" 2>/dev/null || echo 0)
  NOW_TS=$(date +%s)
  DIFF=$((NOW_TS - LAST_TS))
  if [ "$DIFF" -lt 1800 ]; then
    exit 0
  fi
fi

if [ ! -f "$MESH_YAML" ]; then
  log "[error] mesh.yaml not found"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"

if [ ! -d "$CLONE_DIR/.dolt" ]; then
  log "[error] No DoltHub clone"
  exit 1
fi

cd "$CLONE_DIR" || exit 1

# Check for unread messages (if we have unread work, we're not idle)
UNREAD=$(timeout 10 "$DOLT" sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)
if [ "${UNREAD:-0}" -gt 0 ] 2>/dev/null; then
  log "[ok] $UNREAD unread messages — not idle"
  exit 0
fi

# Check if the tmux session is actively running a command (not at prompt)
# If the session is busy, the worker is working
TARGET_SESSION="worker1"
if tmux has-session -t "$TARGET_SESSION" 2>/dev/null; then
  # Capture last line — if it contains the prompt indicator, session is idle
  LAST_LINE=$(tmux capture-pane -t "$TARGET_SESSION" -p 2>/dev/null | grep -v '^$' | tail -1)
  # Kimi prompt contains "agent" or ">" at the end
  # If the last line does NOT look like a prompt, the agent is busy = not idle
  if ! echo "$LAST_LINE" | grep -qE '(agent|>|\$|❯)' 2>/dev/null; then
    log "[ok] Session busy — not idle"
    exit 0
  fi
fi

# Check shared_beads for anything claimed by us
CLAIMED=$(timeout 10 "$DOLT" sql -q "SELECT COUNT(*) FROM shared_beads WHERE claimed_by = '$GT_ID' AND status = 'in_progress';" -r csv 2>/dev/null | tail -n +2 | head -1)
if [ "${CLAIMED:-0}" -gt 0 ] 2>/dev/null; then
  log "[ok] $CLAIMED beads claimed — not idle"
  exit 0
fi

# We are idle — send notification to mayor
log "[idle] No work found. Sending idle notification to gt-local."

SUBJECT="IDLE: $GT_ID has no work"
BODY="Worker $GT_ID is idle. No unread messages, no claimed beads, session is at prompt. Ready for new work assignments. Send tasks via: mesh-send.sh $GT_ID <subject> <body> <priority>"

MSG_ID="idle-${GT_ID}-$(date +%s)"

timeout 10 "$DOLT" sql -q "INSERT INTO messages (id, from_gt, from_addr, to_gt, to_addr, subject, body, priority, created_at) VALUES ('$MSG_ID', '$GT_ID', 'worker/', 'gt-local', 'mayor/', '$SUBJECT', '$BODY', 2, NOW());" 2>/dev/null

timeout 15 "$DOLT" add . 2>/dev/null
timeout 15 "$DOLT" commit -m "worker: idle notification from $GT_ID" 2>/dev/null || true
timeout 30 "$DOLT" push 2>/dev/null || log "[warn] Push deferred"

touch "$LAST_SENT"
log "[sent] Idle notification $MSG_ID"
