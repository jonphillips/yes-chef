#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swiftlint lint --strict --config .swiftlint.yml --cache-path .build/swiftlint-cache

# Search with grep, not rg: ripgrep is not a project prerequisite, and when it
# is missing the old `|| true` turned "the check never ran" into a green result.
# grep exit 1 means "no matching lines"; anything higher is a real search
# failure and must be fatal.
scan_bundle_ids() {
  local pattern="$1" file="$2" out status
  if [[ ! -f "$file" ]]; then
    printf 'check-drift.sh: expected file not found: %s\n' "$file" >&2
    return 1
  fi
  set +e
  out="$(grep -nE -- "$pattern" "$file")"
  status=$?
  set -e
  if (( status > 1 )); then
    printf 'check-drift.sh: bundle-id search failed on %s (grep exit %d)\n' "$file" "$status" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

project_yml_hits="$(scan_bundle_ids 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml)" || exit 1
pbxproj_hits="$(scan_bundle_ids 'PRODUCT_BUNDLE_IDENTIFIER =' YesChef.xcodeproj/project.pbxproj)" || exit 1

# Both files are checked in and both declare bundle identifiers. Zero hits means
# the search did not actually inspect them, which is exactly the silent no-op
# this guard exists to prevent.
if [[ -z "$project_yml_hits" || -z "$pbxproj_hits" ]]; then
  cat >&2 <<'EOF'
check-drift.sh: found no PRODUCT_BUNDLE_IDENTIFIER lines to check.
Both project.yml and YesChef.xcodeproj/project.pbxproj should declare them, so
the bundle-id drift check did not really run. Refusing to report success.
EOF
  exit 1
fi

bundle_id_lines="$(
  printf '%s\n%s\n' "$project_yml_hits" "$pbxproj_hits" | sed -E 's/[",;]//g'
)"
unexpected_bundle_ids="$(printf '%s\n' "$bundle_id_lines" | awk '
  /PRODUCT_BUNDLE_IDENTIFIER/ {
    value = $NF
    if (value != "com.jonphillips.yeschef" &&
        value != "com.jonphillips.yeschef.share-extension" &&
        value != "com.jonphillips.yeschef.tests") {
      print
    }
  }
')"
if [[ -n "$unexpected_bundle_ids" ]]; then
  cat <<EOF
Unexpected app bundle identifier drift:
$unexpected_bundle_ids

Expected only:
- com.jonphillips.yeschef
- com.jonphillips.yeschef.share-extension
- com.jonphillips.yeschef.tests
EOF
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

# ChatSurface's static factories are the only allowed construction path. Search
# every app Swift source with grep so a raw initializer cannot quietly spread
# past the contract definition. As above, grep exit 1 means "no matches";
# only an actual search failure is fatal.
chat_surface_definition="YesChefApp/ChatSurface.swift"
chat_surface_source_count=0
unexpected_chat_surface_initializers=""

while IFS= read -r source; do
  chat_surface_source_count=$((chat_surface_source_count + 1))
  set +e
  chat_surface_hits="$(grep -nE -- 'ChatSurface[[:space:]]*\(' "$source")"
  status=$?
  set -e
  if (( status > 1 )); then
    printf 'check-drift.sh: ChatSurface initializer search failed on %s (grep exit %d)\n' "$source" "$status" >&2
    exit 1
  fi
  if [[ -n "$chat_surface_hits" && "$source" != "$chat_surface_definition" ]]; then
    unexpected_chat_surface_initializers="${unexpected_chat_surface_initializers}
$source:
$chat_surface_hits
"
  fi
done < <(find YesChefApp -type f -name '*.swift' -print)

if (( chat_surface_source_count == 0 )); then
  cat >&2 <<'EOF'
check-drift.sh: found no YesChefApp Swift sources to inspect for raw ChatSurface initializers.
The construction-path guard did not really run. Refusing to report success.
EOF
  exit 1
fi

if [[ -n "$unexpected_chat_surface_initializers" ]]; then
  cat <<EOF
Raw ChatSurface initializers are only allowed in $chat_surface_definition:
$unexpected_chat_surface_initializers
EOF
  exit 1
fi

swift test --package-path YesChefPackage

# ---------------------------------------------------------------------------
# The app test target (YesChefAppTests → the YesChefTests bundle)
#
# Until 2026-07-27 this script ended at the line above, and that was the whole
# problem: `swift test --package-path YesChefPackage` covers the package and
# nothing else. YesChefAppTests held 26 tests that no command in this repo —
# not this script, not ci.yml, not the standing `generic/platform=iOS` build —
# ever compiled, let alone ran. They had drifted for months and this script
# reported green the entire time. That is the same "a check that reports the
# wrong thing when it finds nothing" failure the bundle-id and ChatSurface
# guards above are written to prevent, arriving from an unguarded direction:
# not a search that matched nothing, but a target that was never asked.
#
# What runs here is `build-for-testing`, not `test`. That is a deliberate split:
#
#   • `build-for-testing` compiles AND LINKS the test bundle. It needs a
#     simulator *destination* but never boots one, and it costs ~10s
#     incrementally. It is what catches the failure mode that actually
#     accumulated — code that was not even known to compile.
#   • Running the tests boots a simulator. That is exactly the loop the
#     Verification Pattern keeps Codex out of, and empirically `xcodebuild
#     test-without-building` hung past 10 minutes in its teardown phase on 2 of
#     3 local runs even though the tests themselves finished in 0.6s. An
#     unattended gate cannot depend on that.
#
# So execution is opt-in via YESCHEF_RUN_APP_TESTS=1, and the block below always
# prints where app-test execution stands so the gap is never silent again.
#
# 21 of the 26 tests pass when run; 5 issues remain in 3 suites, inventoried in
# docs/efforts/app-target-tests-to-core.md. Two are missing dependency
# overrides, two are a live servings-scaling bug, one is an open product
# question. Do not quietly edit those assertions to match today's behavior.
# ---------------------------------------------------------------------------

app_test_scheme="YesChef"
app_test_destination="platform=iOS Simulator,name=iPhone 17 Pro"

if [[ -n "${YESCHEF_SKIP_APP_TEST_BUILD:-}" ]]; then
  cat >&2 <<EOF

==============================================================================
  APP TEST TARGET NOT VERIFIED — YESCHEF_SKIP_APP_TEST_BUILD is set.
  YesChefAppTests was neither compiled nor run by this invocation. Green below
  says nothing about it. Unset the variable before treating a run as complete.
==============================================================================

EOF
else
  # Before building: assert the target is still WIRED. A build that compiles
  # nothing exits 0, so the build's own status cannot distinguish "the tests
  # pass the compiler" from "the tests are no longer part of this scheme" —
  # which is the state the repo was in, in effect, for months. Both inputs are
  # checked in, so this costs nothing and follows the same idiom as the
  # bundle-id and ChatSurface guards above: zero hits means the check did not
  # really run, and that is a failure, not a pass.
  app_test_scheme_file="YesChef.xcodeproj/xcshareddata/xcschemes/YesChef.xcscheme"
  if [[ ! -f "$app_test_scheme_file" ]]; then
    printf 'check-drift.sh: expected file not found: %s\n' "$app_test_scheme_file" >&2
    exit 1
  fi
  if ! grep -q 'BuildableName *= *"YesChefTests.xctest"' "$app_test_scheme_file"; then
    cat >&2 <<EOF
check-drift.sh: $app_test_scheme_file has no YesChefTests testable reference.
The app test target is not in the scheme's test action, so build-for-testing
would not build it and a green run below would mean nothing. Restore it in
project.yml and run xcodegen generate.
EOF
    exit 1
  fi

  set +e
  app_test_source_count="$(find YesChefAppTests -type f -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
  set -e
  if (( app_test_source_count == 0 )); then
    cat >&2 <<'EOF'
check-drift.sh: found no Swift sources in YesChefAppTests.
build-for-testing would build an empty bundle and report success. Refusing to
report success on a check that inspected nothing.
EOF
    exit 1
  fi
  echo "App test target: $app_test_source_count source file(s), wired into the scheme."

  echo "Building the app test target (YesChefTests) for ${app_test_destination}..."
  # `set +e` rather than relying on `set -e`: the point of this stage is to say
  # WHY it failed, and `set -e` would exit before the message.
  set +e
  xcodebuild build-for-testing \
    -scheme "$app_test_scheme" \
    -destination "$app_test_destination" \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO
  app_test_build_status=$?
  set -e
  if (( app_test_build_status != 0 )); then
    cat >&2 <<EOF
check-drift.sh: build-for-testing failed for scheme $app_test_scheme (exit $app_test_build_status).
Nothing else in this repo compiles YesChefAppTests, so a break here is usually
stale test code rather than a regression in the app.
EOF
    exit 1
  fi

  if [[ -n "${YESCHEF_RUN_APP_TESTS:-}" ]]; then
    echo "Running the app test target (YESCHEF_RUN_APP_TESTS is set)..."
    xcodebuild test-without-building \
      -scheme "$app_test_scheme" \
      -destination "$app_test_destination" \
      -skipMacroValidation \
      CODE_SIGNING_ALLOWED=NO
  else
    cat <<'EOF'

App test target: COMPILED AND LINKED, NOT RUN.
Set YESCHEF_RUN_APP_TESTS=1 to execute it (boots a simulator; expect 21 of 26
to pass — see docs/efforts/app-target-tests-to-core.md for the 5 that do not).

EOF
  fi
fi

# ---------------------------------------------------------------------------
# Handoff hygiene (WARN ONLY — never fails the build)
#
# docs/CURRENT_HANDOFF.md drifts because nobody sees its size until they happen
# to look. Measured over its history the drift is a sawtooth with a *rising
# floor*: 4307 words cut to 565 (Jul 2), 2204 cut to 1514 (Jul 13), 2273 cut to
# 1680 (Jul 18), then 4554 by Jul 26 — each manual cleanup leaves more behind
# than the last. These two counts make that visible on every dispatch.
#
# These run last on purpose: they are the final thing printed, so they survive
# into the verification output pasted into a PR, which is where the architect
# writes the handoff bump anyway. If `swift test` above failed there is a bigger
# problem and doc hygiene can wait.
#
# Warn-only is deliberate. A hard failure on an unrelated slice's verification
# gets bypassed, and the point is visibility, not enforcement.
#
# Written for bash 3.2 (/bin/bash on macOS): no arrays, because an empty array
# under `set -u` is an unbound-variable error there.
# ---------------------------------------------------------------------------

handoff_doc="docs/CURRENT_HANDOFF.md"
done_log="docs/DONE-LOG.md"
handoff_warnings=""
handoff_warning_count=0

# Tunable, so a genuinely full queue can raise the bar without editing this file.
max_pr_links="${HANDOFF_MAX_PR_LINKS:-5}"
max_words="${HANDOFF_MAX_WORDS:-3200}"

add_handoff_warning() {
  handoff_warnings="${handoff_warnings}
  • $1
"
  handoff_warning_count=$(( handoff_warning_count + 1 ))
}

if [[ ! -f "$handoff_doc" ]]; then
  # The handoff is the project's single dispatch front door; its absence is not
  # a hygiene nit. Still non-fatal here, but say so loudly.
  add_handoff_warning "$handoff_doc is missing — the dispatch front door does not exist."
else
  # A merged-PR link in the handoff is the best available proxy for a rule-7
  # violation: finished work always arrives citing its PR. This count is 0 on
  # every healthy version of the file in git history and climbs into the dozens
  # right before a cleanup becomes necessary — a sharper signal than length,
  # since length also tracks how much real work is legitimately queued.
  #
  # `grep -o | wc -l` counts occurrences. `grep -c` would count matching LINES,
  # which collapses a header paragraph citing a dozen PRs down to 1.
  #
  # The `|| true` is load-bearing: grep exits 1 on zero matches, and under
  # `set -o pipefail` that failure propagates out of the substitution and `set -e`
  # kills the script. Without it this guard hard-fails the whole run at exactly
  # the moment the handoff is *perfectly clean* — the same "a check that reports
  # the wrong thing when it finds nothing" failure this file guards against
  # above, arriving from the opposite direction.
  pr_links="$(grep -oE 'yes-chef/pull/[0-9]+' "$handoff_doc" | wc -l | tr -d ' ' || true)"
  if (( pr_links > max_pr_links )); then
    add_handoff_warning "$handoff_doc cites $pr_links merged PRs (soft cap $max_pr_links).
    Each is probably a done-blurb. AGENTS.md rule 7: if the sentence describes finished work it
    belongs in $done_log instead. Legitimate exceptions are spec pointers (a punch-list comment)
    and provenance for a blocked effort."
  fi

  words="$(wc -w < "$handoff_doc" | tr -d ' ')"
  if (( words > max_words )); then
    add_handoff_warning "$handoff_doc is $words words (soft cap $max_words).
    It is read cold on every dispatch, so length is a recurring tax. Look for Ready Efforts
    entries that describe closed arcs, and for history that crept in around the standing guards."
  fi
fi

# Rule 7 pairs the two writes: the DONE-LOG entry and the handoff edit ride the
# same approved PR branch. PRs #230 and #231 both merged without a DONE-LOG
# entry and the loss stayed invisible until a manual audit — this is the check
# that catches that.
#
# Two narrowings, both learned from the first branch this ran on:
#
# 1. It only speaks once the branch is PUSHED. Rule 7's write is owed by merge,
#    not by the first compile, so firing on every local mid-dispatch run made a
#    warning that was correct to ignore — which is how the two *useful* counts
#    above get ignored too. A local-only branch is still being written; a pushed
#    one is in review and the DONE-LOG entry is genuinely due.
#
# 2. It checks that DONE-LOG names THIS branch, not merely that the file was
#    touched. Presence alone is a false negative the moment a branch also
#    backfills history for some earlier PR — which is exactly what the branch
#    that introduced this check was doing, so its very first run passed for the
#    wrong reason. Every entry in DONE-LOG already cites its branch
#    ("branch `codex/...`"), so the branch name is a reliable, zero-ceremony
#    marker that the new prose is about the work in hand.
#
# Compared against the merge base with main so it reflects the branch's whole
# diff — committed and working tree alike — not just the last commit.
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -n "$branch" && "$branch" != "main" && "$branch" != "HEAD" ]] \
  && git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  merge_base="$(git merge-base HEAD main 2>/dev/null || true)"
  if [[ -n "$merge_base" ]]; then
    # `git diff <commit> -- path` is working tree vs that commit, so this covers
    # committed and uncommitted work in one pass. Untracked files never show up
    # in a diff, hence the separate porcelain pass for the file list.
    changed="$(
      {
        git diff --name-only "$merge_base" 2>/dev/null || true
        git status --porcelain 2>/dev/null | sed -E 's/^.{3}//' || true
      } | sort -u
    )"
    if [[ -n "$changed" ]]; then
      touches_source="$(printf '%s\n' "$changed" | grep -cE '^(YesChefApp|YesChefPackage)/' || true)"
      touches_handoff="$(printf '%s\n' "$changed" | grep -Fxc "$handoff_doc" || true)"
      # Added lines only: a branch that merely reflows existing DONE-LOG prose
      # has not written its own entry.
      names_branch="$(
        git diff "$merge_base" -- "$done_log" 2>/dev/null \
          | grep '^+' | grep -cF "$branch" || true
      )"
      if (( touches_source > 0 || touches_handoff > 0 )) && (( names_branch == 0 )); then
        add_handoff_warning "This branch is pushed and changes source and/or $handoff_doc, but
    $done_log has no entry naming branch '$branch'. The DONE-LOG write and the handoff edit ride
    the same approved PR branch (AGENTS.md rule 7). Owed by merge — not necessarily today."
      fi
    fi
  fi
fi

if (( handoff_warning_count > 0 )); then
  printf '\n%s\n' "=============================================================================="
  printf '  HANDOFF HYGIENE — %d warning(s). Not a build failure.\n' "$handoff_warning_count"
  printf '%s\n' "=============================================================================="
  printf '%s\n' "$handoff_warnings"
fi
