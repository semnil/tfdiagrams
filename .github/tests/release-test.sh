#!/usr/bin/env bash
# Runs the release steps against fixtures and asserts what they do:
# - the tag step of tag-release.yml, in fixture repositories each with a local bare repository as origin and a fake gh:
#   the exit status, the tags origin ends up with and the gh calls the step made;
# - the check step of release.yml, in fixture checkouts of a tag: the exit status;
# - the shape of release.yml: it starts only on a published Release, and every publishing job waits for the check job.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
rules="$root/.github/scripts/release_version.py"
tag_workflow="$root/.github/workflows/tag-release.yml"
release_workflow="$root/.github/workflows/release.yml"
tag_step="Tag a version bump and create its draft Release"
check_step="Check that the tag is the version in pyproject.toml"
tag_script=$(yq ".jobs.tag.steps[] | select(.name == \"${tag_step}\") | .run" "$tag_workflow")
check_script=$(yq ".jobs.check.steps[] | select(.name == \"${check_step}\") | .run" "$release_workflow")
if [ -z "$tag_script" ] || [ "$tag_script" = "null" ]; then
  echo "the \"${tag_step}\" step was not found in ${tag_workflow} (job tag)" >&2
  exit 1
fi
if [ -z "$check_script" ] || [ "$check_script" = "null" ]; then
  echo "the \"${check_step}\" step was not found in ${release_workflow} (job check)" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
count=0
failures=0

new_case() {
  count=$((count + 1))
  name="$1"
  dir="$work/case${count}"
  mkdir -p "$dir/bin"
  out=""
  status=0
  problems=()
}
new_repo_case() {
  new_case "$1"
  git init -q --bare -b master "$dir/origin.git"
  git init -q -b master "$dir/src"
  git -C "$dir/src" remote add origin "$dir/origin.git"
  mkdir -p "$dir/src/.github/scripts"
  cp "$rules" "$dir/src/.github/scripts/"
  : > "$dir/gh.log"
  echo '[]' > "$dir/releases.json"
  break_origin=0
}
# write_pyproject <path> <version | -> writes a pyproject.toml; - writes one without a version.
write_pyproject() {
  if [ "$2" = "-" ]; then
    printf '[tool.poetry]\nname = "fixture"\n' > "$1"
  else
    printf '[tool.poetry]\nname = "fixture"\nversion = "%s"\n' "$2" > "$1"
  fi
}
# commit_version <version | -> prints the new commit.
commit_version() {
  write_pyproject "$dir/src/pyproject.toml" "$1"
  git -C "$dir/src" add -A
  git -C "$dir/src" commit -q -m "version $1"
  git -C "$dir/src" rev-parse HEAD
}
# commit_other prints a new commit that adds a file of its own, so branches made of these commits merge without conflicts.
commit_other() {
  local others
  others=$(($(cat "$work/others" 2> /dev/null || echo 0) + 1))
  echo "$others" > "$work/others"
  echo "$others" > "$dir/src/other${others}.txt"
  git -C "$dir/src" add "other${others}.txt"
  git -C "$dir/src" commit -q -m "other change ${others}"
  git -C "$dir/src" rev-parse HEAD
}
push_master() {
  git -C "$dir/src" push -q origin HEAD:refs/heads/master
}
# remote_tag <name> <commit> [annotated] prints what refs/tags/<name> on origin names.
remote_tag() {
  if [ "${3:-}" = annotated ]; then
    git -C "$dir/src" tag -a -m "$1" "$1" "$2"
  else
    git -C "$dir/src" tag "$1" "$2"
  fi
  git -C "$dir/src" push -q origin "refs/tags/$1"
  git -C "$dir/src" rev-parse "refs/tags/$1"
}

# run_tag_step <tested commit> clones origin, checks out the commit and runs the tag step there as `shell: bash` does.
# The fake gh answers `release list` by running its --jq expression on releases.json, and fails `release list` when
# list-fails exists and `release create` when create-fails exists.
run_tag_step() {
  local head="$1"
  cat > "$dir/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$dir/gh.log"
args=("\$@")
case "\$1 \$2" in
  "release list")
    if [ -e "$dir/list-fails" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
    expr=""
    for ((i = 0; i < \${#args[@]}; i++)); do
      if [ "\${args[\$i]}" = --jq ]; then expr="\${args[\$((i + 1))]}"; fi
    done
    jq -r "\$expr" "$dir/releases.json"
    ;;
  "release create")
    if [ -e "$dir/create-fails" ]; then echo "HTTP 422: Validation Failed" >&2; exit 1; fi
    ;;
  *) echo "unexpected gh call: \$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$dir/bin/gh"
  printf '%s\n' "$tag_script" > "$dir/step.sh"
  git clone -q "$dir/origin.git" "$dir/run"
  git -C "$dir/run" checkout -q --detach "$head"
  if [ "$break_origin" = 1 ]; then
    git -C "$dir/run" remote set-url origin "$dir/missing.git"
  fi
  if out=$(cd "$dir/run" && PATH="$dir/bin:$PATH" HEAD_SHA="$head" GH_TOKEN=unused GH_REPO=owner/repo \
    bash --noprofile --norc -eo pipefail "$dir/step.sh" 2>&1 < /dev/null); then
    status=0
  else
    status=$?
  fi
}
# run_check_step <tag> <version | -> runs the check step in a checkout of a tag whose pyproject.toml holds the version.
run_check_step() {
  mkdir -p "$dir/run/.github/scripts"
  cp "$rules" "$dir/run/.github/scripts/"
  write_pyproject "$dir/run/pyproject.toml" "$2"
  printf '%s\n' "$check_script" > "$dir/step.sh"
  if out=$(cd "$dir/run" && GITHUB_REF_NAME="$1" GITHUB_REF_TYPE=tag \
    bash --noprofile --norc -eo pipefail "$dir/step.sh" 2>&1 < /dev/null); then
    status=0
  else
    status=$?
  fi
}

# expect_status <pass|fail> [reason substring]
expect_status() {
  local got
  if [ "$status" -eq 0 ]; then
    got=pass
  elif [[ "$out" != *"::error::"* ]]; then
    got="crash (exit ${status} without ::error::)"
  elif [ -n "${2:-}" ] && [[ "$out" != *"$2"* ]]; then
    got="fail without \"$2\""
  else
    got=fail
  fi
  if [ "$got" != "$1" ]; then
    problems+=("expected $1, got ${got}")
  fi
}
# expect_tags [<name>=<object> ...] is the whole set of tags on origin and what each names.
expect_tags() {
  local got want
  got=$(git -C "$dir/origin.git" for-each-ref --format='%(refname:strip=2)=%(objectname)' refs/tags | LC_ALL=C sort)
  want=$(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi | LC_ALL=C sort)
  if [ "$got" != "$want" ]; then
    problems+=("tags on origin: expected [${want//$'\n'/ }], got [${got//$'\n'/ }]")
  fi
}
# expect_gh [<call> ...] is every gh call in order.
expect_gh() {
  local got want
  got=$(cat "$dir/gh.log")
  want=$(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi)
  if [ "$got" != "$want" ]; then
    problems+=("gh calls: expected [${want//$'\n'/; }], got [${got//$'\n'/; }]")
  fi
}
end_case() {
  if [ "${#problems[@]}" -eq 0 ]; then
    echo "ok   ${name}"
  else
    failures=$((failures + 1))
    echo "FAIL ${name}"
    printf '     %s\n' "${problems[@]}"
    if [ -n "$out" ]; then
      printf '%s\n' "$out" | tail -n 12 | sed 's/^/     | /'
    fi
  fi
}

list_releases='release list --limit 1000 --json tagName --jq .[] | select(.tagName == "0.5.3") | .tagName'
create_draft='release create 0.5.3 --draft --verify-tag --title 0.5.3 --generate-notes'

new_repo_case "a version bump is tagged at the tested commit and gets a draft Release"
c1=$(commit_version 0.5.2)
t1=$(remote_tag 0.5.2 "$c1")
c2=$(commit_version 0.5.3)
push_master
run_tag_step "$c2"
expect_status pass
expect_tags "0.5.2=$t1" "0.5.3=$c2"
expect_gh "$create_draft"
end_case

new_repo_case "a merge commit of a version bump is compared with its first parent and tagged"
c1=$(commit_version 0.5.2)
git -C "$dir/src" checkout -q -b bump
c2=$(commit_version 0.5.3)
git -C "$dir/src" checkout -q master
commit_other > /dev/null
git -C "$dir/src" merge -q --no-ff -m merge bump
m=$(git -C "$dir/src" rev-parse HEAD)
push_master
run_tag_step "$m"
expect_status pass
expect_tags "0.5.3=$m"
expect_gh "$create_draft"
end_case

new_repo_case "a merge of a branch made before the last version bump is not a release"
commit_version 0.5.2 > /dev/null
git -C "$dir/src" checkout -q -b topic
commit_other > /dev/null
git -C "$dir/src" checkout -q master
c2=$(commit_version 0.5.3)
t2=$(remote_tag 0.5.3 "$c2")
git -C "$dir/src" merge -q --no-ff -m merge topic
m=$(git -C "$dir/src" rev-parse HEAD)
push_master
run_tag_step "$m"
expect_status pass
expect_tags "0.5.3=$t2"
expect_gh
end_case

new_repo_case "a push that does not move the version tags nothing and creates nothing"
c1=$(commit_version 0.5.2)
t1=$(remote_tag 0.5.2 "$c1")
c2=$(commit_other)
push_master
run_tag_step "$c2"
expect_status pass
expect_tags "0.5.2=$t1"
expect_gh
end_case

new_repo_case "a root commit is not a release"
c1=$(commit_version 0.5.3)
push_master
run_tag_step "$c1"
expect_status pass
expect_tags
expect_gh
end_case

for bad in 0.6.0rc1 v0.5.3 0.6; do
  new_repo_case "version ${bad} is refused before a tag is pushed"
  c1=$(commit_version 0.5.2)
  c2=$(commit_version "$bad")
  push_master
  run_tag_step "$c2"
  expect_status fail "::error::version ${bad} is not a release version (X.Y.Z)"
  expect_tags
  expect_gh
  end_case
done

new_repo_case "a version holding a newline is refused on one ::error:: line"
c1=$(commit_version 0.5.2)
c2=$(commit_version '0.5.3\nx')
push_master
run_tag_step "$c2"
expect_status fail "::error::version 0.5.3 x is not a release version (X.Y.Z)"
expect_tags
expect_gh
end_case

new_repo_case "a first parent without a readable version refuses to tag"
c1=$(commit_version -)
c2=$(commit_version 0.5.3)
push_master
run_tag_step "$c2"
expect_status fail "could not read the version from pyproject.toml at ${c1}"
expect_tags
expect_gh
end_case

new_repo_case "a tested commit without a readable version fails"
c1=$(commit_version 0.5.2)
c2=$(commit_version -)
push_master
run_tag_step "$c2"
expect_status fail "could not read the version from pyproject.toml at ${c2}"
expect_tags
expect_gh
end_case

new_repo_case "a tag already at another commit is left alone and fails the job"
c1=$(commit_version 0.5.2)
t1=$(remote_tag 0.5.3 "$c1")
c2=$(commit_version 0.5.3)
push_master
run_tag_step "$c2"
expect_status fail "0.5.3 already names ${c1}, not ${c2}"
expect_tags "0.5.3=$t1"
expect_gh
end_case

new_repo_case "an annotated tag already at another commit is left alone and fails the job"
c1=$(commit_version 0.5.2)
t1=$(remote_tag 0.5.3 "$c1" annotated)
c2=$(commit_version 0.5.3)
push_master
run_tag_step "$c2"
expect_status fail "0.5.3 already names ${c1}, not ${c2}"
expect_tags "0.5.3=$t1"
expect_gh
end_case

new_repo_case "a tag already at the tested commit without a Release gets the draft"
c1=$(commit_version 0.5.2)
c2=$(commit_version 0.5.3)
t2=$(remote_tag 0.5.3 "$c2")
echo '[{"tagName":"0.5.2"}]' > "$dir/releases.json"
push_master
run_tag_step "$c2"
expect_status pass
expect_tags "0.5.3=$t2"
expect_gh "$list_releases" "$create_draft"
end_case

new_repo_case "an annotated tag already at the tested commit without a Release gets the draft"
c1=$(commit_version 0.5.2)
c2=$(commit_version 0.5.3)
t2=$(remote_tag 0.5.3 "$c2" annotated)
push_master
run_tag_step "$c2"
expect_status pass
expect_tags "0.5.3=$t2"
expect_gh "$list_releases" "$create_draft"
end_case

new_repo_case "a tag already at the tested commit with a Release gets no second one"
c1=$(commit_version 0.5.2)
c2=$(commit_version 0.5.3)
t2=$(remote_tag 0.5.3 "$c2")
echo '[{"tagName":"0.5.2"},{"tagName":"0.5.3"}]' > "$dir/releases.json"
push_master
run_tag_step "$c2"
expect_status pass
expect_tags "0.5.3=$t2"
expect_gh "$list_releases"
end_case

new_repo_case "Releases that cannot be listed fail the job before a draft is created"
c1=$(commit_version 0.5.2)
c2=$(commit_version 0.5.3)
t2=$(remote_tag 0.5.3 "$c2")
touch "$dir/list-fails"
push_master
run_tag_step "$c2"
expect_status fail "::error::could not list the Releases"
expect_tags "0.5.3=$t2"
expect_gh "$list_releases"
end_case

new_repo_case "a failed draft create fails the job and leaves the pushed tag"
c1=$(commit_version 0.5.2)
c2=$(commit_version 0.5.3)
touch "$dir/create-fails"
push_master
run_tag_step "$c2"
expect_status fail "could not create the draft Release for 0.5.3"
expect_tags "0.5.3=$c2"
expect_gh "$create_draft"
end_case

new_repo_case "an origin whose tags cannot be listed fails the job before tagging"
c1=$(commit_version 0.5.2)
c2=$(commit_version 0.5.3)
push_master
break_origin=1
run_tag_step "$c2"
expect_status fail "could not list the tags of origin"
expect_tags
expect_gh
end_case

new_case "release.yml: a tag that is the version in pyproject.toml passes the check"
run_check_step 0.5.3 0.5.3
expect_status pass
end_case

new_case "release.yml: a tag naming a commit with another version fails the check"
run_check_step 0.5.3 0.5.2
expect_status fail "::error::tag 0.5.3 names a commit whose pyproject.toml holds version 0.5.2"
end_case

for bad in v0.5.3 0.6.0rc1 0.6; do
  new_case "release.yml: tag ${bad} fails the check even when pyproject.toml holds it"
  run_check_step "$bad" "$bad"
  expect_status fail "::error::version ${bad} is not a release version (X.Y.Z)"
  end_case
done

new_case "release.yml: a checkout without a readable version fails the check"
run_check_step 0.5.3 -
expect_status fail "::error::could not read the version from pyproject.toml at 0.5.3"
end_case

new_case "release.yml: another version holding a newline is reported on one ::error:: line"
run_check_step 0.5.3 '0.5.2\nx'
expect_status fail "::error::tag 0.5.3 names a commit whose pyproject.toml holds version 0.5.2 x"
end_case

new_case "release.yml starts only when a Release is published"
triggers=$(yq -o=json -I=0 '.on' "$release_workflow")
if [ "$triggers" != '{"release":{"types":["published"]}}' ]; then
  problems+=("on: expected {\"release\":{\"types\":[\"published\"]}}, got ${triggers}")
fi
end_case

# waits_for_check <job> succeeds when the job needs check directly or through other jobs.
waits_for_check() {
  local need
  for need in $(yq ".jobs.\"$1\".needs | ([] + .) | .[]" "$release_workflow"); do
    if [ "$need" = check ] || waits_for_check "$need"; then
      return 0
    fi
  done
  return 1
}
new_case "every other job of release.yml waits for the check job"
for job in $(yq '.jobs | keys | .[]' "$release_workflow"); do
  if [ "$job" != check ] && ! waits_for_check "$job"; then
    problems+=("job ${job} does not wait for check")
  fi
done
end_case

echo "${count} cases, ${failures} failed"
if [ "$failures" -ne 0 ]; then
  exit 1
fi
