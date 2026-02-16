#!/usr/bin/env python3

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def run_command(command: list[str], cwd: Path | None = None) -> None:
    process = subprocess.run(command, cwd=cwd or ROOT)
    if process.returncode != 0:
        raise RuntimeError("Command failed")


def is_under_terraform_roots(path: Path) -> bool:
    if not path.exists() or path.suffix != ".tf":
        return False

    posix_path = path.as_posix()
    return posix_path.startswith("initial-setup/infra/") or posix_path.startswith(
        "infra-ai-hub/"
    )


def get_tflint_workdirs(changed_files: list[Path]) -> list[Path]:
    return sorted({(ROOT / file_path).parent for file_path in changed_files})


def main() -> int:
    changed_files = [
        Path(file_path)
        for file_path in sys.argv[1:]
        if is_under_terraform_roots(Path(file_path))
    ]

    if not changed_files:
        return 0

    try:
        for terraform_file in changed_files:
            run_command(
                [
                    "terraform",
                    "fmt",
                    "-check",
                    "-diff",
                    str(ROOT / terraform_file),
                ]
            )

        for terraform_workdir in get_tflint_workdirs(changed_files):
            run_command(["tflint", "--init"], cwd=terraform_workdir)
            run_command(
                ["tflint", "--minimum-failure-severity=error"], cwd=terraform_workdir
            )
    except RuntimeError:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
