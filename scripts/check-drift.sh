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

swift test --package-path YesChefPackage

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

