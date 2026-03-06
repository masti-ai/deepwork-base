# GT Mesh Stress Test Results

**Date:** 2026-03-06
**Tester:** gt-local (Mayor, planner role)
**Version:** v0.1.0+dev (post 1c6796f)

## Summary: 24/24 PASS (all 12 commands tested)

## Round 1: Core Commands (original)

| # | Test | Command | Result | Notes |
|---|------|---------|--------|-------|
| 1 | Fresh init | `gt mesh init --role coordinator` | PASS | Creates mesh.yaml, registers peer |
| 2 | Idempotent init | `gt mesh init` (run again) | PASS | Preserves existing mesh.yaml, reads identity from it |
| 3 | Status | `gt mesh status` | PASS | Shows peers table, unread count |
| 4 | Send valid | `gt mesh send gt-docker "subject" "body"` | PASS | Message stored and pushed to DoltHub |
| 5 | Send missing args | `gt mesh send` | PASS | Shows usage help, exit 1 |
| 6 | Send self | `gt mesh send gt-local "test" "body"` | PASS | Self-send works, appears in own inbox |
| 7 | Inbox unread | `gt mesh inbox` | PASS | Shows unread only |
| 8 | Inbox all | `gt mesh inbox --all` | PASS | Shows all messages |
| 9 | Force sync | `gt mesh sync` | PASS | Pull + push + stats |
| 10 | Help | `gt mesh help` | PASS | Shows all commands |

## Round 2: Invite & Join

| # | Test | Result | Notes |
|---|------|--------|-------|
| 11 | Invite (7d write) | PASS | Generates MESH-XXXX-YYYY, stored in invites table |
| 12 | Invite (permanent admin) | PASS | expires_at = NULL, code works |
| 13 | Join invalid format | PASS | Rejects "INVALID-CODE" with helpful error |
| 14 | Join non-existent code | PASS | "Invite code not found" (after CSV header fix) |

## Round 3: Access, Rules, Feed, Daemon

| # | Test | Result | Notes |
|---|------|--------|-------|
| 15 | Access list | PASS | Shows peers, pending invites, formatted columns |
| 16 | Access set role | PASS | Updates peer role in DoltHub |
| 17 | Access revoke | PASS | Sets status to 'revoked' (no-op on non-existent) |
| 18 | Rules list | PASS | 8 defaults in 3 categories, clean display |
| 19 | Rules set (existing) | PASS | Preserves category ('work' stays 'work') |
| 20 | Rules set (new) | PASS | New rules get category 'custom' |
| 21 | Rules reset | PASS | Deletes all, re-seeds 8 defaults |
| 22 | Feed --since 24h | PASS | Full activity timeline with timestamps |
| 23 | Feed --gt --limit | PASS | Filters work correctly |
| 24 | Daemon lifecycle | PASS | start -> status -> stop -> double-start warns |

## Round 4: Edge Cases & Error Handling

| # | Test | Result | Notes |
|---|------|--------|-------|
| - | Unknown subcommand | PASS | "Unknown command" + help hint |
| - | Bad role on init | PASS | Rejects invalid role |
| - | No mesh.yaml | PASS | "Not in a mesh" error |
| - | Priority messages | PASS | P0 shows [P0!], P2 default [P2] |
| - | Main dispatcher | PASS | All 12 subcommands route correctly |

## Bugs Found and Fixed

### Round 1 (original, commits ca3f38b..4af60b6)
1. **mesh init overwrote mesh.yaml** — Lost custom sections. Fixed: skip if file exists.
2. **Dolt merge conflicts on re-init** — REPLACE INTO caused conflicts. Fixed: auto-resolve --theirs.
3. **set -e false failures** — Benign dolt non-zero exits. Fixed: removed set -e.
4. **Unimplemented commands show raw bash error** — Fixed: friendly error in dispatcher.

### Round 2 (E2E, commit a4c0a30)
5. **mesh-init requires --github on re-init** — Even when mesh.yaml exists with identity. Fixed: read identity from existing mesh.yaml first.
6. **mesh-join validates identity before code** — Asked for --github before checking if code exists. Fixed: reordered so code validation comes first.
7. **CSV header treated as data** — `tail -1` on dolt CSV output returns column header when query returns 0 rows. Fixed: `tail -n +2 | head -1` across ALL scripts.
8. **rules set loses category** — COALESCE returned header text. Fixed: use `tail -n +2 | head -1`.

## HOP URI vs mesh.yaml Identity (Design Note)

**mesh.yaml** is the local config source of truth. **HOP URI** (`hop://email/handle/`) is for cross-mesh federation. They complement each other:
- mesh.yaml defines who you are locally (id, role, owner, DoltHub connection)
- HOP URI is the portable identity for addressing GTs across different meshes
- A mesh.yaml can include a `hop_uri` field if the GT participates in Wasteland federation
