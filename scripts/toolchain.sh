#!/usr/bin/env bash
# Scope Xcode selection to this build. SwiftUI's macOS 27 State macro and
# XCTest require components absent from the standalone Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
