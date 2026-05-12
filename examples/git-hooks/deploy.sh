#!/usr/bin/env bash
# ABOUTME: Deploys tiered git hooks (pre-commit, pre-push) to target repositories.
# ABOUTME: Backs up existing hooks, supports --list to scan for deployed instances.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SIGNATURE="ABOUTME: Git pre-"  # Signature in our hooks to identify them

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: deploy.sh <repo-path> [<repo-path> ...]"
    echo "       deploy.sh --list"
    echo ""
    echo "Deploys pre-commit and pre-push hooks to the target repo(s)."
    echo "Backs up any existing hooks before overwriting."
    echo ""
    echo "Options:"
    echo "  --list    Scan ~/repos/ for repos with our hooks installed"
    echo "  --help    Show this help message"
}

# ---------------------------------------------------------------------------
# List mode: scan ~/repos/ for repos with our hooks
# ---------------------------------------------------------------------------
list_deployed() {
    echo "Scanning ~/repos/ for deployed hooks..."
    echo ""

    local count=0
    local total
    total=$(find ~/repos -name .git -type d 2>/dev/null | wc -l)
    local checked=0

    while IFS= read -r git_dir; do
        checked=$((checked + 1))
        repo_dir=$(dirname "$git_dir")
        hooks_dir="$git_dir/hooks"

        has_precommit=false
        has_prepush=false

        if [ -f "$hooks_dir/pre-commit" ] && grep -q "$HOOK_SIGNATURE" "$hooks_dir/pre-commit" 2>/dev/null; then
            has_precommit=true
        fi
        if [ -f "$hooks_dir/pre-push" ] && grep -q "$HOOK_SIGNATURE" "$hooks_dir/pre-push" 2>/dev/null; then
            has_prepush=true
        fi

        if [ "$has_precommit" = true ] || [ "$has_prepush" = true ]; then
            count=$((count + 1))
            hooks=""
            [ "$has_precommit" = true ] && hooks="pre-commit"
            [ "$has_prepush" = true ] && hooks="${hooks:+$hooks, }pre-push"
            echo "  $repo_dir ($hooks)"
        fi

        # Progress indicator every 10 repos
        if [ $((checked % 10)) -eq 0 ]; then
            printf "\r  [%d/%d repos scanned]" "$checked" "$total" >&2
        fi
    done < <(find ~/repos -name .git -type d 2>/dev/null | sort)

    printf "\r%*s\r" 40 "" >&2  # Clear progress line
    echo ""
    echo "Found $count repo(s) with deployed hooks (scanned $total total)."
}

# ---------------------------------------------------------------------------
# Deploy hooks to a single repo
# ---------------------------------------------------------------------------
deploy_to_repo() {
    local repo_path="$1"

    # Resolve to absolute path
    repo_path=$(cd "$repo_path" && pwd)

    # Verify it's a git repo
    if [ ! -d "$repo_path/.git" ]; then
        echo "  ERROR: $repo_path is not a git repository (no .git directory)"
        return 1
    fi

    local hooks_dir="$repo_path/.git/hooks"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    echo "  Deploying to: $repo_path"

    # Create hooks directory if it doesn't exist
    mkdir -p "$hooks_dir"

    # Deploy each hook
    for hook in pre-commit pre-push; do
        local source="$SCRIPT_DIR/$hook"
        local target="$hooks_dir/$hook"

        if [ ! -f "$source" ]; then
            echo "    WARNING: $source not found — skipping $hook"
            continue
        fi

        # Back up existing hook if it exists and isn't already ours
        if [ -f "$target" ]; then
            if grep -q "$HOOK_SIGNATURE" "$target" 2>/dev/null; then
                echo "    $hook: updating (our hook already installed)"
            else
                local backup="$target.backup.$timestamp"
                cp "$target" "$backup"
                echo "    $hook: backed up existing → $(basename "$backup")"
            fi
        fi

        # Copy and make executable
        cp "$source" "$target"
        chmod +x "$target"
        echo "    $hook: deployed"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
fi

if [ "$1" = "--list" ]; then
    list_deployed
    exit 0
fi

# Deploy to each specified repo
TOTAL=$#
CURRENT=0
FAILURES=0

for repo in "$@"; do
    CURRENT=$((CURRENT + 1))
    echo "[$CURRENT/$TOTAL] Processing: $repo"

    if deploy_to_repo "$repo"; then
        echo "    Done."
    else
        FAILURES=$((FAILURES + 1))
        echo "    FAILED."
    fi
    echo ""
done

echo "Deployed to $((TOTAL - FAILURES))/$TOTAL repo(s)."
if [ "$FAILURES" -gt 0 ]; then
    echo "  $FAILURES repo(s) had errors."
    exit 1
fi
