#!/usr/bin/env bash
# Dry-runs release-semantic.yaml in this repo (never the live one): waits for the dev build of the dev tip,
# promotes it to main, and checks the release packaged. There is no Nexus workflow or secret in this repo.
# Usage: gh api 'repos/alandtse/open-shaders-release-test/contents/run-release-dry-run.sh?ref=e2e-dev-shader-reuse' -H 'Accept: application/vnd.github.raw' | bash
set -euo pipefail

REPO="${REPO:-alandtse/open-shaders-release-test}"
BASELINE_TAG=v2.20.0
WAIT_MIN=180

die() { echo "ERROR: $*" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || die "gh is not logged in"
[ "$REPO" = "alandtse/open-shaders" ] && die "refusing to run against the live repo"

secrets=$(gh secret list -R "$REPO" --json name --jq '.[].name')
grep -qx RELEASE_PAT <<<"$secrets" \
  || die "add the RELEASE_PAT secret first (fine-grained PAT for $REPO only: Contents, Workflows, Actions = read/write)"
! grep -qi nexus <<<"$secrets" || die "a Nexus secret exists in $REPO; remove it first"
workflows=$(gh api "repos/$REPO/contents/.github/workflows" --jq '.[].name')
! grep -qi nexus <<<"$workflows" || die "a Nexus workflow exists in $REPO"

baseline=$(gh api "repos/$REPO/commits/a8c9f2c" --jq .sha)
if ! gh api "repos/$REPO/git/ref/tags/$BASELINE_TAG" >/dev/null 2>&1; then
  echo "Creating baseline tag $BASELINE_TAG at $baseline"
  gh api -X POST "repos/$REPO/git/refs" -f ref="refs/tags/$BASELINE_TAG" -f sha="$baseline" >/dev/null
fi

target=$(gh api "repos/$REPO/commits/dev" --jq .sha)
echo "Release target (dev tip): $target"

echo "Waiting for the dev build of $target (release-dev.yaml) ..."
deadline=$((SECONDS + WAIT_MIN * 60)); dev_run=""
while [ $SECONDS -lt $deadline ]; do
  read -r id status conclusion < <(gh run list -R "$REPO" -w release-dev.yaml -b dev --json databaseId,headSha,status,conclusion \
    --jq "[.[] | select(.headSha == \"$target\")] | first | \"\(.databaseId) \(.status) \(.conclusion)\"" || echo "null null null")
  if [ "$status" = completed ]; then
    [ "$conclusion" = success ] || die "dev build $id ended $conclusion"
    dev_run=$id; break
  fi
  sleep 60
done
[ -n "$dev_run" ] || die "dev build did not finish in $WAIT_MIN min"
echo "Dev build: https://github.com/$REPO/actions/runs/$dev_run"

wait_run() {
  local id=$1 deadline=$((SECONDS + WAIT_MIN * 60)) status conclusion
  while [ $SECONDS -lt $deadline ]; do
    read -r status conclusion < <(gh run view "$id" -R "$REPO" --json status,conclusion --jq '"\(.status) \(.conclusion)"')
    [ "$status" = completed ] && { echo "$conclusion"; return; }
    sleep 30
  done
  echo timeout
}
latest_release_run() {
  gh run list -R "$REPO" -w release-semantic.yaml -b main -e workflow_dispatch -L 10 --json databaseId,createdAt \
    --jq "[.[] | select(.createdAt >= \"$1\")] | sort_by(.createdAt)"
}

since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gh workflow run release-semantic.yaml -R "$REPO" --ref main -f ff_target="$target" >/dev/null
sleep 15
phase1=$(latest_release_run "$since" | jq -r '.[0].databaseId')
echo "Phase 1 (promotion): https://github.com/$REPO/actions/runs/$phase1"
[ "$(wait_run "$phase1")" = success ] || die "promotion run failed"

phase2=""
for _ in $(seq 1 20); do
  phase2=$(latest_release_run "$since" | jq -r "[.[] | select(.databaseId != $phase1)] | last | .databaseId // empty")
  [ -n "$phase2" ] && break; sleep 10
done
[ -n "$phase2" ] || die "phase 2 run did not appear"
echo "Phase 2 (release): https://github.com/$REPO/actions/runs/$phase2"
result=$(wait_run "$phase2")
gh run view "$phase2" -R "$REPO" --json jobs --jq '.jobs[] | "\(.conclusion // .status)\t\(.name)"' | sort
[ "$result" = success ] || die "release run ended $result"

jobs=$(gh run view "$phase2" -R "$REPO" --json jobs --jq '.jobs[] | "\(.conclusion)\t\(.name)"')
grep -q $'success\treuse-dev-shaders / Import CompiledShaderBinaries-SE' <<<"$jobs" || die "dev shader reuse did not run"
grep -q $'skipped\tvalidate-shaders' <<<"$jobs" || die "validate-shaders was not skipped"

tag=$(gh release list -R "$REPO" --exclude-drafts --exclude-pre-releases -L 1 --json tagName --jq '.[0].tagName')
echo "Release: $tag"
assets=$(gh release view "$tag" -R "$REPO" --json assets,isDraft --jq '"draft=\(.isDraft)\n" + (.assets[] | "\(.size)\t\(.name)")')
echo "$assets"
grep -q 'draft=false' <<<"$assets" || die "release is still a draft"
grep -q 'CommunityShaders_AIO-.*\.7z' <<<"$assets" || die "no AIO archive attached"
grep -q 'ShaderCache-SE-.*\.7z' <<<"$assets" || die "no SE shader cache attached"
grep -q 'ShaderCache-VR-.*\.7z' <<<"$assets" || die "no VR shader cache attached"
echo "PASS: release-semantic reused the dev compile, packaged the release and published it in $REPO (no Nexus involved)."
