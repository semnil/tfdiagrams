#!/usr/bin/env bash
# Runs the fetch and check steps of the action pin workflow against fixture git trees served by a fake gh,
# and asserts which fixtures pass and which fail with which reason.
# WORKFLOW_FILE and WORKFLOW_JOB select the workflow under test (relative to the repository root, or absolute).
# WORKFLOW_CHECK_STEP=absent declares a workflow without the pin check step; the pin cases are then skipped.
# Otherwise a missing pin check step fails the test.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="${WORKFLOW_FILE:-.github/workflows/workflow-checks.yml}"
job="${WORKFLOW_JOB:-action-pins}"
check_step_mode="${WORKFLOW_CHECK_STEP:-required}"
case "$workflow" in
  /*) workflow_path="$workflow" ;;
  *) workflow_path="$root/$workflow" ;;
esac
protected_path=".github/workflows/$(basename "$workflow")"
fetch_step="Fetch the pull request's workflow and action files"
check_step="Check that every uses is pinned to a commit SHA"
step_field() {
  yq ".jobs.\"${job}\".steps[] | select(.name == \"$1\") | .$2" "$workflow_path"
}
fetch=$(step_field "$fetch_step" run)
check=$(step_field "$check_step" run)
pattern=$(step_field "$fetch_step" env.PROTECTED_PATTERN)
if [ -z "$fetch" ] || [ "$fetch" = "null" ] || [ -z "$pattern" ] || [ "$pattern" = "null" ]; then
  echo "the fetch step or its PROTECTED_PATTERN was not found in ${workflow} (job ${job})" >&2
  exit 1
fi
if [ "$check" = "null" ]; then
  check=""
fi
case "$check_step_mode" in
  required)
    if [ -z "$check" ]; then
      echo "the \"${check_step}\" step was not found in ${workflow} (job ${job}); set WORKFLOW_CHECK_STEP=absent only for a workflow that has no pin check step" >&2
      exit 1
    fi
    ;;
  absent)
    if [ -n "$check" ]; then
      echo "WORKFLOW_CHECK_STEP=absent but ${workflow} (job ${job}) has the \"${check_step}\" step" >&2
      exit 1
    fi
    ;;
  *)
    echo "WORKFLOW_CHECK_STEP must be required or absent (got ${check_step_mode})" >&2
    exit 1
    ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sha=0123456789abcdef0123456789abcdef01234567
count=0
failures=0
skipped=0

new_case() {
  count=$((count + 1))
  dir="$work/case${count}"
  mkdir -p "$dir/blobs" "$dir/bin"
  : > "$dir/entries"
  blobs=0
  head_check=chk
}
entry() {
  blobs=$((blobs + 1))
  printf '%s' "$4" > "$dir/blobs/b${blobs}"
  printf '%s\t%s\t%s\tb%s\n' "$1" "$2" "$3" "$blobs" >> "$dir/entries"
}
file() { entry "$1" 100644 blob "$2"; }
link() { entry "$1" 120000 blob "$2"; }
submodule() { entry "$1" 160000 commit ""; }
tree_json() {
  local first=1 path mode type blob
  printf '{"truncated":false,"tree":['
  while IFS=$'\t' read -r path mode type blob; do
    if [ "$first" -eq 0 ]; then printf ','; fi
    first=0
    printf '{"path":"%s","mode":"%s","type":"%s","sha":"%s"}' "$path" "$mode" "$type" "$blob"
  done < "$1"
  printf ']}'
}

# run <name> <pass|fail> [reason substring]
run() {
  local name="$1" expected="$2" reason="${3:-}" out status got
  cp "$workflow_path" "$dir/blobs/chk"
  { cat "$workflow_path"; printf '\n# changed\n'; } > "$dir/blobs/chk2"
  printf '%s\t100644\tblob\tchk\n' "$protected_path" > "$dir/base-entries"
  { cat "$dir/entries"; printf '%s\t100644\tblob\t%s\n' "$protected_path" "$head_check"; } > "$dir/head-entries"
  tree_json "$dir/base-entries" > "$dir/base-tree.json"
  tree_json "$dir/head-entries" > "$dir/head-tree.json"
  cat > "$dir/bin/gh" <<EOF
#!/usr/bin/env bash
last="\${@: -1}"
case "\$last" in
  */git/trees/base\?*) cat "$dir/base-tree.json" ;;
  */git/trees/head\?*) cat "$dir/head-tree.json" ;;
  */git/blobs/*) cat "$dir/blobs/\${last##*/}" ;;
  *) echo "unexpected gh call: \$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$dir/bin/gh"
  if out=$(PATH="$dir/bin:$PATH" RUNNER_TEMP="$dir/runner" GITHUB_REPOSITORY=owner/repo HEAD_SHA=head GITHUB_SHA=base \
    GH_TOKEN=unused PROTECTED_PATTERN="$pattern" bash -e -o pipefail -c "${fetch}"$'\n'"${check}" 2>&1 < /dev/null); then
    status=0
  else
    status=$?
  fi
  if [ "$status" -eq 0 ]; then
    got=pass
  elif [[ "$out" != *"::error::"* ]]; then
    got="crash (exit ${status} without ::error::)"
  elif [ -n "$reason" ] && [[ "$out" != *"$reason"* ]]; then
    got="fail without \"${reason}\""
  else
    got=fail
  fi
  if [ "$got" = "$expected" ]; then
    echo "ok   ${name} (${expected})"
  else
    failures=$((failures + 1))
    echo "FAIL ${name}: expected ${expected}, got ${got}"
    printf '%s\n' "$out" | tail -n 12 | sed 's/^/     /'
  fi
}
skip_without_check() {
  if [ -z "$check" ]; then
    skipped=$((skipped + 1))
    echo "skip $1 (WORKFLOW_CHECK_STEP=absent)"
    return 0
  fi
  return 1
}

workflow_yml() {
  printf 'name: w\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@%s # v5.1.0\n%s' "$sha" "$1"
}
composite_yml() {
  printf 'name: x\ndescription: x\nruns:\n  using: composite\n  steps:\n%s' "$1"
}
layout() {
  file .github/actions/ok/action.yml "$(composite_yml "    - run: echo ok
      shell: bash
")"
  link docs/link ../README.md
  submodule third_party/lib
  submodule vendor
  submodule Tools/Sub
  link alias vendor
}
step_case() {
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "      - uses: $4
")"
  run "workflow step: $1" "$2" "$3"
}
composite_case() {
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "      - uses: ./.github/actions/x
")"
  file .github/actions/x/action.yml "$(composite_yml "    - uses: $4
")"
  run "composite step: $1" "$2" "$3"
}

for kind in step_case composite_case; do
  $kind "ordinary local action (unrelated symlink and submodules present)" pass "" ./.github/actions/ok
  $kind "\$/ reference to an ordinary action" pass "" '$/.github/actions/ok'
  $kind "submodule ./vendor" fail "(submodule vendor)" ./vendor
  $kind "below a submodule ./vendor/act" fail "(submodule vendor)" ./vendor/act
  $kind "symlink ./alias" fail "(symlink alias)" ./alias
  $kind "case-changed submodule ./VENDOR/act" fail "(submodule vendor)" ./VENDOR/act
  $kind "case-changed symlink ./Alias" fail "(symlink alias)" ./Alias
  $kind "lower-case reference to the submodule Tools/Sub" fail "(submodule Tools/Sub)" ./tools/sub/act
  $kind "\$/ into a submodule" fail "(submodule vendor)" '$/vendor'
  $kind "\$/ through a case-changed symlink" fail "(symlink alias)" '$/Alias/act'
  $kind ".. component ./docs/../vendor" fail "(non-canonical path)" ./docs/../vendor
  $kind "backslash ./x\\..\\vendor" fail "(characters other than" './x\..\vendor'
  if ! skip_without_check "${kind%_case}: unpinned action"; then
    $kind "unpinned action" fail "uses must be @<40-char commit SHA>" actions/checkout@v5
  fi
done

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")
  b:
    uses: ./vendor/.github/workflows/r.yml
"
run "reusable workflow inside a submodule" fail "(submodule vendor)"

new_case
file .github/workflows/w.yml "$(workflow_yml "      - uses: ./key
")"
submodule "$(printf '\342\204\252')ey"
run "submodule whose name starts with KELVIN SIGN, reached by ./key" fail "(submodule "

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
head_check=chk2
run "check file differs from the default branch" fail "must be identical to the default branch"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
link .github/actions/l/action.yml ../ok/action.yml
run "symlinked action.yml" fail "must be regular files"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file .github/actions/u/Action.yml "$(composite_yml "    - run: echo ok
      shell: bash
")"
run "action file name that is not lowercase" fail "must be lowercase"

echo "${count} cases, ${failures} failed, ${skipped} skipped"
if [ "$failures" -ne 0 ]; then
  exit 1
fi
