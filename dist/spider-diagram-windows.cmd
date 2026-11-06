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
    'R5UrvuKqYql1OnuWJ/qqc8RPCu5MVOr6bDax3tuL8tu4p53eqU1VmTdmjwJCfnbLF0RVGbwJy+5YeO93m2VPv+4fOS8rbepNihcl'
    '1TEswTrSq3PpxlTmujydzhXAUTLYypknupph3GizyaXzZtb7l8PiZDadFjt3yBXDGTqVV2ynfq65AbrjUAgRwKfa2LYXL/gPF7Vm'
    'vNWGi//4v6v24uyUrPX17cX1RefSIni5eDGBA75ceOeUF/5P/qnWHD5Sspsial9060/IuJ4J47qClexQxjWB9e0QxoXv6/338e3Z'
    '2aDirEp3TrvSUXmxcDO/ezAr3XJLLd1cd73RYMbfWvOXZU8cvD0/lKtX3br+0Fid3pWhp/vble57o05BK18IzULp2pwWmm/dYqMz'
    'uJX01aTS85zKSrSWfUF7V1un9tHzqzV7K9k9R7mA+g+3N9Zded4tnK/uHy1ZFQuPy9JkYHUffOBebuFcm3blyVXH77y+FXv9o/6Z'
    '9tBBJC1ezzrj6dvNuGsW3Ha7eN96cvniuXBebrttv7CoCXyhXD1XCkPoiceerpX7VvH67ehsfOs8XFc65fcrr/JYflcLo/eSUXhr'
    'Xs+Fxxnf6zxfHanGS3m+uOMrNzBLjap479137J7yZDVmTkUZzfm2qF8JvtoZr8oXU2s59TuX81m3ONFUcbToWaeq8zZ/K932HAG5'
    'jnB/JTwsxMfVzdh9nXb5rtppSRVpfrd8nT27wmn35m5lFB/nbrtzOdVl0bSuPUnWZrOrknNKNhRcvvNiev12re8PvodnF/UBDsAN'
    'eHmLfKlN71+Ukey+XZu+5Eq8Wbw/EtQjv21ZSh32m/nr+ey9Ne9emw213ruyb7sPxbPa4vrOm1/5z7Ml7zy7yuroSVOss/5SGKwu'
    'Xqb8i1Wy1CPFFdzSoFk6s66n8MeE/89TRxc6HV1oWbdzVZWa96UXZ9B7OH24sSpVzV11n4WpeW7LhfOp2z3SS+IVNF0o2v3SqtF+'
    'uCm6Tn+luNopcPQj25qVOhVnuugXx4pvFhvvwmo2va9XoTsX/trVu37aHtVelgE/hJJ4I6yEjsx3ro0jeXL6Mp1MutX7oVyYlsz+'
    '67S34l87p7rhX0wLdw9GkZ9faN1+17xxB9LyujCv+A9Fp/z8cD/s9S6E99vl0UVl3hRay4r+ArJpR5uVek9F1XVm7Rup054qN6VW'
    'ST1b3YCM/94/lc33+qpnOoMn46bSGdzdF1vToytFaiq9wZUsvYLu8iyU1cHY4WdXfuNN0s8l+bUslxfaGPH/rbYqt+49R1/eVM6V'
    't6XTnZX5SsO/fXs+G/ACLzTn7ZV8egU7+ekM94NniiMasBmGGV26MxB8oTvDR0s07rW21hbvH6TlbeO5Yl6JsLBuryu7jcLj3cNY'
    'qRgvlXep/3773mifTcW73nv3rq8tz8+KnVKh3mk4flvz1aN3Xlet68pjpdftTYWXQr3tqnbJnAtO5XVw9dAsuuJRcwlLOyv1p7Pu'
    'tTJVFFOfglbW6ZitbvEINmqffylc6HO7cHW70mrv8878sj80O1ajoN1q+nJ6fjRvj4XB1VztK3PVnVb75vj1TrqaSiW/NR5Wq94O'
    'O6Y/Kj63RtJ4/uIfzd77LWF6/lI6G+mz8+Z1r3st3s2blTu15QNirAqX8vji1Xg9ahpPpc5T6f5tVSs9DF9nV5bYnr/ozd68rZtq'
    'p9Qu8yW+4oxv9WtZbI5ffOFmdqfPnlW+ohpOuys1WuWWsLRkpS2WFaFp8lfKatBxe5Xze2d559x0BqeFi9JD9/0NZMTzK6PF3w2X'
    'zuxWceXunWpVnMKraxw5g1aXsKjio3+nXXfa1yCu2sq1pRqTI694Ny2c+ULzod9pLBYvaGIpkz13YgsgUnkXTM0krx7xzdtF8cG8'
    'v5dXJrC2a180uzOn60+74pVoNcrvAuh5fsc1PO26XmofTWa2cqS2C3eFy0XfbZd752+VJ/dNaL5fWkNttLrXRmXt5Wjy3jeM96bS'
    'KAmjekm4rypvymzVL/Uaizuvd9H1np2CKzjl+ujMgl5Xt9LldHU7rXS1maBVOk+Fwu243hr7j4JSGS/vzueyOngeFMXz21W1qlLT'
    '25GqKDfavaBpd9f69XRRq1QXN4XbvvbaUsROsz0fNSu9ylltrj3J/k3hUbzxl4P53ZO1vJJea/PHvqsrk9V07nm60Dy66kyPmiNp'
    '1iteFwvTjtNagPp7qq0eNa81k9yOW3oqNZtH1079/mz2qnf6R/yqJ3St5+n4dKANS9M5TKJdKq/4udkuKPXrI11eWbO50NE7p4W6'
    'vKiXxlVlVRSuhk7hTJ0LA942BtMnkEO9I9fonpeV8WNxSErdu1Nt0FmMW++zQbk+nTnem9BXeWsynar1esmrSkblqWjZ3nO9YhRu'
    'jzrK+F0orDztQekcvTqPd2K1Z+r20WPB9AalztFLYX5lFVYvsO/6sBVOqtJLbTaGSnxhVdYGWKlyJdxMYNne3OLl/P3uojZbAO+p'
    'tF4b7ovgDK46j0e8YrmV+8bT3OwX5HsNG+GFRrviD+Tyk/9w7ReGHUcxQTc3PIkvj5sDo2+f3q2q2ltTqC397qDbd8rKw7jrl5dL'
    'f6ABARxdnbcqrdECSxV677dPsjjpvE4HC/dx/jTtXFau7al+3bCujngBGG/l7ol3T8d6qabcvt6fW8XZecc3XjVlKYP6b9yUzt4n'
    'wupC6xWql7ez8vjmeWq/dlxr9mSXSsKdOtDtlnw6uZ5eabfTR91/GXQbd8/15s289DC2rdeC8Sx2y8rznf82EEfPYvPWersed3m3'
    'N5uXzJZsvd25095lq9S98DtXFaHjHL1OnnWnD2pdtzHjB6PO9XzcO5WmM00tdt4fBssj575yVeqoSkl+nlpKxb3xXfmm1xzw7XlL'
    'cPijqTZrak65dNeUhdfi/K03P7KfRoNT//zx/ea++TIfvEiu9l6+e7p+bfear+bD/WV5vmrNn3Svo6nlqqXpc0Ayp3U+L1e7Up2f'
    'me75qmQ4SscBHB7oeq/qTEXj/ap4/VDt8VavOKjYd8VO57b15mrX+qjnq4JevCi0+e6l1i4XJ9OZ2Ou+Ol2h9yDUW6IjHpV5+/a6'
    'Mp10dbkjXZXvG/xl3yp14A9whycX1gYUl7k6teTqCzPK19xby7q/9wrFldQp36gPpSNZmLWEu47ovL2sruRO93o+tN7vtRpoQdVe'
    '47Lojnvv8/FNr7XwHbd0VF70zFWx31WL3c7z/K3tWotT57JarQ8/5LVauY3LV/8NhOYZ78i9e6t4/Sq8TW/G1/eruXJdOro2zcr7'
    'hVU7NR61uxdl4k9X3fLzdKJeWxXg14W7ck/vVeSjt+7CbbYrhX6/fTpRL2vKVW/2XDLvBVAS/YcLs/vglRXbdX2h1+4IbVe23Qvt'
    'rfy+urNmK3XKl69Biu/61692TZTvX5czZ8o366tbdeKWhPOWXmy9ytJ9X9NL5zNX7S5ml9K8ZEzU1+HFe60MPc2KLb/nOm5r6XQW'
    'j2fvXvXiR/16Z4ovXZe0ZxjDdDS4MJ9r5eGwURAfv3+nDlHuYIFecIVn30boG5Ux2ob6b4mL9Ik6dQ+eDjacW6CRzUEsYHgIMQhl'
    'Yj7edODcMd5viVkrMOLqSyJwrxOWPSTHEqBglKzb4oh3lmbaDsKKyW2NY+6JnHmA593cjeoOo+BqeroQu80KuRNSUU9CKuyJ5gIY'
    '0ZvldXLhG+f5s8Eg7raW5FK+WBKkMqY8rxSlePRDpVTMY6x7ReYlXoICu7zWH4hrH4kn9dhRvyDsjN63MYpiimMHSel48MRnj+Qy'
    'IAOK5TJgufqDNelFjWBcG/1onCRif43wxewkTM8TBJidxELyvBMvnnWHFfFOtp88DZPjeGGAfrwAPGT3WRDAo7N8iSi3zc/ipwgT'
    'iW68jIi7cxLApzve5hN2+5w1IFSTfdygYS9+8LABSbOSER8bpF8h8ZDxHCv7hd8mSTneMHsT0nYiHc1+jWP+ioyW8XEQ2Ajt0aQ/'
    'nwnoBVbGeW7/+z/9Z4zHf8Z4/GeMx79FjEe9XtWrazEeDUJT0N0iHePRv6w9vpAYitNBoV6t8zjLZ/Adxu/dnj4+1mqUDoI4i0a9'
    'eTm6fRy2Hjv19vlyaHQmJOaibbe00855Rxgrz0uv0njil+23W/Oq9TJRn+T3u5U9fXp7lO5P/YczjCfpEVoe3lKaj/2pVdu16uLl'
    'tFYAeM7sJsAN3+tnpwArKV+N4Kk/tp8eX+sXMPej2875km92Wi8w+16//nz5dvn+aN6MymfdZd++Nh4LBaCrBcx/9bT+eNusnpWr'
    's4vq2UIfVv/9/gzOBr15r9foXfVMbbq6HjuX45LSVI6W9ZY+rTxdTaeWdN7ySuXu+4uzfHs4O7+eiitprtWePOW8c/duHXVWjlJ/'
    'fOt2FtP6bWlV4htNkHP6fcmqdwS/0NSFsdl9M6vP+unr8/N0IZjq8pwXi8XJ4nJWMIzLN5Mvz6zx7UB6LFQuB0/do8vh8Py+dDSr'
    'FBbNyvVo1eQn1wtFHxzxc5tvzaNyGv9QeGrwoKVeXtbeHGFQkRYA/Uof606h8lReaUdKo1C9fjwagz5Vv4cvzpnyVFgComr3bmF2'
    'dNoQW/yb8FCYdiek5cUZbfB2pN63a69FZeTeOC/qzDC6b1dnt2Pxvdjme7OyZV+XQRs5mvkAZNFCGJ8WU/0BYJyK3aF3J/tmxR9r'
    'K//8tdHhx5Pp3fjVXbYMw55VzstPOK/lt3K3c3HRf20LD1e3pcqFdNr0zlsNV5pez4puoT69nuq9tj/snrv96/nZfflIVSo271/P'
    '9N775EbhC3ZBHQKPa/8cLLq+7V5cqJPZeasl3M8flk+z1yt3+f+z92ZLjhtZouC7voLKqlaSYiSJhQCJzErJYuG+BhdwycrbAgGQ'
    'BIl94aaWWb/Ny7zPjNnM89h8x/2T/pI5xx0AEREpqfre6rebMgUBh+9+/OzuhzvIswVnCpeo3L2/iH53IsrNXm90H7CNWS9kD7O1'
    'XtxtmCMz5b2avHAWi4Uhcw7jTrduT9X8S5d9NNeLvghyMVdb1mTbk4oTEHdmK2mWNj7S+fF0yj9aW5eRV25nHuzHdRYES69th72r'
    'qRWnksnP5QHv1mTeMjdP49nF7YzHlwEz16e8LzX4ak/v9hjfdaPx5PwAfNPEfHw6SELNFxRxN4nWVqNp1apN9cgdW3I1uL9vGOrs'
    'n7OZvLbXNVzPqEF9g+mxOS8+VMN+wK53l8N8LLMy04128kUURf+quN7mgXP60fGBL9/3wnGxzwdNl+lORb6hPm6e5LX4yC1Zt7Op'
    '3XeKK8dWthex1toUq7PNvl27SqfWbvpYfPImlXmX1Qy5b55Wj0J5Vfelea/V9lxHurhnxXY6xbYlzPhoM2uB8CyZ/XHV20/34wML'
    'DVWY1qzK+d6gWRcZyyqeL+vFdaBcHrH6RvPJiyoLjtVMtq+dNo8sVj9odlpNr+OcL52zenQ7T9VZc7HYVsu8sq+ttvrkWrXZTc27'
    'bFbPh8BgHUaYLcPz4l6RPK06YZvhY0OZTDZLd9ATLEPznnr+SSufHnFk/d2qFvWfOEsLpMbusp+Mj9WeG3rrsR4OQplZnC12e+ju'
    'pou5429njCQfXX9lzg9s+bKxAK9PHv+5GPKxE8kDGNBDzTuXV9N6cJiq3pofeU+CvC9erDbLF6ftSJ8CfjmII2P4cviQ27Qhd1mQ'
    'D8XLrrNquMVpXXWONXsOlBE27uk/1Z1RM/LE+dbtdKPQWyqKvZ8qm15XaoaKPfc8zfP0pum6iuUcJsNmx7hMRost6wEeL269hmXu'
    'rUqFOQZBAF3Tgp3uzbSe77C+/jiUh+YFNy/LVBo7t2hfjp2wU5lU59N182JqE+W664WrZTO67i9ld7UYd/TW1WO1xrxpHVTbZZjF'
    'tXWVouv96CT60kyX5w9Ml3nkqvx5cVgYzJyvAqy3+Ian86ttq6LJRW/UWgenp9rQK8stU96upPv5US+OgFuVHrkyPv1B7tFzw+eP'
    '+zJMy3N4xKcHxQ655UOxJW+8/XXZH6y2ldG5MeTsUKu5PPskXZer2bxTNcXDWOx4xwPbXT805MZ4thjPKl29U7Orml8NLEtfiZ2x'
    'UhQ5a3F+eCrfP2qBzmpl160NecvRRovZYTM8TS9DdtNr+Y43XLiy5/EX52h0tsNF5CtaKGvDjbK3fWPX3c3Uzho4vWflNWM/Hlzc'
    'o1p0RuZ8VO0uzYOxNqe6ID1vusGGm52bETBX1lit2ZuaPa4BC79Ri37ZnE+r3TrmPgRFQVqUu4HNzTq9dji6LPdmo3wQeeCPJxPr'
    'NQw9OLrCdTv+4v7CcKK8FD0tYnttVi/uV6dxXTQXm6NYr7kPbLPszhvH7lGuNmoLvm5dwy4i4G5LuS79s3F8kjxr/hhEs+nKqi25'
    'ts+3j7PoYog9YdrUgsVT62RthN35UUGzXwRDGirHnlE0O5H92F0cN+fL8aCZU6HHeXtJnK6lS3E3sNeN07nWsYtLdcj1dvvKFOCh'
    'P2xPH/wixzkSoz/VrrxkrUdHEyBruuLOan/zuCpbrafQqCyL9WsZs9+nuc/fzNxyp5XyKRy09wBGYyC4jcNON3R7qj7rT11hLW5t'
    '9rw/bazlpmNcz9yl4l96XYapNaaPnGJbe0BexYu0P8iNmthynnvbYz2Ud2Il1NmqzaiGc6iNGo2pP/XkR729ak7HfdNQ9xU+HF8X'
    'nZPcqHQ11plHM2nuDifza3ekHL3jUg09y7wGXWOqL4/Birt/0M15unqKa98XNWs+bLdmRTb0x9FYsyVWq2vlszyxO7ohMrPGJTSB'
    'grgR+zA7HXeHqa8IjfHG7y4r7IlX+93KzuuN1TbfFgcaIOJB3dwvtgLMsxQt5OFW3B+k+T64utUiI7bG3UCz5NGGsxr3D4y7SXmN'
    'prR6nEz712XgPdcWQ1MRhuFxMGJ7a7Nfbe2uzdqg82A0L/Oo1gfJcN713OZozNkP8nhelUbLlWdeR9d2cDgO5AHjyfKofF8XRRCp'
    'y7UDd1TUsqcDHlI8e3KI3OVpZjnzmR+54UzoefNH7rkrzH3zflFsNMNINkNp4Z61usBMfFFzR8s1yPnlYDD19uu9sjbH3nFyXZmA'
    'Isab5SycjqtRS1SLD7MrEwm7oj3aTu+fJr5s+dtuZTC1as/Pz8MFH07OzNy2VcsOB14oXcPwtA5njZPbDYfDoH5dlO8b3WfFfPSn'
    '5VbDP4/r9tibwZ6dzffi6V7Zz++VhnW2jrtpz7CWXPV6kQdncxWe5kWL0frCQGwLnOfs54rjKT7bcwxRaaxrExXwnalL1/XoeW5d'
    'T6IYym3TNsdDdzFcrBZF9mn1aHYX8/1F6DSuz7P+wnwQIs/zrN5seu6svYVWruz45/ma32lSa3YUxoE4aJ9D52iB5K49rI56g2e0'
    'Sdl8irYBf3ysikN3c9kxyjMHyPwV2yCbVac3qJ6i4t5b1Jxzsxvwwbk/mxeHPM/XRytt0OoernNtN6sOWo4BwwiWRq3VE6fTRSAA'
    'ojWsKAgG3aOi2fpMrDGccxzJnBm8YhlsQazIV/1aPx3XQm+zDJ4lY8YcvOtwxTWmR1b32obvSYZ/Au6mf8wO8NmZq6I2GK8Xs4EM'
    '7Qi63K3VGXc0Av61dpr1XwxBYxqWVFlsxmyvOFtH+0m3vB5v+o2nofh41Wu9oyOa5e5wrjqjAesfZHXeFobuWpuI+qWvNQ+DsFED'
    'HuTkX5xgzRW1+pF9WK/ZqSc0NOca6HJdnI2vuiT15F5LmAp+ZXZtuXwY1GrmSF3O20V9683GgV8XFwOGH639iJ2eFcfympHWnekM'
    'cLdW8f6etZ37WtcLHFEeACbdbqf+4TA+slbdV9fLpTtbKFEw86RZT95IE6WuHPW5BPyIxTZaZ2UcuXNW8YuLh+NpHDwPHn2V6Y2b'
    'njuZDRazHhtx846k+NWnBzZSQFAZz9yeNjkptYbu257NNgYLQVYW43LRWlTrfLl17jVNZyDNyuP9WVnUgJNoCPbosNkbFbUSRRe/'
    'GdYm6yft6TjYjxrheRM8s8Flc5kxk/YxmM7O7Dkctt32queqSveo8qovuFzEMiLL8mKrDQuj7Twp8ORwahq9C7/3xEOxOtK1J7dp'
    'XpgiAJN7vrD75kaJaiDMD1tD50bdRtw9f5ksh+HaleWFtg+nG7YTTTml3q5oYWOx6fmN59le5mwAoqIlDo4TYdOp6g/LieECHd/v'
    '3Haz2p/110uuw7YNpb15Hj6H/ky4+OqoNuzrvatd2cyEljld7IJnd+NdbX5zlZ7Y+wepPRzcurKrzZfLwOqulfBB9zrmuAl7Ahjp'
    '5nHOXtZM//TEPqrOYGLU+tfm1Kid9ebzdV6zufNk2hUPx/C83cuy3Jz0V21P7y1UvaVK8+vJBAbIKutT5VEP58dG8Sjo48HcXUzK'
    'i5pRjwQxtHc9uegPijXtyq5Hj3MQCtaSMHBarl4rb2oN4YmxtQ3yrM8mP5KDWkc5sqsjv490f1WZsDCmDfB/91KPt6vl7bGtH6q+'
    'VL60J1Xb4/R6uBADvnodVpTL6LQD0cocL3ryQhkbonNx1P3y2PCA7fSFBoiOXuf5QbA9kx8sVb62v/ZmPZCVhaCyZP3mYHn2Bgo7'
    'aIbjQX08dGqiZ7peNLJEz97Zq2K1fW51xMZoVn/qLebPNctbLHr7e+nKmZ46mD0thpVouwy65dr9w2wwjaJnrt41G3PD883nSKyv'
    'u4f95lkYbJRJ9ChPj75lF5vrysFoCAu3vLMuR5MVRtpp6Zuh3vbmq5Eeeu3W2BfnXlXcy+vdQbKe1jDxU04yp4EfbSZyT5vVjK7X'
    'qz6yTocdLXreqBKMzgtzaz2zurDnKpuoZjhlcXqdno58cCh2up29VjxcV61xca2M57Y7rzlPrcYh9N2Ou94sJl3rDOxz3+iFiqrX'
    '5OOTMWe681rYFANPZZa90dP0/Hyec8Yq7LJe2xc6w7IqaCNB2w3Ks+N8vfDkYWW67xqBVJYWbF+WJruZGw4PgSQ8DWpReD6avLcO'
    'Ne8yD3zPG686rttgVelSntnPRica18d1vnW+ry/d58cJSNtKrV45nAezyvS8GbcPLLcFWXPx0BGaQ1exx5o5MP2DUlVYfj3p8de5'
    'y1iXpXphwuFTv1kJzitrp8hedFrx8wsze3KF9sHz3MZCWhqByl4Cfm2yjOyNFlN1J6iMvb1ud/f1YD5qL5ryNdSAiQZ+TgtqLLO6'
    'mk/PC9g4Xddr+sfpaoVDcLye63tWVH4+6S2YJnmhVyp26B+cqjZfKi4vNzZP88lwzF3YxmJsndjLUJ5NZSC5kbe+DvnWsfn0fFqv'
    'V+o9b1RX6sJvaYMZ89RbrwQOdYx73u0LV3NpdM91xZen0tJuXLROYF4vo7O8VjvBeTxfTJ9qg/AQThbdQc2cC3u3Ph+s6jtlb3XC'
    'iWdsAhc6CTt24D49NE6D82UesqeIW4V2KHnOurFgD1d3ZrhVvi7OjY1bl2Th7M9kmRk35MFo095ZVdlcG3ZT76vzMeOvnxRnPZpf'
    'XbW7YwxGOrq82xYaqxbvefs6t1A6bqQYirjeCp2R33zsn6ZVa7TVD6fjZekPOjOOu14W7roaDCOtyQ1ldvwoBFer2r/OWP084zTu'
    'OD7xTT+8NM9ROMCQeOcB8Lc9bn45R9FjR20YYnENnavdm5UoOLnOsu09HJv3QdB/rhzDxukINFjxx0pv0z7I0wWveMATrjpR9boY'
    'y2xVOI6rwjA4R8vooVrdDqUglKX9VmaY3krUdfsgXJr6QAMK2gJ+ix3r3fbRfb6GveHDlgVh+roYHgOJcav2uuvNTU/Ux522u+S7'
    '7FUea/q22G9OH9b8g6UN24Fc0fZ+c+iIE3cJzObT0gm1lmM3Bv5C9ZSeIA23wHxYg/WV91dr6PnC2Y+v8+J1/NgZjhd6k7GUxnTl'
    'WlVVvjiL6mPX8jq9pjca81LE2XbPaT2Iu8vK5xvX4azqzU+8ORaLrsav95XWZM6FM6/R7e6f92Ev3MDubI9d9b7i+g3hMjfXT35V'
    '1FeDzcpzLbHXjTzV6815pTkYmm2H1aoy05k+VACvagNXUhlB79WCpnLsDiW72PBG2+Oo4zYaprlczlhv5V3cxfk49vQzYL3VxTiZ'
    'u2jPzJvM7OLZD6tmrXIEeZbtc48VRxksZ6OL2JerwdG4RJ6419jNmW2dh4d6v/80MJrdYec4O3ttOxheuVA/z0cA1tF0PJMHM/np'
    '0DgcDkF7t1rr0+maNa9Lr7haeWtbeRCBY93JjaVXPj2yeuswHT81NQDP4kAoW7Ni7TBr9GRhqKxkWGrH71UDXxg0zClrFd0zt2Rb'
    'e34kHLRskZfFm8dqT5RFU10I9pERNsWg+FgzhhErj8vNWvna3ejDzPOk+yCZUleaRL3aWVRhDhr2aXEYs5wH6Ju3i6tp9cq4Nb+3'
    'ZMXeSBWj8XGyb4aKV4TCjyAS9pWZbVvyeWO1fK3I7kFkOLbP0j5gwyDshqO1twp6MiNXox5wThPPP/e39wu5az6aD8+u/ziHHTpU'
    'vYPdXV+4+/v10+XP9U8G3626HWUzmlSvk7bUZGeNQa/ln2TvOVxFtbnfqBVd/eBDjWr9IodeWBx2u53FZNbtTGRvMN1cJ5E8H9Wu'
    'pgx7VdDb/KyztPQV8Omn+3qNBTH4OmGkcWv2PBkZFhFQgwVIqIAiu4b06LjLjWkt5vBmP9Tl6VBUHlh/4m/qnjjYdIUZZ3cNretY'
    'tsGL6iTajnp707VU01cvwUC2VtGq2Oifgg4/4acVZeeKMguSng+iqDNcW3L1oJ5l7qA51a2hzuQG09/vro15K1gI4mrPiddF01xI'
    '/Xmn29zZsti+eOaqFQxlTxpKXHVq7LUZ33h+1odrMVj1BZDQm42eu60efGHLKUVtf4YVEG3TdpcuN+1Nw/nkoelI14bsgRgla4hi'
    'ZmzFehJmwZ49yaZc902ufqqxlwHLK37rwTsGz9tlU37yL8vLZHNBP/zTuVw1x2VJn5nK+dQ/L3aj4bTHsbI5aABncO7NZG301Ose'
    'lOs59Jqe1wa5DPgtdzjWfWW6UF3ZeZz1j+1pb7g8OHzlWehHT129OnmW+6F/XrQ68/PzJLTWdW9k62JPUbxQ9dqRIXY9EAIUq1o5'
    'R822cmzNmoOgPrd7Ez+4euOOtbSjtTmZWHKbVYTDngOoaTAsEHf7QWtUurPgYW+VAS/M55dyoIXHoszWzgul+rRUpxXHWwt90XO7'
    'l2DTGM+CtS1W10t+tOItw/G6guaP9ZEuts41PzI1tT9YNkDUPDiKwQwc/RRdlI7Yuz9ERnffhCFXV8yyPN277nEx872n7m4nwBwi'
    '6D/07E7ddVe1WnXaa4XrwWDK9gPLUCQx6Fnroq9Lj1JnXj5Mll3Lge2orllmcj5GXc2YdYdrxzsBJyMVjzNBbBvqSBroQ69xeHxY'
    'mNYqNCKQCBjb+R/W+7b2cyYczBmVbc2fxyAEDc9LYek2HcHnPJyK3nk8Gy1B9K/V1O2a3Q0DK+Iay65R5TpitLmq6wYIoq5fvICA'
    'f1QMtdURGFHeSjPZ83AqQbqelWfP7ALIdfOhP5n2RnrQ5SLP1qL52pqt2kdT58eXmh4cTlEz8sYVdVgpD58bfDAXnoXGchWuq7au'
    'DvtuBXizOUhTvnJYSKyva7wnC0fTOF036nPo1rqVifZ8ugy5rm7tvZXrdoYgHF1Rd63OTVOR1+fBaV4Pq9XH6Ngr7pUBYCg+An5+'
    '+FjR53wnOp0bz+58eXUa0HsZJ0abds/BZHMdKsDk84fF9GJVpGvVfKq0y5OBXFSeRXbeGALTYjclzWY6WidyHyaKIu2rk92yJ2rZ'
    'zENBuuxq9Y2Lbv2DzWRp8cvVc9CQXnxoqUXhufg4Yvbyxtq7/XHQd+aPRTubbHmrrWo/PfbDZrjYdbnedHp2ebZb9EyVG4/qwM3J'
    'gDN3gqmNjaCyHmhyBDzd5FptcOZgO12sar3lJAgl7cFYPE49rjvgzqPp0XMrblNTHH/hwj7uRR3uFB6kw9p45INo4JyYC3ArV8tX'
    'u76yBKj0LlVzIPdmirzw5uphwhw9meGc0dNckNyxVMeTtrBDIqH+bI/a1/ajtHT9Ze9siKbXk5fzoVK2VrP5UA+mU7mu2A2/wSsR'
    'sE5jXRKZcLSze/Z91BTm1/niEaSIFTccX1fRclwDNnXrjTRPGPXdcFy11YFfn5xmw1pN6Zqu2N1vHW/SODQG03NoGMbS2s/7Cvxx'
    'QApoG2399NAEyP6f+TdsRcrZOOoCUE/L8zzYofetjmMpzZVpnRbTyGWAndXsAbt358PySjT143FWWzSmk4ALxDagPH+we5SDcHxc'
    '9RaiEu4X7tieH/eVprFSVqvFtSWvi2Y17A2m83M1jCauyc4nzsJb+eeaV90DxpgsT8AbS/r1KeKPxdrEiKSZOdz05wbnakVhw2+X'
    '0eNTc75udsNQ3swuelE/6qfZdeSNR43zLFiYtsmu1MZMGW4VU1btkLH8lstfJGUw5f3pUh3Mm+xSxcMSgdS8WG6FqQwq0cJXjw25'
    'tjpcRiCrTKLGVe4AfltH5XNtry2VRZPfDNlFONXLl9rp/tHu3Q7DsK1+7152zptJV1x5M/a05Cddb2mVT/f7I39oN6zdeWWaBmzN'
    'BVOzjwCMO6+5mXl6z9gp23Ox3eute9J61dtoimyO76XhIzAJbLhwZgZbXU11tuUdZFlyQXATLpZkKXxxA3/Mq9VSgsXzYCvPGe2q'
    '8POJpVYl35cNqasz/LM/tRqmoPeb8kachQdYmjU35BzRGMmddqNsMRV9sV275s7iW7LKKursMjBsfmD42qB5XDhjEFJh+SJTDUdL'
    'T5oOGr6nOlPBqM6vvSMPvMnx3mq3nloD6OJA3VueBfyH6HitzrB3+h+BQnFoGkp0EcdG1372D8PhZlfej8t8u98/my3n6SoUW8VB'
    'q3zfamc+rcbifa2YvCuu1bKAMjY5adWNtHA8P06l6WQMQsGxppQjt8IOwu5+5k9nMPMr32OdmROp/K7NPZYXBsd1uQnfFVlV603H'
    'HR7Ei/PCGw/NTV12r5OrHHH97k6yg3VHnLBHLeg0rwtbsaFPivYI1QvXR34uLs/X+XlysZdnpspqRdd1WGbncpIizauGV71s+l7N'
    'X0+3YsNcz5xLdHw6VEVHtfWz3jG0llmxx6ewup60PXdRlGZ8LyofN6fhxl5Eg9lB1J6q4Ugvlk9PR+086Fysizw+DhZ2sz/3w6vj'
    '68dxRRidigdb7w4Os/WyYqHapr2fh9NxfeqNn4JH49gTQ33KiXuJExqsMte6zC5g2KpUvb9v73qvMUSwb07G0f6wZKuAGQT/wI5n'
    'ovm82/Sr3U5LFTS1OxZ7R6337DLF4ag2cjreg+cxS1Y2xo3IH5raM6cYNUY+XvhrL7IaK47zagPL8xWWuwRrSdfcshQdn+2qZ26r'
    'HW290X2tpfZWMtDzUdsSrnKlx8J/lf1MvahhdWFEHXYxdTgj8jp8UJ1VuSlgfrd2rO+G3KLX0OdWp3UaLcWGOCzPmZohnqehyIgS'
    '/zBrK/YstIOrWJGE6bPPNy3gwHne0wWJl6rRg6I2/WX9fF2p81l3MmOuy25obHxvPr60peN+6k/PznpwZWAfNFZldTfaD/um2T+K'
    '2rwxB85bmA4rQ3v0XD7PN3x7qO/KRlCOnqUWSIGZD2p42KvRftXsHmfGdjU83T8c/pG9UmyWeWUXaDB9R9WNFLc7HywuQ3FTNzTF'
    'i4w2iDOOPLk+XCfngeGF+kFbDNZrZR8uvYl9kCNh+HhULSNacNqk7qpeUZielmogBXtdCLTF7Hgwx8Onw348qC+uR+Q429XRQXKl'
    'kaUfpnMQtbnl8JkVy55avdZbu14oRc/3T96TFZubDOSaeo6nNgbV05NlGpvHcNFk2UVP9VXDvZqd2aUrDOzi+CJ6582KdVxnO5CV'
    '3dQ/c92D6nCMIk32PcU9PvWuS+3YeNhUexNe5ya16oTtDUIDGDuX6ZL/Red46G+fzct0bY5GS59X7Gi8VCaOYe1FZj5utT19Ks1t'
    'd2YxRWUhhcy8Yk/m1bIycsy9qnXCCgsY4l66v68/m9u3s3164By/tQIWefE4ns/Y/lXR0U5flerjEcgLRqfCjqL2RpiGm0FjVR2t'
    '511vLPdrB18amktGMfAelfHmWfHYqSWuD4COK+Lo2ZShE+PWfKieg+eK7a3mmjmZDSKZFyNzpwWuy6xhCtSjyWuTtrK8n9WBDNQu'
    'q1rZYz1TmbMzfX5/rz/NyK0dDbnBjrXGc+X+IeIeapdgvFwDOZqws/AUXnq81BuWF1q5LWjyWloYvd58KM40MRwMtN6mdw0Hs4Cr'
    '8IrSY9N53T+71lS4rNa7wWjZc9duywNM7QE6cLxyUFV6nn1gV77A9ppn/8KFO2nH6Duendr60qq5gCw76v3DujX/U6CuyzV3/xRI'
    'lRNwjqJsHK1w5l1Hil1rXJTRYnpWAMbbrgysmQRbZriUPOBmB60BqjaG7uRJPam7iuh5pl9ry+qgF/rh0FH2cpuT9JM0kKfl+6Zn'
    '2wDTQ5cZyaL8aF8bq8pcKD8L9jzserJbk8bzxXEB/Of9YTjtbPoDP2xySkPU1sqlN+Wi4VFZXRvFdqW8aG/O9lQ/rKdsoHeHmviA'
    'fvWnVevUeahOh8vjudUShadiX3Pt/qKy30vqrtwcTQauyI0azeF2sfAEtTmuPT7rzNXq1cbnYvRc3reyDeyZvaKH+/Nzpvan1eFo'
    'tQVxML+c++PNpjd/Fjtiq1lcPlwac9tve9WGtHoYng1H6DYtWVYE3a2y49HQ6BzF63TO6lfnzNmzaW0Y8DOtG4lBaD4rNd25Hju7'
    'U3WkBE15UPEcdm9GjL84h/KgIZggJAJ8AXGUZiLDLNyOMgzWzfE43O+XLMiPQF8UC1hStQ4UZjPyI8FUWVdera9Rdc7Lx/F+Mq/c'
    '3+8Pr/dXfVlzrPN1MXrsNy5ALPUid/GKIALLC4tvG8PFtbuXF+e22zmf2+fDYe0IzYF+vnRRsyU3xnq3u/M9hp1tK0d9XPW2vmF2'
    'D5Iw2dYrlcpFnjggIfOPrNy437Py1Zs48kxhN0KrbYidiil13F7N7Wuh5piuodtzc9Fwq4tGZ8h6Z73fqsthL/KAXCzXMGHMc7Mm'
    'eYuWfe5f2ahXe67OotHIWNm+Cot8vjYWkl9p+s7gKkaLB2t/z9vhpFIrdiw9PG+MlmKehdq0L62Ncn249Mrh5l57iDbypdJnli+r'
    'HnP7y+HMwUprytKCZeWHXiWsS0/hdNSXN9xxO9zyIwQipT0fCqPB3gz1pxb/6KyDy6K7sOftY8viXIdnpNrxID89VBqXebUJEFIG'
    'ceJhNlhGjNl48vxFz404vuf6DjD207F+nKrTLltX2GaIZgZmXK+0p9UhZz5U1aszaDIX4O+vrLzUhc1MuH9YtSb3/+vfH+gnyuXV'
    '398lF1OnAc3TIz8krjmGD8GTOE4Uvj5uU/5Gmbm+juOB4l3lGOclCVOm0FiIf3+3C0M3+Fgu63bpZBwMV9cMpeT42zK+lfuGrf2r'
    'pbjQMV9XNAygFoU5C1JzkJqcn1GS0GVxaBuHROEsvO7hzn91fonemq2aEcZHOWEkLTy/REOjYC1zxyeXbSfRVb958uvVfdLsqwul'
    'ebxuvUcu6f6BzkX28mORKTEMV2WqEsMw4ovbpSsVqSRwElerVaosw9Yq/8Rb1rnfOwdGOvr2uNeExvZSsvH1cIpfnNLr3c5rxbeN'
    '4xzGEbfJqTeM5GHSuLQ0XsktaB25hvcupynBjl5wrjlhqL89NLb+ScE4GZmr15UwiSir29rLq9vDHYCDfQu8ghGI/uPf/+971zUv'
    '2AEaCZHeBf8f//7/5GicvBfJORJB6xYtKoUlMleHb8wVSc7tHcO+ddm+kFBUcQiezKAw4lWOnHbLacYGxAkM6HeLcFTKvZr5OOBb'
    'UrFGAp7RqT3kYKY1U38RRJHED3sbV4CefHwVW/hN9KbMcao1PYB3Cx2VLVrKJXHzSDegagz9ejH1JNTdy2pfhVKh+eP4Yt+M+fbq'
    'BnTu1Q3oTxRmSJjqf2xrCRJbEhmer+KdDLXam2vFkz38j13cThq+XQKMA6fXAGO33pGTsLexvLofnXt1P/oTgfrXY8FgdSWOERhe'
    'kGqcwGevaBYEsSRVBKHC4h36FYH987H8wR3TvzcW0q3XY3kdjO/VrekkoE0W27HQ/1KNFyoVlq+yFfHFVdMY1anCc1UOL9Jmqv/A'
    'OP7oXuaX4yAog9z8br8ZxKtb1LlXt6hPEYW8Xo+qVCmJEsBNjRGZGpdcF0/HIdZKTK0iAdLmeE5guT8dxx+d1H05DhIIgtwEj716'
    'PZJXd61zr+5ap3gJqCggNbp7b3gmMzahwpdqrFjDCGAMK0ov9g2D4xarVZ4XeYb/86FxG0mvVF4NrXLr8qvL1rlXl61XSIxd5QjI'
    'aYMk/4dcsFNexNoVhUpJ4pgaK7AiB53NhDvgWLZUYwRYAoHj4RP7T6Sfv3OOmsewPEDcEqLAp0QhDsYRJAF7UmQYhxLPhLIzTAxz'
    'i/E/SYjeHQltdwstcpcckw8IRiZdSJmYBBNnQqe/D3K2YulIx0iYbsfNEUpAsC75Yrxh5aDjSwygYhpABP3L2+Fk49pgPPM3IW3I'
    'yWfa66QjhLfakcUkR6yBKBwN/URonOIDUOISE0ZRC0gsEwzLHdylceuSQ+Mw6vTEOB3+N7o/ATj5xkJ8K45Mcu44Pxo0CxnSTCOf'
    'ICcC3B/yFZccXk7/R8FcCL+YL2mOes7WdILduiP8EhlYwlU2HWcLC/zkqLDemZCIuKxpfJq1TqJ+7ijXFNxlFh2fKHNNsih4Bv+P'
    'epdwsZkojrcotK6JHcgEx8LPUUiiy7xkqh4d95KNvOinVzCQsIuZUX07UMyfBF/kXoUz4F6FM4jjWeE+Cv45iCDBOv9wBBnuVUgC'
    '7lVIghYsx8dXwF/MBQTK/8u6/MeBOLhX91Nwr+6nqKcyD+yCOwqiP+Qs55+FbN92+NvU+9bhV2IV90qsGprIMxNkmYtcmGKNyBhW'
    'oJv/hYDxbVJ9ixn7ilPlX3Gq7f/49//LAjYZI3bHeC3LHnE883tc3mthUPhTYoZtvCFmjApgIv3eLSyNW7cCkIXw9o+1Tm72INLC'
    '5YakKEbAAL+470Gkw5DDJPzqiQRQR1TvRoTiWKXcfRzP+s29Ltjg20tdXseJ1i03jIMC0ypQbiFBg+P4s6UcCWaMTby40oXELY4D'
    'nbkYidrZ0JDIcViwl7LGd2QR31ERnS7jO/4Vu56AyMZ3rCyL5dw4z9e8ZgwZr3jlhHeKK0oBxcmwUd/gvuPKXscm5l9Ult49g5WJ'
    '8dC+++1v5UD1DTf86bu/JQ+qYwdh7q+5z7kg9/mnNAJfyYsAdVHJ0/HzQeFTnDM4biHvX/Pv/6Iq9lEJ3hfukF6bWpxKnjExCPF+'
    'HZpInjER44XD2tJU+vI+rboxHEzh0/sPCgjn+ofgEoS6dZd7wOXoK+qEvDdgee+AXdg6em7WvsuNHZBtnbtcCzd9aKhKbqBHwF/c'
    '+4ZiQi8UO/gQ6L6xef/pu3I595CEYifB25AUxwHfaJi2jxi3EcEPFRYA4XiJC7IBFrxsMVogCN861rs2sRHYZ8YWGncj30Xx2YWe'
    'luLRjO579em0DgP68j6mJu/vcu9jLE0eKf4jjxSrkEfKMJNHulfJIytVWZUjj8KG11SaQVJ5cS2QR5XjBEF9/zWZzfFwOP3XRrvX'
    'wymNWdj3ycfJdDjGrr2nrOeHmER9PLJplna/+a+T9qo+gWy/5iYg8TB3uT6iKPjtoQgOv4seAi6T++22huP+/fRtzWm10KP6v8r1'
    '8aQ9HEC2yicAU1iXdWS5sDGNIJdHtKKQy6DwfhzcwP12c3w/hQKTAlHRIVmlMVUVDIUXAPNA+bc4wPd33+FFP4AayK0vnwlmjNvJ'
    'RKwmioq8AZ1CrSLghQRnFL6j9wTZh0eMtRfgEn6NyyeKluA9xgzEalSaBzce/aoASg0xIPmJ3EmF3BEGnMRhxWrFDUwIfLu101MA'
    'yWI7v/4Wt0M6Z2i5Dz/F6BS1OCZmy52AP8Ta7Vz+19z5LneBDXiX2+V+g/2FjcW10wZhi8EzbQhLk0C+6YxkBoQar0CPmzCQ6cQ6'
    'Tr4BeMcm5QE13OHsQXFYeeTbCWScUQmSu5C/BwAPQFC5rQ6TgaOBJEN7dCI7jF93NHI29ACKT/QwD7sfK49szZmEGDERJ/uOhE/N'
    'vuMFQFO8jCvp/R0J+Z6+xANN303gR5+A0SVdDKFzCKLYELILLaIkS/Ni0gCloLRmwwdq8zm3UcxAR0wGPNBc8W1dSxI/fReDs6Zv'
    'lMgMce3yBUSgsCZArHZKYARxTCsooenJM5lfGrYSvscNEA77Y+49De0Iu/nkKy68WzCqyIJ3JQqdKVBaWgusdLKb5uP7ERmiTWgO'
    'jLNUvcvRcqjQwbiR0DZbEgCpbTYfc20bRCwDRpfu2LWpkE2Sdh9vO2trpHSghzir0LdknPnCHYX/j2Q5bUfDnv+aY/CPoREoQFYH'
    'et9PY23evQASyrDE/EoOeRUcKmSGfIRN+ZjBXb/hfzDc8o+5D+k/ArSx1EwlZIB7SwkpS0JZQRLpPsMg3kojYZR1PzBARgWEA4t7'
    'yeWJSoTgG+j0Dd/kAK2AxIZsxTEuQiQc7ADOE0wRZYvwVjfSE3ofGraxJleThSQaPeY/KRfoG+IzDVAE7SvwgRHBXEntGGEQatY1'
    '2ijuEuxV4SPR/sDuyoEIAVliFUGyWrelitcEpi3mk4AnIJPzrvwubuQdrYvLAf4EqCexBWFZzCiI5/HjG+xNOhsXpyw6/ONzKado'
    'Gkc91mG/i9Pe5fLApCGLCd15V/hEpskm16Ihss0Iu3kKERmAoPXDPwoXBdI8crMfNqajkI2etPy2cO495gS2ImHkYD3CE9DuXKyD'
    'T2uP6/iUc2GoxDJBVdYkBmpcPVW/0R4QpQbUiGMBWR5DtSomMFmopYDhvtC4pI0gEkIdyx3VuJ2MAJF5rJIBCNiEMCGI3W8zUijl'
    'xqiXwXHG8wdQBJBm6QpCI4J1Wr/quAZ0lPC1eg5YJ8CdmwgaOfIx6GdIHCogiOUF+XSiPHACgud3VDd0iXn+g+2cSrSJSi7RMMCg'
    'VUAzF4DadwSPwZiDHZEZ8YJEDFSMAJySFBjGJAWw2+g/kQwxMKXD2DpEisP9FI+IsOm37sR2P5OSSiUgRoY1QJ2L20nLjjK95pHI'
    'HthE2w4MKh2SGVJSmRwonWLCzgx+fyvFCA8wJrTYgBktI63HB8DGsB5I8Eu5H8vfqUB0AmA/T7qPX+uAkX0g+UA/YTfTt19/i7Fu'
    'BsV8Jnw8Czg2RsClUkm7S7ci5ajuMrsPKT2U4NISZBJ/Nz9/l6J0rfR6jJh2G+8Ns5MqgT1ALR/iNoQSxG6w1VBPFgtXTCFWTtEA'
    '1RvDDzKmKwpA8U76mBuu98B4lXDy6lALLHE+TtLjV+gewV3/9m/QhULJUtx8/ssBuv8VaVMMKpgwCVGzlz9A8mdgNZn3uZ9zZN7s'
    'PyIvgBM/Yl1k9ugc8q9nPZ21CskBVHIT2SQoM9lMMd3IawVoz9eROuToVY8lI2jbob7V/bz2cymupgD90pIXaBy+0BH+DJgciOEn'
    'EMrS+i0DIDLU83ivYIHABPIrR2Q5si3j10/w0djk8sfcTy8Y6kIOL8Q8EbLxEg7z7218f58p+rccm82fZHPC2/ag2Wm0cVLiZWO/'
    'IiVToIM3aP5y/Bp3kfQcH5PxfyKGCmz7e5KcoFhY7fDi6rhvs8nf48o6BEDe/2P9jNcDa/n0XbLR0r36Oe4sKoxhp5jGVc8wO6Tp'
    'b2wOTH6FDz6+6Ge6aUgieb6jeus4iTxnWDaKQ7A7MeD97sbNTvYdwidsEFobQnvSRtJADvdt4fd29lsMkO7LeNfdBlKK8V0h5XJ7'
    '7UH9XyfTZY9Ig1/eE0s9Sp3UwEmeiILiPbDq9+PxcE7z2cDD4EfAgPgThIof4gOI7DvMOm8/TVs0K6pz8BNdHHwiBi6UZ9MdoppA'
    '/9DFIG8i8MUCHRLo9wEJY/8x5p8c+0PMsOaOCkjq1M3joLvhd0gwcUgqlbZiiDRzP/yQHWUptqYEebNEeIJCIafSJygXp70oTEed'
    'LUc4clKOPJFy5OlFOToF2XLEwkfK0aDvWI48ZWBcRQCH0Y/1dWSYWoag5YkgqhCcQQUHYm4C2oMiVi6wFRcIdViA2dAJjSQzdtJN'
    '8wMCIhBSOmOlXIMwD0D1sSFiXqBV2xcikVIGNlakANoFRoLErifJqX1KJww5EueE/saC8XtkePxD5BIWOlbnYUtAkUHIIdfwKsEH'
    'Azpyc9TBFUTLGeE3iFiMjQUKSDTAWGgvlAOX976e8CR+LHnrWukGTTc0oFF0Gyu4cGv+nG4dSozu8M5X+iFDohJeO4EkWgHwuChO'
    'HVHwM801lWEZIl2lpKKBQpieLx4LCANHguyQYN3e3iNNKx5zH9Nabi3s9DNUqWKN5f/2ly/MB0n5sPn6q/jbX8tGCbUPeZUgRNQG'
    '5GmRLwf9goQU2aNXVBdGVijE5mWa2UA5l/Y1D+VIXTHmfkPsDJg8mAwo8jcQsuHpezuD0e1XaBzqh1mN9E+Z1tAc+Tn3tma7REl5'
    'IZtZjdkl0iEtkTWT1koEMAhPEBAWAScxTgUugAqisD5Q97lA5FH6cincxXUm3AN26me6JJAp7kmSKZZSYRmgLHkpkHbIY44WhoW0'
    'S0QcITNARBLIdJNsPyYawi8wd/+SvJRM3d6Gu6+0qd9uMw91IkogNX5Oqv6crTp+SLidW1G7RHSb0JEUxt4AYpyHoB2a+3MuSczW'
    'lNrsSNuojcASmVSSlul2sjJ4/Tft79pxEI8jNMSp8edsO3Gs8mwjSdKrFr4xFLTRko2VPqvkFzeNqVhuvq+EuxKI57aWZr/LfQBG'
    'WczA+pf3rmGalFydCRUzTQMGSWgTQNT7rzesDZWgkEOpBBF3cFDkKVthSjdhExBCSOK4v6wIQ7yTevCBVIMPL+bG2uLgyv/tdgP1'
    '38t5197+G95D/W9bY/NvJ33tFpIbqb8oH66AI4rlz1+LKYYg1ZRw78cTha8n4CeZzPsO3wvphlNJ06hugnK4LeIq7nKnj2kVd7nd'
    'x1v5GIJp11OV8hfyGUMCfC3QWid0edJ0Wuy3t3BE7d4vtjjZaiQdK4szJElZ5EFE/M8ZNsJGVkfP4rd468YoEpAfUGTMEu9LbCCu'
    'BX9oQUIEYBd/xbo/UWMLsibkQv3EDmVF2AEUUKkOSEEs8cEEamUmWVBhgyLu1kG6TMATtVEKsjbuJ6IPimViPQCpmDaSB4xDVbex'
    'IgTop2UEKK/dhLMX5sYcSBk7QiOJqopY75wgLL0kGHaGUlCOIE/G+YpUBPoLbS4urPY1nlBSG8owLlkO2r9P8JZQu0/0C5k+92uC'
    '7m/4HRck+YpEBRsr7ZQg72Iv0ipTfXaCFWNU+CmnETfDHF3mT7m1ryuHTzFU5Wh1iqZBdTdwS2WUb429FMB05m0iRKSNZ0h3Fi1T'
    'zdWNT6VaBoUAQRCS1Uwl5de0l+AnSznnP7CE8c+CY9wTFI4p6oM2ijn2LSj+miGQ/yRlbALc6XY63JifN8yG+S1mAxgoWozK+P/T'
    'fMf3JuU5yLhNolz4+iIldMg7/URWBtO+zYlQ48fnhJ0wS3HCS34iTi75umsqqp4v/z0olreAzHPvCyXIZeUBToBS6XmYX5YD/Ims'
    'B22HjP3F+mC3Psbdg9VyPpL+kVXPijtU/kOOw7xxHL8mSxSn3YRAzEw7j7no08uPBDum9JVkw5TEwkDzvl5xAMn2C/j8U9h8A75k'
    'Bl6C742xpaJsugAALHHKyxWIZd5/bAU4JrMCsfhEgQ7n4ZU8nU4S3U2x0JwOF7lFFAFiEZqF4dEpKeLzdxSpJOJ3gsZu5qCglDwT'
    'FEitP3EuaiQKSvj79utLs1FQyr6ni5hmpuakgGC9G61U0JmNMIq3l4zRKS5MTU8guhNRFXmU1Ar1Ho1J+OtsNlmeJShhIQRI+pTL'
    'mK7iWm8GrKCUPL/qd6xzzOoiiJ7upspBe7GhxV4KpRTVJYoVhbBL1Iz1Enmn2VMlzMHQgrQ2KAgAA1xWiFLHG+QOmCYpZgRjxyH0'
    '5pskILERE/9KIOwfgfCmOB6l0Bd0OK2T4Obfq/ObgsStP8Rf5x8o+/lNWezYzWz5Yg5ol5Da+WE+r9zl1tQ2qMSiwc8/55QSIuAP'
    'ufz6lrbGtEJGXwMTMdzkbaSBsQ4x7WLCAhSw67lBRthL9ijRF8Ya6PTISU6hNaOHCLERAL4kjgDEqG/ErkPf0EXToz2J1xBswNRx'
    'KJ4O2AbpZKCROyss5SGBgLeO0iCZuHzhCwNbQMuMVtPdcEdHS8zlKPV/+oOB//p26FqxCKNOFZkv1MNBtA5h/Qjh+zXGl8gtfs6R'
    'TXDjtgzasAECOR7RoowrvBeLhSyRVpE64z7IQ64vxlegxZjdjYJdXsWVTFcCkrEn8S6zt0/GZoNzlQLGbcAEUyrrIK8AbMDHf8nl'
    'udyPNHnUvlWpgWARJ8K8ZrJAMQ0V5Z9uBmoissUalbRJipINO7++u6Fn+HpEAASo6StqkEMr2H/87/9n7EFBHd6pVxH9hn6k1GwH'
    'pCk+OuOjQQjPmV0A1lTUN9GTRYVSZr+iFFqGn38zRjtg5OBH0cqxXKUcja0SOn4JaFOIKjVkP26p0K5/v6VqjUT/ATV1gTYi4cOx'
    'hTfChj38Oz3SRggcjIZ6xAGhe5VpsjM24d8pHfyP/+3/hZxv8yR13HyuDpl26ch+vnUoHyLlDMmE3lPpyVDREpL4ugSuD/Jr1q88'
    'NkO6IJN+Qp+7UDnExiGqKUwyBJFPBBxipQNyms4u1v+ZuqtDl375G/qbEcPa53eG+i6n+IbygTqRfH6HxOPdT3/DpSQnCd/9xfjw'
    '11+x7G/vyj/9rQxlf/rl03evnAeovp0YkX9Aiyp0BZ8zOdCWR3GkGqKmLXWKUwEwQr1u6viWf594wJW2evgI/CSMI/+e026zS9TE'
    'DeLwRukWwcMM4Tc2AXEezG1O6FqFrPiZOAHm3Av67xFOhOZn0/xsleYXk/xsLc7PUs6F5oprFdJcFZqrhpsK1vJxhzpjFd1yAuqg'
    '9C6g6PMd6TKRHYl3J0GtxGmSmupj951YnXtT+yS+6qXY80p90nU3dvmh39KErD4fe9BFFETlgBe+Qp++6Sv0VkYllCuRI6iC5A2q'
    'TSr+knxD/jv/jVTYqkxGnPoHJdgBSJCp9Ep0UpiQzg7iazoWIm3aFLlmhNFYX4CUToNp0ommABUDRNwHhjEXLw/q2fHIHZnRhPLF'
    '5AFBjWrJYVcSQ3iEqoKTTY9ZonifXZdPb9flPzO3n9O5/ZYgtYYaafWE/t8R2pDSxw/x4zoz07fOfEE24mtWyHjzDVYJ5GKtkAgn'
    'f9rt7zNLHVfwpyPBZcdx2LT3cT9jcj4Avide8G8R9jUBivVrwh4LCOq3h/nyw8sx3jgh6r+aGOAd4rMCK4hO2qfX7GaG2SxQWLJj'
    'b27knDKmkMxa/QGvRnkh+/cH/oesHF2foxEYayLjfYPvJFzs9/FWQT2P/Zqj3BjniW4iuiDrmmHUCkm3M8WRbSvELouUiUu3MJnQ'
    'RzytThxyFOLdQOgay+Wc9yp+gc1EdHC4zW7zmn87seguSdfjm7NLKrvHFsj8ptIukoWERQbWJmWfQsXm0CgBG8UvodWmdCaPZ9wv'
    'CZ9UznEZgRa49Ne8FmbOvr/hxShQzakZLRlAgJ5I6m1eLHT9xzRcNirXZmYldgfB/UcmKCEDGV8nbMPXgRVCD7HYc04z/BhrYc0x'
    'GLmOQcgROtSB8GtTgEVRVdMQs2XWJQhRNY7SCZ578rEy81LIzHhwgo30jRl3XwForOujYh3RKib21eyS3fQTW4rsk/K/s2jubdFc'
    'XLQP2SwuybLFLC7JsoUsmZXMZCWPAfC4SiFmclUHOOtC4SYSry+TE0XgN248M3gFG8+8r1POZH0Zxlae/6R8RxiICQUGPElKHS1J'
    'FgQDU7kg3YnvhyAKiFJujp6IKPZ/wOMiObLu7ylXSHxrtbiCPOGv0CsM2iBJRJxTyJFVn/jkazSMr7LdIpPy6bVPXQZyAxTpcJnM'
    'C3WXTlhMUjExVVHxn8hAMDIq7qKuINHh3FQVP6cT9jGZ83QqURuUTqaLOj39jIJDRk65aXJJYy62FuO8A+kCzCzBo3FJoh6Lv6TT'
    'fyDIkJJMXAOcOboL6Tizg6eThVwqMZejExedYVwjJBqxQZOYxomZIkHqGVwLSO6qk5GRHgPOvfWezFUyEyWota6ou3z+cJczYpHw'
    'kNoRjU/oS5KVZWnV94D7oaSq0y2aoeJuhorjBiW5kCTSDpRoDyz95RwldKjwsusUan/7jvpLBA4eDksRHsCMvtkgNjrqsQsJOoMm'
    '5BWmxjfQxH8y7KwDJ2FgYClufHPiIJ2ZQKzuJf4hQEd0NnniG4ZOYAlbhJ47KhU2bgCY6guB9GqJcS7/lpsBphU+fqJ85APhBcKU'
    'W3iP9z+c71ImkjCJaNuMfSyJypHQPmKOJaeCt5Gp+GT8Lysi92LQZugc5JFbZxIRkGpdsG7Kwd7BEONPCWebMKzke4E6UJOPCW9D'
    'oiITzpW2g97cEQDDJeviCYKtTh2BEZpxpj/hoREavJo05cc8tK9/oAxxgnCwdmUd3zVxWxqKRmGSUeCCWf4+u1Apb3ZjlFIuDdaQ'
    'zaiwk0o4rASX9OdcnlT+EyThM2BVrgD0m6aSl485oqMmEsXNvKL7LxG7AgCXX0MJQOs/olieZbczWr+fU7kTPVsSqRCry7MCrEil'
    'QOXDjBWcfAThslLAqtlEcHxZBkVIkiLd5WqxbSB2sgsSOkirW5cgJWY1XOeUZ0tYCbW0U3DNENXNKfUAyNojQCYmrhdpOlGIw4cK'
    '+ZBhS5EyQSUf49mmBTHp1sYrmzz2IX8TromBH7XWxOCf7VrWBJ8pxBAtOjHmZ6R0YqHEHlDzPlZI7fuZGtEXCOamjP0LshaJHPE7'
    'VGFlAlwdwKPE3eFj7vvvE2+Iu8RVH3sDQKEEOhlnQDXnIeyEjy/hAGGTriEsYQnXMDi9yhK7uJBcXAlWlosNGbj+8bSh7ph4PEB+'
    'Mffx5Uq7Z1jpQwwe3yggvClwIQWoZv/m/UoUMa/4NTy7FmNRnCtUxwCtIQqCX/76ay9xCYEZj5/IpL//Db9tTr/lyG/wG3Txr7/i'
    '6cLffvmUtWXNcXv1Src15UQEnSQFQYPjMYXYkH7EvGTteiWce5KCB3C+vEDZaAGhiCGz7LElJpc6b3wfeyX9nPvyFRrAQlNUH8XJ'
    'UBy9lbCP2Vp2L7dZj24ztsTVska0U+ydEMS6X2gka7Cjn5DDMBGrkEmNZ590gQA6MaUlnogfKWkhyuUTPf5l7IiW+buMT8pNLY0j'
    '/YavB6m3//5rrpyxqCVOI7HDCPAJpInMKBPXlB9zAX7dfevrLv56M1VuFUSeUNcPP7yejFoyoFi/jDUaSM2xTPFl7h9h0pOxp/1S'
    'dcPMp0MIcbPC/zdAgnH2St/YCghKFaJf6tFtA3sth62rO5qGO4NLJvVWH/qmxvV9n9ZXuPUHewEdYAWmELMAY5wb4HHJ0QMVGPL0'
    '1BK9/SmIzzsScQpVsgh0ecsJwpjzoqeHAuQNFTMGX+KLgiiSUG3aEJoE6YmPmGUCtsQwY54yuWmKqnxJG0bGBaIPOCbrGRoLDDea'
    '3IcBAt247P4AoGHqQBS+u1kePtAUmNBkTQtEkIHN8yGHO6ZAPn+8Qe+Lqr85129SE1ewl/4LY1xKMuYxyEVRkP+VIsSPSeG7nEbQ'
    'C6w62UJojSc81mccJHSSdv1DbgwffIccosyPUYAEZPMj+UKy/xiDCe0/SYp5Q1KIOG29ho4b5AKCoKoBWjWRMj1g57FsoVAoZFyY'
    'pso2iF2K/xLis0EXO/a2CoyQQgX6N6PHhBGiEZ3ylvQ4WLLypVTHeckFqmJmrgJIOXEKhfScT7hDHYsXKX4YgyvVQhBXPeAZ18Z2'
    'm94+FuTwYGichP28wRDp9WfyEytaqE8wTbq5CSBxDG98DE4ay959A9sypWqFbF1cKiR7ivYSI4UxUmaFt0RLBN7kr7+Gv0eT1B1A'
    'FR7Fxy4SFB3GhwRC4mN3W8M3WPv9X97DqoYJ0oZn7NhvhVTJQYYbA/lPcQupUxu2S01/5LRscoZ2jTbsX4rQ40zhDy8K//bLn/Xs'
    'z8q/6fLL+ZgT/Ij9A6E9gsXKB5F1l1OpriPCa1VUJCBMqh3DtYMVpYXSRtlCwpFml4kBruhTFlhaaXMvcc3LtRUFQhXvsESTUJoX'
    'ZWAjqt8syZQEoZDFPdlixE6QK35OKi2S/nyKicGf4386WzfiguLCCzpE2FxKhlgRICOnI0f9zWoKt9M6L6p4jfhe0sQT5UY4KL17'
    '8WFHPvDCC1/uw++g9d3FdcI8oimKx/tEWjrF+y1/2aVpBF3eGBTa3wOAN0v02G/6dvhmxw6Fmxkm65L+IU/o8ovVKLxSvJJzY734'
    'CDf8AF5HfuBEMTxyBvhrbZfEKxw+Xqh7ePEPOQ5K0sLdx7efKHNOwCZeKoK3CCS2yN9l0sLb3pMJ/S3W/DYBwWoXctkW4T/pVSnA'
    'FLvGGY9Ykp1M/VYTizhe3fUSZSNiK5RgQm0Q0dFQR1mF5LBGRhuSsrghOTdNWNsMqx+7MnxF6SZMTdJvkEmC4HJ/+0yqeGW1chVf'
    'SfiZUuACPcq//zt1w0yNOrH/buKSlylNpgJKYy1x6XKuWC5kPKBTGZ/U8jP9KSK7DH9J+Y/kJ+v2jAOCjhPHENp2+OlmbErdURNW'
    'JOOHkfFOziVls7XHJg/CNaWonWovSKOkfOaoVHyKk/QTDRWJF/BtST9SuyQQ2/RkbuJTkm3lQ2IPy/TCeNv2jbwaBVTlffhwK/Vi'
    'kC8yfsplXKzjL0Y6Db9lPMPfTtRvt62JbiupolwP1OSKm+DmFfHlh7/99O4rekWoMZ19/8N7kCB/UCz3E3q6/Y28mSF5+Ym8bOnL'
    'O/KCVx1/ep/77Yv6tZAqhP0tKmTIIZ2fUpkIT0MCXAV62w7RjzMeF7oQAi5OTWVfjrmfYBrFuxx5qOV+yHGCgG/k4Svxi8kcGT1j'
    'XXfIHoTkdozslkLjBPQFc0Ar6/gtzgf7DMWeVEdNqZTyxfhKtEz4+yGHr0TXlLVQ/IK1/PXXTZ4p/HaHv2z8yxV+K/wSI5d74NHw'
    'ZDvyRyaAWXq/AYod1BWEKCKAGG2N40sXEYAe3dyg6pCoFFFBgdfL6WYpsYLGGRV6F2QuTEQMvGKBMKs4+ehhTx7WuYzFipY87XTd'
    'xMtfcsNu77F1R1WD5Cw71EFsVliEspq3coT/TW4TCEJoTQlgw5BbAmM9O5G4MopK6sxvRZp2yRpcYR9pRLMHTWfXzCSugEcCjcdc'
    '+TMuegGRHVNiKkxFAJQDyTmWK0kow+QhUxG/YS5Ipg8oHpQqGb0BEXETgMxQ4C+wPlu8zOhrBlSoasCwX9BqM6Waa5AUgGtiOY5j'
    'K1WmBuDhkz4IvMjzHP6FpG3cLbZSESSJkyBpjXKj9aoejmUlhq9INS6tR6wxoiQJFYFN62GZKi+JkiCKST3Bq3qYWo1nuIrISmk9'
    'XI2tspBcFdN6RE6SqrUqwwi0nuwIUdeE/YFJrsCk4yBMUqgq8SJbrdawjAWbAu8UrjBVjqmIOHggvffoH1CSqlVJqlUk0m8TFbul'
    'ClcTJI5jaFGsrCIwgsRXGUmiRR9IqwwnSFAnX2Vvrda4apWtiiKXNltjamJVqJJJiM+1JFijd5dlne6h3sRkSE2JD9DJwtdP3+Wy'
    'WtsvPRBwHuH/FovrD1BCLI1fesB7PML/LS5JXhcSHYiGkNRCQbTFfqJv37JYarusyRLeMkz2DgvlH1k8MAgjB4huISg/cpkEVFzC'
    'nyK2gOjnjixPjyUsLbbeI+w8oL1HSH8k6Y+Y/kjT09uetj7Im3gI9eaIRqw4wLrsyI2TtE+4go+JfIBd3uEAHrKpOCxIzewqoj0k'
    'iwXAyfNV+IeS4T2FPlaowYIKVQSkB7IneQr+UOYDgWlBEFm+ItRIGQJXIl8TKmyVq2XLBLcyTE2q1CBDVYjLALMtsZWaIFQyRT69'
    'ZqoqJaYqVissAFMCm3yJZwC+WEFi+RQ4OZ6BXQa7laPA+QGqF2sVvgYAL8aQyZVERoJhVRiWTSGTr7A8K8EsCHFBskdYSQSI5eMW'
    'AaRho7M1EbBG3CILSVV8Z7Cq4Cv1ykf0c3xFl2BDJuuATp/s3QtJ7xgjSLxkDRDSzzF6/DGHx2cJTiTPMDd5FllgkPnodAKyjPUd'
    '8UaiUjSyFWkvjqXQie+bAEJdAhF1gsfY87BB3jPAWZbwmvf8+/eFF+psSrBi4ny7zSFBuG/wLW0KOycIGRizzlnhLC6MaNRO06Hx'
    'WzqBSShUhBwFKkVoqJ6w0NPAspNdvKNK3EAh1ioNj1RoKE+xqa/COiDOIiYRnF9IrJpWIOWxayAR+mjTym+pu285h1//hRgJ4u9b'
    '/I5GK59+JqonIFw+uj6kSRliFXDIqEHPfqT9AbAUYhxg4icEQkD4sAU+5MxXhjDk8b4xCC4eBcAYTAg9O/3jq4wgCf4LkTa5Ankg'
    'JeiGJeXVRPBLKCfA4Bb+XxPc+eWLeod3sTEgv3yBXzV+ZMjjOX7ED3EGJn5UyeP569cveYo9N6bj+PkdmUXUaIjk6esbGM124Jtb'
    '5vc3CwAHmQwEtf8McANCbVB/D3LPMOqPY0dE4oZmOYBZibXWIP48qaPiXewnpOVij5/fd6YqIXtH7xsgfJqmu4ShIpcUxFcLaQbG'
    'H1H1xA0ZQIXW//GlqRq1fInTcRRSL8ggtlDH8Q6wpU0ai+IVt4mKalICJmSnp4VKNJLHXerfQi+nIipPhRQ27DDjIq1YZEDJvCQc'
    '5SU5EWgpIbBn1EWdpFu6HpaIUX7gnFBhjnFTdOrPicIquaosuV4QJjKA0ev5AnW9TYpR11tsdKJ79EBAakwny4MHYAgHG9mGF+k5'
    'RfWdIL2uO649nnH05kY/+cha24qBbgOOU8h4c0Cb05eGu03GX/aF/2BySB7TbgcL4UPc8S+kMseNDewJ0vl+g0aVTcnHPQs/DL29'
    'JvEvjO3mWReqb0B+PsMiUfesTUk9o+npQp8vhbh2olzKtFYoJBtgmjo5JC4iVPJIbhGNfRhsXDe8w4UwHLA78GJKcl9tfPQKb+OD'
    'DbSL1qVXE0nGfvPC/N4IWtE6n/FaK/yJo+XNC24H9SVOnTfNRbJcaamX9uD0FoOYhMUJSMZubpyGfRjab4Xcb5G3tBlA5NKNOxdq'
    '1Rt7zyLftEb9gUhM639hgeNm18Sa+5cN+ff+U+y8Hl+jn0pkLjUyWLAx1Xwhp2iKGwYpbkowQJ7e2Kf4H9Ym3sjxzgds9S75Sm/5'
    'o7e9Gza57T1nOZqeHvqYtur9enJVF8mHbhXrbaZ/KOm6eINsJgWmCd85DRiT2ntyeyZ5F0ReX7+nt1pigrbWq6QALhle41hiOXoG'
    'Dr+Ka+AImfgsnfqR6ipUvGUIT+7m8QkFEKIQR40AJID4ADNbItJZeHfrErpi67obl8qWILkY8u99gR7Gw2m4DZOtsAJbyw6T3YAM'
    'WL0NU6/ogi7dhinqSm2jZ4bJ6rwi6tlhVoTbMJWaslkrr4dJYPOGKRA41I3G6wwCx59Mgoj0vMQmcxAD1Z/MQTJTOAfxnaGK604R'
    'wrJHQZKH+DBICe9iCABxhzQj6spx/sh5S/oAYySQQy8ifqS2UZ8YCrO3zyLlopQFb9dT/NTl8ZRc6gqv5DOedCX3yKZn2DK2xxyy'
    'XjC07e8ZorffsAzktxnXBxb5tGohcd9AhIqGdsJUbksGqus5jlRE1fBkWC3AgUAwc3m8mLZAsGAUEgtvZnyKGqK2OB7mHdW14FW6'
    'sW2a3FxLDQ23uBZYe97Wt9ST+HNsOC7E5JhonNHQrZ8V9AZOCSr0gFA2yHLV/axbdtz8k4GntghzdsmSMPT1xXtsqZMdwMw5e74N'
    'qQe9RAYPst7SLyT9klrdtt82niRu2xmKBPWXMX9i54B6yXti48hasOhanHAddoWXjKn/2ga9hbo8coqJehsnVhVA1R52XaP+yInR'
    '3H9NSGnvUjrqIfNayBBW74IJN+MbdO1FZu9SIMa5D1g1dbuP1oaae/jv/9/VgB0Q35+sBLkv5H6wO6Ia9x0Tzz8kjwBywAd+TQA9'
    '6xqX7OE8uYpYKZ2J/pKQdwW9r8nmv+CXC/1yIV8u5AuxNt60cvr1PsyPXqnkUI1K3KNGX5CnH31hv94RcWR9+8CSD1z8Qb194MgH'
    'nnzIzCz5Sv4kQ7ijaWsiMOBr+FKgJOaIB/36X9u9m5vqq87pSdKtg1aShB7Pr8b35QvtDVQAXy2UdCySS6Xtff16U80H0RrGhcuJ'
    'Q0ObKsXi6YhfDJ0p0AESDhBRVohMWkhZtuQR/SmhfeonrSq2fRNaYofpYyI+IENEHpyTglFnQnIo4y7GH5uE2YsvUvkJFdZ5En/N'
    '1zeAPbSsxzRBNChLQUc39GoHvNLhJv5jvJu4wdRwlZhXWHJk93OuUovP6mYVtWk3i3gTFHKl8IIQbMCwoURq/NzkM0BcIP29Wa+I'
    '9ctBQwT0A+/iJqao5AKCpDMHKi4ccIKhLwfSl0QfQa7oyEMlRShOUc/rdi3ipk5bJk1AQmxqJo2T18ToFcPLzshe+BNPU/jKoBM6'
    'qXEBeQYkJL6aquMxuB6VAzFgkHPCi+GBQBAZCyjmL5D0S+6//x/0InVqxcoHxtbGu+oOsW8wISgZfOCcyA3w8T6A1xfO3IhUU0QT'
    'E4IUveB+TpU0CYbHTIX4aJdDDlHHqsWtnSe1//gKiSJJiT+YGHygwjFZ7VByAXueor014jvqQESoB/bgR2yIIMA8xYBrRH0U1xOS'
    'k2aiquFkAyt3KQoAIOYgI5/BUZmk9dcXq4Ikn95ObxoHPSORJ9dSKHZu8oHuQCK7x5FDyG3Yvk9sQbedSjQF6XEhwgIEKMcTITmg'
    'onBycgl9hVDYim/WtnPkBguMmpScLUqFL+INZyASA6BPUu8SUQKbuUXOovdCU+/OUq6Np0wUg9zcTP3aAZw1KgdmekOvIYhRyi00'
    'JeXzyOhAKCTqBzoccrcyXrFI7EsJv3Sbtxd3NtGbFahLVCk33MQ3jDtBfCcj9mqSidCYtWjdEVkH0SEKQzo9DII9yxNL1m2hgNMt'
    'xDPpq3iAgLCfm8gnVRKVR/wMfNRdetT7uzikQHpZlR/ZGExgZ8Qd2+inmy4liGNZ3hY8/kw7HkMMvTAo8UEgplvKDf6CTdq/FDLh'
    'suLOwydf14NfkHIFrq4a5PwAmaPUHfEWjBN7j4ouLOecbCxF0D+5jhLdAiJTI37IFKZvcWQS2P7/uXvX5TaSLE3wv54ipM4xIpIg'
    'EqAupSJF0ZSqzMqcUirVJfXk9nJpwwAQJEIEEBAiKBKtpln/nN9r8wz7e55hHqWfZP37zvFbRICSsqtm1jatSkREeLh7+OX4uX5n'
    'kPzAlHrn2kRByC0HgwG+jyDbuQyerEeUwiRgrGjZPMvqM9ycKQ8to4KRhXh6kMyy+bmZS66txuyZ5QwPOIjsCQJjCHMRBsSFdExU'
    'Pf2E2l8jiQtRAxWXJwG5B4nrYqmy+jCkFCRCixvHZ93Gt8Zya3waOuguNqy7zZR11U0Ca2pa+LrH0S2hQu57mZsD2T96q35iI3fo'
    'JHNJqizBp0H6BViXAP/6px9+fPFPr969JUpVPxFPwag0F1Z8s8mOsX8r7d9KP97eX+r9pdyHA20oQATD/Dy6bUdIPXxt3CZpLsiH'
    'IUqgDJlz5KCmlcRJErCaVQv7uFkq2wiS95o0leEbTVVNk7ETi8wzGwJjfffNLZwRJfNwuK5D5Nhzkgqd4J70rWlKpvLKTiZ+bTRV'
    'xTC5PfWMDWt9jriTwGGHgvMJQutGp4HbjAAZQqY5TnwDyL+Gc7REAsVGWw8VPqHdmegtWzaNrK90NIksq5IboGpGc23BYzo5McMt'
    'mVJ7DZYDkpasYHq4wKqAcIETpxjtqP9+VH80XlecbzO3jHUNHnx0D5YNTLbrcCo/cnFeNRfnRy7Oq4FFbNPPl8k4Udpz1U8Mz3lt'
    'vuFqAG5jN/mIvxANohL3UeSheRwXS1veWhmJ8MlwYITD4eApFsAd7YLcmYoftSput69FH3f3oQE4MBbPZ9MNoGzsyZ/h4CF/P8TP'
    'x/z5mJ3kz6cIxhnRvDpq9XrrUgAb2FgMT6zQHbCJo+GpJREvQhYIKBJm6+vJs1RriKUV7shZgipYrqfQtEZgtjSdQpJPLyyvJa0Y'
    'mtMb6h347JgDPxC3yGQpp6T05o0cXnDKAt8xBHEyEp9LusF95ylR/QMhHekLpkDa1KWYbhLYr3Gf0OJokoasjhcFhHzrq0Gw95xW'
    'JpFLTZ+ogkib9BBNhHLfBxQIVUt88wNIyocBDQyiy8BQ7bFGvhPqHvpU4rgbGKXjyJBRi/V6P9LNjXB/V+5Hji2UUz5YDAGVUz54'
    'eIHpXVJKLixCWN8S9XV9oWk9d1/ZWWDPFjCreLOlFhZAVdtq6WvnsQOW87jzS5hztPMRjY5svVO4Ry/R3ykibpYbCcfET/EJurWG'
    '8jGWqU0LVU0QcX3kcig1US/fQF9V1aeSaIWbOvQ7pQciCvhDjYs7xZPdo2iGZe1h9peAGRSHkX3u78dDa8tbSAA4zn6GTDwc/s//'
    'QUHObU/bCvfC3e2sVEkXtROD4ECWfyjAYk8YbGLqeyajEqks7EKJljUUFU/200jboIclx4sMmq+hxW6U1hzonWXdfMrSKnEsPQs0'
    'nCN2Mii1YamNlJpFpcKFVob79RlYjk86dBz7Boqs/WsmRDTRllpK/EvmJELRKC3LcWlWXZVrtsy+prghFtIgcAUOe7SKe/QE67uh'
    'vo6eN7FsbASIYX57HxjNyxqu5QraZfm+J3ZpxUQ8Wzp57BJIRpSY6Odc6QI0svK/SOy1Yhsq9CWUPmwaTDMbG7rG9tmY+w9Gf6Wj'
    'DdkXxxDxe+NelXwkQMghVLRflTJxsmmryaHdzW+8u79SBzxwWowPV8g4qqwy8gxtk9uY90v4Z7IiFsFkfDW5zCUlEYGeL9bFND3g'
    'Oy+Wm96qrlJ6BIiuw8uJGJ912hIXP9AHoIBIlzCYjklOzzW5kU9n4KuHwwUDl0dPIovGmto7oGn9kq2QyQ2wd+Z8K/rJex5shQR/'
    'D4fgv9436NsHfmMdiIfQFJoqQscVbMXv2Ly1Edj7G3s/PUx66ApQ05DCx6xEXla4NNzYaapPUmGJPmh4hrWZyCg1juFiaA8CaU9p'
    'Ap2OtDfFqKPIblTkfbuWTaOW96OOImEtHUSzGKputxiFOIx4/N48fm8ev8fj9+bx+wZMI1eWHy4z2pwtDpsZqpgQ1vzoD0II1xH1'
    'q/klSiDWzgLlsfT1hqY3TFyYSO/HQEdmdTFWmWMTXEBHNEgdxylRI7Jb1IvGUkGnplMOFPzkAYVX5RItcyhvWzWLNR2KQHtPMmQi'
    '6AAQQNT6SvLLTH29y2VusSVItdZQzglpocStrKZkNCEYhCj43YcSf4LsLTva1wRweeDZg3qo3nLs9NqH3dKTyWlEqeUKvKSguNaQ'
    '3KymGtBwL4bLzBURUR2HEqp7qIQzn34FVyp1M6eCI5lQ29TLovnJ6dfjPyXUaHvp4k0kS4QKjP8NDDddfKRhxI84hkXX5JvAO3Al'
    'yhrhBsUK8tUaCijSUKjLNqvW8chvKNZgxMI/dQaSVQK9wSks2oY9NtN3ugdcpYFe4bahM2AiLTuKx/Kh1F6lVjPR0CjVY77wA8UD'
    'KY70Z654pGhSkdCa590S0vy16gGTuQAKt6B0+5rZl7x9WLlIHSTYMQPHJy+nsSs4rHwkOTAyQszgjRt7owmLFRQfNosPTxUiq92K'
    '88weiyTl/Ld5HZhKANgQv1qLSq2mraaWGaszbcmqS1Rn56tFNbuJtrY58K7h4RPMzsfud/e2vrtn320r+PJkpkBbZ9NifeaD+S0u'
    'cp2c1WfOz8GSVS9EU2i3m6Zmgttg2ziz4FBtgr1w+xybxW92ECEwdpuPZpS0hsOuU08xiB8OrXAQWK0aFsSWmCcHmenmAKIarKic'
    'LNyAxLZImW3oWA2KZsWLodFy5eHejKuaFRz6uDrzcnM35vFuxABiM9ZWIb33UXfXHpRft8TJNc/ycE/yJWQMNx90xRLjGAgmEFxz'
    'WYA5Fd25LM08E1PdwxAwg5qkjmVuNea57WEuevuP/OxL9jUXdftHfvSl06Rr21dhybFV6dmS+Tgw2UeqckmxbBh80B0iDx0kLtON'
    'piW2meAYu3ngsryhYnH/8m+6lHKfe9UjRDOH2n/98cXLd7/+VXpjjvoDBlv3Nc0X0xkzoxwiAp74d6+WTIit/kqBL2NDsyDPqVeI'
    'lhdNqBwzWlyRJfRWAZMxJrJ9NScbEpbiACdUnTgWICvG9CCwQSp8uTWRbjOFBmf6am6eeE2hnOUWZ/tL1M+BqXcMtVRg6pVb3tQL'
    'kKVQKfnlZovQgbYxMErFljsOC9IM1LIxKIHZGBZj6wtHk3Hs3YGBEhOuHSsjmF9aW0kfzAYtk28j26SVcbUzPRWyzpY0IhYyU1XT'
    'top2cGZa26qyeQqsJj65saVO55dvH4ROcQKwXCHnec4kQWQXwWOW52qIvMgtkpB4vc+LxVhsfo5xXkvz4/ycyiG19QK8LrQgT65q'
    'VegyR7WKkqaRX8+9g4y2Qsc6M+Trfoznres3SEgkB5AVi88qQ83zdXWmACvWgMupoYNA5CPvIgCaqLSy3MwHAP1Y62Sk+B3Anv2v'
    'NMPdYU05alhTOvwjPrdpPNH/amNfX4f5KN52qMeF5HFybA6khkrSm3qplTw5wZs0SsDucT+6shdPw4v9qNzT6Gr/9DS2FSEVvcYR'
    'YNj4tYafz8TB3DRjqI18z8E2i3SQ80c2JnWglQgraVOvRblB14QAQv4jAfQJ58tX/xEccRpLEokO2fHxkdwItAvyBLEG6KfSLEnk'
    '5amWoOJa5wH0buzyfBlB3ZB+t6t1U8rmxv41671QzwZpwwaEMBbFulTI09oHLi+690XVszrmMOAv0PCMN29cjix7twvpG9VwNBUL'
    'F2Nt36VmxuVATE4Gg4F7dBE8Up0E8zU3FyJxUS8rrkL7crx4FEi9AHMs9OFI7ZyJebGZiyQ4mTOLtNunOwHxd510IUXGvsjYFWlb'
    'FDkSl4GC643DMY+oELuXkm3VscHXvQHON4FmqbZ6k7bUjIpIgCCGkv4nugyCQ3CV6FYoYXuS1Qi123HSeydBQ/OEArU5Iy9EP0g9'
    's1ln9Qz+QEFcTnMbdDk3r8S5+ZrisFWc7w8FlswryfcDvLQV4Tn+EvJKFryjMwvJUbL/qCECeMvAX8QysP8oPezS6RM/+XlCCaSh'
    'yOcsP09mgd2fmsI4a8lhFOJrum7mRQJ78fsf4Q07ufauxIIqFPu69CbeO2Wv4atintmSWxw6kxcdGVis5m9ExV/yvSvyvun4iXPs'
    'xUkB7+9TOb3M1an48H5/8l7vT+UqcJcwX+U/6dvEX05FdAJCkbk3oX9uZovI5ZhFWirCYCGrklCXcl6pEuGNQoW5tVyXjrlLwW15'
    'ZmuTROwWKdBx6Indov3B6r0ZhtGvoiCwGgMzozejMGi29XjTftvqG3Dgbtpv+8f2zJU90HHilpaYdmqkAiMWTTw8F1e0xUgMFlPX'
    'XXQnVYj36JPmFn0S1EvJ79rM4g3BCEsuUvjE3IzkGmLgzDzfDO31XgLsmM2o2Ta+FAfli/U62zBLXe+T+s8eJA8fgqfq/VeL+hxZ'
    '+x7up3epBfZ1QwiO/8XPy+/LGxgvuLz5F8Y581t7Lz925Qf727cfkn7VWhUUYFVvmR854i+9hDYBR12FrDHQk81IDgY3I6yewWAz'
    'MuT45bxYrXK63tHxk6w64PFMoyEVdt+WSSwwwn1ZT5+j3fAnnjT8iR3tsSuvHoqiph7ZpBTRMdtPPiintzflgYjqbhiLjOubkdSO'
    '673pxp6YGymw4epnc561w/yshIGzaRc+RPRBBrgFaOTDUT6YxbA6DCrj2/Uw3Gfw+19bRLJ6FO7QesRHDV/wIQ6WeqQT++uyQ6CM'
    '6A8152//y5816zhEL8/Q9axo2eUObH2BqaYX4UAchwlgeAah8gwP+tbW0GsKrtCZqrZVkyeExK9KB8kP4pFXVJDml0vxb9XsCnXp'
    'LBziLKyBwzNiWsc+zZELMqVRBolJavR1HntO07xhQ82oRfBDwoAqyHT6/oEyrozGhkioyXk8yKNlh5EfPouyMYApemW12WJw0OSi'
    'AmLch7dExMZ+koG0SRD1eLF+GOIroGhhV4UvNqMqZ0ciEJndzT+rJF8icmQesb1AKgM3AhXst5Em6YTmCqqdEMnyv80P6etFWdCJ'
    'NwG66WVKTlZG0TS4zTsWk8mgFrUKoQpuyOjtBkN8choCKJrV8kI+9hJl7efDxuvYzeNWSGKfL34fvYjhtq8tt70mKL986Th5CKTm'
    'oC9D5gpHh47vdtFaxQ5aplKiMozSGCiYZEk6+pkKlx0VjvoC8j5ygJwSrSSoNz6YfWfHppEMNlVdXgFnweYvNDsdm0qnGhA4EkQV'
    'RFAFeDs5EUqfkCUADONTZwF7OHjs7o7U7vBGrLah72CvLlY0z8JJ7y9poGub0+Fcz1ACwC5JZJhGBqEYpMfQZLG2PWEcpCEajtWQ'
    'YRqAprb22icjO/s0MWoaFjG8WB2Io3NNuheEkkyY0JqGUmmiqiUTgAO5Y/825ZWGoM7piONAvmQPwtHf0NXL/BrZId0uVLdmSCy1'
    'RHU1PQGLVSjW1JFjn7nhVsxf6OAXybBrMT8V3OJrMUwVKsdiCmybse0RuuseXxKrP/aLvfzLiRnab5OH5H1Zl5j/bZlNVGaTNuwf'
    'NhT3iJPvLUYnvBLDirbkTCtYKoFRhdbPzYFrzT1AuV3/GpaiJn/dXu/uF9a716j3tMuaJkdgFpjPsqQy5y4O7GXegK322wDLq74y'
    'i7Z56CW961lh15yLf5IwHUiYs3K1KiSUQ12C5uUK/OLU4kNXcwuC7ZsTxwq/1dBzomvf04TicwkBQotOUeA75ZcuH/567gyA9D7t'
    'WMDrHGVenkBNjVXRYN6BuyL8O38hVNH+hjdXF0gmHwa08qXSymDlq59Ofu4dO3HBlY/Xg+4e0AodOLTpItXQw5ey5zhivJAdMyCk'
    'Se9zfrnPDQl8HAgSYTyi3tPWnbZYvTcD8vtSgH1kvHEKkOin/gX1a4hfseXtqdOPUgeYZS6cx0uJ0y1WlqN4yRBbs97lufvwkcQN'
    'mAe2pHs0tHVLAqGVX1nvrwjrQSmGXKRbiMp20gfAqfpXJYP7vIyE3fi5cfnsMpBv9StBrx0ZFPjtx186rl/SHt+MWpQ77TY75gbD'
    'fvbLN59eUscAFEz+2twmL/Fz5G6OeBO/9t29fXfvobsHUhwCgsMY6oBQYSC1yBK0kZqtdYbT18zFHm4h7dPm6ME3n3CiPxzso3b8'
    '3B88un1wlhy06ynrens9YEuaNeyEjClWyE/CXbhTwurQzp6toJGcHj0w40OSji8kzb5NXumtu08P98Ldh8f26na/rLr4zLj9Px8Q'
    'zQnjOLl9oOMSX+1RKjh6MHI3MLIIITx6QAHvwXfPw1lkzvAPMiyTYm02fDK5QZVmGZpKJxv5vTG/13b+RoN9uvM/vQ36AwnmlpVb'
    'gEONhBbxzezQA6KrV17ey+o6Q04+70J13bWi3Eq4VqhuABlrK+ZhZeMfDctlGSpzaMLKrwKdwlrtmFbl/DPna2FB+ZVTFT2xE86O'
    'g1Xyzaep+1BY/MOBt7Jba/wxUrvJH2+jaZhkKzsLRtDLJkVthnfwEKPmFjA6Yg6tL2t+sqXt6nprw6Y6s49udRVoa9YvxO2bntA3'
    'S8NVKE5lo0KiMQOvZdJm171vSlTdW4HQsLR/a5VKMG2loKJXRfo141IbMbASw097aHwOhUcwLsDLPjX1fPPJiOi34upx9MBw7lW5'
    'PqCjZ762W6ZlK9G4cvBNihqnx1RmeJP51GUfdivdYbnpU+HRREIolzXz3hchNLkmJTVHsKS5a2cSJaQBvadfM1WgTSOqnRVEA3T2'
    '+6tirpnGVG2kCieoBq/LNfMul+tpscxqpEa8Ko4kr1WAgmzYAbOVb1ZAI1bc5DCUl3BvV0U/UaghB08UalDemfsCWnXCYmqEdvmW'
    'w0m3SVVxD+K2SwesVjFIATpE242HXk6HI5ZL5sTiASZdp6UdBdLOWu/IPCxJfAWsLMKI2p6S2OOrSYhVmKI3KHquRQFHJx6kUIB/'
    'MiT7QCKoJpsDCZ1aDw/aZsa1NzOuaVFYjxjMquw0UOUCxSeuI/Depa/E5YCNcrIQYBCgbrJk4DYjMGZUN9LX2kIgWrS/Q9FVZswR'
    '1lemD8LzA8Bnyf4OIbrDxHioo3JzR0EgZ56UkBUQ0EPDBsDdrVxaXV1LxOAhcqRFPOicQn0p5te7AXpFQK7S4d8TZMQCDfqczRZP'
    'B0nC3g0mFq0ujoBrzn1rgm0kxNk3n3B9+6/ffNKK8BO9EKZMPQ44JCfmldOm0EMS4R+jSjT0zSdFYtzdtRVpTJjhwasgGUEnDMtR'
    '8kRhWKQ4CXQlEBDnZhOB4PYIirgboxbSd+87hAN9x3XH46pc7fHL8JYbtibWn7yWpreWKuM/zjsbx7LK5n/2WJKorMBJYVfcPy3N'
    'Qjx6cFXl67fmDM5/Xf5TZQ4P4XoAu+jYHuAuWr5HOvncHK340Ntn38UN2a5EUtnZ1Xre+wcZYRl1otAHQXzww6xUMczgq3jt2qTF'
    'sa2fnhXbiJ0nS4G7RBfVmUYgYoNpRGbMwngl3uzn5eSqepdJZjiXqmig0GdVzz5PwwIhJGRHUeXdZmafc69L8IN5l12QMTGT2XPd'
    'OE52nl0EHNPo6YPnkk8Pjr9OiR+5WS37mgElwk6AFYHZbpd0ooKy2hKtfuIB5p643InA/IYu8iDZ7+ti+ySKvQM3PepqQv8QnH4z'
    'hKCdAXZvDx+D5YOnEFNu6akcfdh3F/ZbDuNMLwoIcXIaqj8tBE1gTtlpwKP0HMqJDw/RW+rRwdBnH4GikrMqb4h0EwSyuXgur0nP'
    '8xcNZx7ce1NXrruh5Y8eKOJeowPWcK/he91W3NFdVtyhpaXaurhamMmFzablQqMx3uxOyCoZSilfRIcZqnTgR6T3LuSecyCS2k8b'
    'cwVfqncwUB25YDftk9jlzSjL1lVfFNx4hRxW/viCJlBOQjz0zKEVSfoa4KRujTSAQfUOQYppcqGUcwoRQRheLm1eXeASE6dXk531'
    'fiMjyV1HYBe7F3P6iqKJfCLhlJIwwmLdsE23YS+CftYICLo2r0KrZdak7fgg9di7oADmi68KScYS0BZTOrnvwXjN5Sva2fyt1z1z'
    'ExlvPU/MGz45rR3CBy8FO1V6DExKDPWDvuITF+fnOfk13g78RpEu28HlWsal0Fy/PlO1WBc4eeIyaLhc+NKJOkpgih+8RL7w3Mh5'
    '3GFEUgZT/cLiugLaS/AzZ5iZazPMfoexdrEJ2uURLGQqV38dvzejO/iYza8MaQXPyq9Nm95oyJaOAA7J0B1uO+Er5gM2djyoy1fl'
    'db5+mVXKSmvKKlMKc8UfRlDwXTPV+QvLU7x58eqHd+9+ONHumbtVL3jFJun5T7ag3jiNtxMXRkGjhiyZYGXc8eGLXPKG+gUyH2gc'
    '1pGtyWzj8DF1zfah86GZ260ZMZJEd1Lb7ri8kaypkq50GbqcxfCcsU9+YBBlcjpCZc4EqfT2MMowh9yJ8ywAk1xl0zhx+7DvXREk'
    'pCITJ5x+MlbUNYHstC6HeClTN46g4J4vyER3KWf/220NbdjQzL4vyG2zjobEPyQouOcLSkOdJxs3kGhuwP0zWlmcDgVNLLehnmsb'
    'KQaXCdnMVVFr6m0k87FB2wwMD7axg/Di2bggASgQcCHGCppMNEASAWToFiif36DiAnDSMuGwDxcl0MNQM7BLGFGBDGMr9POMVpXq'
    'jJ2nr4Q5pJnizLTU+2STtWFR4OQDKb+qrrK5S2lqNg+JTgrAN/X8FycfI6HFNplL4QQUBU7eUhrI/hTADUI3q1lxTg8QaUVTZaq7'
    'tKsMDigWtbCnjh5VDfGsdBbMSwVmC1Ka0GplplSDR7UJZFk98A+cwUsw5WFbkYAFmSlux/iWjBPvCNdDKwEjDsygSSuMLVNUPobj'
    'I8Q3z/9FghiyC6hbasbjDoIozrL+kXS3Ry5PM1tXBNxqRKZFEBy4eFnyRojCsUVsQujZZRuXQmHPwCNeMteDJMre8/i6TA14KXvo'
    'W0Kq/CE05mqfa4dm4Zn9qEAHNguTSuTdBSNwFxZsQ0hKlBjdwyRGbBChnUQYLXu9oMx3AiBJ2BVfjd632uR4MbahOk6qQqeKnKZM'
    '2gDOSWaH9GJIqZMM/mcb9UYb2oQYRDbnz73g95DxBI/15577TQQlLcyfp22IkLX1g5F4/iUU+RmU++zeAEkQsxt3ec2TQYL2l5tG'
    'UZ4WrtzswN9XKEK5lr1wexilyBOj8JEYAEtGmw59iTBHITUscMqhNxxPVoJ2ce37r3NHVAQ8vbLqISIq2wOm3MRlrN6If2YWIToE'
    'TzG1PkseEvpkg1+pfMDu7qFH7WAZxUfZ8Gcq32ZKuepuG9Mxke0pB7nL2ToxfUxFy7NrD13krSn7UE8wzxHjS3nkf8lbT/HW46G+'
    'JoP/LXBpdnX4v00eBZ8cAGXJBnvMDCgoXgH14iGVJ65MdpOGr2QbSZjioHckVYgGa5yfOwc9HgWlGF4wEFUEWMOheeaIGFTNAUEj'
    'NJAld+s2wIzExGhxpr8QJJoQOFcGnRIaisbuIoJyErl5vC/HneLkndyvSygpHMJFKUmp6zCyT73JItfAhlt7i4EUl7YG4xiAJZGH'
    'HHcrWpxPoOEVDT9T52t4Vz9P4HHNzZVxFdurcaQftO6F3i/uNTOhve4BLcB6xzmZEyqDtFPxIQGG5jZ1+FSXzBkNbt9tyLxZKPEG'
    '98d6/zTtO6l3uy/1kY+xZt/s/AcHjJPkdeKyOreSG3yk1qEDCTOXCIKPF6mlTtamHaFl5g45K/kV43ZdVLnnbpiRpPJOYU61YvNw'
    'lGGGtr5tB598fYfMmSorRGhn3HE1DsI1d1WXXhbDcggkK70bC2jqAUNhhaDpam44TqAz1SvIxnHcoK0V2UmOzbpFu/IKfqL8u4F4'
    'ZdpM20bIt4LofBIomucTt9d67uMCvs9ns1w7t7sDuLSRn75OI57gBS0emYa/yNqmvpouzJGK2hxh2KHosk0i8wL8yGTcuPt9mv5d'
    '1NnUP7fU1ZI1cwJH+rHVUW/RUIMGZevfoaG+GaHkC9rlN/ob+umbffz+Xu7r702kq46b9J3i0rFaatOF9OwwnPAPoVTLGIDvecS/'
    'cDEA3/M4N91wUm48EFvzHamXywuJY5oSxveDrYy3FPnuxj4mHt6UToIjpsazXE7o0z8tCOHg9AcI8SRVFeHfXI79JSlZr0vBjbX4'
    'eR33uLNMcCyY3qRend1QYT9+8FyXoisRKLI9jf8aWj43XMn+4LFXVAuCAUJP1FM98KiOFdUoSbuLKKq9n/qBauu8Rg7UBkpU6/sA'
    'ogH13e0dnw4l9x2nxBN7SpgWhJ7zs1sHxRN4j8lHoQ+uSTAL9r25+9T55MAt5z7Xxm1orXznIwpofib+Ac35JTHH6SuyHQCBQmPA'
    'mLwJNdyWNUnTzxyLXR/s9dv2Y6n8uo0D+eIv1e9DHzAYlltXWAOnHKlsojsFkV5S30x5H5pgan4FRs+532lgHF5i7nKPe+yPq/s9'
    'WSS88cO0qN0yaWUop4GWOaTgPjZ6bGkR86kjZztI0pPhMPnm03l1u7oxf3/89fU7b5xUOZ0CHhjE0R/g/jYaSq5BQ2CEaonHq9Wf'
    'BBoPQJTTMSXnqY5YZqgONSsPZrohNmi0vU8Trx/OTPGwfVyHVnMzi3yBvbk7U7w/oQJcGKsBOgjk/foaPD9Sb8/EU66yitRvMYy7'
    'yVMv8t02RH8QRFVqNDUaczFZNbROcJKQVJQLDc6jHLfhDYnGC4Q2hgtsVjk87CUj1o71B9lJlTeZ9Bap8wrj+Ty1zmE2XXbtteow'
    'HRByLKvsSs0FI5jA9y7jvBpQTubq2SGw7hZ6nfpVfo877ESpyzP4Iukgelucf775hJ11nOzE1FtsdrfPnyESIKHxmAcwfuBU9n5g'
    '5mKWY13hagaD8o13RELqXhlg8UOy/nTvBuOLyMWvmwqTewPxNeti0uEItvWtfeaf3SePcs+Lon7p9mprdDt7hn0vn7gY+I9EclS8'
    'glXYKyR1Hj4BpfdABsEaifbxgeFDzadmy3oP4UxoxYwzJNNsbr7Z7Pq982xRzFkxt7verYp/4dcbUqB3rnUoDYnwo4VvN/xOXk3M'
    '5jIMD7rw/MznCDWdC8+gW69IsEQMrMAdNKxzvTVPKHw/d+6QG1Uda3DauJNQFiFuL1vAAYJfJdZ4hObgMpPL0Ona82f2Z9X7jDtA'
    'd9qwG2bCDFJvySYX1x6XT23S4KuXlmoxp2dB9GEuOmhWnCm9umbuPc8QXAzoySPxZURggvwg99x7h74qwVY6FJdQHJbUuDO5Y2+S'
    'WhWEm8awerjodNSOlGTitSOVXgzMn+NGZrl9MfWntsF3AyTkY8q+R4/jZl397wbMO9iodjR4Yisxt/IJd2pYGYUtjFEAENtOiRd8'
    'x07g17jTMVS2MT8S14bBI24gG2KDrgcP07BhWfrIhvguWwMMhH5MWPv+K/E01E2sb9oJ3cLn/BQ6CihyN1NPyTljPm2dURxLW6kA'
    'Ld6hkiW44uotddJZUps69Y46S+pMpxtHW3VB43oj1zO9thTjPCKuVZf/7q35h/289TTyAC5GnuDbbjiCOI1Iv+lGRPxNN1wX1zf/'
    'gd5EzjriS3okLofzzIwTsSovi+lLsLVqhrzHV+hkFB6BIn6KewrAIqsK3rTTHJ36YtefxuH41B2OgWuaO4mCpeV7E47pHuVrHVK5'
    'CEcUnNA+vWjkw4+hB0ZateZQ31WwcQSvbwS3oGdfEzjNrX7XPHNbs7T/oCNU4UnyyOsB6CoovTGDYVf9/XC3e8xu6rB0Pq2DDwMA'
    '5xYzjHw7cblA7ydM6RQkNPLRVsGmBCdrSceRJR4kEeOL5EAfgYBXIVcLeo4oJMtM2ZnTPd4bgQcf9u2BULGCfrQsHhueCQexfeVx'
    'P3l85wtmGaWHDQRtS6uH28av2THTp4eaP3an7xD7zN0z3xLnk3lfjeSrTXbU4z/PjVEg8ZoVvbhoOV2GZ2yhh2xhT9ld3Fxc/HPM'
    'sE/mjNY8w9/YO1OWhWbFDhJgIwLeJcCG1NqELqu8E5h4rBgWUFJHXdO9JaYMaPgNMXtIG3BpuKtgixaO5BUNclc06V1hCd4Tswme'
    'fWerjnjOs2fFAmm8Z+v8XInRwkztGvzs72oPrewhTODogeq2+A3pA6Tvq3LDq71A5q36r5kRU44e3PxSTP/Z/B+hjpPcb9ZQsURk'
    'FjtnNciSWYqRJKZJUM3dQD6yZQxrhjRcvd7cMtWfWsPumexlwGTD+FNovX8n3tpwDC3umnd55pgxrTMzMCTy8p6ISXLbknp3lBlG'
    'w/Hic8+L65CmIUc4mZlDXcfPaZNpqzGHzgpp6wMF7iTcSnjzt1AMDXhfPCMyudTvKs6StaalJ200RPNCEC9UBhXoYLpHoG2GeJqz'
    'rvZggDYJjFWItMyL4JPQ6ADBL5Y7P5E7p8wY/vTJ0/yPT3aoeXFlkWPenrUgbnLb6waCQ9ssZVv/mRzgphkMO4ZbHqVbJdmztsg6'
    'cSvNLe7s4p85xubHT8o0uR3HFpp7DgUDzit4LwgOixgc8/Febo0kXc/wsIyw4+bgieVUoRp+w0xwfEvftOXWJ/3d9k79GdFURZbS'
    '7AW7LdwU7vzDju04gAf5gxKi2zcQWs/8SsCHHtkvVSswF3GPHaFHyCN3SN+2Ds9Wwm2eoiEda55gV5uY8PGPw147bFExamvEUmE3'
    'a+0mhbevvM1CGPmwxL4rcVdwI8YdIhVAOAxD8Ey8tCG4bQ17a1B1xENlcA8SR7Emn9V7sPv4gQWSIUKikZaypFrAA+3Bv/+3//uB'
    'PX9dxGC5ypcu5+L3QNKvy4sLy36pPz9omHwyYNsfEZ3xKNn4ofQMYnMiRE1hJm4Xa6ZXXY1hlRW38/AMMnVCDB1RNUPDoVMV/qE9'
    'XSoFSFcDSaCbgISUY0y/wWi/jXEujkYhwRiHxGJ/X6jEaLQtjrWTFuw3dFThzh/f+Mb/Llt8tN/Y3H/o2NyytTnaHRs30Da1haC2'
    'pJZ28AZfO011YSSD5y91WeuyND3j7TjOd+zF6LFGu4yGoR6Syo3PRRsPnrQmKaAEXCuPQMWVBow9DRhjP+izfffsrsb2t+/xcNTv'
    'kDwp0ebTgoBZochFLSkcBRBkOS7rulzszfPzOj0AX31hoyck4jNEyqJZwXCZE7qMKrO9DLxNu2SxmSUHRkKZWUIACXQvebh1q9LB'
    'ACGyW5cBXeVmWeEXwp/Q91afcUfiV2f5wi6OeA6jlTLzK2X2hSulW07uWi1XlRUA/qHgNyrvP4v0AbOGQgC701IX7tSvkdYHj7YG'
    'Z28Nne9cYLOsel3WeZihUgV4FdEhpCXFBKY35T5laa0FJogqtAPxb9Gpgb1jiTqTnr6SrVZ9v8LM1PHAwdSlg7aDpT9kHqpn5Zes'
    'Lbb4xeTlV3SAr3QvHn9WLDGJTx1bxmNiGMzik2AW/yhnxMP/OAk62UN+y1EfKEK0aEADaU0aIZ9C6uRo09Lp8ZRJoXNC4aLB4JD7'
    'KHXkyhe/u3eP7+BMvKEi6H5ksIh0Ev5JmHyKHiZQluKHOY7wx5xGvDpzwXJqiWBdiGIPEvCsVvPNfyny614YrU1zLBXP8MzqffPp'
    'oykhiBn8tblF0rRs7h5daowjI8rhevSirtfF+Mq8LApsI6otduiinHzT2/kH8Z3c7KR3lzU1rsqqQE9hmynXvTROq5zDp0+7Lm0X'
    'S7Otfnr3yyvmWENoOhwhWFXwrbisNsvJu7Kcj7O1v8Et/SZb2vhzuj2hx5i/X/LllemycIgpy7/S21K6Xm9gWC3N0Lw1vTUEAN/3'
    'c50vem/f/frXH/rJf3776+uBWRLmDCrON3BiTFUlP0G0kAJa3q/M2/lvmSERBAAILgn5BlTLusyqurdjvgCYFiT0V3VZZR9zR2+Q'
    'WMkQ/n//t/+egNK+xTNTDjIvvbOy83yHEMW3WBPffZvsuf8MG4xGN+Gtb7/zIz8pF4ui7omhYllUsxfLYmEGAV6W5VsoJ8XBoft7'
    'eUC7gsqqPkeOxzSogBEKqHOd6y0NpAOCwZ+Kdb3pceyC5cCB6r2vymW7Z7BkvJGEVkK4YROyNlIJJ4PjHH4zRYfhBKX7q2xdaaXa'
    '90bc2n2JUkuF3WDCB1M7kHcAxBD11q7YqN/4ZA5lleeGIOByR1u63xwmG2IejMpdI22HJJiWctVLm+Om7bNFX2+zxS+aW9ti0D3X'
    'YmONKTOGQ22dSchivNx4nD6YXY0fCMh45cIcNWDvQAOHmIyEWBzgws7h42NZtEzxnfWMBUjB0icwwTs7FRoaz01fv6PxzCqHemAK'
    'N1QzQWskniT54GJAZ1HTLUKyrsp8YZNrGoJaVcXFcoFw5IGmdCmqn5C3PGG8mAvQ3ooXodlaEGergik8ujO2510t44jFJDuHB634'
    'ZIpWytwNRFv8PldXJoX5L5ktRF400vCVmbaFvgjgW6jE0CSTkoTIWrblKjcbwxwP802U9fGmpgKsR4T9/IZmo/BsqQq6eDOqMp8S'
    'YN96SF9igC6tT7S+S1lJx+l+hKvRl289YpUn+CcQiU8D7BYbn9jr8YVjF4dYmFm7gWe3ue29ZxF4swvFbkfAIhFg/sxYaYyOi8I2'
    'sxLPSMX4NXxkX9aoIGXKOpE4bpkatawZQsEViFqrMPcCEv8JyRbEWzvhCOES4H3eDjZFMB1650cEWJuKf1YFg3dMiz0IaFGyMyPl'
    'Q3CBy254k09RM5i/dBv88iSIFi12d7tDQpsgHnAKhnNX0NELZkYAcowg4YhmuatzYdcupGtqyHcvJJNDdRfQArfWf+iyXUQ+j1wY'
    '18Jfc50QIURuUt1ykPBhxVm2u6o9RcrEyAnAVnccA+KEVjnQwAr11DlETuHGNDJNZTY3LIzdWUJ10ng4avsp7lAKeSuox+ATyExT'
    'hoW+WEriWpvoRveWA+KRUNylN3MQjoJveevxUhxrmrk9u51VwkSJyzh0xEXCgItfSn7RnjUTD1ObSvlRlHJ0w7IbLQuT78OnrihV'
    'cbc2K9SPzAogBwljLCWXJ2jyZFbMiSkAzG6Xn3C1I+eSTUqiLBhSzuC7MoWT1ZihlaSLEpoQp86a5K8Ng7rqGHAFNICgx5W/GjRJ'
    '5/3mcHOxppSDLl0QsaQbvLRJK/pmldvUFi4WWtMT7vGFNz+LCbNarQVcT+86/ljPtFXadj16bboZQRq1Ex+u1PXI9GSlyuMbsGaN'
    '1kTNrc7TNxpTIkkOtUQDnmEVJxUJV9MqcK2q6pwxAoZdC9KFoOHHhh+E2+7oKXBFmW87leLSujnf9qbNvbceMpzOjgjyme0/hD16'
    'iH+emn8e/WEIs5C4sEbPTtOtcabo4V5HiKl6wOckiOxbU4U8hccNCnyb+NnEJ93ryFw+zYA8KkPfTtrtY6V04KdZ/AiUUmB/Vj4z'
    'xOOhi2NFEy5XYJZKMOtTLT+z8a1xUSSktEUfx81hK6wkabKLlGXF4tO2kkzI9pFUFOO1dpC4dNt3E3zYrDzlMY59nMNgMDD3scty'
    'oi8sL/5UnJ/Dxy9HrqcDt0BdjlEdanyTd4amZGGGfwxRfZTv/ZEBeXTdcHF4nxL0lagBDX0U4+taoXX34uSTMlr7WG8K3L6bPBoC'
    'l8lTFP2+2+g0QLj8S1A+4euy2ntzfbptZz5b6ckiEaXO0oIPmuZmdedJcPfwM6K7OY/FljudKth4E2nvaonrSqyzAfIV4qDAkf48'
    '3d3tQ5XAbJigBJ7Ssp8sWJqlcGLdPPGV0OkfEKYJQ1dWFu/e/AKxIlkzl4VFSjwQVl+2fcQJYxGsLJgVOYIDFvgVPzXJFFcRhpTM'
    'h4iSxTRgY3ERTIkZjmhGZBa+mF8Ihqk1uWknLB70C+8KxOh8CuRYe7fnJ+qC6NFxJgiIJtUcHt6TeTm5ZByeyB4Ot12i/ND5Hkdf'
    '9DbxF781zAYgdCOJgktucrXuyQHmBkapcIXpqCBWHJg/7jS69XKWEwUPLODHeKMowkb+Wxm2HAvvGsp9fO4ebxeCKF/6sEKJFhT9'
    'riHHnu0fRN/wi2mt97tmC1LkeFze9GyoXLjAAxCRtYR+O0cu6EPN8lLFhIRMMEhhIEWPj81Pcma7Ern/BfvBg40YgvJECEqg+Qg2'
    'iBxhZgin5mUU2XH7xTHquivaa//3rMLOVcTJBkO3dz4vM+odRCVwEIB9GCbNLwb1nzK1ojCyfApiiASNALV/dVXHyJ1mdn+Egfar'
    'd6NmHHd+K879pBYN5UEQrpIvVvWGcbhJAPWhYOvVxLS/bIhcpP296qMReeYIBvyNkCI4nvcSUe2CDxZNLicyKPsTdfRh4Y0vbAWl'
    'jAHjjVivtThxr2GqHw4lx5c9cTNiXGfAtUaJXYC3p1KNZDCXY52dkZxDa3bhNgjleisqocyiDdNAXLSUOw7UyXpQlgjHhwlDlFXA'
    'HC5qfeoURYPtJ8kXbhD5xA1/bNsNWI+du0Fx+NVho7Ur7iCS63xhpIy36qEQiZVy9Hq50mo/71v0yggaU7+apscTLRokC5sfDzCG'
    'qSqiz97BkEXLolnXNqj65OSbTzKer7MFQhwZQ5/enp7aiRJ7l1m8D1olGYSf3j6weYakXqYhuFrO86riHpTvZRDbmfNE141lmY2O'
    '72ipfrtpiVV9OnwBABMxeebCiH7Ca5kORYJHJZjSoYZYFMRuo1dOp3rPwjbyUKgYbGrJtDJijFLwiQBE7f/Cwfku8xwpkGqB16Fm'
    '0i/+LefIhUKimqPvbV47t5KKZ0BDoCko7OKNNBxOt/i7gP/mpwFeg4VjCQEbqLAxVRLM2OJ1wbHH38M6ac+fNih7wR7mkQ4jnL5w'
    'X5gDRNixyR2alvaOCBdTaxWF6iHfAbtmbrdyKE3K76bfyJdBnfeCWJdJW+tWRc0Hip3KqrEkr00uG4cKy4MAkDcnVoa+aNtaU5+1'
    'Zh3Azm/qh0yFCnrg85VAsdVUcRaUECb5qg70mpFSs6+QW4FuU/tSheox7Y/0hjMnOI7RMDV1mLFqsFt97Kq+dJ8aLBcYIbO6d778'
    'ooP8zklOzjG1h59foutc1rNQdobkhHzu0sJ992mgfd3TIuAFK8k0wW2sspdHqNa6eG7JhloOcAC58ExvPjGjFFhPaDNDUsFy2XYk'
    'setqBSU0QZor4q2wacuCeiFH+oC+WgC4F7oytD4iariVCWRJXbMKttEw/WAYVYMmKxfWdAvpaE0nNgXI/V6nqUX9sLhUrLUrjZac'
    'CHR1LNAFn2JECms5CEADKWg6EZMlK0DNUmEBOVK0loqnQHlSdJNN2stxndKd2cx8OqAn6PTmUK7oFzDdHKr99rsEa8rIUuZYrA/C'
    'ad1pbHnqoi1KrMMNMsxsDDArB915RvR7eesenbXNaWPNa+fZhMpMpwkt6gARkw4XMpXVDPjxaDBKDhRlHhwgbp3GONtbOlTxgC9g'
    'W1MsJYkL3iCMW8HsSkNSYsavAjXPdTTC9H81N15wBuBG+6SUF733gN+9zmMdPLB+HSQBAu9pksQlvp8dx87/sQAD/bJez3eHpqK9'
    'c3Nw54zKX+cfrgwPagnrwtSjBj4RPdX7gdYkLqikZ0QUNc5Dp8zQD1Cl4Au16ytzgv0o+LTUtFtaEoHuN+NHnT7/Tgh9jTI3rFcI'
    'ZdsRuwSeMCsIQotZyxIgdMwtfTnkpg49bmWuBdFQd72oCa4R5zS414p/8/YH1YTTAhFExaUeq/NEEmMvFcs+ShR4pc4VPiu5ggmw'
    'V+scgV3LC8mveo55cInTL3Wl4e4r8jctQVwsWO7c0iE6Tk6gCJamibNUCOSwtcAVYQhwyQzkUpNPZ4HoNUwTAoYhiT+k8WP0dBi8'
    'KU6s7mXM2onNItBjWwH9c3pNU7t/ZgHQKiO50JcKKkqpV4wMkuLJ9FFO3QP3U5fGT9n8nM61NE1Zkq+LaqoT7hPsLWRbY3Wcg4Xm'
    'mw4OEEDFtmhHRryLfrLwmKmRznmRSriO1U23Vc22hIvn0cql7e21h+9et2oO24bhaf+Rjsu7hqzqz78ZwEJJUcQd0xNtSYclgUuk'
    'C+aQNrSVtE0VbWa4CFQSGZZ6SP8WowE7SzyeyTzWTA50WX3pnF+srJlFqghAqrKGCcmqv2nMsTVV4ieDZWuaDvHsGLSmdMQpE69W'
    'TeOHMHwtu0e1yrBh9gO7x7dR96XBPrEyMoQo4gUaupzh6NJ/T2ji8Gi3zGN2seKS2NW0Zhd6BVuPLBu99V3S2w+NEc5+gJb73kgA'
    'M4hHCYF1DhkqOgwdANiAHU8et4wdC1eHOcKVy/X3MgY6mpa9s6HqVX70DEHf7dVudoDrscUCWPwv4dfIAwirWMBjsVinfWnIa4K9'
    'r4TZ2wsACo4eDf/n/6D9VMHLv9fUozwVFOkvrwXdcF2aVqVD8I0lA6JwwXKrsHiyyQxOcNWKFLzUHPD1tajM4iSnnrL8+OL1f33z'
    '6sXPryNrpOmhkNp+8vbdD2+CZ86+5qBkLt3ZAnl7K5r1+TyrcfgQ0PqkA5CwAUZ4mgZkHoOwCVo5EVAa07R4wgr1t6dF+KZZpNdT'
    'hZy+ENjpC0Gn+BRY2lg/hfMLwQkMbozBIO8z0PqwZaPPFG1arfQZ6ePFeHBtje/7CFu5iWz1mQJHb+w7M3ln5gz2MBveHIbgkVho'
    'ko7Aw2vYD3gjDHmxlDzBfN7X/F8noeG3ZhrzhIiW++Yv4JqAoB9gGCKpLeZ4P3XCPtNDhX2x6Ku9D0xKcRGfGB8Ggd+CP42eRkPw'
    'YRA4LOiBhEKHIWHHzi6mmg91C2knqQ6ER0+xHXWjjHRZNT3+7kV4SGYl/ZTTJeGyEm8POhVYsZNEVe4XuC9vSLqqNE6AYzaUqcVt'
    'K7OBuH+CNo6TRwgCfPg4wsWk4BCewXcS4EeP9TRxQkMhOXlBN0BGMP02tYENEPtRwP0T8XcjsTsXmGmQBiGBoDFVPv9IMGojFxcL'
    'OZPLZX6gp7OVVIQoSdPnheKvUilT2QyrBJ7MzQK0KdLV84Hy2Md8Od+Y9TzG1cPHhiRmkLeRNCgQ24pzkYckQ8R5oXhdYZZUMyYe'
    'WTVQ0guYOBX18vMZ06jydwhVvbA+EkF0runnR6s/beIretyzxK0rRT9rAib747Y6KU7DI1eawQFdmBWxMI/p2mfTYEdeCfjKRbjl'
    'o5NaUrdyAWF9mO1iFsgi2MC0OkSnqy1DHX50sNonNMMfRpC6RWqztS1MV32Pn7nDAVYQ0NseRq/vP5zlBKMnq3to9sIwjAuc0jhe'
    'fDOolBLZoZ0Alj/sgOc1RReRUyTcWcy2i6B6E7tGGoNljo/LyvsO6dg5tkhoDnna0WC0346ev6p46LX60E+us6Vvz4yn6VGAFIn3'
    'jFhz2QyyB434lmMRExPrh+BfeE5Unx6b2WM/yHw1anSLCCFghnVx+g9lxcG7CPfZxxaH6AfJ4xoZT8BWqBt9JbYa5jImg4Jniq3m'
    'rHioMh3c60Cy0yHuXTYxAjyQmy43Tvuufu63CRYMv5As6/bFHkzYoslVLu/iKZdfy1Fae0Goi7wMndR4LNwP0ximjZclK5CpYkDp'
    'pjfyPJE9U3DE9173qABzeZ9e84jhSBK/9ERO2EufSPfSyvsR7t6CqjkzfPn8gM0ubEsnqm/TSlTfpvX02dHbGN5ApDmrpqH336yc'
    '54GDsGVQXd4D7yHMQ6MO5J6MapKes+ucVfnqzLbDjAfx2ZEGXHdrJTLxRKB243E4xymzsQ4PmSRKkmQN1tpFvl3wE5DFxspi11cN'
    'jV/FMxBjWlmtjTXaSbKIleT6MFvM6XG8ly/jOnqV5Ac1n9mxDWzmlZMTMFOr09O+LhVgVcNBMzzbGgkaA1uOoLmTlTuJ8oapqktz'
    'Q5mFgupdZim/6sJUY2nqMdGttMuPcHssgABpbW/7ZW8ThZvB9m6dJZniOLrzgYJqvooPSJRoQPtvOdpH+/5s74sIuG+JagfU/xdR'
    'lQxIzFuoiXXFW97lihf7Kvh3zRe/HeAgrFzWCb7o7nMTm6VzIkhjpxzgHk9yAeky7U2QTpkpFZY8yDf2galU8YUnAXxmg6F4OzCU'
    'QUA9TVvgurg5jxwhWuK0NmwRjDBwX+M7WDvunbBmuhLDWSATFzqztwzHCEFNYzLML1ZzGvIVTgN4ydpBpiSHPDn/95IjjStbb5+U'
    'ZkXLaNwXXsP08f1p3zH9zFgA9gLBS+gtuXZSTgoukFoarxjyGnQokVRe6HTwrnSC19oHK4aNUd5VLY2nDkjcBveI0LRsN8QxubOh'
    'NOq7NtDKMXHZYHzCbBHcZrLl8TN4WYbcbeXmoAs5wTuDxpidhl0ICQoLY/LTNoCrnk3sjh4wEb6eqLWU5j1X6iCdD5isAXaJPBua'
    'C3dCvcmIjN+ypFyUByJFZMxcVExtUu3Ai/0cWqpA7PBChqXAoOXkjkPWZJh+XuSQpB74Ng5+BS9kwxV2yCF/A17VOdx+Ubdvo8Md'
    'A1cuzKfU2dgIZlQkTXUUKS0ihpvqKH7u1QoCYiS3iYEIJlWmeQ+hFUvmOvbwa344hGcOMDjNGeATuoSe4ExvY1jlvmm1n+w/6Sej'
    'p0BpO7VMGNzWC1BtTRSnIVBTSYkmiJAQE96Cz3bCVL1tmKb2+NDISPS5TlEBP4eOzE8kthE9tsUP3eAjxwj3JONQt0xLuDIkFiFf'
    '6WjI0ne7U1CE5ax15+q2DfxJbTI3uqNkAw/EvjpNyQYH92Fp9amPvdOfmIZ658Uym2t8rs+TUK/pPgjpgsweYNmSD1fIUCFpLpZ7'
    'ZpUgG2fanEzJQbAlkocELVTdO+WNV/ar/uMzMZKwF1aiR1CVrZrxE1VF9Np5Ne/s2id6FJuLBXrRjy0M4K0MO/bzsvuZJo4xU/+L'
    'uEGFxI9KiEV4X6TcQPBLk4sMBAqyLzI1LQJRwvm9Gh7h8kCZ/wMnqywiWWXaElZg2LpNvRYWXrg0rPYT+L86S7G6vav1Fcq0eXZD'
    't1AXxFSV84/5rxIMFH0L1xCCoGsKAD0bruZuPOwnj4bDENGeNkckm6xpcabVKJOQwcLmjAVlUoc7sUlipkWZdQ2pYZFNDSNyrRnt'
    'Yo3/Pef7xq6wUJ9wFCTeOK1cO4GHnHWHpp5L3UPQDbUWIGeouF1KglHNUKp9UuWcPAwchLi0aUdQrT2DQM3qDfyPaGpGmjcvpju3'
    'kHuavwVDUEKzJpozbQhGCr5OX4VcgixdPkF4HA6CDOPreqkpfnxG3FVWrH9XAqO/Ty4idkcZFKi8rQRsO8/kt5mkvnX34kRAYwpD'
    'YflxR/mxK5+dhmvzp/I6kYU7jXM4HlirDDeuGbj5VUXfXAm142JyI5/ZyEmlV5B6GZaMcDpdOHV2Ga1C0bnu2GytWKvTgzCTA8F7'
    'fJoHSrIeIkd+BSkC5SsgbbSSyC+r0A/BnPCTa5+/cyJCyVgTcDLzSW+iWTKZEK039ld8ZkvGsbD1TM5EzCg1Rjqjd1g5fEaRUM+Z'
    'HWjanfGBZhtZIUtPZyrm0R/uSMU8epKmPn+p8CW150rYZX/qUugZq+akKQ3XkESDvIJuuGwKUYxOB+zjgoGYbEiofMHI7VCWxfY4'
    'WQxM44vB+NTHRuoS73gy7ggBS9xqPPCM7HthYt+DgX1i/oJP7UgwxIeXseY7DJcyI0Kx4YP9jW84FZ3eAsLkyaW5uvJXfN4Ubsyq'
    'Q9iokX7WWEf+8gr2I/G+N/fW5oaZBFtELj+wCA7uWlzxh8qUua8+DCSlZiK4YD5KC0FP7iRIdKZZzrbr/stY73/nGIun7sXPy+/L'
    'm54dvXDkyhDgHuBRcms3sLXxVoB5b0tZxCQtlXYMSjMV3m0cm+xz2ql/hx43ZmCcEZ1KsvDEZOZ28UGqS+rIWiekJDGBN4wX1JZl'
    'MpmB+bQZvl9E3iReha0elU7laLiea41D7tRSClDwGArA5TnTKoUZveUIV0SLLVbHpY0uV+wAx6QBuNHsPAeE4VzbvR3J5nVax5HC'
    'kqQg0MIhrkIAJ8ObSM/C7LpYfHHUc6B96odaqoCCZQTOaoWmq83iM+p6RLjB6cV7DMg68tffknQ2bBGN5C1Fp3f+5efZ0zj52Y3Y'
    '/apNmPqz5dlPNURrD0enu7qlIRCdhmK8wjbLQEKcxplhX5uH3s+VV86czfyw6J/ZVlFBCHfTQ/TYPXEv8Ulo3Lpf0WXgfrVJ/eF2'
    'KcJtfSBT4bRoMqtETmraAPwrPl4umr9+ZKkK72OV9YLlVZn1WDETquobGiYC5RcQp3REJgqr6rSdvT2r6fwgoapGRpdc7iLAXKPI'
    '9eAyJjr4PjMYqFr1Ym6FSjJX2latG7Mm+lNChZBJFWHvC3+hkqSL4A1vRvvdqnK8F2bT2VJohdnmp27t9k767IXwLviV6ukNPPn9'
    'YC9q0LOThZpSKINNWBVtF+hM0w3sOqOSIfKxtEtA71a5eNyzJ4denKfP7GErVXPcG02GpGlUxbJou21LuCAO05m02eo1YWZZRJ+I'
    'j77vqCx6263QAZkN4eg4B9Huh75RVIHlU6uraIzZDeI1hxy1GHg2SPtnVSN7LE1PdasV2TMvtyaDzupBDIKTuz/vve7QVCSnen1d'
    'OhsW3UWZxlW8lMTRAhI+z8NMzFQRSFHmnNOra01Abk4Se8AR9IgxCy17HDWhY6D4Xpi2KBKIyMAO2QMSgaC0idWaOc0MIF1CxB7h'
    '7GJoKOxtVbad6aAn8erCQIjFoU5h9pwC6gLmNzqjQGgFCGSF+s4zYjj1jMAyGsJfLi+onLUyt/OahAv8oTUbZpJoHTdzOy7iqh47'
    'lZhJzbNp4FdutUFhTEpD9rlaBQLxsvLk4FNg4okcrsRyBKC0G2uqO0xk/d04C28yESn2xgsySl8mp04pJw28+vmXn9/FjnpD56j3'
    'e9gC7yAOqQ5tvgKEc0sMjIxX5nk/qUKz1XiTfnbL6PkaW8jd0KkLVxomcXrFGFOXwOkVdJRL6jNfkeG1JjBawA5ZCo82+gguvTSB'
    '6S4MYljMcN/9vYFHWePsD7rmuiWnvsbA+BI8100HxhslMb3gDfvod4/bZ6mOcum/IOjAWc2pbxhDu2rJi6AGwiSoQeE2BCpNzhB/'
    'eeY2DikLEb5Je5T8SCuOgoBi6JNFYEf3xOKLSJP0pEdUt2vVn+k3pJw+bUL3OY+Jls+YaAYr5w2QifFHPdYuSsTk/DVXy/4sx9vS'
    'kou9AuGYIirFuaHtrOnaMC3Oz3Na4DFNVZ89YDZKn4nbE3J+4CLPayFxWX2vGZt24LTK/HBRIjM5jgOSKKtQZUMi7xQxmKc+x+VX'
    'en2Klr65h6F8u1qJDkx83JljWG+N5VaBUpPM8DPL6c+wnyg7Phl7JYKNfVBTfgaLyBB7gIXE5jLJTorsNNXcNl4mem2f3AGV9Uqi'
    'DaVcX5Mp85L2P5dVeTI+6WiRRSKzIibdUauLZa/J2n5vt2Vf8wFz8+6FVPSFL/LCFUmV3Q/tXFlMLjJPLjK3+fvJepx06IReeZ3Q'
    'K6cTUsHlqo7lxVcqL74K5cVXKi++CuRFZamoaAYPpapyszfClFsFV9NfDKGKlG7L8lrzhIbj9Rc/GH8JxwsnMb1GQ3gOnlmBmKHX'
    'qHk3mQbaO/PeHm4fxkZhYjyZ/vVe9JM9TuW3XO+QNNdwGVmPYbeYjrXY9/1kW6nI5zc/JwQVyrSQi9ZZdG/Me2N5HX01y0HPDlP+'
    'UG59726NI0uJ7EmkYUSLtOLwuDdtPMc6OE5eCHyLq4D47JEE1FELVl6717vtXpvCCi5lT4SXYDY9RohGuU7KxQq8+dycH3TV9ezn'
    'UqhtzIEyozAQQ6w2hdmF03vqxAWfB2Ecy7Lvc3vhmEnqYgEGNjd3LB2f2D7RuqFEj4cGj4tB0nsTUH3whmLtWIpRg52Af/Asn6+0'
    '5wfeRYvJVktEusEFsh4kP+PzzukCQF2TPSLOCWCB3rMv97yzGN2k2UtrcLmpXZA4XLPJBJNpNtQUJ+254RTZ+YpkX440a+uy+V+J'
    '0hGon9w4xMp473pcq+8xnfiH/BVqX+lTzFMr0vN0Oy8vG87LkWKS2mZRTgbl3nc5OWOHLiGDiyVnKUrLi8zqPzPxU7gY2xvjWCGq'
    'JI7cU3cIxV5XxIU5Wzf6SkcExV5XwEXshGZafC7aY1OR/sLc66nqSFZ5g6bgdr8Pt2Ud3lDhEuluWCCOM2gwoDYBczjFW2Zuew5U'
    'C68QYO66M9YpDLcivgmWWeDzdzMM3ZZXwuBikG9GIT0PHmwab1BhidNt03hDH8QdWEq8g1lbqjopw4OnoTt3oSjU9yy92n3Fnw39'
    '91MzmTdD+yRUlj81q9l8D5/E2nC8sxnaJ6HqHO9sRoeBGxNnGf13eiOPCEuKATABbGJMnuQ2QDCWUtBoFGDVEt5ZzFrLPgcmtT6g'
    'nZar/cd3WK72H6Vd1iSxXqDqL7ZTYEXOSHAiStJNS/aJR2rElFqJibwZmTIKNWUUW0wZT9umjKdtU8bTtinjaWNjo227l5d0mdsf'
    'qj/DnRv4Njx0Wcydm5Yw9+Kc9SLMCBYUfz6TSCfucAKm4C7GI6xAEbs6g2PFPAzrLyG3eVjYeMSkd4capc+Qf++Xj9rvaZR3OgjU'
    'T0sEio6B47wj9VcWu7XvHK/ZARGB4ELRUqD0BN9E8s5T70RPadRGD49iHkTt8GhcWjWTKLQInOcO0ll5TVABov3TZ28dYT3HPjc2'
    'ILZlewmJrqpIf7dSpFiel94octmUpu4KBei0X3Q4Ova2BEW0oGwZAmvBbBkuG1lD5qVYQ2bFndYQAdtobP4wdq4VOtdUSVc3MLlQ'
    'tXpyAuC9PWzjE/cDt+yd0elpl1F42iFPiAd1BWVNz2/q0TD1ny7+19WNFLl2IMipGxCEJEVesfMyPJ7mJWSbQxkjdzbNCt7dav4N'
    'gylQg3n7NnJcjSwtiLaQeGf6wWZAQry12MvbmLiHTSbuLkagQXSxRrvjz2SwXzDD+HlJyvu9vVBHguQ/he83Q8HFX1NE5e8HCPh6'
    'MWDkYRB0jip64XV4QL4YzGDb+X5g5kE9JrfxIr/hoJPiL1D8+ZF5zb9tJCSIR0EgkAjNvw2CDdFPcOk2S6qZ6DyaxLBPH/3hYPgk'
    '3bpFfht4RJqpqtccefgNA0CdnTMW7AZK0OCxXT7qFCV5E3q/oY+yLFwP2meRR721jKRz61ZDglMVifuXI+cU6fQYcZTdKu2uNPbc'
    'QikySlwdzXgqaPmCxJwwjAci0ZjnAaa/9ZJWnYT69ssBQfg66BfUyo8jwXtmEkhEHBhDQJfQYfIrCLvQ36Yd2bqLft6SrJ6U2qyn'
    '8T27lQ++hrg3fCcjvBb456KcZAiHIZOcK3xYYwhPamo51MzIgamyEnqvC/BIjUTi4+DH2QFK1fTQ9POBNs7ERfssIdrBOtCFOsdE'
    'L4ovN+jD2bI6Q0tWEaB6gSBtxoL65BlNR/esVH4utqkqZH1NW2nfa4+VrRGPD9C9ykIhotd04l8foItWeWCjnPs0dEmWCHog24WM'
    'z/bsjYrkTCFBPxWvelYoIwE4ssmlB8kZgLby6Zlp9Z6V/MmuOK5KXzTMi58p54lnNSOXqQWAW1wRhj3baIhaXZYDBaGQHcR0GLKJ'
    'RGUA5YgwZH18sA2+9tFqDPOOjWuKXjZI/vzijVj11kIfVgG0VdRfB0p1VpXzAh/MJxJNJytKNdt8jTUpAIukAkBCp55kfruxkeDz'
    'OWf/XKe5JF3xoFU7bjkrghThkgJSoHtShrivPTJnv/m/zEsfH2i2PYDl2e8Y/onIi3wp9MeBWCKvt6lIRk3LRYM7vNCTRDoC9uNC'
    'jxq9A+lXgzX8u3IoNUvKu2Ft6e/nTk1lE8ukaXUhSiXj1rNK40/4y/AX8sszB/aAF8EFnhoyZm1fDSOsZOCr8INKVjqXVrHIWvU8'
    'rBawXYvzugE2FQSZ2JDNyhlTqDUEfROaZxVxci7WMIAw8Q9fU8p2aElQY1PadsRyjWiWmcBaSRBzwXYDl9m07wANMpQtqGDRcE62'
    'Fa9vCz3gdTi/nseOYluVK7Q36tjQ2rIUa8uqEdwZuLpK4myhNogfAnpV4P+KpBuI85Yp8XW29H3Ka9ZgwvYfKeqHVbPALTMC/th/'
    'FMaHmkYhRvO80q4cC5rAB+HHZwoD/EE4+Jn5c2s69SEIH1WQlUocQH0Y8wfRIXXc37RjmU0JaKgOorwENxW1U4Fvk725aZTc8Gaj'
    'pLnZYObN2vkTTkIurrlfzIaT7EkYJkw3wXFmfbYVxdFpucnsHoe+RPqC4ajn1EdM1YGNduFhhxwYK2VUPScKk2msNQFnSx2dexoq'
    'UEZDVdSJGmUa61L4dBQ+DdUqoyiRxnxgWnmGjvzrvybmYggt20guNniy0ScbPNmMuux73WLMnFGl3mdQZZnIFZZlKMfoL9Uh3fDr'
    '8Y34Em9U7HCHC/px21Ku/plC7XZiCHKPUIA9+ZWlaVPYsoyj2QFHyZ/7TVdHgcnkOV1Fek/SD+936NjE3jLcd2Zk7SkWyf5cFzZ5'
    'ik61v+S62Asej9q5VrZqCj6jIWhojDERy1ChZ2hArDrGNC1D/Z4pEeuQN0PrVWFTphw2lMmbUd8lb7clYkqD6C2fV8t64fADDi1+'
    'yU0rfl6dclwGBbtmbui9c2tWAfC8qva5ptjKYEbanqYy222lSy2wZr1yEA+r7nWmQmB7pOs1dfufSP/CmT6IJvognufgMoy31mrh'
    'oGc4zk8xTR0PMImRVrZJYU2RUUNL26S348Fm2NDaNqmvKTJqaHHTQL8eT+hi80rNJcLyKbQkwx5DmUxk8nhiCTlud1ZYQAE15E05'
    'yuV5E7WD4kNnB2RyG9CcjXXFRqR6V68La6PtWcQT+MmQx3ZSAs2rAbOyLYpHHSOdKMD6fEtEhnOJA5hN4UC9KA2LVVgkUjwVBgwC'
    'Cwyp4TEX4dgmIurl3S2JI6ORV8TcKWO0EwDWKVRdVzOWv3K2ULJkX4545pipzzA/jr1pcj5hJFGb49CInZvmlgjub+LyG3pzNBe/'
    'ux9BLC0m9c3gvKQj/tmT4TAZ7a9ukm8+/fjr63e3Z/GalNE82hpzJ6uuC5EjI5lrReBpCF78BCD1fWeqnA9kgo8ptLzLb+qe3uon'
    'oz8MwYqetEy6dXaheBKVh2D9lFzraEzyYt4LWTIpSXgJorliTBRHlS3W6YDpp1PJ5vKkn8wO4uq/TUaPac27DfzAG8ykWHdN34Br'
    'AdcrSyDUK6pYjoOb9Ivy83TrlDsc4Pkg4yk9H4y3EA7OFOclevH+fGAap3CKX+Ng0nqfoD+eU4vMPWBGOuuzCesO2qCOW9qQJsiT'
    'oYWAAP1Gp41MNy0cDgFCW0cR/B/6ups9l2vkqnKnEqiPDuZYWV5n0F++4/wDtaLexvU2cAMtD0toxFpcAdzJ6F0CutAELQurr87i'
    'V51rwNOOvfSjuD/pZ8Qbpxno6uc1Nm84Fpm2ZwKxwA4IPpk2Z39nMxJbMyFa5M6QNmbeSbewY3TFF0oJGUI5sj30eQ9j38lt+46Z'
    '5X5XzZwrZbJH++SyuUGsE6xO8JZGbrtGq7nRuLHMvkRczqZjAH1qFln0lDOzgSSrN+v4GAN4QFxeJJ4h82AfbPgAfNonn7+ph/bi'
    't8b2rXH4VmQ22sbDdUf9kVEPpqUkrwa6hzLNQeVQlOlnJgvfhMqxZ++YMk0lDKKFxvRyrJd3rZXPdrEx65+f9g6h67ZFbhyT0Vf1'
    'TiRXC61xrreWy/BeaAGfQH0zbqk+MuBCeFw5XzWtrUGYAFa5db8rKBeFG7uR96B3NIuZ8ozdy7t6kyKM3c62JKUW3dG2pHq8nDSg'
    'sFR2+NS9Bsc0AwjXrge9uoSPhdiMxdNlLIRmLN4tYyEy440+I4EZb5PJgxm05NCOzWf2+BYpx+fi2eJaov5XIkaUqqx4xm8BRrxI'
    'IPb+c34V72+k/MyW3wzt/T1//7l8aTvM+Wsk3WUk6kaJREWGnepxJSC+SzmqSn9EQVMdHlIitU71pLJvzfSDgrcacxQMfMIlJLxr'
    '+bmpmTtCC5/5bk+gxplSfpbQbzsMc6VJ82hNzqM1OY/W5DxYk3/TA4+W0+YyvrNwbByIiFjIN0vuNqfW37iLDfUDtsSlrg6WuLST'
    'bkp8RmjpwLj7SuGl0ee56J/+V4kyzbPgvsrHjNikb5+bzALiYel7fNtA2SQgN7x+rWv/n03DC5BZWCJwsR4SO7SqeXUXpj29QKS2'
    'CEGVjg2ojs/EJyIqticuEuE9BhcsKOtY6P8gYLHtVtUPY9aiXs2KL+/VXd0IslV35FZu6VzVU40YWH/kD6BWwfP12OwpU98TcNAO'
    '38lw6kbE2gPO1j5cfPb//d/+n8YikwzM2/Iva4pLBoiYidhlSmDu/pK4DYZ2m4fPjxI6e9iH5uI5+LIOnArnIrXgeWv20PqXwiEo'
    'dqSk6F1MhDJ7wrwttwWKzkQh5WSFFhTzpPQQbfSyx5uPdBU0DNvqdT5ea0QlkH02ySMPAjPNLywYVQObca1y4BrozLtsFbTZ0582'
    'tK1Fc52GhKmFcSsorxHLG+W0xHAeujZxSHE9HXNZDdZmiazpljXSzJZPhm614POKC0nUrWjf1iGkWmTzucRpVQ0e4D6YMSNY9tbp'
    'YMq0mfy1SbsPcF3dLLXlYGejUObD5/PRUAP7gbTGJ8/lI7HQXNP6zPfA30BHgkbtg6hP3bCLoU+4JLDexn0EzkYc5ulN5GEk9zaH'
    'zoBow6tF1pE3RLyRkpjeVg7t++5tI+qHlnD1KnohMdjNRFNMHTph+jEcOzTKXuTiB4ogCmAFWmR4uCk49EV171TEX+avBlx9A6Le'
    '+qlYD9SVC+zj6RFmVA7Sxq4GyY+SJAmCAFdXGnSa3iFA+5rPE0GXtx4e1HNYt5CNhKDk4ouqsPjzTTLLb7KLEnh3M/NFm0m5GIf+'
    'Sh6+LYgVbqK3xdhtnR5M62xaXFUW2T1Ug30FaFugxd4Sv9r26gxzWIRBrQsf1LoYMNwh8mu47jvSKD6NKPF4GDpTTGZMW8h1SYw6'
    'ZZTkN7kghWQ2LA+1XPJOn4SO4yHYdoahOA1yeLg1QLu41wNnsbPsSuCUWCXT0grSklzfuA+ShD1O19vrZU0/xs/6ObpYKlG+wYct'
    '3DR2iwT7oqjsp3ssa4t+Y72uqxZw9VrDawW0jU5CQLXDuu7aZy45jMvkmiPmaCURcQjcZfyrQGcDSIGJn2Lwt2mcP/VkoUmMwoxi'
    'ePuH5fTLdNAn3QrntrL5tJm0jQhYAchhw4MFx5WuGVhWV5JMzjPTEeKM7bLDXA8xxgxFMb3IJFp1QZhQm6xVHo1TaoGPkxN5i7nN'
    '9MnWlzL/0hjgcafUkcfQZ1g4RwnZY2qcXWKqq0U/OWEmUVJC6ae5G+9KU4C8QGk3MKRLuoLdMGMZWYDSbmn3cMP8VvSGfdyyhNPx'
    'UBbgFsivfQv5pcyvphnhOteVK4m9zAa/1xSjoqRZu6bCkHd8Yo9RnU0RdUhPJEeU2eNgTggDFiNxo8Smq4Q4UjmW53arN7V0/ctC'
    '4hpl3wfDYT4aYFZmtwIZMHCxbbkISSV0avjgLxE71wAdEN34yiP+i4czg431czWm+INchbbpqY/BBq+v0bBy+cxzsox5XY+3Boy5'
    'FHTM0KClJcJ0lxLA1GUBw7EzcxHXH9a1N/IM2Wt9X6r8Vv62DBtMKCqT7r4/taWBn2BkQqYYlWn3AxOW2b6eFqgZBqPwTdaKAwt3'
    '9KFrGpANVsO8uPEFut7e7X47WoMNac0Q70nJFESxf0ZL3SafEocB6nqksL1quCSWfvWUvrPP7Mqh5PV467xXDvuDUk2vVbE9X23t'
    '9vzFIQr6RiStXX+Im2uY6fK9h5EHxcT0iANAQGUdiWpyaIeojFlaEUuOldmwfUCTMhKWkF4TEBCwUnqmm6/uOyOCdrURcX6TKNPt'
    'uCIarHhLSWkbtmMa4naQc+tA7pimDX6/weoTvEPIiGYB1cR05XxeXifm6MrF5K5fqcvZkJwxuYO1W2I8i7LpVLoS8PnMozu+qutS'
    'EHcOQrjkKumRY6FTAED66KgLN8qKcWaFkWKmayNHOB//IKmc9em859PJM7PyNMABcfp9lp2K1r8vUkaWjEtTJ48fyBuilwPbks+z'
    'qi4mg+SXiMenX/XqSvPkZhHucwyzOzac1Fy8SqtB8uKqLveYgxZ4R4hsC0cAtMPLCGhHUk9dZ4T2EMBpeGkn2G3yNeJpGuf2dsDI'
    'gZhwtRTTQxe2tLd7b48zq780zuxv4xr2/wvHMGf3Z3wWpvrAcOOcGmLWG/LRo6HnZqQA7BOzKXq06GzsrfVBSFFN9wU5bDMiXpgW'
    'goJmKBqYYRj4RTLAqRcCfcWEDgN0JW3LhShIx2LJPSzvOajZKxv0exUBv1t/N3n5RPIaFw34qPnfnGHnAHvsO89Raz8Y+U+7pN5g'
    '5D/tk/yuk7DcKUcEjEn0bOyfpX44510J/Szey7/k1i87lGBdymeKsv7Ky7Sfd8KJouPmXWjFgkrvoJqBglhpuJWEg1fqdRFIcg6H'
    'TUjQvdgcvj2lZmHOY0YtnVwOBDbp0kyMpMR0k5WKK2s6AD3tibjCAe/TWHzaeIy08eLYE2OQYFTBR+/Kr7F44GCT9OYusbKpYfQH'
    '5ONreu6or5D138FZzIyaqd8ldvIWVzjmbMKhJj3EKXSkm4KD7zaEnIN8CdnEnKfMF4ZduvyN4DXOz6XyMqgcdMLWPnDGP0YUjshN'
    '+KfOyCdP2ZdEMZ/mBK2rC0ruVhcg30pIQ1LvYMPL4rJ5ipt26qssOYo2Wz+5GifxdmvqsD+SvxG58fz85Gp8ahGp0W3cyai4+Uim'
    'R0RILadw1UG5TUtY+chXQ2ikwPJOsztEhxLmmlMdoUe+3I/SOpgh009BSTs/1NvkkUy3wtvS+1Zp6WxUupWOpksIlJX1RTJgXLQT'
    'GeWFXasuAleuIONxGr4fTOw8vJdpeIE7Mr6FnwZTbuPLbaTcxpf7umm4YNjRC/L/3/Pf0WgI009suEGx54Kd/aMu+mCc8RSz9/BQ'
    'nsbDHT1935zR5tN4YoOnTWX6ttMwxkS/r4drhMHSEWMvI/WjDrR8hTnpLqmUfQ6cjWP88525OghH0U4Oeq0j821yeegmw93f8H5j'
    '4UVsiXklxGZ65fVyDvJf3G8LRc1G5F/leOUZ/hFoI6QAMJypRBGSnqCG5dX0ggGkc8ODVz4RNLXhJTM5Gk6XQsFF8TH3wZBAJrqa'
    'a9pIsLupzwyJMorZuoC7M8UF02wuCEbse6BSjJIGrLqSBqzuSBqwipIGRGY4Hgbx+VDlF90n80ngT0biFXEeN4FTWfvppuFZFpQY'
    'h++Pm++Pg/eDIzdg0t1wiWekGgzi9EcNEmU+sTvoX1+O0w2Y0mYlnoyEuuiVaOb9o030aNOmkA3SF3ahk/CdyGQX8PobnwoQDGng'
    'iQD3F+ZP8cE+eN/MDig5P4oVQY304gMvxuETvfjQZSu0eQPcqpOkAHL5IcobIF3K4tQCY80b4CZod/cOsBg/jd8CTR9skZ0NchNW'
    'HbGgiyC0vQ1FrupPQsWscgxm04kACuk1obxZcWIUZchSj5Y6CRcvZaOEYl2Yq4w5nZjfx/ysHGPlfBKewDNgZIhf4z4p4yMQRUl0'
    'Zup5ppXodTPeVJm5Ts4tVGTdl9oQ7hQTcdl/Q+6zYdNlROJ4e4UZuf3Bwz/+0Qyu1IOkaH9o2W8ESmL/Mabpj0MQGSn9n5JH7djD'
    'm4NA07y8IKoee+G1y3q3GxJdOFbL1wqTCLkTjq5mdnrmeQAYOFG0bUwc03r6SQx0YebQUGjpO45EIyI6VRYPqUPc2QR3NochNIly'
    'lJDzWafor+wstHQBVx1YGVdN2/XVQPBoxcRs9S4HycUclqgAzUiDy6mVWZVVASXKIHmDRaOQFaJjkeheM10XFzkc1V02ViqEzHHI'
    'IyyrtfgOEVlLeiUM7kkOhGLh/GN8njPTNRyCPR9Jfh+SFizEPMxsAerN13Cm9rwF9lY1e2Eq7gVnFPVdPl5MVD5NCPmTpRpdbULF'
    'ebYpr+qwHuJpfmUtTUz0E5xPp4KJDnE+yg4XpYRT9BJtGkqYVb421S2y5SQfLMtrIGFPr7h/ngbGXwww+lleN0/kKB22kZR6KLNn'
    '6qZO/GrNMGzadkcWtG9lmsGFmduHW5DxTxj0OZJvqsumFLf0MX+C1rZNvX1i4eKPODJNGH3Bm6Z6yGp9sNXRYYs4TUVRz2mC9GF0'
    'RDB3Z7DJCd6Ycima3QVm68iU+mDE+xqrKMOS/BH3exhWfZEw+tHqVcKv9z4xjwqrO7irNrx061d+uHj92kedkWYF0z9vVOf7/7lF'
    'x5KYJVT+uqkH716CjU/1oxh0vi4vLub5y3KOXHM5tWCIiO+lwadcGjLVC3MI+q/C83xaYIenOhA/mEu7+xYL+1s6N9F20Mr95i2q'
    'rab5OXTWeKXK54xDjfoe0BkFfYGa/yDZoevIDq+qVk7DKfMWevQNmwJgx6P96Ivg1btQ5QiYQt9X08mgEdLeEAU/r1/M53Y8pz0U'
    'laEEtlxvh73dMeudD75qCJtAlqRkaSIJIcxWciNpa0UT5O90cNK2a4D428iq4jQvomSRi2jGrF9vXLcbwjuqDx7Qs8w3FTR9GTV9'
    'ubXpzlMljei+Xy7nMnpcKX+B5CVLQ4H06OFrvTnCHOjemFHUTL8J9hH6PQsD6LLMCVy5yyqBdiBEamxonM+d6XKzjcIOWexbca7K'
    'XYp16dWdZiSBC0wPNNu6RdcgELERJ/vW0ywAHJSMdoi+dSALhWSGmRbrfCLcwl+sbApO+Z5FAuG4VHq/qts4R1F4q5EDprzrOXrT'
    '8sSCLZIRsZbMez7f4nmY/8KuqUHyvU6DN2VpzB1cAySV39xwL+TsJXGHTdqIQqjfIRsDots5EzBrxtkYsn19ZojzCsD712bFLtXI'
    '5XJYBpvb5dlUVOIjQGlKHcTUGQ7vyn7x5sWfcEQPLQbP6GmMZ9vEQtmOb1q13N47pFxxeS+6Xd5jnNPfjzDieHzTrdWBC9/u/33x'
    'Rpy0xmClSPEjYNlR4Hd33LeRdRQ2C6bVQnPi9C2eNRZDhLDD1AFfat742vjiGNT4zkjhkY0UdupwsYWIJ6jAiRq+JZydLzZH9bdH'
    'Gn91fPGXhhefiv2iywSWaV5AneAXTD8r6TcQ32+999SZVmP3dTzCjX7seWx4AXpNGkM63SSI8OwFk3Zahc8BcvclrVoH0jaUck1g'
    'bk2+1gGyraUjTO7YlHQDL2zz+jF+PsOHsO7REzOq5rbcmfHOYQs5+5KUJgAFaJCbz8XY/MeIzf9igIBANbwVmkjhyfuC+NXAJho3'
    'sYlIKMDNp8cJNAZIpJQDza0899phNkOqUqxW4sfheQGccOWNV+/ONJxyzlVZaox32UQ2auAajQNcI1EGlzGukTlw1EvBPQ6Bjfh4'
    'M1QT1R7aC5GN5PEofBxCG5nHXhz7WyAbdWNi/22RjJqt+pWhxHdO+rJIeouuBaK6zOOWXh5BD1hyWKZwmzZ/VxtV01P3rkp6auVV'
    'RW9/476WOQyzGFRVbhfF4rOLYsFVsBhQzkZvF5z3xYCxtryxkRIUtssNbkgJxtiWm9ZkLqLZXETTuYjmc/E7JvRTy63Vz+rYX0XJ'
    'bF0MaUQTfFfbdMR3vIM2uM9o0xP7UU2NR1fiWXxSpwZ/deOS8or5jvOw2oR3NzoZH4Ky/GZX/sOm+WQTzFekp9ccOfx0fodfiaq6'
    '7yjxgW3E2ny+ZB/1E/uaU+83ntvKVN/fFcre1vfHe1BXcU5GmktedPwDQfEzqwET5S+htZMVKHcWA8kSF4WwZ1ojU6YoNZ9kEAW4'
    'veKUIVV0JHYd4Yg3dme/B9YYx8Aazajl4FSPK5jFFYQBzEqVfpux55RtrFQqcuuZkZfPDEUktboWtMbQw3Ai6CTn54b7PAiVxJq/'
    '6IyJXM4EadSfQ4hpJuhz762CcbNcI8fG38ErDrBxbA86IYavqCBxulUt2Y22/v8Rx7lguQehFpToZYXo6auABuYAMa1k6EyG9jLQ'
    'HjDAFgxlz1RgFlXmoVDk2gKh2OceBmUdM1vWiZsxYQcBdt6YHpBvA6AeJorN1mpfDpe4MK1iwO26v4nLz/z93dZ9I2yEfWIE/AHX'
    'gYgLFqnhNMb8kY7K/vddnRN2bU5ktTnB03BO+SaK5RKhRHD3s5EwDfAyl8pY37ltpukWf2orY+g2lCRLhWCljiFuBEzDx4Ow6DZd'
    'icNmlaYsRLRolVwpeUnoWlykUN9dj/HqXB80fDz5FSnzLE+qHGqZWHDXSsBdD30IVbFkkFPQeaZuIhlSAFkCFxfrpMqAQjIpV0j0'
    'i4BB//3S0Ec0hcRY5mE6SN7W5aoCdVrWEu4yoe8Wd4ap4WxeLIr6bND0UnDk6JOLavSrpi/TCweBjxBgF0Vor23Qrol3DFDOYwr1'
    'ogCXT2Bvu0whWrGau1x4mwAjIciNnCc9JVNjrlM4kj+GgsidjxOb6oaqvWsjmGJkI4BhpgsPsPVIGdvmnFYHCGED2RlVDFYSEl5X'
    'PVyGHRo1OnSvC6GCo3v3B7NyEV72PoIZMP9uvrgVN6pBmJqrVbqsBo+v6bZfIF8AATQPBmn+tc0tms1J6gHDeWjvF6xKWfroHqrf'
    '/4LadQ6+qGKzDej0FszA/u+a5ju+a95sW4SUjsn/TNMnThFDK9dcQa0cH3dZtdLneaIoMI+i03HIjar4bSJiidpDGLxQnnjrcevA'
    'TwYHYdpwiWM7oeJIv/BJxxd2po66EwLLLr3yM/XeihVz+4ruXsNdlcXuN80Dz4cM36WgDxIrEQR8XiIdBN0JnNlkkdU4JgXOH7kJ'
    'VDsbJGOVJmxscit4g+ahKC/FZTNwg8ajtIk5HIQ2ZzZwq69+uqtWitKxLzJ2RVKf2eLSw4N7nBXQLYuyEmqwMSGxxkuZXKVyyNQc'
    '3RjC7eRUncijbJPmfC+m8OjWLFIw5PQVEqLSDCLbTEFmXjQdLlw9ltg0ahuCBcfqtMj1IDEKUcVcYnApHxmPWjYjL7yVgmxfNedQ'
    'sNwrj+XeyEJT+ei6KojNbISmV35y3AsIWmZa15ZmEof6E8VpebSPH4DaiMhbdUErquZeatsoT4aDp4/7yEo9GozwY/CwJY2MmXtg'
    'l3V9ux3FxXSyFYcLWJHLMAaX0NiV+kGuHPTIZRiFq2U2XbG4cdf/0E+0/7bz+Oex+YK4M370qYm6JGqPOuOH8aD6xDUcjfRDC4mz'
    '/2ioY/1wmHYqgJ6q/ifuxTQciCIaxkfSm2k4DM0SrlfWJdhUzggOH9VgWEP4bkRBSP6cpLsgggyUgFyZ+xojRLecPVPMOZIECguy'
    'u5IIvXLQX+I69gVQJZ2hi3bXv0hmVxe5ovqZTTktsot1tlDRXp2IC+QhqTZCEnLTGrLuIB0NHZGRDYISSmZoxA3QEBbgvNEZw25e'
    'Sjvq1+y8liVur5hurLGWrsy2dS3c6ehMen5XXj+1mgJPT2ymz93TIHmXGsGsv1YT5t2l62w7cSmnvExPfbTIuenb7MCa42G194qg'
    '5HxerGzqF3OovbU5DKjVn8wzvEntigy6uI8ajgMMRyHpm3qdFn494PqqnxEDVQG7oqTTxXUe5sJgY3nLyBLwZ7FY3ObHl03eX5Vk'
    'RC/sZnMZqi4N272IT4SCAHgLpgJYtNDhA820J286eVnlcJ62t+mXMnf3fj9/FDBxxD/b2v2SLWfb+h/V0shL2uTz7hyjVgstLjGm'
    '1GShbX3W1SWAP/p8DlvbvrYrcLBaYxzRrpvsGe0FEcSSoBnh9V7aSr2aIVvZel4gvxC9KhRRBauecOtFZbNGfwFomtJJegOx3022'
    'WvdzlW6HK4sjeKsvjeB1LUwDv+uHw9YHK22wecAAwaV6D8nMfbWq8lpNy3Axkoye9SxbUvWTz1dVo8NvW1krrjN8AtncXsALIeUZ'
    'AYzAO5kxaH75qiznrAt6WacFCQ3yHyt/0nUdbSmhyfNzQQOgu7StBpX3G07haaf88hHT97EbbVj1LdrEriB1HQ+YhPz42LBWqTs9'
    'W5jKfDdcnx4LEFm9qVEa009ZRohnk2jwpyVM/DaYX2HEuOD39sJ2eELL8ezG5LANsyo4+R3DY1VK8Gf4aJkB+djm57CSZ10DAFLW'
    'mnraLcy6cOhoGl/9sS/dud3yGYGQfTdk2n3BTGvuKqmKUAysj79Yp/7abM/uaN9SrFIeBA6WQS4ttFp3Sojfk63xNaY1gjdzQAN0'
    '+BKoEoqXVKVlN4WkhlAORaHzUPthmIFOc6gR0SCEHajK+cf8V2mu6kmk3+jpds+u7ZlJH/8HMpP+R1PL/y0Sy4doHjaGzEJ52Aiz'
    'uOzWFPQYxiCh/PTO5PPNwpvogDZtPFM4HlODkI/mIu/KUB2g4qAKvHwMCGuaPrFREY1DWYeOEiP4WQ0VIse/gKBr06OOlzZ8qYH9'
    'gpHWIy5L9XW9HqcaGmRkD0PZxuq/X2W2ikziRReIjTR3JW74CB2S67GIEfJ8fCiWFvt8vG17xbiF9777Ntlz/yXFIoNJILjz7Xf3'
    '6CBxvawmmTjQZZoJ9elwuLohi5svxhAvoAGaGnE9+ae/vkp6b17/mfgo1iOTdUPXPzf3ruDdUJtjtiI9nGyM9JBVm+UkCXZiNv0Z'
    '7/TMYZ9HICBrnIqmkcHEFKpzcbMz11IS3wYf3EiRtLjQQ1mqtLEEi4tBtYZVwNQpt7LrrGD5wdRIVFNXVLc+HD7wcJmZYczmv8Hb'
    'DUvx4RCGwln89KecehT7uGoEcpgBNCveHefLa9QQO2VeRyl4+yGOkOmKmec0hIrqKDSTQmGd+NxpOblC5KmO4A9zxqH2dszp+jGr'
    'doz8NBFPPmSbxsVMPuUomUVV1dhOE0gDL80WhAvgzv50xzZX3wzgPClDbsaljw1l/mc+dBbDuLEaU9xUxNJ/MsuoFxQeYF15Hjmb'
    'r2aZI6IxAX2oYGQ3noBiWzySQ2t1A2yDZ4hdgzhuKyKhsFxIA/bELJADLXhsvrUu0Tmsth0u6e9Wy4sdZhJsP3q/yi92RBWTypeo'
    'aRGe/twIn7iO1/nH8jJYx2Y1phL11dgUlY4Pz1i/L7qXuyzlxj7yjj5bow6CuANVUEh95t9DH5axJSjD0Rv35lvipdZlZrirHfYE'
    'OmlDMP793/67DUqDxpKwIypES7Ha8GDjbC3r6dawfnCz+2Srekn23Ijv/ERx+OCw73SPndn9rPY1dvUKA5jV/2sGESHnL2fFfOqb'
    '/cTqb9Ptw/j139sk5kvJM2x2ZYJumk0SE3Y3MnjKFVVUr/Nru69gWTUfl81lePRLlVOFSri4OND1gTb0bUPmltnqIPnPb399bRhm'
    'YDcX5xs4P6s7pmToYMUKbKNBP2lQGVOts8yhNl2uRfthHUBYLHgoMmDIWIVhY2aDmYOHM69KfH3t3BBChZzVO2aLvc3not7+KxZn'
    'L2xeiUo/6bhptU4uxF+GZXK1rhDx4QI9wgAsG6r5A6sLI8jcymrC84gPjD5uJMAjIA99pcQru7dUOIaPRX49uAyCIqND42KAT7oY'
    'zGcgU/ET4r496iejxwzOu5TzpsfIbBcTLEXhFfaEWOBBSxMwUOIgY4o0PMxNw0gi491OUQn/zL0vTZwF3k5TvUEIl2Wsz+uD5Oyb'
    'T/xMsG9LgZQwVdE/5XZ1c9YH4qgvhQ5NNlpo5gqxPh59LHotb8rxxzszuYMwAFA23rsYnCNw/dI/+k1fME+utTA6jBtFnc2Lifn4'
    'Hfm1YwZgZ4kI0flO3ylBf/ItcjBc7SuJr+GT1tjr5+BTkqf6ObdpR7wiCZUEJbZzQG9fe9h++vAwoAhW79Pci5b/jhauLFnd5dqF'
    '4yQfgKCYoYg21jonUF/vu/+r2v3mu36yI2cBfTk0OXGw48WF31Q8MHRnIVhM95c4g9LAyd90AITK2ZmzseFhS4QXgT9E4N9BMl2X'
    'KzFrLplTh9YvBbpmjwLMoTQQTiTs89Pnwz2j6Ewnt8vhasNoDsGmMSYYawOgUSSq5mGV9xCV/bbOJpeDVbnqORn71oe6Li0llaGV'
    'M4VPZCzc83DEjmVizIrc0VPMDbOOG6iLvgry7Su3a0eLwTurWSwlwprrOBSq+QDnBc9Bva85CBfZ+vJPxbrGcQhabobtt+Ky+Gt+'
    'XvWktr42kPpY/pDm0xdHep824kZ1jZmd9MNHM9CviqrOl+a9nWK5uqoNx9ZTM05EZ914Bis0PL+x0bbWPJ5frV3FIbNw10uX+Qax'
    'q+a93JpVzXgZMvbGrM/sgmvLf2w+MOUlKvMHI62tDGNgPiEfrHD6Les/5efZ1byWsEjXPraoDiDXRrMiw9Wvd7iRTMvQHf0l33xB'
    'tXdU+S4bb+2Y0zY5MkO/3rjiIAbaDJkwVoxUN0yQGYwGGwRiTzUt8gZvYYDq8rdybWqJxEzYqauPF5BJvocwZTrzcl6Y/v7VnEaW'
    'rfAYF+YTJ3z8f8Afc4AjKZHWBb1WTmCxrdqi/8yiyLirJTe+ZCPMfDwub5Q9+Ft44TajiX0O+u5okw7GQvb838DllvX8bdxub++1'
    'XePiKDyYf14xh6r71PYnjNXte/sniBvs+A6v4bF6fm/vvrjGjrd3/421mzEaq2qY1EcaUzG0MRUeIW95mYzLa5o8rxCwOxX8/AAM'
    'ZFVMzNKliBVMd5TOnnFbw63TLNDMTzpHR7LbP+kcF8F7ftI5Ih84Ik/cWIT760asFKji+iBxCKKGTVPoCNkwGJ1Vzt0qWSmVOwj4'
    'nzqClGWyaG6ufvKbbnnZnVTu9JOfopuq09lLHtG/I2rqN6eZ/Im/rIunEdnmWSE+NxvTP7P/LwbMg3IhxvE6G6fAnIAIKkpoc9or'
    'VfcthOyY0ohQoTR4FNiGhvT7cA9/A7T4WIIE9wHe/JPcmOkN5R+UfcaXCDvei9e5YS+9IKFc9BHr2re4Y35BR4Wz1Wq++S/msgFA'
    'sTQimVluK3PC3UzmV9Ocp7/Mj86+xfqFOisO19RXBsWSfzX3+x0BnBE1i3xGLqKoDYFMWzLs4yiImXvUKLVhqY2WsrFxjw4d1904'
    'ixRMWYNTwVcGqKWNw0kDnC9/KTkowihyPX1KBKsUMDqGpZOc7JNZWVYNzIFaklmYvwFCBZhWBEv3FF+nQlwxqroQXr4hC0gpm+bd'
    'BveIRkLk5K4W+Ra9IHY+j3IRfGX4aQe+V1QcmJ5f4OA0ciA4JIJz7+DdAgo4x//bl5zKyRzahqnsHJakZxgl+qiTX0934sUpdzlY'
    'evI25qOjV+scivZGx77p7fyDWLA2O+mAvrY/vfvllakGbHaoDjAckdkkbHIVUilJPG3blyDuu2s+e7YyCzWZHj345ZtP2eDmto8/'
    'm9vk1TefVnJpFvDtA2jA5kcPlkYCegDfv/IyP3rwzad3P/3wyw9vT8y+fTfLF/npwKyTW1tgjwLy0YP9wWN3a5oBPWqdbY4e/CHx'
    'tyHLGl706AEp3YPvnp91SKP8XgtCFKE/RV/sgXRkTuycA+FJ89UjM2tJPlNwmjzFhGNrsNngADTOLc66t+kzKEEINNwcBIYD0Z2M'
    'fZgW5+c5HSslD3t6aEMrsK/La2lHDJM2SZKAz1XwGMLOYXoQj0s5aMC8BBwwAAOWRuT4eSrQeQ5AQOGpRQ8nG8Z89K2i5mBsVEWr'
    '8mQTASiUhjT3WM1UN9X/y92bdLeRJWuC+/gVLqZewiGC4CCFUglOrYEKqVIS2SKVkVkUI+gAnCSSmB7cwSFI1slVr3rRpxdVveje'
    'VJ/zFvUHet8/JX5J22dmd3J3gFRk1qtzOuM9Ee5+52vXrs1GXBfhJDnihAk6qTdSiEjlRH3gRWtGXzLxE4GBOBGGwykfJZHoIoJC'
    'D+kDR+dZrQoXDkZTqh7iPFyzZS5oPOqBCylyQsJWaCR+8JgrDw9NhNgBH2nAqr4txh+r4t7HifywUGdA01JeAQoWnx0N65KwaAEV'
    'CnG90iahY2IwmjwirO0hNB1LtMFGi+KfEGLPF3PWhWQpNPEaRCEwfzS0kxeyfFYvDEy4D44c/uyzmaK7JRb7me3Qlm9EyjZiw+jL'
    'nuzQ62QMopJ2Rbfsfbdu0kT5YdGG86ZO1FKaeQMachg/geTFoZs9l1v3AF5uyBHRS5/wKc4Qgbui93GPcwbN6h/2aq53FJb+87cQ'
    'FSPbM97ZYcDKq6qX/vk9C++v+blOUWey2D8P1jw4yN4xLveqgprqXtPuaXrk38fewtJxNj2iWHldK3o1/AbnnwOeb6FWgSIADkgT'
    'GGOMnPD5dN76c0gyb5w5i40KkcoW81O3Bfypcj3uPWMNtk93/H9DIvBFb5Jco/UVkPKsM+iKddt9DeRHBB/hSyjPmxwy/XvJ3Gve'
    '9SSEllhpetZbviDBFr4izOdJDex7dix+LpEP5ZWEsmvxOMTigMbS4LuC2CjbOHNTrkmrm6FqvrSUbUeV+lM9Ea20lesAfOx3K41h'
    'mnJsytFrzhYxrjuGiN2RBVrSbivMPVKBzMKRYL3SZtI3siixmO7ni0wRS54Uj9hTE1++zzVlHJE03zmBq16V1fAu5Sw+xDIK8pMP'
    '9yPAe6djlnvmYEoeMU4Uh+xooAZa1kDSOqnwYjAsXI9TVjF005rAAU+nFY2NFg82kuwRy+bUPXYfqgPk+O/1UX2OVk+T0beM0lCZ'
    'smBAxprNX9RAFl0cK122NYTTCeA18wEW8d9byrAiUHvL8KN3dsfK3AI1O7REOTbiIdsHTm4uYYL5FwkTRxz4JL3DMyG/UiRc8K6J'
    'pRCJKVbDAIll0bnMBbhzH1/w2+xq3XHnUu7aK/dXW07Nt3zmvJKKKOLIrsktZhoCPFnjMOGLvQ/XwWSbYp0V4jzjPGFkBoTUnvmr'
    '4lV0aqUgYCZhN4TLBLnFhY2+QUAZMTI5rfi6wjTiZHJq8eDSJhT6UYxBexl+xJ9kL4wznYY0NApM7M6qZ7aK+l7cSbFVbYM2npyy'
    'A5aHjXJJXWxDACEmpu0fyhMrGeER6LGqy2KMxgd8p8Egh6qKhbyx83djVkUSIQn93KoKB1r3pGP09g1Vjj0JgAHl7aaAajE2rQ60'
    'ANsmUCsNLTc3Xci+0t7YF3r+1Z7nNzHuwe1fIpvvo5Yrj6Le53qI1g2Wuo/1D7AMH2c5y9gbwcIcnrvbLJnkydm3m1u4H2aCewWs'
    '+2DuLJoEHGg8uARcR7oiuuyf06Ukz+GS33WI0l741UGdaZc/cbMW5B5ZmRFu9l/SXbWA9gsZegAjGXu5HqGKQPstE46PY9sRB8Wq'
    '1+IBMNtRUCx2H6JYnBNbdi7Kn46B8OWs3Hc9CIg+oPzlWSrlnK6vpCF7EHdKS7qL3NIfk04DEsYlOgywos86E6KfQXlRcU1NDSEk'
    'lcMdsI60cZKJlCi4IWed7uST/iIPrA4n0F//1/9jUVqJfhmNBpyjQtw40IZoCVEFlIk8DdI8UTJNr64l0C/dtJ8nf7HXlHv31/XK'
    '68hD0vfo5Rpi41vWxqktb0n35k76+RosEvrJANmf+BZS85b0ahwvmQHC2tfNclsyFMGMd2Vl9XvYY4rs/WkoUeeElzH/a3SCT9Ch'
    'Ufd5NzYnz4z5X6MUrCoKeD5fKwvXYVyGSHa9i1SJskjUosvRGzZrECPfkSTtNuEwaXPTwTi/9lJtidTCaIqkYF2j1zazcQ9O2zCH'
    'Ax4G283BhAQploEbuBOCSgvflfrfSqqN0YMgVJ7JvC44IaHVs8/C0K7Fuc2Nxvecxgd04MWzZ+AD43gAw+eTdAI3phRRPSx9dFK8'
    'DU746hA6Kvuxl58Z09JaQVNbJNGEojBEhGJ4vNx2RqRCFDSiE5ivBuaRHAO8AQbhxCfWMaLlr81feuPHy70mEmrTAGGZQYOZDul1'
    'fFJv0oU9jHuD8WiS/zlhx1A2ZIzTyURyReOWWXht4vI6Y8YLlG5FCyBVJxPCHFlG4xFygrsHkL2lJYtPlGwpiBQ7ozGhHQB/npaN'
    '2F8Dlb024WrYN0T5Tz/npR8uy8TYITqGLfnY5iyDiCDHHz0ZSIqIiODs7vmdCwDpaXrAb9abMoI/y/g4wjCbzKu3mSpmC2Nal0r7'
    'YPdcVdjVc3BjCWCbedGA6CzCPdeSmYZ0Ms66xJVlYtyYNTXSQ28suZA4lDJhVcQVixDUYIiMaojRPM0h3mH/KzteMwugEemK0FDG'
    '2fh4scRyytSVZddgvNhMydxmG0E3iKIk0vnmdwLUrz+83/v54K97O9CUAMv1OnznLV8tCf5ZUs/k2jrryzAXm74FDwdisVOrNaSr'
    'g96AI00UslcAcF7xtEoh8Kt8ENmATeMkFV39JjZxghN30onKNFaE5bL9JKDEUE8ZlLqvkTsVxi1wYR7KZTlB4pGhXJITpBxRJdxw'
    'PUj8d2/Q4SCSVp/lp7ijZR4aWEsI8+JbBAd2MYuLo+1rikxZ+xuOOtRiMQNPvKEjuzOFdE8UMHZPzGKZUCRUJFAR+QUlS9tKoB8+'
    'rH3Na7AUTBMibeGpFzsLYd+C8MnXIf2zfNqIalGtbizeiBSv/fr3f6tJQA521EvZnshF/nAjOBfKmV19TLSO2tdhzcSYf6+nRv3Y'
    '4zxpc/xzvlQzVSLRs4mh3kZkjpyLDKeDNjvItlNESaGDxisKtztzKBy80pe3tFUSdBkmcB6sGhf6wvQnPHGad0bHKJdRBzDR1xWp'
    'u4gk36+seBlDPdNdqwkORZ8G0g/ZL9qR3EyS8osWsS68RhBEHRmkx9SDS97pO78Ddxj/9/DGk3Y0RBZtFu6Y5Z+ww3Uk4XIzz2XL'
    '6X81w7n7IjW16uNWZAVc3Z/iw6Uni7/+/b/++l/+7df//N9+/fv/fXT7tbt42Kwf1b9mi8u6oma9OFaUtC1a+ZgnbcQFdK7kmQB1'
    'aRWjRLAxmUddP7E1Zyjx03s8C8Yub9QnnYWSjHWdN29DQ8C0omAM2+EQVo+UK26IjyoOrvUDzhw35e9aPRQOcVA3M0Q/WIOxY2Xe'
    '33LeorAde07Zq1aGm+HyTfqsJe1LTMDTRKQldIPqLeeiOMglI9c9B6mjQ5Wlv3HtWnxLVK0fi5wrAhyIMRVNpR7ldqqascSzXarG'
    'hy0+JJJAHPIsMwj8VichVriOQR8iGcYIN8veyw87Bwc7SjIWujCFq7sKm2ds9fospSOqiCbu5az9ZeSjucblXtc7tu6ICMS4wN1O'
    'xxZ3OiAdwa7RXNoN8FSaDIk5G8cdz7r8JawEmr2M/8ad7SYPtj4Dp7Sv33f5eGYcc16vNwxwZ8gZGuKYvxEePzwSpH3FYuyrbV6J'
    'qyM/hXM3sKe+kXVqcSdxRwdil03fauSKO7hSpJKlSa98reFCkSwOt5smBEGIEgvXsnYVnBc0zjfu0LYhuZe4D858redK5WmdJja+'
    'vHAFuJBiRZgoDkhmaUCy02TfTfTiQ2dHbaD1tYWkPT6DCklyTEXpFsUYVEsoXSybp+dhVtJJS3uIRsvULOeP5+ConHSk1+0S49lE'
    'PwgFxgEtlXDUU+/ytWjfZ5bgpLY8gORqApANHWHDNip96lXKkgAHvXYzOkUjqE+qzNL+rtPcqkFdkhegKeIUMmVChC2UlEA8JJ9P'
    'FIdUA1rO7q247etFDGwXZ9urPQMdaxvIJUH9OQbUw8yzJtpzq5zknmjWm8iDkxrxZRAIO0WUKO+89FA20VHFN6Uv0D+PTwQb4MnA'
    'Rgm3YrI2cYhNn6Y3gYag4jpnCjZYRo7CaW7IQaL2iVUW1AZ7iNGCkcWjzbpEtyR8IYGKfLue+tymnBrWbr40GDq8e5cdejrVnpAk'
    'ccQBxzWzd0i3wzUMwzHXnKuq0lnEr5C7TxWKIx2Y2h+h8XVeFLlL8VxlxtyXOSkaNTFZigyHfQVuoxAFsMIYqsocqmKSfZ0k+nFT'
    '1H7BLfsvYYFmr16xsodpfQFQNx2gCr7wUuAd4g2bzD5bEXQiFs1yX1sZSthSYIceF+yP1ba26EegltVxyTDZK+45E/hqjmLnLmaX'
    'xutio/IViQcPeTEsa2WKkMeyMzU7TyPbAH7zWIg5hSW6pzMEBd2tOi4e3eRvs4ntLbuR8x3YMOfXMd9DF4aRXcFzT9tUuayRh/lU'
    'uT9snvc4PBnhviKRylQ6vZYSJn2auMB4qEHfEtWIG61mgjbYdGwgX/2wFcNig3UqZAJfWrPtpVXmQo2aUdH3QILhK0rhBWCSQ99L'
    'K3RYNaXaoku1zRBnx8QF/UHJdY69HFoS8/Pu7sHPb99/+LBeGjfPFOPmmNGQq6B6jYCCxtseXYIl1f0x1kGiY2As6xl3RPCG3TR2'
    '/TRgARaXJei5Mfav/GbzxPomBGG8ydxXbAUQIF/W3apgfq6c2RLgGtFZGTLBAzzNOHWeRkbQ68nxfLk6h+PLOeM4jD/5wuRiNcTB'
    '7o+mdCiobB+s8tm0zSRgZvMU6rLWm35Yn9hu1aa3WQBPjpM69NPo4Qrnwnrz9LJ30zYMi7d5fq/5UzC/CMEnuYqdKm8Vb8KnlJM7'
    'I5KpbAoDq0zoqCLsPZsJJDnbCTjzAHpxzS8q0gGwuIPb89SZLlaiHyqR6yps8PVjh1J1Bw0lISEMMgSqWYZLTPf1sANzQU4fBqcm'
    'q8zvTaLDQ75fjo4iVuVFltzJEOEdcm8vT6WiLcuD1avMeIr+iTOSGYaRADzndbZptIa4fPX6pgjAS0yKd+m3RuulHT3Wd49vvBp3'
    'Zi7HRnh14DTtiXLVpyNDU7c86TRR0qoGKlD0mNPQkYlGlm3EuSKCNXpbVdE4AzIh/TBFVlL0rbWC4yenuYppfYFXxideZLbrnkKy'
    'N4yzmVYbRer2pQ1yKbGjErZbREwj2DYbJqUlFFVPsiAalQK1nqdJ11D1gIesWWVUhsoH3J8nca57BmUECxBRI5OlqJL2dQldRMvc'
    '8DfTPGJ1FKcfgBE/h+fzBPq+ELU7FeF5OnflvFFlBtt5LFOfs86biH2RUofE7ti8fyZwhFcmc2YXd6HEXVcCERICAebQY390y5YQ'
    'iHcoiX4F1D5B6x0wSTZIc8gbQ77rcSo1d3yOH99gEenMvJ7mfJW/Zh6udhctPL5Bb3f4SwWOmYOj3+bQ4PWWnLeMa1Ido4M5lmc5'
    'Via+p27J+9PhaCJGuhK5kJj6nb5xmKehGp96/CzYrW4349rvVPXEfsrClNPKJw09aoSbwRmwCLqXJ221o7XRfspKTuxD0XatOFoY'
    'A9F4DDA/cq4Wj1DUV1lWWyywyl2aRIAcYDwO8GPVO42iYSG3O7cukx7LnKuu5nQ9qhecN2H27/7/2XzZ6RHn9E/C1Krn25xlEGb9'
    '/oUIzKGQ+c6gJ6dO86VriP61WZxDg1XfoBpiFNgWtbcK7I7k8J6wW/wcZbdViM9yHTe5EY1yW1XYJ+qJbtJ/mJuYo/3wGy+oggzv'
    'tLhdgkRQk00QTGAeTwQuKoSwur9j0kLNSZGM0JNHwNVhKGdka1ZNti0StVYhRkOF/qelirNZMBlIvryLOK43PNChUdLQAtFftar9'
    'PL0WpfEMj/phcmFtOmfcN8XAscTrdT0v9gd5qYeiESZgq0QjF1ccVuPKhFi/MDFpOJx6Q2NIbqLcE1CtiyhBv5BCLZ2M/TSdUoRt'
    'c7jIlWftKM0YH2CuuaVtP0H49erBSW6hTS24KPWemJSfbGTPJTZofQD8vEr8at0un4uAwaF/OfKn8e3QqJ2hC0dIUZpYm/sDujPP'
    'WLw65Dy6mvMykYiaIPgzz2goA6PSGQ1om3DZsO9y1pnA4iEOsmmfgXrunPWI5W8qshJztbIqPozUVKAKZqT+Eik5I+gK+83DDu14'
    '5xriGQRd2W7mI5PuCUzzIftWEDAYPeWg110CAb6EMOitKOkNGA7FYIGjeJ8RsUeI2/bwYLfxRgSfRoiG2qM8ZwfHdwRJcOLEEmW1'
    'enN0ckIozHqZI/JSVfwmlhXZaEdxxw+5IFGa2Cs/KLEYlHBtXdu2OEhTxw+7IG1drxZLLAYlKkLi90ewQaIJ94YQnF5pAG64royQ'
    'XzHBiAcIkhvF+LMohdSTnMosUml51pxVIwQDbpnwrZorqYXmNrQh/Mvtt9CTdLKtXdGLluR+8nhTCYZrEocOEACABlVXRlW+SjpR'
    '/iqb5pnuX7FUCDjOA7p7zTN1pa7s/mgqYFlgouqwH4QFTqCnosaKfkgchlg8jAq5NvJChMlYvJDyFV5IdvxPNc4oFxtTw3jIjbmi'
    'Z7CYib08bW/q2SZmYjTPb0u+A8KSu6MNpyfQyJP0X6eEhAprwhkVPIv0O7mmbO05tRxlLb5fr0b9ruUoedlyjRVAB7stH+GJSgx+'
    '8+SSRvUHhObFtea38l4Cc81qp2c+P7K/CePY8HV+exLAARRBVUP6TQxNY32mplYguiMUu/SUQ3mVG59Dz1VECqoOCQSIte3QAk+u'
    'hcUcUSNN+PC2iMWID4UjOaqzmWHgLxtY5PIxCJgYexScVwS+jxHP8Yy4qH7q5Fs0tswOdBazU6tXNMlfACx0w81rdT43ZZgmifpU'
    'L18dg5H4UxpjX25HLZoFL/MCG4SA4pDD+aGTZpGrPIPdcTpUgo4GJW6rOBLOibVivamXUHDOrqbndK19GF3CiSlL/UCcfR3OLzOH'
    'EniTwVqexwBzehPGyVNdmOaua7MJ8bkVOwyCVjJiZfUzhSMSkMJKlFW3e63CD1ibsvQjKwg/Kju/qu7ckyutV1e8qFkjFQ6fw9Ix'
    'GQESXRHwrUtuhJ5kaGpPRpcZIk6x6EFDALA3+NCIwH2GzW2BDSA9i9kKDRk9gZFgraK4ZhapT7/XrLHSjK3qztxjT5w0c6OzhwEc'
    'kki+FLDHzzkNjmY2OOJzNLNi+rCRpFewWd4VYz8ekLzZ+/RDRePa9vLMtgsey7OH176nCdxuc6r37qku19rsGWyyO5I+LM451rin'
    '4tWZ7SzdV3Vpdt2VmXXFSOKkh0AyErspDNDsazbtlqjvifMQniMwEKNyG8NPmyoKf+TWVH2zfjzC2zjA9t5Kvl3jp/g8lNAHI7N8'
    'bNX41LveGoSj75a47kaXE7nYOO8rIpFE8T5MTBvR2zWWVfJwWJqodub4kdV9yzR85EhoZrJ0o5XGei5ea/TfdhSXV6ApnbNwA9TL'
    'uVwcGtC3Ym/mBf+z7uNGQBA4nj3oVqUm9sV5LJ5R/w2r/fyNepV0ztk+dw78+qL4WS3rhutTNBvncOjVeVN0wRtDV+Ig9o2rdqKB'
    'KepBlAqRuauGNAggMTu0w13leF5O6DL7kJ7ks4mZ5IJV1yszZsQtfAZLO7eJ+1r4Mp5bfQWp/ObVR3SE+1ooNzDn/M7EWX3jRKDb'
    'zQERVDkiKi4xpKMTMytuJV2GOOG/ZwTFPnnG50pElpqMWZy5OANDF2ZSJbcXaPWMl0TGOpSWJZVZoyJ2d2fG7o4nDhqHzTq5BMdE'
    '4mTP+hn1rU7MN0wnDHHQy/upF8gaSCPHO6txs2+sTLcn+hwXuU1feEbczVhmf/u3bDSsP17u2WDAKh5KBmxnaXR91j4iHshSA0d9'
    'GXK/3dAKHvpaNX23QWfQmtn4jU3ijq2Npf9FVEDyyhqBEwyqY0AjYqRYY4xcQ1RqLimm1+B88Rja8h6L4slrbs1v7c4oovxRIN4z'
    'R7A6dnxx1p+eWk42dtviVvTwp6+XX5eio0XjF+DHWuZ3S3CS8JkKXsOC4w0tGQMZlMCSSXCkqe5Zyi9phTRJKUpGq83o3e7+QctY'
    'D1/0Ega3fQHuNybV4Hgs2fX6yRS5ZieITM45ZCX7IBKJRPsEk9Gy/CH4XY7AUAHa+6PTzCQrVVKc7UejtWb0+mwyGvSmOA1wJov2'
    'r4kkHkQvOx0YaL7cey8lnzajPcjuI/DV/VECpw+xdAa3GMVve5P0ZHRlXTmCsbbsmCQGAIeGSjlDrngwGZU4lgI5NogAGV029/fe'
    'v9n5/DNeGlEC1d/rsSPFIy5L+KeWnY0u0T6Gj48gPGig0oipOOYPB9dj8ci4ibpp1pn0xui9FdV0uc02NqKE5j/OW4TSAk8rHLda'
    'KzqsKfapHeGWODK9vH3/Yefn/YPdz+yiFcJGC8ulnln4uZdw1HmR9V8mE9r9N2Zty3E6nZv2hYZ8ALrt4g1kZevItXfJWmDGoC7A'
    'oX3tC49FpETnYFtQD0DZYBlFDZLN3jmUuaAQbcbnkNJSA2gKzkLDwZw8KhmH7ICpZ35vKfQ0HIgT6ScZZ21IA8DLnK10WKOLlaOv'
    'EgguD4vTi9o6vw4r1H79+381H3jWm26iEqctq0noIJqiQQBMgxFNEA8HbN8Ty5pvR4fUDtxFDtWiPlgQ14GGbRhp0G5hi82yQnxs'
    'YWE7Ov46fHxjnu9Ec17XWHeyZKZZOwrMKRKdO/t6zdjT7VlfBCMj94hrpBYiH6unw4mrq6oQJ7e/n48m8PiFlpGQRuzAv6TSvbEw'
    '37B9NxR+7+qhHtEHXyLh4OI65OJj/8iIoCtyEhM7WQUN/5Shprx4Z6pJfT8AghWt+De4nMi43R+1xeaiGIdyFjgnsnVJky6DkxkZ'
    'mtAq6PRm1518GXsCTUlHozqWxBpVWXKkIxFkrHgyYUL2PfbvUE9DaaGwPfmIl1kiGMn6rlr5rW3B1oah0ysae3wYtB7XjxoualEJ'
    'b7LUtpCGJhn34jFDRXvEaoabu0BFmkssjM0iUDKFZr5OphxipCkXHjg8ThpIh449VIR2rJlUCROn8J7YlDYnKRzmZCQ30SClW6xL'
    'c9gjkK81WMXFaU5vYBXD+GQJd0mtappEK/xlSUa7dEBbhAsDR4eoB3qI7mSqpehReMkZUsVqWLPdUOv7MksWYdBlfcmrv0MU/CTW'
    'BfA4daQCSfJpxvT5s5Wn9W9pwzDZ+MhCRVVYUgOG3DB57M+hS2Fclidtu11/cymCmliL2Hi7K+V1A1f20aRld+7Oc+yZNEfnQE1/'
    'a3Khemmk+gFlzDTV6sMSjH9T4z1OWkwjUxPSBOMbpupBCyDJRwGJYqaXsfNIQuBwaXJIe0ZmfWMBB0NAdBNDUi32rugM5q+QLdSb'
    '0fuToH1tWNwgpXDP5D/m8cRgIoRkYacfFoFzXqHvrJR3QJQWNYVsoJJqoyF5daixDLRmNjK2d9i4k6THwU2Qo5muOPEOHCFgq1Kl'
    'uiTCz1BD7HROdCZS2mJIcoja11QUqEkFLGn/pBFNjBtiMjQAYhkzG9EpaTd9dgvtnhNNpe7t7KYktCii6A95aVih7rpj3YQxoRRV'
    'OfX0A3bAZmWiF59lQbyAzbBhgNt/hWs7z/nleKwEkS0HKAPjuj+aTojsry0TZlrmr9t8bjdxWadDJMH78vn9a9oMGgbheXeyBZS5'
    'SpO+Mahu2twZDOLBYOuM/KQjiY4RHJYbRgUq+DplZpQaZBevJCJg7UzH2/5V6Z9yy26a5aIjU+jbyQvdkppIYjJt0Q3Flrihnbog'
    'Eho27vUCZbUwGznzlir3fsmCf6RbL6JqwKbBJoT7JvBkjECZX8MovAhBnDB8IRzXK2RGq8h7peT/ZNRmqxK+fcye8NJirAaG2zDW'
    'UE6MB7bNjqDAaMAKgxGudtZo2MFqrt8C9ItoUS4Z7EPs3zK15VqDs+IQZuBIhEu0VpMU92OdcKDz1Lhn1WufzRmmnuG07zszzEnF'
    'FkUn/Wl25qnU/OCOFpda5kwOpPl+F5p8BdQJL7Pn+H1XoF7C76WcdJDjpgejWEgznw64tBeLfFNK6seJ2HXK2KTAZZObiS1lwpJF'
    '882DaUNbaotCYvq0pWdbXttnLqGmXO8nMV4oJyRklQ2PWyT1ePEAJ0CXbM/Q2eBsDf1at+ExHL3iUEcmIX5umMZteWQ27O9aUYFA'
    'YwLDzHyik540UdcpAUpzloJW12CkVO90n0xqAllj3USvgJ/AD4Fv6jaNnxfZhvlOl9UP09KciCwsEIMjvcwiUYB4STGM3mzGprBK'
    '7Zu3RWnQ6Slxhrkk1zI8Bm3P8lcVArjoP5ap2nYlWyx9ipmxMlKDkKO6ccgi8N2ZtdtLScYbbgc2Z699X5lJU0TmfRPreAYUVGy/'
    'frlTDHDPVs5RSqkAJ5h0NfzIU1m4E3sT/8TyW28dwHoQme5Le+7qdjjhsHnrJzJ7FYu3R5Ocac1aPTA0uGMeXFlBD7E0XN8BSgnf'
    'yvoURDzEupvfusoOzlpzvgGKogM9BsQ9JGwaR+eCb0qVMiKWPAv20mg0mSFPFPgvCZ6EBigdItEpW7qiBLhzQBZVa5qoKoRBdKkj'
    'IiiUkB0laKzaut8AcVZUuKths0qiwtkH8fDsyM6r3ER8Y8DunydWJB6SGSiVL3on2V7ObulkYPrnDNacDIR1oRcApWfh7WZv8n/o'
    'QIA6YZlm3ckqKuFGg5Sx1Kg46hM7xhN3x9jafnkBjwcIgpTN77KtPdzeJ+EVq2b5nqF7brjISMorov8zsUpIKYcKiCvO4q0/73ze'
    'f7/7ad1vatCjEeZiMF912fl6Zgu6zKvhLBCv9im9TCdYJl5r3WnCEAeesJDZQva5Z1UXc+k01AsZJDi+8IxDYJ8mhAimYxqXH5aw'
    'ph20ooUD2ONoxBLQ5kmUBSC7EGitZ16UAT1ZCGoApnhPsjZ5JSSXI/zORfDEK6eqQlVaieNgld/gHF9BCa/6st830rwgpqlaTJSl'
    'igHJR0xE+m40UDJRNkzgYjs63hXuQD2iGrq6XRMjRgHI7ErMig8jiILVgTDM7CnIhpB1FvNqq0YrxifJO18Vjjssr3bhI/2gimra'
    'Z8MpulcmZ3Cttm7cR/wogpHxnlGxRRdeJ6wVsgxViPx9dlrvv/ewSKB+4iLjCx7zQSxvA/nhwSAIfyaxN60gRS3IAilU6ol3cKeJ'
    '+qjKzYcuUcLfbtnE2BLJEHt8u0KfbccazI4JZx4QMpXJdnsyjBrsL4mIZabuu/BSPAmxTSA6Py2Jzuv1defa44mwT5rmYd0Xdcvr'
    'Tyw0Nuqgkyb/Wi/yamrGyea/ytsR93tmo4X9DsCwGTcX64+XJRdVGQ4ePRpYA0+D2ghL0XSujcpkPwcyFOSMKFK2M5y0obH7jgok'
    'whK+eoxMNy3JWgaHq0egaiWoJsfPfAAJ0YiCWJulYJpQOMwEGWHvp0wdhWAji61smlD9VdYPFbYMYkfXivY+/SAWCyL+gHjexIcM'
    '7RY09FN/1D4YvSKU/vwZHFno0cji96DDJdCaQLu5FVBj+Iyt+8wibGb34dEkxJ4cO6pFa0f/0pCNJUCjhmhoXBohSV9mcOLyVBZ3'
    'oukWve5Qp6TRr5DAghXSTKOK/tkqtp3ElQUllz1WBBviulnFvO1w454KBkGKht051Oi9bJSMN+SiWl7bhqOSev7KywLcw1opB7Vj'
    'ViVgogLz8Xkc1fJ0CARHtwhdYOxzfyvjZnqzbrhOH6DZfRftOwEVYGuS8tVfYALoWkqHicRDpcK6JjD0vJewrtKLedKSYOJK1gVZ'
    'pkp04nh4ygql0TjPSlqgsaj8cSFSOc7ARjcHX2YsAmdEiJpNeYChodTZlEipsNczudsiYQ89Bh8awOmY3cjo0McqQeamCtKxco7M'
    'MZ8j+DD9aLxNOmmvr9kl8fVJtFYX/yf/65n3tRjs6ngjuziNrgb9Yba5cJbn49by8uXlZfPyaXM0OV2Gfm+ZSixEmnfu8c2Pdwua'
    'lB1P7+gJLiqvRld4lPSt1NldhIdr9/Aj/qHSWwiFgDW420DDSEpnow0NThWJiB+pCE0Gp00Zao2PibilUs1FGvQ6kSZ0zeWb0/xk'
    '6UVjhticqnsyOzQo+N6X5AWYTaIjuHgAoBLq5kreT06SSY+mBbcxG4nYBKVl/vfPPzgBrmh0uEPfcS2je9lCkjwQJC2yFBZPDuY6'
    'c/S+hAgukkyNsZq8RZxC9Im0TwehKVvF7m7mrR1EJ79ih38iDFjSS8xRba3rZXSMBdARNNvks9i2R8O9BWklEQjFZyW/AqFAdMc1'
    'z1ETGuaSzbB9um5LcNx4gmf6Px1+ww7ZKCepaHeSSITsmDaPS1dXcCK60nZ2mvmIDz1tpro2jzUKeQk/eLbnzp1nFjviXRoCSQa7'
    'QGDjhHHojHoeS2DyUpfQgD6wQ3fpKOQmF73TBFnMrQeGSqUPsQqvrWc5SL8bf/ItN1a6Y47CXBQgGDSwHpJ9mFZqAc954yUM0VDW'
    'kKcmF0mvz8ieBamQrEJKxBc4tVtzbq/Q2V2ejfpOcxfb4HIajobPFmdgQTJ5qEbYsKRhfEEzvnWGIrHSqL4Njm2ODugm6Jzzxc9U'
    '9OpaNKrxuyZUcLSUbEypAYQk/i+60LZt+BSYo6lNg82E6xz/4qEzdAzN+SoDH/tw2gTS244kUwrbxxzyBh2xiYz5DZPFnMCG6aDd'
    'MCwK+8WyblaWBeoju3J0PO06NaN9CfLaktSSXvxHb8omlHqpmWzatisen63Vm9FbF34mQ/Ryjd0DKkIDnZtFbmPFJco5IoZmRgVs'
    'KmsuUAK0Xt6MFiTi7QLGhWSWhG/h+cxtsOMzlHiyJ0s+JcvWgz+ybt01zCrMPtvYA05E9X6ZwL2YWoFtMquE2Uy/ncIRPDMKe5dH'
    'jwmiDAeOg78zKMUvo1//l/89etXiTmj0EoXk5XqED/8bPsibV3X2Xz2T3kwIR7yRIQ1HOg73gfX9BOsL+WhBemOd7AJ+Ljh+UNR/'
    'nhEw5rnPUeP6gekQN0+cWFN+EZx+eP9p5+c3O29ffvlwsM+uBfLNoH6twj48w66VyCEwU1PyniJoH4E1rX3t6KiiGqt/w4qoYKrP'
    'rogFuK/DRjS7uW+s2BtyvbtwFUXen1lPeG10doj3fpJ/NHHa/W0wkeTiQzoXR8wDcaZATj8oxtLxITEo8ukQIzuqi0pXP8ortmmx'
    'eCj+FI80ws7UWlbDJq+vfiGInBM/vtHHu7oa+NWr4ru/wsnKAqvNgWfQ3YgGxKwh7/0gML+G0/8ja1HeYHFYxtEU+i6AXi8DlkBw'
    '22nuhyRPos40gx8+C4AN4rVozJHj0wwkTQwuROLoIs8dUSR1DQ9vgkn7BSRiLn7TOrg1G7Irh0Sb1lC8WsbfcbzSeGwI3txsNrm/'
    'IOK/CR6/GXFk/D7hVQTRSJC+2zqGeyE0OhCZegHuQSXxuGv9HmLKgDfURgT3tbgx2lB+y/Ig7TPuNG2XiDeo3aqo3FJuvGWGT5Wu'
    'eGGptwEEdeWY2uf+GAcmlJobKeQl5xioGeFKMCyJz++5cQQhAsMRiLjmRvfJ81yoCPU94PBxmTNUcKMZlEZjTA5mzaowo7XilFar'
    'p7TmmGdPQs3wbiP2+vM8K82xtuulBIFGtTxsb9AnbFOF5guAcmIBhcOkVw/7hIe96u2Ew190YNRq7aWJypWpSzddNx+JMQO3LSHm'
    'Mjk6IiwS1CNRzOnq/8JXlSUaJDGLo8jkPKObbEDogIqapm2ZdcMxJTpwIir0k0YtkxzempOBQwlIHgQv1A0GfjAybcdn+YDXXMZt'
    '7bPssOhy+d3vflcj0Cxy/RxsWHjPN7sf98BUEhsuQlSE+9ln08n4eAOWk8TCZsmQyPNf1HEc/daJn+WPxw0JzrmMt0Tz4aXDHK8+'
    '7L7+E/W0/FO8d/tu7fbd09svH253P9x+eH/L3/7nL7sHO7d7n3duD16++kD/vtt5+eb24NXum7/eHrzd3T24PfhML28P3ty++1x/'
    'vOyaTrPOR8mTC2dkXgLQlLRnjiKND79+PX7y8+HXo42t26M6E6Zfvz5e9f15LicJBBQxcpt76IxzMnOrQPwmJJIL5ucH1qELLUEA'
    'EoLDNtSZuRX7xkQO12kU2df9oyfbdX5UAbAF0gQhSfD/va7+alsDH5OAgiWXmybGuxkjwEgumlptvRIJB+GdTShWvDwwOT8RAKd5'
    'sPOXg58/7b7Zsb7nLiIlETbXkRhyXYMyZquz3TYBc49ISrGzzNLUy3XLyj4a1qKJrvdn0A9lt5/Iekctx18Pvx4e/kT/Hn0dHi3S'
    'v7RbSi4gbgJvTC/6l2hNN5l3P87rxmepZrFhVIh9ZJzOS7N/ZGa/84EY9k9mAYq1Hd/TQQ5usa7vDYepM0GU/aG2O/Bo+MRr7ssw'
    'c/X/ZLdNfdg/+LwL3tCsFMAwrj15UtPG43o9iK3rtfPeb2fnY6mNBzSxXxjK+z/t+G/e7Hwotvqf/tMDmn1NK1hzNlWQOsm6OeO6'
    'ddOsObJcqMV/msr5ZnHtuMYC1+NjlnNyGXCLx8fMKB77L49r63aLiwN6WXPAb1OgitMAy4Fe5nSu29M8pVuMXsOTxnjh6Fw9JjaA'
    'bDP8WMpzuu02hxjdlB624WIn5ChIU7wTupR9CWxz0BUfH2pJjvvBkM2F7o60oudMF9e/Zkc4PmXJX53aL8J8CXY+ejBn5lA7VLke'
    's+HHjw7Rb3F9skmn5vdQbPnV54qGv0rk6iiiH6WKhB6/3O5/eUX/v3f78eXnPxFqFLk7wmkWmtLtwPg2Ht/kob/gHd1RWoDupYrP'
    '4ai1aa3hR6bw6YYABUtWkCh2NGu9GBPJpEOSMOSCncFGrJZQc5/DD6d9wRcTxLLxMXS/ZxCN+MR/eF+bhZYgW2ZERI2ZOrwbux9q'
    'AoG9xcW7JrNDS0h0PW1HJhEQHyibz0paMgzPIvuo+D1JvnfEVqThOTx3ZDifDocZrbxdfPzK1n207yAC7HZbxFp3qEWIHyYGMQse'
    '8Z0I09MJhOuKdGlc9VI2pa9DueqHYuDVrnOQ1BK13JGET942GLCcNTx/WAAJxDhE+1VAJEX9zF0BRLF1Le9cEZBYbCJrTdsahE6C'
    '9UUtn9TqR3w35izsRcF8YmdxZLnzvOua1sCUaV9wG69d3vVvrAcJ8qxajs9l3TSIPx7Z9dMt3eV0hX+95SYer379elsr2lkdohJz'
    'nJKfx8amJ1I/XqSxhfinM+qLGyOQ5GodkXrrzHf3cfvrmbvzc0I/wkIWc4wYSsncUP3MD4tPg+FKWFxe24mNcG4UUnbJJ97YuZ0l'
    'V7o4LktN2nGE3VDT8cTQMtEtrXm9ADk+ljGjqN3y7ViuzEf7thaQmYe85egW/HDDVHbjN4NeWoI/drk1ni4PW1zGVzVVHzVbyFAX'
    'wDkLMk3eriKoWzGJxZh9Nkl275RF7KtgpO4r4XMHylzNAqrcS3UnMIF6xWvZxPWvIpf9IzGLcK4kHZlRYKamjDZupHdNXwKVrUHn'
    '9qbmKcb1uWRn7vsZVlGdFSdVr+c9jy670lCwZqWuvJW6qs+mpt6t+UTiu6cVxJXXtP1S7MJc6VcghgyzypeVeSJE7zoBHfE7E/v6'
    '8c0Ve+8eP3mCn0+eOMQ+a9SOz6x5gxCwpL2wkMt5Cv2chTYRpR2x5PbDULbkXPT9YzqTLCb29h6q2L+6Hkuyv/XygimpTFTxsVxt'
    'hgT+OqRXtTk79+WDv3O7H/yVMPdYbc4M3n2uVWxgzdnS8KIw5pjVBPP3fiviXtIpdGo/I8uC2aPgeg0OSgXBpq+0MgdnN0TKq9EI'
    'qbbCPXf+vEJlfFA6Ts1iCbvycePAyJXgAfHzmMM2IEZ9P8TcRelzfDIIYtD7GJDFbANdr0HXHi8PTbVZwBcKsusFqxwRcG1GbUZY'
    '25KBgrMIFQRIUqCpod5vIieRanOAbBlIv1dzEfj9D2drcjZZyNQywqYCBjPZYtuiOnDZIY+ffDBqsNYTNp+QAl4MEpHi+8jM717E'
    'qx5A1X7HN1pbbdVqFbAYDD+oix5/940NrFW0ML8JVzpypDfNHDJOvmeXvOphDhgso+jPsJtZL3cp6HoTJ5kcTWxGZc9IozcxYsds'
    'ZASNHAVadJBhXhsmcyoGGHAFxcXo94I4UpmPLvhs6NTko6b8kdQoblEEq3nHMDYZsBPOt4sCihwDTFfdLz9r8arutG2vuZIg/xtP'
    'XtXSKbO1vR2t1B8MyhZ+Nm1LNtyufNOD1Iier4A2nQloweIX4EqG4Z/L8q5Fsq5yTrWR4kFFuXqt0KyHe7xWS3s7Bx15MnjOiVle'
    'MaAfoB471pq/FGVlgIeZ/Rv35mnjThlG/qTh7wXeVIGwz/Gp1IY0yaJ3Bx8/NBg+TDpAMTrHuWMyjbMD/jAanRKX92bUQdCgH0cT'
    'P2mptoaWYudcATm6ZhJny8LNaGnVs2HqCxFLbTMhrNl/uSTMcHEGuYVFamJjud/b2lie9rdqErpyaYkNlwsR7+dB9rwbBSE1fb2A'
    'v391D3XfdxFsjLc2elvuNthY7m3RhZBmnbgMaxDwjLf8m8E7TI8cJgrJ6OSUs4Ax1FDNs1VEnmhFohM7W8MvIjTvDqWdIxcbFS6t'
    'HOvNLCpLn5JTSJxkgHyiROokr3nERMHyOtwdrxdEN3feoAWtbvHe1Au7uRHZe8HfUtrMDdpV3dDFRRNLz2JCGbOpu16EBqkrNcwn'
    'byIGQ0O5bnb5eKPbu9gyE9pYxpMXQYfN1uxCufOG1nF4YKINyLfG2UnU7I46V2KH84ukHv/Lxw/iYdeMXk2JWENwBPiNILE1MoQ0'
    '6LZDmAbkNoVllFxjsDzFTCST0hDmNu1JAg938YJn2xn03QhOYjwds5U2HaI3k94FfCeopw9UN909OSHetulMw19/fv0zk66gCON6'
    '2RoKSrQvdNifrgkrvfb9c5drEwd6KNkOsaP0jX4sLjJDaPKErLui51L0nIq+oD8oyClao99z/LeVq503r168eLq2Ev1Ehzfa2uKc'
    '1q1If65H+eGQE2by80rgxgtNaD22kWc6k87TNRzH69xYtpsRrVy91f+t+2jiinOmXecmmYhdmUMayk8RcXi/pwl+f+TG9sL5PXMR'
    '13DdDtCjkAkU2DxPPS3ZEttb7HTY0eWGecMOi78nYig8yU0yeA7an/T1iSPXi5pTQgi7netJNKPRJcRM70bTCSxCNjai1dXo1rz+'
    'SKdWImXTh+/d+30JXxJjFtFqkJWGA/losbdEcf01TSC1XopW//hihdv5I7VjSnwkzHDGN81qsQ83YNbycbIGho7vKnTnWLACxhYX'
    'FlqzpigKYnUCbBjPOiwv6jblWWyYoPbFrRrUEye9lhZtAHQAYwAg55dntSupuD8gEG+DyNTTui+D1CwpblMSjuiPBz49r6aIosKV'
    'HV94AW80OWKQDVKbXiIzjwm8UAQb3DoIR0VDip/CjPZq5dnK02ft7w0l1jctrz6PnyG8k2k4+PKca75Yqf76gm0mvPH4H1fxqcei'
    'm3LN1TXejIqPNNHVZ7zQ1S3j+wvZSUsHVrSxtnZPGRrE2nPxMSiU0QwLdLCUljbuIaUN75gVfibrtLay6q1wZ+YKd8IVnvHlRWnt'
    'O4XlDRe/U1jfYPGDj88Ki9/xF/d5efH97xhs1cIGZZ7dUwaL/2L24vttPaOZCAoIiwiyU6mi5ysSGYRBl/vTFXUUcbodb1j2Ahcz'
    'fU0Yoe3SvTslCjkGAyY5FCFtbuIO+KADNpk+5h7ntTWTciw4yLSxz1e+B7DYxUnDrReKoLCAaQEAqgoVOgMkCEIqtqGbXVpcz7Be'
    'orEhFSmOA0vBdYFo6jYqGws+jCDpatDfyXAw+GbNPPXt7ze2Flh929GoXbXfI9LZ75PBeB307QY/9XN+2OKHU3lY4Id/nY7okSjV'
    'DsdGLNjVg6zi4cKPeU90uv4V+uPPn/bBW6jnS9Y5SwdJ1gQlSUMWBiZjT5hLIprGkxEildKVMOjDNeb5MucTdvfd5wc3N2Ky6o36'
    'dUhjk7TPvosZ0jV5rU6mQ2PWc7xx2Zps0T+8pC0Onr25ACIQoXvgXCMrHTMFTsW28O/E97KhTUv4PoJ3RgMJaMS+cZMjMmofY/Qx'
    '3pvA1Im9OLbltbh0XLYukj7cffjb3cKyUr9E43Nb3LXUprGbsYz9UQzSbi/xDUJvFJ1OeuoQ551C+H/Qon/mdYjlzmVpgOSXKime'
    'UYw78LS33DImOXnffT84ZWcxm9jymO3skWWyyVO4U/W4NKIWpqXxhRJXuzU6Wvo5bqmhUreX5QebCysL/OuV/fXB/vqMX1vHen8v'
    'orVxi0YCSUmHXas6V3cLNFn+eY01RwmC771J1Ovi7ZC+Y4ybCwronDZTC3Y+XfwwScZnvQ4n86G92Uhap96bD6yUGo5es7P3y2yc'
    'dvLNhVVUX66s74/VNuW1CuQXTSc961Y25zTokplTpcYXC1sb9Ks1RrP4MbygiWHkeKAB6cxXzLRN5tBlVwLlMQO/uj9wvG8jpV+v'
    '38fY8TuatDioNxqk3eb2khaRggiohZ/GcwkNex+Wg8aKvWRjWfOrk8kAfwkBRFc8+Gv8y31ASjJrs5dd1fEky39IR4MIPzYXJjSU'
    'BbxPLj5kOihTREclnS+b1fTHthxs2Jb3LBsvEMxoxAK2QymeWlM3rfKE0nW5N6lCLvSvhyzcOa845GUc0n7+TJk1cWbcYrbzBV+0'
    'bN0fJzmhfqSUDz2N9bKBojCZvCaa/mUer9Q9Zuikl+8MppjKZSM64yxqP/K/7+oeZ3jFNvL40rk2OvPJaDrsxngbPYmQpu1SZa1U'
    'ZEtbuJGqXvkOkn3hI1Wgqa5Lg3gBaYY1D5BseqqsDW14YY3CSKzBUWOGYnhrM+NmasVrJeH5SBTn07FGs4e7DwvEOee5MXNH6+x5'
    'h7VolxCteGwaIRg9ebYG9DTDxsBLCygLDbe+Jq00/tBqr75Ye8EE7urTP6w+d9EZEqSFovprvSHx3qvN73tDfywiVt6sUNUA6Hpw'
    '/mn10xN2W4WK7z1XsIIhd40FaF3BOjbAFqtDar1hXFODrKmejyr7+kEgix9o+G/jFE6A5khgVLjAOVphi/1ECeGuARdY+57jovEA'
    'yBAWGmIrZOFhc6eSxm/xQhPdFVXwknuZM6x1xSFDndDUtCowAHtv1lzkdjSkp89XCJSdbF69Gl4oS7+IAibbI0yCtQ/VxXBpllEN'
    'p4SCwXw36aqwfbJZLpyf/7iy9tyM+5Kopaid5pcIqPjyGcZ52htm3+GMSCwEFdfCXYvlbibWQVESCwmJ+gp8mg6c6Zor9ZlpCDGY'
    '9GIfWMoCMluOtB2IdFlNJL0YYoLJCG7nzsmEJghB4202Edu7MpySpQf3uEYte+M1HEzwTpQMXdeJ7QNKNAj9UnbR07xuCgASp3WE'
    'ROyokmfMLazL8nGS2jw5p/J7n35Y/g97Oz+wDTSNjJrKEfpfEtFDAOuwCXogyitT5gj2WPWqVLPsP+SnmX00NCL0UHDsVTxs4Ao4'
    'QvVQBG+qigE6rMWWN4C1qPTmQnz408LRYn1h+bQeWraYoSJkCbuPzzI37A0KHuv0Rt3V6V9TVgK0GPdz533u+dGWzV9wHsS6Zfkn'
    'h1W+Aq2oGR4G5uGXsBghm+1iQUZAmvfRir28cfJis9C7aMXyICd0zwWdZjlMCJKSPudkDRzR3TfJterZqZc80QPXb/H8Rg40GTl8'
    'uk2oEN+ne13XjRemaAxjt5bYWywM2FVG7C1LT4gMT6mPy1ZxMqwoKU7CcgNGx0anC/wKsYxjOhM9SR0vXpsT1VLLaRKymHNu9iZw'
    'b7Fs3x4HBwu9G6483wa2jmh22KvtSjQaRJi9HcFVlS6UrNMj4puWMxv1k2yBXp29HGaFV53Me17eClpue822C9963rde4VvmfYME'
    '9TwtFAAm9Mp0Rn1k+RWmcuX7509frxaHgrvHq3FGS97nZdda12m/P7os1ppy9oFid1NTCYx8Py1WgkUwV8umY62FmxqY7SX1OXTc'
    'r5Slc0V/JBIfX/NUL53oMxMVAT1xpfTIhCneK6Zq8duRHgY5d/KrluebBtLFEDmAJFx7DeMMxllexCZbb1xnugLX+3fq3L22/DRi'
    'pj1jIA09qf4y6KsLFXVdL1jg/nf3j/rv6iHliVIyUUh0cSJPGhLXpF40Cw6diO51I3qYI5Hn4uAbM853CFr3ajkjTgOVLGLZm8Qn'
    'tLy/TSg0y0fIYczf6ic0w2TzXPJu+laaoWXkQ5yDsI8xWgL6bjabtJFtYxhh9tS1+mB/oYpmew9v9svchqYPb+hbnJEqesq+oacv'
    '4TJ/2Zvb8mHBj+To4T3BnWVu20DxD29OHatmN4dr8eHN+b46NSPIa7PoCA+12TVf1oIDeUYHZIILJ5q0RCynbENc7V5V54hIFeOX'
    'nJPh+Pn02h7881vt1VTGOEKvGhIImWkrvZpKWKc3sLP0hDREBDHBBFa4ydQSxm5YeuHowdBbbhAviT384/dr3+uc6On50++J2Hr6'
    '/Ps/gNevVyEg30nJW6uT4sbehfpPNYItaED32G0frk5FsRTLo4youySfsjJuruuLo6p8orrpuHCvKIszHbzvzvRPchwfM+irtIL9'
    'i76fW/4F387W/lC6WX/Y1TXHzeobHK3+RzlAWU/DvZhhgB3Vb+hwqFRgyRNJxFg2mAGWtRaIt0gETMJSTpaOt2hP9vjE82Jb+g5P'
    'd7bE+677wo8iljW1j71x/mMeVTpLY4XOOxxYmj4Iyo03FQMjaMcKWHyQX1XI8MLjCMoodqSyXkKr3hm/z1GpQQe+XrCJLnodrTrX'
    'mjleXUYbS2CQi0n6EN5t1FWcI2HNSr2iHxs676Q/Gk3i2AEPr9Eyj4Uj9kwkOjOug3/JCjwDPWa/bC484x9Cb60wOwVWZnPh1Vv8'
    '5zgLK1DlRnnNa/loDC0musXf9ijPRwjbXZtwtlaOTANr5Xfu559r4uXGXkPSlqUZa/+CsBJphf+3Qwo4DHm7vyV/BOTpx4808EtW'
    'NWB5nvAK3GE2kKNuLnSvEhZJMgOybRp5z/JUroYPpfKKLY/toVg0NV/JIlCLuhxClLoPUuxDco1Rm1ZPeldpVw4jfXxN/N7HhCfA'
    'w+KRvFgpDgI3ubKJ1d+Xw9aWzcJUDPuHSa9LY8bTKf18Per7y8aMnrFMZhAys+J6xxXYmKCacAOAvMIlO9UA+U2JsMdYM7gvmOth'
    '2q10LligF6uKo1DJZygAGNOMhYuIp0eLkAU3RzhaTvTk9VNFXgz9m8odRHUGRF/G8hypXVfqUXuSJuc+scHjWYQRYJlbOmPEU5pR'
    'UJInobRY3mFo6Sigd4pwPqwA8qFmljXbvA985/B+oOtmY10WcpzZu6EDiamHCRAtHI/QGW4uvF3Df8AL0gaDSCeAN4E5veICf1SE'
    'CaUObxynQ43g/jPTgVHdc9if1Ko0C9AriGW69OoTtXfhjq/LNmzwxskDW14+eHHvKg+alh2bR5+A9UjoHIQXHwBZ3XxiMdU7Diys'
    '9fG6ZvaCxybr6TG25ZvSzp/QYI0Xmt1UZi9YxdVqHThjCTcFE5S04nplzLTJ5Jp1MOeytFlPn68YCngzCu6gwo2R4A6SWrIc41dd'
    'H+9V3Eqra9619MIDxpfP8Z9uB7dTCxyKrCKNNToW2xdUZ4ztQ11ZwbZEg4Fs6Y9tWmWltzEd9mepB7V9urVR8nid5fNqAiJQp3Jc'
    'uGLDrtaNY971pAi3UO36+g3Or/8E99cCf3UvkUxt+ZIiE3wndKJ9oDin4FhbKaepFMl4wgG36J0ARd2/9jN51rnOtA44Jc5MRdc4'
    'Z5737A13PE8spKwtWrTzKjRiAbfMR6hI9fGNvfCeNoK5bEdrNIKnHJYPzWZnvRPWzq7UWdnMSt674zq769BqykBmsr9zHHgxcOMa'
    'arbAZxhmOuDOXN77fHFLfp+wh5WgRHFPEVVRhmJz/vqCy5tAUPMgKWa/IMWsinjk8YoB5vmtt7XgrIfsTbVjsc/Qrcw7A54cyl1N'
    'BuULj1CN9J97OH+1ihXxcH5xNnM8kzEQ9UtWNnK9UipTAL8Sr1rAOTNY17Knslmuu0CNnO2eGBuIR0UXLPZ/K9iAfCc5bqyWo+hY'
    'Z3UsZbMQq2Lx3A294Isv6r6qhQPOERh/J2GM7u1vpeFF83PN4DDAjofwRZWD8Wrk4gZ6BgzBmhRcynhRAturKornhdie/MMGNE5k'
    '9p1jobhLJeV6zJoFer/v/4j/FE4NxVeNCZxjXBQgghmd/dZuLMKp9rlzHXuSQBAymlxaqJtv8irEDcwGPnG7XnLlC/xiDebmvsx1'
    'XDvQ+JqhQ2vJ9Nn6UL/sXyKXL+Ijg0l2xh/wu6M7BEl+kc+Ugx9fcnAajiDP5mMnSHLBBjecjMaLf68GOM0CfTEennreYWKmF+YT'
    'M+HIbyQhQgvgJ7IQLwR9y4R15KG06JJFKtPEs66vl0ibbsnBhrpqtrm4sS5DwHPJvR2djfrdTA2iruikw/bFtmiXXA3DxnAyr0l8'
    'dyf+7l5ACGYN6uFl5L9ZA5v2/R+ern4Pg/3nz1bg0TGLc1t7tiKyjL917MUFK76Jx6A4TGvG5xnvwXJv0SAJeVAsagEtmumUmddd'
    'k0GwAA7yALBTSmiVIa8yJEJQbo3L2bxg8i2QytbYLP14tmS2iIuBh6sktauVItrfskKeMbqawbA8bZtQhEnARd01VxYkDB1Nc3Ph'
    'y8HbJWK/kHmtm/RHwxR2CtnC9tZ3sBI3zXDuDWGd4Y1ArLO8meDNZ//N5fg32FKHfgtv5KNpMfkNDcLlwdSnM/APmXeDpGF7AfwB'
    '7Ye48SolON3/RUQKq6t/XGHq5ox+P3/x9IVs9Pj0YwK0no9oWVafPWPh3kTykphHIZjcs9xe5klO++bCH1aYST4hcsN7PJ3mVgwA'
    'GDJDW9ZBs0W0bqJvlXwykoTJVbY4Cdxxe74pjnuTJln+MuslwUs2z9FHlSarHF6MOP4xGNRGShC4JfCpmaUyvUv1ccsar2CmvGm/'
    'mPO2tiZ7k/3yOiu+6yeM0/hdOlz64ZV/CS8XexgXn2YRLNjVHqa19vyZefg87adKzCvdq334rS6Hc7TrYSVXY6skolddKae0NRd8'
    '391c+AQo7/OCsSuJzk9f87z/9S2fBAUiVLyvL9s63+elxuUtt43Q393dYVW3Q9jAzR3O7GXVC2fZllBCyW309xUbLe+8Hf22yZpb'
    'pDRfk5hi9Z85Z+RI/AQrpHABJAXb5sLTNYaswCibCir19sHdRdUL1S7Tt6tvn74gCF0O1/FpxTo+/aes49rMdVz7d1xHwvcLBf6i'
    'chlXH7qMa2+/f/bH58VlXHtegXee/zOW8enMZXz677iMq8/9ZXw+cxnXHrqMz1bwX2kZn1Us47N/aBlDbXtxLfE1Kijj5yzoQ3CX'
    'mVVHzIinSX9fioQ3gZmF+Zn5VzhnFWMl7a9//69g+H79L//Gf/7zf6t5DgEnA4myUOumnR4NktW5MI76kIJ0sI+fR4Nk6FfU8h/E'
    '22Ez8jyW4FoEnr0V/REiy/hnI1YDNSw0MEhhNk+Qi5q9T4JzxPTu20HuWarSSA8RLfzpkZLJ1MaBB57/Qs1BoHHXtJ//g2U2QDUt'
    '+IseigLU5aPneXiw/geOhEyDPH2+UriHqfmi3M6oTP59lkT8TSqX4vENb39puf6HrId1g/kHKT3XTiWxl7SR3b2Tf5pCuug9vWf/'
    'ShThhCIMsaylMMjwmijT7kd8461TQwFsIotIvKYC+czcDle/tcPgPM3td8j9Df1+gs6L1/rQq+971UDk3esaIAxaJSjs3s1ueZVH'
    '/A3gvUsbPoFopRrMvc/BTerV9EHrzs7KvdP51fSTAIrPbEzkTP52APzse7YXsk3O4RsJcZ/Dq6PsHU/z99uMsPCT911W0GQL0QHf'
    'SMo+L2fmLSem3lyQZziWYa2q2qEdKzZiF8a1E/io8baKvziAYyA7WGqcyjTZqbjQPLuvuKa5oWUUNi7N/h5qSC0XcLOyo35lR9Z8'
    '1HXmNCtNibJvPn0cdanmzhVdZkO+g0NACnY1YIF7wpseMmSJ5zyy2ak+6WeMKDvCqtVM8tvfDlvc2G+EqY4MaAkUDGBKucEIUx7K'
    'QAD7C5GOXJYyGY/7PUkzvXwx7BZ6WdIemgHALiq0VfSAL7M7mF1vDFgM6lkfqBk14P9VWYU/UB2LTIgmyz+xUz0LkJat79f8wVas'
    'hgS6sPWLYTSa9gvkSmaVZo7DO7r/1FFIu/d2H574f+oIbNPzBsHhHkbjjAB3kn77GAxkovaS80wzPS7zUdo6pmsoPLg/4xAsA6Cz'
    'f8KB/fe6DFaLqC+MueLwXxnCZ1wLa6bFf2S0y4M0T7CGy4VtcAMqbzN2p4BuS7tUqvVP2KvOuIXW9uwglX7sjL95EWZPW5rsOlHy'
    'eDrpi+C4s5yKm2m2vNpcXXZl6UoaZJUV+IsteZX1ZuS1Xl3+y8cP+zz4pd4Qk+9A1tbttFjJ5tR/Lj8dLj37HSXZE3Y02QqTnXMh'
    '82lDxyov0m5EIzKmcfrlx6ev3xy8hcLRBeZr5qP3+7vqVlfXBAMIifDH+t1/RAdBowQdpZ2qgJASoFsIsdqIyioO69oKxomwqniA'
    'JW0Nx4JUVhIc4w8uxDdMg3LNo4JeVTIEgmCqa+grL2CPaV4IKpg+CEllmh00vVg+an5QCLtY+yfdcBJYvTrZ9K7GQn9A/mcre9As'
    '9SoFIubW5AwvRU4faXIyl1XVy1p9ASrhP/bGYcLqKLYZzbhAvUmrAokG/tSDZBZIoGO7QsAtaPxEoWvDb2GgeNjrdbxk4cZMwsYU'
    '80PC20BircgPAQ9jBnYfHWiUZLYr4jccHtkEXPdmiDEGybgBBtRmA//Mysb9T98Rl7c72BteMKeXh9s4MhRL2sggxbVJOppNJxe9'
    'i9SGWS7FVaajIYGVpcnfkibcars9V92KjZJIzd5OecURobrQjGxQ1YZzcP9SO3ZDTUMuS7nNU/5acpQjxzgWJJ25HNaU1w9nfu/q'
    'cOJYHyyL/SuczM6VboKo/+aM6dq7yZpuoRQwq73vjpkwCFL4zoPHBp/M0rnFcL2T+nl0SRXOet0uR902X+DT7b9HDuArU5WRRbEE'
    'enkUICJTvP3aHbVijc1CDW/qHF35Yzqc6oyLt4FFxmWfpia9n9bqdcL8tjfYW1UZ68xp5jCZ9JKlsyQbj8bT8REabCOkhOf2xCUI'
    'vdPZTbtAnWy3IrcAHXMMP0NI51OX0FucVdLuacrOFpqmIM9Hw/Xo8iyV+BH5aNSHNSPSEGZRnBDwcvLsy96Q8GEdbgJJTuA2RC+c'
    'P5lIOgR05Nps1y2NRxmRD+mQY7cQgdHlVOdtotnkDF300ksvODtUFLvDfa4SYxFl6fFL2KcmG+ngVrTWTyo+4nB8VIyI21eId0VY'
    'i8CfFhZR1DjBNFsMUbEXnoabzWU3OYUU/dgwhbbNjyXziYiDpqycWpxzmA76bmtUvV2ytVoSRBhomTutz5rUMT8QFZ7+JX58w2Xv'
    'xlfIAEhXSLe7c8GR/AkJIY1ebZLCbog23tirfyuUtggzxIcCpUd1gFi4B0AIfkKVfHRKSI+PRTsf2sylbJJFLxFeHL+VolZgY7WJ'
    'hv8CoHkRGoeIgEYtNaHI0nAv+712X9JqEBEkcmleLBnluol8Lmdz3cCHwxVazay3PmKsGeZU43kzmYZ6HLeoDHgSJAcjm3/ilHw2'
    'nfDJs4te3rDxqAerKiYqOIjrlubReATfK7BmTZ5clm83dYuWcAixM/6seVe+09hT8j+1sFsmqnNyHg0Qtcv7aGOrH7zb+bjz8/7B'
    '7mdEV69lzFYsdYWtaLFRXM3bcJr9Ad4hI+yE/oLAVnQmh5MoVy6Al1hyO3nzQ3eViWBqrZn7pTF102xdgxj1R52kv09gCjkC1WBy'
    'wRs2Gx+62+7O4HkeBmF4PokgG+AmQpM2JsdYl5rEUhGKbjAaaeq0oD7zXnoZnY0GafF9sbn9yx4GwuHusANYem7ffbBbYm8lv2F/'
    'wNUzsTnXUW2nr8AOUhvB997Ry7huY6wREzSkqz4jZICINYLQ0SKzH8Ou5N+8+47DVX0E0xLX4vEkPSHefYlVuEvMcBONhHETVqgA'
    '5A7H8LQwrHapoIjh2YPoT+u6neZdsK2n5W0t7inPlyvXHRSmTRPSbdvsgGfCybefWQhv9tk1DXsQTYfEbGXR9Whau+BAdDDxpYvr'
    'u4rDhGrImMJIoiWtMPZMOUf4OSf94csOhfqqsM9HYUkx/yucQ3u2UFXkMR4LQHVhfEzEjKR/+v3vcaTEPPhQPx5ZJusmOqcrmZdg'
    'eI7sJe2/tSrKw8VbjJBa0Yf3n3Z+frPz9uWXDwf7XM6PB8eRLjmlru3+E8bkM6+c1+pRL/s8ossjq7Mrjg4jJwyKzPTscJHpeLIm'
    'L9LtLTvpzBoJqrInDwOPDevMtv4HEm1ryIqIX//+fz6+kXxoTDoP2em7Nh3yAUVELyvKeLpSv/v17//X8XpI0mJjPdLOWUb7O2JO'
    'qnsHHOBcVnDVwH2thtZqnAP9nP3axKadtkNdAo55P030wMc3dkbxpzhv0gqxkq5ev2MWrOp7PqpLYq5jBkmCMr9Uzpb/dQkobEas'
    '9HE43tyY6deEEogSA6HgKfhEV8J0L2dwJ66DCLdkeC0F6A2m2SwaoYNQnE968AixARHh91PcbUWymNqoqCfkQ82atLeb3V4GlqbL'
    'm6Gmt3SDJlkGVNUUciWujXDbPqLtIsCVNT1ED+ZKgqTwCNmi6JZS6Cx/r/POtu3LC2u0a9b8FZFunTOfx6BbnGGCORM+G/4efU4z'
    'BqrSJEyBNzT5kM0JGmQg88t/QD7r+4rfBZc7ACrG/BoRs233nQjGyrnBP4I3BoOe97V0DPw4i9wHf/OWWpe3y7ONZHv43brw0d4b'
    'GpGVdgRcdpColQPcyLFg1NOIpHZLKhtXoAcOCC3oeGy13fbfCCyb5+l1JslYbS4vr1tdPp2FnZ79vm5zZblLObwcRgJS8UN2pQxr'
    's3bJO2w9drnPpm1UUEwCktiklfNGW6eLgL40Z6wxLWowT1d4ffYk4QgjIPjfBe68iZ5jnoc1ZrjAKDM/ix/ssYkfTPnUinB4boLH'
    '4/N0As64JQws48VMMtDXsu+iebscTP4fwpRojDBTBUEG5Ox4CoNLN6MiY+HQqMRJaNctHijivEaI7qqYDppZMuBr4gwx6JmLmEXv'
    'cNlUNRgPl3ryCjvhENqocfSUqzkRQ3vD8TQX4p4KypUgIR2imoyjts5fFAFETgUj79kdFV46EqGF6+ZnxN/qJGumacMW1HbA2QEs'
    'pP1GhHQUuFih9uk3ow8pRG29PEoH4/waX9hOseczyNBQ06FME0nOwFMvCJH0JdeJaQA63hNaiMwMXghQl8qoO+Izy/Sxb0OB5ab3'
    'YH9dbAFsCSr4hy0yTRg5lp9WyC5jZXRBkyjeEmVrKyvWS+aKqgxGF7zqhcnawcqIeIx0fV8wgoPGTFdeYlG7T54ujc+BYgnB9vXI'
    'VaSrJERZ9tO6O7B+njd/GI8uDGXONcKu7m8PAdQBUrELvo3FKB9rumECYYGMppnlozH0cMkp64xiz5cvxa2kcQcBkTVzrmIvi42d'
    'j1866yTj1BVXbgrjq88eYLs/nVgBlN9R3eSh87kqlSuGCAIQyiLrg94gnQTSJsixB9lp8XYAKuCPQGJ5gcrlSxmV8MnRgjT0uIZ1'
    'V90S/LLR4WhKJLTtHZXsA/NCuSkkU/SbVNjVVhmyV7yMNNkleNXXuFfYVOnz7u7Bz2/ff/jAXnx7Lz/sHBzsEFGB2UjZNCuIA/wm'
    '2BZLQu7whtnmvmMuY0PQesTD21yQmpG4UgGJL3XY8PRuQRSrmwu4xU45OUBL3jOsbi4csH+l4qFapjdfS4OoM7sg4egZYyFE24RK'
    't0eXC1sf6cfGsgyEjRpbM8b1jUPihy3Xsm/HWli9B96MHf9mNHdcR/Mo8I3Ii8554wMJKPjHAwHjgGgpMs7byjfbWNi8ncyAnKaj'
    'wWFGZNYRkNeAkD2cPLO6E0VZwt9jDYxgYNNx5vGjDC3EvQwLD1acXmLr6CIwjtmAlFWvaQ6XCwVpNZMkLonjdBh7dWgp+sk4KwxI'
    'On90jkBVxHzLjGwdDlNfKF/VYHh2s+1mR79xbJ4dlrQyy2rr2Fa+DLujQhcEOaP9nKDIS7XFZT+npbKTtFz2G9QzTQE6UcvMZDl5'
    'xx0VJSc3azKx6dM4594OzxX9mBlxC29G4B9Fi+DODgPatkh69w+NgPao2YlNx0iZfr4tD9Ul++euaM3XpdG7j6zeKoAC7sT+uS3I'
    'ZrLlgvxtr9epaqKSNTms/e7kFVFhnOj75H2e0GGW3/vIPiIuEFSkd3pqfu+f4Rrjn0iTI7+E18bP3stuF2T+Y2ZQKuFTeqzP3tUP'
    'mO6H5slltLUZ/UHpGa6pI7y/bo8Luooy6rqlR+kkZHgl9I0txjMKSiGQSFiIZ1ghB5cA9hwfJc44lwqOWPRZiLZf//5vfM4ideTH'
    'sx1ebx96ptJW9j7zDVjcSZunxa/qDZm+4iWP+qMddrYzGJ850w2hyaEAAHOQNYlqPkuynt2k7G3STWcXP6GvtihODgtHstkVmPx8'
    'zXed6+PlNB/NrgL3z4OexBY3/TBy9ZgKrwN8tEV/ZK1OdUlofBwZMeKUZEjmkV40opMhkyECvaXLTkt499UwvfwGjotjqEhEdSRb'
    'cBQt0Zp7KatV7VcaMoj/fjI8x2PGTNqKx15MRgOoJgASgd4i4IgR5EGq5wTbaQzMhwzKCEs5MgQyc/+mvbqxb/iUXlqWE+YMr/NJ'
    'f/E/grE6BUWJPAh9FvAzwy5acRwDugRT5v0NZeDWiMpICVyBfhHOFm0+wmbC/wgtRfDxZVb8/DKzBV4joJT/XQhL2kv+EnemiC9h'
    'i+Nq90tTObwy3w1H7JUI+GzbzlsRzZd7xYfY9QdzCZVklkrDaumAF79jS0G5LqyCa2Ka+3U701yK2gJ7MKMpN8/WNbBaiWHg0pBn'
    'IwUq9cKN/KnXzb65IcOfSDtvpmJ7Fwyoa166fRW1dGEr9K1rTCi3YDeAIvdVJWQLAm/4xXJ6dnvVy8uTMvprOjA1d27ubCUmh7xa'
    'oIXsR6Z/glF5H8WIje9krwjTy57CP20SZCI8iiwkFrDqum7jGJu2qG3CLe6Jbib34GgEfnS0BT8aKgEPQB84kcGLj6NJiouc5gDk'
    '+C3jRiwWKgy5VUYtSSohNpFJwJpP1DQhxlQaEQ2a9lr5IPwyUWwSRrGqmc9YTdLvnaesIiFiingnNJM151kEFLgT4cmLEjs2BGhy'
    '7O8tNaJoRJbriZQUpVc9Hqu5l+mXEj5V5gOy90YXVtr5m3lruF7QoxVaPC9DL7OM+ORQjacz8Yr7gm+/pKXgHAir3NIvVT5/NqmV'
    'P//wUIbjV8T5G46Df5qCqvxm79MPAZINUCQ9+993fJPdclP6IWiuorBnZGqKeoZ6KGi0+GVDP6pQZf3nelRurLTSskTme3CxyKuX'
    'QpPP3R8Y3fT7pkY3rrUZHlLOAXVXahIXYvbtjTKrHLYoDOdvGaIxPnBtfRaxyP3AKOVCKBQbkJmXgBjqyDDENMIZ4gTWKWIbAcKe'
    'XwV9iCyg1IcnA6AWeKhK9FEzIIT0ybRjGTR7lzEI4K0t4ji3sNB7wwZJMY+pC8cklm7x0qrXq+X5Kot6JS1HGFqtiHV9PJR1HSq/'
    '5cmFhDgnLgU5LolUTpHXzjVruMv5rTJ/9vBGS2hOJatBq2XFVlu3oGfXWS0Da5mZPAbi6beGrNtyPTPXWOqXObjBKfwUmKmlb27j'
    'zYfSGhgp24k/cfZ1OFyBVjdcCzblFJN18MaeFI0FcRI9K0MIrhMffIWxvHf9DbNZ3IJg7srH3rPsZuWYvQ2e9jl1oWYSzDm/nfzF'
    '5N5Djup3J2xledUqtJqOFlCHBiJT0vQXIFGV54t6kvUS+aibXBPVgUh11C4ojnW2hBexLdtmDiOITpHolA01h12x2SsztYHqUDoP'
    'GTdTkNWadmrMxFcChOUlq7j6qt6q+3IAIBKAh/cFkcA9/bi2PZHBw3vwZQgP7oklAQ/vA8KBCmC+b61ENPENU0H5uf3cCSH9J0De'
    'eXotngZMPRPDlyHKJBPYotycZkZJrDogjyguy1Y1SKKhdPVRtJr2UVW8TTqjOwnxoYhLCjVVmchuhwH9X305ONj9xLfjYDTN0umY'
    '70e7MEqwFjU/7SZ0XWDNaeI4VZ/5otltczDPiZYai5SEODhqn3k0ahvuXdccFLJeb46kQpxdnJb16ZojNRkSEnSvobPDHI3+pZMM'
    'OYJkNIEjj9QxeUgbEWR+9WbEtzThAuJHJAgnccEQq+dnk9H09KyQxVQcYKjdBGaTzGqwkf8kbU97JlalOrMLq5R1JuA6aHbEgIh3'
    'IlC8fiS2CpIXVjTScGt5lA2muPHRDSEgyV6YQaiFFmntu33kLaGbDcR57jqLL896rMlCxBuq0E47CTxX2FItmYIsnEQv997D+HyS'
    '0ipBEIle1Oehl3H4UFoRlWzKonAC9i6tR5JJts8vnz9k7KggsQWIYbkGyJ0sYSAJLuqmM6Pmpd7jbRJR6FD0KqpB2QlevxoRr097'
    'DUUnv3g7mqiVrJY36kbv1Ws+lzlLHTUcKb//zGZ6amPrjwYUmw1d/8gN0ErdpOyn3YOdnw9e/rDPRjxiM5ycRktbEiCbNdx1cLmq'
    'zGdDfirBJoArUTwdAgO19MZxQJFx0l4YqOxxVqlXn+UP/yvJ9fjne/535yP/+SJfTZn3f9rhn292PsirL1r9i7SJDG/8A7nZ+Mfe'
    'Z/5Lvb5bbXEsUIL/Nf707qn8eYb3T/H+e/vrufn1RTralT8fZHAu+Dk/vpRxf5Txv/usHXIIa37FiVLkF1JEyi+kiZRfn7WQ/JGC'
    'b97/mYYAvL+/9/ITB2d+u/vpAD++uzNb9ebz7p7ZquWfYjkyt6zuue2dEI+a3sq/IzZHu2WQvs3pToUDye1wZGpcnN7S8Tm7Bea8'
    'ZZ3qLXylb6FaukU0rFsQOreMUW8F694Ktr0FEUPHJbm9oBM+uk2m3d7oVvLx1h8v93zNaDkhp68f5YzF92f3hKsXx3ZFA1sm2Sce'
    'RMlxX45PlZlzpodZxkHd3oXvYHqZsPotBr4AX+Ll2fATR8OjgmhtlKpM2SBZnTkG97wUndRBk+4DuiZE3FsYJEx6Ucc1VUzcOV1b'
    'WWmzdU0NV1FFXufySGZmj7AgJgkkhl4SoJkZqYEuNiO/aDMffaEpacrGRjSZsn2NRTWHVO4oSAGNElgMrL3mOKGFDyYjuGk6PB/C'
    'xoA2QjDPGFdYcqoICCYIAAOvbR6eyZtYynrEedV1eaqyJZrc9mK1FOaoeESHEI7+2XaLzlOvn49a9eWerByHtblnRoUwysFgkU6R'
    'lahhjm3Efr5F7JTb097J7WXaHtfXcWCfP2scJku/rCz9cXF582t2tPjYDKRiZpxwUSc2a1P5IptxYHAeYZTNu4rBZnxaQUHxuxY2'
    'JEzbGYQHD3cE2QGz8sqL10DlnphcJOvlqpOUWfDhCHIJukKHI3ZkmcDuaX32StfLLWGRKscQpqsMmjqQ9Fju+V1odZoIc26y0yHz'
    '2uiSfx6VQROmdIwP3w+rdhHpwldXChB5wbmk2PZtg76ulOeVNKKLUgDvAgpS9w78z4Ne+/bOmKjxR05oTvjV9wihR99ZyWguibMT'
    'IlRdNx49UhqVjVeWN2LinG859cPt2aT+tW1BWEoxyOpvh/82Dn/aOnqydfv7YTsbryseVAgR42fgdnctOYEVoqlFrF1rRGwuGTiy'
    'zdWLlqgp30BRNJ89Zo/ZsE9JPKhoQ+tfdcznvmkJlFRs9jK1gEGHWA4DHKaAMe7000yXjytThixQVANQYHxtOYu1Lf5sbGw8G78I'
    'SlNhwtigUI3biB3jZlnjWyhBfJZ0OVFXiKL7tJEa3hQ1yzNW1BiXFmjkogW1YTo5ej6T4KNhpd9VnCUXhu0EM9LLaxn8WvASJO6w'
    'K/cHm4OqNL8Zmnp9ssP01OePfCspz0pW7l0zdrXigY3UJ/uaYToueFjJ46adNzUawJHxv3IZ8GwvgZ+WrW+sDJS34IQOBUsr+CyX'
    'nai+qBOVrmCtPsNZKEtTXjrhenzAh9yEgC208y+eitkQIbve64YTQ5VtvG1ZgJizFtv+UnhV7HHzDGOwDCHhapGPMXwy1TrhGdXK'
    'NQAtyw/E997WKPFv7KqcTM5/7J33ZJXCRZJaLIRAat6b0ETVsYl0EAOe0RNUuCVtRM9glhTxafkRYSbccWGbToED9sJ3hp3NCMaf'
    'J72JRKgdSpAA8NTRRS/r5WCxcZCgWiYGOR17p8XfTqH7Hzb8B2xoGbjlFIbuIHzjgE/YLO5ocd/BpYts1txQCOWDvy1p4Q7gxr9a'
    'nphe+zUQEsjwxTtsyJLfECE8CqEhtBQvQYqY+KtrE6DlTW+SX7u7Y6iy5aG5V+k5tGLXb0FoTclms2kxmjuk5dvJFK+HAl7A0YHn'
    '40GQ0E6BXPVi7kIy0B2JpQyb1NRbIIVgijMdihMw0ZESTYZAJ2F7AQRA4VceKIJHJCDzQKtsffTw0yGuyMUbJYJp+nL02Xi0X3JM'
    'FJZmTCcZglgnIgsyFusYAgzxJU4Oy7nYgXiSYTrpBOP34mvwkszV+2fmIi2IHUOL4vDGtSEkmizfZ7Nbn45QQVUWc951vptf5vFK'
    'vQmAGw1fDjtEXY0mr1WeNWF+JRAqlSoiVpulK+yFCAPoTLwZAuPoCbcvx05r8YQq6Bh7V0rXVbNwn+dOYOZqRVkVEZM5usV1UAx8'
    'gy+vB924M+iqY2RkNFIhEVBNvTkMULEiQZSE9Crt4PwTVMXinfZjLz97vb9v3NmtV/usWjxELSounO4KMpdJxdZZIl3AF9/0ShQc'
    'umXXoCYl8JWN2UpSHh8COgnNnVNPlazjy7As8tCuAJ4H0tslOGTrEbvt3p1uRB0CQPcJX7QzLuiyHnuMjGuqBIvdtM753bqp56Ne'
    'phV1fYsxg+61Jucel4BusuhQnCMG3SPn68z5Sx3bocEV+E3YrMLFfo4gf57l+aBbjLAw11d6NCwkJWqzkMzf321noHS21ojOnjYk'
    'rR67pjei8SR1BsRDruMZvKK5bfzryZA8+UHE0tGKwGkOXFkvnEkIPR/WiKnMbGpXbwtOWHonpZkN4xxSAloZTp0aSC/zousCozEJ'
    '9idRvIjR6opC+qTur6eLFTbtS7wtlIw4DBxHA+TCJq4Ft2o8hsMDKN84+LeEXYaZNvHcHJS7ST/uFnz/Fw6qPd7aaCPK+3irFpKU'
    'hOnE5OobsZb6yAhHNHvXkxo9zRSisaSstbxcM0d9OgFtNp6MBuMc6biG5xggYciMjUS5M0fdoTQoLFTiNF+mOX+g0iRCczp53X2S'
    'OipNGyw18UB0Yac/7RIo1f4ncSR8FL5Fl9AVSjtM63uDWURTc1A9hlNgnLH2ajZU2v7jjYSFlNjvNOvwaO8QuNM+bCwnWyL8kGxj'
    'TPxZZC2iALXBQ/kAIHinX8o4jPXizfyxSzHZAxlrLUwpCC/mTZGBAV45t/bxxuMbenOngKkPNnv9U8zCZdFW5FtaCR7t1kYOtQWS'
    'uY4uYfjEgcHl3Uau+gH51OXA5e43FdM8WtqSOyjHBeyG5N6zAT3vIuQZtHuG9UN5v0DC3LIFP3y2QVoUNexNc5/ChBGGNscMl6+R'
    'yCfahXdLcRJ24DX43U9EA0Hfjjjx99XuScx9NrAdmSmG1isum3xSqx9V7S984gubO0eNgmbWnZoER7zHLgD0ZyPyxmgcrKIecrxP'
    '5qk/XOO0gfUHlWxPrHg2pk7dioVaf1bSQWQtq5K/GnV7bI8kEly8Uw0M1LV8AwWtwaEG8PmKE+bEk0b0kM7iYm9w2KHd5imxfJOJ'
    'Su4LvJyzJ7cBLoqbRGBgN8kPJqBxU7J64OQ4Y9UeMHQcNQ58iiiTUecb9oK2OFirTiNywHAIMF6MVo/s7Nc1fGXlbImr9aGSlsl6'
    'jM+tdP8qhUOijQkarjgd1Kqcc5bpVRwuhyjqClF+kwWSHN7R5jIus4di3GKNdIrkvJiGcSFL7Cp2hjiPNUkp0371yESx3VfTnFg/'
    'rJekUWzSM3tMzL2xM4qxRZ0h6LqnncBl/Kbgc/SNY6rwj9fYgqMuWy918kn/T+k1tixtQulND43onL9R5ZDqdFZ3Za/4G6pAJC26'
    '17wH7L0UDN6MUwyFBK4rXe3ZMZ9JjVSStmOI9BiwT8VnKyLeYZHY8k9fsyfx0tLS7dcn+O/2559/rtOrx8tC5/h1feGvZSmq5sM6'
    '1wVqdEGMBXmkMPHp9i7YxAd2YXI/zGjeRuaMShzkaNL7BQxVH9kTa/ac2RXCnjHgliIYVC++r2RYr2zqXPWVD9w/bzO21W2LLwL8'
    'vKeL85ldWCJ8NjwcJO1acbs96qLfE5akqnWzxsHQa6NpjsTZjL8lE3jNSmtmH6bQ/8MdJUQv3MSAqw5T3fDLH6kYceupPUWo97B1'
    'V0IJFXAZYfHT/C3QzUFyGpvX2AmJ6gcEIa8v6ZcurFG5VoW8SRxtlrDyccZcZg1XAt9yWPY44RQ2jaj2M/s++urnRlH9PH+9x+oG'
    'Z9e7outyxhsi7DB8E9wZ+aa3xbgaczk8qh/hCdFhTtiEeQ6bazWSHNPeMKQlcjzgtEvC9sJYwBDib+yb55iOxCqoQOjzyzIn411n'
    'jXs6kSjedTVEnr3g3UlySvfxxKx5RSCVe+qPxuXzUdgZXK4HHNI3nfyjG/OoamfWqyFlVlgYTY0+ygJqEJhmb5T1UA4GWHuITLut'
    'kEUl/qJrTj//Cq5itrpZh0od4PRA95zvY0540xydnNCz8C/u2VyVRuw8KaDGcJhcyo6xHladV7R6MjzgWbCtRs0a4UMtkLNoMM1y'
    'tmHN06Tvc3E2rrZYKXz3W0V+LrRhhf2ymCn7dE55+0NvzH9A3NieczE4/yCc0FC4aCzNVdJXYWluT7Z4VZhykBWEVuZ3YM+d7frw'
    'gKnumV4mFxVm6jNdTC7qgRDkIuio6LqoV7f9zsBS7STDC/p+cFr2krFfZrvJGOwR+srM9JQpAW8WzIKJctx8gS+gpZUEwt8QKgxU'
    'whznnOPCcwgzmLZHvXydy3CQPLGvFoVZ2m165sT7P/9YEUtaQEzi661/J+JUNbik0ouV8YC1NeVwLuu+mYiEOZGhbFIbi1FtfFUL'
    'ZNp2I8Q0vzIcUFUI7nuuXvBwgLELj+upGtPHJD9rcgiWuNNPBuM4CAqfXjhstPZipeGHjH8SrTT/UK+7ObnOp2Nr1H2j0jKMp3pW'
    '6sWEP9bLtbrkFBfZdKyCkzmRt3VLGr5tWtX82TqtqGLgeczcg3C0M4u5oQLGZajVCjSN4GnT/e6nSBlME3LatNq4Fg6SzsJLUeji'
    'dod1aTK8Fn0wUdEZchYwvmeTZ5ihiuo9O4OkH3fCIDmXIm3IFWCDKJk+UiT+uJY4kc3v7idGjPN3SD9w3sBtTxoNn/QMiLqKBMAC'
    '3UO2/JN6wboZiUJ0RvuUtdg0pINkZuw5IlHyM8EgnbNRr5NWo5B37z8d7FcgEG61EIz+Hd7FsCcSLpZjqXO5qpA7NpYUVFpcad2r'
    'c8ClihHXqBRsjThgzpUoWKJ3gALr2gSuSr4btycttm9L2Gw81WeKZ9wwfdVWmU9bKQCmBivxRlp20bcrUr0OVn3prQSb0Ya+605e'
    'Yc+XbbgSTfP4xeSFBh/owWxF6w9ddHFC7AY45LTg+kOdWYuSIUKzQ8LQniSTa1qeNJmIN0/BFerA9/w5IdYsCzyQsmJT4Bq7MNUY'
    'E9cpvUrIBw0Fz8xbF2eb7VTUE6pLA0DTbP5EoF1TS8EGG5xHsXGqXIzUYAxVbHCIJfhpsgc+ix8lCL+G5vf8iCQwjpdtwPgJmaEb'
    'nyCunKkLxcdkXA74H+3/+YdoTGswpmtocZD3Bql2kvf6rPfmIJ/a8HYTvYEXHvssiH7lj6z1+k9QYY41eqf/1TIlrWjsnVHCaXFe'
    'VP0j4RyRnJd0jS3DTHmFrsMcEUp6kt788PkKPJVTqtGtHTUieR70hlPij/G89oyeCeNO+OkPDXizX/PvZ82n3yOMb5qe8/PqGmoS'
    '3J/x4/shTHlzgqbaNYFT7ejIaCNBNRZjjh2CamhwXNYjUNA8wCB+dbQRoYyTsQ/NvT9IrmK4KOH3SX80mhBt6UQbQytf11libf82'
    'Zb+SSxz/48c3w7uI/kEyXvrDht1IVsG4oXaHhT02Fu0X0fImj8PY3QpBd0kgOMpxKMyZuqQ9VfYEOe7V2CuF8gLSvTGrpMSor8Yu'
    'b7kES/KMryx8MY/k7yyLrzBwfGgC6u5u9YGhD08mKoFEp2fjeQbk5lmSxecscTFaMnmPED14v+51g+i0cuc3IgRPbEQm6GAjEuNh'
    'Dhty/no6uYDpY9/67goBwqkpLk41i0CtFuZKkzhWYOQ4ANWgRyuXp/F/2N/9JP5J8lN8Hnon17FMl27FXnrJ3qClzBsEOhI5WNAR'
    '3A2nY2q2y+m7Rt9pGra3E4kqnIb7Bd9JTSEkRspDoKzol9GIkSQ8FJOJ3LEJne2hQ6Fw8VdPzcRkZ3MyPKYks046NHbfDQ4Q3W6P'
    'rmASf+lDcrsJAhvH8PmzFfp4Fn4804/PbCxf6QYhmdvNK/qKBpajNTro/LcRXfOna/50pp/4r9R3+3O8Qb85NdSr0RWnjsa5uMY/'
    'l/jn7G4BtiXsRPsyGxNT+xnSjs2Fq4+97l/p/6NBmuYLkaTPYvDYXIBdJbTosg53G8vUh6ifvavLBxE+aYQ7kn4f92H8G8FPoyur'
    'iFJhPBMYb5geg+Qa8qrC8gXUgoRE+8Y4buWMSUE4tnJgaLl4vUtpn1+IGE8+unjT+uyHnGbJ1bvd/QNrvBRcZrLhtm1COtOsNkuH'
    'YIr9MOkVgxoeb3R7FyauLMoscWTtha2/+nc/BCFyPDI6SKl6MofpVOGgHcUb7a2QAl2inZxebSy3t0AblD8Pkg5bJtIZRaF6E9YF'
    '74eCUg03QDQG+2tnOQKBgNSgU8v8BugN3Lz0PHSh7JobyzSt0DTCzzQxZ83MlE2Wj7c9tpkVWsgsAuI6mk3SCoVEQo52tdsmxk/J'
    'uBfXlunfZf1ifKzkBMXpZGJ2/J6RLhu3PuqXuTzVWVELzUGaZfDXxjRYjCHrmSdtRoaTlNewsIHqk+BTfVgCr72q9Qyn7dnJuPCD'
    'tAzF0yI22maGb4W2ZH44yL0hltzfGSNsRIPn5FGIIW29mQ6bTxa3f3p8cxfXbw+/Hn39esQeTV+/Pv59zberPOudnnEonxgLCRJ0'
    'MlDKBLebEcVnHf5eTPMg6fikihbFHzsMiWZwunM1jnmgMTdUJ7xfO+3B7GUgtj3AnkCihD/557GPudCiGoq/1Chq6VUnnYwJcCQu'
    'bW6dCxTDYEg0TnxT82kTXV+8On1nnGGPmPOK6WsAXShxsb6oVdLpYokSwN0SUWh93p6VOUtkaLsep62ilqyNTa6SqR4Cv66wJilB'
    '4sAVSPhh9ZKwelU6661rX7k1gHEmgFLNUj9+MkNBCt59SxctFV+KvsdNnHKAX/nWG/J6aPNcapH7XIxerPh7E0ubdKJMmFdmWbmy'
    'kPZcgFuvV4bxR9BYdL0ReT2GDRZSe7ij5awPPYQT2hr+a8Vto0kFNH9AsKkKAVTpX4nz69O1x2OtGwXLq9GonyZDu/lGRWMYGFGr'
    'wMryxAnWjNOioWoleP/d1yF+M10uP7EAd8dlKDNZSjCyJnOZMR93atFJVgg+7Ka7y9Cm8zohogBJtlsyQTOfXBVGGFDYcdCy2ZY7'
    'idpftRqqH7jeH01yf80Rss5a54JP4aiimsIKXqRtiRfaNKNgwUD6ejSAIRGRhPq+4XxiGiwOGELHdEEsGMEIPJeRbFezMrtmUZ15'
    'BoLyxPzmE8oblSHHsl+a14jLyi86fTIlKVTwlgt3PYwMPueSkh2Q4iaXl/A35u0dkAYzboq3wLhxxHV7B2fEunHOuojzls2Fcc5V'
    'pmtzfG+zx56lLlH7AG8H1kSvnsCNqQDcwKKFmUHZrrhVQNti15Ylwky6zjwxR4ND5ymP6l7ceQlMov/3/4mOhXfF9w7o5Tv1M7Mv'
    'yrPis8YSVmoYbdgXd8Id8W+vYQ6P7hfmF3dMhbvv5dVTtporQWihQKd51OyRDIhMrDPaBK/LTWLB9xJBhMaEWRn2hWgy4pwGrNlb'
    'AP3Ct8jmwopmP0ArxsxX2qz7KQ/4DobkxnyEHbC6afuDYqYCvI3HqcP2FVSkFp855g04o5uG2kn3lJgkjiNDxBnxSPRxS6djOg6z'
    'OUA0nPR1PvIwc0b7kHb+f7293XIbV5Ymeq+nSFHqASCCICW7HHVIiQxZll2asiWHRJdPNQibSSJJwgSQMBIUxaJYUVcdJ+L0xUyf'
    'ieh+gr6ZBzj3p9/ET3LW9621f/IHINXdMx3VMpi5c//vtdfvt2R3qDIOHVYlqv69Aa6OPruW5KFhpHDm9VNQmQS0gToDo+QJkm7n'
    '8oyUv8bOdj7W+H3nwm59dAyd2ncPr3ni9srbyM5bubt4WOnrYXnq+SySDm6izFjRge4oOehdTOkR1K5m4DhmRvDsck3OqcpNr7PL'
    'F/IwLAn0pLIWEcB2lHtjiW+CNspQiSbCuUxWEyGVqliX15NUElO7klKSVDpJyVHM5U0ECVCZzats0XOiAxOCUvELKVAa0/zoCH6U'
    'Po2OoQDoQrCjRliqyqHRmV5BHjStMyVEinTLFM9tCCcmKQibdgSLl+t+J76KGsRcndiQ8MSJLVZdu4nv8u9iFhmYXs+80LfXc51T'
    '55TADR2WqELzcZXdkZSOAPa+7TMjBjDrbWhpTxNicrDIZyYHaIz+qKiRhg8xQTB6VEr+kiwTw8p6gqPdb8sLss0le3jNOUGwSmnI'
    'uGJ8TpqTcfZh4wgYhdvYE2u703yaOdqoZ9MN3J2n58Ph15WR2IkClrT1QfjmMq2rd2FX9342pKBSMnHAegy+jxDWF0c2rMqmpqBs'
    'Vo1g1aSXDVSSGLwqJHtubqOsA+f7uWWGCKBiQwQjY76kjAhyk3aLqhYXKOTUkGdy+7uYX/V4kJ7xWnHKZvYmvdo7mLb/bPoRBAq7'
    '5PC86IFn3uuUpGAMaD+/mMciRdTRMhrDOE+HLvUBc0Jp1qiLORzHysweBN2KQiH7kE5mwubqpOtes0CO51P31o1422Q29tuzQMD5'
    'opodUIiJisDHcHq5HBWZiksVFR/G97WlOWjz+vTjrF/f8B7mgnh5oiFpwtLZif0x5g0aHnSFHEoLbDxbv0GStmhS58Yuznua726u'
    'N36DSshmLtbuaMBtZfy6jc01B5UhzR+hSK9vdCqC2r6p6+GTWCCb9zQF31ij74NWa75TyaB9E+mDb+t6hWLf2ZtWuaRGL9V+xEYN'
    'WlFEPh6oa2rdwy9aMy3oF2zb2vJuWta0CIYcIgaliN3VEXq71Y7XV9R7+yBiHVqRUBslHClLKCvGjO5GI0bpTvk00KDhk1Nyn9Ed'
    '5NZlWBoh8OldMs/hqhs/PYj9w2S5r/ZtAzKH4SVX2t132GTl7oru5XiTTTrl41dS9G6WPot32CTaXSiinY540yUbx9+Rmv55acMy'
    'atdqjDMccYZAvbZomXCaS+UcHL9zvmsudmtSGJeFYlleGLzH7VTK/YJ7YV/4hvkoHceJCjRX823Q8A0Z4TsJrD783L2Kvf+orNbb'
    'qdpP9M1jv/8hG89u7ShH1AxE/6m483GVtrGbRn+bVv3+ygI7NdY4QrvHetc8IsMSb24m3+Rgp+gXYSk9IpV0F0CxCNoU1l+N7DLy'
    'bXlIlGNVa8tyLVR6gMW3wgFFPhKF3MpMB9sOXkzApcqasZoOkVPI1QNTB4WkUgpUcAWI4duLlLe9tjIvH38p8inAOgmVhtIhRyrk'
    'qL2QOR59+Gp8Gs+4tw36Akx/1InBPALpT+Rymgh709Z8sWXtk084m04Lquvdije1G6ws0dt8qknon9VfGJ33CC/oQFsb6uy4lN9L'
    'q4v6mtwteXKEB3jkc6Ye9UYuBbWfKXpx8Md2Unn/1ajANcAiQ/cbUNTkV0IjUcyQ9od1lAfj+xC+tszVGCLcmyJvxqP8g0L7LZmW'
    'MJklp8G7RsU18in17t04RXUDKxyfzn+PxZthBModx1vQ7TzHNEYnMXCMrhCjba23pWTI1UJcXtp9WKsLF4v64NkpXZM24epwqi+F'
    'qnj2FMLaSToCo2oWStsmET8V3ADM2ObiyjE18r1LTi4ilSaa9vTL1KeqqaBfielepDSwmyIKVW7Wz34J964UfQd0moYccRW/gyUp'
    '40JuUzu7Po2n4ngkPlWnx/WopIurppOTmTGr7ScwhEvdHroro0lXBo0uC7T028jcJxS5hwaT8Ld5opRllKr/RSV2OurFpoUBG8lA'
    '+Kh+vOzY3ubacYd41hKBCq1x0+eqARDqk9EjSUSQ0uUwL2KLFBj6pMaKu3g1KVsREPisKiEsm5rn83l++RV2wYpON03R8t7tlZek'
    'Mai1gnHDruStVeJCANnCUX8D35HvUsTTZ8w1EeVbwIGmB3DS/u0f/4UaIyREBEyBHJxZOkyEeSD8fSdmRZCZQGpUf6WSvhBor1lD'
    '3Nf+PMt+5LsQpwWRu0u4pa9pcuy9+8ObH38G8lLXzkB6fJzNGAi2rWCw0xiBwF+viljeTR5c5vMxUplFAPoAdgwtfP3q2/2Xb39+'
    '+/K/vnyxL5dm/dXzFy9efr/f9Zpyj1IhdBgpXWyExF0g5LYwqYqtZ6Db4EJymZw/QnsUPa+6VwCBdGW4VZ98GvxRyZudOeErdi3N'
    'xi6VvPtVat6/3om/iKrjd9Hf1a/jos7/pZpHaMUQ1Ls8OT+irI/mz8tcKvbyV7wpz6uuXL/94/9seSfJDBvYgRXKmSh3o5jdrR8E'
    'UQZO6qzsvR/96TlhbKp8PMY1Rx/K/+//TRB7kUQZk+WVATTPRlM4poSi9nE+149Iv2ofNia7T0+LiuP6Az7zmlhCwBjSauHSeDCD'
    '4JsjYdVG6XQb3gua9mJ6gagJ+fFzF4ZvaXuTGSGYdkEu+VO4KvfMPf5KYwuEt5jRJRQ2+XkE9Gn+NV1LapjR/8bykMlQUZhgWSDJ'
    'ahUBi7KjvCQUuPeIIh3cksyX3xBize04Vaz4tn4Fdus0hU+rzCUcOItE7skuXbeEW+xEXvH7z7+Bk1j7p4/9g6K92x10HrT7B7Pr'
    'b2/kn9c3Pw/iPw42NwaPOpunFy5tgrT5Ij0+y0rO8nSqP7GQcu+IGAEjnRZvTtrTGClrzyHBmnjT977jCwU8Yiv0WHagscEgV2Y7'
    'LRXUMjBr52QTXkTo1uXnItnr4//iLsSFBQ9irO+kL0T+gY8Ob1gcGpnOzoD2HfpxTfpPBhW09hCa/IGK/s2f+gdDmdd1BybxoRMR'
    'Hj90BgnuJk+2gDzunxKZ0/E4oWyYJlnzTnDBU+9vY2aZ5QabRmZVLQW6Q3V/8dhsG0roh0Vt03YTkcZnBBmFmG6ftoG2JLVZUTQz'
    'zWTTHiFNU8c5UvvUOvP5lc9VJB1Jx0Byu0pGCgia8kSZS/YkGy8KRS5FAwaiW9pVzGpavlg1OcX1jRyEqb7mn5HPCh6ksnCdqudL'
    'Cvlxg2Jk9RKa4sROi07dqc1t7Y7MhDXYXwySvT09H9gzHaoX298///bl/v5L7+42tSTwAa1R9/HWv6PtcNPJ+KX9aiICU8qOU2oI'
    'CH6HnRz1eNArqDhlJmLvgOc94fgjPSqkwEYyEqbdjcb8XDaSSolO8vRZ8tj2KUY3U13AxuMKqtW5SinnydNqnQifwUdP+R7oVgr/'
    'hVG0CdabrCfnneTvKh9K29bYikL/0V5EU8dwi/+c/tAYZa35r/hRc3ldbSljL/v4xJKB2HZiJevJ4wpNkC/LGJsRJsjCIWx6gk4k'
    'XP83hB34Oy4irNBGHP594IqoBeQQHio4+g8eXrt3N9twD+JRNAJJ5tXv6+B+52vreOcwixDr4Z5z19xhI6tAx1j0bjvZRMlfLiYz'
    'FeL9nVrmJL4zdwlY3gq7qM3JMz9RAkmbHO2P/nkKU+TQnjo2pBOslMPC/HDvueQDvWQNTMsajcVFxEEU5Uu+p0hBuNpT4xJOc1Wg'
    'CqPTvphCh0+k5xN64WfD+L7XsZvwp39A6tZfr6DcL717pZnfXIFvR0X5PR64ODp98gcLNBuESoXCKSUrW19HukfuoHBiyQY9adTH'
    'WIy3N1/q7MV1aFGvTq1mUQhdqrWpOtK4loA8FYyqcavRNfQrHQYrfV3ibXvsrqnoRouwRQC/4pJ8xPDorZh1uSuvU/OrNckAjp7D'
    'JmBX3j48o2WmS2PubL9COY7zWpbAkYyBCTyhgbXITWpgLywRQiu6HtTVNNwPJLK/dvzzLX3sJf9fS9guD1oRWvVCPZfpef3YNIWB'
    'pvCaIyP2gXIVfMpdI5/thAYav4gbpbOx+/KJix7032OC4uK/RqU/32kqq67WwpQfbPy82R7A45pNX6Lpy0pdcacbKvOU89dSJ8sl'
    'ubVKdDYuHS2EPgJTYK+H6ovW5x8iKQ08y2mvq07FgIIUwcoQIaNdk/YfDzqBi4jeHEVvogNt1Ma1w1Xe6iaPn6iTla4TPo1pgKdH'
    'SUTWSsJtqFxdfEWSGtU8fFWyfObVK4oap2kxWnJKEc7bjobwuu1KdhS2N+x8hLkXX88znBt8zYhmkx9xRryjS8lLmCLus+iG9OP/'
    'TIe/qPuYLU69u1WQrbcfXh87/uVmhz/l0Wh6/mba9i/gE/vAHNHgK9bkItbsy3sylMq8R7Cw4nDZpUJvRKxlqbjUx2G+aO7k/h9e'
    'fvfyXd/ZQQe943Zxlg4z5XtRjfaq7N81cS6kJfJUJkjfRwTpB78sfphE1S1uSvVy+V3Ver274iXP0WiCKldFNv8mb4/ii2Ja2nv9'
    '0cBHFLqrqTklB2imGi1LOVA8QzuLtumO/OV26g7fvG7POm5nsnI+OA7AydfGa2sLnTiRrSqXyh/sRH1xsVkud5PM+LBmhSglO1bX'
    'GU3M54QvuoW41svJMuJ7dTm4Z3Qzw8tt5TcNVouVeF8OtK9Tyxiu2sqIxjgYVGoQlwDCr2fBjWhkfmiebnV2mqrrRyUGez3Vo70S'
    'WZmJcK8VK1529jRLAT/don/ZzadDcJZ34i02iqV4hG7nl4e1rLJgP1hdoSPrXkiNaLi/UB6XmdJ1yKRcv/ZtPfhh9kntayhZ/Gaj'
    '0tbNrfuwBN5ay5F87TzDyad6+JGQB0XozHsHF6wm6waG9kbuyt9tdXxfuK3uhuQUuQUu84AawZSkPk+37ob1edj1arCup2zu9xli'
    'MhhAdlLWtyyrfVvW6LqcN/0+iL5+VlMDa9TKaJGU8jMl8EYXCka05rYQVEIJaEUfofGdUtModUI/rM8fFIo7PxBOJdk/QzytVm7e'
    '7nkp8BLewF1uiIz2YWjbZE08JIribwbEu21HbPHEj8hlVkNDlAN7CfF8oUJHLs9yk1RVX8xkHqhVdlV7ZDL9FAIoNXDZiN43wFbi'
    'FQyHTzlHFCZkVKfCpUSi5Y+v/vgKuuSD/kG/3f/pAEG2048PBuud9t52/8HHgXs2eNTZk/8ONk+dHjnczEG22aNqtSbbHBSPDqby'
    'TxBiLB1BgxRG7reOo0GeuEn6ihxsbtUJ9tCMqihWiT2gIADZcBDcwe0beKqvqVMIiWCccnl14t5PytQbW4iCnhprVVZUPx743J9Q'
    '237noLZCmLDuZcIwTi3QTrdidCh9prqeJn3CXBbglNWNa3pltRxjqZH8qTkPoMuaVbKRajI9U6P62fMGAY2q8GvfKQV0UmW16DHb'
    'nTIhEYeM53EgI4f4TOgIUj2rsE7CqgFuvmKu2LinpV2tt3FjFiDi0hsrvzXmEOhmjmFShTiWjUQx1k69b78/lnYGzTxWrBTOmfUr'
    'dTzdfWZTpghpHZcSFHlzNFypviLfM58nikCN+Gq4vr7j8FzsI/mEwDEjZEiShrY5G7A4dSPa5pygKl0v6yLtpVkp3mZyWmllcIT5'
    'Yib3hJyafv8N8r8oGST/DTsBE0+C7i+AFSI0TPfbMAd+3NE8S2PAnTkqzwBx/DY7Kdr5eLhPU51sMoKFxMizuifA61uxW0lShwY3'
    '/cZqvP2bEPKFBol+n9Pr0O0yJM2uhnTPnQHOkAVaB0Jo8b/iEdPiYOXvhoMAcDV81t57Jp8PhHp3WgZNsEIVREVDyDc7z8rJZQlW'
    'm/WE3V0E4TvOrFex1UGJ0Or30XXmdTbYJUY1BmqDm0+tvAZokGs0JU27w1EhdV3RYksr1lVrrm5gQ5pqqUYjfkOMrvkzst6/+6Q7'
    '7OMnW05lJC9oLaPKNgKOMhgTMxgHg6/s/q5s8JHQWzqLqW6YZYTcZmOAZy3yC0YvtZm3W764px4AhDHKlAkshGgPNemfpQekNeBC'
    '07sWoMjjPD+PfVYc2HhZnamRfarjvYPrioE8NzutlN1FRDgFSW52F4k234Sq9yhnu7/YwjKWDGG43zracVVWXTO/2Daw0ahK204m'
    'aosjMIP/S7bgpL818LAPuHa249vSHF4iyaFu0Z30Pxt07tY623sS2lvVF6ZmR90VluOmavFlwyXtQyX1Q7DEG/r6i3fv9np+A1LB'
    'bJnJ/+DdECgbeQSCVp0qXY6NKvlvoN+ejIoCe6/hlemzKs+bcotF+/LWJDoReHYSY2af9DT59onqUi2Z8+KlcHXhFUA6LOHNieHl'
    's5fbMZd5otj48u4SaUxthGrnDR5AMqfRlNJI38I4Ni4RnHAJ38qlRazKlp++VYWlgy2dzDibqBJOoZsylSCbkaMKMa+72ADCoDWc'
    'fqYa8AA4OjWKLu7df1eDnQdt/Ox2ZPQlUOIuo+BsL0I637F+xM8/CeD8unHf3Bnf3HVqvlfJmxh1zL17E/UuzoG4F+9mlSoMtF4r'
    'f/bM50q0OnefuU0bPXz6zLZrlDORfLympMGth0BVHGPgppXk5LUHyVqCNF+8atY2kjWTAdce9+S3+kPJ7WIPd+UZMw8CBQcmTGkn'
    'Mnwi5mYnefToSBilR4+6yaPRIh2PjuXX4bEM5JA391//CpS/8+yvfwXvNvV9U0i9cV5opLpMSq9Mtkr5dY7PSviX1DA2J3K9Ly/j'
    'xJfgrPColCCuxlcx5/O4nCGz6xe9uuZRksyQHPN+LTkm225Oe1nNaHx85iLdGApsfx1cbG2lW5X0YdTxlTNumvInaGVmXSSX6SYu'
    'h+R4VM4j6XIqxUYGB5Gk9Tcl7OQb5ibRMnHynD17tu2exFXP5tkt5FpKBIJtuEnItW3PQauVHM3jM1bqP2kDONLc5OdYl8CJdCw4'
    'Ar3NwH3//qppRJIYc7I0nq3QvZvCWfLYHQviR8mxS2Xs0w3KHtjUucvqo1vsgt6nmz89uH7cfXKTOJ5hgeukX8Hvb509aQ1kLlH6'
    's+4Xt5b+jKXtqt5NWk2Fwvq3BhYDgwb6G4/WB3H9EE5tflCLIuP/MKUzWDakH4B27XG/17n9yzeV7wJAkwYSX5TTZFrkZLzKwMeq'
    'pusInq/Uq4k4WEDuEzFFhQSABY4Mf+zDYlv5acbCZxUEz2wFJ6GtaBBmQmTZ0GKXIJTOqy0kIOSOYxtaLmzrhg0MzF5v64w+WL3f'
    'rZzqC0zjU5TwsjxlUt/qanbeciq5VYnnupYBuJJGj0YebweyrjrYUgjzF1Odr/RkQd5D1gN4AYt5LvcRsAzU9QOCjD9Zl7mmA+H9'
    'MtXgG8yvwUEiRwNirQyPV/1ym9TljTj22GfCU3vMev79GB57LmFeNR/cTacJ3rDse1qa5mCVrS+a0cGURuzrpPWotS2M2iZyjIn0'
    '+UjEzPUO/ni4iZMqxxVd7dNbV94eDDpWrhhAPOUHj/Tvzl7HPhvJZ48HA2RR0tp//lm++Zl1//xzVPOAquekdajFDqXUIUsdshDu'
    'bisHrGqW+etfpdBfWeivf2WpQoskN/3js4HinVSRnyHeCwPKtMXEfsb4y5fZxOELUq5rz2Nf/PuTZn/GeS1NTQP7zxTntxy9SMiC'
    'BR+31J6KfPZwO2H6BV/Z6mOpxZpPpTcTLs0eiWRcTsCsOPtP+tq1J9Khx4O4MZe2RCTnbFxqSg9eXVp3gnbrt7/93/5yg7JQnRwW'
    'uWJDq96gWwpw1PsER9J1k420+W8TWeCLrncH9bxwOWejR9v+Jq9YZtIgy9AnD0YU3qxCx9u8byP3CURAaU8VDqUTIof1bpBnEYcZ'
    'JT0LtoNqwKPzS68aGpa5pJufyGvVhHwtR0HIyzG8x/zamD39bipX7LWyylVvM/VD/LDNBgkN/QTI0Vf2AIDQj59sMb2ILP22wd3L'
    '1A231eWkZe5n28nbN2/2f/761bffInVCOsu21bDQchrcuykCG5T0sQ9T3VIyrWUnhwtSxSgQfPFft0dOPDe/0u+g4VKQX1v/NQN6'
    'Xwt5iFVOWHyKJ8JCdfteml5mNnOZFmiOU35Du4HLrW0GkhQGZflsOJqrmAKsUXjjF+oVi0ZU3wfLm+xq2PW6auZjKBrOA/hNusO3'
    'ERrA8JiT0UI9TP1JUc5EY+gz2O9wYf7bP9M4swaAJEpr57/97V/XXOGjfLHIJ6Y2j0dAH1mt6uhKV0oEGyifjy5GY7hDIdgVeR5A'
    'MFTByAHH9h0ZYLSUXeyj45KF7ij/YA6mnGIWjLI9szxFjfzDHYzeZWkKPjPX/DL29ULcJ5456zO2tosGDcAsPgF3sdIyNE4XCIJR'
    'C4s8ezeCI93Y24zafRFfB+RIGPRdMka1+0JZIaLNtUR/HP52JcblIjGZ0bXBqchlG3CTAZGzp79gKASeFnVIAAyomq48l/YuE3nc'
    'sq355d9GlLPWRGcAmmTi7WW7BCtcQOr57R/+yczFsontyf8A3whIKoDP/Y8YNL+4wpVvfYa0gi8ZrC9fwSsresVRKB4uX0mRfyr5'
    'xSFujeOjVW0vaXPAdKuTQalhIbLZKt8Iy4faMOVPS46oGSGav3qt3knRd9722YoBPZsc4qbjqsfbaB7BUTZNA51QijChy+bkdW7k'
    'BV2g6qpw12e8Ti0mupdZ9458JvutS0/pNOW6Nj5yoJOkPegfLIQ3awm3v8ObG/eUNKm5HnkDQhCkfmOL0cLRFFqgc8uPWlUsTi4g'
    'avqRPu/YhSSokyydAtttrdTdMubiaW7dPc1RHQfN/u72+zU3QFv6sjPmzWAQMBiXtiMMnTU0LM2KDeQr56thfV/b/bd/jvD1KsiS'
    'dfrjTmSVWlX20YahcZJOarUPr7FTvNfhjQ5hvfolkoDJLtS1BpzedCwXgir+8Afv7coyhhtj2yk8gjNNCIKg/5fUjRER9k+r1xox'
    'eHsez0PEUIzAUGDcDckUZTcq/obB8ozcpfwO8XGp3Y+4RCxQTBMIWVhaHLNLrSNhG2KDV6gY86IX0+R48UFWRfFhvtjaSh5/NvuQ'
    'PLz++s3rfUu2Qg+uhgx1x9lo3Ob3snWLizkZba3bAhYAZs4/46Bhq0TYtd/7RHWx+QYrQNU0+I/22If945TzoKTKkmxw9nFNznOZ'
    'lWycT08L2uSD0dEud5eeEHnDHBsSgWWPt2MPAZEANTxwvXpRl3bxzc69KFGgK3FncK3TfIVr2Wk+gBpimK3Cd5O3Ee7Wad6p5UBX'
    'VnD9NPcdP83rIBmNLGEB0apia8jGwaQgk8akJOXFWh9G7p1DVkEPEAWkcM2OHW/qr2mXYlCPg6oirPOr1iDue5n5es0BdOmBof52'
    'HhHtluVyPrUlvBq/APWEaNUz6wqbMuUOLTJgZ1TyyC216pB+SMLk9mWVSm8qAKXq1gVWKtwCNfB2dfsqudDnMx680pW34EVU8u++'
    '23Du7mD8SY61fjpCZNIS/9zVXr6lqXV7iYS1U8+SGqhC8yeDvZgxsIiaxlyrDd3/lO2RR3vyXqz8d/V2nRy++sC43FnVkRuJdVcM'
    'wIRwBQ4jvnNcmo/qRHSZB80FfzUlfnA+iVEYy1ak+BpD7nlP80qF3VKi43zyLfeuK/IseW/Tbp5k9iImDRVkm+qJUue5Eip0mA/I'
    '2hhx14mFSPyOh7EWBrGIeSwLM5qRWpN6GFltjuBz0/8Id5uHnKvI69NFjNHTqkkhU9WuqIIm71QgyCaqobEozSXKlzuqXyZl5cvk'
    'P1f1kuhYI93H3bUficWlcZFz5w7JQYdULLWxr/Tzw8dwdBOOkBXeuNi3sLvigA2ngWn2Zq+dzNtF/OqttvJ0R/edkeuKh7mziQul'
    'F2pYbCO1KtJ30NAw4c+yx/lLvteErJRwZl7G6iXPq77mR9lxbnno8MBjgxDSAMAfCDROk7Uv7ffaPab0Kmiy8q5vXe/xzcIcpzLu'
    'SXuNZ3sb2vk3EG4Gg7WKub8FhznY6OW4ZONh0aFWCA1ZVGYBzgue8otFenxGz7HNnsJFcIRwhqc6mK0r8CHyxOUy9MUV09PTo8NB'
    'nnTVrUwxHdAO51ad0TT57yybFoqmdjFjYWc/K6hlejXROYb7sH4LmGeguxucqcZC9/4ympm9Bq2Axc0J2JYuQu9sBSLaJPXgBs+G'
    'wYkU/oJBySzHTROTUpQM/u5HX3x+dKUejPITu/gHkVt/L5J6ekWerZ0u8qO2vENYL6EUesdn6fyF0A96EnSc+/tVOhm/W0DsY97r'
    'w9bDazNWv4+s1S3QvrVWa61z0zqM/N05JX8/mrWbtdXOZ8+Qior0RGXfgEypArChcjt/7y7B696cGH7GRUF/XY9i0fWJfuAFiLfP'
    'F7F/9nJ30VVO9RWXBjm2cY9LfvZ3CuAL94OLUE5h5TsP4a+qtWxjAHS7btRA28eHD6/xPeD4z9fXXfYSfgpXr4ZPd2wS+xDnBxZ6'
    'ULYZ6ilD/FgxP+6ygzXNHnRj8tasYZs/gaJtj5CR/mCzPZuefvxllp1+PB2dfLzMjmadHVTyxefddj/d+MvWxv+xvvnsoBisA5e0'
    'YkerZUcyg9QHtS89HjTBqKExTao6O8V818vVpt3NXE84Z2R0WrYEsof8Kiydd1dJmH585lbAGteMGc7ZUp4zz4+egpvNmLTZDSl9'
    '4rT6Y92mI2bEpxnr0amYgJPDptp2XEp25mijUE6Z2+v/nfZUDdujIjjhporGE1R2Pv4miO2lKuSi7UVY29N8ukpHPfH66V6kQGQ3'
    'sKrXSa/XG7vbHVECerurGGp6ZTlkGTLr3sjyjzufBhIQn4iuy3QEjsLFDAgHReUJhywn/EOHbFTp2VXH80uGnNNgmSLQWr8FLgue'
    'LnRVwQ+yVfiBJK70gZFtQXBrOqqxyOgvLCHU5Z39xJVJUGOf33tgBq/++SBARmNAeCB/9x34iprFqIqCA5X+um/2Lv2k53GrFsxJ'
    'GlFBheXvl+qSfgWOjSnwdBPqqx5JiZ4GS4GH0mwH9BKld1ixnpDD+9CNpoubweCQe9ylz0tii15gmR1GzmPHf4aqWHI/d26HwfDn'
    'D9J9OtC32zERA6EarDu6FcgW3B86m6ejLkLwZFPKuDoxfHDSMAMc+6GdQ0eqPaccArzgjRQPPNLZQy2r8xDxzLanRkz/ZW5PIUJZ'
    'ZwpvvU9SmJTWgweJY+lkC8kBY0GcRPIFhwht1HxncjKOcTLQo7gPMZ4Vj/iqKCS6XKnGPeqcfLykb8ops2Mo5CmE9At6bZUj95zg'
    'GJZye5s0cVvjRrYR3M80StFgQECWDAaMXnGX4UQ0q31txAhkSboLALSpdD9rQ5clD9pjIwd7PB6kEO4RqNX1jS9nBonrUoCSFpH1'
    '79hOKHXMiCpznIw9UMWu92WgmI5h+YnmmbPEaDrisgdkPiMP1RJxQheg3QQn0T9U6UAI2nayFk2vK4wpXjuEI11/IAM8VK4ciErG'
    'W1YzazP3Vge3njXdag3ucnPauepNhv7C5CBMC3Yw5V7g9gpPolt0ev1Z90YDjqZ8ZWEUiDuatuqxC8LTfzkWLtpS8bSAojo6pops'
    'U95VUBU8q7jQmCPNyFkPIu0fHGxuP9pbe7r78cFPQo40BGqj1bmbXgYZP5Obexqflg5N9gAqFIFzAGCZwRQsv2Vt5iPQTtrq+5rM'
    'gV63R8nNoFfF4r6YSkW19O9HFyfGWgcJo60A2MyQnuLBlxcnJ5C3O6poYhiprA8hAKSC3hHfd7pGRALEoqY5RREfJ/+ErJkxZnjv'
    'IODewxcanfjsSZsOBRSnuVW3Pmx9sfW7z49+t9VBlRsbXoHJXKaALTwDu4GOvRQmYt5e24doZi6aWGmOZs372CBYoNIg9ChfOCE+'
    'jhxCAtkt8ARMdRg+e/yF+2zLy/7IHsuC8hMQbtflzItnRKCOa5jF38stBFtTuWso8SSUwBn5lmH21Wqe/D7qfcRvz9OGwp+FGqHE'
    'ympDY6EnvhAThTb07PMnDY1qmiMuB6xSX2Vw8EPA8ZC/uGeKiyPuLa1FJl7/K//YCDuNvuLaD/Rf/on76148cWu47P3v/Zjm6aXt'
    'Tt8ZcwTX1ta5HLFcg4EhEsLQoDYD+K/FgtkSPyOCES48I3bhaG5zWkh4+tKBQeD5Y7jpUM/vl9ajp1RjM4uZzJKmgI6qBlHOgP3e'
    'm41m2b6ckYvTMxbCkkwI3yqk4Z2Wahll2ZBvZWCdHpqJwtCUV5FlelZaJ/mlm2zd7aRmBEBLKT2Bx7QPHQEqJ7KhyVkzJAKLFSm6'
    'ClbX1XAQoI2mqlE5VnfIC/4B9npTeetNjfrooh1TYMnpdIqnXhTeKat7BVFIDbjUyJjuRr8rIxt0GqJE9vM/LCbj9mQYk1JTfVl6'
    '8Pjko8tFxGgTeTbcB3SHhTMsboW2CELKiR4ihmBrCwBKQ3dtypuN5PGNvjmM/NXUauQYixJHzGjTwUcNND34iD8CTII2eMIGkWzE'
    'RP69SOYX2V4d7k86zAEJNp820GxylA1hsjpxqW/XmO3ykFwEObOmDmkHyKj3f+pQfSD/lScd150LHX9DSxe0i9Vqbe89vX+/YyMF'
    'Z4/KzxaLWQHfZbbxcZIKt5W7PzvaWutpmpzNsxOp+8na7sPHTzfT3Va9fuc1bT7TH9XPmV7Ors9e6YREhcL4E34M6AmN/VUv60vv'
    'Za3e2O29+wePOoj7PfixE7lS4/mln53ZY7Y2e+JbfHg9ewzHz9mTm6cjNi5/oPFRU+PqWU2/ap2CggMvdmMe5dkzKQQh6dkzLaRZ'
    '4x9bzvgKJteiHPiytdU+GMqA+NN1e2Szg91s0FbHau4YAN2Kj82RcidKdznlyZkMoxbmB9M94/Okywpnx991BmTk0NiM4cD9zDo9'
    'Fx2fUzu/LGAIWT7l+TS2T41guvCe4pE8u/nT4eGhxafgm07VGHSsAV7IhzEKtp8lvaOwVa2SE9ZhRUoT7OH6+iDks0H//LVx+FQo'
    'fTTlEfuMmcfLw85OxfP9xivaJmEegOjBHnp9YRvBRV/cyJlab/ceCa3ocIJ827Fz+9NnyRNSkLMnSKlJcklVGHohz0g7np591vDy'
    'M/ZwxbS3D4pH/Y1HPw86kALkj4eVVQhdaj09m++2Vle3u2oNf41I+cq1K9djC/drddUiY+TuQbG32S0LFD8d9OX0rx8M+usbgz3g'
    'Oqiu0LUfLXMIuJIprNxVv1ZWPSq7bPF1KgAn8bEn/1+dVB0hX6Nb23sbFMBKAwZ3Owim5PJRyABq/yxxmCEqCUXj/vjx4KO3yhpq'
    'JSj9wUHn4ONmJyg5bLccuxPq58Y5yadgu9medh2M+rrXEldccO+4tMvmxZaZnnJ6Z/t27ZQ2LR25m92nC/RV/jMHCI/8jBQ58k4e'
    'HsvSyY/INwQP5rt4qp8ahA/bx9dz+xpVzkv1DV19w3p9lQesVP7LXh7G87t817QZ6PdRbgKE7YFCrDpUo0U2ufPs36EBLgMNOSh7'
    '/USIwrvaa6mK7XoA7U5N/zeZRDdCIHvSfKfevpHAoBEkMw8oHrZiTPwwmyHrIrXOJ+NcxNUJyWS44RaqH0DIlFcFbSZPcMGpdnBb'
    'mLWhw4AglXSuAhPCNsTUo598+D+F11PKMXlCTKYnAYq1lQyYlaX127/8N9Wy/fYv/13ajeQSJ5lgEP14wsCMDlS/vK6xxOthrmI/'
    'CncpOR1oOUfbxWiMA9pWMwCnp1EXuyBGuHYDZQc9mw50Px8r5u+4FZrE9aUAWLLfibR5AySrX2ArgOebL2h77RfZa6XxuQ3S/2XQ'
    'Y7+grrAOht7pOlcL+nLW+75ImV2ipQ8odsqg2790K/ULabIO4z8R7vLB5lhYO1lBqQUqraf4G7fYL4bcXr/K9P9Y3TomABW4m9W3'
    'SqSaG9Z2KJWFNUqiWlzuDK1LqtqMJtMfWO9Fgmn/JWApL53eaG5Q810mx5NMfFAa/c0KmuTUElSFOAqzgr5U9rDxYcbrHBQfhSP7'
    'uPuxkQR9LN0LnfrFgF4sYdxMxyDvw/w0F7dxxSyerC3LgsLrIjsSjrz3JOOz3cNOXTgvochCev56LlOIwDuoeX0QcjFisuy18+xq'
    'W70V14w9pyc68OBjQIWTUEl7UUG8qsRgbv60sbFxMG0Dkfrd4NFe52DKB3ubITonWJT78BkgQGIU5mrKbs2/ge0H5cEfFZLPLNAx'
    'Rhr4/PxEzcuR/FBBJpO9V2V3ZU03qnTenX3dOGyWC4c+9e3BQJcJxQLAT0Sl+2utwUf84/idTv0414fkLUfva2x5/+Ay2RDxbRub'
    'tNrb++fvq4Gu9phJZbyYE1qUN6HbZYN8ZaAm3NQ6L2vyXit6Ur4alF9o9R61HBf1Xhp/T12jYat3k43HsbeKuausVfGRNn9a6z1a'
    'i6vRBOmojEYKAh7Kix2fIPy6oSXXZx3Y8qEP6ABZPk99fqQb1CqNgn47A56ximZevb/+RCdZr9Sn667+AfWO/nIWo0zz+0BRsNlp'
    'H/Ryc8D6eCAdTYuzzsGmTUKmSfQidx0HjdZU5eZBbzL0+p74WwvyX0SSs5P96SCI6CADSJMq1NJjuFQaE9u6Qzp7n50ymL8+36Jx'
    '4L70/WQ0n7QP90Fs1FULzp4Pr+MPbhJLTVTkJXDSSQoVX1KM88te8gLJgZJ8undYatwcHd+q/rG54t/+9q+H0VQucqJf4w3WmNrh'
    'wFdtkq0qvzViI6+AUO/MwlobB+WAStk2Az51ZTL7PkoLkENjrjpoONHKn3v8V2ot+xpGbRxduQYsp5bbBbg12FA/q/a0N8tn9WQS'
    '2SDeVEdX3wed/8p6V1YDL1tkBAUzOM9OugZk6VlBeQYPUloRfnj76kUuJ2eKWHZ54Xr8gHNbMh4MR3Pj+OJheZsbiIvegZsVvZYO'
    'i8nB2kgCKzOMfzntXD1YGaTtyuxQ7ih9G1bnjt9imfhtNLIla1HVmZnKG24LpDNciyvzhVWC6BwVaEGADv4VnCW0INX+JQoZu3K5'
    'dL9NQlsMT+6g1CroC448Ait8oGviuQTtTcb2yZb6IHZqodSbJ1x9OhJ7rIZiNU3LREfEPn7jAazC4MLtZM4w6FnJ8KRx1IG78Jae'
    'NOREvZgz5jYzj90ZTOugP6eIIqCx1ldDX1ThuiL3FjC8sGoHduDBg6TtvDo+0oVCeKJ2e297IxHOcrrXAeDjRPWqZ2opsfV17fTP'
    'BuQJAAFvJubA51SjUlw8MoMlbkpZsZ1jT6expzEw6E/3FRoUMqD76pOgQQf8X/GotcxBxgSjimJLkYgDxKkv7dxSl6HNDEfvXSta'
    'thTOg8Zqbl8wSMjGtuL1IEJ53w8Gi0Fd56UEDDPjXMdZUggdkZro9WA3N0hDolgxhgnIXMkki3Yzd3HWcYpwAejxscPfPimtojyl'
    '2lr9tzRZF37tJLpICP96vpBJPLpYZDIzfgjqr6UMli/Zblgb88BbdnlE+ezJYNQ8dtQJhT7BBgep3FfLe6e0Bs6dEI4m8Cesl1gV'
    '11FCggLWAsAWz0WsdCCv5jZv/tyj4FPvoWBd1GccXj4zaEn1zR4V6kGhVIdAia6jPUN3jIenz5qGxTel4XyMQlRcCp8uTFmbHfrm'
    'VNK3fKu2DHYvxqOuiR4PTJ9cC1XzH8mVCrxcd0kmrXIWSbYEHs1+u9WH7ko5GNZihybGDPe8ElMc+UMIhJnnw1+ke9MFTmO7dUTc'
    'qIzOlirq0t6p7cWSbVLWtGncDKhR1++wrqeRXWdzLtLpaDH6i+VBrxIDBO1MgIcq1ezRyRE56tx5dKTOH8rI0Uh22ZfUbUW86Hbl'
    'tigM/uYsE8ZigdgBmq0t0KHYMUfdUpBHHGLQixh7tTJDPnZuYfg9Gr45KWdRDWkgXw2dr6XDJ2MOMPWZ3XI6Rc+Z0oNWQ4+WRRyh'
    'hoaIo5hrIDyFLRRBW0bcIKMFk7FHcsLlVIHEwD+T8I8iBEVpoSgFQ/NX8et80S7rdKsgUedQKxEdSssZq9puAiYvB2lhJomGKl2t'
    'u+Rjpks0bcJRclBg6rAW00pg18RnIrAqOcPrk94Hqq7Pk7/jODvJo+SzJ1vJho76UfLYAsCkJPPYtyNl8nmyaR8hCYkUfvJkyy/I'
    'xBwW5ZvK2pT9m0Xq/9/i4Tzpn0Np4H2cp/o3QgTwI1JOuO3hPCXTohidToH0cl2JdqvEtpXUNAFBSKRHPe/Xjgz4tzedToQh7h6X'
    'qil5SestXL6ArcxOuH+n5iAtfzgNg3fIdOHg097POAzSpuXWjAICK4hwo+HXhHMgS7GrexMCg4X34HHVN7Eh2NHdJB8fDDYhNzUq'
    'OiIJTRabNEN54aprfjkygJ330E0ysL2e0dBhWHBW2OfrntJSHayBVNythbLajp//7KbQNk+Twkua9HwHNP2Y0fhhx3Vz6VvzIoan'
    'b1jKekmfzWraw1at5fBzVAK3qBbpWFFEMJOk1o6oU2LKt+5C6ylaFKHxalGoNV3mRiICRbv3aK+zDS1hZ8/7CqkHjWwISzMwmYQJ'
    'UGtTzFwy2YNOE8C88+BcXZny4GYRk1aN4YPE73bAOBqFohbTRKw7hV7fUXYJ54yuFNZbIBRNIsSUbqPVegIJeEXT+EZvbQ1wTCYl'
    'EPbIsztyCdewQ3p7y88Gx/Dw1Dt+B6755s472+8b289xxPFQGMXvhSmS4x4F5Ym4QwXSfCL0+C8ZyBtnGnwPsfSE0jESZ6hx+QVu'
    'LhdHu83L+UZBOAvjI7qKPBPxAUZUb4dqa4BYU+67lNolZAta4Yfn0dUmjNolsWqGWaMD7h9Hw6Jd4SXG6RXigs1XV4EIZ3N1s9a8'
    'DapYlEJdCvFQBKIvlkYJACenzDdTAnM70eB4ZDYGR2jonmejYfYHcDedSLv4ZpYhHPThdcyimHJRgbHWHl77adbY6pt7uXDdD86k'
    'LuqIeY8aromGOCMumR99NZojshkvXbYdQMrh01l6ilTo51nBfTPLTEmLXFHbMn4dOZzNuxrzatPeu4evX44bwBGG8/RUxMF5FbAD'
    '4uO+kL7iJJvv9SDvFHuRXhSTVEA0bkKIwMZa0WA+qyMxnFDuLDfKoe31ZI8EfLdY2dvQtJUTCVXmIPg89ixg0Nzn5WY8y6btSGUv'
    '802Cms3paaELvfYivxgP4X3O7cVAYc7wdrIGh9n5XEhdUcia6OXKm0BTF49VeHcAFdG6NsDbENSyPiXBcIC0Tx7+grOiqZlOLOQF'
    'Ist2ctK7zI7OR4u32ThFDDyVuUgNYzypOhyfgDHS2auDbHiPfNX7OiNBk23jPz5hDeH1jIMkAY8ztyGkWv2OgetuABv51KCmkvYa'
    'wr1xFPL5WjdZUw3RcA3O4eiGQdVllps7wBXSICq0CuGRUv9X+YW82NCU2alhVsgpKqgcAksCoU69yg2/EMBRdMBWTCu9apFdKFPc'
    'ULsq0eEvPXAh/0T26nzeivOSAbjYwKWGwBoX2TEdxxbXMn4Ikjy5YzGuGmCW5sr2jZPFiQlvQBRqytIehCG0zm4qS4sbG+JO+3Vb'
    'w7I6BLd4rQmqeh868HmhmBOVuIpKXLGEXqxlqcDNmyJnQUQYZycLhhu9H2WXbAdC1qOEf57fzD4cYgVmocgVi1yViti952t3+99m'
    'HG63PqZtz06FL1xPMu5f+bTh0bMiSjagSMPlZn2ylsbHtZSwspS6Q6BuCGlZokV1HHk1VUF57/gPDHWm0vongc/EO8rtnPp0uURe'
    'jIKErgR29v9swJqb0qa9uee78b8NYyleI4ck8u9DWYpr4l7ziEcrRlVKCVrri3xbvD9tupKPxksw1sbnK+DTiH8RTMLj86XIU56y'
    'rY/PA+yRfO4HVbkIhCEpCBEiXOIiVR4O1Ncld6tdDnQ26s2uQJ8ns8JAOhlUR3COuWwVaXVHiX5+AZjY4xzlgT7aGmbvW2xgSoAP'
    'DT0FZ2wNOlL+/Pvvf/7Ty7fvXr15jRvzydaTL3qPH/e25N/fPdmS+UOBH77/6vn+y59/eEv4WEYwbG9uztPL3ulocXZxdFFk82PT'
    'nsou3/zxuy9T6Ck31cC1YUzbJnjkzaGs0qbQICj70iNhap/PZhSHbIq24z51XX+3HWD9cTp9pVPoH9mUwv+QT0B6dXSvXr/bf/7t'
    'tz+/23/z9iX6Xu7Q9jTfsI83cgQLSrcqXhDjPB0+Ry+jpFF/ePNu3zlxRCNQTUs6G7Vbm/LvJl+1OhWzHk+O+6rnlh8ZOCozLaQk'
    'XhwQFa5qIIHyF5p1ddn86WF0JcmsZXNuVtC8EqA6KpAL4SvZIuN8xnA7bCEagt9Du16tO6rxa6GMn1Thn6x7TfUiKk5/fSXT0a6+'
    'FoLdNf2+tf7iLJPT3Qnk+H51Sg2K4r/CUUwfDbcNAJKoprLq02HB0AwgoY6ZkIcZ9WBPka5fkFfSd0SgkEWGzKoMEzXcZFVkzLYZ'
    'YsMRTQMuMvCdcEbCI0IR9kokrLas6c/vXr587cS9to2zcN8xvYZ0QcQdcp+M3B4tthVulCkfmdUOCNVXwM6QQQEcCPzgxmI0Ec7N'
    'q5Osyj1XNzZSbf63k/v8+O3FtOPm+MvFlGKbAzgE4EhrVGxIyx5oJh5dURldt9aMmiDi0wAwK9sYejnhgZ3vNxre66hxdYGdKqkG'
    'rXWMvfEDC9lF002e/G5ry0PzL17hyhPOYMUHX0C3/cXWVvaZW6QTyp+L9IhMm24VPBsKvTXwfl17N/4GemPzsFFkGXRnUuuf3Mqn'
    'tuw/7L9AdJkaXLCUCs50CdwoIEhtJ55GP+k9/vx3nwF4Oll7krzO3/PVWuTuGB+q992wK1utquMjnMeH15/fdA568uNg6P+7yfQh'
    '8E4L7mSTsJvWXdx11sY/Pel+ex2aqi7z+mkK8nVNCEj1rWyYDCVNIezz6YEblqlE0vYL2b/U2U+EsIgc2KKYJH9fZem8VADz8/ey'
    '/4GBtP8CWnXzXrq5F3LSjvNTcwZRkh0/jVwysOv9qzJlK9NwU1/gfG4nlyISEmDMrqCuz/2r/mWI9zT6I1sYiDYMARfinWeGRKaP'
    'eKm742gpYXschX79anqSG0PqLsV3C9SqYJLcotFjTAM0MtjamkjPILNlx7ZO0hHQosow9f4YxnH4i6nJeI4eIAo5PEJTFwZXL2Uj'
    'YrHIT0/HWbt1lhYb2i3pwv37YSydW2+naNxyp+j5pADM+2T5tffpVxq6TmVitdVDd2k9vA7P3Zc3ADFif4i9rDsA0WJrf3LXlrve'
    '3Sor3V4jofPRiS/OhNMTLj+QumiWyrcKRe6VniNyyFcUOUKB2YoCgEZHGUIRL62FN6i7A5iYAOtuPnwtmR635FaisrB3nFXDu5ot'
    '3Ra94mIySec0NbaekxC5zZCfJAbv9pUpDK0vp3m5szMRAqUKOUHyptwQ2Lxo500NY/4rkbLAFeIa9nUux3h2cI8UNb4TmuGQibXa'
    'L1OFWb6Y2gUUZVzCzArXIfJf+0iWDavi7rCFf5F/sFuVjCVOXmkQK4/Jmlz3U00txYwxKb1XmTgaKRFmF0djJqei5yqj+iFLuE2t'
    'uXh7hGwEA1FjaqUB+sVSLAG9Q81GCysflwgaeugJF1bghf0RCzC//e1fW8s+NvqGDngFHissSUDJ83mmXB/jEvaW9sXlGlj7s+b6'
    'QALhnJd0b817y8rMB2YUcNA41a8ZI6+6j0h1wavH0T5cNlQx5Kc1igDrjruSgtNqTBIUf2LZSZW3o+NxhhN9tqLY2ee30YUZscfv'
    '5rY2rJMDYM+33NvyBo1ZlMwzijjSWUyi+aGR6JIoUSmlOol4s9eYUG8g18CtZSPKJpDdpEylw61X7q4XojF055Bpq8yAelb5InOE'
    'qpmgZWbTV8BoFpF1cxXL4TvrxGMzC1ZUZFZ2D5Y3mmjBbysoMEb5RWFjswx20X4Nm8ztVbI5r7PLDI4Ejg4ELQaQMWBaZW4pTTQF'
    'uh1OBjXJjgWa5pjxqeX+qWEACeHO5mX2I4jZccLaqoStJ3XzWIVB7y8676XvhQIgKlRO7Ty415bynGplDlUog+6/IoGvc/OiV71f'
    'iny6t3iGDUc2Vy4DGCilc8K2gdma5hsEQwIP2mHxdswxz/2W3C1J9VH3ZMor8xLLJZN0euGU5xXuz5PKnbo4VZVLw8DLk27QkjGn'
    'qYZjr5SZB2HcdjOexTewoiMGb8ZyN1FdixcoyWmU45L2ci381ahAvmekpq1ekbHkWJ0Bo/eqWHUzVbXg3OECsBNcmcWbiAv3HfQK'
    'c+W8175NkQKkomEYyQmhOq4mC3QpsZuFeXRMVEwkDbpMr8pceTQFXEjcGloFMIxqPPMdWavt8vt4FdPb+CiF+gz9+Cav9eKOnFOl'
    'juGowJEdxraISpG6sSIUkDlqKFE7VBGnFQk678uMpd/q5IPLnbjVIlXFI6aWyBEzn7ZELft06yZ/dJyqmZEMgLFHyEFiU8atIgtD'
    'oNQcILCUOGQxQ9hBOXwZgGt3pHJlLcXG8dk8n2R50YO3+d57Ur33y4mdAjKVnWnSVUxJyxdOe2fqey4dsWJqMZO/I9gotDBAB2C1'
    'Nxe6TXSOHdiRavw8PVs9mhYKmyeC68QtR8pvW5HHE3hK+LVY1ZAaaa/gVeu+L1TaH7pESRl8h2hW9bHhIknUDEwx3avStNL20DEs'
    'pWrVDK5IARNOnGvttsng2ZFtD/bbXzDLLmZgF161rH0dA+zrHT+S2IC+c2vb+36Q1IsetBQXvafCW418lNLZyan7MxbDxd6Nyl72'
    'lnzXJY0/zU3kEZqtZJy47S6LryqDEZPjNMG3df2tlo0mTmoID6MFKAP8KXbf77dKwH0BYu172WSjIlM0jUgROu8iRNFFnpjaq8IA'
    'KDFobbaWnewdS0GdMwu6kZC5i4EKrjNAb39/00LcInN+VwweN/dUTwzqKwIOtms7+A95uhq5D3kSLcWiQrxi625G18vvAM5pw82t'
    'z29c9bLwMClATVSr3Z2wthQaqesadGDji1PF8LQYLiLfsDJTlEUVmReSasSoAch6xxdzuGXuu7xAS1TuFtkStO6h094IUutyzDY6'
    'M6npLB1nAhOH2/lMf7kxH52eQVU2nyK8PmfK2ORyNJXxO483569F7t9KuOPU5mlBM8rIwCfRF4pyh3YM38Auz0hVzXuvSQeJHWu+'
    'V7awe5wuaehUJFsYVb5EQK9U92I8kkl9K/dHG4rg64Sj2k4YNPEjUox1bbz27A8Zh30T6SJ/nKczeCAzt5nOirnzT9IP7cdPulFt'
    'yYacBy2DdCchdVlzbZZptKk66wjqs1LlCm/uGaKibMA3R7ph2/GUdRBtjcftaG5k4RlfcbHg6bvlQ51kUIPUBV0VihLcDU++ZjjO'
    'dtJv6WK0BtySdf3XPDOH+1JjavY1XSkPdJWRRoZVYRiFlU6L8yQ9BZdEs5uzhZD2KuUts8plsxF3EANK8tCEUkI+uX+/0TRXshhX'
    'bbcWe3nGPKNerxAs0pRk/HNvE1AHavULLg2d4UkXC7dfsABWU8m0iQYdI4nfnWrpxjvH96O4KogZAVXWjzzRhWrO9rwuo8Lk7yWv'
    'NAcviAR5GKYPN6uoC2hVR03awQzpXxmc0cKSpSgTG6vLnMbuzu3KWhf/Cc2W3FWt7QqVtqhkH9YdOOoqczNyS2S6mvp6uxum2Zjp'
    '3G5XLlC0ONnwfvLanYCujrw8b8EjMKxTK5rmu9ZQnvJWSeguM26BBR05Z4yqQ6RzhKnO+9JrvEIVlk5h0lTr67ypSj3vjVbq0kGX'
    'Tx+XPTWWNlzx65Hjm4MxaPTuXGSzjaOrDfxXSFFRQKCGl+dsjqROx/76tGRDLCdUT3lQbN7cEmMwB/0YV4Tq2M4yl+SyQFPkBjMn'
    'YEjN5/4U5CcnmvlzhKDxjFW33kvL1NgtEN6gDEMR3+da0ZjEXN2GUrRzIpdJahHjC8XtRaVTsIOy9XD4EAYNRHCmD5RpEeJIjIvz'
    'EZ27XY6ikywzN/bzDO2nyg0wsdlFcLxTgrv/w/5SDx43/63I75RdglfGNSrb6+Fvei9kxFixWr96+e3Pf3z5Z/hJFt+lx8Qa+8f/'
    'qYoKimgt1/7FyMHnHj49cgllL0ZIKLxQLFVXEn7JjCJBYc1sEYM1OZ0B/nAckCWes7wKcdgx3YJ0JyN7QrsUYeADY9mkcni6AicX'
    'c9qfqVhFjH8O3GYmmMopL3ERyNwLjyYcE4pKW/QwsHVisqMxc2IZNnL2IQXQUsSwydS+y5CXs+JJELopzNYWYvNtNHy2E3mDc/9o'
    'TpBhe8IpmoRUIa3vcPXLYqdMxxdq8TAsAO5EiLklWUKWJCLQjIq3eb5oT1kjp25an7G4lqDTYZ/u7Hsch71Q9WhJTSq9//gxuT+J'
    'N0PHjVPKfX+WL3K5e+DfNyoi7y50U1Ml/GguAzzjIHPuwQSBE/oAizeC+Q4mgUJTGxiUWH3mniafdZLXbXxOU5N0HLmofEoWtNyv'
    'faaIma8wpAhiBQu8RXSQeJkVEA6d/xZUi310dP9FOj+S/TMc5R9kfkpd5WIdLV+sp7JWpY4flToubfZvqaIyCIvdsbA+i8Tp7NTC'
    'aHysTOu5cGWIzAEttEPhgp5xwJS0I2xiqtBlMQl7+f07zIlUdu2Cl1o/ZmNNkZdXruRWV3kFRuS2DaZ4tkuLqr91LtOxuy6MHjO2'
    '3c67McugwcO8y7tET/OCvDXUdMYRNN5KCGA3xZQ0HK6o8kWkMqV2ggSn8Q7Kp8dZ5e7pQSPDzp3mBCDR4AShQPBq0yGg0nSsThbn'
    'IhaU++Ro8WI0W9t9tbBAIvJVyeOtZDKaXlDP79oRoVSax7inVypP+PxSD68vhL/7t39udW708jPtDg7VmByJ57G06J6UdPK0paVa'
    '5DP27zC56ZbWmKZQMlcTTxUAHQ/hX14/EKqMaOXG9X6J9TRVoxe3VfzRLqXJ06NdXy+uIyfaT0SCQFbGV1BjuVksLJ8yIeaTI0QK'
    'DFMa92TWFJ+vvO70oJQm4jgRtiI7NlJXW2LHIr1yczE65oLP4bTzflSQh6H/ogaYPD0/Gu7S+fzpJn6iPiWwKxb5hcWyhJgXH8zS'
    '0xrfnY1OFutxvTZZPnErNeejYUjmvpMgT7gC71+KwF4gsas5KHA9dWWGdDTz/hwNF563QN5+pRGyqLxLNNm8ktHS9jgirVuyP350'
    'O9hvAb/E3Xim99Mjmw9YZnUPvyKoBTYyfAhljRXdB6vboXNp1CNcdjiROMwy2eU9sn81001AwBVCRTSu8bLpbLzcHzdN0AROh0ch'
    'tVQ0S2bWXjVPfjCNUxRvmhWTZO2UZ2maG9OVmbYir8/SHxEmcppjFr3LcUQSiBwn9Qslz8IY0cyKA/EaqW8duyh0VNPmHQNG+3IE'
    '53j6FbpoVvRMc5Q63dxcWj8yunrXhfmsujDfiKgiY+P1fsdt63CkSJfPQJb9KLRnI8KRiFih5zvXsHLOWEgcW95oYYv7VdGJhZPp'
    'vL4e2E+Y78ucxTjVVtbnJtS2VizAl+7uV++pZQOhf+9wnsqvIyK5eDRAj8HlhhcR+Smp8h0Wh9zvkRcVjm7hd6sL+F2Oe1H3DhoF'
    'xwvIioxO89QA3u22+qFQHR3X47d/+G+//cN//+0f/h85OLYwmoAR6cSwRlBu2xxYSJleaYG6W2LhGrUhJaJ04q4z+8ZupCKgIiX7'
    'OVZZXVz04sL9hKNgFtQu3g+jYElfSivd1nU5vpgXQhXGjBsImSixbubb6e5Ymvur7BMCykq72DbOaq5GCVNxbPMnp+UYsaSpRlfG'
    'O4PX3LaleUnUD7AIeTExsS8NU0YlJviTUWDqK/KAyqtAPtTt4TYba6wKWcy6B7Ji7TBhOn9a6tdy3sf6O96QyGpb2YoqexunIPsx'
    'X7oPj1zRB0c/sFzjjjT64VmGCs14eG16gJuI8HPpZXDK3nXAQRUlKmuKx8oSv85Bi7E1RwtF1GM5tvNiMR+v/32lDQxPj4S08TIw'
    '7uB65Y3pTlBqmilXGupSPsfVOM+GVJs20ApD2KISBKlmW2qAbik+Z/Sck11bD5jFdNJE/MmWLwbKKVHHgnyPwv4HUA/uuDzOCXUp'
    'kefgX+iwt7X4sfCaHLzOdyQBOcJvmFql3EuJGTCHVeqCjWdcpbvWm/dOtA5/ChfP6eg9RXHe5HaLiGDqyDxoCwWdUEX0MSdZbW9n'
    '+djdJUsusDqhYHVfWXXDC80cyAzrNoLAm4C71T2FW1Lqn4KKMqc653PopAvnxqF9o2oey2M4XzArIqAN6gdlMkjoGLy0yPM7bEfd'
    'V3U6ME9PVfNZ2M3077qQWE3p8IPWz/NZQnLMCKp4jYNks2GJqkcLpecwEQQGknd76oLvlULgmvfblkJ9SsGikVrUuDi79uXWGukV'
    'MpEleg/o4uci7W/gqaWUd6MBmSAQOu/R0/EISGukOwwT5UUoCwSBxFeh/HvEDlKiH/FOaonUm3IuZhcLfz9lH9LjxfhKk8WzzcsU'
    'mQRJoIPIpZtuHegb7A/mCjKfV4943e8oIqYr5qSEXpBNZgtIwRA2q4KJrQ4GFngJzxGsuiIVG+kTL0nLP/qp16Rri/dilPDUv9G7'
    'sXYOgH+TXMyWE14UAKU1tREcDJachdIuI6sqZ8HvDO58eHoy3gz7fz4HyxRvxWmWYiuQwqoChQqa4bCre5CJQOne5LXOQftSyAbQ'
    '8wQ7yDzeiSppOcWXiFqgHxW6/KOeInzWjT7C8CNVjIwEd8HFjFYPxiuwi8V55LzV2JzpH9SXSvtKOq0bsNTYil0LLwtnU2Ot6ViO'
    'rDKfMunCIVxC9eAO12m2sOAgDRrT1AWgpsJtvtfUqsVChLTTs7tc7Qv2j4BX0VNGqg2j7dFwyUMmLJZusuISZrHs9kvcGIDczbQJ'
    'm5yJdnggAxvm3vlK7onxUTrvuOsZCh4tx+ulfBW6qbydqH6DizhiLNy6QwmDRbe+qe24Qr1V2aUqIxOREdk3wv7F2ZnKoYRZ7FRu'
    'phl3uU1hcpIOlUTJETixS3MsDy7T+bBwMgOFPUrm2qJQU4LW40a59Vjg1L7VPtkYiljrR4aDEy5UvLCzapNnl4MbkubtucO+ImRY'
    'fdt8DTgvonct3TknX4q0K+Tp5BWBGPHrHVTQEIDl5ej0VH+9AzoifnytAI5SJL9kBW+Fv1gs2XjfwnyYwqoFxiw/ho113o03FVZJ'
    '+lg0XQ3b8d65GO8iFQ2E86QdmKkv9V7r2DbBGOLXr+w1M9W4qpjRBiv3/Lf/65+wbPbXOn5j1xQ6AzjcR5wBDqy5jndwHXIfUrQ+'
    '2iWUJNe8PRshHvQo/9BNsvF4NCvUPUvzozDBSWokTb6DUQ+fsaWnmzLkiO1l9gGS8MVl3ksqrZvui4thc7pwimDuM3/QuMcWuWG9'
    'LdNd1C9Kzvz9ANkn16FON38zBbH+wuD1J8ZT25TfG39f2ZLOIl3foqPnw2G840aAB5WtOHpL77tlCiyj4NRfoeupkyxinVVECh0A'
    'fqCF7snoGFFJKfV2oH4yzzaI3/72r0FeONolMdF1r0kPHSsDBoxFwNYDP9/fH8ru1nW3JZpBk2Kpv7ZDw7Zlb9QzsbiFrc19LdIy'
    'qOaeAjLQyOMCh+6+RQhvWrWtQLBbzh3Z68YlBFKptzQJvVAzgMb562buVrCyYl5Aa5ajEa1FpEHuNExz5AhptqpaXuEjkksHcMjk'
    'wpWMwT8SjcvzV6YpYXiprhuqX7EoPssxfAEK5/EMz3oZydHuA24e6xc1Yxt8gv7xz0eP0MdHj6j/dt2R5/0+zFyDgZOgCGVWk6+6'
    'TgYjfLkru1BZj9thOyH8OL3szPO09Ckmd9NEXPBrBa15jvhcqQkCVCw9XbazNGUM2EF1zKjvNI/Haz+jlGf9n3YHj3YdUq0z6Ndu'
    'RqEIQYVxmV6t0pwo+vB/SEMS70xfYXlzbrqNCS+7E+lgoXJiRU7rKmsl7aVDUA9ZB5wPLMcEM01VucJVXBzD1wejq2x2NdPZrcN6'
    '3EpfTNEyzxNcO+MVmuVwI1sEzMb6snigZiRR6qGm2J+7gYWxIvTLXFFbdfl47bH/ZMiXrx1gV1dIXNW1Qx4h+cubfDp2evOyZIJa'
    'Y7GkKHUHZuyh+fMAEwYMQU4cWWfInYO7Fj5H7w5VQh7tUtFo+idlCkbTrl3TPDDC3p6vIBzGxSCmg65EEVeOzkLv5dhNs7KaisSL'
    '6XrPEIT2zjR/bDj+JqHDdNDWpx0P51hZPeL/0cR/6SwIq5fwfCl7CcBX5BeoVtfFQOnNNxzBOxDSvDuPxEwk+cL/63Gx8NfKMals'
    'D9sMQ9V8OV8NWTmSUlyfpp/KFaTIXPcJR6Oe+00aLZF7y0IsBww3B7s43FEtfbRCa+JQ/OMV8Uh8blGajuPKD5JdX3XjYVT8yttP'
    'ojBuFWnV+u8M9wqwa/6IPFNpoWqwPXI/DoWz7MwTIUuvHEbsOxYlGEKmh0HJF66rUP6ooAznH7mVlcExPUi/wkWnBhe9HZn8+lsD'
    '4pgj0Tr+e7NTwrxM3KJUN7rS64BAWvaroEb8oshWUCin9FYa46B63ckwuEtgi8bSPVmtGj+qh44Ko/RKsXHM39UCyEUC7yo+cJPZ'
    'zmGo1nBOKRLFTiydUscNhZUOqU9HuwGBFfnqV1BF7a4IJcNMNeYKx4VD1CrcQA2blSesVdAkKdvYAKW9D5JSR3ZjNGU9+nlXtQMa'
    '1av3OyrVr4XjGSt8zs1taoNGe5fq64rYlIqKlxHoMh54tP1Jsy1ptt5XIqKNe2rw5c9Lhszwp8/2YEiXDQZpwmGlOg3NXlNHVOQ0'
    'b+g304yBAkE8K3AzyUXn65JNhP3nfPhMp0m3Jfq9Xkyx96kzrDiCdJPjsxzstuy/72LHq66y0emd3GBWKK1Gi8jQQHncNPTcnr0k'
    'HBHeTU6ZqFaicOzCUFeRc7ovBTemFfTblWj2K/BVVVnhKC1Mef2+ZmKMxvV7TnVF+JJH+2ScQ5Njt5+IMN1IEzfmiijfDrLCaxdG'
    'DcTgA2UZpgd68t2+qF9XGsZKOkJR0FkTjgXLF9FfuBWzhREkXM9BcospmHkOJF/BQJXGGXWabnZKV85IdVeOalRgdOYcvdQKT/kl'
    'GFLL63a7peEWTXtJ1cGmwlalv5PGQwTPKJVWKLUu8ojCOkY2uxKxl2onBcLXE3wmBa/kMj1qsvD69l9+mNEKqqqxuhYVDWI4kVmZ'
    'Kq6L2SprrI0r9uKy8KSQutg5/piIFSmYT/N8aIqIXy94NUvjBHy+XVeLudrmSayb+PmOsXB1Ze7f5zD30tA/rZzT0TL968NrHztB'
    'pZU5D2LO/pLnEy/sF8fz3OYXwoljcDGPp2rbRdgFfOtCQauDS6l+UN1gv61VgE9aN96pSC3Gy9dd9yUGVpaRt5wyDb5Hc+dEraKO'
    '88sKFla/Is2bwICyp5EB2t/1kSOUTg79F3ytVdt5lWizzDPNmMHfN83yb7T0GKvuB8zQcInMzdDU9KhoK7x4smmNyc8N5G3aTbZ6'
    'W7/D1c2SZ1ezfNE28PINV/ZDNzGwcv/oqsO0uR3XfJDaG52lo1ik0l4UhgM0q7WKjaVpmxewd8tWyE7EOhGORbbQD9MiRTesEb1f'
    'gGqE8ErHF1Il5REDzEbEfq70ZF6xJX40G3jqqkljRAINH1KUATQHDoZsMyFpG2/zklrrPvgxRcmqylDpeyXjy9XgR1Imi/XgfPC8'
    'WHr09QSVzAP4oqqffueOlJK/kosjPSrkO4vt1FXgoJUUXpnpmARYY4HVGR+EgKjrLowqmvKH14Y/c2hqV+0qggUbffZ1cygUeDmo'
    'PS3OTc+CzaLwuqqoB8mGv9+4NJ6i2u8iS+cwu1255XasGpG5qVhMYHgBw+exJVxwxzY9mhBn6bW7o6I5SgOok4eVrUa4C8Z7jQq1'
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
    'eNrtnWmUVNW1x6+S92K+EKN8yIeHl7WQsUERUeZu5qkB814n0ZWlGYAGGhxBGbqBAnpg6AbtRuNsgiZxwsREEkTRICgEYxBDHAAp'
    'KiAaoAfornnab//3ufdWVVdVd1V1lQxJrfWjDufss8/et27fuueevU9p2mXaf2mjRmn83k3rPUbTfqhp2oAB6v8v9NC0FVzXrZvx'
    '/ys1redcTfvud9X/135L0/Yv0bQrr1T/n/sN7r9a03qzDlaprdRUvby4YsLtinRfp2Zdq52Z2ePiYMa1WrZeZ2b1ZN97yrtQ3Iv1'
    '97iCx+nCdGW6nWe6GrZcIbaZds5U5UxfjbN7a/WzejA9BdZ1NVN4ZlaPah5rO3OQsTOO84zdsGW72CY29rzatBs0FPdOy/d6Po4W'
    's3p+hylh9rFeD0MXMmynF7YaNl8V7UtKvuNzB3N6o88w5k0mxNBFBmzeIT7M6WP51darYY6SoXn/w++9buW+xy9Cv1tzHL7QT/5b'
    'a2Df4GNC3+f2NfzvA7lb+TjUM3SJUK986qM1so+N7Gti//uAYcxxhi4xjhu+afVz+8T6XtJX+T+3z1XMDoYuUd5kviO+lkTOgTMl'
    'vcR/Pi9K+D3E0CVKyPBRO12i7g3q77xOayzJA1c3lvTdx9ClTd4+5Wsef+59tab5/bTGeXmgkPEydInjMXwV35vmwX95r2bo34T1'
    '8LkR/s/vD67gY7GdoazA51kTX2+aSvqockf0QMfcDuqJZ7vhs9Z0Z3/QhTnIUIfg8+vsgpup5aGfkev5VeR6toyaK/+Xmu66To2b'
    'qh7Ich/0hQ7ogk7oxhgdtlP52kX5fh3oytgZygjDv+ZVheTf/waFvW5SrzCFzp4mz9aHle0ydnv6+oss+qAvdIgmr0t0Ywzz+HTA'
    '3qNMV0Y7q9AZB0OZ0Z/OLRpBgX+8QwlfoRB5frchZX2eVzdIn0QvjIGxMGbm9oqvuvh+9/VAZxwMZcSd/cj1zP1sc8CyM+zjcyDo'
    'jxyCUw5qXjFRjZ9MD85520SRtV6sQ3RZigIyFsbM2F7lqy6+3zMA6IyDoYxgu707non43tJIrifvJe/rT0TOX7+XnJtmsd39k+vh'
    'NshA1vz78b7+uOiCTvOFseQ4Zmqv8hU+a+cUOuNgKCPuhv+/iPX/Kfb/jadi/Hc9XEzn8LeSTA+3QSbGf9YBXbH+/0LGzNhe5asu'
    'vt97A9AZB0MZwba4f7mo1fnv4XM38v/Qv+zUsnKSGj+ZHm6DTOjUsajzP6B0RZ3/GEv8z9Re5asuvt83EOjN9w10MJQJ0NlcWkCB'
    'j3dRslfw2AFqLhvFsgPa0DNAZCCb7IUxMJaMmaG98BU+w/dmRYf8F9geZ+UtFDiwI/Z6FfUd4N32KDUvuDG5Dm6DTKJrP3QGPtoh'
    'YzR3zHcyfNXF9wU3Ap1xiG0d4b4bqGXJcHI9Mps8L1WQ97WHKHz2VMQHdzO5+W+5Wc6BG9R7VBltkLHkua/3tVrRBZ0tS0Yo2Y7a'
    'qXzVxfeFg4DOOFoWDqKOYh4H0y/vljWx34NfHiZXzW3kXFdE7sdKBJRRFzp5OOZ7z/vK2hhd0J0VG9lXw2etRaG3ZMn/WNjeJcPI'
    'v+/V2D+F+i8ofO4M/zH7BJRRF/3y7/u99BUdWbdLfNXF9/tvAjrjYCjrsP3OiqkUdPydUn0F/3mQ+0xTvufCJuWrLr4/cDPQGQdD'
    'OeH+QeTf+WzCa2Kia51/53PSJ2f2KF/hs+ZcJOiMg6Gsw364q39A4YaTUQ56KfDBVvL+qlRAmax7HhJZ9EHfnNikfNWV74MBlwdz'
    '3WDKOuyD77UHYz5z3/bHybl0OLfdqOAy6qLPBd8fHjT8H5wLHIbPmnPxEKAzDoYyw9CL99b1S4ZSYP+2mPtAV8UU9TmYclxGHdqs'
    '+xzug74JdSYcKy0chs+aa4mgMw6G0oJ1uWB72Uhyr5pIrhWjuW5whEU3kYs/2+Cn70WubYf3ibz0jdbDdWiz5LgP+oqOaJ08howF'
    'HRh7cZo2KxyGz+z7UMDloVw3lFKH9SwvIN8LK9nWd/l7/QiF+L7V/+aT5F4znVy2seR5bC75/7yZws31UfPgY+Sumqp8MXVxGXXR'
    '9/3og2smdLhZF3RCN8bAWBgTY8MG5VM6touvuvi+dBjQ3UuHOhhKmWX54lv0vY3l4xefsp0fUtjrjL/mh0Pkf+MJcpeNYL9vFlBG'
    'HdrixFmH+Mw6478o/WIDbEnLdvYVPsN3d6mgMw6GUoKPt2/zA3zN9lBGL+4X5Gu+7/nlQlCu/5nrgi2wKWX7la+68n044PJwrhtO'
    'KVE2nALv/z5ig9dFwYNvUbj+RLx93IZzIfj3Hep+r9W5EPeZswxk0Qd9484HHgNjRbfBFtiUsv3KV118LxsBdO7v8LCOlFhRQMHP'
    '3o2c78f/QZ7VEyjw51/G+rF3C/menC9tHttoCrz1NH+xuZN/lpjjvf0My46RPugLHdHHDWOgDWNGrpXvik2p2g9flc8jNM8yQWcc'
    'DKVK8K9tf/7hM/8k79rp5Fk6JOa4+X61hEKH9sSe71wOHdorbTF+cF/ogK62Pn/Yko7thq+6+L58JNAZB0MpUTaMbV3c5t9scM/L'
    'LJvPY0X1w9jc11MxkUJH/xY5f7jsqZik2iBjyY8UHdDV5t8/2yJ9U7Vf+aor3/NBev4z3pVjKPjOc4mv/+yPd8MPYn2J6TtaPm9L'
    '/vBeqUs4FuuArtDRDxJe/4O7nhNb0rFd+Qqf8zXvCkFnHAylDPxYPY78W8rlfA5/9TmFHB/J36+vpojbRyTv29r/Q8r/5GONYJ3/'
    'J7oxhox16D0K8NiwQWxJx3blqy6+2wqAzjgYSgvDNrFh7TTyVk7iupGKpH1Gkq/2RxT+8lDkb5rLqGuvn4yHMTCW+G0c43TtVr7q'
    'hu+Z+x9DfkrHy//EXPb3cPz32leHpS01f/KpY7ZG/PetHAV0xsFQzuBxfeum8ff6/qSXMrRBRmRzaYvyVRffV40GOuNgKGfwZxb4'
    'NX9nBPxR32XHhciXu19kIJtTW5SvuuG7+O/nOoZyBXwK/vHB2HudzfcJ0fdEkIFsLm3xR/nvXz0G6IyDoZyxku8ZXymP3O+GghQ6'
    'sJ1CH22Xsnk/DBnI5tQW5asuvpePBTrjYChnrOb734dvp3DjyaR//2iDDGRzaovyVTd8B10DFWPtDOWMckVw64bEcwCuQ5spl1Nb'
    'KsYe9VeM7cpogYpxoAtzkKHcwmNXTeBzfDWFHTy/a6kXUEYd2pR9ubZDfO0ivleOB1cw2xnKPcZxqJ5GwZ//REBZ6tD2tdggvsJn'
    'LVg5QQtW8TGoGl/N0NeG2DHW4GscV1EtPrPvcgyqcAwmTGW8QZyflzbwsRA+K9/HasE1E8DVwTUT9zF0aTNhn/KVfV47VmKAQ1XT'
    'tNDaifz/iSX8HmLoEiVk+KiFKgut+O/gmknsv3AVs4OhSxT2beJV8lmvmRiTAxDi/4fWTQLDmBMMXWIcN3yTc731K7R+Avs+WQtX'
    'c/v6ybeG10+uZ+gSoV58gm/sY2jdxIQ5QOL/+sna+7Zifp/C8lOOM3SRcwK+PL9mpvgGH9t6QUaQc2HKMGYHE7oI/Q4Ztg8LG58r'
    'SOXFfSLUFF7FlDD7qKbQy9AFjhe2MvPE9ihf0nkZvluw3quZQqqZWk0bpm5nDjJHmWPnmaOGLdvFtprCqbA12vZwdWHGecCsU6MN'
    't8B/xfopGm2cdgWP14Xpylxznulq2HIF8Wdm2blhqrxn60UPsr6NYJrSfSFTMz11v3bi305Exn+D6r3Aq971s+r92w71/s2d6r2T'
    '+b5SvV9mvmv/eeX01fp4t/48zM/J/NzMz9H8XM3P2fzckQ08gPlp9D4R16a+T4TabwB7DZzH/R5kX4aeae130FDcSzt1u672BxAf'
    'ZA+FfKaYKWVsOabUGCuf7e7SYOxVcPoOvd1c/frZMfsTdGXKWMd+xnke9hzAmPthA3ON2DRbkfC4IwedOTm7G+yfznx4AeXKH4BN'
    'X87pxjb2Ejtj9weQ3HitZWZ37BMwg2m4AHPdYdNMZ/G1ks/fOCeS6910zyAzx30608DtdGEC28RG7dRdA9V+JCV5Ro5632sa5vY5'
    'cBHkmn/ItnaVvHLkV6v8ci73LbuI8qVhK9udZ+ZId2H2sz90UQBblc2S58zkM86McoaNYyL5pyn3y1N9pF9GecrOpvlis5mnXMxQ'
    'WsDeu66nc8vG0znbZDp77yBVl0I/yKIP+kJHSv3iKRbbVZ5taVp5qvP70bmyseR953kK1Z+gUNO/yP/R29S87lYjnzh5P8hAFn3Q'
    'Fzqgq81+iYHNRp7s9TaGUuM6OnvfIPLt/V182I7jIDUvG6dyIVv347rm5eNEJm6JjHVBp8phTdUO2GzludpSzhG9qz+1rCmy8g6D'
    'Jz6lAOKYw2HBtXlJ4hxU5MJuXmrJoQ/6qrzIBtEpubup56rCZjNP05ZyjiMfI+eDd0jetBy797aQ57frrbVmz8tViXMxuc7z8hpr'
    'jRp90NfMwYZO6E4j19IWlWdpSzlHkfvKeWDmRAX8FDbi7cSOTTMT50ByHdpMv6WPEXMRPHlIdLaZgxkPbDbzBG3p5gS6Ny9WuU6t'
    'Ylw9L6wy8rpa9xkgba1jZaEDujLI/bNF5fnZMsmXc/Fn7v3TI+R/9yUKO5vUqdH4JdffTs33XMc2Xa/gsmvj7RRq+FLZzLLog77Q'
    'kWGuHmw289RsGeW7IXcOuYnIr3yt1vobQL6B+6l7yLOlSkDZykFAvibLtpj5fOifWa6ZTeWZSa6ZrWO5ZIPIWZpPgf2vx5xL0fFD'
    'VvHD7SIrNnQsV8wmtj8guWI2fqfMuZmP50ByPz4vNkcWedLB2L0DIANZla/VoTFhs5nnZet47tRg8u/6jWFomIIfv0OeXy4UUJbr'
    'PsJyWUblGnU4V8smti9GrtJgm8r7SYGYsc26m8m1ehKF/nXUilt3lU+x8rBQNuPKIQNZlaeURF9qwGbNhVyjxUNskq/TFpIPNFje'
    '3SvHC1IH29lGd80PrXyawJ4tqt7M6+Ey6sz8GciijykTo88Yo117lM2aaylyZYbaGGoTjFM5lfzvPEehk58JyGf01P2EfC/Y1Dli'
    'nOvBQ3vJtXxUJLeJy0EzLphlIIscH/SFDksf68YYYn979iibNTdyXZYOszGUnKHkto2m4Ievx8dmuc5G4tSirj3+t54hT/X3BZTj'
    'cjy4j/RtfQ/IY2AslY/Tlk1is5mnYmszrwP5Ao/P5Zsdl3UOR+fUqe+kRgp9/oG8mzF3yDOXPHUjNi9OJip3z/zbwRgYC2O2k2sC'
    'mzVPGRhhYygZ0OX7dallR+CNxwVzL4zgX14h76Yfk2flGPI9vyxhvg3q/NwGGciij7kHR4w+HgNjuSU/Y0Rb2MR2lSdiazOvomwY'
    'eR/+qXXckMtv5vOjTmzHeCI7nLwbb6NgVB4R8ji8D96mcj8gg8+T+yTVx2NZORPJsUXledjazQ2wFUicfUxeA5dVXk5BrGzpEDnW'
    'Ko8pTP4XlktdxvoSA5vNPAVb+7H9Rl7CS3yt+dtWAWWJl1/RKk+Aj53/RZs1VxE5fIaZ6kuMLSrPwJZyjDpi+xOVo2LpkTMguURW'
    'HsUeI48gP319ybFFxcnbshYLv6ZQ8l7iYuC5Dm1ZjIG3RcW527IWy464bSNnPXz8oGDltnNbFmPYbVFx2rZsxWIHXlwemQfselYw'
    'v6/QlsUYbJuKsxZsDHUYxFL/nK+z505H5gDG9y7q0KZiqLMwVvlY2KwFJFZ4bGn2YpDHUej1OiJPS+Tk5zLqrFjh7FAqtlci1ndc'
    'sYqxzQKwEfGUzy2gEJ87AGUVw5ylMRTFynaJUy4IVI13ZjUGt/Xxym4srpP15fO7GWPbhdkfXDOBLgpgq7IZsaGaETdYdhHFu5Yh'
    'rjO4VuJ7xX7mGq47cBHEah5Qtk4U2/HyL883YzSnMw2hdZPpAqXBsJGv+flR8YUSW6n51k9DLNpMpuECjJWETTN9NbeIrbA5Nk5U'
    'xdERt4erp0xnDlxAMX+wZTpVfw/xm2JrCvF91zBlVFO4n3Geh3g9jLkfNogtKcbroT1Y9z2JbwtJzJfEgBUwxUwpsyLHlBpjFWDs'
    'kBknWHdLWvF2Kl5tihFnFx3DlWPixipsM15O4od0TZO4om9rmsQZfVPTVBiREZf0n+iv9OK4Lou8m8fRPK7mcTaPOyJRuhm/6WPF'
    'aV2ZPE4rKj5Ia8Tvwszs0ZnRmWs7CHR0bjB0J/ptkZjfEJnVM4+pODOr527mCHOsg0DHLugU3cZvdpi/7dFg/tZHca9OzAzGkcN4'
    'IUf9bB5jdq9O6rc11NiNKsZmBte1MJRT5vAYGEvG7G3GyOQxjq/xdwUcjWpMTeJFSvIqzkO8RwXia5rm9+vM7G5z/3PEMSAmA/tx'
    'm7EZcTL9Wsnktben+i4Z+87+OnMk+d7m/ensohHk+f1D5P/bNtnbHGv6reVQhzbIQBZ9JJ4i+Z7mh5vuvA57Ondn7InX9FVcgnfb'
    'Y+qZKJ5fBPzkfm5Z7Fo+l1En62nyjCMsfay4g8Tr9Biz+7l7BgB70vXwBTdR4LO9FHafI9/uF+V5g2/3C3SOdUT2U75e6lTbiyKL'
    'Pujbxjq7Xca+9wZgb2tNG3tK43mfuZ7u/eMjsWvp2M+Z66z1c2Mf6nbWyTFm9+YFNwJ78j1iB1JL2Wjybt1EgY/fkbW+4IlPyFk+'
    '1doPFuXg8U/Unrcf7xJZ9DH3yE0CxuzesnAQsLe5Jot9VLG2uGgI+d54UsVpfPIu+Xb+Sgh8slvq0AYZkW1/71W7jH3/TcCe8nru'
    'ygkU+uIz69mT+UwKdWhLY/0WY3Z3LhoM7Mn3PryZnA9E7U350B1qveOrz8nzi4UCyqhDm7UH5QNRa3+JwZjdXYuHAHvCtTSswy0r'
    'IPfqSeRaOkzWHH0vV6jllK215Fw4UEBZ6rhN1iWxDoQ+3Nfa8y8eu4y9dCiwJ1qX89T9WPYVDJ12UGDvK+Tf8ZS1515g36vkXl4g'
    'BIz9atEGGciiD/pCR5J1N4zZ3V06nBlmj9tzjfUGD76t1sOi9gINN30lyHrfoT2C7Plt1kftCYq+0CF2xu/pZsfYnmUjgD12XWY4'
    'eVaPl7VdxDOZ63vB/dvIW11E3kdmUOiz96z92FD2/nyGtAWNvSvRB33VXmfjI2s0Eewy9vKRwJ5oLSOw7eHIc8rGL8n32GzylA5V'
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
VERSION = '2026.11.06.1520'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
