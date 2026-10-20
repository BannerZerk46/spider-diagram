@echo off & goto :run
"""
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
"""
__doc__ = """Spider Diagram launcher.

Serves the app on localhost and opens it in your browser, giving it real file handling that
browsers like Firefox can't do on their own: Save overwrites the current file, and Save as /
Open / Export show a native file dialog (macOS: Finder dialogs; Linux: zenity or kdialog;
Windows and elsewhere: Tk, which shows the system's own dialogs). Works with Python 3.8 or newer.

    spider-diagram.py                  # start on the homepage listing all your diagrams
    spider-diagram.py notes.spider     # open a specific file
    spider-diagram.py --install        # Linux / Windows: add to the app menu (Start menu) and open
                                       #   .spider files with it when double-clicked
    spider-diagram.py --uninstall      # undo --install

Installing and updating also work from inside the app: the homepage offers to install, and when a
newer version has been published (see build.py), the app offers to update itself in one click.

build.py turns this file plus index.html into single-file versions (dist/spider-diagram-linux,
dist/spider-diagram-mac.command and dist/spider-diagram-windows.cmd) that carry the app inside them.

The homepage lists .spider files found in your library folders (~/Documents to begin with; add
more from the homepage) plus every diagram you've opened or saved here. That list is kept in
~/.config/spider-diagram/library.json.

The server stops by itself about two minutes after you close the tab.
"""
import base64, hashlib, html, json, os, platform, re, secrets, shutil, struct, subprocess, sys, tempfile, threading, time, webbrowser, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
# build.py fills these in for the single-file versions; when None, index.html and icon.svg next to this file are used.
EMBEDDED_HTML = (
    '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'
    '5PyScfeIXECq6r7fvfdt6pwWmZGxh4dv4eG+FtMFUcwWHmuwMMrcLrv2wOvpWmOfXdiFZaLYVpV7q6rv0wkAJmu3FxfVqbQugTDf'
    'emyZIXVrZ26y++645U2swWCkLLzeVHxa9zLSQy2neJXRtOFUXvqLQcYAIEqsCs1NNz99Kqq3465mAR1fzK1atfjcf56MM09iTZNq'
    '05fWi+f083tHbpdaz2rjYOSm/fyj3hvN3Rdrah+M7PRQvhdvbsu1VjPsyrw0HI/dVX0iebeq/aR3qrAngJGubobifpJ+3t6Ld7LZ'
    '7Gql50O1p5V2avXlMCwZmV23Vy8sN95uthgMBtXu82vNVhsjWX2Uy8PDVgcGaJVSe9Kd6g03lcQmr3aaQ2vUTY1K2sM6X/CMeWOQ'
    'cJqJknIQJ+27IQgFk3K+aT5aaik1LVXy92lDmSLP+qJn2wO39CRtxNdNdrFWnddcV4QxTYH/uyk3skYxNdvU1GXRKaf2tW7RsDPq'
    'gzcquNnioZWT9u3tHEQrvTNqDEZSRyuYe1NejDcVG9hOJ18B0dF+ernNG7aebY7lbGlxaPQbICvn3dxYdKrN8c5uSmKz6nWaD52W'
    'WSrYumWv26uCbcyN10Sxtnt8KlTa/Yf7xmj4UlrZo1FjcVM+ZHRbbvbvR63cejZ266nSzW2/2VuvXzIPdb0y1GxHf1kXHib15WL6'
    'km9Ope76btDbOCsjUZ3kllolP7JS89V+o4v5trIdO7qn1uzha1v17NpjxykM7WJhMZjMl+XV/QQmvpcp6z3XWU+7g4bSL2l1u1G8'
    'E80nsT1q2O2c296N9NnqRVTzi0xuui5pZqrQO/S2m6y7TDzVnxZKYnl4fewkJlJnaFjDknn/WFl6jvVkTaajbn21A/b5WWt4kqyW'
    'Bpt7bZiuD0teteDacnrcaN/3di+7YUZ79eqiXXPyT62UnFfaeWXeTPU3w8nIHrRyvUVdc8up8kh8HpS7877ltZZuOX/fLK293UbP'
    '2hNPsfdD17HtzuuTZVVEubxP9Y0X7Wndeeg8ZB93Nw9j6+WuC9K2VHrILXfNfq63m3ZqSzEzA1lzdPuUr7YsyegoelN3llJRErOT'
    'biN7GFrp1X4s79Ne6/65mnN3r6u5NLDX29fscJ/u31v52tK2rcqoPNZcWdy72Ykupgd2e9ST53k5bcwOs/nNgzts10bVwcFTgIkG'
    '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'
)
EMBEDDED_ICON = (
    'eNqNU02PmzAQve+vmHoPDVIx32RZQQ5VpZ5yqtQ7AQPuGhsZZ0n+fccmVN10Vyqy8MybN7w3Bsr5tYfLKORckcGY6TkIlmWhS0KV'
    '7oM4DMMAGQReOVu+qktFQgghT3GRwwNA+cn34cfEW6bhG697XY9QTxPwRslnMAMDLn0LCNUr2DnAd/F8HU9KYBlXyy50MKPwbLoM'
    '3DBQ0nVj6+cZddx1Emf2BeahbrnsodNqdJy21i/+qFpkNw2TBnaPafPUdp0HRjmG4P1g7ihxlifs5FHwfTdIy7r54JRKwSWr9XeN'
    'OpbL24oYLhiBS4TzE7iu2yVeM9wicriZLGejJlBdNzPjyjb3GyWUrsjNFwneZ0d37NXixi6Dt76c62CzXWrWGMD3E6Mjd194a4aK'
    '5OhhYPYA1lgjJ0oJdFyIipy12D3a4bxVpuzB6FrOndIjTm1DURu2i2KIYpp5MDe1wJTmeb73tqdIJZn1rtULQ98djnjL/JuLmEZ/'
    'IDtGU08V0eos2zfwL8Xlht+mbrhuBIPG2sapmuu64/kkaPm9ckIzV0eTd4w4XBnFX/V/Vfa23+kUHz4p/w9O+pHYVJsB8KM64qkW'
    'PzMaHaOUPkEU0kIkdO9HNDlGiUVSmooYA0yOWI5XxN+gwiLYBRnNoNgUyqA/PJT2tz08/AZluheo'
)
EMBEDDED_ICO = (
    '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'
    'a0HY54uPN/Cum670c5vvsWKRNZ9zQkeSdRKM2d27Ih/YE65FYB3j10so8Kc68j06K2YvJ9+G71v7saAcvacSZNEHfdW6R8J1DozZ'
    '3bdyFLAnfe6P/Y9WjGDyI3VVkyn00RuRNYCP3pQ6aw0AstJnZFvrAnYZe9VoYE/9WT6f70/Nk33Ewic+FlBGnYyV+nN6jNndv3oM'
    'sKf8fHzVKAo8OoPI2STPruWZNpdRh7Y0nrNjzO6BinE6cyStPSkq+Rr8+iY+z74QUEZdmntR8Jhj9UDl+M7M7rT3hKgaT8G62wT1'
    'bDbtvSAwZuegel5WmdnzzvGKzJ6XViCn2sijz+N3x9eY146xMKY8mwqqZ4QzQusntzCUY1owVnCdypnF8zLJNa2e0omZwThy+LzL'
    'YYzRKRz1rC4mh7emMI+poJrC3cwRxt5BoGM366wU3eLvlLjc2qjna1qoejKes3RmdKZ7B4GOzsHqyUZuZ+yzsp0qJ++y8/A8A7lo'
    'nTAL/66RU2Y9p/hW/HMKY44unJlxbaczs3r0PjOzRyHz/TQplL6sw3rmgbn4XJWrw//Xmbr64p7H6mf1dDGeNHFxX4fS0UtvMHWr'
    'OT7+vzOL8/mdopN1N87L68Tz6bpsz9V5jlwH3Y3z+vVmHAl/I25uH6a3ek+nTeh3jOnF89FCxpVortpS/SPy8PyqpW6W9ZtX5m9j'
    'oU7aWCbJPBc6C3muWcR44n4/adlYNXfCbyqcOU7Nld9TcfaIq+cy6tAGGcgm+D0m6CziuRzwxMZWX08tqwvltxqwBzXie50b71Bz'
    'R8Rdb7xD6mQvbJaBrMxrY+eJ0FnEczngiYtX5vmO5zcrKHjkrxLr43mpkud2qg1l1KENMs0S2xsX7wydRTxvAp6k878lw8n39maJ'
    '+8JvtsjvtnAZdWhrY74HnUU8HwIemRfFcJPQwvMYzxN3yv7VwSPvCyijDm2mXHx/0VnEcxngiZ3jDCaXbZzsLY65GOLtcKxdqyYI'
    'KKNO4jxZRmQltjBmnuQR3UuHAk/0/Mj72BzZX1T2Mf1gq8RQym+wPDFPkDg5rkObKYc+reZD0FnkLhsOPG6137DMURDrJfOaxpMq'
    'TuGtpymE48JzTZmDchl1ch8IGZZFH5nfmHqUziK+1weeyJ68w8n/hxqJNQQoIxbLW8Xn6+d/FVCWmC2Ra4rIYa4RmUdAZ5HXVgA8'
    'MXudYv7w7ELBjH/yrZkqe1UDlK14qRi5mHgk6Czie3XgiZ8j5CuMuUHw7aeJED/JoGzd/0fLxQKdRXwvDDxt33uPptC+V3heVy+g'
    'LPsjtn2fDZ1FfL9byLjavCcuH8P38T+j8N/fFFCWurbvo6GzkO9DezOOdvez4vtka70b5Xb3v4JO6J7Qie9TN2X7XpR11kG3sU6t'
    '8/3hzizea+4UneuM/ZrUfabO1IWrCx18P+RiPGnikr7VUzZBl6z5GvfR5r0VbZzWiWqm9ub7rkKmKE0KpS/rsO4JU9yHpSOv3mp5'
    'SO7ArPuwbyS+D+N7p8v5PqfgzKye5UwdU5sEtJWLLPqoNY/L+b7lbi6fTiNH+TT68H3U5Y0leQWNJX1PWzmnuE+Z3Ysa5/SO5KEi'
    'Jxh1c2NyU0+jb9P8/uWRXMN+dHbBYHI+Op/OrZ5mPZtHGXVoU3VWbmI5f9fXxuSuPb2QQnyd97//Gn9XDxRQRh3aWuW81fJ3bW10'
    '7pKz+jZ5lhr8/ANqWTlRQDnw6bvS1irnqbbl/ptq434vqTSf/Hu2UNC+X0BZ5bLE/R5SrXPx4NpIrsEQ9V24rIACf/kt+f64SUBZ'
    'nh1ym/UbKopa99JhtRJnvmQweZ+cTyGMefgv8gw0sOdlAWWp4zbIQNaITa/1LBtRK8+/+DvK//xy+d7CszJv7e0U5GsekDKen3Eb'
    'ZCBrPDOr5e+CWvO7wVc+nvxPlpBv/S38vcH3cR9uE1BGnbSxTNR3SS1fi2sj1+bRKm4RPMz3YqfsAspW/eqY63ttoHJcecLYtjWT'
    'KPRqlYBykpi2cp73F/C193TC+KOqcYrEsUmn0ZevZZfzNeduviacTiNG5TT68DXwcolF2Tjtcr6OFfC8tJypbYdykUWfLFyH/h+V'
    'j56/'
)    # Windows icon (icon.ico)
VERSION = '2026.10.20.2133'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
UPDATE_URL = ''        # build.py: where published builds live (a folder holding version.json); '' = no updates
PORT = int(os.environ.get('SPIDER_DIAGRAM_PORT') or 47615)   # fixed, so the browser's autosave survives restarts
TOKEN = secrets.token_urlsafe(24)  # only pages served by us know it, so other sites can't use the API
IDLE_EXIT = 120
DIAGRAM_SUFFIXES = {'.spider', '.json'}
SYSTEM = platform.system()   # 'Linux', 'Darwin' (macOS) or 'Windows'
DIAGRAM_FILTERS = [('Spider diagrams', ['*.spider', '*.json']), ('All files', ['*'])]
EXPORT_FILTERS = {  # kind -> (file-dialog filters, default extension)
    'png': ([('PNG images', ['*.png'])], '.png'),
    'md': ([('Markdown', ['*.md'])], '.md'),
    'txt': ([('Text files', ['*.txt'])], '.txt'),
    'docx': ([('Word documents', ['*.docx'])], '.docx'),
}

def config_dir():
    if SYSTEM == 'Windows':
        return Path(os.environ.get('APPDATA') or Path.home() / 'AppData' / 'Roaming') / 'Spider Diagram'
    return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'spider-diagram'


def documents_dir():
    """The user's Documents folder. On Windows, ask the system: it's often redirected into OneDrive."""
    if SYSTEM == 'Windows':
        try:
            import ctypes
            from ctypes import wintypes

            class GUID(ctypes.Structure):
                _fields_ = [('a', wintypes.DWORD), ('b', wintypes.WORD), ('c', wintypes.WORD), ('d', ctypes.c_ubyte * 8)]
            documents = GUID(0xFDD39AD0, 0x238F, 0x46AF, (ctypes.c_ubyte * 8)(0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7))
            found = ctypes.c_wchar_p()
            if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(documents), 0, None, ctypes.byref(found)) == 0:
                path = Path(found.value)
                ctypes.windll.ole32.CoTaskMemFree(found)
                if path.is_dir():
                    return path
        except Exception:
            pass
    docs = Path.home() / 'Documents'
    return docs if docs.is_dir() else Path.home()


CONFIG = config_dir() / 'library.json'
SKIP_DIRS = {'node_modules', '__pycache__', 'venv', 'site-packages', 'Trash'}
MAX_DEPTH, MAX_FILES = 6, 3000

last_seen = time.time()
lock = threading.Lock()
summaries = {}   # path -> ((mtime, size), summary): files are only re-read when they change
last_dir = documents_dir()


def applescript(text):
    return '"' + str(text).replace('\\', '\\\\').replace('"', '\\"') + '"'


def pick(mode, title, start_dir, suggested='', filters=None):
    """A native file chooser. mode: 'open', 'save' or 'folder'. Returns a path string, or None if cancelled."""
    start_dir, filters = str(start_dir), filters or []
    if SYSTEM == 'Darwin':
        where = f'default location (POSIX file {applescript(start_dir)})'
        ask = {'open': f'choose file with prompt {applescript(title)} {where}',
               'save': f'choose file name with prompt {applescript(title)} default name {applescript(suggested)} {where}',
               'folder': f'choose folder with prompt {applescript(title)} {where}'}[mode]
        # 'activate' brings the dialog in front of the browser; cancelling exits non-zero.
        r = subprocess.run(['osascript', '-e', 'activate', '-e', f'POSIX path of ({ask})'], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    if SYSTEM != 'Windows' and shutil.which('zenity'):
        args = ['zenity', '--file-selection', f'--title={title}']
        if mode == 'folder':
            args += ['--directory', f'--filename={start_dir}/']
        elif mode == 'save':
            args += ['--save', f'--filename={Path(start_dir) / suggested}']
        else:
            args.append(f'--filename={start_dir}/')
        args += [f'--file-filter={label} | {" ".join(pats)}' for label, pats in filters if mode != 'folder']
        r = subprocess.run(args, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    if SYSTEM != 'Windows' and shutil.which('kdialog'):
        spec = ' '.join(f'{" ".join(pats)}|{label}' for label, pats in filters)
        args = {'open': ['kdialog', '--title', title, '--getopenfilename', start_dir, spec],
                'save': ['kdialog', '--title', title, '--getsavefilename', str(Path(start_dir) / suggested), spec],
                'folder': ['kdialog', '--title', title, '--getexistingdirectory', start_dir]}[mode]
        r = subprocess.run(args, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    try:   # Windows, or anything else: Tk's dialogs (bundled with most Python installs)
        import tkinter
        from tkinter import filedialog
    except ImportError:
        raise RuntimeError('No file dialog available here; on Linux, install zenity')
    root = tkinter.Tk()
    root.withdraw()
    root.attributes('-topmost', True)
    root.lift()
    root.focus_force()
    try:
        types = [(label, ' '.join(pats)) for label, pats in filters]
        if mode == 'open':
            chosen = filedialog.askopenfilename(parent=root, title=title, initialdir=start_dir, filetypes=types)
        elif mode == 'save':
            chosen = filedialog.asksaveasfilename(parent=root, title=title, initialdir=start_dir, initialfile=suggested, filetypes=types)
        else:
            chosen = filedialog.askdirectory(parent=root, title=title, initialdir=start_dir)
    finally:
        root.destroy()
    return chosen or None


def dialog(title, save=False, suggested=None, kind=None):
    """Choose a diagram (kind=None) or export file; returns a Path or None if cancelled."""
    global last_dir
    filters, ext = EXPORT_FILTERS[kind] if kind else (DIAGRAM_FILTERS, '.spider')
    chosen = pick('save' if save else 'open', title, last_dir, suggested or '', filters)
    if not chosen:
        return None
    p = Path(chosen)
    if save and not p.suffix:
        p = p.with_suffix(ext)
    last_dir = p.parent
    return p


def reveal(p: Path):
    """Show a file in the system file manager."""
    if SYSTEM == 'Darwin':
        args = ['open', '-R', str(p)]
    elif SYSTEM == 'Windows':
        args = ['explorer', '/select,', str(p)]
    else:
        args = ['xdg-open', str(p.parent)]
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def write_atomic(path: Path, data: bytes):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name, suffix='.tmp')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def diagram_path(raw) -> Path:
    p = Path(raw or '').expanduser()
    if not p.is_absolute() or p.suffix.lower() not in DIAGRAM_SUFFIXES:
        raise ValueError('Only .spider files can be saved or opened this way')
    return p


def info(p: Path, **extra):
    return {'path': str(p), 'name': p.name, **extra}


# ---------- library ----------

def tiny_png():
    """A 1x1 grey PNG: stands in for bubble pictures in homepage thumbnails (keeps the list light)."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(b'\x00\xc4\xc4\xc4')) + chunk(b'IEND', b''))
    return 'data:image/png;base64,' + base64.b64encode(png).decode()


PLACEHOLDER_IMG = tiny_png()
PREVIEW_KEYS = ('text', 'x', 'y', 'parent', 'kind', 'color', 'order', 'collapsed', 'bold', 'italic', 'size', 'shape', 'fill', 'imgSize', 'line')


def load_config():
    try:
        cfg = json.loads(CONFIG.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        cfg = {}
    if not isinstance(cfg.get('folders'), list):
        docs = documents_dir()
        cfg['folders'] = [str(docs)] if docs != Path.home() else []
    if not isinstance(cfg.get('recent'), list):
        cfg['recent'] = []
    return cfg


def save_config(cfg):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(CONFIG, json.dumps(cfg, indent=1).encode())


def remember(p: Path):
    """Note a diagram you've opened or saved, so the homepage lists it wherever it lives."""
    with lock:
        cfg = load_config()
        cfg['recent'] = [str(p)] + [r for r in cfg['recent'] if r != str(p)][:199]
        save_config(cfg)


def scan(folder: Path):
    """.spider files under a folder, skipping hidden and bulky directories."""
    base = len(folder.parts)
    for root, dirs, files in os.walk(folder):
        depth = len(Path(root).parts) - base
        dirs[:] = [] if depth >= MAX_DEPTH else [d for d in dirs if not d.startswith('.') and d not in SKIP_DIRS]
        for f in files:
            if f.endswith('.spider'):
                yield Path(root) / f


def strip_html(text):
    """Notes as plain text: block tags become spaces, inline ones (bold, links…) just disappear."""
    text = re.sub(r'</?(p|div|li|h\d|br|tr|td|th|blockquote|pre|hr|ul|ol|table)\b[^>]*>', ' ', text or '', flags=re.I)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', text))).strip()


def summarize(p: Path):
    """Title, counts, searchable text and a lightweight copy for the thumbnail (no pictures, no notes)."""
    st = p.stat()
    key = (st.st_mtime_ns, st.st_size)
    cached = summaries.get(str(p))
    if cached and cached[0] == key:
        return cached[1]
    data = json.loads(p.read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        return None
    # Version 3+ keeps bubbles under "bubbles" (several main ideas possible); older files under "nodes"
    # with bubble 0 as the one centre. The app itself upgrades files; here we only need to read them.
    key_name = 'bubbles' if isinstance(data.get('bubbles'), dict) else 'nodes'
    nodes = data.get(key_name)
    if not isinstance(nodes, dict) or not nodes or (key_name == 'nodes' and not isinstance(nodes.get('0'), dict)):
        return None
    texts, preview, with_notes = [], {}, 0
    for k, n in nodes.items():
        if not isinstance(n, dict):
            continue
        if isinstance(n.get('text'), str):
            texts.append(n['text'])
        notes = n.get('notes') if isinstance(n.get('notes'), str) else ''
        note_text = strip_html(notes)
        if note_text:
            texts.append(note_text)
        pn = {key: n[key] for key in PREVIEW_KEYS if key in n}
        if isinstance(n.get('img'), dict):
            pn['img'] = {'src': PLACEHOLDER_IMG, 'w': n['img'].get('w', 4), 'h': n['img'].get('h', 3)}
        if note_text or '<img' in notes or '<table' in notes:
            pn['notes'] = '<p>notes</p>'
            with_notes += 1
        preview[k] = pn
    if key_name == 'nodes':
        mains = [nodes['0']]
    else:
        def sort_key(item):
            k, n = item
            order = n.get('order')
            return (order if isinstance(order, (int, float)) else int(k) if str(k).isdigit() else 0, str(k))
        mains = [n for k, n in sorted(nodes.items(), key=sort_key)
                 if isinstance(n, dict) and n.get('parent') is None and n.get('kind') != 'free']
    names = [' '.join(m['text'].split()) if isinstance(m.get('text'), str) and m['text'].strip() else 'Untitled' for m in mains]
    if isinstance(data.get('title'), str) and data['title'].strip():   # the diagram's own name, if it has one
        title = ' '.join(data['title'].split())[:200]
    elif not names:
        title = p.stem
    elif len(names) <= 3:   # matches docTitle() in the app
        title = ', '.join(names[:-1]) + ' and ' + names[-1] if len(names) > 1 else names[0]
    else:
        title = f"{', '.join(names[:2])} and {len(names) - 2} more"
    links = data.get('links') if isinstance(data.get('links'), dict) else {}
    preview = {key_name: preview, 'links': links, 'settings': data.get('settings', {}), 'nextId': data.get('nextId', 1)}
    for k in ('format', 'version'):   # so the app knows which version to upgrade the thumbnail from
        if k in data:
            preview[k] = data[k]
    summary = {
        'path': str(p), 'name': p.name, 'folder': str(p.parent), 'mtime': st.st_mtime, 'bytes': st.st_size,
        'title': title, 'count': len(preview[key_name]), 'notes': with_notes, 'mains': max(1, len(mains)),
        'links': len(links), 'text': '\n'.join(texts)[:50000], 'preview': preview,
    }
    summaries[str(p)] = (key, summary)
    return summary


def library():
    with lock:
        cfg = load_config()
        paths = {}
        for folder in cfg['folders']:
            f = Path(folder)
            if f.is_dir():
                for p in scan(f):
                    paths[str(p)] = p
                    if len(paths) >= MAX_FILES:
                        break
        alive = [r for r in cfg['recent'] if Path(r).is_file()]
        if alive != cfg['recent']:   # forget recent files that have since been deleted or moved
            cfg['recent'] = alive
            save_config(cfg)
        for r in alive:
            paths.setdefault(r, Path(r))
    files = []
    for p in paths.values():
        try:
            s = summarize(p)
        except (OSError, ValueError):
            continue
        if s:
            files.append(s)
    files.sort(key=lambda s: s['mtime'], reverse=True)
    return {'folders': cfg['folders'], 'home': str(Path.home()), 'files': files}


def route(path, req):
    if path == '/api/ping':
        return {'ok': True}
    if path == '/api/open':
        p = dialog('Open spider diagram')
        if not p:
            return {'cancelled': True}
        text = p.read_text(encoding='utf-8')
        remember(p)
        return info(p, text=text)
    if path == '/api/open-path':
        p = diagram_path(req.get('path'))
        text = p.read_text(encoding='utf-8')
        remember(p)
        return info(p, text=text)
    if path == '/api/save':
        p = diagram_path(req.get('path'))
        write_atomic(p, req['data'].encode('utf-8'))
        remember(p)
        return info(p)
    if path == '/api/save-as':
        p = dialog('Save spider diagram as', save=True, suggested=req.get('suggested'))
        if not p:
            return {'cancelled': True}
        write_atomic(p, req['data'].encode('utf-8'))
        remember(p)
        return info(p)
    if path == '/api/library':
        return library()
    if path == '/api/library/add-folder':
        folder = pick('folder', 'Add a folder to your library', Path.home())
        if not folder:
            return {'cancelled': True}
        folder = str(Path(folder))   # drops the trailing slash macOS adds
        with lock:
            cfg = load_config()
            if folder not in cfg['folders']:
                cfg['folders'].append(folder)
                save_config(cfg)
        return library()
    if path == '/api/library/remove-folder':
        with lock:
            cfg = load_config()
            cfg['folders'] = [f for f in cfg['folders'] if f != req.get('path')]
            save_config(cfg)
        return library()
    if path == '/api/reveal':
        p = diagram_path(req.get('path'))
        if not p.is_file():
            raise ValueError('That file no longer exists')
        reveal(p)
        return {'ok': True}
    if path in ('/api/export', '/api/export-png'):
        kind = req.get('kind', 'png')
        if kind not in EXPORT_FILTERS:
            raise ValueError('Unknown export type')
        p = dialog('Export ' + ('PNG' if kind == 'png' else 'outline'), save=True, suggested=req.get('suggested'), kind=kind)
        if not p:
            return {'cancelled': True}
        write_atomic(p, base64.b64decode(req['data']))
        return info(p)
    if path == '/api/about':
        return about()
    if path == '/api/install':
        return {'message': install()}
    if path == '/api/update/check':
        return check_update()
    if path == '/api/update/apply':
        return apply_update()
    raise LookupError('unknown endpoint')


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def host_ok(self):
        # Blocks DNS-rebinding: the page must be addressed as localhost.
        return self.headers.get('Host') in (f'127.0.0.1:{PORT}', f'localhost:{PORT}')

    def send(self, code, body, ctype='application/json'):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global last_seen
        if not self.host_ok():
            return self.send(403, {'error': 'forbidden'})
        if self.path.split('?')[0] not in ('/', '/index.html'):
            return self.send(404, {'error': 'not found'})
        last_seen = time.time()
        html = app_html()
        html = html.replace('<!--spider-host-->', f'<script>window.SPIDER_HOST = {json.dumps({"token": TOKEN})};</script>', 1)
        self.send(200, html.encode(), 'text/html; charset=utf-8')

    def do_POST(self):
        global last_seen
        if not self.host_ok() or self.headers.get('X-Spider-Token') != TOKEN:
            return self.send(403, {'error': 'forbidden'})
        last_seen = time.time()
        try:
            req = json.loads(self.rfile.read(int(self.headers.get('Content-Length') or 0)) or b'{}')
            self.send(200, route(self.path, req))
        except LookupError as e:
            self.send(404, {'error': str(e)})
        except Exception as e:
            self.send(500, {'error': str(e)})


def unpack(blob, text=True):
    data = zlib.decompress(base64.b64decode(''.join(blob)))
    return data.decode('utf-8') if text else data


def app_html():
    return unpack(EMBEDDED_HTML) if EMBEDDED_HTML else (HERE / 'index.html').read_text(encoding='utf-8')


# ---------- Linux desktop integration ----------

DATA = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local' / 'share')
INSTALLED = {
    'program': Path.home() / '.local' / 'bin' / 'spider-diagram',
    'desktop': DATA / 'applications' / 'spider-diagram.desktop',
    'mime': DATA / 'mime' / 'packages' / 'spider-diagram.xml',
    'icon': DATA / 'icons' / 'hicolor' / 'scalable' / 'apps' / 'spider-diagram.svg',
    'mime-icon': DATA / 'icons' / 'hicolor' / 'scalable' / 'mimetypes' / 'application-x-spider-diagram.svg',
}
MIME_XML = """<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-spider-diagram">
    <comment>Spider diagram</comment>
    <sub-class-of type="application/json"/>
    <icon name="application-x-spider-diagram"/>
    <glob pattern="*.spider" weight="80"/>
  </mime-type>
</mime-info>
"""


def refresh_desktop_caches():
    for cmd in (['update-mime-database', str(DATA / 'mime')], ['update-desktop-database', str(DATA / 'applications')],
                ['kbuildsycoca6'], ['kbuildsycoca5']):
        if shutil.which(cmd[0]):
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def install():
    if SYSTEM == 'Windows':
        return windows_install()
    if SYSTEM != 'Linux':
        raise RuntimeError('Installing is for Linux and Windows. On a Mac, just double-click spider-diagram-mac.command.')
    me, prog = Path(__file__).resolve(), INSTALLED['program']
    for p in INSTALLED.values():
        p.parent.mkdir(parents=True, exist_ok=True)
    if me != prog:
        shutil.copyfile(me, prog)
    prog.chmod(0o755)
    icon = unpack(EMBEDDED_ICON) if EMBEDDED_ICON else (HERE / 'icon.svg').read_text(encoding='utf-8')
    INSTALLED['icon'].write_text(icon, encoding='utf-8')
    INSTALLED['mime-icon'].write_text(icon, encoding='utf-8')
    # Some launchers skip an icon folder that has no index.theme; borrow the system one.
    theme = DATA / 'icons' / 'hicolor' / 'index.theme'
    if not theme.exists() and Path('/usr/share/icons/hicolor/index.theme').exists():
        theme.symlink_to('/usr/share/icons/hicolor/index.theme')
    INSTALLED['mime'].write_text(MIME_XML, encoding='utf-8')
    INSTALLED['desktop'].write_text(f"""[Desktop Entry]
Type=Application
Name=Spider Diagram
GenericName=Mind map editor
Comment=Create spider diagrams and export them as pictures or documents
Exec="{prog}" %f
Icon=spider-diagram
Terminal=false
Categories=Office;
MimeType=application/x-spider-diagram;
Keywords=mind map;mindmap;spider;diagram;brainstorm;notes;
StartupNotify=false
""", encoding='utf-8')
    refresh_desktop_caches()
    if shutil.which('xdg-mime'):
        subprocess.run(['xdg-mime', 'default', 'spider-diagram.desktop', 'application/x-spider-diagram'])
    return (f'Installed. Spider Diagram is in your app menu, .spider files open with it, and the program\n'
            f'itself is at {prog}. Remove it again with:  spider-diagram --uninstall')


# ---------- Windows: Start menu shortcut and .spider file type (current user only, no admin needed) ----------

WIN_APP_DIR = Path(os.environ.get('LOCALAPPDATA') or Path.home() / 'AppData' / 'Local') / 'Programs' / 'Spider Diagram'
WIN_SHORTCUT = Path(os.environ.get('APPDATA') or Path.home() / 'AppData' / 'Roaming') / 'Microsoft' / 'Windows' / 'Start Menu' / 'Programs' / 'Spider Diagram.lnk'
WIN_CLASSES = r'Software\Classes'
WIN_KEYS = [r'.spider', r'SpiderDiagram.File\shell\open\command', r'SpiderDiagram.File\shell\open',
            r'SpiderDiagram.File\shell', r'SpiderDiagram.File\DefaultIcon', r'SpiderDiagram.File']   # deepest first


def windows_refresh_icons():
    try:
        import ctypes
        ctypes.windll.shell32.SHChangeNotify(0x08000000, 0, None, None)   # SHCNE_ASSOCCHANGED
    except Exception:
        pass


def windows_install():
    import winreg
    WIN_APP_DIR.mkdir(parents=True, exist_ok=True)
    prog, ico, me = WIN_APP_DIR / 'Spider Diagram.cmd', WIN_APP_DIR / 'spider-diagram.ico', Path(__file__).resolve()
    if me != prog:
        shutil.copyfile(me, prog)
    ico.write_bytes(unpack(EMBEDDED_ICO, text=False) if EMBEDDED_ICO else (HERE / 'icon.ico').read_bytes())
    # Start menu shortcut, starting minimised: the app itself lives in your browser.
    script = ('$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:SD_LINK); $s.TargetPath = $env:SD_PROG; '
              '$s.IconLocation = $env:SD_ICON; $s.WindowStyle = 7; $s.Description = "Spider Diagram"; $s.Save()')
    WIN_SHORTCUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script], check=True,
                   env={**os.environ, 'SD_LINK': str(WIN_SHORTCUT), 'SD_PROG': str(prog), 'SD_ICON': str(ico)})
    # .spider files: their own icon, and double-click opens them in Spider Diagram.
    values = {r'.spider': 'SpiderDiagram.File', r'SpiderDiagram.File': 'Spider diagram',
              r'SpiderDiagram.File\DefaultIcon': f'"{ico}"', r'SpiderDiagram.File\shell\open\command': f'"{prog}" "%1"'}
    for key, value in values.items():
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, WIN_CLASSES + '\\' + key) as k:
            winreg.SetValueEx(k, '', 0, winreg.REG_SZ, value)
    windows_refresh_icons()
    return ('Installed. Spider Diagram is in your Start menu and .spider files open with it.\n'
            f'The program itself is in {WIN_APP_DIR}. Remove it again with:  "{prog}" --uninstall')


def windows_uninstall():
    import winreg
    for key in WIN_KEYS:
        try:
            winreg.DeleteKey(winreg.HKEY_CURRENT_USER, WIN_CLASSES + '\\' + key)
        except OSError:
            pass
    WIN_SHORTCUT.unlink(missing_ok=True)
    (WIN_APP_DIR / 'spider-diagram.ico').unlink(missing_ok=True)
    windows_refresh_icons()
    # The program file may be the one running right now, so it's left for Windows to tidy away.
    print(f'Removed Spider Diagram from your Start menu and file types. You can delete {WIN_APP_DIR} too.\n'
          'Your diagrams and library settings are untouched.')


def uninstall():
    if SYSTEM == 'Windows':
        return windows_uninstall()
    for p in INSTALLED.values():
        p.unlink(missing_ok=True)
    refresh_desktop_caches()
    print('Removed Spider Diagram from your app menu. Your diagrams and library settings are untouched.')


# ---------- installing from the app, and updates ----------

def installed_program():
    return WIN_APP_DIR / 'Spider Diagram.cmd' if SYSTEM == 'Windows' else INSTALLED['program']


def about():
    packed = EMBEDDED_HTML is not None   # a built single-file copy (not the source folder)
    return {'version': VERSION, 'system': SYSTEM, 'updates': bool(UPDATE_URL) and packed,
            'canInstall': packed and SYSTEM in ('Linux', 'Windows'),
            'installed': Path(__file__).resolve() == installed_program()}


def fetch(url, limit=20_000_000):
    with urlopen(Request(url, headers={'User-Agent': 'Spider Diagram/' + VERSION, 'Cache-Control': 'no-cache'}), timeout=20) as r:
        return r.read(limit)


def latest():
    return json.loads(fetch(UPDATE_URL + 'version.json?t=' + str(int(time.time())), 100_000))


def check_update():
    if not about()['updates']:
        return {'available': False}
    info = latest()
    return {'available': str(info.get('version', '')) > VERSION, 'version': info.get('version'), 'current': VERSION}


RESTART = False


def apply_update():
    """Download the newest build for this computer, check it, and put it in place of this program."""
    global RESTART
    if not about()['updates']:
        raise RuntimeError('Updates are not set up for this copy')
    info = latest()
    name = 'spider-diagram-windows.cmd' if SYSTEM == 'Windows' else 'spider-diagram-linux'   # Mac uses the Linux file
    data = fetch(UPDATE_URL + name + '?v=' + str(info['version']))
    if hashlib.sha256(data).hexdigest() != info['sha256'][name]:
        raise RuntimeError('The download was damaged; nothing was changed. Try again later')
    if b'Spider Diagram launcher.' not in data[:4000]:
        raise RuntimeError("That download doesn't look like Spider Diagram; nothing was changed")
    me = Path(__file__).resolve()
    mode = me.stat().st_mode
    write_atomic(me, data)
    if SYSTEM != 'Windows':
        me.chmod(mode | 0o755)
    RESTART = True
    threading.Thread(target=lambda: (time.sleep(0.5), SERVER.shutdown()), daemon=True).start()
    return {'version': info['version']}


def restart():
    """Start the freshly updated program in place of this one (no new browser tab: the page reloads itself)."""
    me = str(Path(__file__).resolve())
    if SYSTEM == 'Windows':
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 7   # minimised, like the Start menu shortcut
        subprocess.Popen([sys.executable, '-x', me, '--no-browser'], creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=si)
    else:
        os.execv(sys.executable, [sys.executable, me, '--no-browser'])


SERVER = None


def main():
    global SERVER
    args = sys.argv[1:]
    browser = '--no-browser' not in args
    args = [a for a in args if a != '--no-browser']
    if args and args[0] in ('-h', '--help'):
        return print(__doc__)
    if args and args[0] == '--install':
        try:
            return print(install())
        except RuntimeError as e:
            sys.exit(str(e))
    if args and args[0] == '--uninstall':
        return uninstall()
    url = f'http://127.0.0.1:{PORT}/'
    if args:
        url += '#open=' + quote(str(Path(args[0]).expanduser().resolve()))
    for attempt in range(1 if browser else 40):   # after an update, the old copy may still be letting go of the port
        try:
            server = SERVER = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
            break
        except OSError:
            time.sleep(0.25)
    else:
        # Already running (e.g. another window): just open another tab on it.
        if browser:
            webbrowser.open(url)
        return

    def watchdog():
        while True:
            time.sleep(15)
            if time.time() - last_seen > IDLE_EXIT:
                server.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    print(f'Spider Diagram is running at {url}\nYou can minimise this window. Everything stops by itself about '
          f'{IDLE_EXIT // 60} minutes after you close the browser tab.')
    if browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    if RESTART:
        restart()


if __name__ == '__main__':
    main()
