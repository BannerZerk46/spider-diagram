#!/usr/bin/env python3
"""Build the single-file versions of Spider Diagram into dist/.

    python3 build.py

Makes exactly the four files that get handed out (dist/ is emptied first, so it always mirrors them):
    dist/spider-diagram-chromeos.html  the app on its own: Chromebooks, or any browser with nothing installed
    dist/spider-diagram-mac.zip        unzips to spider-diagram-mac.command (double-click in Finder); zipped
                                       because a bare .command usually loses its "executable" permission
                                       when it's downloaded or emailed
    dist/spider-diagram-linux          run it (or: sh spider-diagram-linux); --install adds it to the app menu
    dist/spider-diagram-windows.cmd    double-click in Explorer; --install adds it to the Start menu

plus dist/version.json, which installed copies read to find out about (and safely download) updates.

Every build is stamped with a version: the date and time it was built (UTC), e.g. 2026.10.19.1534.
To publish, commit and push dist/ to the GitHub repository named in release.json
({"repo": "username/spider-diagram"}); copies built with that set check
https://raw.githubusercontent.com/<repo>/main/dist/version.json and offer to update themselves.

Each is spider-diagram.py with index.html (which already contains the tour) and icon.svg packed
inside, behind a few lines of shell (or, on Windows, batch) that find Python 3 and run the same
file with it. The Linux and Mac files are identical apart from their names.
"""
import base64, hashlib, json, os, shutil, time, zipfile, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
DIST = HERE / 'dist'

# Read by sh as `_=":"` followed by a shell script; read by Python as one string assigned to `_`.
HEADER = """#!/bin/sh
_=''':'
# Spider Diagram, all in one file. These first lines are a small shell script that runs this same
# file with Python 3; everything after them is the Python program, with the app packed inside.
for py in python3 python; do
  if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1; then
    exec "$py" "$0" "$@"
  fi
done
echo
echo "Spider Diagram needs Python 3.8 or newer."
if [ "$(uname)" = Darwin ]; then
  echo "If your Mac offered to install the \\"command line developer tools\\", click Install, wait for it"
  echo "to finish, then open Spider Diagram again. Or get Python from https://www.python.org/downloads/"
else
  echo "Install it with your package manager (it's usually called python3), then try again."
fi
printf 'Press Return to close. '
read -r _
exit 1
'''
"""


# Windows: cmd.exe runs line 1 and jumps to :run; Python is started with -x, which skips line 1,
# and then sees the rest of the batch script as a string. Saved with CRLF line endings, which
# cmd.exe needs to find labels reliably.
HEADER_WINDOWS = """@echo off & goto :run
\"\"\"
:run
setlocal
rem Spider Diagram, all in one file. These first lines find Python 3 and run this same file with it;
rem everything after them is the Python program, with the app packed inside.
set "CHECK=import sys; sys.exit(sys.version_info < (3, 8))"
py -3 -c "%CHECK%" >nul 2>&1
if not errorlevel 1 goto :with_py
python -c "%CHECK%" >nul 2>&1
if not errorlevel 1 goto :with_python
echo.
echo Spider Diagram needs Python 3.8 or newer.
echo Get it free from https://www.python.org/downloads/ and, while installing, tick "Add python.exe to PATH".
echo Then open Spider Diagram again.
echo.
pause
exit /b 1
:with_py
py -3 -x "%~f0" %*
if errorlevel 1 pause
exit /b
:with_python
python -x "%~f0" %*
if errorlevel 1 pause
exit /b
\"\"\"
"""


def pack(data: bytes) -> str:
    """Compressed, base64'd, as a parenthesised run of short string literals."""
    b64 = base64.b64encode(zlib.compress(data, 9)).decode()
    return '(\n' + '\n'.join(f"    '{b64[i:i + 100]}'" for i in range(0, len(b64), 100)) + '\n)'


def release_config():
    if os.environ.get('SPIDER_UPDATE_URL'):   # testing: publish to somewhere else
        return os.environ['SPIDER_UPDATE_URL']
    try:
        cfg = json.loads((HERE / 'release.json').read_text(encoding='utf-8'))
    except FileNotFoundError:
        return ''
    return f"https://raw.githubusercontent.com/{cfg['repo']}/{cfg.get('branch', 'main')}/dist/"


def stamp(text, old, new):
    assert text.count(old) == 1, f'{old!r} not found'
    return text.replace(old, new)


def build():
    version = os.environ.get('SPIDER_VERSION') or time.strftime('%Y.%m.%d.%H%M', time.gmtime())
    update_url = release_config()
    app = stamp((HERE / 'index.html').read_text(encoding='utf-8'), "const APP_VERSION = 'dev', APP_UPDATE_URL = '';",
                f"const APP_VERSION = {json.dumps(version)}, APP_UPDATE_URL = {json.dumps(update_url)};".replace('"', "'"))
    src = (HERE / 'spider-diagram.py').read_text(encoding='utf-8')
    src = stamp(src, "VERSION = 'dev'", f"VERSION = '{version}'")
    src = stamp(src, "UPDATE_URL = ''", f"UPDATE_URL = '{update_url}'")
    body = src.split('\n', 1)[1]   # drop the original #! line; HEADER brings its own
    # The header is now the first statement, so make the docstring explicit (used by --help).
    body = body.replace('"""Spider Diagram launcher.', '__doc__ = """Spider Diagram launcher.', 1)
    for name, data in (('EMBEDDED_HTML', app.encode('utf-8')), ('EMBEDDED_ICON', (HERE / 'icon.svg').read_bytes()),
                       ('EMBEDDED_ICO', (HERE / 'icon.ico').read_bytes())):
        body = stamp(body, f'{name} = None', f'{name} = ' + pack(data))
    program = HEADER + body

    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    (DIST / 'spider-diagram-chromeos.html').write_text(app, encoding='utf-8')
    linux = DIST / 'spider-diagram-linux'
    linux.write_text(program, encoding='utf-8')
    linux.chmod(0o755)
    with zipfile.ZipFile(DIST / 'spider-diagram-mac.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        info = zipfile.ZipInfo('spider-diagram-mac.command', time.localtime()[:6])
        info.create_system = 3                  # unix, so the permissions below are honoured
        info.external_attr = 0o100755 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, program)
    windows = DIST / 'spider-diagram-windows.cmd'
    windows.write_bytes((HEADER_WINDOWS + body).replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'))
    # What installed copies check: the newest version, and checksums so a broken download is never installed.
    files = ('spider-diagram-linux', 'spider-diagram-windows.cmd', 'spider-diagram-chromeos.html')
    (DIST / 'version.json').write_text(json.dumps({'version': version, 'sha256': {
        f: hashlib.sha256((DIST / f).read_bytes()).hexdigest() for f in files}}, indent=1) + '\n', encoding='utf-8')
    for f in sorted(DIST.iterdir()):
        print(f'{f.relative_to(HERE)}  {f.stat().st_size // 1024} KB')
    print(f'Version {version}' + ('' if update_url else '  (no release.json yet: these copies won\'t look for updates)'))


if __name__ == '__main__':
    build()
