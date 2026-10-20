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
    'q9Lp0kZ+2B0JUmcytfVT5/TibnatYYu0h8NONlfieTCps+KG3snzrK0CH5Jto7fxrcl+sDVHA8e3vAHXsEcF+rXOjRw9N06VK54/'
    '1D1pbB2UEkf2HF6xOpMZ2PlZt9W317O1PNO79q53murAIrqLycDrdwW/ys9T+cGJ9LlVyugs+7lizxlunWWdbfW34uvra3vMeL0D'
    'OTKM+dbwWrYnnTxvP/MG5b1V99ptt3QaZ3Pl+qusF5x+tlp2Dt2S0bUHQLOD0Zrf5+T1KCeXt4ftbtVvaNsJLZyOw9ZBn3r7UWpL'
    'Kk2uxb9wtG2uR7Jpyw7VMDVeLs/E3hz4na5Kp1nndbQ97XneG77oht5tW+P2eDpOUcVpQa+PR+sjVyufXgfNsZ7nfNu2t41B/1Cb'
    '2WMly66Y19GMWSlSdbDjui7fejl45m4LlruSn+7UMkMqvaxe9JcusysIfNtaHFek/EoDM79SG4a6YDZawt5Pre2xaB4qdZdxD83B'
    'KNVmGKbUmSqtan1zGimrgdCqmhoMw51oYrXB9/tjlwNGq219123Vd7JiqANeJGlz1xnSunulMhgczw5P6qm03824xmLivkragNzY'
    'p/aULvd3lGq/aI4tac4etJvmLj7AV3M055VWdzYetIbQD6cO62KJtDod0F/F/aCZGIJClrcSO150qUZqMPPXvXp21l00y8U2Xzip'
    'YmNn8nq23h7NzU6LcjbD+eiFa1szpcerx6ZS2bS8sgg6yN45mu6MTimlHZWfzai+zZUV8+SqwxI/6J5USWoMG1Wuzzns4FS1GM8V'
    'Rb0zn4xeUurSHnRdp8SPWyTTmTk+1T/I5tau+Ep9oJKg3W5TuRxlmDmxbrsmP2wBJ10u+85m091R25Izn00m1mAs++7AlgaN4ULq'
    'ySV5p44k0Ee2VLl6kLu+NaJkJzXO7/Zd97VVcOZko1uxrd6gNR40KJ8e1STZEYp5ypfBUOkOrIbS28tiWXUM26DKrTE3lMfdbGo7'
    'FkpMtnpoVHSzJQ2y3fVBHougSZQ5o7NZrDV2zvr+0al4Ym9WVIq71rpT9g4L95Vyj4vjgOy97Nz+4EAdvPaL9TJtWHO5vpszc4ez'
    'aP//Z+/NlhPJtkTB9/wKT52sFCQS4MxIGRGmCYRAgJhRnLiVjrsDDo7PjHHCrN66H/qprc2626z7ua2/4/7J+ZJea+3tA0gRmXWr'
    '6q2z6oQc9z3vtde81xLTBVHMFh5rsDHK3C679sDr6Vpjn13YhWWi2FaVe6uq79MJACZrtxcX1am0LoEw33psmSF1a2dusvvuuOVN'
    'rMFgpCy83lR8Wvcy0kMtp3iV0bThVF76i0HGACBKrArNTTc/fSqqt+OuZgEdX8ytWrX43H+ejDNPYk2TatOX1ovn9PN7R26XWs9q'
    '42Dkpv38o94bzd0Xa2ofjOz0UL4Xb27LtVYzHMq8NByP3VV9Inm3qv2kd6pwJoCRrm6G4n6Sft7ei3ey2exqpedDtaeVdmr15TAs'
    'GZldt1cvLDfebrYYDAbV7vNrzVYbI1l9lMvDw1YHBmiVUnvSneoNN5XEJq92mkNr1E2NStrDOl/wjHljkHCaiZJyECftuyEIBZNy'
    'vmk+WmopNS1V8vdpQ5kiz/qiZ9sDt/QkbcTXTXaxVp3XXFeEOU2B/7spN7JGMTXb1NRl0Smn9rVu0bAz6oM3KrjZ4qGVk/bt7RxE'
    'K70zagxGUkcrmHtTXow3FRvYTidfAdHRfnq5zRu2nm2O5WxpcWj0GyAr593cWHSqzfHObkpis+p1mg+dllkq2Lplr9urgm3MjddE'
    'sbZ7fCpU2v2H+8Zo+FJa2aNRY3FTPmR0W27270et3Ho2duup0s1tv9lbr18yD3W9MtRsR39ZFx4m9eVi+pJvTqXu+m7Q2zgrI1Gd'
    '5JZaJT+yUvPVfqOL+bayHTu6p9bs4Wtb9ezaY8cpDO1iYTGYzJfl1f0EFr6XKes911lPu4OG0i9pdbtRvBPNJ7E9atjtnNvejfTZ'
    '6kVU84tMbrouaWaq0Dv0tpusu0w81Z8WSmJ5eH3sJCZSZ2hYw5J5/1hZeo71ZE2mo259tQP2+VlreJKslgabe22Yrg9LXrXg2nJ6'
    '3Gjf93Yvu2FGe/Xqol1z8k+tlJxX2nll3kz1N8PJyB60cr1FXXPLqfJIfB6Uu/O+5bWWbjl/3yytvd1Gz9oTT7H3Q9ex7c7rk2VV'
    'RLm8T/WNF+1p3XnoPGQfdzcPY+vlrgvStlR6yC13zX6ut5t2aksxMwNZc3T7lK+2LMnoKHpTd5ZSURKzk24jexha6dV+LO/TXuv+'
    'uZpzd6+ruTSw19vX7HCf7t9b+drStq3KqDzWXFncu9mJLqYHdnvUk+d5OW3MDrP5zYM7bNdG1cHBU4CJBn5OcUti+vWg37+M4ODU'
    'LbvqbHqvrzgF025Yjr1ap1626iMs02Ck5nKG5yzNojIcS1Z2UJneD7utTmYvVkad1Vbctwb93gBI7tqeHFrZx031/mU7mbzKN1mt'
    '+CqPnEel2U/fNyav+QzqGBdZ6zl/0MdaffcgOYNeeWxU9sqTqx/27d1gIj+5u85w1LsvNb2l1x3VmyV9mF9YD8Pm68NcWqyevK6t'
    'TV0LBgkntmnd31a2zd1+6InbdebVM7yybU4qI3F5sPqaVcw+FIba1HooD/I7pz8YpDuVQbM9rc1XxYE+0Yyq+iwPO2lnci+Zk/bw'
    'YMn1eVpLlzdW1qrlK6+PWdtePGRG0pO1ljSpMJnln9pO9e552yuu2jN1ud3sx07zqZ/JHPYja1J0W2ulmmkNxM5d3j2sis+Hvqju'
    '+hkls+lss1XH21d3a6+JySF3TeBvG5nhfrde3z3JFa2QmMDgSjd6bu1uLXNcs2831RvXfX7JbbzKdgM0WHI6UmNaWw56o6xkA0/4'
    '+rQuHkadgVjMbzrFfMvdrcfr22Jx1iq73qC8mA3S6cZrQVWNZX5fVZsKUNBH4LfEjlqvbayXg9do3c5EEKYPo9bGLaetojGp20Pd'
    'Lqidp5o1ztbFw6CjqLPEc7V3O8nerpRWzR3klIVTbZmFrjUGZvN+bHrKo2lUms5ItqVGvtyaAfOxak4OWed1AiMfmYvOYZg4dO6e'
    'Wp2RWk2vpErv1VoV5cHeHBXv6iv7qVG1251seZ0xjIb5eFuY71+dbOXQ6hft4TardwoJS8lOFrnH7jDj9e1Kvb54WXgNbwqns9ax'
    '5Juc5VTy+6E+uXeKBfW1OX21rVWhUV/bst0YZqVqs6XXTFEpDtJPvdsc4FWlaZXldF5tlNyqtKm3ykaiYrdnm/aTVano+njcF+1X'
    'e2+NdpuOre4A673uta0+Xy/Sw2q6v7eN29dqKbcBeVZ8ztzlTKk57rf3hedB0d1o+7VdWCjidCc+7lrLh+fn+6ZWrbeeNv2dXTPc'
    '1iHjqbthG8B63ev0B83+4H5ZWS6Xbm3+OlF7vYmoH8Z24vXVnhjSbQE41vmgMrZT2ztRfVz2OvdVBcAz0cynVv1EadmvNAb5lvQ6'
    'gK02nUbRdfLNit4TVwlrlxmLj4tsO79UolWOq1c3xUZhUNDlUd7YpPPThJu4K2mttTjopKql1KE+VVuR5279tqyX6+XuulHaFWRY'
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
VERSION = '2026.10.20.2116'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
