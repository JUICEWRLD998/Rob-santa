#!/usr/bin/env bash
# Static checks for everything in src/. Run before every playtest:  bash tools/check.sh
# Exit code is non-zero if either tool reports a problem.
set -u
cd "$(dirname "$0")/.."
BIN=tools/bin
status=0

node tools/sourcemap.mjs || exit 1

echo "== selene (lint)"
"$BIN/selene.exe" --no-summary src || status=1

echo "== luau-lsp (types)"
"$BIN/luau-lsp.exe" analyze \
	--platform=roblox \
	--sourcemap=sourcemap.json \
	--definitions=@roblox=tools/types/globalTypes.d.luau \
	src || status=1

if [ $status -eq 0 ]; then echo "== CLEAN"; else echo "== PROBLEMS FOUND"; fi
exit $status
