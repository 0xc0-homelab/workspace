---
description: Show the declared phase in every repo, or advance all of them at once
argument-hint: "[new phase number]"
allowed-tools: Bash
---

The current phase is declared in three CLAUDE.md files, one per repo that
gates on it, and shown publicly on the org profile. The duplication is
deliberate — a repo cloned on its own has to carry its own gate — so these
four must never disagree.

Declared right now:

!`for f in CLAUDE.md infrastructure/CLAUDE.md gitops/CLAUDE.md; do if [ -f "$f" ]; then printf "%-28s %s\n" "$f" "$(grep -m1 '^## CURRENT PHASE' "$f" || echo 'NOT DECLARED')"; else printf "%-28s %s\n" "$f" "missing"; fi; done; printf "%-28s %s\n" ".github/profile/README.md" "$(grep -m1 '^\*\*Current phase:' .github/profile/README.md 2>/dev/null || echo 'NOT DECLARED')"`

Phases: 1 Base · 2 Cluster · 3 Platform · 4 Resilience · 5 HA · 6 Applications.
Each one is defined in `docs/design.md`.

**With no argument**: report whether the four agree. If they diverge, say so
plainly and name the odd one out — that is a bug, not a detail.

**With a phase number in `$1`**: this is a deliberate project milestone, not a
routine edit. Before touching anything, confirm with the operator that the
previous phase is actually finished, quoting what `docs/design.md` requires of
it. Phase 2 in particular is not done until the restore has been timed and
written down.

Once confirmed, update the `## CURRENT PHASE` heading in the three CLAUDE.md
files and the `**Current phase:**` line in `.github/profile/README.md`, plus any
prose in them that names the current phase. Each repo gets its own commit,
never one that crosses repos:

```
chore: advance to phase $1
```

Then report the four files and stop. Do not start implementing anything from
the new phase in the same pass.
