#!/usr/bin/env bash
# Checks that dependabot-auto-merge.yml reports `auto-merge` on every pull request: only pull_request starts it, with
# no filter, the job has no condition of its own, and its two steps alone are limited to pull requests dependabot[bot]
# opened; a failure of the metadata step lets the job go on to the deciding step, and the runs for one pull request
# share a concurrency group. Then runs the step that decides, against a fake gh that answers the pull request's
# commit list, head and auto-merge state from fixtures, for each metadata outcome, update type and commit history:
# auto-merge is enabled (pinned to the head) only for a patch or minor fetch-metadata classified whose pull request
# is one commit at the head that dependabot[bot] wrote, GitHub (web-flow) committed and GitHub verified the
# signature of; every other case turns an earlier auto-merge off, except a run whose head is no longer the head of
# the pull request, which changes nothing; and a failure to read the commits, the head or the auto-merge state fails
# the step.
# WORKFLOW_FILE selects the workflow under test (relative to the repository root, or absolute).
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="${WORKFLOW_FILE:-.github/workflows/dependabot-auto-merge.yml}"
case "$workflow" in
  /*) workflow_path="$workflow" ;;
  *) workflow_path="$root/$workflow" ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
count=0
failures=0

# expect <name> <actual> <expected>
expect() {
  count=$((count + 1))
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    failures=$((failures + 1))
    echo "FAIL $1: expected $3, got $2"
  fi
}

author_condition="github.event.pull_request.user.login == 'dependabot[bot]'"
expect 'pull_request is the only trigger' "$(yq -o=json -I=0 '.on | keys' "$workflow_path")" '["pull_request"]'
expect 'the trigger has no filter' "$(yq -r '.on.pull_request == null' "$workflow_path")" 'true'
expect 'the job has no condition' "$(yq -r '.jobs.auto-merge | has("if")' "$workflow_path")" 'false'
expect 'the job has two steps' "$(yq -r '.jobs.auto-merge.steps | length' "$workflow_path")" '2'
expect 'the metadata step is limited to Dependabot' "$(yq -r '.jobs.auto-merge.steps[0].if' "$workflow_path")" "$author_condition"
expect 'the deciding step is limited to Dependabot' "$(yq -r '.jobs.auto-merge.steps[1].if' "$workflow_path")" "$author_condition"
# The deciding step runs after a failed metadata step only when that failure does not fail the job (dependabot-auto-merge.yml:37).
expect 'a failed metadata step does not fail the job' "$(yq -r '.jobs.auto-merge.steps[0].continue-on-error' "$workflow_path")" 'true'
expect 'the deciding step reads the metadata outcome' "$(yq -r '.jobs.auto-merge.steps[1].env.METADATA_OUTCOME' "$workflow_path")" "\${{ steps.metadata.outcome }}"
expect 'the runs for one pull request share a concurrency group' "$(yq -r '.jobs.auto-merge.concurrency.group' "$workflow_path")" "dependabot-auto-merge-\${{ github.event.pull_request.number }}"

yq -r '.jobs.auto-merge.steps[1].run' "$workflow_path" > "$work/step.sh"
mkdir "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
if [ "$1" = api ]; then
  [ "${STUB_COMMITS_FAIL:-0}" = 1 ] && { echo 'HTTP 502' >&2; exit 1; }
  cat "$STUB_COMMITS"; exit 0
fi
if [ "$1 $2" = 'pr view' ]; then
  [ "${STUB_VIEW_FAIL:-0}" = 1 ] && { echo 'HTTP 502' >&2; exit 1; }
  printf '%s\t%s\n' "$STUB_HEAD" "$STUB_ENABLED"
fi
EOF
chmod +x "$work/bin/gh"

url=https://github.com/o/r/pull/7
head=0123456789abcdef0123456789abcdef01234567
other=fedcba9876543210fedcba9876543210fedcba98
bot='{"login":"dependabot[bot]"}'
human='{"login":"someone"}'
webflow='{"login":"web-flow"}'
commit() { printf '{"sha":"%s","author":%s,"committer":%s,"commit":{"verification":{"verified":%s}}}' "$1" "$2" "${4:-$webflow}" "$3"; }
printf '[%s]' "$(commit $head "$bot" true)" > "$work/single-bot.json"
printf '[%s,%s]' "$(commit $other "$bot" true)" "$(commit $head "$human" true)" > "$work/bot-then-human.json"
printf '[%s]' "$(commit $head "$human" true)" > "$work/single-human.json"
printf '[%s]' "$(commit $head "$bot" false)" > "$work/single-unverified.json"
printf '[%s]' "$(commit $other "$bot" true)" > "$work/single-other-sha.json"
printf '[%s]' "$(commit $head "$bot" true "$human")" > "$work/single-amended.json"
printf '[%s,%s]' "$(commit $head "$bot" true)" "$(commit $other "$bot" true)" > "$work/two-head-first.json"

api="api repos/o/r/pulls/7/commits?per_page=100"
enable="pr merge --auto --merge --match-head-commit $head $url"
view="pr view $url --json headRefOid,autoMergeRequest --jq [.headRefOid, (.autoMergeRequest != null)] | @tsv"
disable="pr merge --disable-auto $url"

# decide <name> <update type> <commits fixture> <auto-merge state> <commit list fails> <exit code> <gh calls...>
# METADATA_OUTCOME (default success), CURRENT_HEAD (default the event's head) and VIEW_FAIL (default 0) set before
# the call give the outcome of the metadata step, the head the pull request has now, and a failing pr view.
decide() {
  local name=$1 type=$2 commits=$3 enabled=$4 fail=$5 want_rc=$6 rc=0
  shift 6
  : > "$work/log"
  STUB_LOG="$work/log" STUB_ENABLED="$enabled" STUB_COMMITS="$work/$commits.json" STUB_COMMITS_FAIL="$fail" \
    STUB_HEAD="${CURRENT_HEAD:-$head}" STUB_VIEW_FAIL="${VIEW_FAIL:-0}" \
    PATH="$work/bin:$PATH" GH_TOKEN=x GITHUB_REPOSITORY=o/r PR_URL=$url PR_NUMBER=7 HEAD_SHA=$head \
    METADATA_OUTCOME="${METADATA_OUTCOME:-success}" UPDATE_TYPE="$type" bash -e "$work/step.sh" > "$work/out" 2>&1 || rc=$?
  expect "$name: exit code" "$rc" "$want_rc"
  expect "$name: gh calls" "$(paste -sd'|' - < "$work/log")" "$(printf '%s\n' "$@" | paste -sd'|' -)"
}
patch=version-update:semver-patch
minor=version-update:semver-minor
major=version-update:semver-major
decide 'patch, one verified Dependabot commit at the head' $patch single-bot false 0 0 "$api" "$enable"
decide 'minor, one verified Dependabot commit at the head' $minor single-bot false 0 0 "$api" "$enable"
decide 'patch, a commit added after Dependabot, auto-merge on' $patch bot-then-human true 0 0 "$api" "$view" "$disable"
decide 'minor, a commit added after Dependabot, auto-merge off' $minor bot-then-human false 0 0 "$api" "$view"
decide 'minor, one commit someone else wrote' $minor single-human true 0 0 "$api" "$view" "$disable"
decide 'patch, one unverified Dependabot commit' $patch single-unverified true 0 0 "$api" "$view" "$disable"
decide 'patch, a signed amend of the Dependabot commit by someone else' $patch single-amended true 0 0 "$api" "$view" "$disable"
decide 'patch, the Dependabot commit is not the head' $patch single-other-sha true 0 0 "$api" "$view" "$disable"
decide 'patch, two commits with the head listed first' $patch two-head-first true 0 0 "$api" "$view" "$disable"
decide 'major, auto-merge on' $major single-bot true 0 0 "$view" "$disable"
decide 'no update type, auto-merge off' '' single-bot false 0 0 "$view"
decide 'unknown update type, auto-merge state unreadable' other single-bot unreadable 0 1 "$view"
decide 'patch, commit list unreadable' $patch single-bot false 1 1 "$api"
METADATA_OUTCOME=failure decide 'metadata step failed, auto-merge on' '' single-bot true 0 0 "$view" "$disable"
METADATA_OUTCOME=failure decide 'metadata step failed, auto-merge off' '' single-bot false 0 0 "$view"
METADATA_OUTCOME=failure decide 'metadata step failed with an update type left, auto-merge on' $patch single-bot true 0 0 "$view" "$disable"
METADATA_OUTCOME=failure CURRENT_HEAD=$other decide 'metadata step failed, the head has moved' '' single-bot true 0 0 "$view"
CURRENT_HEAD=$other decide 'patch, the head has moved to a newer Dependabot commit' $patch single-other-sha true 0 0 "$api" "$view"
CURRENT_HEAD=$other decide 'major, the head has moved' $major single-bot true 0 0 "$view"
CURRENT_HEAD=unreadable decide 'major, head unreadable' $major single-bot true 0 1 "$view"
VIEW_FAIL=1 decide 'major, pr view fails' $major single-bot true 0 1 "$view"

echo "${count} checks, ${failures} failed"
[ "$failures" -eq 0 ]
