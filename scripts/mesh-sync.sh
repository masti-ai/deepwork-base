#!/bin/bash
# GT Mesh — Force sync with DoltHub
#
# Usage: mesh-sync.sh

GT_ROOT="${GT_ROOT:-.}"
MESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"

# Prevent concurrent runs — shared lock with sync-dolthub.sh on gt-local
LOCK="/tmp/mesh-sync.lock"
if [ -f "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt 120 ] && exit 0
  rm -f "$LOCK"
fi
touch "$LOCK"
trap "rm -f $LOCK" EXIT

if [ ! -f "$MESH_YAML" ]; then
  echo "[error] Not in a mesh. Run: gt mesh init"
  exit 1
fi

GT_ID=$(grep "^  id:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR=$(grep "clone_dir:" "$MESH_YAML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
CLONE_DIR="${CLONE_DIR:-/tmp/mesh-sync-clone}"
DOLTHUB_DB="deepwork/gt-agent-mail"

echo "[sync] Starting mesh sync for $GT_ID..."

# Ensure clone exists (check for .dolt dir, not just the directory)
if [ ! -d "$CLONE_DIR/.dolt" ]; then
  echo "[sync] Cloning $DOLTHUB_DB..."
  rm -rf "$CLONE_DIR"
  timeout 90 dolt clone "$DOLTHUB_DB" "$CLONE_DIR" 2>&1
  if [ $? -ne 0 ]; then
    echo "[error] Clone failed"
    exit 1
  fi
fi

cd "$CLONE_DIR"

# Commit any uncommitted local changes BEFORE pulling (prevents "cannot merge with uncommitted changes")
timeout 15 dolt add . 2>/dev/null
if timeout 15 dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
  timeout 15 dolt commit -m "mesh: pre-sync commit from $GT_ID" --allow-empty 2>/dev/null || true
fi

# Pull
echo "[sync] Pulling from DoltHub..."
timeout 45 dolt pull 2>/dev/null || echo "[warn] Pull had issues, continuing..."

# Auto-resolve conflicts (peers/messages conflicts are harmless — theirs wins)
for table in peers messages; do
  if timeout 5 dolt conflicts cat "$table" >/dev/null 2>&1; then
    timeout 10 dolt conflicts resolve --theirs "$table" 2>/dev/null
    timeout 10 dolt add . 2>/dev/null
    timeout 10 dolt commit -m "mesh: auto-resolve $table conflict (theirs)" --allow-empty 2>/dev/null || true
    echo "[sync] Resolved $table conflict"
  fi
done

# Update heartbeat
timeout 10 dolt sql -q "UPDATE peers SET last_seen = NOW() WHERE gt_id = '$GT_ID';" 2>/dev/null || true

# Commit and push
timeout 15 dolt add . 2>/dev/null
if timeout 15 dolt diff --staged --stat 2>/dev/null | grep -qi "row"; then
  timeout 15 dolt commit -m "mesh: sync from $GT_ID" --allow-empty 2>/dev/null
fi
timeout 30 dolt push 2>/dev/null || echo "[warn] Push deferred"

# Count stats
UNREAD=$(timeout 10 dolt sql -q "SELECT COUNT(*) FROM messages WHERE to_gt = '$GT_ID' AND read_at IS NULL;" -r csv 2>/dev/null | tail -n +2 | head -1)
PEERS=$(timeout 10 dolt sql -q "SELECT COUNT(*) FROM peers WHERE status = 'active';" -r csv 2>/dev/null | tail -n +2 | head -1)

cd "$GT_ROOT"

# Check for config updates
MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_CACHE="$GT_ROOT/.mesh-config"
LOCAL_HASH=""
[ -f "$CONFIG_CACHE/version" ] && LOCAL_HASH=$(cat "$CONFIG_CACHE/version")
REMOTE_HASH=$(cd "$CLONE_DIR" && timeout 10 dolt sql -q "SELECT config_hash FROM mesh_config LIMIT 1;" -r csv 2>/dev/null | tail -n +2 | head -1)
if [ -n "$REMOTE_HASH" ] && [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
  echo "[sync] Config updated — pulling..."
  GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" bash "$MESH_DIR/scripts/mesh-config.sh" pull --quiet 2>/dev/null
fi

# Pull new knowledge entries
KNOWLEDGE_DIR="$GT_ROOT/.mesh-config/knowledge"
LEARNINGS="$KNOWLEDGE_DIR/mesh-learnings.md"
LAST_KNOWLEDGE_SYNC=""
[ -f "$KNOWLEDGE_DIR/.last-sync" ] && LAST_KNOWLEDGE_SYNC=$(cat "$KNOWLEDGE_DIR/.last-sync")
NEW_KNOWLEDGE=$(cd "$CLONE_DIR" && timeout 10 dolt sql -q "SELECT COUNT(*) FROM mesh_knowledge_entries WHERE updated_at > '${LAST_KNOWLEDGE_SYNC:-1970-01-01}';" -r csv 2>/dev/null | tail -n +2 | head -1)
if [ "${NEW_KNOWLEDGE:-0}" -gt 0 ] 2>/dev/null; then
  echo "[sync] $NEW_KNOWLEDGE new knowledge entries — pulling..."
  mkdir -p "$KNOWLEDGE_DIR"
  cd "$CLONE_DIR"
  ENTRIES=$(timeout 10 dolt sql -q "SELECT CONCAT(title, '|||', content) FROM mesh_knowledge_entries WHERE updated_at > '${LAST_KNOWLEDGE_SYNC:-1970-01-01}' ORDER BY created_at;" -r csv 2>/dev/null | tail -n +2 | sed 's/^"//;s/"$//' | sed 's/""/"/g')
  while IFS='|||' read -r ktitle kcontent; do
    [ -z "$ktitle" ] && continue
    # Skip if already in file (use fixed string matching)
    if [ -f "$LEARNINGS" ] && grep -qF "$ktitle" "$LEARNINGS" 2>/dev/null; then
      continue
    fi
    # Write content safely - escape any markdown special chars in title
    echo "" >> "$LEARNINGS"
    echo "### $(printf '%s' "$ktitle" | sed 's/^#//g')" >> "$LEARNINGS"
    # Content: replace literal \n with newlines, but sanitize for shell safety
    printf '%s' "$kcontent" | sed 's/\\n/\n/g' | sed 's/^[ \t]*//;s/[ \t]*$//' >> "$LEARNINGS"
    echo "" >> "$LEARNINGS"
  done <<< "$ENTRIES"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$KNOWLEDGE_DIR/.last-sync"
  cd "$GT_ROOT"
fi

# Handle incoming mail (route P0/P1 to mayor, auto-reply to pings)
MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${UNREAD:-0}" -gt 0 ] 2>/dev/null; then
  timeout 30 bash "$MESH_DIR/scripts/mesh-mail-handler.sh" --auto-reply 2>/dev/null || true
fi

# Log sync activity
MESH_DIR_SYNC="$(cd "$(dirname "$0")/.." && pwd)"
GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" timeout 15 bash "$MESH_DIR_SYNC/scripts/mesh-auto-sync.sh" log "sync completed: unread=${UNREAD:-0} peers=${PEERS:-0}" 2>/dev/null || true

# Run self-improving loop review
GT_ROOT="$GT_ROOT" MESH_YAML="$MESH_YAML" timeout 30 bash "$MESH_DIR_SYNC/scripts/mesh-improve.sh" review 2>/dev/null | head -5 || true

echo "[sync] Done. Unread: ${UNREAD:-0} | Active peers: ${PEERS:-0}"
