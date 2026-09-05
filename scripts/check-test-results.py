#!/usr/bin/env python3
"""Reject failed or incomplete XCTest runs and retain a source-linked receipt."""

import argparse
import json
from pathlib import Path
import subprocess


def validate(summary, minimum_tests):
    if summary.get("result") != "Passed" or summary.get("failedTests", 0):
        raise ValueError("XCTest did not report a passing run")
    total = summary.get("totalTestCount", 0)
    if total < minimum_tests:
        raise ValueError(f"Only {total} tests discovered; expected at least {minimum_tests}")
    if not summary.get("passedTests", 0):
        raise ValueError("No tests executed successfully")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("minimum_tests", type=int)
    args = parser.parse_args()
    summary = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(args.bundle),
    ]))
    receipt = {
        "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "trackedChanges": bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], text=True).strip()),
        "minimumTests": args.minimum_tests,
        "summary": summary,
    }
    receipt_path = args.bundle.with_suffix(".receipt.json")
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    validate(summary, args.minimum_tests)
    print(f"Verified {summary['totalTestCount']} tests; receipt: {receipt_path}")


if __name__ == "__main__":
    main()
