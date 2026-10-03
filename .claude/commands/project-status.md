---
description: Read the org project board — what is in progress, blocked and next
allowed-tools: Bash
---

The org project (`0xc0-labs`, #1) is the source of truth for the state of
work. Decisions are not here: they live in `docs/design.md`.

!`gh project item-list 1 --owner 0xc0-labs --limit 200 --format json --jq '.items | if length == 0 then "The board is empty." else (group_by(.status // "No status")[] | "\n## \(.[0].status // "No status")", (.[] | "- \(.repository // "draft" | sub("https://github.com/0xc0-labs/"; "")) — \(.title)\(if .content.number then " (#\(.content.number))" else "" end)")) end' 2>&1`

Summarise in a few lines: what is in progress, what is blocked and on what, and
what the next items are.
