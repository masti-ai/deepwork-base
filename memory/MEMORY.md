# Mayor Memory

## Critical Rules — Learned from Mistakes
See [mistakes.md](mistakes.md) for full incident log.

### Pre-Nudge Verification (MANDATORY)
**NEVER nudge or send instructions to a crew/polecat without verifying the Claude process is alive inside the tmux pane.**
- `gt crew status` showing "running" only means the **tmux session** exists — NOT that Claude is running inside it
- ALWAYS check: `tmux list-panes -t <session> -F '#{pane_dead}'` → must return `0`
- If pane is dead (`1`), restart the session FIRST: `gt crew restart <name>`, then nudge
- After nudging, peek to confirm the agent acknowledged: `gt peek <target>`

### Refinery Instability
- gt_arcade refinery keeps dying (exit code 1) — likely test_command misconfiguration
- Pattern: kill stale tmux session, then `gt rig start` to respawn

## Rig Registry
| Rig | Prefix | Repo | Svc Registry | Notes |
|-----|--------|------|-------------|-------|
| villa_ai_planogram | vap- | Deepwork-AI/ai-planogram | vap-8k7 | Planogram platform |
| villa_alc_ai | vaa- | Deepwork-AI/alc-ai-villa | vaa-wuy | ALC AI |
| gt_arcade | gta- | freebird-ai/gt-arcade | gta-e1d | Gamified dashboard |

## Multi-GT Coordination (updated 2026-03-06)
- **gt-local** (this GT) = Parent / Reviewer / Coordinator
- **gt-docker** = Worker (picks up issues, creates PRs, does NOT merge)
- Communication via GitHub Issues (`gt-task` labels) and PRs (`needs-review`)
- Worker instructions at `/home/pratham2/gt/mayor/multi-gt-worker-instructions.md`
- Worker branch format: `gt/<instance-id>/<issue-number>-<desc>`
- Workers NEVER push to dev/main directly — always via PR
- gt-local reviews, approves, and merges all PRs
- Labels created on both repos: `gt-task`, `gt-from:*`, `gt-to:*`, `gt-status:*`, `needs-review`, `approved`, `priority:*`
- Beads opt-in to GitHub sync via `gh-sync` label

## Release Workflow (added 2026-03-06)
- All rig work goes to `dev` branch, NEVER directly to `main`
- After 2-3 epics/convoys complete, Mayor creates consolidated PR: `dev` -> `main`
- PR must use release body format from `/home/pratham2/gt/CLAUDE.md`
- Reviewer crew member must approve before merge
- `dev` = staging, `main` = production (CI/CD is future TODO — AWS pipeline)
- Existing templates: `.github/PULL_REQUEST_TEMPLATE.md`, `CONTRIBUTING.md`, `docs/CONTRIBUTION_SYSTEM_SUMMARY.md`
- GitHub default branch should be set to `dev` (requires admin access)

## Project Notes
- GitHub org: `Deepwork-AI` (repos transferred from pratham-bhatnagar 2026-03-06)
- freebird-ai is admin in Deepwork-AI org
- Teams: "Villa Market Agents team" (ai-planogram + alc-ai-villa), "Builders"
- GitHub Projects (all on Deepwork-AI org):
  - #4 Villa AI Planogram Kanban | #2 Villa Planogram Roadmap
  - #5 Villa ALC AI Kanban | #6 Villa ALC AI Roadmap
- Kanban template: Status (Backlog/Ready/In progress/In review/Done), Priority (P0/P1/P2), Size, Estimate, Start/Target date
- GitHub sync at epic level, not every bead. Summary view only.
- Need `read:project,project` scope on gh token to access Projects API
- Versioning: ai-planogram starts v1.0.0, alc-ai-villa starts v0.1.0, gt-arcade starts v0.1.0
- Releases created after every dev->main PR merge. Tag + `gh release create`.
- Cloud dev env — all services need tunnels until CI/CD is set up
- Rig names cannot contain hyphens (use underscores)
- Default branch on all rigs is now `dev`
