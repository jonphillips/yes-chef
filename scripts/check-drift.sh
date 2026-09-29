#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Noisy stages run through jon-platform's quiet-run: full log to a file, only
# errors and verdicts to the terminal, so an agent's context isn't flooded
# (jon-platform docs/agent-workflow.md § Token discipline). Without a platform
# checkout it's empty and the stages run verbose, exactly as before.
qr="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/quiet-run"
[[ -x "$qr" ]] || qr=""

$qr swiftlint lint --strict --config .swiftlint.yml --cache-path .build/swiftlint-cache

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

$qr swift test --package-path YesChefPackage

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
# 26 of the current 29 were verified passing 2026-07-27. The 3 added by Playbook
# S0.1 have NEVER been compiled or run: as of 2026-07-29 this stage does not
# reach them, because build-for-testing dies at
#   Ld .../PackageFrameworks/SQLiteData.framework/SQLiteData
# with missing StructuredQueriesCore symbols (exit 65) — the upstream defect
# described in CURRENT_HANDOFF's standing guard, reproduced on clean main. So
# "26 pass" is a fact about 2026-07-27, not a statement about today's tree.
#
# Do NOT bump this count from a report. Bump it only from the tail of an actual
# test-without-building run, because that is exactly how it went wrong: on
# 2026-07-29 it was raised to 29 on the strength of a summary, while the stage
# below had exited 65 and the tests had never been built.
#
# Execution stays opt-in because of the teardown hang above, not because
# anything is known-red. If this stage ever
# goes red, read docs/efforts/app-target-tests-to-core.md first: three of the
# five original failures were stale expectations left behind by an API swap that
# nothing ever ran, so "the test is wrong" and "the code is wrong" are both live
# possibilities. Do not edit assertions to match today's behavior without
# establishing which side moved.
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
  $qr xcodebuild build-for-testing \
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
    $qr xcodebuild test-without-building \
      -scheme "$app_test_scheme" \
      -destination "$app_test_destination" \
      -skipMacroValidation \
      CODE_SIGNING_ALLOWED=NO
  else
    cat <<'EOF'

App test target: COMPILED AND LINKED, NOT RUN.
Set YESCHEF_RUN_APP_TESTS=1 to execute it (boots a simulator; 26 of 29 last
verified 2026-07-27 — the 3 from Playbook S0.1 have never been run).

EOF
  fi
fi

# ---------------------------------------------------------------------------
# Handoff hygiene (WARN ONLY; never fails the build)
#
# The shared jon-platform check for the ADR-0005 document shape: NEXT_UP.md
# template and cap, merged-PR citations, a DONE-LOG entry naming a pushed
# branch, and the retired CURRENT_HANDOFF.md. It replaced this script's own
# handoff checks, which it was generalized from. Runs last, so its warnings
# survive into the verification output pasted into a PR.
# ---------------------------------------------------------------------------

check_handoff="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/check-handoff"
if [[ -x "$check_handoff" ]]; then
  "$check_handoff"
else
  echo "check-drift.sh: $check_handoff not found; handoff hygiene skipped." >&2
fi
