#!/usr/bin/env bash
# Pin /opt/automation/catalyst_job_scheduler to an exact tagged release instead of
# a live `main` checkout - template, see automation-design
# docs/11-project-template.md §11.4. Concrete precedent:
# obj_fw_block/scripts/deploy.sh (first built there), copied for
# aws_prefix_update/scripts/deploy.sh (2026-10-20) - this template is
# that second copy generalized, so the THIRD tool doesn't have to
# reverse-engineer it from whichever sibling repo happens to have it,
# the same reason templates/scripts/setup-python-env.sh exists.
#
# Closes automation-design doc 12 finding #2 (CM-3, "release integrity
# documented but not enforced" - a git tag alone doesn't change what
# actually runs; see doc 04 §4.3/doc 05 §5.5/§5.8). Copy this in ON DAY
# ONE, alongside cutting the tool's first tag - not after, the way both
# obj_fw_block and aws_prefix_update originally did it. Every real-run
# lesson either project's own docs/ROADMAP.md recorded for this pattern
# is already baked in below, not left to be re-discovered a third time:
# BASE_DIR must stay root-only (never `chmod g+w` for the operator
# group - that would let any operator repoint the live symlink
# directly, bypassing every check below), the executable bit must
# actually be committed (`git update-index --chmod=+x
# scripts/deploy.sh`, not just a local `chmod +x` - a real obj_fw_block
# run found `git ls-tree` showing `100644` despite a local chmod), env
# vars must be exported or set on the same line as the invocation (a
# bare `VAR=value` on its own line only sets a shell variable, not
# something `./deploy.sh` as a child process inherits), and SHARED_PATHS
# below must be symlinked into a persistent shared/ tree, never copied
# per-release or left to a fresh `mkdir -p` (both aws_prefix_update and
# obj_fw_block hit real data-loss-shaped bugs from this - see that
# section's own comment).
#
# TODO when copying this template:
# - Replace every `CATALYST_JOB_SCHEDULER` below with this tool's own fleet-wide
#   repo-prefix convention (SCREAMING_SNAKE_CASE, e.g. `AWS_PREFIX_UPDATE`
#   for aws_prefix_update) - this becomes the env var prefix
#   (`CATALYST_JOB_SCHEDULER_REPO_URL`, `CATALYST_JOB_SCHEDULER_BASE_DIR`, etc.), so operators
#   invoking two different tools' deploy.sh on the same machine never
#   collide on the same variable name.
# - Replace `catalyst_job_scheduler` with the exact directory name this tool is
#   checked out under on the automation VM today (check `netauto`'s own
#   `registry.py` `repo_path=` value for the real name, including
#   case - it must match exactly, since this script replaces that
#   directory with a symlink of the same name) and case-insensitively
#   in this header comment too.
# - Replace `SHARED_PATHS` with this tool's own real list of paths that
#   must persist across releases - pull this from the tool's own
#   `.gitignore` (lab inventories/credentials if not already committed
#   to git - see the TODO on that below - plus genuine runtime state:
#   audit logs, sync-token markers, caches), its README's own "Service"
#   section, and any systemd units under `deploy/systemd/` - don't
#   guess from a partial grep, both real copies of this script found
#   real gaps that way (missing `cache/`, `.service-home/`).
# - Decide inventories/credentials one of two ways, per doc 15 §15.2 -
#   do NOT leave this undecided, both real tools hit the consequence
#   of not deciding: (a) commit them to git, vault-encrypting anything
#   sensitive (obj_fw_block's own approach, and the simpler one - a
#   fresh clone just has them like any other tracked file, nothing to
#   add here); (b) add them to SHARED_PATHS too if they genuinely can't
#   be committed (per-operator local topology, say) - same
#   seed-once/symlink mechanism as runtime state, just never written by
#   the tool itself at runtime.
# - Confirm the default `ADMIN_GROUP`/`SVC_USER`/`OPERATOR_GROUP` names
#   are actually this tool's own per doc 14 §14.2 - don't assume, check
#   the tool's own ROADMAP "Vault access / service-account design"
#   entry. A tool with its own separate unattended service account
#   (e.g. aws_prefix_update's systemd-timer-driven feedwatch) needs an
#   extra per-account ACL grant on SHARED_PATHS, following the same
#   `setfacl -R -m u:<account>:rwX` pattern below - see that repo's own
#   deploy.sh for a worked example with a real second account.
# - Set the executable bit in git, not just locally - see the header
#   comment above for why this matters:
#     git update-index --chmod=+x scripts/deploy.sh
#
# Run on the automation VM (needs shell + git there), from anywhere -
# it does not need to be run from inside an existing checkout of this
# repo, and on a first-run migration (see "Idempotent for the first
# run" below) it will REFUSE if your shell's cwd is inside the live
# directory about to be moved - real-usage-caught gap: `mv` on your
# own cwd "succeeds" but leaves that shell's relative-path resolution
# broken right after. cd to $BASE_DIR or /tmp first.
#
# Usage: sudo CATALYST_JOB_SCHEDULER_REPO_URL=<url> ./deploy.sh v1.0.0
# CATALYST_JOB_SCHEDULER_REPO_URL is required, no default - the real clone URL
# depends on the machine (SSH host alias, work-org vs. personal
# remote, etc. - obj_fw_block's own first real run found `git remote -v`
# on the automation VM pointing at a different host alias/org than that
# project's GitHub remote). Guessing a default here would risk silently
# cloning the wrong repo; check `git remote -v` in an existing checkout
# on the target machine for the right value.
#
# Requires sudo/root - deliberately, not a workaround (see BASE_DIR
# reasoning above). If `git clone` fails here with an SSH auth error,
# it is very likely because root doesn't have its own SSH access to
# CATALYST_JOB_SCHEDULER_REPO_URL's host - the operator account's own SSH key/agent
# isn't automatically available to root, sudo does not forward it. Give
# root its own deploy key/config for that host, or clone over HTTPS
# with a token instead.
#
# What it does:
#   1. Clones the exact tag into releases/catalyst_job_scheduler/<tag>/ (a fresh
#      checkout per release, never reused - see the exact-tag
#      verification below for why reuse would be the wrong call
#      anyway). Scoped under releases/catalyst_job_scheduler/, not a flat
#      releases/<tag>/ - releases/ is shared across every tool deployed
#      this way on the same machine, and a flat layout would let one
#      tool's pruning (below) delete another tool's still-live release
#      if their tag names ever collided, or just make `ls releases/`
#      impossible to read at a glance with every tool's tags mixed
#      together.
#   2. Verifies the checkout really is that tag (not a same-named branch
#      resolving to something else - `git clone --branch` accepts both).
#   3. Sanity-checks every .yml/.yaml file in the checkout parses -
#      obj_fw_block found this exact class of bug by hand once (broken
#      YAML that had been committed to a tagged release) before this
#      check existed; catching it here means it never reaches the live
#      symlink.
#   4. Replaces SHARED_PATHS inside the new checkout with symlinks into
#      a persistent shared/catalyst_job_scheduler/ tree (see "Shared runtime-state
#      directories" below) - NOT a copy from the previous release.
#   5. Sets ownership: the code tree itself is root:$ADMIN_GROUP,
#      read-only for everyone else - netauto-operators (or this tool's
#      own equivalent) get NO write access to code/config at any point.
#      The shared/ tree is owned by $SVC_USER (the account this tool's
#      real invocations run as) with an ACL additionally granting
#      $OPERATOR_GROUP read-only.
#   6. Atomically repoints the live symlink at the new release
#      (`ln -sfn` replaces the link target in one syscall - no window
#      where the live path points at nothing or a half-written target,
#      unlike rm-then-ln).
#   7. Prunes old releases, keeping the last N (default 5) plus
#      whichever release is still actually live, even if older than the
#      window. Prunes within releases/catalyst_job_scheduler/ only - never touches
#      another tool's own releases/<their-repo-name>/ pool, and never
#      touches shared/catalyst_job_scheduler/ at all (it lives outside releases/
#      entirely - that's the whole point).
#
# Shared runtime-state directories (Capistrano's "linked directories"
# pattern) - SHARED_PATHS live at shared/catalyst_job_scheduler/<path>, outside
# releases/ entirely, and every release's own copy of that path is a
# symlink into it, never a real directory. NOT a copy-forward
# specifically because this data accumulates (audit logs, sync-token
# markers) and a copy taken at deploy time goes stale the moment
# anything writes to either copy afterward - worse, a copy-per-release
# means pruning an old release deletes that release's own copy of this
# data outright (real finding, obj_fw_block commit `27f92cc`), and
# `rollback.sh` pointing back at an older release would silently
# present OLDER history as current - a real replay-safety hazard if
# anything in this tool checks "has this request/change already been
# processed" against that history. A shared, symlinked location has
# none of these problems: every release, past or present, reads and
# writes the exact same files. Seeded ONCE - see the migration logic
# below for where from, preferring whichever candidate actually has
# real content over a fixed priority order, since which candidate is
# authoritative depends on this host's own real deploy history, not
# something this template can assume - and never overwritten after;
# `rm -rf` a path under shared/ by hand if you genuinely want to reset
# it.
#
# Idempotent for the first run specifically: if the live path already
# exists as a real directory (not yet migrated to this scheme), it is
# NOT a disposable backup - treat it as this tool's ordinary dev/
# testing checkout (real git branches, log-pushing, etc.), the same
# directory that served double duty as both "what production runs"
# and "where dev work happens" before this script existed. A real
# obj_fw_block run hit this exactly: each releases/ checkout is a
# shallow, single-tag clone in detached HEAD by design (a release is a
# pinned snapshot, not something to commit against), so once the
# symlink took over the live path, there was no branch left to do
# ordinary git work on. Fixed there by keeping the pre-pinning checkout
# as a permanent, stably-named catalyst_job_scheduler-workdir directory rather
# than a disposable timestamped backup - do this from the start here
# instead of rediscovering the same gap a third time. Ordinary git work
# continues in catalyst_job_scheduler-workdir exactly as it always has; the
# symlinked path is deploy-only from here on. (This only triggers on a
# machine that still has a real pre-pinning directory at the live path -
# a machine that's never had anything deployed here still needs that
# workdir checkout set up separately, by hand, the first time.)
# catalyst_job_scheduler-workdir also doubles as a seed-source candidate for
# shared/'s first-ever population - see "Seeding shared/" below. Does
# NOT re-run pytest/ansible-lint/Molecule here - that's CI's job and
# already gates the tag before it exists; this script trusts a real
# tag already passed that.
set -euo pipefail

REPO_URL="${CATALYST_JOB_SCHEDULER_REPO_URL:?Set CATALYST_JOB_SCHEDULER_REPO_URL to the real clone URL for THIS machine - run git remote -v in an existing checkout to find it; do not assume it matches another machine}"
BASE_DIR="${CATALYST_JOB_SCHEDULER_BASE_DIR:-/opt/automation}"
KEEP_RELEASES="${CATALYST_JOB_SCHEDULER_KEEP_RELEASES:-5}"
# Three real identities, not one - per doc 14 §14.2's trust-tier model.
# ADMIN_GROUP owns the code tree, read-only for everyone else -
# OPERATOR_GROUP gets NO write access to code/config at any point.
ADMIN_GROUP="${CATALYST_JOB_SCHEDULER_ADMIN_GROUP:-netauto-admins}"
OPERATOR_GROUP="${CATALYST_JOB_SCHEDULER_OPERATOR_GROUP:-netauto-operators}"
SVC_USER="${CATALYST_JOB_SCHEDULER_SVC_USER:-netauto-svc}"
REPO_NAME="catalyst_job_scheduler"

# Paths that must persist across releases - see the "Shared runtime-
# state directories" header comment above for why these are symlinked
# into shared/, never copied per-release. Replace with this tool's own
# real list - see the TODO above.
SHARED_PATHS="output_files .service-home"

LIVE_LINK="$BASE_DIR/$REPO_NAME"
# Scoped under releases/$REPO_NAME/, not a flat releases/ - see the
# header comment's "What it does" step 1 for why (shared releases/
# pool across every tool deployed this way on the same machine).
RELEASES_DIR="$BASE_DIR/releases/$REPO_NAME"
SHARED_DIR="$BASE_DIR/shared/$REPO_NAME"

TAG="${1:?Usage: CATALYST_JOB_SCHEDULER_REPO_URL=<url> ./deploy.sh <tag>}"
RELEASE_DIR="$RELEASES_DIR/$TAG"
CHECKOUT_DIR="$RELEASE_DIR/$REPO_NAME"

# Fail before doing any (wasted) clone work, not after: swapping the live
# symlink, moving a pre-migration directory aside, and chown'ing the new
# release all need write access on BASE_DIR/its contents that only root
# has by design (see the header comment on why this requires sudo, not
# a group-write grant).
if [ ! -w "$BASE_DIR" ]; then
  echo "deploy: no write permission on $BASE_DIR itself (its contents may still be writable - this is about the directory entry, not what's inside it)." >&2
  echo "        This script needs sudo/root - re-run as:" >&2
  echo "            sudo CATALYST_JOB_SCHEDULER_REPO_URL=... $0 $TAG" >&2
  echo "        Do NOT chmod g+w $BASE_DIR for the operator group instead - that lets any operator repoint the live symlink directly, bypassing every check this script does." >&2
  exit 1
fi

if [ -e "$CHECKOUT_DIR" ]; then
  echo "deploy: $CHECKOUT_DIR already exists - releases are immutable once" >&2
  echo "        deployed, refusing to overwrite. Delete it first if you" >&2
  echo "        really mean to re-fetch this tag." >&2
  exit 1
fi

echo "==> Cloning $TAG into $CHECKOUT_DIR"
mkdir -p "$RELEASE_DIR"
git clone --branch "$TAG" --depth 1 "$REPO_URL" "$CHECKOUT_DIR"

echo "==> Verifying the checkout is exactly tag $TAG (not a same-named branch)"
ACTUAL_TAG="$(git -C "$CHECKOUT_DIR" describe --tags --exact-match 2>/dev/null || true)"
if [ "$ACTUAL_TAG" != "$TAG" ]; then
  echo "deploy: checked-out commit doesn't exactly match tag $TAG (got: ${ACTUAL_TAG:-<none>}) - aborting, live symlink untouched" >&2
  rm -rf "$RELEASE_DIR"
  exit 1
fi

echo "==> Sanity-checking YAML in the new checkout"
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
  if ! python3 - "$CHECKOUT_DIR" <<'PYEOF'
import sys, glob, os
import yaml

checkout = sys.argv[1]
failed = False
patterns = ["**/*.yml", "**/*.yaml"]
for pattern in patterns:
    for path in glob.glob(os.path.join(checkout, pattern), recursive=True):
        try:
            with open(path, encoding="utf-8") as f:
                # BaseLoader, not safe_load: a checkout with vault-
                # encrypted group_vars using the !vault tag needs this -
                # safe_load doesn't know that tag either, and BaseLoader
                # accepts unknown tags as plain scalars, which is enough
                # to prove the file is at least structurally valid YAML
                # without needing the vault password here.
                yaml.load(f, Loader=yaml.BaseLoader)
        except Exception as exc:
            print(f"deploy: YAML parse error in {path}: {exc}", file=sys.stderr)
            failed = True
if failed:
    sys.exit(1)
PYEOF
  then
    echo "deploy: YAML sanity check failed - aborting, live symlink untouched" >&2
    rm -rf "$RELEASE_DIR"
    exit 1
  fi
else
  echo "deploy: WARNING - no python3/PyYAML available on this machine, skipping the YAML sanity check (not blocking deploy)" >&2
fi

# Seeding shared/: prefer whichever candidate actually has real
# content for THIS path, checked in order most-likely-authoritative
# first - (1) the CURRENTLY LIVE release, if $LIVE_LINK is already a
# symlink (any real deploy since would have been writing there); (2)
# catalyst_job_scheduler-workdir, the original pre-pinning checkout; (3)
# $LIVE_LINK itself if it's still a real, non-symlink directory (a
# true first-ever deploy, before migration). "Real content" = more
# than an empty directory `mkdir -p` would also produce - a candidate
# that merely EXISTS but is empty is skipped in favor of the next one.
# Deliberately NOT a fixed priority order - which candidate is
# authoritative depends entirely on this host's own real deploy
# history (a host with several real prior deploys has its most recent
# history in the live release; a host doing its first-ever tag-pinned
# deploy has it in -workdir instead). Never overwrites a shared/ path
# that already exists - seeding happens exactly once per path, ever.
if [ -L "$LIVE_LINK" ]; then
  LIVE_TARGET="$(readlink -f "$LIVE_LINK" 2>/dev/null || true)"
else
  LIVE_TARGET=""
fi

echo "==> Ensuring shared/ runtime-state directories exist ($SHARED_DIR)"
for SHARED_PATH in $SHARED_PATHS; do
  DEST="$SHARED_DIR/$SHARED_PATH"
  if [ -e "$DEST" ]; then
    continue
  fi
  SEED_SOURCE=""
  for CANDIDATE in "$LIVE_TARGET" "${LIVE_LINK}-workdir" "$LIVE_LINK"; do
    if [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE/$SHARED_PATH" ] && [ -n "$(ls -A "$CANDIDATE/$SHARED_PATH" 2>/dev/null)" ]; then
      SEED_SOURCE="$CANDIDATE"
      break
    fi
  done
  if [ -n "$SEED_SOURCE" ]; then
    echo "    seeding $SHARED_PATH from $SEED_SOURCE"
    mkdir -p "$(dirname "$DEST")"
    cp -a "$SEED_SOURCE/$SHARED_PATH" "$DEST"
  else
    echo "    $SHARED_PATH not found with real content in any candidate - creating empty (provision manually if real history was expected)"
    mkdir -p "$DEST"
  fi
done

echo "==> Linking $CHECKOUT_DIR's runtime-state paths into shared/"
for SHARED_PATH in $SHARED_PATHS; do
  TARGET="$CHECKOUT_DIR/$SHARED_PATH"
  rm -rf "$TARGET"
  mkdir -p "$(dirname "$TARGET")"
  ln -sfn "$SHARED_DIR/$SHARED_PATH" "$TARGET"
done

echo "==> Setting ownership on the code tree (root:$ADMIN_GROUP, read-only for everyone else)"
if ! getent group "$ADMIN_GROUP" >/dev/null 2>&1; then
  echo "deploy: WARNING - group $ADMIN_GROUP doesn't exist on this machine, falling back to root:root (override with CATALYST_JOB_SCHEDULER_ADMIN_GROUP if the real group is named differently)" >&2
  chown -R root:root "$CHECKOUT_DIR"
else
  chown -R "root:$ADMIN_GROUP" "$CHECKOUT_DIR"
fi
# Absolute mode, not additive - this checkout should never carry
# leftover group-write bits from an older version of this script.
# `-type d`/`-type f` never match the SHARED_PATHS symlinks just
# created above (a symlink is neither), so this leaves them alone -
# their own ownership is set separately below, on the real shared/
# target, not through the in-release link.
find "$CHECKOUT_DIR" -type d -exec chmod 0755 {} +
find "$CHECKOUT_DIR" -type f -exec chmod 0644 {} +
find "$CHECKOUT_DIR" -type f -name "*.sh" -exec chmod 0755 {} +

echo "==> Setting ownership on shared/ runtime state ($SHARED_DIR)"
if id "$SVC_USER" >/dev/null 2>&1; then
  for SHARED_PATH in $SHARED_PATHS; do
    chown -R "$SVC_USER:$SVC_USER" "$SHARED_DIR/$SHARED_PATH"
  done
  # setgid on directories so anything $SVC_USER writes at runtime
  # inherits its group automatically; files 0644 not 0640/0660 (a
  # non-root $SVC_USER process can't chgrp a new file to a group it
  # isn't a member of - EPERM, a hard Ansible task failure - so read
  # access for other accounts has to come from the file's own "other"
  # bits, with the directory already restricting who "other" can mean
  # here). chmod BEFORE setfacl below, not after - chmod resets an
  # ACL's mask entry.
  find "$SHARED_DIR" -mindepth 1 -maxdepth 1 -type d -exec chmod 2750 {} +
  find "$SHARED_DIR" -type f -exec chmod 0644 {} +
  if command -v setfacl >/dev/null 2>&1 && getent group "$OPERATOR_GROUP" >/dev/null 2>&1; then
    for SHARED_PATH in $SHARED_PATHS; do
      setfacl -R -m "g:${OPERATOR_GROUP}:rX" "$SHARED_DIR/$SHARED_PATH"
      setfacl -R -d -m "g:${OPERATOR_GROUP}:rX" "$SHARED_DIR/$SHARED_PATH"
    done
  else
    echo "deploy: WARNING - setfacl unavailable or group $OPERATOR_GROUP missing - operators will NOT be able to read shared/ (reports/audit log) until this is fixed" >&2
  fi
else
  echo "deploy: WARNING - service account $SVC_USER doesn't exist on this machine yet - $SHARED_DIR left as previously owned (override with CATALYST_JOB_SCHEDULER_SVC_USER if the real account is named differently)" >&2
fi

if [ -e "$LIVE_LINK" ] && [ ! -L "$LIVE_LINK" ]; then
  WORKDIR="${LIVE_LINK}-workdir"
  if [ -e "$WORKDIR" ]; then
    echo "deploy: $LIVE_LINK is a real directory (not yet a symlink), and $WORKDIR already exists too - refusing to guess which one is the real ongoing dev checkout. Resolve this by hand before re-running (see the header comment's 'Idempotent for the first run' note)." >&2
    exit 1
  fi
  # Real-usage-caught gap: `mv` on the directory your own shell is
  # currently cd'd into "succeeds" (exit 0) but leaves that shell's
  # pwd/relative-path resolution broken afterward (confirmed by
  # reproducing it directly - every relative-path command fails with
  # "No such file or directory" right after). Refuse up front instead
  # of letting that confusion happen mid-migration.
  LIVE_LINK_REAL="$(cd "$LIVE_LINK" && pwd -P)"
  CWD_REAL="$(pwd -P)"
  case "$CWD_REAL" in
    "$LIVE_LINK_REAL"|"$LIVE_LINK_REAL"/*)
      echo "deploy: refusing to move $LIVE_LINK while your shell's current directory is inside it ($CWD_REAL). cd elsewhere first (e.g. 'cd $BASE_DIR' or 'cd /tmp') and re-run this exact command." >&2
      exit 1
      ;;
  esac
  echo "==> $LIVE_LINK is a real directory, not yet a symlink - this is the ongoing dev/testing checkout, not disposable. Moving it to the stable $WORKDIR path; ordinary git work continues there unaffected."
  mv "$LIVE_LINK" "$WORKDIR"
fi

echo "==> Switching live symlink: $LIVE_LINK -> $CHECKOUT_DIR"
ln -sfn "$CHECKOUT_DIR" "$LIVE_LINK"
echo "==> Live: $TAG"

echo "==> Pruning old releases (keeping the last $KEEP_RELEASES, plus whichever is live)"
CURRENT_TARGET="$(readlink -f "$LIVE_LINK" 2>/dev/null || true)"
CURRENT_TAG=""
if [ -n "$CURRENT_TARGET" ]; then
  CURRENT_TAG="$(basename "$(dirname "$CURRENT_TARGET")")"
fi
if [ -d "$RELEASES_DIR" ]; then
  ls -1t "$RELEASES_DIR" 2>/dev/null | tail -n "+$((KEEP_RELEASES + 1))" | while read -r old_tag; do
    if [ "$old_tag" = "$CURRENT_TAG" ]; then
      continue
    fi
    echo "    pruning $old_tag"
    rm -rf "${RELEASES_DIR:?}/$old_tag"
  done
fi

echo "==> Done. $LIVE_LINK now points at $TAG."
