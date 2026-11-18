#!/usr/bin/env bash
# Builds the AgentCore direct-code-deployment package without Docker:
# Linux ARM64 wheels for Python 3.12, cross-installed by uv, plus server.py.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/../server"
out="$here/build/server-pkg"
rm -rf "$out" && mkdir -p "$out"
uv pip install --quiet \
  --python-platform aarch64-manylinux2014 --python-version 3.12 \
  --only-binary=:all: --target "$out" -r "$src/requirements.txt"
cp "$src/server.py" "$out/"
find "$out" -name '__pycache__' -type d -prune -exec rm -rf {} +
echo "packaged $(du -sh "$out" | cut -f1) into $out"
