# Mistakes Log — Mayor

## 2026-03-04: Nudged dead session, instructions dumped to raw bash

**What happened:**
- Mayor nudged `villa_ai_planogram/manager` with priority instructions
- `gt crew status` showed "running" — Mayor assumed Claude was alive
- In reality, the Claude process inside the tmux pane had exited/crashed
- The tmux session was still alive but sitting at a bare bash prompt
- `gt nudge` sent the multi-line instructions via tmux send-keys
- Bash tried to execute each line as a shell command — all failed with syntax errors
- Mayor reported to the user that the manager was instructed and working
- User tmux'd in and found nothing had happened — complete silent failure

**Root cause:**
- Mayor trusted `gt crew status` "running" without verifying the Claude process
- No verification step after nudging (no peek to confirm acknowledgment)

**Fix — MANDATORY pre-nudge checklist:**
1. Check tmux pane is alive: `tmux list-panes -t <session> -F '#{pane_dead}'` must return `0`
2. If dead: `gt crew restart <name>` BEFORE nudging
3. After nudging: `gt peek <target>` to confirm Claude received and acknowledged
4. If peek shows raw bash output or no Claude activity → session is dead, restart

**Severity:** HIGH — causes total work loss and false reporting to user
