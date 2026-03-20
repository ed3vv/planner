#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup.sh — Bootstrap the Widget Xcode project using XcodeGen
#
# Prerequisites:
#   • Xcode 15+ installed (for macOS 14 SDK)
#   • XcodeGen installed:
#       brew install xcodegen
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_YML="$PROJECT_DIR/project.yml"
PROJECT_NAME="Widget"

echo "==> Checking prerequisites..."

if ! command -v xcodegen &>/dev/null; then
    echo ""
    echo "ERROR: xcodegen is not installed."
    echo "Install it with:  brew install xcodegen"
    echo ""
    exit 1
fi

echo "    xcodegen: $(xcodegen --version 2>/dev/null || echo 'found')"
echo ""

echo "==> Generating Xcode project from project.yml..."
xcodegen generate \
    --spec "$PROJECT_YML" \
    --project "$PROJECT_DIR" \
    --use-cache

echo ""
echo "==> Project generated: $PROJECT_DIR/$PROJECT_NAME.xcodeproj"
echo ""
echo "==> Opening project in Xcode..."
open "$PROJECT_DIR/$PROJECT_NAME.xcodeproj"

echo ""
echo "Done! Next steps inside Xcode:"
echo "  1. Select the 'WidgetHost' scheme and your Mac as the run destination."
echo "  2. Set a valid development team under:"
echo "       Targets > WidgetHost > Signing & Capabilities"
echo "       Targets > MyWidget  > Signing & Capabilities"
echo "  3. Press Cmd+R to build and run."
echo "  4. After launch, open Notification Center and add 'MyWidget'."
