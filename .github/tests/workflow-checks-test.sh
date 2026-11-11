#!/usr/bin/env bash
# Runs the fetch and check steps of the action pin workflow against fixture git trees served by a fake gh,
# and asserts which fixtures pass and which fail with which reason.
# A gh api call that fails is made again after a ten-second wait, which a fake sleep records in place of waiting,
# and the fetch step fails on a call whose third attempt failed; what a failed attempt printed stays out of the file.
# A path with a control character and a file with a YAML anchor fail the fetch step, a path that starts
# with - is read as a path, and nothing a fixture wrote starts a line of what the steps print.
# An anchor on a key fails the fetch step like one on a value, a file whose name yq would quote is checked like any
# other, and nothing a fixture wrote is a workflow command in what the steps print.
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
# FAILS, as <call>=<count> words (head, base, blob), makes the first <count> gh api calls of that kind fail. The
# calls by kind and the waits of the run are left in $dir/calls, and what the steps printed in last_out.
run() {
  local name="$1" expected="$2" reason="${3:-}" out status got pair
  cp "$workflow_path" "$dir/blobs/chk"
  { cat "$workflow_path"; printf '\n# changed\n'; } > "$dir/blobs/chk2"
  printf '%s\t100644\tblob\tchk\n' "$protected_path" > "$dir/base-entries"
  { cat "$dir/entries"; printf '%s\t100644\tblob\t%s\n' "$protected_path" "$head_check"; } > "$dir/head-entries"
  tree_json "$dir/base-entries" > "$dir/base-tree.json"
  tree_json "$dir/head-entries" > "$dir/head-tree.json"
  mkdir -p "$dir/fails"
  : > "$dir/calls"
  for pair in ${FAILS:-}; do echo "${pair#*=}" > "$dir/fails/${pair%%=*}"; done
  cat > "$dir/bin/gh" <<EOF
#!/usr/bin/env bash
last="\${@: -1}"
kind=other
case "\$last" in
  */git/trees/base\?*) kind=base ;;
  */git/trees/head\?*) kind=head ;;
  */git/blobs/*) kind=blob ;;
esac
echo "\$kind" >> "$dir/calls"
# A call of a kind fails while the count in fails/<kind> is above zero, the way gh fails on an error answer: the
# body on stdout, its reading of it on stderr.
left=\$(cat "$dir/fails/\$kind" 2>/dev/null || echo 0)
if [ "\$left" -gt 0 ]; then
  echo \$((left - 1)) > "$dir/fails/\$kind"
  echo '{"message":"Server Error"}'
  echo "stub gh: the \$kind call failed" >&2
  exit 1
fi
case "\$last" in
  */git/trees/base\?*) cat "$dir/base-tree.json" ;;
  */git/trees/head\?*) cat "$dir/head-tree.json" ;;
  */git/blobs/*) cat "$dir/blobs/\${last##*/}" ;;
  *) echo "unexpected gh call: \$*" >&2; exit 2 ;;
esac
EOF
  # The waits the step asks for are recorded beside the gh calls and take no time.
  cat > "$dir/bin/sleep" <<EOF
#!/usr/bin/env bash
echo "wait\$1" >> "$dir/calls"
EOF
  chmod +x "$dir/bin/gh" "$dir/bin/sleep"
  if out=$(PATH="$dir/bin:$PATH" RUNNER_TEMP="$dir/runner" GITHUB_REPOSITORY=owner/repo HEAD_SHA=head GITHUB_SHA=base \
    GH_TOKEN=unused PROTECTED_PATTERN="$pattern" bash -e -o pipefail -c "${fetch}"$'\n'"${check}" 2>&1 < /dev/null); then
    status=0
  else
    status=$?
  fi
  last_out="$out"
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
  file .github/workflows/w.yml "$(workflow_yml "      - uses: \$/.github/actions/x
")"
  file .github/actions/x/action.yml "$(composite_yml "    - uses: $4
")"
  run "composite step: $1" "$2" "$3"
}
reusable_yml() {
  printf 'name: r\non:\n  workflow_call:\njobs:\n  r:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@%s # v5.1.0\n' "$sha"
}
job_case() {
  new_case
  layout
  file .github/workflows/r.yml "$(reusable_yml)"
  file .github/workflows/w.yml "$(workflow_yml "")
  b:
    uses: $4
"
  run "job: $1" "$2" "$3"
}
workspace='runner workspace; use $/)'

for kind in step_case composite_case; do
  $kind "\$/ reference to an ordinary action (unrelated symlink and submodules present)" pass "" '$/.github/actions/ok'
  $kind "./ reference to an ordinary action" fail "$workspace" ./.github/actions/ok
  $kind "./ reference into a submodule" fail "$workspace" ./vendor
  $kind "\$/ into a submodule" fail "(submodule vendor)" '$/vendor'
  $kind "\$/ below a submodule" fail "(submodule vendor)" '$/vendor/act'
  $kind "\$/ through a symlink" fail "(symlink alias)" '$/alias'
  $kind "\$/ case-changed submodule" fail "(submodule vendor)" '$/VENDOR/act'
  $kind "\$/ case-changed symlink" fail "(symlink alias)" '$/Alias/act'
  $kind "\$/ lower-case reference to the submodule Tools/Sub" fail "(submodule Tools/Sub)" '$/tools/sub/act'
  $kind "\$/ .. component" fail "(non-canonical path)" '$/docs/../vendor'
  $kind "\$/ backslash" fail "(characters other than" '$/x\..\vendor'
  if ! skip_without_check "${kind%_case}: unpinned action"; then
    $kind "unpinned action" fail "uses must be @<40-char commit SHA>" actions/checkout@v5
  fi
done

job_case "./ reusable workflow in the repository" pass "" ./.github/workflows/r.yml
job_case "\$/ reusable workflow in the repository" pass "" '$/.github/workflows/r.yml'
job_case "./ reusable workflow inside a submodule" fail "(submodule vendor)" ./vendor/.github/workflows/r.yml
job_case "./ reusable workflow through a case-changed submodule path" fail "(submodule vendor)" ./VENDOR/.github/workflows/r.yml
job_case "./ reusable workflow with a .. component" fail "(non-canonical path)" ./docs/../.github/workflows/r.yml

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "      - uses: actions/checkout@$sha # v5.1.0
        with:
          repository: someone/external
          path: external-action
      - uses: ./external-action
")"
run "workflow step: ./ to another repository checked out into the workspace" fail "$workspace"

new_case
file .github/workflows/w.yml "$(workflow_yml "      - uses: \$/key
")"
submodule "$(printf '\342\204\252')ey"
run "submodule whose name starts with KELVIN SIGN, reached by \$/key" fail "(submodule "

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

# calls <name> <the gh api calls by kind and the waits of the last run, in order>
calls() {
  local got
  got=$(paste -sd' ' - < "$dir/calls")
  if [ "$got" = "$2" ]; then
    echo "ok   $1"
  else
    failures=$((failures + 1))
    echo "FAIL $1: expected \"$2\", got \"$got\""
  fi
}
# retry_case <name> <FAILS> <pass|fail> <reason substring> <calls>
retry_case() {
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "")"
  FAILS="$2" run "$1" "$3" "$4"
  calls "$1: gh api calls and waits" "$5"
}
# Each of the three gh api calls goes through the step's fetch on its own line, so each has its own cases. The
# fixture has three files to fetch: the composite action, w.yml and the check's own workflow.
retry_case "the head tree fails once" head=1 pass "" "head wait10 head base blob blob blob"
retry_case "the base tree fails once" base=1 pass "" "head base wait10 base blob blob blob"
retry_case "a blob fails once" blob=1 pass "" "head base blob wait10 blob blob blob"
retry_case "the head tree fails twice" head=2 pass "" "head wait10 head wait10 head base blob blob blob"
warnings=$(awk '/^::warning::attempt [12] of 3 failed, running it again in 10 seconds: gh api / { n++ } END { print n + 0 }' <<< "$last_out")
if [ "$warnings" = 2 ]; then
  echo "ok   the head tree fails twice: each failed attempt is named"
else
  failures=$((failures + 1))
  echo "FAIL the head tree fails twice: expected 2 warnings, got ${warnings}"
fi
retry_case "the head tree fails every time" head=9 fail "failed three times" "head wait10 head wait10 head"
retry_case "the base tree fails every time" base=9 fail "failed three times" "head base wait10 base wait10 base"
retry_case "a blob fails every time" blob=9 fail "failed three times" "head base blob wait10 blob wait10 blob"

# same_line <name> <text> <text>: one line of what the last run printed holds both texts
same_line() {
  if grep -F -- "$2" <<< "$last_out" | grep -q -F -- "$3"; then
    echo "ok   $1"
  else
    failures=$((failures + 1))
    echo "FAIL $1: no line of the output holds both \"$2\" and \"$3\""
  fi
}
# no_line <name> <prefix>: no line of what the last run printed starts with the prefix
no_line() {
  if grep -q "^$2" <<< "$last_out"; then
    failures=$((failures + 1))
    echo "FAIL $1: a line of the output starts with $2"
  else
    echo "ok   $1"
  fi
}

new_case
layout
file .github/workflows/w.yml "$(printf 'name: w\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    strategy:\n      matrix:\n        include:\n          - &s\n            uses: someone/action@main\n    steps:\n      - uses: actions/checkout@%s # v5.1.0\n      - *s\n' "$sha")"
run "workflow step aliased from a matrix entry, beside a pinned step" fail "must not use YAML anchors"

new_case
layout
file .github/workflows/w.yml "$(printf 'name: w\non: push\nenv:\n  A: &a x\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@%s # v5.1.0\n' "$sha")"
run "workflow with an anchor nothing refers to" fail "must not use YAML anchors"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file .github/actions/a/action.yml "$(composite_yml "    - &s
      run: echo ok
      shell: bash
    - *s
")"
run "composite action with an aliased step" fail "must not use YAML anchors"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file 'docs/a\u0001b.txt' x
run "path with a control character" fail "paths with a control character"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file 'docs/a\n::notice::spoofed' x
run "path with a line break" fail "paths with a control character"
no_line "path with a line break: the path starts no line of the output" "::notice::"
same_line "path with a line break: the path is printed on one line" "docs/a" "spoofed"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file -x/action.yml "$(composite_yml "    - uses: actions/checkout@$sha # v5.1.0
")"
run "action file under a directory whose name starts with -" pass

if ! skip_without_check "unpinned action under a directory whose name starts with -"; then
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "")"
  file -x/action.yml "$(composite_yml "    - uses: actions/checkout@v5
")"
  run "unpinned action under a directory whose name starts with -" fail "uses must be @<40-char commit SHA>"
fi

if ! skip_without_check "unpinned uses holding a line break"; then
  new_case
  layout
  file .github/workflows/w.yml "$(printf 'name: w\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: "actions/checkout@v5\\n::notice::spoofed"\n')"
  run "unpinned uses holding a line break" fail "uses must be @<40-char commit SHA>"
  no_line "unpinned uses holding a line break: the value starts no line of the output" "::notice::"
  same_line "unpinned uses holding a line break: the value is printed on one line" "w.yml:7" "spoofed"
fi

# no_command <name>: the fixtures write ::notice:: and ##[notice] where a path, a uses value or a comment goes, and
# the runner reads :: at the start of a line, leading white space aside, and ##[ anywhere in one. Neither is in what
# the last run printed.
no_command() {
  if grep -q -E '^[[:space:]]*::notice::|##\[' <<< "$last_out"; then
    failures=$((failures + 1))
    echo "FAIL $1: a line of the output is a workflow command a fixture wrote"
    grep -E '^[[:space:]]*::notice::|##\[' <<< "$last_out" | sed 's/##\[/#-#-[/g; s/^/     seen: /'
  else
    echo "ok   $1"
  fi
}

new_case
layout
file .github/workflows/w.yml "$(printf 'name: w\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - &k uses: actions/checkout@%s # v5.1.0\n      - *k: someone/action@main\n' "$sha")"
run "workflow step whose uses key is an alias of an anchored key" fail "must not use YAML anchors"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file .github/actions/a/action.yml "$(composite_yml "    - &k uses: actions/checkout@$sha # v5.1.0
    - *k: someone/action@main
")"
run "composite step whose uses key is an alias of an anchored key" fail "must not use YAML anchors"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file '.github/workflows/a\"b.yml' "$(workflow_yml "")"
run "workflow file with a quotation mark in its name" pass
# The steps after the fetch step read the file under the pull request's files by its own path.
if [ -f "$dir/runner/pr-files/.github/workflows/a\"b.yml" ]; then
  echo "ok   workflow file with a quotation mark in its name: fetched under its own name"
else
  failures=$((failures + 1))
  echo "FAIL workflow file with a quotation mark in its name: not fetched under its own name"
fi

if ! skip_without_check "unpinned uses in a workflow file with a quotation mark in its name"; then
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "")"
  file '.github/workflows/a\"b.yml' "$(workflow_yml "      - uses: actions/checkout@v5
")"
  run "unpinned uses in a workflow file with a quotation mark in its name" fail "uses must be @<40-char commit SHA>"
fi

if ! skip_without_check "unpinned action under a directory whose name starts with a space"; then
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "")"
  file ' x/action.yml' "$(composite_yml "    - uses: actions/checkout@v5
")"
  run "unpinned action under a directory whose name starts with a space" fail "uses must be @<40-char commit SHA>"
fi

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file 'docs/##[notice]spoofed' x
run "path that holds ##[" fail "paths with a control character or a workflow command prefix"
no_command "path that holds ##[: the path is no command in the output"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file '::notice::x/action.yml' "$(composite_yml "    - &s
      run: echo ok
      shell: bash
    - *s
")"
run "anchor in an action file whose path starts with ::notice::" fail "must not use YAML anchors"
no_command "anchor in an action file whose path starts with ::notice::: the path is no command in the output"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file '::notice::x/Action.yml' "$(composite_yml "    - run: echo ok
      shell: bash
")"
run "action file name that is not lowercase, under a path that starts with ::notice::" fail "must be lowercase"
no_command "action file name that is not lowercase, under a path that starts with ::notice::: the path is no command in the output"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
link '::notice::l/action.yml' ../.github/actions/ok/action.yml
run "symlinked action.yml under a path that starts with ::notice::" fail "must be regular files"
no_command "symlinked action.yml under a path that starts with ::notice::: the path is no command in the output"

new_case
layout
file .github/workflows/w.yml "$(workflow_yml "")"
file '::notice::x/action.yml' "$(composite_yml "    - uses: ./.github/actions/ok
")"
run "./ reference in an action file whose path starts with ::notice::" fail "$workspace"
no_command "./ reference in an action file whose path starts with ::notice::: the path is no command in the output"

if ! skip_without_check "unpinned action whose path starts with ::notice::"; then
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "")"
  file '::notice::x/action.yml' "$(composite_yml "    - uses: actions/checkout@v5
")"
  run "unpinned action whose path starts with ::notice::" fail "uses must be @<40-char commit SHA>"
  no_command "unpinned action whose path starts with ::notice::: the path is no command in the output"
fi

if ! skip_without_check "unpinned uses with ##[ in its comment"; then
  new_case
  layout
  file .github/workflows/w.yml "$(workflow_yml "      - uses: actions/checkout@v5 # ##[notice]spoofed
")"
  run "unpinned uses with ##[ in its comment" fail "uses must be @<40-char commit SHA>"
  no_command "unpinned uses with ##[ in its comment: the comment is no command in the output"
fi

echo "${count} cases, ${failures} failed, ${skipped} skipped"
if [ "$failures" -ne 0 ]; then
  exit 1
fi
