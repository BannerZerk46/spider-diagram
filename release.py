#!/usr/bin/env python3
"""Publish a new version of Spider Diagram.

    python3 release.py "One-sentence summary" "What changed, in more detail (optional)"

Adds the version to the changelog in index.html (the app's version menu lists it, and the update
notice shows the summary), builds the four release files (build.py --release), commits everything,
pushes to GitHub (installed copies read dist/version.json from there and offer to update), and creates
a GitHub release with the four files attached, so the download links in the README always give the
newest version.

If GitHub has trouble partway through (pushing and the release are each tried a few times), run it
again with no arguments to finish the unfinished release, rather than starting another:

    python3 release.py

Needs the GitHub command-line tool, logged in once:  gh auth login
"""
import json, os, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
START, END = '<script id="changelog" type="application/json">\n', '\n</script>'
FILES = ['spider-diagram-chromeos.html', 'spider-diagram-linux', 'spider-diagram-mac.zip', 'spider-diagram-windows.cmd']


def run(*cmd, env=None):
    print('$', ' '.join(cmd))
    subprocess.run(cmd, cwd=HERE, check=True, env=env)


def ok(*cmd):
    """Whether cmd succeeds (quietly)."""
    return subprocess.run(cmd, cwd=HERE, capture_output=True).returncode == 0


def output(*cmd):
    return subprocess.run(cmd, cwd=HERE, capture_output=True, text=True).stdout.strip()


def retry(what, *cmd, done=None):
    """Run cmd, trying again a few times if it fails (GitHub sometimes has a bad few minutes). done():
    whether it actually went through anyway, worth checking before each retry."""
    for attempt, wait in enumerate([10, 30, 60, None], 1):
        try:
            return run(*cmd)
        except subprocess.CalledProcessError:
            if done and done():
                return
            if wait is None:
                sys.exit(f'\nCould not {what}. GitHub may be having trouble (https://www.githubstatus.com):\n'
                         f'run  python3 release.py  again later to finish this release.')
            print(f'Could not {what} (try {attempt}); trying again in {wait}s…')
            time.sleep(wait)


def changelog():
    html = (HERE / 'index.html').read_text(encoding='utf-8')
    head, rest = html.split(START, 1)
    data, tail = rest.split(END, 1)
    return head, json.loads(data), tail


def add_to_changelog(version, summary, notes):
    head, log, tail = changelog()
    log.insert(0, {'version': version, 'summary': summary, 'notes': notes})
    (HERE / 'index.html').write_text(head + START + json.dumps(log, indent=1, ensure_ascii=False) + END + tail, encoding='utf-8')


def pushed():
    """Whether this commit is on GitHub's main branch (as far as this copy last heard)."""
    return ok('git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/main')


def unfinished():
    """The version of a release that was committed here but not pushed or not published, or None."""
    version = json.loads((HERE / 'dist' / 'version.json').read_text())['version']
    if not output('git', 'log', '-1', '--format=%B').endswith(f'Release {version}'):
        return None   # the last commit isn't a release
    return version if not pushed() or not ok('gh', 'release', 'view', f'v{version}') else None


def publish(version):
    """Push the release commit and create the GitHub release (or finish one that's half there)."""
    _, log, _ = changelog()
    entry = next(e for e in log if e['version'] == version)
    if not pushed():
        retry('push to GitHub', 'git', 'push', 'origin', 'HEAD:main', done=lambda: ok('git', 'fetch') and pushed())
    tag, files = f'v{version}', [f'dist/{f}' for f in FILES]
    if not ok('gh', 'release', 'view', tag):
        body = f"{entry['summary']}\n\n{entry['notes']}".strip()
        retry('create the GitHub release', 'gh', 'release', 'create', tag, *files, '--title', f'Spider Diagram {version}',
              '--notes', body, '--latest', done=lambda: ok('gh', 'release', 'view', tag))
    # A release can be created with some files still missing if an upload failed: add any that are.
    have = output('gh', 'release', 'view', tag, '--json', 'assets', '-q', '.assets[].name').split('\n')
    missing = [f'dist/{f}' for f in FILES if f not in have]
    if missing:
        retry('upload the release files', 'gh', 'release', 'upload', tag, *missing, '--clobber')
    print(f'\nPublished {version}. Installed copies will offer the update the next time they start.')


def main():
    args = [a.strip() for a in sys.argv[1:]]
    pending = unfinished()
    if pending:
        if args:
            sys.exit(f'Version {pending} is committed but not published yet. Run  python3 release.py  (with no\n'
                     f'arguments) to finish it first, then release the new changes.')
        print(f'Finishing the release of {pending}.')
        return publish(pending)
    if not 1 <= len(args) <= 2 or not args[0]:
        sys.exit(__doc__)
    summary, notes = args[0], args[1] if len(args) > 1 else ''
    version = time.strftime('%Y.%m.%d.%H%M', time.gmtime())
    add_to_changelog(version, summary, notes)
    run(sys.executable, 'build.py', '--release', env={**os.environ, 'SPIDER_VERSION': version})
    run('git', 'add', '-A')
    run('git', 'commit', '-m', f'{summary}\n\n{notes}\n\nRelease {version}'.replace('\n\n\n\n', '\n\n'))
    publish(version)


if __name__ == '__main__':
    main()
