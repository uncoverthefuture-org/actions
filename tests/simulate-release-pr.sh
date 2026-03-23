#!/bin/bash
set -euo pipefail

# ==============================================================================
# Release-Please PR Simulator
# ==============================================================================
# This script automates the full lifecycle for testing the 'extract-version' 
# action within a repository that utilizes it.
# 
# Usage: ./simulate-release-pr.sh <target-branch> <test-version>
# Example: ./simulate-release-pr.sh sandbox "v9.9.9"
# ==============================================================================

# 1. Inputs Check
TARGET_BRANCH="${1:-main}"
TEST_VERSION="${2:-v9.9.9}"

echo "🚀 Simulating Release-Please PR to test extract-version..."
echo "Target Base Branch: $TARGET_BRANCH"
echo "Test Version: $TEST_VERSION"

# Ensure we're up to date
git checkout "$TARGET_BRANCH"
git pull origin "$TARGET_BRANCH"

# 2. Create Issue First
echo "📝 Creating test issue..."
ISSUE_URL=$(gh issue create --title "Automated Extract Version Test for $TEST_VERSION" --body "This is an automated issue triggered to test the extract-version GH action subaction.")
echo "✅ Created issue: $ISSUE_URL"

# Extract issue number from URL
ISSUE_NUM=$(basename "$ISSUE_URL")

# 3. Create a branch (Simulating release-please naming convention)
BRANCH_NAME="release-please--branches--$TARGET_BRANCH--components--test-$ISSUE_NUM"
echo "🌿 Creating properly formatted test branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# 4. "Solve" the issue (Create changes)
echo "🛠️ Creating a dummy file to push changes..."
DUMMY_FILE="test_extract_version_$ISSUE_NUM.txt"
echo "This file artificially solves issue $ISSUE_NUM for release testing." > "$DUMMY_FILE"

git add "$DUMMY_FILE"
git commit -m "chore: artificial commit to trigger release action for #$ISSUE_NUM"

echo "⬆️ Pushing branch..."
git push -u origin "$BRANCH_NAME"

# 5. Raise a PR
# The title must explicitly match the semver regex inside extract-version: ([0-9]+\.[0-9]+\.[0-9]+)
CLEAN_VERSION="${TEST_VERSION#v}" # Strip 'v' if present so title format matches typical release-please (e.g., 'chore: release 1.2.3')

echo "🔄 Raising PR..."
PR_URL=$(gh pr create \
  --base "$TARGET_BRANCH" \
  --head "$BRANCH_NAME" \
  --title "chore: release $CLEAN_VERSION" \
  --body "Closes #$ISSUE_NUM - Automated PR to verify extract-version safely handles merged PR contexts.")

echo "🎉 Done! Your test Release-Please PR has been raised: $PR_URL"
echo ""
echo "👉 NEXT STEPS:"
echo "1. Because 'extract-version' relies on 'github.event.pull_request.merged == true', the action will ONLY fire when you MERGE the PR."
echo "2. Approve and merge the PR created above!"
echo "3. Watch the latest workflow run on your target branch to confirm versions seamlessly extracted."
