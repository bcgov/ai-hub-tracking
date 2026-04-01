#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ $# -gt 0 && "$1" != -* && "$1" =~ ^(dev|test|prod)$ ]]; then
    export TEST_ENV="$1"
    shift
fi

if [[ -z "${TEST_ENV:-}" ]]; then
    export TEST_ENV="test"
fi

ARGS=("$@")
HAS_ENV_FLAG="false"
for arg in "${ARGS[@]}"; do
    if [[ "${arg}" == "--env" || "${arg}" == "-e" ]]; then
        HAS_ENV_FLAG="true"
        break
    fi
done

if command -v uv >/dev/null 2>&1; then
    uv sync --group dev
    if [[ "${HAS_ENV_FLAG}" == "true" ]]; then
        exec uv run python ./run-tests.py "${ARGS[@]}"
    fi
    exec uv run python ./run-tests.py --env "${TEST_ENV}" "${ARGS[@]}"
fi

if command -v python >/dev/null 2>&1; then
    if [[ "${HAS_ENV_FLAG}" == "true" ]]; then
        exec python ./run-tests.py "${ARGS[@]}"
    fi
    exec python ./run-tests.py --env "${TEST_ENV}" "${ARGS[@]}"
fi

echo "Missing required runtime: install uv or python to run integration tests." >&2
exit 1
