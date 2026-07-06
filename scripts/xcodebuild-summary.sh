#!/usr/bin/env bash
set -euo pipefail

# Run xcodebuild but surface only a summary to the terminal/chat.
#
# The full log always lands in a file; we print just the matching lines
# (errors, warnings, the verdict) plus the exit code. This keeps package
# resolution, dependency graphs, compile commands, and signing noise out of
# an agent's context while still leaving the raw log addressable when a
# failure needs real diagnosis.
#
# Usage: scripts/xcodebuild-summary.sh <xcodebuild args...>
# Example:
#   scripts/xcodebuild-summary.sh \
#     -scheme YesChef \
#     -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5) (16GB)' \
#     -skipMacroValidation \
#     build

log="$(mktemp -t yeschef-xcodebuild.XXXXXX).log"

# Mirror check-drift.sh's toolchain selection so both paths build the same way.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

# Capture, don't pipe: piping into rg would discard the full log (needed when a
# build fails for a non-compile reason) and mask xcodebuild's exit status.
set +e
xcodebuild "$@" >"$log" 2>&1
status=$?
set -e

rg -n "error:|warning:|BUILD SUCCEEDED|BUILD FAILED|Testing failed|Linker command failed|The following build commands failed" "$log" || true

echo "--- exit=$status  full log: $log"
exit "$status"
