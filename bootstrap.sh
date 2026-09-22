#!/usr/bin/env bash
# Clones (or updates) the org repos inside the workspace.
set -euo pipefail
cd "$(dirname "$0")"

ORG=0xc0-homelab

clone() {  # $1 = repo name, $2 = local directory
  if [ -d "$2/.git" ]; then
    echo "==> $2: pull"
    git -C "$2" pull --ff-only
  elif [ -d "$2" ] && [ -n "$(ls -A "$2" 2>/dev/null)" ]; then
    echo "==> $2: exists without .git, leaving it as is"
  else
    echo "==> $2: clone"
    gh repo clone "$ORG/$1" "$2"
  fi
}

clone .github        .github
clone claude-config  claude-config
clone infrastructure infrastructure
clone deployments    deployments
