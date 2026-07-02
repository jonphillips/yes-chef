#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swiftlint lint --strict --config .swiftlint.yml --cache-path .build/swiftlint-cache

bundle_id_lines="$(
  {
    rg --no-heading --line-number "PRODUCT_BUNDLE_IDENTIFIER:" project.yml || true
    rg --no-heading --line-number "PRODUCT_BUNDLE_IDENTIFIER =" YesChef.xcodeproj/project.pbxproj || true
  } | sed -E 's/[",;]//g'
)"
unexpected_bundle_ids="$(printf '%s\n' "$bundle_id_lines" | awk '
  /PRODUCT_BUNDLE_IDENTIFIER/ {
    value = $NF
    if (value != "com.jonphillips.yeschef" && value != "com.jonphillips.yeschef.share-extension") {
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
EOF
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

swift test --package-path YesChefPackage
