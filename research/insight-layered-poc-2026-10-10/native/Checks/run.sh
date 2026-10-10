#!/bin/sh
set -eu
salini_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
salini_check_dir=$(mktemp -d -t salini-motion-checks)
trap 'rm -rf "$salini_check_dir"' EXIT
xcrun swiftc "$salini_root/Sources/MotionTimeline.swift" "$salini_root/Checks/main.swift" -o "$salini_check_dir/checks"
"$salini_check_dir/checks"
