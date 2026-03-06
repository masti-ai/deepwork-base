# GT Mesh — Complete Documentation

## Table of Contents

1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Mesh Lifecycle](#mesh-lifecycle)
4. [Access Control System](#access-control-system)
5. [Mesh Rules](#mesh-rules)
6. [Shared Beads (Work Coordination)](#shared-beads)
7. [Shared Context (Knowledge Layer)](#shared-context)
8. [Mesh Feed (Activity Stream)](#mesh-feed)
9. [Mesh Daemon](#mesh-daemon)
10. [Scaling](#scaling)
11. [Troubleshooting](#troubleshooting)

---

## Overview

GT Mesh is a plugin for Gas Town that connects multiple Gas Town instances
into a collaborative coding network. Multiple developers, each running their
own Gas Town, can join a shared workspace and build software together through
AI agents.

**The core idea:** You talk to your Mayor, start a mesh, share an invite code.
Friends join with one command. They create beads (tasks), your polecats build
the features. Everyone sees what's happening through the mesh feed.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Mesh** | A network of connected Gas Towns sharing work and context |
| **Coordinator** | The GT that created the mesh. Sets rules, reviews work, manages access |
| **Worker** | A GT that picks up and executes work. Creates PRs, doesn't merge |
| **Contributor** | A GT that creates beads/issues. Doesn't execute — coordinator's polecats do |
| **Mesh Rules** | Governance rules all participants follow. Set by coordinator |
| **Shared Beads** | Issues visible across the mesh. Anyone with write access can create them |
| **Claims** | Prevents race conditions — a GT claims a bead before working on it |
| **Mesh Feed** | Activity stream showing what's happening across all connected GTs |

---

## Getting Started

### 1. Install the plugin

```bash
# Option A: Plugin install (when available)
gt plugin install Deepwork-AI/gt-mesh

# Option B: Manual
git clone https://github.com/Deepwork-AI/gt-mesh.git .gt-mesh
bash .gt-mesh/install.sh
```

### 2. Create a mesh (you become coordinator)

```bash
gt mesh init --role coordinator
# Creates mesh.yaml with your identity
# Sets up DoltHub backbone
# Starts the mesh daemon
```

### 3. Invite someone

```bash
gt mesh invite --role write --rigs my_project --expires 7d
# Output: MESH-K9XP-4LMN
# Share this code with your friend
```

### 4. Friend joins

```bash
# On their Gas Town:
gt mesh join MESH-K9XP-4LMN
# Connects to your mesh, gets access to shared rigs
# Their daemon starts syncing automatically
```

### 5. Start collaborating

```bash
# Friend creates a bead on your shared rig:
bd create --mesh --rig my_project "Add dark mode to dashboard"

# You see it in your mesh feed:
gt mesh feed
# > [gt-friend] Created bead: "Add dark mode to dashboard" on my_project

# Your Mayor reviews and accepts:
gt mesh accept <bead-id>

# Your polecats build it — friend gets notified when done
```

---

## Mesh Lifecycle

### Creating a Mesh

```
You run: gt mesh init --role coordinator
    |
    v
mesh.yaml created (identity, rules, access control)
    |
    v
DoltHub database initialized (or connected to existing)
    |
    v
Mesh daemon starts (background sync every 2 min)
    |
    v
You're registered as 'owner' in peers table
    |
    v
Ready to invite others
```

### Inviting Participants

```
You run: gt mesh invite --role write --rigs project_a --expires 7d
    |
    v
Invite code generated: MESH-K9XP-4LMN
Invite written to DoltHub `invites` table
    |
    v
You share the code (Slack, email, whatever)
    |
    v
Friend runs: gt mesh join MESH-K9XP-4LMN
    |
    v
Friend's GT:
  - Validates invite (not expired, not claimed)
  - Claims the invite
  - Runs mesh init if needed
  - Registers as peer with role from invite
  - Gets access to specified rigs
  - Starts daemon
  - Accepts mesh rules automatically
```

### Revoking Access

```bash
gt mesh revoke <gt-id>                  # Revoke a peer immediately
gt mesh revoke --invite <code>          # Revoke an unclaimed invite
gt mesh access set <gt-id> --role read  # Downgrade to read-only
```

### Leaving a Mesh

```bash
gt mesh leave                           # Graceful departure
# Deregisters from peers table
# Stops daemon
# Keeps local data (doesn't delete anything)
```

### Shutting Down a Mesh (owner only)

```bash
gt mesh shutdown                        # Tear down the mesh
# Notifies all peers
# Marks all invites as expired
# Peers' daemons detect shutdown and stop syncing
```

---

## Access Control System

### The Hierarchy

```
OWNER (mesh creator)
  |
  |-- Full control: rules, access, delete, transfer
  |
  v
ADMIN (trusted reviewers)
  |
  |-- Merge PRs, approve/reject, assign beads, manage write/read
  |
  v
WRITE (contributors)
  |
  |-- Create beads, claim work, create PRs, publish findings
  |
  v
READ (observers)
  |
  |-- View everything, send messages, cannot modify
```

### Permission Matrix

| Permission | Read | Write | Admin | Owner |
|-----------|------|-------|-------|-------|
| View shared rigs | YES | YES | YES | YES |
| View beads & activity | YES | YES | YES | YES |
| Send mesh messages | YES | YES | YES | YES |
| Create beads | - | YES | YES | YES |
| Claim beads | - | YES | YES | YES |
| Create PRs | - | YES | YES | YES |
| Publish findings/skills | - | YES | YES | YES |
| Approve/reject PRs | - | - | YES | YES |
| Merge PRs | - | - | YES | YES |
| Close any bead | - | - | YES | YES |
| Assign beads to GTs | - | - | YES | YES |
| Manage write/read access | - | - | YES | YES |
| Configure auto-approve | - | - | YES | YES |
| Change mesh rules | - | - | - | YES |
| Manage admins | - | - | - | YES |
| Delete mesh | - | - | - | YES |
| Transfer ownership | - | - | - | YES |

### Managing Access

```bash
# List current access
gt mesh access list

# Grant access
gt mesh access set gt-friend --role write --rigs project_a,project_b

# Promote to admin
gt mesh access set gt-friend --role admin

# Downgrade
gt mesh access set gt-friend --role read

# Revoke completely
gt mesh revoke gt-friend

# Set up auto-approval for trusted worker
gt mesh auto-approve gt-docker --rigs gt_arcade --max-lines 100
```

### Auto-Approval

For trusted workers whose PRs should merge without manual review:

```yaml
# In mesh.yaml
auto_approve:
  enabled: true
  trusted_gts:
    - id: "gt-docker"
      rigs: ["gt_arcade"]
      conditions:
        max_lines: 100        # Only auto-approve small PRs
        require_tests: true   # Must include tests
```

When auto-approve is enabled for a GT:
1. Their PR is created
2. Mesh daemon detects the PR
3. Checks conditions (size, tests, target rig)
4. If conditions pass: auto-approves and merges
5. If conditions fail: requires manual review

---

## Mesh Rules

Rules are set by the coordinator and enforced by every GT's mesh daemon.

### Work Rules

| Rule | Default | Description |
|------|---------|-------------|
| `branch_format` | `gt/{id}/{issue}-{desc}` | Required branch naming |
| `pr_target` | `dev` | All PRs target this branch |
| `commit_format` | `conventional` | Commit message format |
| `require_issue_reference` | `true` | PRs must reference an issue |
| `max_concurrent_claims` | `3` | Max beads one GT can work on |

### Review Rules

| Rule | Default | Description |
|------|---------|-------------|
| `require_review` | `true` | PRs need approval |
| `min_reviewers` | `1` | Minimum approvals needed |
| `auto_merge_on_approve` | `false` | Auto-merge when approved |
| `allow_self_merge` | `false` | Can a GT merge its own PR? |

### Communication Rules

| Rule | Default | Description |
|------|---------|-------------|
| `require_status_updates` | `true` | Workers must post progress |
| `status_update_interval` | `4h` | How often |
| `announce_claims` | `true` | Broadcast when work claimed |
| `announce_completions` | `true` | Broadcast when work done |

### Security Rules

| Rule | Default | Description |
|------|---------|-------------|
| `no_secrets_in_commits` | `true` | Block .env, credentials |
| `no_force_push` | `true` | Block force pushes |
| `no_direct_push_to_main` | `true` | Block pushes to main/dev |

### Updating Rules

Only the owner can change rules:

```bash
gt mesh rules set max_concurrent_claims 5
gt mesh rules set require_tests true
gt mesh rules set auto_merge_on_approve true
```

Changes propagate to all peers on next sync. Peers' daemons enforce the
new rules automatically.

---

## Shared Beads

### How It Works

When mesh mode is active, beads can be shared across the network:

```bash
# Create a shared bead (visible to all mesh participants with access)
bd create --mesh --rig project_a "Add dark mode"

# List all beads (local + mesh)
bd list --mesh

# List only unclaimed mesh beads
bd list --mesh --unclaimed

# Claim a bead (prevents others from working on it)
bd claim <bead-id>
# Writes to DoltHub `claims` table
# Other GTs see it's taken on next sync

# Work the bead locally, create PR, close when done
bd close <bead-id>
# Status syncs to DoltHub — everyone sees it's done
```

### Claim System (Race Condition Prevention)

```
GT-A sees unclaimed bead #15
GT-B sees unclaimed bead #15
    |                    |
    v                    v
GT-A claims #15      GT-B claims #15
    |                    |
    v                    v
Writes to DoltHub    Writes to DoltHub
    |                    |
    v                    v
DoltHub merge:
  First write wins (GT-A claimed first)
  GT-B's claim is rejected
    |
    v
Next sync:
  GT-A: "You claimed #15, proceed"
  GT-B: "Already claimed by GT-A, skipping"
```

The `claims` table uses DoltHub's merge semantics — first writer wins.
Losers detect the conflict on their next pull and back off.

### DoltHub Schema

```sql
CREATE TABLE shared_beads (
    id VARCHAR(64) PRIMARY KEY,
    source_gt VARCHAR(64) NOT NULL,
    rig VARCHAR(64) NOT NULL,
    title VARCHAR(512) NOT NULL,
    description TEXT,
    priority TINYINT DEFAULT 2,
    status VARCHAR(32) DEFAULT 'open',
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    metadata JSON
);

CREATE TABLE claims (
    bead_id VARCHAR(64) PRIMARY KEY,
    claimed_by VARCHAR(64) NOT NULL,
    claimed_at DATETIME NOT NULL,
    status VARCHAR(32) DEFAULT 'active',
    pr_url VARCHAR(512),
    completed_at DATETIME
);
```

---

## Shared Context

### What Gets Shared

| Type | Description | Auto-share? |
|------|-------------|-------------|
| **Findings** | Patterns, mistakes, solutions, architecture decisions | Yes (if enabled) |
| **Activity** | What each GT is currently working on | Yes |
| **Memory** | MEMORY.md contents | No (opt-in, sensitive) |
| **Skills** | Claude Code skills | Via explicit publish |

### How Context Flows

```
GT-A discovers a pattern:
  "Always use --no-tls for local Dolt connections"
    |
    v
Auto-published to DoltHub `findings` table
    |
    v
GT-B's daemon pulls the finding
    |
    v
GT-B's deacon reviews:
  - Relevant to our rigs? Yes
  - Conflicts with existing memory? No
  - Confidence high enough? Yes (3+ adoptions)
    |
    v
Adopted into GT-B's local memory
    |
    v
GT-B's agents now know the pattern
```

### Adoption Flow

1. **Publish**: Any GT writes to `findings` table
2. **Propagate**: All GTs receive on next sync
3. **Review**: Deacon evaluates relevance
4. **Adopt or Skip**: With reason logged in `adoptions` table
5. **Quality Signal**: Adoption rate = finding quality metric

---

## Mesh Feed

The mesh feed is a real-time activity stream showing what's happening
across all connected Gas Towns.

### Feed Events

```
[12:15] gt-docker joined the mesh (role: worker)
[12:16] gt-docker claimed: "Wire terminal WebSocket" (#1 on OfficeWorld)
[12:30] gt-docker opened PR #42: feat(issue-1): wire terminal WS
[12:45] gt-local approved PR #42
[12:46] PR #42 merged into dev
[12:46] gt-docker completed: "Wire terminal WebSocket" (#1)
[12:50] gt-docker published finding: "WebSocket auth needs token refresh"
[13:00] gt-alex created bead: "Add dark mode" on villa_ai_planogram
[13:01] gt-local accepted contribution from gt-alex
[13:05] gt-local assigned "Add dark mode" to polecat anar
```

### Viewing the Feed

```bash
gt mesh feed                    # Latest 20 events
gt mesh feed --since 1h         # Last hour
gt mesh feed --gt gt-docker     # Filter by GT
gt mesh feed --rig gt_arcade    # Filter by rig
gt mesh feed --type claims      # Filter by event type
```

### Feed Delivery

Feed events are delivered to the local gt mail system. The mesh daemon
injects them as messages addressed to the configured `deliver_to` address.

Options:
- **Real-time**: Every event delivered immediately (noisy)
- **Digest**: Batched every N minutes/hours (recommended)
- **Off**: Check manually with `gt mesh feed`

---

## Mesh Daemon

The mesh daemon is a background process that keeps everything in sync.

### What It Does (every 2 minutes)

1. **Pull** from DoltHub — get new messages, beads, claims, findings
2. **Deliver** new messages to local gt mail
3. **Process** new shared beads (notify mayor for review)
4. **Auto-claim** unclaimed beads (if worker GT with auto-claim enabled)
5. **Enforce** mesh rules (check for violations)
6. **Update** heartbeat (last_seen in peers table)
7. **Push** outbound messages, claims, findings to DoltHub

### Starting/Stopping

```bash
gt mesh daemon start            # Start background daemon
gt mesh daemon stop             # Stop daemon
gt mesh daemon status           # Check daemon health
gt mesh daemon restart          # Restart
```

The daemon is implemented as a deacon dog that runs on each GT.

### Auto-Claim (Worker Mode)

Worker GTs can auto-claim unclaimed beads:

```yaml
daemon:
  auto_claim:
    enabled: true
    max_concurrent: 2
    priority_threshold: 2       # Only P0-P2
    rig_filter: ["gt_arcade"]   # Only from these rigs
```

Flow:
1. Daemon detects unclaimed bead on a rig it has access to
2. Checks: under max_concurrent? Priority meets threshold?
3. Claims the bead in DoltHub
4. Notifies local mayor to start work
5. Mayor slings a polecat

---

## Scaling

### Network Sizes

| Size | Sync Interval | Notes |
|------|--------------|-------|
| 2-5 GTs | 2m | Default. Works great |
| 5-20 GTs | 2-5m | May need longer interval |
| 20-50 GTs | 5m | Consider message TTL |
| 50+ GTs | 10m+ | Need relay architecture |

### Performance Tips

- Set message TTL to auto-delete old messages (30 days default)
- Use digest mode for feed delivery (avoid real-time noise)
- Only share rigs that need collaboration (keep others private)
- Workers should filter auto-claim to specific rigs

---

## Troubleshooting

### "Sync failed: PermissionDenied"
Your Dolt pubkey isn't authorized on the DoltHub org.
Ask the mesh owner to add your key.

### "Invite expired"
Generate a new invite: `gt mesh invite ...`

### "Bead already claimed"
Another GT claimed it first. Find unclaimed work: `bd list --mesh --unclaimed`

### "Daemon not running"
Restart: `gt mesh daemon restart`

### "No messages from other GTs"
Check sync: `gt mesh sync` (force pull/push)
Check peers: `gt mesh peers` (are they online?)
Check logs: `cat /tmp/gt-mesh-sync.log`
