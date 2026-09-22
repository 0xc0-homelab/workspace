---
description: Create the same branch across the repos a change touches
argument-hint: <branch-name> [repo ...]
allowed-tools: Bash
---

Create the branch `$1` in the repos given after it. With no repos named, ask
which ones the change touches — do not default to all of them.

Cross-repo rules from `CLAUDE.md` that apply here:

- One branch per repo, **the same name in all of them**.
- Never a commit that crosses repos.
- Only branch the repos the change actually touches.

Current state:

!`for d in . .github claude-config infrastructure deployments; do name=$([ "$d" = "." ] && echo "workspace" || echo "$d"); if [ -d "$d/.git" ]; then printf "%-16s on %s\n" "$name" "$(git -C "$d" branch --show-current 2>/dev/null)"; else printf "%-16s %s\n" "$name" "not a git repo"; fi; done`

For each requested repo, in order: confirm the working tree is clean, then
`git -C <repo> checkout -b $1`. If a tree is dirty or the branch already
exists, stop and report it rather than forcing anything.

Finish with one line per repo saying what happened.
