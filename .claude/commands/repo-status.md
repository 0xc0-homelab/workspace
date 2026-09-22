---
description: Branch and working-tree state of every 0xc0-homelab repo in one shot
allowed-tools: Bash
---

State of every repo in the workspace:

!`for d in . .github claude-config infrastructure deployments; do name=$([ "$d" = "." ] && echo "workspace" || echo "$d"); if [ -d "$d/.git" ]; then b=$(git -C "$d" branch --show-current 2>/dev/null || echo "-"); n=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d " "); u=$(git -C "$d" log --oneline @{u}.. 2>/dev/null | wc -l | tr -d " "); printf "%-16s %-14s %2s change(s)  %2s unpushed\n" "$name" "$b" "$n" "$u"; elif [ -d "$d" ]; then printf "%-16s %s\n" "$name" "present, not a git repo"; else printf "%-16s %s\n" "$name" "not cloned"; fi; done`

Summarise in two or three lines: which repos have uncommitted work, which are
ahead of their remote, and which are not cloned yet. Do not repeat the table.
If everything is clean, say so in one line.
