# Agent Instructions

## Project Overview

<!-- Update with your project description -->

This project is managed by multiple Gas Town instances.

## Multi-GT Worker Coordination

| Instance | Role |
|----------|------|
| `gt-local` | Parent coordinator -- creates issues, reviews PRs, merges, releases |
| `gt-docker` | Worker -- picks up issues, writes code, creates PRs |

### For Worker GTs

1. **Find assigned work:**
   ```bash
   gh issue list --repo <org>/<repo> --label "gt-to:<your-id>,gt-status:pending"
   ```

2. **Claim:** Relabel `gt-status:pending` -> `gt-status:claimed`, comment on issue.

3. **Branch:** `gt/<your-id>/<issue-number>-<short-desc>`

4. **PR:** Target `dev`, add label `needs-review,gt-from:<your-id>`, reference issue with `Closes #N`.

5. **Done:** Relabel `gt-status:claimed` -> `gt-status:done`.

### Rules for Workers

- NEVER push directly to `dev` or `main`
- NEVER merge your own PRs
- NEVER create releases, tags, or modify CI/CD
- NEVER commit `.env` files or secrets
- All work goes through PRs reviewed by `gt-local`

### If Blocked

Comment on the issue: `@gt-local BLOCKED: <reason>`

## Issue Tracking with bd (beads)

This project uses **bd (beads)** for issue tracking.

```bash
bd ready --json          # Check for ready work
bd create "Title" -t task -p 1 --json   # Create issue
bd update <id> --claim --json           # Claim work
bd close <id> --reason "Done" --json    # Complete
```

## Landing the Plane (Session Completion)

When ending a work session:

1. File issues for remaining work
2. Run quality gates (tests, lint)
3. Update issue status
4. **PUSH TO REMOTE** (mandatory)
5. Hand off context

Work is NOT complete until `git push` succeeds.
