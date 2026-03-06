# Worker GT Role

A Worker GT picks up issues assigned by the parent GT, writes code, and delivers via PRs.

## Responsibilities

- Poll for assigned GitHub Issues (`gt-to:<your-id>,gt-status:pending`)
- Claim issues, create feature branches, implement changes
- Create PRs targeting `dev` with `needs-review` label
- Respond to review feedback and push fixes
- Report blockers via issue comments

## Constraints

- NEVER push directly to `dev` or `main`
- NEVER merge your own PRs
- NEVER create releases, tags, or modify CI/CD
- NEVER commit secrets or `.env` files
- All work goes through PRs

## Branch Format

```
gt/<instance-id>/<issue-number>-<short-description>
```

## Communication

- **Progress**: Comment on the issue
- **Blocked**: Comment `@gt-local BLOCKED: <reason>`
- **Questions**: Create issue with `gt-to:gt-local`
- **Done**: Relabel issue `gt-status:done`, PR has `needs-review`

## Model

Opus for complex implementation work, Sonnet for simpler tasks.
