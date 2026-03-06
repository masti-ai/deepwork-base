# Worker GT Setup Instructions

**For:** Any Gas Town instance that will work as a worker under `gt-local` (the parent coordinator).

---

## 1. Identity Configuration

Add to your `mayor/town.json`:

```json
{
  "type": "town",
  "version": 3,
  "name": "gt",
  "owner": "prathamonchain@gmail.com",
  "instance_id": "gt-docker",
  "github_sync": {
    "enabled": true,
    "poll_interval_seconds": 180,
    "accept_tasks_from": ["gt-local"]
  }
}
```

Change `instance_id` to your unique ID (e.g., `gt-docker`, `gt-cloud`, `gt-dev2`).

---

## 2. Add to your CLAUDE.md

Add this section to your Gas Town's `CLAUDE.md`:

```markdown
## Worker GT Rules

**This GT (`gt-docker`) is a worker instance. `gt-local` is the parent coordinator.**

### Your role
- Pick up GitHub Issues assigned to you (labeled `gt-to:gt-docker`)
- Write code, create PRs targeting `dev` branch
- Respond to review feedback from gt-local
- You do NOT merge PRs, create releases, or push to `main`

### Workflow

1. **Poll for work:**
   ```bash
   gh issue list --repo Deepwork-AI/ai-planogram --label "gt-to:gt-docker,gt-status:pending"
   gh issue list --repo Deepwork-AI/alc-ai-villa --label "gt-to:gt-docker,gt-status:pending"
   ```

2. **Claim an issue:**
   ```bash
   gh issue edit <N> --repo Deepwork-AI/<repo> \
     --remove-label "gt-status:pending" --add-label "gt-status:claimed"
   ```
   Comment on the issue: "Claimed by gt-docker. Starting work."

3. **Create a feature branch:**
   ```
   gt/gt-docker/<issue-number>-<short-description>
   ```
   Example: `gt/gt-docker/15-fix-test-runner`

4. **Do the work.** Follow the acceptance criteria in the issue.

5. **Create a PR targeting `dev`:**
   ```bash
   gh pr create --repo Deepwork-AI/<repo> --base dev \
     --title "<type>(issue-<N>): <description>" \
     --label "needs-review,gt-from:gt-docker" \
     --body "Closes #<N>\n\n## Changes\n- ...\n\n## Testing\n- ..."
   ```

6. **Mark the issue done:**
   ```bash
   gh issue edit <N> --repo Deepwork-AI/<repo> \
     --remove-label "gt-status:claimed" --add-label "gt-status:done"
   ```

7. **Wait for review.** gt-local will review and either:
   - Approve and merge
   - Request changes (you fix and push to the same branch)

### Rules

- **NEVER** push directly to `dev` or `main`
- **NEVER** merge your own PRs
- **NEVER** create releases or tags
- **NEVER** modify `.github/workflows/` without explicit approval
- **NEVER** commit `.env` files or secrets
- All work goes through PRs with the `needs-review` label
- Use conventional commit format: `<type>(issue-<N>): <description>`
- Types: `feat`, `fix`, `refactor`, `chore`, `test`, `docs`

### Repos you have access to

| Repo | Description |
|------|-------------|
| `Deepwork-AI/ai-planogram` | AI planogram generation (Python/FastAPI + Next.js + React Native) |
| `Deepwork-AI/alc-ai-villa` | AI alcohol concierge (Python/FastAPI + Next.js + Google ADK + AWS) |

### Branch structure

- `main` — production (DO NOT TOUCH)
- `dev` — working branch (PR target)
- `gt/gt-docker/*` — your feature branches

### If you are blocked

Comment on the issue:
```
@gt-local BLOCKED: <reason>
```

Or create a new issue asking for help:
```bash
gh issue create --repo Deepwork-AI/<repo> \
  --title "Question: <topic>" \
  --label "gt-task,gt-from:gt-docker,gt-to:gt-local,gt-status:pending" \
  --body "I need help with..."
```

### Checking for review feedback

After creating a PR, periodically check for review comments:
```bash
gh pr view <N> --repo Deepwork-AI/<repo> --comments
gh pr checks <N> --repo Deepwork-AI/<repo>
```

If changes are requested, fix them on the same branch and push. Do NOT create a new PR.
```

---

## 3. GitHub Authentication

The worker GT needs `gh` CLI authenticated with access to `Deepwork-AI` repos.

```bash
gh auth login
gh auth status  # verify access
gh repo list Deepwork-AI  # verify org access
```

Required scopes: `repo`, `read:org`, `project`

If using a fine-grained PAT, ensure it has:
- Repository access to `ai-planogram` and `alc-ai-villa`
- Permissions: Contents (read/write), Issues (read/write), Pull requests (read/write), Metadata (read)

---

## 4. Repo Setup

Clone both repos:

```bash
git clone git@github.com:Deepwork-AI/ai-planogram.git
git clone git@github.com:Deepwork-AI/alc-ai-villa.git
```

Set up your Git identity:

```bash
git config user.name "gt-docker"
git config user.email "prathamonchain@gmail.com"
```

Verify you can push (to a test branch, not dev/main):

```bash
cd ai-planogram
git checkout -b gt/gt-docker/test-access
git commit --allow-empty -m "chore(test): verify push access"
git push origin gt/gt-docker/test-access
git push origin --delete gt/gt-docker/test-access  # cleanup
```

---

## 5. Daily Workflow

On startup or at regular intervals:

```bash
# 1. Check for assigned work
gh issue list --repo Deepwork-AI/ai-planogram --label "gt-to:gt-docker,gt-status:pending"
gh issue list --repo Deepwork-AI/alc-ai-villa --label "gt-to:gt-docker,gt-status:pending"

# 2. Check for review feedback on open PRs
gh pr list --repo Deepwork-AI/ai-planogram --author "@me" --state open
gh pr list --repo Deepwork-AI/alc-ai-villa --author "@me" --state open

# 3. Check if any PRs need revision
gh pr list --repo Deepwork-AI/ai-planogram --label "changes-requested"
gh pr list --repo Deepwork-AI/alc-ai-villa --label "changes-requested"
```

---

## 6. Quick Reference

| Action | Command |
|--------|---------|
| Find work | `gh issue list --repo Deepwork-AI/<repo> --label "gt-to:gt-docker,gt-status:pending"` |
| Claim issue | `gh issue edit <N> --remove-label "gt-status:pending" --add-label "gt-status:claimed"` |
| Create branch | `git checkout -b gt/gt-docker/<N>-<desc>` |
| Create PR | `gh pr create --base dev --label "needs-review,gt-from:gt-docker"` |
| Mark done | `gh issue edit <N> --remove-label "gt-status:claimed" --add-label "gt-status:done"` |
| Ask for help | Create issue with `gt-to:gt-local,gt-status:pending` |

---

**Parent GT:** `gt-local`
**Organization:** `Deepwork-AI`
**Contact:** prathamonchain@gmail.com
