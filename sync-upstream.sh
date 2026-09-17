#!/bin/zsh

# Sync Lokinet fork with official upstream (oxen-io/lokinet)
set -euo pipefail

REPO_DIR="/Users/janindra/lokinet"
cd "$REPO_DIR"

echo "=== 🔄 Syncing with Upstream (oxen-io/lokinet) ==="

# 1. Ensure remotes are configured
if ! git remote | grep -q "^upstream$"; then
  echo "Adding upstream remote..."
  git remote add upstream https://github.com/oxen-io/lokinet.git
fi

# 2. Fetch upstream dev branch
echo "Fetching latest changes from upstream/dev..."
git fetch upstream dev

CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
echo "Current local branch: $CURRENT_BRANCH"

# Check if there are upstream commits to pull
BEHIND_COUNT=$(git rev-list --count HEAD..upstream/dev || echo 0)

if [ "$BEHIND_COUNT" -eq 0 ]; then
  echo "✅ Already up-to-date with upstream/dev!"
else
  echo "Found $BEHIND_COUNT new upstream commits."
  echo "Merging upstream/dev into $CURRENT_BRANCH..."
  git merge upstream/dev -m "chore: sync with upstream/dev ($(date +'%Y-%m-%d'))"
  
  echo "Pushing updated branch to origin..."
  git push origin "$CURRENT_BRANCH"
  echo "✅ Successfully synced and pushed to your GitHub fork!"
  
  # Prompt to rebuild
  echo ""
  echo "To recompile with the latest upstream code:"
  echo "  cd /Users/janindra/lokinet/build && ninja lokinet-daemon"
fi
