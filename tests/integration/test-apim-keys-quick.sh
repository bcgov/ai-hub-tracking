#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ -z "${TEST_ENV:-}" ]]; then
    export TEST_ENV="test"
fi

if command -v uv >/dev/null 2>&1; then
    uv sync --group dev
    exec uv run python ./run-tests.py --env "${TEST_ENV}" --group proxy -v apim-key-rotation
fi

if command -v python >/dev/null 2>&1; then
    exec python ./run-tests.py --env "${TEST_ENV}" --group proxy -v apim-key-rotation
fi

echo "Missing required runtime: install uv or python to run the key rotation integration test." >&2
exit 1