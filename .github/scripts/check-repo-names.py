#!/usr/bin/env python3
"""Check for duplicate repository names across product groups."""

import sys
from collections import defaultdict
from pathlib import Path


def check_duplicate_repos() -> int:
    """Detect duplicate repo names across products/*/repos/*.yaml files."""
    repo_map = defaultdict(list)  # repo_name -> [file_paths]

    # Find all repo yaml files
    repo_files = Path("products").glob("*/repos/*.yaml")

    for repo_file in repo_files:
        repo_name = repo_file.stem  # filename without .yaml extension
        repo_map[repo_name].append(str(repo_file))

    # Check for duplicates
    duplicates = {
        name: paths for name, paths in repo_map.items() if len(paths) > 1
    }

    if duplicates:
        print("ERROR: Duplicate repository names found:")
        for repo_name, paths in sorted(duplicates.items()):
            print(f"  {repo_name}:")
            for path in paths:
                print(f"    - {path}")
        return 1

    print("OK: No duplicate repository names found.")
    return 0


if __name__ == "__main__":
    sys.exit(check_duplicate_repos())
