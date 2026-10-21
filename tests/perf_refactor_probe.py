#!/usr/bin/env python3
"""Offline differential SQL tests and optimized microbenchmark. No DB/network.

python3 tests/perf_refactor_probe.py [--bench]
Requires rustc and baseline commit in git; creates binaries only in a temp dir.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "4c68b84"

def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--bench", action="store_true")
    args = parser.parse_args()
    rustc = shutil.which("rustc") or str(Path.home() / ".cargo/bin/rustc")
    baseline = subprocess.check_output(["git", "show", f"{BASELINE}:src/sql.rs"], cwd=ROOT, text=True)
    with tempfile.TemporaryDirectory(prefix="wt-sql-perf-") as directory:
        directory = Path(directory)
        legacy = directory / "legacy.rs"
        legacy.write_text(baseline)
        source = directory / "probe.rs"
        source.write_text(
            'mod config { pub const MAX_LOG_DAMAGE_PER_MINUTE: f64 = 3000.0; }\n'
            f'#[path = "{ROOT / "src/sql.rs"}"] mod sql;\n'
            f'#[path = "{legacy}"] mod legacy;\n'
            + (ROOT / "tests/fixtures/sql_classification_probe.rs").read_text())
        executable = directory / "probe"
        command = [rustc, "--edition=2021", "-A", "dead_code", "-C", "opt-level=3", str(source), "-o", str(executable)]
        if not args.bench:
            command.append("--test")
        subprocess.run(command, check=True, env=os.environ.copy())
        subprocess.run([str(executable)], check=True)

if __name__ == "__main__":
    main()
