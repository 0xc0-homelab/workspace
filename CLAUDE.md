# 0xc0-homelab — workspace

This directory is the clone of `0xc0-homelab/workspace` and holds the other
repos of the organization as subdirectories. Each one is an independent git
repo with its own remote. **Never make a commit that crosses repos.**

Always start `claude` from here for work touching more than one repo.

## CURRENT PHASE: 1 (Base)

1 Base · 2 Core · 3 Platform · 4 Resilience · 5 HA · 6 Kubernetes

Do not implement anything from later phases even if it fits technically. If
something requires it, say so and stop. Each phase is detailed in
`docs/design.md`.

## Repos

| Directory        | Repo              | Contents                                        |
|------------------|-------------------|-------------------------------------------------|
| `.github/`       | `.github`         | org Terraform + reusable workflows              |
| `claude-config/` | `claude-config`   | marketplace and `homelab` plugin (agents, hooks) |
| `infrastructure/`| `infrastructure`  | Packer + OpenTofu + Ansible + docs              |
| `deployments/`   | `deployments`     | compose/ per VM, clusters/prod/ (Flux, phase 6) |
| `app-*/`         | various           | applications                                    |

Dependency order: `.github` → `infrastructure` → `deployments` → `app-*`.
A downstream change is not merged until the upstream one is applied.

## Changes that cross repos

1. Plan mode first. List what each repo needs before editing anything.
2. One branch per repo, with the same name everywhere.
3. One PR per repo. In the body, link the sibling PRs and state the merge order.
4. `infrastructure` and `.github`: `main` only, PR required, apply behind manual
   approval. The human runs the apply, never you.

## Commits

Conventional Commits, in English, in every repo.

```
<type>(<scope>): <subject>
```

- Types: `feat`, `fix`, `docs`, `refactor`, `chore`, `ci`.
- Scope: the area touched — `firewall`, `zones`, `packer`, `ansible`, `tofu`,
  `compose`, `agents`, `hooks`. Optional, but use it when it is obvious.
- Subject: imperative, lowercase, no trailing period, 72 characters or less.
- `!` after the scope for any change that recreates a resource or breaks a
  contract (`feat(tofu)!: move vm-edge to its own bridge`). Explain it in the
  body.
- Body when the why is not obvious from the subject. Wrap at 72.

No trailers added by tooling: **never** `Co-Authored-By: Claude`, never a
generated-by footer. The commit is signed by whoever runs it.

## Branches and pull requests

Branch names mirror the commit types: `<type>/<slug>`.

```
feat/vault-transit-8200
fix/edge-bind-address
chore/bump-opentofu
docs/zone-matrix-rewrite
```

The same branch name in every repo the change touches, and only in those.

PRs are **squash merged**, so the PR title becomes the commit on `main`: write
it as a Conventional Commit subject, same rules as a commit message.

The PR body links the sibling PRs and states the merge order. No trailers
added by tooling: no generated-by footer, same rule as commits.

## Autonomy

Without asking: create branches, commit, push a branch, open issues, open a
**draft** PR, and add items to the project board.

Ask first: marking a PR ready for review, merging, creating, renaming or
deleting a repo, changing organization settings, and anything that applies
infrastructure. The apply is launched by the human, always.

The rule behind it: work freely while nothing is presented as final.

## Git identity

Every repo under `~/git/github/0xc0-homelab/` commits as
`sergioaten <me@sergioaten.cloud>`.

It is not set per repo. `gitconfig` in this repo holds the identity and the
shared defaults, and a single `includeIf` in `~/.gitconfig` points at it:

```gitconfig
[includeIf "gitdir:~/git/github/0xc0-homelab/"]
	path = ~/git/github/0xc0-homelab/workspace/gitconfig
```

Scoping by path means a repo cloned later by `bootstrap.sh` gets the identity
with no extra step, and nothing outside this tree is affected. On a fresh
machine, that `includeIf` is the only thing to add by hand.

## Tooling

**Nothing is installed system-wide. Every tool comes from `mise`.**

No `brew install`, no `apt install`, no `npm -g`, no `pip install`, no
downloading a binary into `/usr/local/bin`. If a tool is missing, it gets
declared in the repo's `mise.toml` with a pinned version, and that is the fix.

- Each repo carries its own `mise.toml` and declares **everything** it needs,
  including tools the workspace also declares. A repo is cloned alone by CI,
  so it cannot lean on a parent config.
- Versions are pinned exactly. No `latest`, no version ranges.
- Bumping a version is its own commit: `chore(mise): bump opentofu to X.Y.Z`.
- `mise.local.toml` is for personal overrides and is never committed.

## Rules that apply in every repo

- **Everything written is in English**: file contents, file and directory
  names, code comments, commit messages, branch names, PR titles and bodies,
  docs. The conversation with the operator is in Spanish.
- No `tofu apply`, `tofu destroy` or `ansible-playbook` without `--check`.
- Secrets with SOPS+age. An unencrypted file holding sensitive material is a bug.
- Before proposing any IP or subnet, check it against
  `infrastructure/docs/zones.md`. There are reserved ranges that are off limits.
- What is discarded stays discarded. The list and the reasons are in
  `docs/design.md`. Do not reopen it unless the human explicitly asks.

## Status

The design is closed (`docs/design.md`). What exists so far is configuration
scaffolding: CLAUDE.md files, the zone matrix, the agents and the skills.
**Not a single line of Terraform, Packer or Ansible exists yet.**

All five repos are initialised locally on `main` with an initial commit, but
**none of them has a remote**: the organization is still empty. Nothing can be
pushed until the repos exist on GitHub.

Two consequences worth remembering:

- The `homelab` plugin is declared in `.claude/settings.json` but its
  marketplace source repo does not exist yet, so the agents, the skills and
  the hooks are **not active**. The guardrails are written, not enforced.
- `bootstrap.sh` cannot clone anything yet either.

Next steps, in order: create the org repos with Terraform from `.github/`,
push, then generate `infrastructure/firewall.tf` from the matrix in
`infrastructure/docs/zones.md`.
