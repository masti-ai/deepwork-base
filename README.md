# GT Mesh

**Connect multiple Gas Towns into a collaborative coding network.**

GT Mesh is a plugin for [Gas Town](https://github.com/Deepwork-AI/gasclaw) that lets developers invite each other into a shared AI-powered workspace. Your friend joins your mesh, creates tasks (beads), and your agents build the features. Multiplayer vibe coding.

## How It Works

```
You (running Gas Town)                    Your friend (running Gas Town)
       |                                          |
  gt mesh init                               gt mesh join MESH-A7K9
       |                                          |
  gt mesh invite --expires 24h                    |
       |                                          |
  Share code: MESH-A7K9  ────────────────>  Pastes code
       |                                          |
       |                                   Can see your project
       |                                   Creates beads (tasks)
       |                                          |
  Mayor reviews  <──── mail sync ────────  "Add dark mode"
       |
  Accepts -> polecat builds it
       |
  "PR merged" ─────── mail sync ────────>  Gets notified
```

## Quick Start

### Install the plugin

```bash
# From inside your Gas Town directory
gt plugin install Deepwork-AI/gt-mesh

# Or manually
git clone https://github.com/Deepwork-AI/gt-mesh.git .gt-mesh
```

### Initialize mesh

```bash
gt mesh init
# Creates mesh.yaml — your identity on the network
# Sets up DoltHub sync for cross-GT communication
```

### Invite a friend

```bash
gt mesh invite --role contributor --rigs my_project --expires 7d
# Output: MESH-A7K9-XPLN
# Share this code with your friend
```

### Join a mesh (friend's side)

```bash
gt mesh join MESH-A7K9-XPLN
# Connects to the mesh, syncs state, can see shared rigs
```

## Architecture

```
              ┌──────────────────────┐
              │  DoltHub (backbone)  │
              │  deepwork/gt-mesh    │
              │                      │
              │  messages | peers    │
              │  channels | access   │
              │  skills   | invites  │
              └──────────┬───────────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
     ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
     │  GT #1  │   │  GT #2  │   │  GT #3  │
     │ (owner) │   │(contrib)│   │(worker) │
     └─────────┘   └─────────┘   └─────────┘
```

Every Gas Town syncs with one central DoltHub database. No point-to-point connections. Scales linearly to 20+ nodes.

## What Can Mesh Members Do?

| Role | Read code | Create beads | Chat with agents | Execute work | Merge PRs |
|------|-----------|-------------|-----------------|-------------|-----------|
| **Owner** | Yes | Yes | Yes | Yes | Yes |
| **Contributor** | Yes (shared rigs) | Yes (review gate) | Via mesh mail | No (owner's polecats do it) | No |
| **Worker** | Yes (assigned rigs) | Yes | Via mesh mail | Yes (own polecats) | No (owner reviews) |
| **Reviewer** | Yes | Yes | Via mesh mail | No | Yes |

## Contribution Flow

Contributors don't get direct access to your agents or filesystem. They use their own Gas Town to understand your code, then create beads (tasks) that flow through a review gate:

1. Contributor creates a bead on your shared rig
2. Your Mayor gets a mesh mail notification
3. You accept or reject the contribution
4. If accepted, your polecats pick it up and build it
5. Contributor gets notified when the PR is ready

## Shared Skills

Skills are shared across the mesh. When a node publishes a skill, other nodes can adopt it:

```bash
# List skills available on the mesh
gt mesh skills

# Install a skill from the mesh
gt mesh skill install excalidraw-diagram-generator

# Share one of your skills to the mesh
gt mesh skill publish my-custom-skill
```

## Mesh Commands

```bash
# Setup
gt mesh init                          # Initialize mesh plugin
gt mesh join <code>                   # Join an existing mesh

# Invites & Access
gt mesh invite [--role R] [--rigs R]  # Generate invite code
gt mesh revoke <gt-id>                # Revoke access
gt mesh access list                   # Show access table

# Communication
gt mesh send <gt-id> "subject" "body" # Send cross-GT message
gt mesh inbox                         # Check incoming messages
gt mesh peers                         # List connected Gas Towns

# Contributions
gt mesh contributions                 # Pending contributions to review
gt mesh accept <bead-id>              # Accept a contribution
gt mesh reject <bead-id> --reason "." # Reject with reason

# Skills
gt mesh skills                        # List mesh skills
gt mesh skill install <name>          # Install from mesh
gt mesh skill publish <name>          # Share to mesh

# Status
gt mesh status                        # Full mesh dashboard
gt mesh sync                          # Force sync now
gt mesh log                           # Recent sync activity
```

## mesh.yaml

Your identity and mesh configuration:

```yaml
version: 1

instance:
  id: "gt-local"
  name: "My Gas Town"
  role: "coordinator"       # coordinator | worker | contributor
  owner:
    name: "Your Name"
    email: "you@example.com"

dolthub:
  org: "deepwork"
  database: "gt-mesh-mail"
  sync_interval: "2m"

shared_rigs:
  - name: "my_project"
    visibility: "invite-only"
    accept_contributions: true

defaults:
  contributor_expiry: "7d"
  auto_accept_beads: false
```

## Scaling

| Mesh Size | Sync Load | Works? |
|-----------|----------|--------|
| 2-5 GTs | Light | Great |
| 5-20 GTs | Moderate | Good |
| 20-50 GTs | Heavy | Needs longer sync intervals |
| 50+ GTs | Too heavy | Needs relay architecture |

GT Mesh uses a hub-and-spoke model via DoltHub. All nodes sync to one database. Messages are append-only — no merge conflicts. Adding a node = one more sync client.

## Related Projects

- [Gas Town](https://github.com/steveyegge/gastown) — The multi-agent workspace GT Mesh extends
- [Gasclaw](https://github.com/Deepwork-AI/gasclaw) — Single-container Gas Town deployment
- [Beads](https://github.com/steveyegge/beads) — Git-backed issue tracking used by GT Mesh
- [Dolt](https://github.com/dolthub/dolt) — Git-for-data database powering the mesh backbone

## License

MIT

---

Built by [Deepwork AI](https://github.com/Deepwork-AI) with [Gas Town](https://github.com/steveyegge/gastown).
