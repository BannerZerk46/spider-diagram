#!/usr/bin/env python3
"""Publish a new version of Spider Diagram.

    python3 release.py "One-sentence summary" "What changed, in more detail (optional)"

Adds the version to the changelog in index.html (the app's version menu lists it, and the update
notice shows the summary), builds the four release files (build.py --release), commits everything,
pushes to GitHub (installed copies read dist/version.json from there and offer to update), and creates
a GitHub release with the four files attached, so the download links in the README always give the
newest version.
Needs the GitHub command-line tool, logged in once:  gh auth login
"""
import json, os, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
START, END = '<script id="changelog" type="application/json">\n', '\n</script>'


def run(*cmd, env=None):
    print('$', ' '.join(cmd))
    subprocess.run(cmd, cwd=HERE, check=True, env=env)


def add_to_changelog(version, summary, notes):
    page = HERE / 'index.html'
    html = page.read_text(encoding='utf-8')
    head, rest = html.split(START, 1)
    data, tail = rest.split(END, 1)
    log = json.loads(data)
    log.insert(0, {'version': version, 'summary': summary, 'notes': notes})
    page.write_text(head + START + json.dumps(log, indent=1, ensure_ascii=False) + END + tail, encoding='utf-8')


def main():
    args = [a.strip() for a in sys.argv[1:]]
    if not 1 <= len(args) <= 2 or not args[0]:
        sys.exit(__doc__)
    summary, notes = args[0], args[1] if len(args) > 1 else ''
    version = time.strftime('%Y.%m.%d.%H%M', time.gmtime())
    add_to_changelog(version, summary, notes)
    run(sys.executable, 'build.py', '--release', env={**os.environ, 'SPIDER_VERSION': version})
    run('git', 'add', '-A')
    run('git', 'commit', '-m', f'{summary}\n\n{notes}\n\nRelease {version}'.replace('\n\n\n\n', '\n\n'))
    run('git', 'push')
    files = sorted(str(p.relative_to(HERE)) for p in (HERE / 'dist').glob('spider-diagram-*'))
    body = f'{summary}\n\n{notes}'.strip()
    run('gh', 'release', 'create', f'v{version}', *files, '--title', f'Spider Diagram {version}', '--notes', body, '--latest')
    print(f'\nPublished {version}. Installed copies will offer the update the next time they start.')


if __name__ == '__main__':
    main()
