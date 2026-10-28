#!/usr/bin/env bash
# Repoint the live /opt/automation/catalyst_job_scheduler symlink at an
# already-deployed release, without re-cloning - for when the
# currently-live tag turns out to be bad and a previous one is
# known-good. Template, see automation-design docs/11-project-template.md
# §11.4 and templates/scripts/deploy.sh (which creates the releases/
# this script switches between - same TODO list applies here: replace
# every `CATALYST_JOB_SCHEDULER`, `catalyst_job_scheduler`, and `SHARED_PATHS` below, confirm
# this script's executable bit is committed via
# `git update-index --chmod=+x scripts/rollback.sh`).
#
# Usage: sudo ./rollback.sh v1.0.0
# Requires sudo/root, deliberately - same reasoning as deploy.sh's own
# header comment: BASE_DIR write access must stay root-only, not
# granted to the operator group, or any operator could repoint the
# live symlink themselves with a bare `ln -sfn`, bypassing every
# safety check deploy.sh does when it originally deployed each
# release.
#
# If the target tag was pruned by a later deploy.sh run (or was never
# deployed on this machine), this refuses to guess - re-run
# deploy.sh <tag> to fetch it fresh instead.
#
# Also re-links the target release's SHARED_PATHS into shared/ if
# they're still real directories instead of symlinks - a release
# deployed before deploy.sh grew the shared/ model (see its own header
# comment) has its own frozen, real copy of these paths. Rolling back
# to one of those WITHOUT this step would silently drop the live path
# back onto that frozen snapshot, hiding everything shared/ has
# accumulated since. Never deletes that real directory outright, even
# when it looks safe to (e.g. it's empty) - a release that was
# genuinely live in production before this model existed may hold
# history unique to it that shared/ was never seeded with. Renamed
# aside with a timestamp instead; reconcile into shared/ by hand if it
# turns out to hold anything shared/ is missing.
set -euo pipefail

BASE_DIR="${CATALYST_JOB_SCHEDULER_BASE_DIR:-/opt/automation}"
REPO_NAME="catalyst_job_scheduler"
SHARED_PATHS="output_files .service-home"

LIVE_LINK="$BASE_DIR/$REPO_NAME"
# Must match deploy.sh's own RELEASES_DIR exactly - scoped under
# releases/$REPO_NAME/, not a flat releases/ (shared pool across every
# tool deployed this way on the same machine).
RELEASES_DIR="$BASE_DIR/releases/$REPO_NAME"
SHARED_DIR="$BASE_DIR/shared/$REPO_NAME"

TAG="${1:?Usage: ./rollback.sh <tag>}"
CHECKOUT_DIR="$RELEASES_DIR/$TAG/$REPO_NAME"

# Swapping the live symlink needs write access on BASE_DIR itself (the
# parent), not on what's inside it - see deploy.sh's own version of this
# check for why (found the hard way on a real obj_fw_block run).
if [ ! -w "$BASE_DIR" ]; then
  echo "rollback: no write permission on $BASE_DIR itself. This script needs sudo/root - re-run as:" >&2
  echo "              sudo $0 $TAG" >&2
  echo "          Do NOT chmod g+w $BASE_DIR for the operator group instead - that lets any operator repoint the live symlink directly." >&2
  exit 1
fi

if [ ! -d "$CHECKOUT_DIR" ]; then
  echo "rollback: $CHECKOUT_DIR doesn't exist on this machine (never deployed here, or pruned by a later deploy)." >&2
  echo "          Run: ./deploy.sh $TAG   to fetch it fresh instead." >&2
  exit 1
fi

echo "==> Checking $TAG's runtime-state paths are linked into shared/ ($SHARED_DIR)"
for SHARED_PATH in $SHARED_PATHS; do
  TARGET="$CHECKOUT_DIR/$SHARED_PATH"
  if [ -L "$TARGET" ]; then
    continue
  fi
  if [ ! -e "$SHARED_DIR/$SHARED_PATH" ]; then
    echo "rollback: WARNING - $SHARED_DIR/$SHARED_PATH doesn't exist - leaving $TARGET as-is (run deploy.sh at least once first to establish shared/)" >&2
    continue
  fi
  if [ -e "$TARGET" ]; then
    BACKUP="${TARGET}.pre-shared-model-$(date +%Y%m%d%H%M%S)"
    echo "    $TARGET predates the shared/ model - renaming aside to $BACKUP (NOT deleting) before linking $TARGET into shared/. Compare the two by hand and merge anything shared/$SHARED_PATH is missing."
    mv "$TARGET" "$BACKUP"
  fi
  mkdir -p "$(dirname "$TARGET")"
  ln -sfn "$SHARED_DIR/$SHARED_PATH" "$TARGET"
done

echo "==> Switching live symlink: $LIVE_LINK -> $CHECKOUT_DIR"
ln -sfn "$CHECKOUT_DIR" "$LIVE_LINK"
echo "==> Live: $TAG"
