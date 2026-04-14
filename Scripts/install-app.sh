#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Agent Meter"
APP_PATH="$ROOT_DIR/.build/app/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
"$ROOT_DIR/Scripts/build-app.sh"
rm -rf "$INSTALL_PATH"
ditto "$APP_PATH" "$INSTALL_PATH"
echo "$INSTALL_PATH"
