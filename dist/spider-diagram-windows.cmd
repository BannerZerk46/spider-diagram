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
from urllib.parse import parse_qs, quote, urlsplit
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
# build.py fills these in for the single-file versions; when None, index.html and icon.svg next to this file are used.
EMBEDDED_HTML = (
    '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'
    'O5rX8gb0cL9iZsv6vDd8sZxZn5YHW9sZGS9LJnuYroCvd4u/LYcs1jaDFgyoIK332VGv7C57k/WYa69LucEidVg9Mlyq97jResBf'
    'lkJbf0oOH2obJtTO5gbL1GFeG1XsVK88sbaS+QKSEQh39yFw2g+btfAys2v1jbd+VRRz0VOmjbr84Cnmy3qtrtfag2Hbyspadp8e'
    'avqh2x7OmDXw8dRsXVkZixXP01vXdQE01Z1r677acCzG0YpPgyfjgIiXofnK3E6Zh23Nq/Fd8aU3fjgYalc5zhve6PVhc1wcsvZo'
    '2Klp1eOaUSsvD6vlxLRpenisHuXNMd/eCY7c1wYvBbpOF1mR2w+XQ51+4UTA9SpXWWvcaFbl1UFq3a6O3V1JelpnB1VjMBvJ+Zet'
    'lmqDtioX2Sy6eqN2+7nicNtFFqbl2duiq4JieuxrIVUdTNeL42uzNZrx7X3liTU9VbI5piQfX0f9l5poCMuOUFtvl0x9XKgMKp3+'
    'sNPn61pNMkXVEd3VShsJtY6SEtjVcF8oZfNF1dUYNWvb0hO3stT2sL+cPu16hydm2qg61vppaA/Wa+5gbfXa7Gm4cRTVG6hPU2Vh'
    'Ovq8Pu9PamPQ9J6VU8W+0zrY20nKahsvbbH+aiz1sdHTcvLztO5O2f7+YQPK1aozkcypZHYkUOGnk5STNV56Yr2Mai/dVE4eZuuu'
    'yfZrjUevfXhdGJXsUuBAP+52V6c4VLA0ha3XnGH+QLPC4FVYqxum8choqcVo1ykLxnC6FcqSXWAesvZLZVvfDsSKNOTKq6NXRwy4'
    'XlWOr85e35bk9eql6G76vdFKemUfHe5x298cdKGR6z2o7rBU3a2mufm+qKBtvw0M6UnZNvSUUduYxfpwO90ftkvV6OUa7HohC72x'
    'fEjNW+a4sttLNTP1OnliG/MF3wN8aD499gpOimUtmdZK0pGTV+P21gDM6o3Y/aQ5LY6yq2rJ0/nXVPmYRdXzYe39xcpVu8dnd17r'
    'cQFo1AGBW1nONV0ze5NnrVTPjYWZyewXu+nqdVrTj3v2wDuHRp2mpUqvyCrmagHMK3WQF8tBRRKq1nNjti17g7nAexojmvREt5ZS'
    'u1LpOb31oKg9jh56naahTxY853WOw9puUOHrKmO9bPryi/3UfTnW28p2vX2deOuVcXTrek973bojNl/QjJdw9RTbzKfU1cvTY7Wf'
    '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'
    'dmzL6s2eTbMqSJVjeqi/qs9e76n3lKsf7p6m5utDH6RtsfyU3xzaw/zgsOg1NkJ2CbLm5P65UOuYot6TtbZmb8SSKOTm/VbuNDYz'
    '2+NUOmbczuNLLe8cZtuVOLK8/Sw3PmaGj2ahsbEsszqpTFVHEo5Obq4JmZHVnQykVUHK6MvTcnX35Iy7jUltdHJlYKKBn5OdspCZ'
    'nbTH1wkcnKZp1ezdYDbDKRhWy7StrZd+3St1WKbRRMnnddfeGCV5PBXN3Ki6eBz3O73sUahOetu9cOyMhoMRkFzPmp86ufqu9vi6'
    'n89n0l1OLc2kiV2X28PMY2s+K2RRx7jOmS+FkzZVm4cn0R4NKlO9epSfHe107B5Gc+nZOfTGk8Fjue1u3P6k2S5r48LafBq3Z08r'
    'cb19dvuWunBMGCSc2Lb5eF/dtw/HsSvsvezM1d2KZcyrE2FzMoeqWco9FcfqwnyqjAoHezgaZXrVUbu7aKy2pZE2V/Wa8iKNexl7'
    '/iga8+74ZErNVUbNVHZmzmwUqrN6zrLWT9mJ+Gx6oioW58vCc9euPbzsB6Vtd6ls9rvj1G4/D7PZ03FizktOx5Nr2c5I6D0UnNO2'
    '9HIaCsphmJWzu94+V7PdY+3guW1MhnloA3/byo6PB897eJaqajE5h8GV77S85+xNY9qw7ne1O8d5ec3v3Op+BzRYtHtia9HYjAaT'
    'nGgBTzh79kqnSW8klAq7XqnQcQ7e1LsvlZadiuOOKuvlKJNpzYqKom8Kx5rSloGC1oHfEnpKs7EzX09uq3O/FECYPk06O6eSMUv6'
    'vGmNNauo9J4b5jTXFE6jnqwsky+1wf08d7+VOw1nlJfXdq1jFPvmFJjNx6nhynVDr7btiWSJrUKlswTmY9uen3L2bA4jnxjr3mmc'
    'PPUenju9iVLLbMXqYGZuS9LoaExKD82t9dyqWd1eruJldb1l1O+Lq+PMzlVPnWHJGu9zWq+YNOXcfJ2v98dZd2hVm83169ptuQs4'
    'nY2eKd3lTbtaOI61+aNdKiqz9mJmmdtiq+lZktUa58Rau6M1DEEujTLPg/s84FW5bVakTEFplZ2auGt2KnqyanWXu+6zWa1q2nQ6'
    'FKyZdTQnh13PUg6A9WZHda+tvHVmXMsMj5Z+P6uV8zuQZ4WX7EPeENvTYfdYfBmVnJ169KziWhYWB6F+6GyeXl4e22qt2XneDQ9W'
    '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'
    'jp3i4kmVRctTGyDOGKP+6f7UP7RVy1U28qQ9n4trd2r19c3IK3QedtJW9SZZuf9kSlayMNhPJafirJWCI0+Gu43W6zxu1r320+S0'
    'Q46zUepuKmalu1U2gzGI2tlp51Uopi2pdHqqr1puxXu9e7Qet9zcpCLX1DIsqdou7R+3mrp4cCc1QZi0JFtSzZP2PDw2C2092TsW'
    'rcNiJhimsWyPxNXAPmSbG8nIZsRKf90Szd1j6zSVd9X7RanVzynZfrnUF1ptVwXGzsw06f9FY7d5Wb5qx8Fc63andk7Uvd5U7Bvq'
    'dl3MjHv1hqUMKmPdHG4zSXFScTPjvN4fl9Ji19DWkvzs5gXAEHeVu7unV235drX391nDrs+ARZ489MZD4eUkKminL1Weel2QF9Tn'
    'vND1GovCwF20q7NSdz5uWr3RS3ljVzraNCOqGEelt3gVLWGwLc43gI7zxe6rNoJB9OrjjnRwXvO6NRvLWn/Y9ka5oqetZMc0M3NY'
    'Ammn5eR+Q5zeDZ+ADJSPs3LaEixNHAtDZXx3pzwOKWpHdVQVenL1NX9372Xvy0enN50DOeoLQ3fvHlu5SquTnsjpRkEezSsTtdUa'
    'd4pDuei223Jr0Tq57aGTzedEsSUE67p+NbeDwnE2X7W705Y5N+sWYGoL0IFhpZ2S2LL0jTCzC0KrdrCPWXdVWWWUVU4Y6Mp0WzYB'
    'WT5Ld/fz+vhPgfppVDbXj04lvwfOsThSd1t3aJ26ol6uHsXuZHAQAcYb5ghYswocmc60YgE32663UbXRMfuP0l5a5YuWpdnlxkhq'
    't1zb7RjietTIVpR9pT0apO9qlq4DTHfMTHdUHD3op+osPy6kXwv62G1aI7Nc6Y0nuwnwn3ebzuB58dK23VpWrBbluXhsDbJeZyfO'
    'TtVkI5+eNBYHfaBs5gPBUZoduXiPfvX7WX3/fF8adKa7Q71eLDwmX2RTf5nk1+uKtErXuv22Wcx2q7XOcjKxClKtV354VTKnbavc'
    'OyS91/S6Hu1gnVmLirs+vEZaf5xtdttGodgeHw8vvcWiNX4tPhfrteT0/lgd63bDKlUrs/vOQTUKzdp2NBILilkSet2O+rwrngZj'
    'QTkZh6w+HJQ7Tm4oN72i42qvYlkxTrvn1b7UFZ3aqJ23DGGteRl7cnBH7WpBAyER4AuIY2VYzGQm5rPYcea1Xs9dr6cCyI9AX8Qt'
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
VERSION = '2026.11.02.1453'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
UPDATE_URL = 'https://raw.githubusercontent.com/BannerZerk46/spider-diagram/main/dist/'        # build.py: where published builds live (a folder holding version.json); '' = no updates
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
    'zip': ([('Zip archives', ['*.zip'])], '.zip'),
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
live, closed_at = 0, None   # tabs connected right now, and when the last one went
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
        if self.path.startswith('/api/alive?'):
            return self.alive()
        if self.path.split('?')[0] not in ('/', '/index.html'):
            return self.send(404, {'error': 'not found'})
        last_seen = time.time()
        html = app_html()
        html = html.replace('<!--spider-host-->', f'<script>window.SPIDER_HOST = {json.dumps({"token": TOKEN})};</script>', 1)
        self.send(200, html.encode(), 'text/html; charset=utf-8')

    def alive(self):
        """Each open tab keeps this connection open. Closing the tab (or the browser) drops it, which is
        how the launcher knows when nothing is using it any more, whatever the browser."""
        global live, closed_at
        if parse_qs(urlsplit(self.path).query).get('token') != [TOKEN]:
            return self.send(403, {'error': 'forbidden'})
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        with lock:
            live += 1
        try:
            while True:
                self.wfile.write(b': still here\n\n')
                self.wfile.flush()
                time.sleep(1)
        except OSError:
            pass
        finally:
            with lock:
                live -= 1
                if not live:
                    closed_at = time.time()

    def do_POST(self):
        global last_seen
        if not self.host_ok():
            return self.send(403, {'error': 'forbidden'})
        if self.headers.get('X-Spider-Token') != TOKEN:
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


def shown_version():
    """The version to show. The source folder counts as a release when it's exactly the last published
    version (checked out at the release commit, with nothing changed since); otherwise it's 'dev'."""
    if EMBEDDED_HTML is not None or VERSION != 'dev':
        return VERSION
    try:
        git = lambda *a: subprocess.run(['git', '-C', str(HERE), *a], capture_output=True, text=True, timeout=5).stdout.strip()
        released = json.loads((HERE / 'dist' / 'version.json').read_text())['version']
        if git('rev-parse', 'HEAD') == git('log', '-1', '--format=%H', '--', 'dist/version.json') and not git('status', '--porcelain'):
            return released
    except Exception:
        pass
    return 'dev'


def about():
    packed = EMBEDDED_HTML is not None   # a built single-file copy (not the source folder)
    return {'version': shown_version(), 'system': SYSTEM, 'updates': bool(UPDATE_URL) and packed,
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
        # Stops a few seconds after the last tab closes (a reload is back well within that). A tab from
        # an older version, without the connection, just checks in now and then: then it's IDLE_EXIT.
        global last_seen
        before = time.time()
        while True:
            time.sleep(1)
            now = time.time()
            if now - before > 20:   # the computer was asleep: give the tabs a chance to reconnect
                last_seen = now
            before = now
            if live:
                continue
            if (closed_at is not None and now - closed_at > 3 and last_seen < closed_at) or now - last_seen > IDLE_EXIT:
                server.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    print(f'Spider Diagram is running at {url}\nYou can minimise this window. It stops by itself a few seconds '
          'after you close the browser tab.')
    if browser:
        def open_tab():
            # A tab left open from last time reconnects by itself within a second or two: then use that
            # one rather than opening another. (Opening a file always gets a tab to open it in.)
            if not args:
                for _ in range(30):
                    time.sleep(0.1)
                    if live:
                        return
            webbrowser.open(url)
        threading.Thread(target=open_tab, daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    if RESTART:
        restart()


if __name__ == '__main__':
    main()
