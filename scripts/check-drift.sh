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
