#!/usr/bin/env bash
# Runs the dev-shader-reuse e2e end to end with gh: promotes the branch to main (workflow_dispatch only
# sees workflows on the default branch), runs e2e-fake-dev, then the reuse and no-match scenarios.
# Usage: gh api 'repos/alandtse/open-shaders-release-test/contents/run-e2e-dev-shader-reuse.sh?ref=e2e-dev-shader-reuse' -H 'Accept: application/vnd.github.raw' | bash
set -euo pipefail

REPO="${REPO:-alandtse/open-shaders-release-test}"
BRANCH="${BRANCH:-e2e-dev-shader-reuse}"
TIMEOUT_MIN=15

gh auth status >/dev/null 2>&1 || { echo "gh is not logged in: run 'gh auth login'" >&2; exit 1; }

branch_sha=$(gh api "repos/$REPO/commits/$BRANCH" --jq .sha)
main_sha=$(gh api "repos/$REPO/commits/main" --jq .sha)
if [ "$main_sha" != "$branch_sha" ]; then
  echo "Fast-forwarding main $main_sha -> $branch_sha"
  gh api -X PATCH "repos/$REPO/git/refs/heads/main" -f sha="$branch_sha" -F force=false >/dev/null
fi

# Dispatch a workflow on main, wait for the run it created, print its URL and return its conclusion.
run_and_wait() {
  local workflow=$1; shift
  local since; since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  gh workflow run "$workflow" -R "$REPO" --ref main "$@" >/dev/null
  local id=""
  for _ in $(seq 1 30); do
    id=$(gh run list -R "$REPO" -w "$workflow" -b main -e workflow_dispatch -L 5 --json databaseId,createdAt \
      --jq "[.[] | select(.createdAt >= \"$since\")] | sort_by(.createdAt) | last | .databaseId // empty")
    [ -n "$id" ] && break
    sleep 4
  done
  [ -n "$id" ] || { echo "no run appeared for $workflow" >&2; return 1; }
  echo "$workflow $* -> https://github.com/$REPO/actions/runs/$id" >&2
  local deadline=$((SECONDS + TIMEOUT_MIN * 60)) status conclusion
  while [ $SECONDS -lt $deadline ]; do
    read -r status conclusion < <(gh run view "$id" -R "$REPO" --json status,conclusion --jq '"\(.status) \(.conclusion)"')
    [ "$status" = completed ] && { echo "$conclusion"; return 0; }
    sleep 10
  done
  echo "timed out after $TIMEOUT_MIN min: $workflow" >&2
  return 1
}

fail=0
check() {
  local name=$1 result=$2
  printf '%-10s %s\n' "$name" "$result"
  [ "$result" = success ] || fail=1
}

check fake-dev "$(run_and_wait e2e-fake-dev.yaml)"
[ "$fail" = 0 ] || { echo "e2e-fake-dev failed; skipping the reuse scenarios" >&2; exit 1; }
check reuse "$(run_and_wait e2e-dev-shader-reuse.yaml -f scenario=reuse)"
check no-match "$(run_and_wait e2e-dev-shader-reuse.yaml -f scenario=no-match)"
exit "$fail"
