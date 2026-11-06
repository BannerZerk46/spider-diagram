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
    'zV31XoSZeW7LpfOZ2zvSK+I1NF0q24PK6rLzeFt2ncFKcbVT4OhHthVUujVnthiUJ4pvli8/hFUwe2jWoTsX/tr1+0HWH9VZVgE/'
    'hIp4K6yErsx3b4wjeXr6OptOe/WHkVyaVczB26y/4t+6p7rhX8xK949GmZ9faL1Bz7x1h9LypjSv+Y9lp/ry+DDq9y+Ej7vl0UVt'
    '3hLay5r+CrppVwsq/eey6jpB51bqdmbKbaVdUc9Wt6DjfwxOZfOjueqbzvDZuK11h/cP5fbs6FqRWkp/eC1Lb2C7vAhVdThx+ODa'
    'v3yX9HNJfqvK1YU2Qfx/b6yq7QfP0Ze3tXPlfen0gipfu/Tv3l/OhrzAC615ZyWfXoMkPw1QHrxQHNGAzTDM6FHJQPCFSobPlrh8'
    '0DpaR3x4lJZ3ly8181qEhXX7Pdm9LD3dP06UmvFa+5AGH3cfl52zmXjf/+jdD7Tl+Vm5Wyk1u5eO39F89eiD11XrpvZU6/f6M+G1'
    '1Oy4ql0x54JTexteP7bKrnjUWsLSBpXBLOjdKDNFMfUZWGXdrtnulY9AUPv8a+lCn9ul67uV1viYd+dXg5HZtS5L2p2mL2fnR/PO'
    'RBhez9WBMlfdWX1gTt7upeuZVPHbk1G97u3wY/rj8kt7LE3mr/5R8DFoC7Pz18rZWA/OWzf93o14P2/V7tW2D4ixKl3Jk4s34+2o'
    'ZTxXus+Vh/dVo/I4eguuLbEzf9Vb/XlHN9VupVPlK3zNmdzpN7LYmrz6wm1wrwcvKl9TDafTky7b1bawtGSlI1YVoWXy18pq2HX7'
    'tfMHZ3nv3HaHp6WLymPv4x10xPNro83fj5ZOcKe4cu9etWpO6c01jpxhu0dYVPnJv9duup0bUFdt5cZSjemRV76flc58ofU46F4u'
    'Fq/oYqkSmTu1BVCpvAtmZpJXT/jm/aL8aD48yCsTWNuNL5q9wOn5s554LVqX1Q8B7Dy/6xqedtOsdI6mga0cqZ3SfelqMXA71f75'
    'e+3ZfRdaH1fWSBuvHrRxVXs9mn4MDOOjpVxWhHGzIjzUlXclWA0q/cvFvde/6HkvTskVnGpzfGZBr6s76Wq2upvVelogaLXuc6l0'
    'N2m2J/6ToNQmy/vzuawOX4Zl8fxuVa+r1PV2pCrKrfYgaNr9jX4zWzRq9cVt6W6gvbUVsdvqzMetWr921phrz7J/W3oSb/3lcH7/'
    'bC2vpbfG/Gng6sp0NZt7ni60jq67s6PWWAr65ZtyadZ12gswf0+11ZPmtQPJ7bqV50qrdXTjNB/Ogje9OzjiV32hZ73MJqdDbVSZ'
    'zWES7Up1xc/NTklp3hzp8soK5kJX756WmvKiWZnUlVVZuB45pTN1Lgx52xjOnkEP9Y5co3deVSZP5REp9eDOtGF3MWl/BMNqcxY4'
    '3rswUHlrOpupzWbFq0tG7bls2d5Ls2aU7o66yuRDKK087VHpHr05T/divW/q9tFTyfSGle7Ra2l+bZVWryB3fRCF07r02ggmUIkv'
    'raraECvVroXbKSzbu1u+mn/cXzSCBfCeWvvt0n0VnOF19+mIVyy39nD5PDcHJflBw0Z44bJT84dy9dl/vPFLo66jmGCbG57EVyet'
    'oTGwT+9Xde29JTSWfm/YGzhV5XHS86vLpT/UgACOrs/btfZ4gaVK/Y+7Z1mcdt9mw4X7NH+eda9qN/ZMv7m0ro94ARhv7f6Zd08n'
    'eqWh3L09nFvl4LzrG2+aspTB/DduK2cfU2F1ofVL9au7oDq5fZnZb13XCp7tSkW4V4e63ZZPpzeza+1u9qT7r8Pe5f1Ls3U7rzxO'
    'bOutZLyIvarycu+/D8Xxi9i6s95vJj3e7QfzitmWrfd7d9a/ald6F373uiZ0naO36YvuDMCs610G/HDcvZlP+qfSLNDUcvfjcbg8'
    'ch5q15WuqlTkl5ml1Nxb35Vv+60h35m3BYc/mmlBS3OqlfuWLLyV5+/9+ZH9PB6e+udPH7cPrdf58FVytY/q/fPNW6ffejMfH66q'
    '81V7/qx7XU2t1i1NnwOSOe3zebXek5p8YLrnq4rhKF0HcHio6/26MxONj+vyzWO9z1v98rBm35e73bv2u6vd6OO+rwp6+aLU4XtX'
    'Wqdans4Csd97c3pC/1FotkVHPKry9t1NbTbt6XJXuq4+XPJXA6vShT/AHZ5dWBswXObqzJLrr8wp33DvLOvhwSuVV1K3eqs+Vo5k'
    'IWgL913ReX9dXcvd3s18ZH08aA2wgur9y6uyO+l/zCe3/fbCd9zKUXXRN1flQU8t97ov8/eOay1Onat6vTn61K7Vyr28evPfQWkO'
    'eEfuP1jlmzfhfXY7uXlYzZWbytGNadY+LqzGqfGk3b8qU3+26lVfZlP1xqoBvy7dV/t6vyYfvfcWbqtTKw0GndOpetVQrvvBS8V8'
    'EMBI9B8vzN6jV1Vs1/WFfqcrdFzZdi+09+rH6t4KVuqMr96AFt/zb97shig/vC0DZ8a3mqs7depWhPO2Xm6/ydLDQNMr54Gr9hbB'
    'lTSvGFP1bXTx0ahCT0G57fddx20vne7i6ezDq1/86L7emeJLNxXtBcYwGw8vzJdGdTS6LIlPv/1GN0S5gwXugis8+zbGvVEZo23o'
    '/i3ZIn2mm7oHzwcbzi3QyOYwFjA6hBiGMrE93mzg3DHeb4lZKzDi6lsqcK8blT0kxxKgYJys2+LI7izNtB2GFZPbGifcMznzAM97'
    'hVvVHcXB1fR0IXabF3InZKKehEzYE80FMLbpVR3kwjfO84PhMLltLcmVYrkiSFVMeV4rS8noh1qlXMRY95rMS7wEBXbtWn8irn0s'
    'njQTR/3CsDN638Y4jilOHCSl48ETn32Sy4AMKJHLgOXqD9ekHzeCcW30o3GSiv01ohfBSZSeJwwwO0mE5HknXjLrDivinWw/eRol'
    'x/GiAP1kAXjI7rMggMdn+VJRbpufJU8RphLdeDkRd+ckgE93vM0n7PY5a0CoJv+4waW9+MHDBiTNSk58bJh+hcRDJnOs7Bd+mybl'
    'ZMPsTUTbqXQ0+zWO+StyWsbHYWAjtEeT/nwloBdYGee5g9/++X/EePyPGI//EePxbxHj0WzW9fpajMcloSnobpGN8RhcNZ5eSQzF'
    '6bDUrDd5nOUz+A7j9+5On54aDUoHYZzFZbN1Nb57GrWfus3O+XJkdKck5qJjt7XT7nlXmCgvS692+cwvO+935nX7dao+yx/3K3v2'
    '/P4kPZz6j2cYT9IntDy6ozSf+NOodxr1xetpowTwnNktgBu+N89OAVZSvh7D03zqPD+9NS9g7sd33fMl3+q2X2H2vUHz5er96uPJ'
    'vB1Xz3rLgX1jPJVKQFcLmP/6afPprlU/q9aDi/rZQh/V//3+DM+G/Xm/f9m/7pvabHUzca4mFaWlHC2bbX1We76ezSzpvO1Vqr2P'
    'V2f5/nh2fjMTV9Jcazx7ynn3/sM66q4cpfn03usuZs27yqrCX7ZAzxkMJKvZFfxSSxcmZu/drL/op28vL7OFYKrLc14sl6eLq6Bk'
    'GFfvJl8NrMndUHoq1a6Gz72jq9Ho/KFyFNRKi1btZrxq8dObhaIPj/i5zbfncTmNfyw9X/JgpV5dNd4dYViTFgD9Sp/oTqn2XF1p'
    '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'
    '/RtWRAVTfX5FLMBtHbai+c19Y8VsxPVuwlUUeX9uPeG10fkh3gdJ8d7Eafe3wUSSi/fpXBwwD8SZAjn9oBhLx/vEoMinfYzsoCkq'
    'Xf0or9imxeKh+EM81gg7M2tZDZu8gfqFIHJOfP9KH2+aauDXrIvv/hwnKw+sNoeeQXcrGhKzhrz3w8D8Gk7/96xFeYvFYTlHUxi4'
    'AHpZDiyB4Lazwg9JnkS9WQ4/fBYAG8Rr0Zgjx2c5SJoYXIjE0UWeO6JImhoe3gST9gtIxFz8pnVwazZiVw6JNq2heLWMv+N4pfHY'
    'ELy53W5zf0HEfxM8fiviyPgDwqsIopEgfbd1DPdCaPQgMvUC3INK4nE3BhliyoA31EYE93W4MdpQfsvyIO0z7rVtl4g3qN2qqNxS'
    'brxlhk+VrnhhqbchBHXVmNqn/hiHJpSaGynkJacYqBnhWjAsic/vuXEEIQLDEYi45kr3yfNcqAn1PeTwcbkzVHCjGVZGY0wO5s2q'
    'NKON8pTW66e04ZhnT0LN8G4j9vrzPKnMsfHRSwkCjWp12N6gj9imCs2XAOXIAgqHSa8f9hEPe93bCYe/6MCo1dozE5UrV5duum7e'
    'E2MGbltCzOVydERYJKhHopjT1f+FrypLNEhiFkeRyXlGN/mQ0AEVNU3bMpuGY0p04ERU6CeNWiY5vDUnA4cSkDwIXqgbDHxvbNqO'
    'T4ohr7mM29pn2WHR5fK73/2uQaBZ5vo52LDwni8/vv8EppLYcBGiItzPLptOxodPYTlJLGyejIg8/0Udx9Fvk/hZ/njYkuCcq3hL'
    'NB9eOszx/N3HF3+inlZ/ij9dv9m4fvPw+su764/vrt+9veZv/+uXj3uvrj99fnW99+z5O/r3zatnL6/3nn98+dfrvdcfP+5d732m'
    'l9d7L6/ffG7eX3VNp3nvveTJhTMyLwFoStozR5HG+1+/Hj74ef/rwdPt64MmE6Zfv95f9/15zqcJBBQxcpt76IxzMnOrQPwmJJIL'
    '5ucH1qELLUEAEoLDLtSZhRX7xkQON2kU+dfdgwc7TX5UAbAF0gQhSfD/WV9/da2Bj0lAwZLLLRPj3YwRYCQXTaOxWYuEg/DOJhQr'
    'Xu6ZnJ8IgNPee/WXvZ8/fHz5yvqeu4iURNhcRmLIdQnKmK3OPnYJmDMiKcXOMk9TL9ctK/toWMsmut6fQT9U3X4i6x21Gn/d/7q/'
    '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'
    'ZH/9'
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
VERSION = '2026.11.06.1524'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
UPDATE_URL = 'https://raw.githubusercontent.com/WMBanner/spider-diagram/main/dist/'        # build.py: where published builds live (a folder holding version.json); '' = no updates
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
    return {'available': str(info.get('version', '')) > VERSION, 'version': info.get('version'), 'current': VERSION,
            'summary': str(info.get('summary', ''))}


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
