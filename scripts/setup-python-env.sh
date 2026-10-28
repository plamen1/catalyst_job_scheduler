#!/usr/bin/env bash
# Sets up this project's Python venv, dev/lint/test tooling, Ansible
# Galaxy collections, and the pre-commit git hook. Idempotent - safe
# to re-run (e.g. after requirements-dev.txt or requirements.yml
# changes). Copy this file as-is into every new tool's own
# `scripts/setup-python-env.sh` - see doc 11 §11.4. First built for
# `obj_fw_block`, copied for `aws_prefix_update` by hand (2026-10-15) -
# templated here so the next tool doesn't have to reverse-engineer it
# from whichever sibling repo happens to have it.
#
# Does NOT need sudo. Run from the repo root:
#   ./scripts/setup-python-env.sh
#
# If this fails with a build error on a genuinely fresh machine
# (missing gcc/python3-dev/python3-venv for a compiled wheel), that
# machine needs OS-level packages first - see whether a sibling repo's
# own `scripts/setup-system-packages.sh` already covers this host (the
# Automation VM is already a working Ansible host for every tool
# dispatched through `netauto`, so this step is usually a no-op there,
# not something every new tool needs its own copy of).
#
# TODO when copying this template, once this tool has its own
# scripts/deploy.sh (templates/scripts/deploy.sh): replace
# `catalyst_job_scheduler` in the guard below with this tool's own real directory
# name - see that script's own TODO for why it has to match exactly.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Real gap, found 2026-10-20 (aws_prefix_update/obj_fw_block, same
# automation VM): once this tool's own scripts/deploy.sh has ever run
# on a host, the tool's live path is a symlink into an immutable,
# root:netauto-admins-owned release checkout under releases/ - this
# script runs fine from there before deploy.sh's first run (it's the
# only checkout there is yet), but running it there afterward either
# fails outright (read-only) or "succeeds" into a .venv/git hook that
# the next deploy's fresh clone never carries forward. Ordinary dev
# work (this script, ansible-lint, git commits) belongs in
# catalyst_job_scheduler-workdir instead - see templates/scripts/deploy.sh's own
# header comment ("Idempotent for the first run") for why that
# directory exists. Checked via the resolved real path, not the
# as-typed one, so this still catches a symlink-based cd into the
# release checkout, not just a direct path.
case "$(pwd -P)" in
  */releases/*)
    echo "setup-python-env: refusing to run inside a deploy-pinned release checkout ($(pwd -P))." >&2
    echo "    This path is managed by scripts/deploy.sh and may be read-only, or get" >&2
    echo "    discarded on the next deploy - ordinary dev work (venv, pre-commit," >&2
    echo "    git commits, ansible-lint) belongs in catalyst_job_scheduler-workdir instead." >&2
    echo "    cd there and re-run." >&2
    exit 1
    ;;
esac

if [ ! -d .venv ]; then
  echo "==> Creating .venv"
  python3 -m venv .venv
else
  echo "==> .venv already exists, reusing"
fi

# shellcheck disable=SC1091
source .venv/bin/activate

# Situational, not universal - only set PIP_TRUSTED_HOST_LIST if THIS
# host actually needs it (real finding, aws_prefix_update/obj_fw_block's
# shared automation VM, 2026-10-20: pip couldn't verify PyPI's
# certificate chain there - corporate proxy/TLS-inspection or an
# outdated ca-certificates package). Empty by default - don't trust
# pip's cert verification away on a host that was never shown to need
# it; export PIP_TRUSTED_HOST_LIST="pypi.org files.pythonhosted.org
# pypi.python.org" (bare hostnames, space-separated) before running
# this script if the plain `pip install` below fails with a TLS/cert
# error.
PIP_TRUSTED_HOST_LIST="${PIP_TRUSTED_HOST_LIST:-}"
PIP_TRUSTED_HOSTS=""
for PIP_TRUSTED_HOST in $PIP_TRUSTED_HOST_LIST; do
  PIP_TRUSTED_HOSTS="$PIP_TRUSTED_HOSTS --trusted-host $PIP_TRUSTED_HOST"
done

# Second real gap found the same way (aws_prefix_update/obj_fw_block,
# a later real git commit): the flags above only cover pip calls this
# script makes directly. pre-commit manages its own isolated
# environment per hook, installed lazily the first time that hook
# actually runs (not during `pre-commit install` below, which just
# registers the git hook entry point) - its first real trigger can
# hit the identical TLS error installing a hook's own environment, a
# pip call this script never sees or controls. If PIP_TRUSTED_HOST_LIST
# is set, also persist it to this account's own pip.conf so every
# future pip invocation (this script's own, pre-commit's internal
# ones, anything else) picks it up with no flag needed. Never touches
# an existing pip.conf that already has content - safer to print what
# to add by hand than to risk corrupting a config section this script
# knows nothing about. Only covers pip calls made as this account -
# see the two real repos' own ROADMAP entries for the root/sudo
# caveat if git/pre-commit ever runs as root on a given host.
if [ -n "$PIP_TRUSTED_HOST_LIST" ]; then
  PIP_CONF_FILE="${HOME}/.config/pip/pip.conf"
  if [ -f "$PIP_CONF_FILE" ]; then
    if grep -q "^trusted-host" "$PIP_CONF_FILE" 2>/dev/null; then
      echo "==> $PIP_CONF_FILE already sets trusted-host, leaving as-is"
    else
      echo "==> WARNING: $PIP_CONF_FILE exists without a trusted-host line - not editing an existing pip config automatically. Add this by hand under its [global] section if pre-commit's own internal pip calls need it too:" >&2
      echo "        trusted-host = $PIP_TRUSTED_HOST_LIST" >&2
    fi
  else
    echo "==> Persisting pip's trusted-host setting to $PIP_CONF_FILE (covers pip calls this script doesn't make directly - e.g. pre-commit's own hook-environment installs during a later git commit)"
    mkdir -p "$(dirname "$PIP_CONF_FILE")"
    printf '[global]\ntrusted-host = %s\n' "$PIP_TRUSTED_HOST_LIST" > "$PIP_CONF_FILE"
  fi
fi

echo "==> Upgrading pip"
pip install --upgrade pip $PIP_TRUSTED_HOSTS -q

echo "==> Installing dev/lint/test tooling (requirements-dev.txt)"
pip install -r requirements-dev.txt $PIP_TRUSTED_HOSTS -q

echo "==> Installing Ansible Galaxy collections (requirements.yml)"
ansible-galaxy collection install -r requirements.yml

echo "==> Installing pre-commit git hook"
pre-commit install

if [ ! -f .secrets.baseline ]; then
  echo "==> Creating initial detect-secrets baseline"
  detect-secrets scan > .secrets.baseline
  echo "    Review .secrets.baseline before committing it — it should contain"
  echo "    zero real secrets (only known-safe/false-positive matches, if any)."
else
  echo "==> .secrets.baseline already exists, leaving as-is (use 'detect-secrets scan --update .secrets.baseline' to refresh)"
fi

echo ""
echo "==> Python environment ready. Sanity checks:"
echo "    source .venv/bin/activate"
echo "    pytest tests/ -v"
echo "    yamllint ."
echo "    black --check <paths from .pre-commit-config.yaml's own black hook>"
echo "    flake8 --max-line-length=100 <same paths>"
echo "    mypy <same paths>"
echo "    bandit -r <same paths>"
echo "    ansible-lint"
echo ""
echo "==> If this tool uses Molecule, see its own molecule/<scenario>/"
echo "    requirements.yml and run 'molecule test' separately - not part"
echo "    of this script, since not every tool here uses it."
