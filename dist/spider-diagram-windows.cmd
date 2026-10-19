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
    'n/Wa2Re66R2X+3bfONaZWX7/snBUfney966rUr1UfWSnemvGn3MNLmuPrMEBzN+CcnpR3IHPOCNH6Au9XqphlTpFf6aOFinyNKcm'
    'xtjeFpbKSrD3MImmIJ7IvT7M8qVGSmVPhr+nRuqokC2xh5KwzfEnjqqvrGxR3lNL0tSWdh/0UDflaJOyyG9fuBWu1XFsZTk6bAdn'
    'fymWbN9yN9RCJo2dbculkuDmGE3qc4bpjkuSlm2lRvz2TGVPrtLlR6mZ9dKmc3NdNVMvWd1dCqPUNLuvG9nTFOSuB6Jwl2OmeX8L'
    'L5HZk6gs0UtSnWruYNk2Dlfbn9uVvH8A3iMNZlVnSlnL+uglRfKGI3Wq/b2+yLIdBTVCUtWh5C1Zse91G152NbJ4HWxzzWVIcdtb'
    'aguz0D7llE2Pyh+9yXKysES+u5144vHoLRUggFS9PJAG6wOqlZ2fW32W3o1m9vLgvOz79qgmNUxbbVSNeoqkgPFK7T7pFLaqkOdb'
    's07Z4PzyyNNmCn9kwfzXmkLxvKNOFWWezdVavrhtjm1zNnIMv28KAtWWl6o5YAu7hl1XWvaL6k2Xk2p7XOo190J3axqzrDamJyI/'
    'bnubJb0e072WsWlsJ6Qz9/eCPmCNTdux57WBMKl4o7pEjazUbDdWrQWYdZOqTy7Xo8Z+Oy8wtq/I3OjcXR5TVkeqCyOZF9ixbfCS'
    '0/QctjnvLcnhfkBZZMpW/J5iiUK7x1Izbr+Z71Nmf70seOWXc7PTm+6XU8ZRzmK735gN572Z3u3UxP1psO+r7kiRxZyhqHtAMmtQ'
    '3ou5CVMifd0pnwTN4kcW4PBSVec5y6a1c51rdHNz0phzS8lsc6NRa7BxlIa6nnsypXKV7JCc1JShyO1sn55PZtaEmnep0oC26JRI'
    'mq2GZO8mKjti6mKnStYWhjCCP8Ad+g6sDRgue9k22Nw0dMrnnZZhdDpuljsxI7Epd4UUS/kDqj2irc30VGdHk8Z+ZZw7Sh6soNy8'
    'WuOc7fy83zbng4NnOUJKPMz1E7eYyNxkNN5vho5xKFi1XK60+lTU6uRUazNvA0qzT1rsvGNwjRm1sZvbRue05xtCqqHr0rli5Ava'
    'i9Ke8jvPPk3Esb2TG4YE/DrbFufqXGJTm8nB6Q2l7GIxLOzkWp6vz/2xoHcoMBK9bkWfdF2RNx3Ho+bDETV0WNOpKBvxfGob/km2'
    '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'
    '17Y96ex5h7k3LB+shtfpuKXzJJsrN15kveAMstWyc+yVjJ49BJodjjf8ISdvxjm5vDvu9utBU9tNaeF8GrWP+sw7jFM7Umlxbb7G'
    '0ba5GcumLTtU09R4uTwX+wvgd7oqnefdl/HufOB5b1TTDb3XsSadyWySooqzgt6YjDcnrl4+vwxbEz3P+bZt75rDwbE+tydKll0z'
    'L+M5s1ak6nDP9Vy+XTt65n4HlruSn+3VMkMq/axe9Fcusy8IfMdantak/EIDM79RG0a6YDbbwsFPbeyJaB4rDZdxj63hONVhGKbU'
    'nSntamN7HivrodCumhoMw51qYrXJDwYTlwNGq+1812039rJiqENeJGlz3x3RunujMhgcz47O6rl02M+55nLqvkjakNza586MLg/2'
    'lGrXNMeWNOcA2k1rHx/gizle8Eq7N58M2yPoh1NHDbFEWt0u6K/iYdhKDEEhyzuJnSx7VDM1nPubfiM77y1b5WKHL5xVsbk3eT3b'
    '6IwXZrdNOdvRYlzjOtZc6fPqqaVUtm2vLIIOcnBOpjunU0ppT+Xnc2pgc2XFPLvqqMQPe2dVkpqjZpUbcA47PFctxnNFUe8upuNa'
    'Sl3Zw57rlPhJm2S6c8enBkfZ3NkVX2kMVRK0210ql6MMMyc2bNfkR23gpKvVwNlue3tqV3IW8+nUGk5k3x3a0rA5Wkp9uSTv1bEE'
    '+siOKlePcs+3xpTspCb5/aHnvrQLzoJs9iq21R+2J8Mm5dPjuiQ7QjFP+TIYKr2h1VT6B1ksq45hG1S5PeFG8qSXTe0mQonJVo/N'
    'im62pWG2tznKExE0iTJndLfLjcYuWN8/ORVP7M+LSnHf3nTL3nHpvlDuaXkakv3a3h0Mj9TR69Ss2qxpLeTGfsEsHM6ifYrkKYrh'
    'qzVYGGVtS6498ga61jwxG5vfpoSuqhStin4iU4BM1vFEbSpL2RfBmO9UO+ZVunXpHHPqTzve3BqNJsrGGyz/f/bebUlxLEsUfM+v'
    'IL2y0yFxB8Qd94wM8xs4Dg44d4iKUykkAXKEJCRxjQqzfpt5mKexMTtnzGaex+Y7zp/Ul8xaa29JG9wjMqu6+22yu8KFtO977XXf'
    'a0lP625afqhmVa88nNad8kvvtZ82AYjiy3xj08lNnwra7aij20DHX+d2tVJ47j1PRuknqarL1elL88Vzerm9o7SKzWetfjCz017u'
    '0egO5+6LPV0dzMz0ULqXbm5L1WYjHMq8OBiN3GVtInu32urJaFfgTAAjXdkMpP0k9by9l+4Uq9HRi8+HSlcv7rTKy2FQNNO7TreW'
    'X2y83ey13+9XOs/j6kqrDxXtUSkNDlsDGKBlUuvKd5o32JTjm5zWbgzsYSc5LOoP61zeM+f1ftxpxIvqQZq07gYgFExKuYb1aGvF'
    '5LRYzt2nTHWKPOuLkWn13eKTvJHGm8zrWnPG2Y4Ec5oC/3dTqmfMQnK2qWqLglNK7qudgrlKaw/eMO9mCodmVt63tnMQrYz2sN4f'
    'ym09b+0t5XW0Ka+A7XRyZRAdV08vtzlzZWQaIyVTfD3Ue3WQlXNudiQ5lcZot2rIUqPitRsP7aZVzK8Me7VuLfMrc26O44Xq7vEp'
    'X271Hu7rw8FLcbkaDuuvN6VD2lgpjd79sJldz0ZuLVm8ue01uuv1S/qhZpQH+soxXtb5h0lt8Tp9yTWmcmd91+9unKUZr0yyC72c'
    'G9rJ+XK/MaRcS92OHMPTqqvBuKV5q+pj28kPVoX8a38yX5SW9xNY+G66ZHRdZz3t9Otqr6jXVvXCnWQ9Sa1hfdXKuq3d0JgtXyQt'
    '95rOTtdF3Urmu4fudpNxF/Gn2tOrGl8cxo/t+ERuD0x7ULTuH8sLz7Gf7Ml02Kktd8A+P+t1T1a0Yn9zrw9StUHRq+TdlZIa1Vv3'
    '3d3LbpDWx15NWlWd3FMzqeTUVk6dN5K9zWAyXPWb2e5rTXdLydJQeu6XOvOe7TUXbil33yiuvd3GyKwmnrraD1xntWqPn2y7LCml'
    'fbJnvuhP6/ZD+yHzuLt5GNkvdx2QtuXiQ3axa/Sy3d20XV1I6RnImsPbp1ylactmWzUahrOQC7KUmXTqmcPATi33I2Wf8pr3z5Ws'
    'uxsv53J/td6OM4N9qndv56qL1couD0sj3VWkvZuZGFKqv2oNu8o8p6TM2WE2v3lwB63qsNI/eCow0cDPqW5RSo0Pxv3LEA5OzV5V'
    'nE13PMYpWKu67ayW6+TLVnuEZeoPtWzW9JyFVVAHI9nO9MvT+0Gn2U7vpfKwvdxK+2a/1+0DyV2vJodm5nFTuX/ZTiZj5SajF8bK'
    '0HlUG73UfX0yzqVRx/iasZ9zB2Ok13YPstPvlkZmea8+ucZh39r1J8qTu2sPht37YsNbeJ1hrVE0BrlX+2HQGD/M5dflk9dZ6VPX'
    'hkHCiW3Y97flbWO3H3jSdp0ee6ZXWlmT8lBaHOyebhcyD/mBPrUfSv3czun1+6l2ud9oTavzZaFvTHSzoj0rg3bKmdzL1qQ1ONhK'
    'bZ7SU6WNnbGrufL4MbNavT6kh/KTvZZ1OT+Z5Z5aTuXuedstLFszbbHd7EdO46mXTh/2Q3tScJtrtZJu9qX2Xc49LAvPh56k7Xpp'
    'Nb1pbzMVx9tXdmuvgdkWdw3gb+vpwX63Xt89KWU9H5/A4Io3Rnbtbm1rVF3dbio3rvv8kt145e0GaLDstOX6tLrod4cZeQU84fhp'
    'XTgM232pkNu0C7mmu1uP1reFwqxZcr1+6XXWT6Xq47ymmYvcvqI1VKCgj8BvSW2tVt3YLwev3rydSSBMH4bNjVtK2QVzUlsNjFVe'
    'az9V7VGmJh36bVWbxZ8r3dtJ5napNqtuP6u+OpWmle/YI2A270eWpz5aZrnhDJWVXM+VmjNgPpaNySHjjCcw8qH12j4M4of23VOz'
    'PdQqqaVc7o7tZUHp761h4a62XD3VK6tWO1Nap02zbj3e5uf7sZMpH5q9wmqwzRjtfNxWM5PX7GNnkPZ6q3Kt9vry6tW9KZzOattW'
    'brK2U87tB8bk3inktXFjOl7Zy3y9tl4pq/ogI1caTaNqSWqhn3rq3mYBr6oNu6Skclq96FbkTa1ZMuPlVWu2aT3Z5bJhjEY9aTVe'
    '7e3hbtNeaTvAeuO9vjXm69fUoJLq7Vfm7bhSzG5AnpWe03dZS26Meq19/rlfcDf6fr3Kv6rSdCc97pqLh+fn+4ZeqTWfNr3dqmq6'
    'zUPa03aDFoD1utvu9Ru9/v2ivFgs3Op8PNG63YlkHEar+Hi8mpjybR441nm/PFolt3eS9rjotu8rKoBnvJFLLnvx4qJXrvdzTXnc'
    'h622nHrBdXKNstGVlnF7lx5Jj6+ZVm6hilWOq1c2hXq+nzeUYc7cpHLTuBu/K+rNtdRvJyvF5KE21ZrCc6d2WzJKtVJnXS/u8gqs'
    'QdncDhdtKb0C9J0x4+Nu4ZCyi059JOXrLSW/bm86rxVPXsWh8h2IhM9yzzSX/d10+eiocekVRIZNdVd6dSXP9Wpea7Iau/V+ql9Y'
    '14Fz6qyc3fPsZtivGXfG7Yvt3A3ghDaV1cKsTfbpm5vJ/f6P9U96plawn+Rpq1M4dKqlitQrN+qPzra/evHG6+LAKRfjtrZwoEXl'
    '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'
    'zni07g+5+GO88Zi8eawKn8bt/E0x7v+W7eXjEihjJV0a19aq1x5suqVupw1CwaYoJ9d2Vmp4tdee0+3Byo+dlWT1rLWSmVfTd8mh'
    'nk7X0p1MLS8par3bfsqAeLEbrtpNY/rQtw+dQ3+dfq7NS6Y7ecp3pI3qPlUOQ1M2YUyyegfN5w53mUF+tDsMdp29OdqlCpIat21L'
    'Ss3tdEkuDQr6qrCfPq+KzqQ7y5eNSc/arzf3i0LeUkxtpz3p6qORNdtbrzDpVFf2MF7qZerr5Ga6bU7N4brRW+TV+4LX0uLJ7f1G'
    '3TWe9st9v71pDM3K88DxDpajbdrZXGsbX5harbHoTUbZJaptqq8Dr9t+6K7a9+6dvqnnPa2bzr+W0rmyJA/UWmrupqRCqXBzU53X'
    'TzGE+1rptNevi5FUAMyQcxZSu5c3XubT50Lt6VHJqUqtna9v1PqLnYo3W8WW9bS6Xa1SI6mvt8trp2moL2lZL6b6m33mUF8vy+N0'
    'elVsLFeOLKX37qSkqXaytN68mIWVMSs8qZOp5qiPSn3cB3reqi5zh362LsH/ZV97yl7xCkN9/SQNu1ZaX6+eMm6hV0h3AfPbxc3D'
    'vJke1svaYPn0uG2N8uV8MzlIFfX8ruvlU/lS5rZXlc2eZ7qHfLaU6744mcoSOPBMZqXlSplSYX0rKxVn9LA7jJVBr9bppQ6jmqdP'
    'ndWgva+WNq9dp7uzJo1DCs5BeZxU5q3X5rNhPG/y6qA8AM47121mm2brJbkbTDPVpjZP6m5y/VJ6BClQ+KB4i1dl/Tqu1DY9fTZu'
    'bm9uF3/mrMQryYw8d1VYvo1ir2W7NmgM98389EFX5dVar4I4Y/U7h9tDZ9fQV562UIeNyUR+9Uarjrnor3PNu42y1NfDtNp5sJVV'
    'PNfdjhS35L5qOVcd9jYLo928X7y2Gw/DwwY5zmqhtSjZpdZSW3QHIGqnR80XKZ9cKYXDw+O87pXWLzf3q/slNzfpyDXVrZVSbhS2'
    '90tDn955w4okDeuKo+j2wXjq7Wu5hhlv7/Or3XQsWbY1a/TledfZpWsLxUqn5FLntS7bm/v6YaRuyrfTQr2T0dKdYqEj1RueDoyd'
    'narR//LWZvE8ezH23YnRao2cjGyu2yO5Y+nL13xq0H6srrRuaWDavWUqLg9LXmqQNTuDQlJuWcaroj55WQkwxE3p5ubhxZi9Xe3t'
    'bdpyHsfAIg/v2oOe9HyQNbTTF0oP7RbIC/pTVmqtq9Nc15s2yuNCazKordr95+LCKTWNUUrWMY5Ke/oir6TuMj9ZADrO5lsvRh8G'
    '0X4cNJWd+5I1V+OBanR6jXU/k18bc9W17dQElkDZGBm1U5VHN70HIAPF/biYXEkrQx5IPW1wc6Pd9yhqR7lfltpq+SV7c7tO3xb3'
    'bns0AXLUkXre1tvXM6V6MzlUk9Wc2p+Uhnq9Pmjme2reazTU+rR+8Bo9N53NyHJdCtb19cVednP78WTeaI3q9sR+XAGmXgE6sFZJ'
    'tyDXV+ZCGjs5qV7ZOfu0Ny/NU9o8I3VNbbQs2oAsn5Sb28nj4A+B+qFftF/v3VJ2C5xjvq9vll5vdWjJZrG8l1vD7k4GGK/afWDN'
    'SnBkmqPSCrjZxmMDVRtNu3OvbJV5Nr9aGU6x2lcadc/xmpb82q+mS9q21Oh3kzeVlWkCTDftVKuf79+Zh/I4O8glX3LmwKut+nax'
    '1B4MN0PgP28Wze7T9LnheJW0XM6rE3lf76bXzY08PpTj1WxyWJ3uzK62mHQlV6s11fwt+tVvx4/bp9tCtzna7B4f87n7+LNqm8/D'
    '7OtrSZknK61Ow86nW+VKczYcrnJKpV28e9FSh2W92N7F1y/J10exg9fUq6x5r7sXofX78WKzrObyjcF+99yeTuuDl/xT/rESH93u'
    'ywPTqa4K5dL4trnTrVytsuz35ZxmF6R2q6k/bfKH7kDSDtYubfa6xaab6am1dd71jBe5qFmHzdN8W2jJbqXfyK4s6dVYp5zhzus3'
    'yjkDhESALyCOpV4+lRraT3LTnVTabe/1dSSB/Aj0RV4CS6o8AIWZtpx1zlAkuz+eHNaFQaa/ab92Btmbm9fF6fl6GBWt5e4wbN09'
    'l/dALLV4er+KgwjcHy4zVb05PNRe+8Nd1X7a7aq7xWJi5SoNbbevoWarX25rtdrcWaWk3iy70dqF1czRjdqilOvMHrLZ7L7fsUBC'
    'ztxJ/fLNq9Q/rDpWvydL09xjVc8/ZY3Sk10v2s+qp1qGrWvmwBiW7cKw/NSUVjvt+fGh79XXKyAXowksWOqlUiytho/m7vkgrevF'
    'l0Jv3WrpY9NRYJN3h/Kw5GQrjtU45NfD2+XrTcb0Otli/Gmpebup/igbu1yx+1ya6MmH5miV9KY36u162t9nn1Oj46bb6df9YpeG'
    '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'
    '8gmlEfAX0KXbt/4POWiFeg=='
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
VERSION = '2026.10.19.1629'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
