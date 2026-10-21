#!/usr/bin/env python3
"""Publish a new version of Spider Diagram.

    python3 release.py "What changed"

Builds the four release files (build.py), commits everything, pushes to GitHub (installed copies
read dist/version.json from there and offer to update), and creates a GitHub release with the four
files attached, so the download links in the README always give the newest version.
Needs the GitHub command-line tool, logged in once:  gh auth login
"""
import json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run(*cmd):
    print('$', ' '.join(cmd))
    subprocess.run(cmd, cwd=HERE, check=True)


def main():
    if len(sys.argv) != 2 or not sys.argv[1].strip():
        sys.exit(__doc__)
    notes = sys.argv[1].strip()
    run(sys.executable, 'build.py')
    version = json.loads((HERE / 'dist' / 'version.json').read_text())['version']
    run('git', 'add', '-A')
    run('git', 'commit', '-m', f'{notes}\n\nRelease {version}')
    run('git', 'push')
    files = sorted(str(p.relative_to(HERE)) for p in (HERE / 'dist').glob('spider-diagram-*'))
    run('gh', 'release', 'create', f'v{version}', *files, '--title', f'Spider Diagram {version}', '--notes', notes, '--latest')
    print(f'\nPublished {version}. Installed copies will offer the update the next time they start.')


if __name__ == '__main__':
    main()
