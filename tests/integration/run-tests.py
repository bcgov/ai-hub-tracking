from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
SRC_DIR = ROOT_DIR / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

import pytest

from ai_hub_integration.runner import build_marker_expression, normalize_selector


def parse_args() -> argparse.Namespace:
    """Parse command-line options for the Python integration test runner."""
    parser = argparse.ArgumentParser(description="Run Python integration tests for AI Services Hub APIM")
    parser.add_argument("tests", nargs="*", help="Optional pytest paths or suite aliases")
    parser.add_argument("-e", "--env", dest="environment", default=os.getenv("TEST_ENV", "test"))
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument(
        "-x",
        "--exclude",
        default="",
        help="Comma-separated list of suite aliases or pytest paths to exclude",
    )
    parser.add_argument("--group", choices=["all", "direct", "proxy"], default="all")
    parser.add_argument("--include-ai-eval", action="store_true")
    return parser.parse_args()


def main() -> int:
    """Translate CLI options into pytest arguments and execute the selected suites."""
    args = parse_args()
    os.environ["TEST_ENV"] = args.environment

    pytest_args = ["tests", "-m", build_marker_expression(args.group, args.include_ai_eval)]
    if args.verbose:
        pytest_args.insert(0, "-vv")
    else:
        pytest_args.insert(0, "-q")

    if args.tests:
        pytest_args = pytest_args[:1] + [normalize_selector(test) for test in args.tests] + pytest_args[1:]

    if args.exclude:
        for item in args.exclude.split(","):
            candidate = item.strip()
            if candidate:
                pytest_args.append(f"--ignore={normalize_selector(candidate)}")

    return pytest.main(pytest_args)


if __name__ == "__main__":
    raise SystemExit(main())
