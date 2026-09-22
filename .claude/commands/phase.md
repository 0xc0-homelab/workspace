---
description: Show the declared phase in every repo, or advance all of them at once
argument-hint: "[new phase number]"
allowed-tools: Bash
---

The current phase is declared in three files, one per repo that gates on it.
The duplication is deliberate — a repo cloned on its own has to carry its own
gate — so these three must never disagree.

Declared right now:

!`for f in CLAUDE.md infrastructure/CLAUDE.md deployments/CLAUDE.md; do if [ -f "$f" ]; then printf "%-28s %s\n" "$f" "$(grep -m1 '^## CURRENT PHASE' "$f" || echo 'NOT DECLARED')"; else printf "%-28s %s\n" "$f" "missing"; fi; done`

Phases: 1 Base · 2 Core · 3 Platform · 4 Resilience · 5 HA · 6 Kubernetes.
Each one is defined in `docs/design.md`.

**With no argument**: report whether the three agree. If they diverge, say so
plainly and name the odd one out — that is a bug, not a detail.

**With a phase number in `$1`**: this is a deliberate project milestone, not a
routine edit. Before touching anything, confirm with the operator that the
previous phase is actually finished, quoting what `docs/design.md` requires of
it. Phase 2 in particular is not done until the restore has been timed and
written down.

Once confirmed, update the `## CURRENT PHASE` heading in all three files, plus
any prose in them that names the current phase. Each repo gets its own commit,
never one that crosses repos:

```
chore: advance to phase $1
```

Then report the three files and stop. Do not start implementing anything from
the new phase in the same pass.
