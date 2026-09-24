# 0xc0-homelab — workspace

This directory is the clone of `0xc0-homelab/workspace` and holds the other
repos of the organization as subdirectories. Each one is an independent git
repo with its own remote. **Never make a commit that crosses repos.**

Always start `claude` from here for work touching more than one repo.

## CURRENT PHASE: 2 (Cluster)

1 Base · 2 Cluster · 3 Platform · 4 Resilience · 5 HA · 6 Applications

Do not implement anything from later phases even if it fits technically. If
something requires it, say so and stop. Each phase is detailed in
`docs/design.md`.

## Repos

| Directory        | Repo              | Contents                                        |
|------------------|-------------------|-------------------------------------------------|
| `.github/`       | `.github`         | org Terraform + reusable workflows              |
| `claude-config/` | `claude-config`   | marketplace and `homelab` plugin (agents, hooks, skills) |
| `infrastructure/`| `infrastructure`  | Packer + OpenTofu + Ansible + docs              |
| `gitops/`        | `gitops`          | clusters/prod/: ArgoCD manifests (phase 2)        |
| `app-*/`         | various           | applications                                    |

Dependency order: `.github` → `infrastructure` → `gitops` → `app-*`.
A downstream change is not merged until the upstream one is applied.

## Changes that cross repos

1. Plan mode first. List what each repo needs before editing anything.
2. One branch per repo, with the same name everywhere.
3. One PR per repo. In the body, link the sibling PRs and state the merge order.
4. `infrastructure` and `.github`: `main` only, PR required, apply behind manual
   approval. The human runs the apply, never you.

## Tracking — mandatory

The org project board (`github.com/orgs/0xc0-homelab/projects/1`) is the source
of truth for the state of work. **No work starts without an issue on it.**

1. Before editing anything, find the issue for the task, or open one in the
   repo it belongs to and add it to the board with `Phase` set.
2. Move it to `In Progress` when you start, `Blocked` when it waits on
   something outside the task.
3. Every PR body links it: `Closes #N`, or `Refs owner/repo#N` from a sibling
   repo. A PR without a linked issue fails the `issue` check.
4. It closes through the PR that finishes it, not by hand.

A request that arrives mid-conversation gets its issue first. The board is
loaded into every Claude Code session by the plugin's `SessionStart` hook;
`/project-status` reads it on demand. Decisions do not live on the board —
they stay in `docs/design.md`.

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
  contract (`feat(tofu)!: move vm-edge to its own vnet`). Explain it in the
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

The same file pins the SSH key: `core.sshCommand` uses `~/.ssh/0xc0-homelab`
with `IdentitiesOnly`, so git never offers another key to these remotes.

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
- OpenTofu is **always** written as modules, with Google's layout:
  `modules/<name>/` for resources, `environments/<env>/` for roots, which only
  call modules. Each root has its own state key,
  `homelab/<repo>/<environment>.tfstate` in RustFS, never a shared one. Full
  conventions in `.github/README.md`.
- Secrets with SOPS+age. An unencrypted file holding sensitive material is a bug.
- Before proposing any IP or subnet, check it against `zones` and `vms` in
  `infrastructure/environments/prod/terraform.tfvars` and the reserved ranges
  in `infrastructure/docs/zones.md`, which are off limits.
- What is discarded stays discarded. The list and the reasons are in
  `docs/design.md`. Do not reopen it unless the human explicitly asks.

## Status

The design is closed (`docs/design.md`). The org is bootstrapped: the five
repos exist, created by `.github/environments/prod`, with their rulesets active
and every change going through a PR linked to an issue.

Phase 1 is complete: `infrastructure` runs the node from its OpenTofu root
(`environments/prod`):

- the SDN zones;
- the templates every VM clones, `debian-13-base` and `debian-13-runner`,
  baked by Packer from the raw `debian-13-cloud` that OpenTofu imports;
- `vm-access-01` and `vm-access-02`, identical cloudflared connectors over
  QUIC, with admin access over WARP;
- `vm-ci` with two ephemeral GitHub Actions runners, so CI runs inside the
  network and RustFS stays closed;
- the zone firewall, and the node's firewall on DROP.

Nothing is exposed to the internet: Traefik on the node is reached over WARP.
Every VM carries `prevent_destroy`.

Phase 2 builds one RKE2 cluster on Rocky Linux in `platform`, behind an HAProxy
load balancer that also carries the public tunnel; everything after phase 1
runs in it (`docs/design.md`). Credential rotation comes with Vault, in
phase 3.

Secrets reach CI through SOPS: each repo commits its encrypted
`secrets/tofu.sops.yaml` and holds one Actions secret, its CI age key.
