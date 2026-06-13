#!/bin/bash
# Run the FamilyTreeCore test suite.
#
# Swift Testing (`import Testing`) ships with both full Xcode and the Command Line
# Tools, but under CLT-only machines SwiftPM doesn't add the framework search paths
# automatically, so we pass them explicitly. Under full Xcode, plain `swift test`
# works — which is what CI uses.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVDIR="$(xcode-select -p)"
if [[ "$DEVDIR" == *CommandLineTools* ]]; then
    FW="$DEVDIR/Library/Developer/Frameworks"
    IL="$DEVDIR/Library/Developer/usr/lib"
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$IL" \
        "$@"
else
    exec swift test "$@"
fi
