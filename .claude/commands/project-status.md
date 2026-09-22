---
description: Read the org project board — what is in progress, blocked and next
allowed-tools: Bash
---

The org project (`0xc0-homelab`, #1) is the source of truth for the state of
work. Decisions are not here: they live in `docs/design.md`, and the current
phase in `CLAUDE.md`.

!`gh project item-list 1 --owner 0xc0-homelab --limit 200 --format json --jq '.items | if length == 0 then "The board is empty." else (group_by(.status // "No status")[] | "\n## \(.[0].status // "No status")", (.[] | "- [\(.phase // "no phase")] \(.repository // "draft" | sub("https://github.com/0xc0-homelab/"; "")) — \(.title)\(if .content.number then " (#\(.content.number))" else "" end)")) end' 2>&1`

Current phase declared in `CLAUDE.md`:

!`grep -m1 '^## CURRENT PHASE' CLAUDE.md`

Summarise in a few lines: what is in progress, what is blocked and on what, and
what the next item for the current phase is. Flag, separately, any item whose
phase is later than the current one — it should not be in progress.
