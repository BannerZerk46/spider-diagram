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
    'Zp5H5jvun9SXjKqeYwu4R2RWV/fbRHelG2ZnP3p0P6pO3sqsxXRBFLOFhxpsjDK3y6498Hq61thnF3ZhmSi2VeXOqur7dAKAydrt'
    'xUV1Kq1LIMy3HlpmSN3amevsvjtueRNrMBgpC683FR/XvYx0X8spXmU0bTiV5/5ikDEAiBKrQnPTzU8fi+rNuKtZQMcXc6tWLT71'
    'nybjzKNY06Ta9Ln17Dn9/N6R26XWk9o4GLlpP/+g90Zz99ma2gcjOz2U78Trm3Kt1QyHMi8Nx2N3VZ9I3o1qP+qdKpwJYKSrm6G4'
    'n6SftnfirWw2u1rp6VDtaaWdWn0+DEtGZtft1QvLjbebLQaDQbX79FKz1cZIVh/k8vCw1YEBWqXUnnSresNNJbHJq53m0Bp1U6OS'
    'dr/OFzxj3hgknGaipBzESft2CELBpJxvmg+WWkpNS5X8XdpQpsizPuvZ9sAtPUob8WWTXaxV5yXXFWFOU+D/rsuNrFFMzTY1dVl0'
    'yql9rVs07Ix6740KbrZ4aOWkfXs7B9FK74wag5HU0Qrm3pQX403FBrbTyVdAdLQfn2/yhq1nm2M5W1ocGv0GyMp5NzcWnWpzvLOb'
    'ktisep3mfadllgq2btnr9qpgG3PjJVGs7R4eC5V2//6uMRo+l1b2aNRYXJcPGd2Wm/27USu3no3deqp0fdNv9tbr58x9Xa8MNdvR'
    'n9eF+0l9uZg+55tTqbu+HfQ2zspIVCe5pVbJj6zUfLXf6GK+rWzHju6pNXv40lY9u/bQcQpDu1hYDCbzZXl1N4GF72XKes911tPu'
    'oKH0S1rdbhRvRfNRbI8adjvntncjfbZ6FtX8IpObrkuamSr0Dr3tJusuE4/1x4WSWB5eHjqJidQZGtawZN49VJaeYz1ak+moW1/t'
    'gH1+0hqeJKulweZOG6brw5JXLbi2nB432ne93fNumNFevLpo15z8Yysl55V2Xpk3U/3NcDKyB61cb1HX3HKqPBKfBuXuvG95raVb'
    'zt81S2tvt9Gz9sRT7P3QdWy78/JoWRVRLu9TfeNZe1x37jv32Yfd9f3Yer7tgrQtle5zy12zn+vtpp3aUszMQNYc3Tzmqy1LMjqK'
    '3tSdpVSUxOyk28gehlZ6tR/L+7TXunuq5tzdy2ouDez19iU73Kf7d1a+trRtqzIqjzVXFvdudqKL6YHdHvXkeV5OG7PDbH597w7b'
    'tVF1cPAUYKKBn1Pckph+Oeh3zyM4OHXLrjqb3ssLTsG0G5Zjr9ap5636AMs0GKm5nOE5S7OoDMeSlR1UpnfDbquT2YuVUWe1Ffet'
    'Qb83AJK7tieHVvZhU7173k4mL/J1Viu+yCPnQWn203eNyUs+gzrGRdZ6yh/0sVbf3UvOoFceG5W98ujqh317N5jIj+6uMxz17kpN'
    'b+l1R/VmSR/mF9b9sPlyP5cWq0eva2tT14JBwoltWnc3lW1ztx964nadefEMr2ybk8pIXB6svmYVs/eFoTa17suD/M7pDwbpTmXQ'
    'bE9r81VxoE80o6o+ycNO2pncSeakPTxYcn2e1tLljZW1avnKy0PWthf3mZH0aK0lTSpMZvnHtlO9fdr2iqv2TF1uN/ux03zsZzKH'
    '/ciaFN3WWqlmWgOxc5t3D6vi06Evqrt+RslsOtts1fH21d3aa2JyyF0T+NtGZrjfrde3j3JFKyQmMLjStZ5bu1vLHNfsm0312nWf'
    'nnMbr7LdAA2WnI7UmNaWg94oK9nAE748rouHUWcgFvObTjHfcnfr8fqmWJy1yq43KC9mg3S68VJQVWOZ31fVpgIU9AH4LbGj1msb'
    '6/ngNVo3MxGE6cOotXHLaatoTOr2ULcLauexZo2zdfEw6CjqLPFU7d1MsjcrpVVzBzll4VRbZqFrjYHZvBubnvJgGpWmM5JtqZEv'
    't2bAfKyak0PWeZnAyEfmonMYJg6d28dWZ6RW0yup0nuxVkV5sDdHxdv6yn5sVO12J1teZwyjYT7cFOb7FydbObT6RXu4zeqdQsJS'
    'spNF7qE7zHh9u1KvL54XXsObwumsdSz5Omc5lfx+qE/unGJBfWlOX2xrVWjU17ZsN4ZZqdps6TVTVIqD9GPvJgd4VWlaZTmdVxsl'
    'typt6q2ykajY7dmm/WhVKro+HvdF+8XeW6PdpmOrO8B6L3ttq8/Xi/Swmu7vbePmpVrKbUCeFZ8ytzlTao777X3haVB0N9p+bRcW'
    'ijjdiQ+71vL+6emuqVXrrcdNf2fXDLd1yHjqbtgGsF73Ov1Bsz+4W1aWy6Vbm79M1F5vIuqHsZ14ebEnhnRTAI51PqiM7dT2VlQf'
    'lr3OXVUB8Ew086lVP1Fa9iuNQb4lvQxgq02nUXSdfLOi98RVwtplxuLDItvOL5VolePq1U2xURgUdHmUNzbp/DThJm5LWmstDjqp'
    'ail1qE/VVuS5W78p6+V6ubtulHYFGdagYmxHy46YsQF9Z43ES694SFslpzEWC422XFh3Nt1F1ZPsBFS+BZHwSeobxmqwm64eHCUh'
    'LkBk2NR25YUreq5X99oT+8VtDNKD4roBnFPXdnZPs+vRoK7f6jfPlnM7hBPaku2lUZ/sM9fXk7v9H+uftGy9aD1K03a3eOjWylWx'
    'X2k2HpztwH72XtaloVMpJSx16UCL8v1+4NleolWvP466/fpjd2A3e9NDdz0YtksHfQBnNa/Wsv3H8Up9AT59e31fEkEMPnTT5c5D'
    '/7nb1lYkoLojkFABRda18q1pjaf6ajSEX8bN/aDXKkg3otN1pvd2oTmt5/sZo64pdXNlaNmC3F3P2o2Fbq1k3ZH3bnOwelm/JCpP'
    'W/cx2832ctLcKgxEkPQcEEXN1mQ1KC7l3SCzVMziTJP7g0r6aTE/VIYP7ihfeFlkCodRVR+Vn4aP9ercGBRqe1t/eXBbA7vcKmeK'
    'PW2h9LOV52e1NSm4L095kNCrlYY1Ky6d/CwjJZTFDnagYOiGNbYyvUbPG3Zvqmb5UBnYIEYNFEQxfTG3usv33YW4HeiDe0fP3G9L'
    '4r4pZiXn4cbeuM+zcXVw5+zH++50j374212qqHdSZbWvS7vt0240b7d6jYw40JsV4Ax2jf5Aad816kvpsPPsqm3XQC4DfstqdVRH'
    '6o1ka2De9p82tV6jNV6a2dxz/ml9V1eL3efBk+fsRg+Pw91z11tN7u22oRYakmR7sl1ba4W6DUKAtCrmdutqTdo89KtN935oNLqO'
    'e7A7j6uxsZ7o3e5qUBOl/HKRAaippEUg7saNUsnV++7NYpUCvDAc7lOu4m0SA7G0G0nFu7Hcy5n2JP9UsK363p1WOn13YhSKk3G2'
    '/ZJdaaZdzytOR22rhYddyVnrivzUHFdA1FyakpZumup2vZceC43r5VqrL6ow5eJLepzqLSxrM+o79l19Ps/DGiLo3zSMx3vLeimV'
    'ir3GgzdpNnvik7vSpHLBbawmCUct35Yfh6lld1xfmXAc5YmY7u4267qi9eutiWlvgZMpJzb9fKGmye1yU23ZleXtzUhfvXjaGiSC'
    'tGH+h/W+D4th2msO07L4MHzugBDU2o3zY6tq5p2MjUvR2HX67TGI/qWSPJuI85a7Wmcq47pWzDwW1tODPKmAIGo5iT0I+BtJkx8e'
    '8+nCYFbuD2wblxKk636q/yyOgFxXb566vUZbdeuZtW0o6+Fk1X+pbXQ129mXVHe5XVfXdicnt3Kp1nMl6w7zz/nK+MWbFA1Vbj1Z'
    'OeDNhiBNOdJyVBYdVcnag/xG17aHqfzsWaV6rqs8b/etTF1dLewXy3psgXB0QN21PNR1aTDZNbfDe69YvF1vGomF1AQMlV0DP9+6'
    'zanD7ON6u6s8W8PxwazA6Ae4MEqvvnO700NLAiY/uxz19qtc+VDU73K1VLc5SEjPBXFYaQHTYlTLipF+VB7X1k1XksqLYnc+bhSU'
    'aOFWvryfl+6nFrr1N6fd8So7fnl2K+WjDw9yIv+cuG2nF4PpamE9ddwnc3ibMKKvV/bLTDbubp+8qjea1zONXm9nZcV6wtblTKd9'
    'D9zcAHDmPK8rHc3NTZrKYA08XfdQrGT05qw3eik1xl3XKys32ui2Z2fqzcyu3dvYVs6qKpLpjCw4x431Y2brLcvLiXabdddNc5ve'
    'A7dyWDly3ZHGAJX2vqg3B42+NBjZQ3nZTW/sQTpjtu+G+bLVKd/jTVs4Iev8/bPRrh1qt+Wx5YwbO62g243BeNiSUquX/rClur3e'
    '4F4yKk4lK62Bdeqo5ULaa8+NhnG9ruaHh+HoFqSIl0yrc3hZjzslYFNndlux8+0ny+sUDbnp3He3/VapJNV1q1BfzEy7W1lWmr2d'
    'p2naeLUYPknwHxOkgJpWU7c3VYDsf+Vf62Et7bSNmgfqubJtG07o9cOjuZKqL/pqO+qtrTSws4rRFBfWsJV6KejqZtMvjSq9rptx'
    'CzVAeU5zfjtwvc7mpTEqSN5iZHWM4WaRq2ov0svL6PAwmCT0otdo9oa7orfuWro47Joj+8XZleziAjBGd7wF3risHu7W2U2i1NXW'
    '5b7emj4NtYylJPLT7Gy8vr2rDifVuucNpv29mlA36rZ/aNuddmXXd0e6oYsvcqUvtWaSPpANL71yHqzsviw1e1mnN5abw6o4lvGy'
    'hFuu7ldWLp1r5tYjR95UBqWX5b4Nskp3XTkMHgG/TdapXWmhjKVRNTttiSOvp6b2pe31rdEIL8OID0+N64G5m3brhRe7L27H2W7d'
    'Hq9S2+vFJrusVVbz3Yuua3A0R+mSsQFgnNvVad9WG9pcmu0StUZj0ihPXhpTRRronety6xaYBNEbmX1NLL70VPHBXg4GZQsEt/x+'
    'VV5J2cQU/qMfVg+SO3puzgbDtHKQssPuSi6WHWegletqOvvs9FYVPa8+VQfTQt9bwtZMMq2MWdDag8daJbVK59TRbGLp81X2YSCL'
    'ktzfNzUj29QcpVndjMwOCKmwfWtd9tpju9xrVhxbNnt5rTg8NDZZ4E0216vaw91DE4bYlBcrewX8R8G0Hx5bje1/BAoLLV2T1vtC'
    'R6sbz86y1ZrOU4tOKlt7etrpD+bdIZ94SDQfUtcPtcinl07hupTwf0vW6mEFlLGaKb/U14rXGW565V63A0LBpiSl1lZObHr1Rd/p'
    '9WHlXxxbNPvmWs7Oa5nb1EjLZOqZbrZeEGWl0es8ZkG82I3sTkuf3g+sQ/cwWGee6vOy4U4eC11xo7iP1cPIkAwYk6TcQvP5w212'
    'WBjvDsNdd2+Md+miqCQsyxTTcytTlsrDomYX99Mnu+RMerNCRZ/0zf16c7csFkzZUHfqo6Y86Dmjs/WKk27NtkaJcj/bWKc2021r'
    'aozWzf6yoNwVvbaaSG3vNsqu+bhf7QedTXNkVJ+GjncwHXXTyeXb28TSUOvNZX8yzq1QbVNbDL1e575nd+7cW23TKHhqL1NYlDP5'
    'iigNlXp67qbFYrl4fV2bN04xhLuodjvrxXIsFgEz5J2l2OkX9Of59KlYf3yQ84pc7xQaG6XxbKUTrXapbT7aN7adHosDrVNZOy1d'
    'ec5IWik92Oyzh8Z6VXnJZOxSc2U7kpjZu5Oyqlip8nrzbBRtfVZ8VCZT1VEe5MbLAOh5u7bKHwa5hgj/l1v05b3sFUfa+lEc9cyM'
    'trYfs26xX8z0APNbpc39vJUZNSrqcPX4sG2PC5VCKzVMl7TCrucV0oVy9qZfk4y+Z7iHQq6c7z072eoKOPBs1lbz5Wy5uL6R5Koz'
    'vt8dXuRhv97tpw/juqdNHXvY2dfKm0XP6e3MSfOQhnNQeUnJ8/ai9aTrT5uCMqwMgfPO91q5ltF+Tu2G02ytpc5TmptaP5cfQAqM'
    'fJC95UJeL16q9U1fm720ttc3yz9zVhLVVFaauwos30a21pJVHzZH+1Zheq8pkr3WaiDOmIPu4ebQ3TU121OXyqg5mUgLb2x3jeVg'
    'nW/dbuSVth5llO69JduJfG87lt2yu1DzrjLqb5Z6p3W3XHSa96PDBjnOWrG9LFvl9kpd9oYgamfGrWexkLLl4uH+Yd7wyuvn6zv7'
    'bsXNTRpyTQ3TlivN4vZupWvTW29UFcVRQ3ZkzTroj/19Pd80Ep19wd5NX0TTMmfNgTTvObtMfSmbmbRU7i4akrW5axzGyqZyMy02'
    'ulk10y0Vu2Kj6WnA2FnpOv2vYG6WT7Nnfd+b6O322MlKxrozlrqmtloU0sPOQ81We+WhYfVX6YQ0KnvpYc7oDospqW3qC1l59HIi'
    'YIjr8vX1/bM+e73a25uM6Ty8AIs8uu0M++LTQVLRTl8s33faIC9ojzmxva5N8z1v2qy8FNuTYd3uDJ5KS6fc0sdpScM4Kp3ps2SL'
    'vVVhsgR0nCu0n/UBDKLzMGzJO/c5Z9gvQ0Xv9pvrQbaw1ueKa1npCSyBvNGzSrcmja/790AGSvuXUsoWbV0ain11eH2t3vUpakdl'
    'UBE7SuU5d32zztyU9m5nPAFy1BX73tbbN7LlRis1UlK1vDKYlEdaozFsFfpKwWs2lca0cfCafTeTy0pSQwzWdfFsrXr5/ctk3myP'
    'G9bEerABU9uADkw75Ralhm0sxRcnLzaqO2ef8ebleVqdZ8WeoY5XJQuQ5aN8fTN5GP4hUN8PStbizi3ntsA5FgbaZuX17UNbMkqV'
    'vdQe9XYSwHjNGgBrVoYj0xqXbeBmmw9NVG20rO6dvJXnuYJt606pNpCbDc/xWqa0GNQyZXVbbg56qeuqbRgA0y0r3R4UBrfGofKS'
    'G+ZTz3lj6NXtgVUqd4ajzQj4z+tlq/c4fWo6XjUjVQrKRNo3epl1ayO9HCqJWi41qk13Rk9dTnqiq9ZbSuEG/eq3Lw/bx5tirzXe'
    '7B4eCvm7xJNiGU+j3GJRlueparvbtAqZdqXamo1Gdl6udkq3z2r6sGqUOrvE+jm1eIh2sEgvJNVb7J4jrd+9LDerWr7QHO53T53p'
    'tDF8LjwWHqqJ8c2+MjScml2slF9uWjvNzNerq8FAyqtWUey0W9rjpnDoDUX1YO4yRr9XarnZvlJfF1xPf5ZKqnnYPM63xbbkVgfN'
    'nG2KC32ddkY7b9Cs5HUQEgG+gDiW+4V0emQ9Si13Uu10vMViLIL8CPRFWgFLKt8DhZm2nXVel0Vr8DI5rIvD7GDTWXSHuevrxfL0'
    'fN2PS+Zqdxi1b58qeyCWaiKztxMgAg9Gq2xNa40O9cVgtKtZj7tdbbdcTsx8tanu9nXUbA0qHbVenzt2WuzPchu1U7RnjqbXl+V8'
    'd3afy+X2g64JEnL2VhxUrhfi4GB3zUFfEqf5h5pWeMzp5UerUbKeFE8xdUtTjaE+qljFUeWxJdo79enhfuA11jaQi/EEFiz9XC2V'
    '7dGDsXs6iOtG6bnYX7fb2ovhyLDJu0NlVHZyVcdsHgrr0c1qcZ01vG6ulHhcqd5uqj1I+i5f6j2VJ1rqvjW2U970WrlZTwf73FN6'
    'fNx0J7PYL3cZ2GlFGq9gW7MtO+fdl++8XvtpMM1sZq1Zto1AJNWGrXy7udA99e4he2tO3P2oPjKGtc3DKmOZ2XS5tFkO7m5ylf2w'
    'WAUISYE4cdNvjtdpvXJnO6OGtc5kG5ZjAmPf66ibntyri/eSWPXQzJDu3OdqvWIro98U5YPZrKb3wN8fxMFYzU/7+eubl4fu9f//'
    '7wf6iVTq5a9nfmDqII14cOWHsolj+hC8iWOuvdPrNqk36gzVCUsQSrHKMc+Ln6ZMYrkQ/3o29zzLvUqlVCO51ZaapSqalDSdWQp/'
    'pZ40Q/nbSrJgYI4qKZhAbe0JK3grwFv//ozkpy7jqW1YXtH46Qjnzsn9JRY1W9bXmB9li5m08P4SS42CrQxNh4JtP0nOUjG3b9/8'
    'OoknLZ4ElM5iuPUGBen+la1FNPhxIZ1MpzPFdLGcTqcLR9Glc7lyMp8pZ0qlXFFMi6Xcf2KU9cz37oHRQF9f9+qy3F5SNL8epW6N'
    '3tJrhPe1eLRxXEOe55puvWEmD52lsWf5SsKkdRSG90JQJHfOApwrpuepry+NTT5ImCcjEnpd8gRVozRVqqEch2735gAORph4BTMQ'
    '/ePf/69ry9L3OACWCZHFgv/Hv//fAsuTd/RaoAxaYbaoAJZorZZvrBW9FhamZoRDNvaUioqn4IlMCjNeCXTbTVC0KYgTmNAvzHCU'
    'FE5Wnid88xtWKOEZW9qlACut6OpREkXKH/Y6rwC7+cize303e1PkOtWEXcALU0dFqyaF25O0vpj6da+rfqq742ZPUqmw8jy/2Js5'
    '304ioGdOIqDfMZih5NB/7mjly2KykM5mixiToVR6FVbcP8N/LnA7dRwGAcaJszDAOKwzugkbzuUkPnrmJD76HUH96VwwWV0yk86n'
    's/lyKZPPRkM05/OFZDmXz+dEjKGfy4t/PJcfxJj+3lxoWKdzOU3GdxI1nRLaRLGdCONPlrL5XE7MFsVc4SjUNGZ1ymUzxQwG0k4X'
    '/8Q8fhSX+XgehDIo8rvxahInUdQzJ1HUe4hCTvejWM4lC2WAm1K6kC5l/HDxbB6FUjJdypUBaWeymbyY+cN5/Oim7vE8KBEERYLH'
    'UZ3O5CTWeuYk1jrDS0BFAamx0xvimcjc8rlssiQWSpgBLC0WykfnJo3zLhSL2Wwhm87+8dQy07Kay51MLRcO+STYeuYk2HqOcuxK'
    'G0BOUyT5vwruXDrKtVvI55LlTLok5sVCBgYbSXeQEcVkKZ2HLchnsvBJ/E+kn9+5R53FtDxA3HyikA2IAk/G4foJewJkyFOJR1LZ'
    'aTqmucX8n5Sid06p7cLUIhdBKnbCyDSEgInxMXEkdfq5KxjSSkU6Rmm6TUsgSkBYl75or1g5GPgYE6joGhBBZ/96OtG8NpjP/FVK'
    'G7r5zEbtD4R4qzltJl2xBqKw0dQt0TjJAaDELSZGUXEplwmm5XYvgrx1/qVxmHVwY5xN/43hdwFO3tiIt/LI+PeOY+1mNR4hzSzz'
    'CXIiwP0hX7EXMDj9j5K5EL8YSyqmvIu2tIXTOid+iSbmc5VV05zBBt+ZMux3JCUibmuQn2aiUtbPOeOa3IvIpuMTY66piIR38H80'
    'Op+LjWRxDLPQWjoOIJIcCz+vPcouc8xU3ZrWPpp50QlCMFDaxcis3k4U8wfJFzMn6QwyJ+kMeD4rPEfufw4i8LHOn84gkzlJSZA5'
    'SUnwANtxdQL8CcElKP8vG/KPE3FkTuJTZE7iU9wHMg+cggsGor8KK/M/C9m+HvDb1Dsc8IlYlTkRq1o68syELIW1BUuskIyxclX9'
    'vxAw3ibVYc7YE041e8Kp1v7x7//nCthkzNjN8VqUPcpk09/j8k6FwfwfEjPs4xUxS8sAJuXvRWGphMNyQRbC6B8TlSJ7kLSwD5EU'
    'wwiY4BfPPYh0mHKY0q9uKYE6onprTRRnlRSueT7rV3FdsMPXQV1O80SrK8vjSYFZEyi3UNJgnn82KVAyY+ziKKQL5S3mic4szERt'
    'TllKZJ4W7FjW+Ik28YyJ6Gwbz7In7LoPIlPHXEVZLDPkPE95TQ4ZJ7yyzzvxhgJAMSNs1BvcN2/sNDdx9qixIPYMNlbgU/vp2+8p'
    'V3Y0y/vw0+/+g2warif8IrwXXOH9hyADX9JeA+pikqfpxNz4O17S3cyg7C+x87/IkrGR3PP4BdJrXeFv6Rlfuh7G12Ev6RlfYr5w'
    '2Fv2lv04D5qutJo9+HR+KYFwrl66e9dTVxfCDW7HkyR36XcFtvcC2IWZqQr92oXQMUG2NS+EBzz0niZLQlNdA39x7WiSDqOQDPfS'
    'VR1tev7up1RKuPFTsVPyNiTFPOEbS9N2hXkbEfxQYQEQjkFckA1YwY8ZZgsE4VvFdic6dgLnTJtB59basVB8tmCkST6b9nXjvte7'
    'hwl9OufU5PxCOOdYmh4Z/qNHhlXokTHM9MjOKj2K5aIoZ+gxP80qMitQlrOFSZ4e5Uwmn5fPP/ur2Wm1en+r1BoNXFLOwp77H7u9'
    'VgeHds5Yz0tOoq42YlCk9lT9W7f2ct+FYl+FLkg86QvhCVEU/G2gCA5/Rw0E3LTwLdzDztN173XLQbMwovu/De473VqrCcVy7wBM'
    'YV8m65UFB1NzhRiiFYmCQWF8HDzAT7Vq57oHFbpxUtEhWWU5VSVMhecC88D4N57g+6efMNAPoAaK+vKeMCPvJ5KxmhQVMQ0GhVpF'
    'wAs+zoj/xOIEGctbzLXn4hZ+5vV9RYt7jjkDsRmZlcGDx75KgFI9TEi+pZhUyB1hwkmcFlcrTmFB4FvYT0MCJIv9fP3G+6HBaYpw'
    '+YGjU9Ti6FhM2AJ/iK0bQuyrsLsQ9nAAL4S58A3OF3bGW2cdwhGDZ9YR1qZEvsGKRCaEGi9X5V1oyHRiG1tHA7xjUH1ADRe4elAd'
    'dh75doKMHSpBhD39dwngAQhKmKmwGDgbeKUpt+ba8PjPOcucDSOA6l3Vi8Hpx8bXhmJ2PcyYiIt9QelTo78xAFAPg3H5o7+glO/B'
    'Dz7R4LcO/OgdMLo0RA8GhyCKHSG78EBKsqAsvmqiFBS0rDlAbd4LU0l3VcRkwAMNJcdQFf/lu584OCvqVFrrHu5dLI4IFPYEiNVc'
    'cjWX57SCGorqPxMzfSWcsyyOcHC3jmTB7xVMYL2C39LaM3tAVFkF2FT/4Aw7122ajUHkBaaULF4IrB7qbjBFJHQjJvOAv6bTK6Fm'
    'gDSlwUSCwznRJToPwUgxsFlNodqu6uECwtj8KcXiFwzUr2jnDFPBkX8V0vgfTaENR64GRv8UpNW8OIIHxptw1kRAtgSnCoWhHHEk'
    'VxE09Q3/D6ab+k24DP4RfHIBmQnDAOIryWPcB+P6KKl9hBcMayMNHKiOq4E4CrgF9nEvxEj7QagFBh2iFgEwCAhnyEFseBUSZnAA'
    'uE6wRIwDwgBuNBIW+gz7mFAUMo8Sz2P5rbSHsSHqUgAbsLECy7cmJOW3jskEoWVVYZ3igcBRxa9I0QMHSQBpAYpwbYC/W+FW8T2B'
    'ZeMsEZB/Wpyz1Bnv5Iy1lREAVQKAUxpB2BZ97fJ1vHqFqGmwvDrjxuFfVgiYQl3bqFxdfcbfnQkx4MeQm4ThnMXf0TIZFAEN8WpE'
    'ro0xiIgABGsf/jG4iFP3yLheTnVTojPt9/y6snCOJYGD8Hk22A9vC2Ra4Or2oHXexjvBgqmSEYJppyndKW+eadrYCEh/AS3iXEBs'
    'x6yskg78FCokYLpHypWgE8Q3qE65YMq1reYi3ubaF4CAqQcLgog8XJF4UuigCgbnydcPoAggbaVKCI0I1kH7smlpMFBiYUHYtyxA'
    'k9M1dLLJctCPUDPUNZCRBVly0hOYLqH0OVMD7Tl7vzTMbZJ1kRN8ZQJMWgY0sweoPSOSAHN25yQeYixEzEmMABxQD5hGNwCwcPbv'
    'qAAHpmAaM5MENjxPfEbEkYfD4SY+nVFFySV7wgSgzsLjpERnGUR0JDEDu6gZrsYEQVohKRC/gahJOpxM9/tHiSM8wJjQYwVWNIVk'
    'HR8AG8N+IG1PCr+lfpKBvrjAaW5VB7/eA0Z2gLoDqYTTzH59/caxbgTFvCeWXQQcyxFwMplULoKjyJini8jpQ6IONTJBDVrE75bP'
    'XgQoXUmezhHfhfMNMTs1CZwAKvQQtyGUIHaDo4YqMS5HpeNcD8VyUU81x41YqRgA8ZN0JbQmC+Cxkrh499AKbHGMv1L5Txge4a6/'
    '/x2GEE+uJCsW+7SE4X9G2sRBBV90PVTixZbw+j1wlelz4aNA62b8iLwATrzCtmj12BpmT1c9WLUclQAqOV0blH+ZDhOnGzElDv05'
    'KlIHgUV1TGpuzfDUmerElI9J3kwcxqX4P6Bz+MJm+BEwORDDdyB/Be2vNIBIT41hCME4wQSyJhvkLqI949d38FGbCrGN8OGId44L'
    'GPtyS2TjGA5j5wb+Po9U/V0Qo+X9YqYXHg9WnCUWpxrHnX1FSibBAENo/rT5zIdII8dHf/7vyCaBff9Mr30UC7vt7S0Vz2309c+4'
    'syYByPmfGyffD2zl3U/+QQvO6ns+WNQNw0nRtYMaYXao6zcOB74+wQdXR+MMDg29pOcLpqLmr+g5wrIxHILD4YD33YMbXewLhE84'
    'IKw1hHa/D78DAc9t/Hsn+zUGCM4lP3XhRJIc38UDhrZRa97/rdsbN0jw+3RORnkUMJktk55IF3EOXPl1p9MasnIG8DD4ETAg/gGJ'
    '3/HwAaTzORYd1u56D6woam7wE9scfCJbFoquwQmRdaB/6E0Q0xH4uOyGBPrcpYz1V5x/Mo1LzrAKGwmEcubRsVQt7yckmDglmQlW'
    'HCJ14ddfo7NMcsOJG9OTxBPE44LMnqAef3dUmc06Wo84cqpHT1SPno7qsSWI1iNjHtVj+d2xHj1FYFxGAIfZd9TJWtOVCEGLkcwp'
    'Ec5gggNZloD2oDQluIZkAaH24rAaKtFIWrGtquuXCIhASNmKJYUKMQ9A9bEjsiSwpo09CZ+MgeU6E0C7wEhQmnp6HZiiVGLIkTj7'
    '9JfLwOfI8DjLtUUsNNfcYU9AkUHIoYi7knupwUBCnxzcQTSSEb9BEjB25kog0QBjoRzpAfbnjurzJA4XslUlGUJTiAYUhm65LguP'
    '5sfg6DBidIHhXdmHCInyeW0fklgDwOOiOLVBGU/XJ0xcTZN0FZCKCgphaiyxiSMMbAjZIcEKf50jTUts4FT7rYQ9zNUdNClji6n/'
    '9pdP6cuydDn9/LXw7ZeUlkRFQ0wmhIiCf4xV+bRU90hIkT06obows3icW5JZYQ1FWjbWGNSjtjjmfkXsNFg8WAyo8jvI0/D0sxHB'
    '6MYJGof2YVXX6rtIb2h5fC+8btlIMlIejxaWObtEA1J8WdPvLUmAQTyBSywCLiJ/C1wAE0Rhf6DtXZzkUfZjH7/gbfrcAw7qI9sS'
    'KMRH4hfiUipsA9SlH3Hqhx4FVhk20kiSOEIrQCIJFAol2ytfGfgJ1u7f/B9JXTVm3vwz6+pbuPLQJqIEavG93/T7aNP8wed2wqpG'
    'ktSYMJAAxl4BIi9DaIeVfi/4L6MtBeY56hu1EVgj8pbeRYbt7wxG+mbjnZgm4nGEBv6Wf472w9OSRzvxX5308MZU0BxLByt4lukv'
    'HhpdWlmxJ8mbJ0E8N5Sg+IVwCYxyIQLrn84tTdcZudoRFdN1DSZJtAkg6vxziLWhERRyGJUgcQcnRU/RBgO6CYeACCGlbD9uCLO5'
    'Uzv4QM3gw9HarGY4udR/C4NN/zUVs4zZ3zHk9N9n2vTvW3Vixf3g05+kywPgiETq/edEgCGomSSefb5Q+HML/GQ68nuOv+PBgZOp'
    'a1Q3QT08FryJC2F7FTRxIcyvwvocgtnQA+3xJ/qM0f8/x1mrXbY9wXtW7dtrOGIm7qMjTkeN3mNjvID/Koo8SMR/H2EjDGR11Ch+'
    '40eXo0hAfkCRsQg/l9gBbwX/sIpEBOAUf8a23zG7CrImFDvfNzmt1jgAFFCZDkhCLHGpA7XS/SKosEERd2YiXSbwRG2UhKyN9Y70'
    'QVwmVl2QilknMcA4TEvLFSFAP1eai/JaKJwdWRYFkDLmRCNJVUWGOtP1kscEw4hQCsYRxGieJ6TCVY8Ut7ixyme+oNQayjAWbQcb'
    '3zv45VO7d+wLLZ/12Uf3IX7HDfG/IlHBzpJzyY1ZOIqgyUB17WNFjgrfCQp5FApsm98JE0eVlu84VAmsOUlRoLkQ3AIZ5a25J11Y'
    'zphBQkTQeYR0R9Ey01yFfCrTMkgEBK5HuxlIyqe0l/DTStrFLkVi/KPgyEeCwjFDfdBHQhBfg+LXCIH8T1LG+sAdHKdlyPy8Yjb0'
    't5gNYKBYNSbj/8t8x8864zlo3jopFz4fvfFM+s0+0c7gu7c5EWbneO+zE3qSvzjmJ/jrpKNauiSrsdRf3URqBshcOI8nodQqBnAC'
    'lEqNwfqKGcCfyHqwfmjuR/uDw7riw4PdMq9ofLTrUXGHyX/Iceghx/HV3yL+LhQCsTAbPJZiT/zj6S4CmNWOYO4P4e0VSNKsjkEy'
    'ZFaZeBosKgAAf3O8qlyO/XOrmklHVpWLRAyQcOInMnKwKuyEcEE4mC5ygMjWc7FYhOmxJUng808MUfgitY+aQmuOm/SfCa0x6xAv'
    'xWw8bhL/vv7KrT4uIaeQpEnoXkb8XPgjYhvilZmFCCRskiiRlQiMRedo88G/5nQaZS3cJFZCuGFPQsTCxFsN7Uxu0n8OeDDOkl6E'
    'iIarDEidFmpc0IKrKdxvIBlgJF//IRFXw6xNxzg2KB7oSpaa4gatQUWAAWCGPBQOXuFgQAh+Nc3tmCaRhTcxtW+1JY9HoL9XQB8D'
    'VIzC4hG5DNokFPq9Nt/k98PxkAfNn6j7/lVdHFhoSDxaAzYkJEqOF4tJF8KEmfAkzsF//ChIScSTl0JsEr6b4Lt4RK0CC9Gaxgwk'
    'VVzVFwzRp9RxHLrQjMhk/rEjtR5XFAeXQASJtYw+G6TKB7RGpnkys2vcmecNlTG7bOP78cCZClx5+HLAMQgWA83OUZkmBi8IvFUU'
    '2mjhYvFPaTgCSmS2imp5czZbMmCjcP7uBxP/+nrqSiIBsw70jUdaXHc98WD/iD595SgQmbr3Ah2CkCnSWMcayM14aYrxl/A7kYhH'
    'aamMRBTPQQxKfdI+A8nE4tbancdk3MlgJ+A1joSfMmN2p02nuFYBYIQTJuQnTdyYBLABH/9NiGWE39jrdi1sUgH+n7+EdY0UgWoK'
    '6rPfhXZkkqy44iPokmFZzYhNLkKMC183CIAANU+S7AporPrH//Y/uE8Dc0Fnfj7sG3p2MusaUBt+mcVBuw3e/NoDrMmoFmJ3feLJ'
    'yHlFYTEFf/6utefAb8EfSUlx8UfaaDPJM50kkBsPNV/IJYRvoV/nesa0D76aAlqqA7lDWoZz80JahSP8K7tkRjQLZsN81IB2nRTq'
    'zrWp91dG2v7xv/w/UPJ1Gb+N0AtqGemXzexjOKCYh8TQowW9ZkKOJqPBwvc+cS0HxMyopze3FlogOr5DLzhPWnIbDlPo+QXctUNy'
    'CBnTgEIGq4vtv2cO5DCkL7+jBxjZv96fafKZIDmadMncOt6fIfE4+/A7biXd7Tv7i3b5y1es++0s9eH3FNT98OXdTyc2fqYWJ1vv'
    'r2j4hKHgc6QEmtwYjpQ9VIgFbmoyAIan3usq/oqd+z5pyZnq3QLbB/OInWeUcHVJm1shFzRGtwgPp4mFmLrkzidMt+jshBzzjtzy'
    'BGuPHnXEXLDyYlBeLLLyBb+8WOLlRcaMsFK81XxQKsdKlfBQwV7ezlG1K6OjjMtchs5chj7PaMgk4pG/JaFWcmNkFnXuUMO1rqF2'
    'xvceT3JfKPlOVS3uhMO+BS+ianccQR1REGPXj7x33r3pvfNalCTK5bP7TI/xCtX6DX/yvyGbHHvjLRzVdETq+ZOCZhMEvUDIJNUR'
    'vghWB/E1mwsJhQZDrhGZkYv1SOkUWCaVBHqU30kqBx5Q4NuD6nC8BEcr6lM+Th4Q1JgyG04l2avXKNFvDXbxEaXw6L68e70v/8za'
    'vg/W9i15ZwItsuaJ/l8QbQjo4yV/nERWOhzMJ2QjPkflhlffYJdAfFXivrzxh8P+ObLVvIE/nAluO87DYKPn4+TkvAl8D9/wtwj7'
    'hIBickrYOc8vvz3N4w/Hcww5IeZR6tvJTXItgR1Et+ntKbsZYTbjDJYM7l+NnFPEYhHZqx/waowXMr4/8R+ycmx/NpqrTUhse4Pv'
    'JC72Z35UUB1jnHKUU23XVXVEF7SvEUYt7g87Uh3Ztjh3ImRMXHCEaUFv8f44+c1I5IRAdE3MCOa5jF/gMJGqDI9ZuK6x1wuLDoxs'
    'P95cXWrsGnug9Q0EWCQLPosMrE3APnmSkUHbARwUJ4nGleSOHnd4Xnw+KSVkIjIqcOmnvBYWjv5+xYsxoBoya5c/ARcdhuRwXVbo'
    'jI/vcNuYqBpZFe61geePFsgnAxGXJOzDUYEVQkcu7uCmaA7HWtgyByPL1Igcod8byLMGA1gUVRUFMVtkX1wPNdgoneBNJAcb0/fx'
    'yIq7WzhIb6y4dQKgXCXHxDpS/vlm0OiWhSqHGUP2fv3vbJoVbpqFm3YZLWJRkRkWsajIDIpEdjJSlB5d4HGlOGdyZRM463g8FIkn'
    '++6WIfCQG49MXsLOI78nAWcy2be4MeaflO+IgegyYMC7ncwfkoogGOjSHukOj9hACoikMESHQRT7L/ECh0D7fs64QvJ2VXgDMeKv'
    '0HkL+qBXJM5JdInUIS95hSXWlWYzZFLenbq+RSDXRZEOt0nfMwdmn8WkhsmixMR/koFgZkzcRV2Br5YJVRUfgwW78tc8WEpU8ASL'
    'aaHqTd2h4BCRU0KFK3VmYW8c5y1pCLCyhEd5TdJ48S/B8i8JGTKSiXuAK8dOIZtndPJssZBLJas2+lqxFcY9QqLB7Y5kwSZrgo/U'
    'I7gWkNxBpZnRiAHnhqOntfJXIgmt3kvyPBZbXggaFwmXgblPe4cuH1FZljV9DbgfasoqO6IRKm5FqDgeUCqFJJENIMlGsFKP18in'
    'Q/HjoTOo/fYTc2twTbyuFSA8gBl1OkVstFG5pwf6bPrkFZbG0dASv9WMqJ8lMTCwFSHf7PsxRxYQmzvGPwR0pLOJkQsX+mr5bBE6'
    '2MhM2AgBMFABAulVfBta7DU3A0wrfHzH+Mgb4gW8gFs4x4gMu4uAiSQmEU2Q3BWStIhE+8hqSvd0Z2tdcmj+xw1RpArWDVuDGHLr'
    'aV8EZFoXbJtxsBcwRf7J52x9hpW+x5mfM330eRvKU0ycK+sHna7XAAz7qCcmCLYq89dFaMaVfofXOFg6aerK4Ty0o14yhthHONi6'
    'NOHRH8KtYWgUFhkFLljln6MbFfBmIaMUcGmwh2JEK+03ksFGcEs/CjFq/AO8wmfAqpk40G/2ln5cCaR2JokitIKozjFilwDgYhOo'
    'AWj9NxTLo+x2ROv3MZA70QHFlwqxuZiYhx3JxZl8GDFW00cQLnNxbFr0BcfjOihC0pvyhVDi6n7uC+f6dJA1N0nCG85qWOY2Jiax'
    'EWYQZ+AaIarTbWCoD1TCMAeQiclDInhPOm74kKMPEbYUKRM0csVXm1XEV2EfJ6ZzHEMsFK7JDo9aa7LLR4cWtZRHKqVJi04294iU'
    'ToZEHAGzwmODzAwfaRFddmBtUjg+N2pkEMg9UIadcXF3AI+SV8KV8PPPvtPChe9Rj6MBoJBclebpMs25Byfh6hgOEDbZHsIWJnEP'
    '3e1JEe6JQqUySdjZDLdN4P7zZUPdMTkmQPmCcHW809YOdnrJweONCvlXFfZUgWn2QydVUsSc8Gt4m4xjUVwrVMcArSEFwZdfvjZ8'
    'zw1Ycf5Ei37+Db9Nt98E+ut+gyH+8hXv+3378i5qnhri8Wokwz3NFBB0/DcIGpksviGz0G9YlvaukcS1pzd4T+bTEcpGCwhDDJFt'
    '55YYIfCx+Jk7D30UPn2GDrBSD9VH/DVUR6ciHGO0lfnxMWuwYyYmM6WoXWzLnQhcrvuFTqI2OPYJOQwdsQotKl99GgIBOlnHfIfB'
    'K0ZaSLm8ZReytDlpmX+KuI6Eammc6RsuGdTu0/lnIRUxkvm+HdyvA/gE6iIyS9+D5DfBxa/zt77O+dfQ+jiTEHlCW7/+eroYJX9C'
    'XL+MLWpIzbFO4rj0b7Do/tyDccmqpseCKXh4WOF/ISDBPBvJN44CglKO9EsNdmzgrAnYuzxn7/BkZPxFDdtDF1Le3s9Be/FwPDgK'
    'GICYT8c5C9DBtQEel24IyMCQB5eLWDwml99AJHEKVbIIdLGV6Xqc82KXfFzkDSWdgy+5jCCKJKrNOkKTILuYwVkmYEs0nfOUfuwn'
    'pvKlPrSIp8IT4JioAycXGEKa/AQTBLqxn/8AoGHpQBS+CC0Pl+wNLKi/p3ESZODwXAp4YuL0+SqE3qOm31zrV299j61jN4MObiXN'
    'uQNy0dqNfWUI8cqvfCEohF5g1+kIoUWdeKz3OEkYJBv6pdCBD45J1xpjHRQgAdn8Rl+o+G8cTNj46RXnDakS+VadQkcIuYAgmGqA'
    'NU1Spg3sPNaNx+OBWo0BYQSOT2d9fCC2DBVl4BjOjz7M6UM2f+RvufzOns73FojiOEa2iU/EKtEvWJPYfh68o7UKsRMb7xImL5IS'
    '69XYlm8ObBkPdbBRt1EORkckGpBng1+qhD+whXj0t2wzEQng39VsTH6a8HHPHDYTP0QuDHq9+dUbn75xHU0V+FAQQjFQDVEKFmYA'
    'yJel7fDOUozsFOQI5tuuMOxN5Fie4w08FO9g9gYw06hSZ4fa936OyC0BMfLoIiIRoQhR5kbHz8iHeIHx6BUZ8Tj9EH5/T02c6JdB'
    '3pR8zJN0LV3zYud/ZX5NgfqVO8T5Pi6R2rQUUBtb4bVTQiIVj7gUBtw4tfKR/UkgYYP/Uv0r+hP1I8QJwcDJhMv69t6FauHAv8tH'
    'GhGLacTdT/DrRlvnyknCb3yLP3A5gzql+pG7B/xaFI0TVYq+W124pVfMggB8YnDVzbf+Rnu59DXXkVFor/sOXWC0OArdl5dhraNJ'
    'HhV8J0R8FvkXLViGbxFXy9cL9S08WWhgDlRaqiv74SHc0H756dffP5x9RvulzG+3nP96Drzer9LKeoc+Kb/TL92jHx/ox4z9OKMf'
    'GCb03bnw7ZP8OR6obpwZik7k9f4h4F7wehHAlavWDA8do/i80H9HLIRK7U8b4QMsY+FCoIeS8KuQyefxFz18Jgt25A7WDtuCkw7/'
    'TzfLo0cK1YgwFiwBvUz4L14OzhkyKIE2ifE90iftM8mD+BdEQrTgo1QY1SV+wVZ++TqNpePfLvCvyP9m4t/iXzhyuQZajldF0WUP'
    'pIDwwjAyCMxoSyID0JeZtjk25gL0qPoUhXwS/lGUwNBMqh7BJuwFn3x4/ewTdAi7OfkcmToxpRuc6AbRYj4f4WpXuyg945XRpcoI'
    '3mtG5D35AkGlBJSIMySroPplhTrXleHzdHPGzroSye0K+ospSFzEQGsLLAXSSh1PUkhtEAUoIF3PWZNIHh2U7mMz5viQEvDrv5G4'
    'xL/P8DuK7w77TET4Sog5qAQOXuUiQmsGDwKM7Dc2nnQyk6cthtnhJx33P50s5uGbfqISwDP0xiQyfBbALcOCsMsev50UBLL4b0R6'
    'M3F6oBqw0Ngj/pJ9ush9Mh0QLmfwv4mIe/npE8ipsNVpoA+f4K/MH9P0uOOP+IEXSPNHmR53nz9/ijHeegqSnxOb0yoiz1ygp88R'
    '+D7/C+Ly6ABCCIoclQA6xIivCAaVQOCgxUBQS3omv/0JpzxpSUoXL5XFYJnO00CWkhhfNXZ+7ttNKkzzTTHQkJPmJlkyyK1MEzAv'
    'BQsgy0Zgsr3gFhNF4LaP75uVkmjuYxek6KgpqkXMPN2q4nehFQ1jI8uq75ABoMLavzpW2qER2He/WHvMHuxyXR2PxYo9TYM4uSen'
    'GVl2qgELMleDSkkWZfgi0PSz2/SkWJSoMkgdEWcRaUUT8teFVH90NZy7MK8kD5gu5qxD71eq6iVJPdk0tyg6YExnlVm2kRmg2Ap+'
    '6BNYSBdmr8bizAnBr8acELDTrmoz16hArUjbg66AsI57EF00e60KkuyYbhBKkLfOVxz9WtBjaL2aGJKGClTTjEf02tBn71iFMY14'
    'DhxZUv1bPfgu9ISGD3zgn6gx0+KqRh/p/DxF8XKadPDMwp80u27rW1q5BjFqTHoD8mMRVpsZqqZJeYdC+J497+O8deK0I73F4/4B'
    '6AXqXl9ZzsQ8P8IR1+YauG946ZQkPDgdGDSHYmlxJ1QMHwIHaL6eJE8WkuYe2qN/1tyH9SQWsd/F/8DkHNoD59Ceb94OOUN/u4Ja'
    'x5qx4NoVJ2H8BZKx0KCtGcuW8ZqJeIu8Bd0AIi+XAe04gIDSyXypCM8zehbFHDxPkD8rkJLxL2JBLIoT0mv9ZUr/zt9xNx4e4jMI'
    'L2UxZf0KDqYciwuSIlmeG+AmHwPEWIgRybmc6HiF8AzEPu/M/8rCkrBIlJpBkSiFlamogftb7+H+6d6PLUDlUME8mUXGh5yEhdGt'
    'Im9gmfB3RsmK2dI5Rfah3/lCVp2cs4g7+EKZqEWqgFuGcWeSYoZ5A+PXwqSYKaW5V7F8xXhBGa9F41WDGD6hqwZpy5HjghfJYglW'
    'NpkuIX28CIeETimqavFa0RpUKk3/QNIlt2RchnCaYk7Mi6XoNMVpJpMphtNUc2peLYfTLKhSaapGpimqWamgRqeZy4fTlErSdCKd'
    'TpNgM8QUCBzyVMmqaQSOP1iEAtLzpOivAQeqP1gDf6VwDXg8I8myeghhUac4/4G7xSXx8pgLiNtjBVFxgOtHnufsAeZIkMOCpN0y'
    'LZFDKpNoZCykXIyyYDgQyQmMv1s/4BT8pM/oxk8xrgJv3ogWRkDWC6Y2+55K7ugDmQKAUZtFlMAi8mnFuK/IRoSKKkdiKmdJDXUX'
    'mQw1xHQSNK0HwIFAMIUYBs2KExZce6TrisxPkj2Uxvk0L9jdLAzzxbV0FFWLaV3CmLvYesxQZ8yn4j1XocU5OSaJHlV+6k5Cv4iA'
    'oMIIiLJBkYPqRB1UePd3GvqvEnO2j5Iw9HrAGFvM3Agws4t6+iL1YLde0aU/fL+n9/vAyWL2tibJd2CJUCRoP4XlfaUPtEu/fYUP'
    'MqS+dYntxRb3YR4/ZkydU23cDNqyyZ+T+V34KiZA1TYOXWGeGb760DklpGx0AR21kXmNRwirvccXgZMODu2osL2PYwGUADgNvV1P'
    'NFm4+Z//70GDE8Bju0mu8IkCGlyQ6sExdfQE8x8B5IAP/OwDetRI6J/hGIVJk5I7kg+JvEvoh0KHf49f9uzLnr7s6QtFZQgdwtTD'
    'tRdrBxJbKKaSoaj9CXn69ifx8wWJI5Pwg0gfMvyDHH7I0IcsfYisLH2l//hTuGDvJiQw4E8vfmQpInXPjXr4rx1eaLA/GZzqvwoH'
    'uPJfoe/Hyfw+fWKjgQbg6wolnRWVkll/nz+Hqg93PYF54Xbi1DDgGcPiwYyPpp6OswkSB4goy0MmzWMsm/+IlmXon3mMyJJhhEIL'
    'dx3Z+OIDMkT0YG4ljIjtkXvaBccfU5/Z4zc/P6BCIEa5IRx1CthDifqOEKJBWQoGOmV30fAOWij+Yyxu3mGgGPTVVyJdXngv5Er8'
    '1kJUxx4MM4FX15ErhR8IwRpMG2oEmuBpLALEcRpvqB0k7aKJih4YB8YJJFWff7vKH8ySiQtLXGAYy5LG4usj6E5hDBpJQHWGek77'
    'XZHDDuuZuoAX7wCfY+RD0//pKxU5vMy16A1lvkzeicLMMwPlDfIMSEgcOYhGhok/mByIwczNLQatBAJBMhZQzC/w6ovwP/87C/LI'
    'tIQxV5sZGFxjyb0kiKBE8IG5peiU/BzAzyO3FkSqAaLhhCBAL3ieAyWNj+GxUJw7uZp0nYR7u82MGLX+2wkSRZLCP+gYGDWXSUe1'
    'Q35wyBhDexPEd8yUQtQDR/AbdkQIMMYw4ARRH8P1RHKCQsy1wT/A0kWAAgCIM1AwG8FRkVeTz75oRKHMyAWL+BlHZpQcI6MEchCJ'
    '687awOCXc407VE7VLcrX0VwnYVWXLpj79rSfeNzO8L4KqUoVIfYFL10YX658l8rguK+ARxjiifXtesgqqDZzrqG20aORRV7DponR'
    '8Ech63gX3DNnKl2HIZHZDaQ4P+og11XTBOnqhyTgZRedoxo/ND3zxwGA9VSHnP3QhCUFCo0I5FHcU4ysGrMuBN8HCyMh4RzJDnFK'
    'AggOLITDPf7dY4jQif/e4O9R0o04sKAKRj+G0Qg8Ryjl70I2k+Z8I4hrOV+POMFt8yN6ujK65r0PYmKemD4o/u+U9GDYxIVwyf6k'
    'k1l6zuJjnh7z+Fiix9LnY0SI4TnfOJah8/qcWWfSFyTt+eb6E1ybYRfFsukjVOv3gfqSAJshgs2K8SMsyS1CFAGQNiZs4RX3aPpq'
    'jNCIEpxsmxbbxFP7e4QzE8mmGSm1p1J7Vmp+VCrKxALVsnHjbFa0xG5geC564Z/c1ff/AhCyfCUuS+QQukQjbOqSxaJQwlICusQs'
    'Q4wsGubEhKPnqjwc+dVRJAV2wyV5tKbMP/2ewglEx2wdj7mAyPGEMT/6HrVb/Rw2CitBR4P5R3qBKhTXz6NVttkqi7mjtfVobXnj'
    'IvqBIdTAgkWoUejdQbBFjmJp2ACCr9+EXNpnfbHBY6x9yY4Y8y4j7hMOwe/kdJNOpilmXeRWvguf6BDhxvmnyX3nn7J2aLLlSBo/'
    'hHwUxdu6u69c9xs9FlAab06iAE+OcVdCEC+FB7f144mRwfIqiBWGmIPJ5GHNIDDZH1UNLzBSJK6/Va5ve60OGw3ge0QfaC5i5Sko'
    'LsUlw5i6hbDu2qAIylyIjCiYTrAV+4709F1orwZ8R3SNMB6RQYw1yZRHLYOnR2OOnwzUybLMnwHeQBLpDqo8nBZeZsZlZLVi3UvG'
    'OwIWCGkA10D5McOwH+4XFSdXY3Iq+YJL+gU/XPgJvGJhE+jvbRA7wyNe8+sGRyQR6Ng9y8AGQi2QPcNgUjG/j+D5/A+pmDEaNlMw'
    'z4nqBIpH8okhHfJRqjNSJrCYXxQJm9TQLhUkUuWrJHgCE39JSPDGM8/rk8ZTc5gLDhJafp2NBbMN7bguBT6Tju4voI6D4jMwmsd0'
    'A1z5iK5nFxgk1o0Svq9sIYMo0mxzfILEcDO32q+1sNicoOucaapYoPIwELWq3/LgD++pv5BcolYdxwGnOQrcn8gMTCcBJR6PITl6'
    'ySPVkexvKOcUOePkPcXuw2pkeHmjIovy992q7/4FLgDJYTviD7SME31lqwgdvs2FEMYidp7MgVEvwLdCL7A2o/zkBE2nEX6SvYry'
    'k5H2Q4QaivQfIgqXkEuJSCk7Ug4c8cTvgmHQWqx2gVLg2/GrCV+1zwzd0kCChves4SgffdKwxBd5FTY8OXrlN8wFOzg212zXl7jk'
    'PhzAI7EP6Mf/+eMrHd4FVbw5qohw51czvleNOQhSpY9CFp08Iy6UaYoGhgP6eCTL2oiCv0u1L7FRMmOK8WMfQxDN3/OB/kGDxhsN'
    'ihfMP1z0IZRL+khAgXgGSrTz80jeAB+7eOYaDZN+6AOMEg7YhcP8LdJV0jpEVA7ReIASnuACesyQExewonNJR3Etm8wHb0XuddhG'
    'eYOhbziaVDnmaRbdAEALWj0eUT1gzHzExSoa/TAoDl0v99gNNAzkQIQJBQlq7ZJJqqwjin3I7ZTQAVJRL9RngDgc3jDjtw/ImAdF'
    '0UKLhIwIADvezG5KIauEFawV68L12CWCwOuGxodpZpjOViemz7dhsjGSrzIQmCVIcUroxsjmDMelztw/TEbIo0oNzQo47TrTKdnR'
    'FwHEwLMTsHSM8juEDaAFhBqHcAD+IOjBLfD75OwVBxXkK2JUiXGEFFqR/6x/gqX9Tch+xhapLcYZ+mX2R2WYhjciS/m66/e0+ZTf'
    'gCb8iX4RHvB7gk9J9IMlUGE/0QUWQYzwhN9b8AHLJcJqCIo8bsz32038yXYvT9r9zKHavyFJAMB4gTAtLRIbFxgQ5FwM9cTjNTwG'
    'CF7eGoD2lPoLMRKIWU+an2qDxU5BBeWcBxzXOLuCEraF2hnFdy119SAAedAdnY/IUcORk2PuTzxkmE5X+skdN6pT8A374V7ixxZF'
    '+4BPFyzh7RsA7KhY5vYTRmVFqDiRNFGuZ7o0ekLdnv+ceI9+Jq+99uhjBFfeclwZgXwmNELXHF/yHwT5WD0y3Ct8jEpMHEi5ru6W'
    'nTlaMfrBTkySfABir3A0LUWIpT9gGozw7qgXFZn4O957EBaYaFQ8in5vmScMW2+kAoT042EFooanVfzyPtW5OLp1AGDOWLBbptjW'
    'LJ+1uiWdNMA7+x5MXGQmDfjglww+pf222d1DK4SsxZrs4GTbInY6AETOf7Novb5MbJlLlcJur2dzH4Mn/2hd/hAM2FxDSOC/AzQI'
    'YImuUn92Xf9Mf1TzqEf25nWfb+wNLvuXp1++4k4kd+iWR0/7b8ItPorBS5Fe4lMmeJcJ3mWDd4iKo/dbUFANPDNZfGlmiiX5FY7W'
    'F6S+sBeX+ApvjO7fn/3yFSl6NpnB1vExk8x9O/siXL1uh4Xl/k47JNOftHAe5dARQh4YdxFQCVj2OAv6YqGSRXl/ButDKB1nSDj7'
    'm9Dgr35MPYIKPyYe328u8eeaO6YZ317OyP0J11H+dsbX5fjXJYlH78/E4AWuLDqXvT8jSfcs9SG6ixRuzGbLImuOjJrUHTYJYAiN'
    'ynv2vIdnx98/MZkhb5LSt8h4UJT7Ro1H4puj6YDJsSoGaMSo1m4o+EqeJ+F1/tAjcfsWRAWQsOWO/uhZzXuBjyyCOvMV8RkqIJqo'
    'geGSLfcDw7jajP4BfYXuJ9psRvlIkIQwr/NASv0YgZJfvirBRFEbE114X4h9tf64Ugmh/O1oG2TJ8ncBJF5J1jxY3mQWVy0AYBwI'
    'EK0/1738nb7d7Xc7hubgHH3jUMB7YzLNx/DcxBh+83E41w7E2UFFiQYWnpeJnw7dl6xOmusym7OP+7/bJEeYfqOIRdda/J9ZF8pu'
    'wjNJvlqawGSOKvEtqXfj0M4vX+ea942p4d6fAefums4VGThUxz8yx+7kgXmMJZNkbpacTEnAm+hKELgogPTA+ZF/5VkdSUIwDY9C'
    '5mnRuxI8ngmQYHZD/nUQErIBsgCkFGXAj0DCB8tMgJQsEAPuu1H9Gde8oSMWS3oom6ajaAbmfEsKa+09uxIbccvGwJ5+3jfuyB0N'
    'i0H+kWvtQuC+OYE/T1SVhPn0mJfXJyr2mWGjIFRTdNP9eCz4LkjDFolYj1IAX6K3ozcZbjwip6NNNLgHSsUjTpyB23VUz4IF4m+2'
    '+oOgRSz+D/PuO3Kq+n40o9AhkSSwo+g+kaJTXhT9N1kcn48fUeckg3DiIKsg769YUBcnffXa2uSE1iYHY8cLjsiTyRE7jW6YESd4'
    '/H0hvHLlpEaC8DHhdS4AMfLIRS9IBjIGRswgvz/SuyKjFvgM++6x75jSVqLrxRec6UPh+Qz9zdj5jt4ZiN6pxzbCOL4kCKh0VTzK'
    'CjAvYWADMNulafhKy1ciBhGR97xI6KXJfeO4k1wviaMiDzbzKP524JkbhnvyHVDwfnEvKQcR9+M/2vtXG3xBsQPpPjL+/vb3X77y'
    'hvARR8GYMm6ooSXBMMafT4UeQhHhZ2wSO/rlK3ddTiT8hthSusCDu5HbUW/6LbwXCtxvgRUnBO2yQH1TOESIcGPkRZw4dvPFm3FC'
    'Cn3uUwR3RK5M65JmhrWCZTt1jmXV4vFvPlbGf7Tv1DmClaRXQ+drbExDSuFDXN8AQHx/hoESu5iCt2X0XSAejOtBP+WA7UFHZZ/v'
    'YYP8AKQVJ/rt99RxR/5QjqSyL2tHj/2FrTBbdboWI4Q6YVWZqS7XkJOhz1/vH2McHlDIiL+NUJQjh7okF0xZX7BIgfY/4thMWmd2'
    'AzFq3Eqi+YECy7BQ5KhW9Q/5RSR8YCEIU4AxKFB356cPJtUJkgQgr1fCF3TevMSR4Jri8JB3/xY/juwc2t5pnU5Tl57mGOVqFIZG'
    '8GNIWX1+zk+FFknNRnpL5EIpPAlqNAJpkt1nMAw/ngk6DdCtgBD1TE2ZPD/XGgvDcRTQNcjV+kaM15Cg04swKAcaiHFSOk/myh0t'
    'CX0yz1Rm76GY2Ff8boI2napEelik7DAaJgYNClzlfRys8YgnYbwepiilpWTuV0CwVYmyBsNasCsKZ7cUlRJYVmJ26BYF8gfXvk83'
    'uvWwEWKIUwxl44YLRa0zO88bUQD118H6kfzyuNwn8YExZhTefmJxiqK4m6FIHt/8Y9IzG+ZWdW4ll3MF/O4ulMJLifQAPE84NGgu'
    '/OGjRz/LyVHA8LCKfwHyVQaUY1gmQGG5XBnMRODkBxNfqSx6QgguLNI6IzCsJeAyop9JbeZ/jPsYRvcPyhFNZJ48zF43MXcsdgQL'
    '2mBErcDHrrnHpt+IkYvyaPgpNFj2DH6ouQMHd3EIHEktSTkOX5W+CP2xmDlJYl4aF+T4hUYg5q7r3ySjeLzcUBUpeBkWTFAvtPu/'
    'fa+jPXU09+sza9P8jY6Y6StS8DIsyDo61ubqflw7OjMSP5+YK5LdVFlpGHUOwRJR0rnru0eFIaD8axQU08gyvVDf+lOYU/nEGYS8'
    'nAxmyqYeLwJVMrd877mhm5mY/XG5msdjHeGdTK6bYt3MKTwVYYywIh7zFeEaDV0ImIqXeV6xVM9eJFJhPCl8IYs82tKjHmOEXoLJ'
    '8LgzlBATBiKrQf7ZEBsyk32IXJhJ+tPnyJ1GWCkWEDfmO4TR/XlA6RGO75VHFf64NelF1KnqOzxP6Kz5Sq2cJrNVbEk3G1mAnMvQ'
    'm5yiAiwZ1KDuLp2LGmL4gD0uAtAhs/khs5NBYuwok+bHfUm/4TVFQc7I1IzIzyLcQrfBkLxFXXOsMP7j74LvGpU9KeKz+1DE94vK'
    'xln/vhNPaKChhWRIJgnEZC2rMeSZmV5fhqocIeB9WhOTF6FS8IKFxiV09Gdq5eK8BluE34TCkX+QRzda8/FjrTxaB4LdplCq4c7j'
    '18AHyDm+js9rwlYy/66oDy2bJ90+x8rHhjDmOXRkwFqYEzcA2z9LDIO7++w0zMwweFroInLx2vsjQiWlUFgO6QnzWjihIyHNlIik'
    'TN7mMwO3DyAdPNygSbYMP9ygRI5z/i+8Nu37jYQOD00KPwnybvzE+TL+hjthmrtuB/6EzBeNr33kEJEzIerh+aJJHsNdaD71VLwM'
    'EZql6AKhGqQ5YbwmD1SPz0cCG4ZsDHkNiv4Tcg5+hpUjBuTzUaYWuhLAdQMfBRRwgrwoV6xx9hYf8VWP9h/VZiufhaDI4r/C4v4c'
    'sALwcxL+DLcPasVDxv/891lE7Sjmzz6cf180CHflDbGAjekk1Qu5s8GBzSTzIevP/NtYuni+N/4un0gFWJIkPyYVhC5DVyGXzdlq'
    'XEJNCV2IcJmQB/8W//7UU7MP5z+AqIIPUdAD23ua9iugKqTjvtMejiHoEg+1X08PporLgTv3Laol6YUuXaT2Qj84pkY04cBxG+2V'
    'cOSzhieau8TFk/+qfHgSpvbiP+DQFPUS/kPHJIxCJrHkCnRl9Ur4875GHJA+hn4/J+5Gr7yL3voeuBpB368ciE7d9U+9id74Pvn8'
    'Z5DTW6DUDnCTD0YkDXx7K9j4m5CEu43A5u83vyodMHKuf/efnVFi6XTg71DPLM14yPeAqSN2jl8QwEosV0IQhCbEcj/H2CGkF/eK'
    '5gXH8FVQHFLB0bVaNBCKeZ8CH4XXK6TTwi9fXwfPO056hy0F4YL4aC4EsYir521Pkj+Fged+HDEoHj/u6DiUk7elGLgFFjntddCk'
    'hFBiN7I4q3nMZ9KCsMgXKwJtLpvs6QUCdRD2yac3TJXxSU/62bXQQ853ZHuD7WMCHSm7ZsIbmPM7NoxfviL4fBTOj0kAj2j44Xd0'
    'aBJIB4YKMNJ/ofIrNGfBj7mK5xl/zVEvtgvtKSBNceGImVN8s2AvOZkdWSrfRuVE9Fj6G11+w5713Vp4LVZMZkgZGLj++2GwKA+7'
    '54cM/vI7RYijQa+S4SQxKApWwf2NaezKPE4BS1+ithoVkkxeOwNcB1OVDO8S3VOxF1hndAWW9DOKgHU5lVaaTg0TTPO3GJiUtIiu'
    '/2bLlxLOQbhaOPcPv3xVXRmA9dvvKRzChy9hbBCMLxUhZN9C503/pGIM0R8c1Dfh7ZTM4fxJok+TPJ8OE68F5JQBIb4G1u9ETUP6'
    'ggnTPKKHIf6U2M/4j1Wbb18H3lGEi8iVWnaajGTkOi27aol8UxiKIXJVhQU0ZUBF0Zd8Daa7pTv1Idcw49lLiX6REz8y3jxOq1/v'
    'XdgUc89/xyzXiPdJIqWgDZjLmIsIwTZFm6cgrq9bx6vGzLjAGp0l4c/HkxvjGaZhjfsd9pJ40Z6u4ufyx90G7feSFE/gpFkxWfAb'
    'gVcUXva4MeJBcY0iSU1fX3WPzOM8Yn49f2Op/M7ClWBRbKln/HgVHUE2Hu2YgTZGOehR8CpmbqFY8sEs8WuURXF2ry9qR7/TVK7J'
    'RMTuDdKVUpfwLkzNkUh5Fn91xd+/Yx5wKF9+56+4LcEgPkQJ7QkG8RHKPsCdHKDx9579nvPfPkaYHiFP9y03g2/wHxrntxAHXqEl'
    'JETo/jAChKccoXYYxhFyh2EEQ3R2/8JojkyXzOT9XojmYobNPA42/u4nlq4FbSFREsfsOMxg4OdrwpR7Zx8i1q9QGR+CRdhSdD0u'
    'hUK4HOxHdDWQAciQyYoN+iNeKsIrRKfL9KOCJ+TRwV0AriLmVyNmMv5d1w6ih69WOHP2hjdUQciFxjAWz55GA4sxeyOu69fwStr1'
    'qxxL3MdY15ZqyDi6nsTiuMp0cztyoTR06IwcKOTa/GP/3j/4dLwnM+GKf0Lk6x7lp8EQsxGFjb9z/HzGRPRyS/vRqV2XGrg44mfy'
    'wM8gkfSr5C8wvusPKpTOzuOnGZtn0bi4b63f6cBgTFke0wXjAfILW/D2S9gT7SfFYgHRlnf5Rjvh9II1ip9k0H5l143SR40TSM2n'
    'kAl8uZqNTxf1y+8yoKo2XTaEo4U//OMVZQW1AGtoJxhDO0UZmo8zCpQbzW/+iC378jsl/ebZ1KhDlogbqv6H+sNeLtEh6P0Z2Voj'
    '84if4e12VwWW5tq1YEYdTP3x/mz3pClj+J9AYRfDcxO9grhPR5bPQwwBUHEkCvAYIfA2ws/7ZYJ0FXqQruLV8oe8qBHhRVGDqfF2'
    '/4tY0FnyNRNKbwl1zyIxz3k9Jk2w1764EFAEoNcBy6qHLCtf0vi7H7AM7HhFV/UUtNf7422gP772OfMapEmY3Yk+7cUD4fkEdk+v'
    '1whVu0xInaMlMkGJHzlW4hohn4QXgABT/M4s3siNfdfl7gTG0BdLUvDuvsFCYB4j4NhZIn8WZMLDtHjAAkmCu0J7yNk//tf//cyP'
    'Fhd4K5qW6idHSgo3GBzQM2czHy9zTxPEE2zKW1ia3AUabN8L+3ApQ8pxuhF+funzBAZEjPmpQonCRk8EtIm8pUjyFGlCA8m5+Hq7'
    'OGlnQ42Q97fl1yhampChL9g4eoWnVBSjSGMSRRmZDMNOovg9H9ojUTWkt6kTDBYe3Mku7Py/5LCKmZNzWowKi76QQeePVts/figi'
    'fnklIr7mjl6zX/E3MNU/u02Uu/rDLQdrDpYwMnp97GM8CXnjCfe0EdNR5QFJLH/k6ZwsvNqkCCYgWMkl8wEOmIQ4YILngX/LBN9+'
    '1Fnm+2c8uuo/YElJmaaCXE5ZML8ehwfgSWLx+rrnmatLXZ168StKSMXuq2ke8zaNXlcmBTFlbSWnasaZGRGb7VtM2txHB8C6zH1E'
    'gKzppZD97lElAwq6534XDMh4PJe0EBDucOyvxoxvuAVbXfnAcbyHR5AyDyFl/ich5W0G+i1oOUrwiqPi3Mj8SFCYn0gKeDp97EIn'
    '9Z9h45O57zqGf9dt/00Am0tu0/RUl5T9R5w9590ppCilvdV4eG8GWg67okhy8dVRkkFMCGpgm0KMV5Es6yKEMNg6Ijgs4ssRVBnH'
    'RAZgy/izsEU9/mn00rJYum3VfRt4Qlph4CaW/E00iEykI7tYiOximdGI7L+Ogj5dYoAV8QJvMJIaEtUKvh4yyqcQdgpwkxEI55xJ'
    'oRhrWuBZh/4EuXiArsLiPx5d/gecSahdjAz/SMt4JKyEXyLhMWLkf4kaEHwAcoR/gBrRL3a1AcUyrj6ktihjWuA5jvnW9wNN3cai'
    'nuJkKCBtEtpvY7983UAJdluHnvbf4oIrS3rwacn9K8mbHW1S157naJM1VGZaKczNfM4CrP4SO/8LcyjYn8d/XBZatExXw5GiQtV0'
    'YscR4xwVre586KxvzYBj9dB7wgxDzC0eTaDUVGSu+NPdG3LPNPWJ5IQv6Ei3JcP3fSffXhwx7t+TaqxhyIxDjFP5Bn/NSnvOHm1H'
    'JiwNZvEDBIDzq3nqKtbttTr3F8Jjt9VMuhSOWpvu0c0g7me3oSDJLP3pz5Q9cSg5BksyHPkpsDxa7wAZSK4XO4cZ4H0aQvRrz3Qx'
    'PYSPbxxzC2KY8I9//z8oK3pXYpk6KVoVXsiWppjCCiOaUBa9o2TagJag0/1J9uxIhufVSvNiTPtoaO782tBWsAjoB2F2UWvBDHBv'
    'z5cIdFAwTJuQT8cjDbiY+DxG0XX5K+6Hircn7jTH28eOsw+iyxYsVGzhmsbrkaF6sq1SZnKGuFHR6xs2eNJnGB8+U+gW4ATZ8Cln'
    'AGuUj/3E7fTn5lFGWoz9Da3jrT+8BHI0Wh9ij8aNU6aldFUVEAL+POc9/Xy6TL57e2RVfrTS/pJEtsW0YvHTdeP9U49hu6c9/qm9'
    '9XuMDC/o8QTGODOGRM2RmMfvMbgROT2bryeIRiXMCut7CXMP2yvuKhuGW6dI5WG4dR6+DPA1p7F4QcI4zvx77mJH/x9x77LeRpKs'
    'Ce71FCFVVgEQQfAmqZSgSH66UCV16TYiVVmnKVYqAATJSAIIJCLAS5Ls76x6NatZzMxiZtOLXsxj1ZOM/Wbmt4gAyMzKc7ryKxER'
    '4Xc3dzczN/uNQZNXWCNuEZXBFF7yvckxbdvw125HSee4I3jXsx7j4kyyZKTmP3CAywF1N5KQm6ooArw1yAqHkLUQmOursindRmx0'
    'FUwtkLZnZxyaGEcxIj3I7XPMlmDGellFW/w+UnMGNjgG74qKJCNJwzOaNgM5TZPFZs6okpHsfK9eU3OeIEhLkQwvPU8kmD+zZYgN'
    'mApkW/9syVM2wtJgrYtDpiIvy0p1kOq4x4/ZZAxFHuAfTyT2wwkYg+JmkzPsWMPhlGbtArZX9NoZA8FucAlqphoLYwnbA3henpBG'
    'bkMjl2aEo2ppqFumUUHpEDoRbCKZGgP+uykUiFKZHo9mU2bbOdK7ARhMp3bCiax5Tehrb1H4IHvy5jVJME0q+O3AAXWmxnrRuxZk'
    'VbOZGUnvW7ec1rtWXQXVcDTbanAdF73CzEa6tFRvw112IJJovld+Q4/RUBPft6V6rtrG+U07lqbp7ZzNEPU39Q5QE9yYS//TahLp'
    'novd/jnRCZGNyE6qJQex91ewK7OqqlOkTIycAFxrwzIgVmiVAw2sUFONvOUULk1jYaPsmpUlu04rHI7CdMUeSj5vBfUYrFUYgYxY'
    '6OOxoLUZXEZdW9YJUGznx07pyvZQnKujNG7ivpu87OW4OfcGGjtk6DVYCqbtgVRHzwRYGvc7qwb8s4SEZ4CrJS3ugjae2qSsirux'
    'QUBSBr3kg4RtwDG6Me/J/ZN0KCGqulF8Hl+KemCi0ThM+GVlwRBFT2IWCpSNGtJOBOdc9gQ/pA4sWj8QgzqpGXCNogRBz4uW7G+d'
    '98vDLZGlXdBpLwb5qYtofmojmlvnBcYA24qWvaD07Uii7Zqbo09vLX/shVkv2xN4QdX17kVKvjVweqU2ttt+pGaTF2p5isKWTIqS'
    'M9PEUtOkTE0Tz0VC4gbTMK8SZ+mATRChkPhBsToHpglksMctSS610/m2XLGsmK6y9bcZEdjPrW/gogqhdzee0j+P/rzK1nBrf6aH'
    '4Ntha66ZPFq4XGMhb2Ic84bIbSurkAe4RkeCh5GbTXTpXg1c5yAG6okMfdmE0bdm1oEfxOEn7JTicjhxWJ+PV60ZvoWP1Hj3PKdP'
    'Nf2JMc8Pk+bwF9Gkj8PqsBQmfJswtYb+XLAYqkz4AsN+koJCq/SaLa41r98MfESUVwpVSaV2Oh16j1WWsLvU+PhVenQEw5yk1bLR'
    'BYhA/WhMg1j65Mz0BCBzG5NNG1Ky/D2byecBQuYVg/izm09JH8UW8BXjdz/KoZiZ4toB9KbGpktA93zo7yjav1IUX2I8X2LnE74u'
    'LpyJxtWNvz+JietETxZxgLA3LejQICHqTiLv7eYtojudxwJsMTBhjMpe/rMxnnMJmed53cJAFhzp28HSUhuqBHjGM/Kc22m5nZww'
    'I1I4MLZZ6CV0+l12EcXQZbmx0aVf2Kx4W6PH1KA0dIXVl2UfcMIggolxpGWOoMsJNJI9my4yFWFImfkQUTIdeGwsHrwpoeEIZkRm'
    '4c78gjdMlclt1brkQ7+wnwLe+8qTY83bppuoY0auCuE4IZrkwwzoE4hNy55WIntYzDjxBUDjmzz6orcJe7xHzAbgewKJgkmuP5s2'
    '5QCzA6O7cM6B3iFWdOmPPY1unJxlRcGu8dATr8+oSAG/TWw5CO8cyn10d5lfp4Jm5zmOCcTEVIMfeWx/J+jDe6qt+ZtmC1Jkr5dd'
    'NIlcKgTuef0xy+lZeEAfSuSligneqUZsqduRpDs79JM5syXBIrzDenDegUsIry1Ws07z4S0QOcJoCAeUGUkadr1YRl1XRZX2fwsV'
    '1lIRTzYYuuWjYRaz3sHG27Quc8SkOWIQ3QHmGomHSXwmfncCowPEwAkCMBfh7L7GBe2vXo3MR3EuWUI2uFohGkqiXGKvpeZkNCku'
    'BZvZ82hUoLe8T/WPSyKXmOfnZyTyDOE0/wPHbxUYfVHtgg8WTa5Y3ru0b1hH7ye+dImNoMRRFvsl03yBJqc/z3DisFWPPXFjxteK'
    'gamFFEtbHD87Lkxj+3Ksc2P64gMnLgCeO8eeqIRig3Qkcagryh3rhW1MqzLg3eMKQ5RVwDtKC/1qFUWd+SfJHReIdPGSf8xbDaDH'
    '2tWgGIBqsFFZFQs2yWkyIiljTy0UArFSjl4nVxrt532DnHHlaNKc09YR7kBTH1a1pm4ZGk3hTbA5l9Sloi21VJ9bBeM940TDOyS9'
    'p8Rmz1KuhO1wHSKf6MCfW1ydcZIMvEDkUNM5SpizqR4rNgmdA3tJYW0sct4QS9x9ypIfcrT8AbKUUEp+gCkaHnruhTBBSEv+hay9'
    'oCIZVch4m8PKxb0DaGF1RrRCIQxzsgUCvb8vBqF2EuVN+gvUDovJo0IXvq7kNorwj+vyNminn4Qtr0wfMblfVUHlQfWeliM3Oh0B'
    'mNUoN6y963rIOAm7dmpGU9eUlTtTLgMgdmVlCQc5E3WcBQ6Flqes70uZXe4nk8JT8gUaPhM/w1P0aVtyX1ek7ZHW8MwJ9lQwTGWF'
    'Xqgnq9el2qJPbVc9csGNXFw0j8Z3OtUWTnJ0hKndvJ1Ep4nQs2xzlcjKY4O7JVHxPrigyilDE5llrIKIg4rSsngTlwU17mA3tuh5'
    '7i4hjNzKF0gTDvFataowdDWBRpbRknJ2D+aqDT/mOH5pA9pq4AueK2VoeYzNZClTQrLIFUCTP5XuQTCMqk4SysXVsgEkMfcIBovz'
    'frP23kGNkphUzNVPKyA5kW6KULrxukL8tVGje5AXLHVZeYtT5i0NNsdClajwNLoQC1eiqCvvvTyuAyg4MPMtcAgI+bYpT3xJPrjc'
    '1MvMlegz4wSRaEGcWtENdO7HgvV7ngyOLeOkVi8TmuRsCgqkvCq3KOvXhDbPwm+zBykr6qmJIygOOtGuizkgHoGMoIpggcmY7080'
    'Sq/4QCOBUmVq4v4adOu0UMgGZkIliK8thV0JkVs6gPi5DNGqX7PohKRhSsBEAYaAiITv2UT7KJAObKoEPRZCMYBsvX2m4OXonQx4'
    'UT0/ZWjdBbtb0xbtBmyiki+YZY5RqsEcxtgmIzAr2A9ep+AxXxbT4dIqFbR8RMd5wi6V0+TnGbFpZrsdUTl6BybSmRoI8IULk1nU'
    'JC5e76+hdjWRJf1ADNr0CZ1rYNhNcASzwwSYeGW/KavyXohwp3D6xI0FQGkIymqXfMUENcX9XSqBkGOQKHzOh4boNnnSfQNVHj5F'
    '9dB9QaRqjvTmoyapD4hT16vimBX2nmdIy2HRcMfasjZpOR62qhKmXM3YM0g7sxMdQMNpLpJ0k9Oc52ObzyFCwjsDQwlnNQiUG6zD'
    'X3vqhwITW0ybGSN7YID4mlyXt3NZ9RyV7r4ZcAtaVacSgA9Q91yu6MoFJZnaKOdl1/7UKXsTD4/YRtQPZ2omfqAT4VbxSERIDrEN'
    '5pdzahhqQZAxSWtA5Y/b0agVhPmxGk4Jbu5UrFWNqUlxEobO1Lrnl+7nPa+U7NeN+5N1L6j96+cfSsp6jtkX3m3wMRKv0v9pyqcT'
    'z5X6uVkCR/GYI6piORMrPLbHqbnQl31D7tNMSDuJpcbo6J6PjD3JTSWCyR6dAGxrLJFgxsGJfxIPTCB2joCDiHvmFBZkLuzwx1kh'
    'UPLeuWEPAQcJqOqnD0JLAI4ACl+8Gm1jsCoRB2MozuM1jbgRr0ocQcqBkZV3a/puyb3zb1dP7cW6MkaMMXya35XujyfmxsQG9OLY'
    'wNCarlYuHYS3rNw35JN4zN2RzoJY/Jqo1QW0gHDkjuExhOQScNdUfurHEzOKhOkEo8OY5ccTpl37qE/NcLx3oqfwCHvs/JoClRgi'
    '4vFi0PxEHOv+TYFV7qOBbafB50i1tkhcnW3xnl69hhjRqYZbNv1euYsY2VJkaQjnDa2TDgutEJskZn8leulMA0uYBYL9OOfaV7VK'
    'txjL4FTUtafspbKwEXeBQToDD0+P4OiLuU5W8j913iV1WBgCewfryofermFIJRfrKYy3R7+Fod+ihn43HSiQtqYdXGACAZPrFG/5'
    'zmOv4uDTqr1IhOb3vSgg7G2GcgzgjIfxBWv7lPnJs+FZ8lF5rArrwLqAC+hJV1khEDp8ePE25TQFV4zUzBTLK7DFl9V1yHyxJ+50'
    '2L+quda6nVG2VgzPpxLUMtg11Rmxz6KEcoomTKRGW4lZf8qbIgd0cdEknaURo6wwp4xgGfAdBqdiqIwxlPxrcWs9n/tXBZ4+dNKJ'
    'Xgs700SMMnjntLxGs1HTVEDM4h4z3DgkiJvk49eCknMAM6j+JPoG2zfRxn+SXMTHzPyfUI8uid31jTU8gvBk0VHurP4MnYysMdIz'
    '3Go6DZfelJoI5qOAEep0OmYmR/71vrA890vo08yqqXWMR0WeaHxc2dCrca/FY2vkwIVH0PAu+Ukqgbhv+KrgsRcISfxvLIwGr1+F'
    '0uDfDAPj4A8Z/EDy0DbX1fFoctqWhmgxkUoMDWzhctFBJMZ1ZgRSpLMl0OeLljMTkHPTGFA34+iP3tZPWzyS+s/l75uRQT6VuJLY'
    'EfxFY5aIty4kmF3fiz2XG1zUzMSNrYR7JSLWiEWI25rAZC+GyAe6rltnTNmKwiotQXCO2YQZJFxoCUD62KCcCitIoqwnJwxCXejB'
    'SPdhn/dH7t0xK1nm4miCMBlG8+BDs4J8xvhWJeCz1mF5vxxhW6NV5O1m90qWBkozLY6axyKgAXezKzPl/pgmd46GcfEeXgHAIuod'
    'ylmSTagVsWB4jhjmwChe5VOvxScRSTWSC7KN+TI3U+wy9WjiONPBYYB/wIRD5ydLM4i9YNm0GQkOB6wV5J1Q2klvw1VJCZjryMwC'
    'RgxVpMfCw8dL/qhL2n7UYPWePUUZu1AIsFUfL3vdxssWIR9ovgJhmRjKFZaYFnjFbiQ4j5eoQN8oxUY+1dk0EE7WboHW+BRcVKti'
    '7WFsGSopxOjDOsTezAOPMmCCsmcrjJRN9xOkTr4bpZ+VtD95w0Gdpky0mgsAanqBu4OhmFiUxoP0UJAo9fGnQ0Z3roalmbh4NBNB'
    'kI/ZxGUq12RTXA3/LE++PYnxqL++pmK3kWkJafnxmZPu6P0yvZ9r+2KFUkr4MNLU+NWDFRD9GFgOGsfOiQ37/fO0aPoQsC6/FPlQ'
    '/paRoUbOtMf1v2VSU1XES42cjU/TDYyfZj49jVAy4w55OblUCWK4bD7aqumjF0bRJajLvVSfO6DBO8WWrgnGLF1xQhfzpEKPbIA5'
    'KQU1yhz1ZK6xzwzlKFbnXJunvplJlreblYLN+WpKN+cvg/NSv5oZn6f2EKdnxJJJljcCq6d+bVzgvjV7ykJ7J34rARhw0aptQJUh'
    '9ClxLRPeO8/1TKdei6h7abOVcPUk5D2V77giiXqPV7qVVlnwgc+DqymFF7/ZxQu5suy9Y8kHPk+u1//C4MoxTg9DxCAElGYF+FRR'
    'pHD8Ty2J8VkUDwbSFM9aGfcsJOwVBWI6jIc0Cp74l0dN5lhYkXh+QtVB0XISwzQCLghp0YoG0/QIsibrF8NwlBLox0SvZ1lBnC+s'
    'kay9ouC0A3Ag5wN7L9/LqEw+fiBv4AJD7HASGAel/U70PuDxoVSGTtkEqPflWCNgCKPTI06KOHvWNHei59aAR9X6wQhg73Aywj0O'
    'dASI5/NYDPc13CSECVpt0ps+higJ7+msaOiJCQjNyBZoNSK6Q8/zuZzwKqu4XSJwSpuLVW8vaQuwhnu8WPPtSenz2kL7UqFvvXtZ'
    'LGRIxVZ7AhE2wBAj9vkiCHZysSYplrwUl0EZl6vtEHQMKYIyLtfaFq7CpAgCQsA8I2/zVMNIj6cGd4UI30JtpIwXawpaiUAuTcYD'
    'uTSvpkFEl4s1Fc0v11gg10SDC8ZtG1w64DZn48BTLxv0DPM266AprapciIQcllFuDCSfhTWZGVfWGZGCe28cJCSzWqSkQIL32fbf'
    'nWHnATb06HPU2g7GnuN7Zn0hgXOIV25yvw78dIc8ImBMgm89983F9rs/zMu+aZ570S+J8bXyJVgXlQOirHtyMm0FJXNtvQSRqaJH'
    'xuGQhgpz6PXbaNliA8dOuwbMHhHshJeT+GcB0sOT5FircZ7V4EYPF80YLdWBWPUfnPI0wZC/yMTr2U6WxnJQX2MRV3jA25EgBYaf'
    '2deKWxj6W2BUwUcvya+eIHWypffQt4Rmm/YK/qdiJBoUULZAZrAut0rM5I1mOOYYxorDVIb7IU6hLV0UPPh2Qcg5yJmIpTaU77P6'
    'Gqc0BZr4xir/qiLJvwavcXQkhWde4Ww/p6WLoCX8KOIhqsWc+cqSlnCiHC3xxoJhxxphqUhZcrfh+DhrMjAab2/BC3EZreeVdRTX'
    'zSKOtoLF1o7Y0dBfO5ulPGfM34jceHR0MOsdGiBgNBtvYlbcnDHTIyKkplNkYC/dZUVYOeOsbL60Vq6ao83iQgMr6OD00EDxu3Sv'
    'pXYwQ9TOFZYsjjb1NfNI1Cz/tbS+kloaG6TWOm5alaBKnhAolHUnGTBM+pNPSqa/zw2tspD3wj5BxuNpeNHpm3n4SabhOd7I+KZu'
    'GijdpUt3KekuXbpfNw0SH/058/8v+N+1tVUEvHQJ2SKNkm1DUXBFI5qWxxlfMXsbm/I1HO7g60/lGS1/DSfW+2riAJi/807Dq6Dh'
    '9/Vw9Y6GQLQMR+q1DrT0otVmXceIer7+GHCfj6lVIxOhXaVJnRy0WkfmYXS6aSfDvr/k9yXCC9gSymJDFFh9ogkDoupD1rbDxAP3'
    'xRL7w/DKJ/iHNhKoDbsMPkBssNhbTNnAeTxj4IdmPCQePHcxiFgbno31TpOFAhdrkD9Ok3w2LKQJYHdbzGUb6zTElwTPCzdnEReo'
    'Wshkpu2eSrHfP/fCz8h+6oGPP4yM5lbC63oI5PLNpPTjkItMiMMgPB/y5Lj+ZD4wuONmOws4jwsLZV739dLHJQ9T9Pz8vXL+npff'
    'O3I9Jt0OF7YgEoTUxjVanQtyji6GG9SVvSjlzEsBdVNqokQOOkzDqE+imXefLoNPl9UdsrT1+U2o3fgOZLJT+pP2DtkA+Jj3wINJ'
    'O/qZXsK98Wfz4afDcONJJfRFOsHuZR5+5oee/0Uffq7qLtS7q3/uqO5h5B5/hv5DzNH77GpJTYpNEnnscZKWmyAXauWmuozdND6M'
    'HsHSfcnOBnMTRh0xMjFVyopc1Z/4ilnlGDi8NgRQNvRheTPniYH5ocQKsqZFdwmsY+e0mMI4jslKfj6L1sxvN6fGRVJChtcxXr4e'
    '6r6URJNT2oNl+YiPyKpDVDc3R6xZTDmk9Mb339PYSDmIOfznyvWLxOhZf4xR/h6ua01J/cfokbvp92p1imJYqz5UnwKnHNa3plU3'
    'gYpeGE7DlgqP1xLMa+xCTfruXXn3F4S4caos2vPt/f3cE40kPKuJ4jNmE28uvTeXJtKXJ6fPIKZzmaJ+MrNQEeVZfixpo1BjoI9C'
    'hZv2htioTbrq3uUZOauZZGCO14k+qSksG8mc6PVyzJSH8M9QbxUa+Y/1OScIuaUheTl5I2fEEXZr7dxjS5QxB2ORyH3O6cYaEFvr'
    '5Pu1LkOs9p7Gxz5rEGDEOHu5Kct4uAfDdZFobMqGcQfWMu6w5dtDeuVwyJpfWUrZZuAAx8uh2Aywa4Cbta3Im7Gt6NI3sy+gQ5kk'
    'U7bdHveTzhggA8Qpznj9PF0NXaAZ9ua8fKAWvh4GVnpIs0xls0p7NqXyEnHoXjO+rROqBg80txutiiZJewSZaU36hGg7oRBmVUsK'
    'gTOep50+MOYUWzwyneOkaFoblIi1SlsRa3eM0gZLHQ3eZHXRVsR6nqZV5OjHYIc31v5mkWs0KpBih41UcRMpJqqgIsaxeY33TQyr'
    'ZmSb7IB6dd/Wd1c0DFBPUbbuotJKXrk+8TraR5mBYgTTPywV59p/G9FxSswSCv9QVmPXk2Cpq7UAE4JraeAqWYkVicOA60rZHr3k'
    'KXQn17qydeoW8JrCV6x1GiRHUDlXnW/rHRVUS68ujXkjEhfksokVw7cULrypsWJsGLNCmxGstu+2Zu0OxfobFGT8nGs9S4GkNhya'
    '8Rwwoqxvw82tBYwsf/it2CJja2TWcv4TzpX7nkOzFcRhGZxW9WZfzGXUJwXTPOr4Ez0KZowhzypl2yFcUHytM4x3Q8PPp0HVp3Or'
    'nuOI6u/7jlyOZPSYUj7M2NPAM3OyFw7sMaIW3LBO5UuX+IIkPnFmY5EMRk5qLL8Z1dvQB9cPoSmaSPxrTwP/mfoI7hVV2eOyqgwp'
    'UOHA2MzPl1XGd9SljOcoUpzdwFh0KD35CQXKcWxuHVTzddwzLwK9l3+rZ2RJc6VnJM0wbXbB9tEx2z8f9zrnBiMGw+gDOFzA8ORS'
    'E59I4pN5iS8D5Amq45ley1MJ+Fk948wgGwIs3Y6jCGTeQfQMFmh2omXAVDI+OmpgDCtmu/mq3GWA8pVaVJPpkjOV7oAx0mpbG7c0'
    'uz73WoqNSSIL8XI9ZQRyiwsSi95oBB0JvRX94RYaJM894T3le29ThGjzvVfGXL3PY+KfAjXIhYx0X4Mk94q2Xwat5ItJEDF17unq'
    '6uRCnPZGPRhdQbsCWNToy+d3UfPTh7+IPXgqfKyg6E8TWo6XwFSE/aKJudK/bHXuxQCFjLyVGA/eIk/zKB0GMGizKY4YqqTT5yjP'
    'ouenZ0lp0ST928DRsXKTUqRhSgTJH/LZdKju2Odxyuk7g6SfDWxSXfpQyODjOKZhjIfiDU6kyDg045Pwq/p/m895iSOkASSKtzdx'
    '43OU0ArqC8KFrbV9ewJqCs1zyzcZqUl0Iok2S17ttBvPoIHSEdwdsj6q2SB+5yzOgaDYlxsHxDLDw4nxIDkJiio4Tg24x5e0BHFh'
    '0VgfmPAUuMuA/5AMOY0Lx4pYleBgoTkXF0PJqSBO/YrIqOkl7oCuPLP64eQktptouIFuqFHShdtA2UdeQ8pe4I7jGYRgsGKmIMEF'
    'lTCp5etPIpCuJtyhvhYZGgdqazBJr0zGxw1sFjWffpokxwir0XnK0alsTDTEIhjzQrhiOp4mZ9mpR8dEjS0RH0uLItfxYWcQty7q'
    'yV1IubSOHDc+l33xXU6F3ZPy6N9Nx9/N4e7sfmNz7qW/UDPV35xbAqwH2jAArqrSLUOc4PpRvfkkmQI4CD3dWJhXLeplNiNuBtBg'
    'jHYlnn3I16gfO1r9XOwHrGoLxfOfMYg1CEBXXPxNa/4w/vr+ljfzMWM2M7RDwhDA8xBpLSRCmn9Izs26AhIbdS4eyvAYxFED2JBN'
    '0+Ou0gfq0Ny0zY3jSbcOrVdon/WUUrBecKv00PIK43hknMZANmRTuci1Jv1I5n1U1z6PsfLlT1pgdPDwzKuUq9k49mzTf0NLTBAg'
    'aGQ+gzibfvW6qbSjmpfmrtKq+mVYBA0cxybeUaN8Sa6M0ezkN0tZ5Wt6kfH1cyc0I6kB/5NrGcEc8bQrwaGBECVtDuCCbSr8wvZf'
    'j9qCMPwwOpXzpska2nU/Sv1xZ3KJuNgtc3ejZ4QLiFIOSLMjIVK6xvSEzVQmYq0yVGMUKkfv8QUe1swGg4+0LWN9hJC8BmybqhrL'
    '1ZIJZnkzufgGp66JS4UG9S810YlNxOXx0cdJzyWnHH/85kTewNoBOxu/Q3walOQ+/aAZEKNGE6PBeOGC1cgvDk8juMmNtononLxx'
    'NfJg2NInguXFXypjr91BV6Kn2p2bVo3igzcq0W6EDryLaQ/LTz9uejuCUVaU16LhvwPCFZLVVa5N2ImSDjYUGopgYU0TcUpa+Zov'
    'fbfSBia7UdnLyRGIUqJIRzRY2ndGYpNxPwhAxVt2hzcqa3cc94iHzWAxB/5QoKyAVwAhrmkgkHNW3LLDizhKO9uDlieciP7o6na9'
    'UaDmsbe0crgawIWFmNplVOrgjpR1ZmOzk8rQypkiAK73RMen3/0R25GJARKPnmJ2mHXcBHyZUzHUsC3c0I4mo7GvJGuxpVWAhJ10'
    'cF7cjlRuAPncns7XBtK6VknBpDREK2X3jAbyXZoXyZjyNdLxZFYQR9bUq4JgH7Xj5VFgADtOZc8tuTecTW3BPjOwKNNpcgklF+VL'
    'jPqYxoO2qU9Ef/Ex047rbNKh9KK+2SVpbJJwBMukM8HpNi5eJUfxbChAIa5+gwPoY8D4BSFCRUPiuwhq/F+TyzsUu6DI/bg3t2Ee'
    'LJQb+HLBnrLU4dENhMmhwSixOQyTcJIMJ8k0n8fgFNkPgElsBmIkdPnA6iKZ4wWEJWrMS4bt+kynjWEb3GUYdVFQvf4OM5wOjpy5'
    'EGAm6b9xUriX1uN/eduyYNNZiOl/1QZ1AfDC1a9CDf4dbFK5nN/BLrXquNvz4KHUzM9FC7ZdrXZB1Fm9BV1wEH3zzGpFBdZb0Pye'
    'hmCf2/xPaD4a/BJBjPNWKMiuiSC7biKzXzlLuPFp1MvO2XVoVgiCSeoAdMBmTtI+kS6LUN50/8yXoF5I9/XVudMsLhhPakfnZx6d'
    'J7XjIn4dT2pH5GcekSetOnzVC7njRhHn3chaChMbpndMsmAwOhMJRfGata16+nv8TRGYjvvAjz/okveg/NrRm+Cl6myWo0d8yxdU'
    '9YPVPL7hX8rvQySz0COX1L4mBzoApMKxYi3EvRYupyBiipKZTnPjFW1r8Nkt3SN8hVHnUduNJsBv2+7jD3Ah6lkQb3SKX5zoC+UP'
    'lD1GT4TdboZ0TuyjExSUS97istaNfZEj6CBxECDG29YA70bkNrHxDKow6MamH+qqEAJds/xGDPTACvc4gDOfdBz4+ZYHBvKolMrB'
    'nm9ZGYVSObzz0lmkThPquga+0bNOLh1OIGSkf5/xoAgjyPR0FYlNMkdQu8HVBkKKnWRZbpy8y/HIMu8qC0wprOGaehFPPKUUdSy8'
    'eonXl1QGpi4EBxQ5uK5GzsWus3eA2vd66Xet61olII0Fgv5wnGRwSOyE00DeFAo2y9+bTFal9JJjfNUOS9QkRolRo5gfbzVKOP38'
    'lgdLT97SfNS0SjAiSw0L4zL5YMxgo31xnzgiWiRc5cTfpWKWjUz94juwuORvzxBDNhpsPXj/3VUsEabizuVN9O67q4k8EgHPD9X8'
    'Zvf97t4Brdv9k2SUHM4J+fa4Lnbzn6PHC8OGVqRN7q+xVgjMRIIeuxt3mRMz5zAFUQxM2nv5aUsNOtyOCRctb7EBMKGXGH8q4MtA'
    'YwbXLaBc2Ug04rUVEw/FtpiD9OgoYVixofAQcmWo65rRDXEE80lrwBDEyCxPCw5xKlAizv60Mx87ug4Y1aJTWj2bLBjqtEEyVfxQ'
    '8M0qL1ZMBSKzNt5x9zvRl1wAKhBzi1i88YwXheheT7JzBnFFDO1G3a42yhACK9y9cGBW5RmNeFeWaURAUN85SIOrd7dGgK++ixJW'
    'MTmqk7Mnsfyw9GOIzPJQwWYqZsJw+GdgKigBkKFkypN0BK2vwy3C2B5okPdDc9/h0zoJ0ksF31rkSSH42bzD+odSGHOBnYzm1WKD'
    'WB66nXCYS3wzs98vDXNboU1vYG6Zw6Evn2SGXsYTsIc0Kzplbwe1gKPjRV3nUIZeg8aFBOICTS6NXe85XRX6FvEYJZoYY9rW1D48'
    'vWVI/NE41cq1jqXhaTAawWJZCLKqyo76WoEaeOifeV6XaaGZGpHsTmC/hqdnLBfspV2NkOwfaCmD8sKgIXMK3OMFrRT7IK+dBate'
    'SmZDS8WxbbB8qh2PW6m/zU75TsZuizlc9Cou1HSutPHNWx0u2aA3VKu6ZQa4xwV0h92PHrP1sX2Xij2LhKj17IJ9Yd0mvkAIMieZ'
    '2/fs1f1EzBDlldiVdbkdcmtPbWnzfkyiii2cJRZXpL3foGy+xpGjcimHpXctJpZSKSSep/Fgvm1i0hl09EnLCR1sQGriaXdDP96a'
    'bSZsCcYr6cRDo+8RJLlhseTi9sYeQ2UwW3FmKvwKsQ33nNJSj6N6epd0dqfy0Lf5w+1b063dMcM9tzEV12Cn7gLSCE7cbhn5NhIW'
    'nGnhkjHFIc40hA64O91oYm7C4FXKoEJsoJq2FT9K/14ethbcjLXFYqVrLt5U8AkaZKys/UEN9LnlttIxSE3NQ3rNfYKFL1VXhUI4'
    'PXWNzHdjZ6zKkVOxY8v4YiLuMn2QlhayDOh/mWVwx7bPNrt9JpQJyiwF3nUwFKKVxGgYIrFiMKc5gwTs7xf8Nr/YdBKwpLv00v2b'
    'TacmUL4AXHu+l/fIgcHpMAWBnhyWL8ue3ofLoLMdsXAK97wBZ3ZyOW1qj/xR8TK6q5nAerXNIXLYdJUTG529QqFJmGQPDU2iJA8C'
    '42lsoQw3AMsnhiP/IHNhoBzrYOk92FuOZ+KMQInDa8A/g7jWKe4hUh9BWjH2NDo462ju2/pxAWG1D9wCE1JRBiOb7POZBqMWykrJ'
    '6Y+JoOjabNCvd8znbp1tbsvTQNFbBBBvelK2IeWdjpBq2VBcG1qibWM1TU0rzEkXiogImWte6PpXm5jfJBwHp3+Fob2Nj61dinqe'
    '6yLaNLvUbeJ1sMvwcpa1jLmRXZh9ZQadilmbrH07uaXzYS6519C6T+bOKkih1QfsgeAq0hHRYf+cLMdFQUJgMnAbpT3w6z0sOLzD'
    'wCe5+1Yvg5P9l0QA0MNEhh8wCOtG+ZRLtJ+8y4YiDQn/CtmGry/LC8BMR+lybnCXy7kFht4Lt/zZBBu+rJXbjgch0TukPz9JJJ27'
    'T6vcQt1JbqQh/Qicxvdxvw0t3jIthmPacvL+FIFYiPOaAG3Xhj6hdDgDNgHBIqhexMGNGcGxD2RublgLWLf//N//7yUpJfoly0Z5'
    'xwve0NebOGQBZyJPo6SIlU3To2sZ/MsgGRbx3+0x5d7922btceRt0rfcfbXFTrZ646X2sJX7LbfST9dxqz+MR0BS4FNITUSSi0lz'
    '2TQQFrOulzvi7Q9T2NXVtcewaRT99kaotWbwqCb/a+7dHqJCc6XmndgMRNXkf83FW11S0PPpelWBDQOtCQxOzhJlyiK5elyJXrFp'
    'gBjKSjgDs7UCU1MCDDnYCtEnmNsYSQjbZ3zp5JMUyDgwKcM+DIGYYyLJplglbuydUAZa+q69Y63l2nh7kA2Ve7KoCgb3sXfZ83Zo'
    'V+LC4rLJLavxDhV4zmVMfBAc9zncfTIFiEoCqEXLHx2VT4MjPjqEj8p/SIsTY57ZKN2Gllk04SgME6E7PF7uOENMYQra0RFMQAMT'
    'Q3bIaUNAOPKZdczya2pz80j5BmuLW7P70WFSYYvnGudgcA46nY4IvxN2dIdB6o6MEQ7Mg8PWoVy1sAP4opGxozfvLt8OgXb0aN4N'
    '/WlyKU73c27nx/GZ5V3nhKarcdId1LnnLrrxZhWVYaM4tE0tuDLDS8gdd25hJOSummMXGjy/MxiYDcAQn8GKbADc1GQ6sciqvbwp'
    'SXgP4iQXHlcnxZj7RM65bYH91jqP6xtn8N0k4ZLkeyggPAYPDime0fiwG+2AweDolXWiHTtrGhf70uiwGKotNO71TCdFT6derXuj'
    'jJjwIWL8jRledZgyKHAs3jfJgB1U4yCmRz8b0TQB+pjvQSXgGs0ax/TQm+sTRK6mE3SSt8Rz1RzLVe/V0KqzPsJNGcZX3CKZeaxZ'
    'Qgf9C8BYQfsOA60dOtuMayQi/TmHU+W6RulgOXbuvXE6Yjo08DTEdp0k8UCczaWGO19BC877I1gaZEXBlyVviJJwIYQhyhutTnZ0'
    'RIvQ3ljDSrPO1pPv9q1lZLPvm2+IRSff8AcploIUrqxLWxYbdPZ9Ew4p63KtnGIpSOH5zkL/AlvSYYa9tg0kV/onvuBz5ySFii6j'
    'VUFvAB5IIt0OHen0Z0kS6a00pVmi1PKswKpZ1INORl29OLZpRPszJX2mBeFfLr+LmqSSHa2KXnQjz8mXRXVuLVtGwAJiBGMCalRL'
    '5XX5esnQZvxVJs1TUVwwM4c97hb30oAN1ZG6sPMDFY4d4PYcV+V/2T95nY0IbnNOtoxZLnoBOAF7PFguygF+W9GRCBqjW9rsG0wz'
    'sMiDtxs6AHu5F3oR39wzHuXQcb9gH0hjqCfRucTugBZ2Tz7iLqw5bnWOzqlVf4YbH441v5S3YsQ7r5zUfL5vfweOsl55YgwC+biu'
    'IP0mDHVTn6moVUCBAaV/g81+q4Uv4CpqrA7rzQsFm1nLoQGeXopFQEaFdHCL2B1nRfNAzH0PW8xOBTd2geQhoJ7ZKNkdqoWwXQpO'
    '+4PvE/h+nMTjwTDJrfMvtS23DQ0vI3Y6tCfyJVOjVVMkfwGx0Am3qFS1ZqahrKtA9OzwiYAFaQ384CiTeyMj1HA5KrnJvswDbEHu'
    'M1bfnfpmmPM4Le7BR+Ib2UCXGyUXZxxmx16j1Yw31RKyuHylBrC7d9k5lLV54jvtDLU5v8xtSqA1h1aA2wC1QdMCR1o9hynucm5x'
    'UsLcjPnd2pGTvPJcRgM/FxSYzS0w4+GdmzG5W0tIyCX+5uOswFUeN0jefPrwl5rCteyVuWWXLuzmN693SxHY9BZkT2/JLrvd/B5s'
    'sTZOH5YWzDZDIK7NLWf5tqzL8/OuNuYLKuzDn8JWSV3LAx8/X39ZCtypO2ApXCfjcAYr1+v+63V+ap4GCm7V5Oh9m5VJ6pqrN8Lm'
    'Yo/VtV0FEjqfyibl0DCbe9A1tKPX6+yKy83hS0aOZ8ZBl9O85ZvC4SNbyJrOAv2y3NZT0bTSfztRsyZgqVRO/Ww0WoxG3/UcufwB'
    'Pb3dKNxeeRphL1CW3mmH9MOb1+d/JQF8vYl6EfdPWVGzgOjCeMD1JeuE61M0f6Ngl5tFXXRG/eH1V2ATpVd+gTnDfEODm9qank+n'
    '2fm75KiYf+SQTI7Q56tz2solfIbgsbCI20r4MlmYndhpu+Jr8+Ou/rYSqgUsWJlzt5ChgVjRieTreb2ulajM4j5Ca2GeHoTOJqzd'
    'P/FZwxpiowHc4kthDUMoqkX2qecoRxVv/H0Od8lRm0nAHDPwjWFo8IROpgizBgUlbpOHav3FisaxABj2Ez4rB/oZ+V0gFg8Qg9b+'
    'floME881EdtBgXfWXtS+sUojqukDZBhrq6svPI+uTlN6f/1Tno1b362k1r1LhXiOYmmjA/HlOof8aY5kqLH7fBlzvQOShvPJkOal'
    '8ZUIAmB84tDkjJNQmo0rtEUyjGla8GWbhRB5JeFThAYF5ZdYZt7uGrzXAhBGUhLHvsyAEfyoykgt/tt3V6Xi1v3Sbrgok0ZbAQ8+'
    'tln85qSXfDg7tvJG002LG9GDf3w9/7ocHS6tHPNQBt5z/I7O15D14zGUaVg2JEVDxkQGYxJgXypMJuILQo0o+Hhi/NtFymitE735'
    'uLcvrCgdWGdpzOS2J8T9SgOMk/QnQUyH8QzYM0DAkqCCAqAJaIhoj2iS5E/+Q/S7EoHtBbUPs2MOU8ph5mnl5zCtRO3rnejlyTQb'
    'pTOsBmhWo71LEnVG0fN+P8nz6Pmnt5JyoxN94mj3kH6GWYxggLwkmKePmq/TaXKUXVgI/KCtXdsmuZFmE0Jg7w+zfixhKGWeMBRA'
    'TUiJJz7v7H16+2r38494aQQ+yv8p5Zu0+5yW9p9GfpKdo3w0Hx/BUlBDpRCTccIf9i8nvCwOrqJBkvenKYe16EYNHW4zjQjSh7DZ'
    'XdrSGpC8U2nnCpZboxsdNHT3aRzilDg0tbx++273x739j593Yb4c0kYXw9XYZLUcfn6K2Y9YNLLn8ZRm/5UZ26pnhrs0PFMDBGy3'
    'A7yBRmMT0ZrOsUnISetM2u1rX8Ungj+tgx3ZekDKZpfRrYE3ODsgHp47My9brEujAlAUrNjGowXIGDkbkLTpe3FrKo6aPZIrjQ/S'
    'zsaYGoCXBUd/JmaGTStRtZj+FmFyetHY5NdhhsY///1/mA/c6y3XUQ2m0BBDNuqi2QCYuyKeoDketYH13ZQx34kOqByNrmStze2A'
    'uArUiADbAA97cZLmdlih5LO0sBN9+zr+7so833xjT9KWWjfLkJlibSvQp6ghKVHanDndmfdFdmSgSbhCGuHm0zDHAFZcS6AeeOUO'
    '94psivsn3GbQptF05N8uW2pdWZpv27rbSr+MVG4hG258E3gqme97xpx84i8ZUUdE1kTBdVZJw19lyCkv3phskt+/jhfvjmD5mN2u'
    '2RtmvTaXW/Y8mEfOsUxd3KHD4GgO5g5KBQfeGbiVL22Poc/uqx0/jcJ+OkoA9iVHWB3uiVREq2x9dXXV09zRZp+yB/S+eOhKCaXp'
    'KTIeZrGnk/Fds1o2W4LNjXvZF9T25kFQerN12HY2dJV9k3VrJWCReJI2J0wVvYyVwVc3ZT9TQRE5Sog6NOlVhBgoGUDwPhFNNtp8'
    'U5BMc96vdcEvY7Nv1LWDDvO/LwuNL+/TGGJHB23T8U4PgE1GWyrGhnjZCuIG/OQwTjoomRgKJmKdJSL6hBjtabe8opi9hKsyjE6m'
    'M7bW6chpDcHzGOcs7RiMhSGMb8OEFmBF4LSTnWIR/9Th8mlN0iF+zrOyixdN/YA0QHuIi1mO+fH9cn/arKK8QEJO9rOmLA1/Hs5t'
    'T+WbUvIPlCG2SG6S4LzDxTQtZbDMZr6xAs5SNROdlihL3F/bvjPGHu/SDeU6PoiKvwrxwxosD3wQL+7gZeXga8w+B87C7B8u+owj'
    'R9BtY4X+Xcnlwv+K95iut83hpr0blRYIw9aYnk+109MO8loVZLXPktCqXoyU8EbnyTgDyhjrJHoJfEicJlFGywLj0EOHeOccWmOc'
    '+w4nB91SlCFm1uRajqiSP4g+yHNDNWrEOZPyPP8t06Lbz+yYTuZC4CrMHk/TQ1KQcFgk/nQQqNKTnHZcyi5z/00+2AzXFp5oMvOO'
    'BqJbZns5znnCbcMWzLUPUz3tiDJiaDwf5lBBzfTrFwUBv20qF+jolIEOOl1PP/JUZa6bXsc/sPzsjQO2ftqFfW77pmWbEzabp34q'
    'vVe1RC+bFryDNVqBOv6GeSA9ir2Npe3qDraU8K2MT4nFJtbJ/NZRdnTWXfANVBTt6zKgwyGW0CpZdJnNpkbKg88XC1YSzb1WnhP6'
    'rzD+YltcWUSiYrdqhArhLiBZZG0YUOOABlGltoioUBCXKtRYN3W/geKsqPZRbXgqotr8hXhwcmj7VS2ieWXI7vcT64hF4BNd5Ttv'
    'Jeta8YdOGqZ/TmDzwETYEq0WqPQkPN0M3sy/tiAgcLBM2XK8Yi3dqMUUc+3lVh/ZNh65M8bm9tMLedyBEVcUDmyJ7QgBBafhEcsw'
    'l6K1UzyewvAmkaTXjf5vxNEBxAUZ4GXE4sXfdj/vvf34YdMvapRSC4nl4IQ1h52vwbekS4RHnBGthewo+pCcJ1MME4+1zjTtEPue'
    'sEZLFWq+gYT5E+NEauqZNBIWOOEah8KEQcpnkwFiSzkjxYZW0I0e7AOITvQoOTQjcZQHJPsguA+Ye1AeDWf5ibnILDnNwhTwk+Ak'
    'eCkEHQl28ML488ipqlaVhhKCuc4ZaAEmsRhbPx8OjTRVg01cI9UFLN8JjcCbbJT43rhCFyQifxQ9mSj9iFWX0R2YSI9KQGZWmqx4'
    'Mrw07nMEIxGsspgLtFjM1lKNVpJXkre+qnYAGirAGpP6JpZ6AW6NK90rg8LXaGwa+0DfpJG3GcY2EM3ZAGaFrJWzCqFw84fgjbsd'
    'KldlDrfti/lnIJCQbNUGnCrkQwe3lwfKuoiO1rNEgRMYiC/uASAF7bwXHjZH4SoOVALHFZVAq7XpbCI90fyoYx42fRFeXn9gYdio'
    'uY46/ItvZpy6wI+wZBWKJGEB7AN9X/nHH9D4rWZnqfXdikZMqIzv/fsja15gtgxa/dSdS6MK2iuwycim16Cpt5WBgsfG6igqHb3L'
    '+OoJCAKN++Xz25fZaJKNoSsYHawh+jydFyd0yk8xVXc4mtuQLiWSePk0trFXVZNaA7mVEPknM+Y6HBXzwubBVvFHuOm6W52aOxq5'
    'ru9GQC8WxGKo5/m6IZNb/dJ9jILMDLPefvaCtsonj2BGSY9Gx/AJumkiLUTo8JbZVPGIMXWfWfLnG8dOZpgoIXfKRWMnIaXMDUe7'
    '0cJgIzWQQJ/nBnVWVTE3osEXffVYu4TtJQUAYSyKdub9RK9uFfZm/WjsdAQdjmLLtHbqhKJdLtxTLbWjU5qvBVzereKJtDeUTrpe'
    '2UZSkXz+yMsA3CKyqGSya0YlEE4C46VFksrKbHw6xoVbkw4GdlK5lnYzH9cy0pxP0DiMX6J80Z9iTwJtTRM+UkvMNW33yThmhy0k'
    '1jGBPcmtDGudvs/TQgQdV3YpQFmo8F+T8TEryrIJx+ANtVsTucrAQUPpGEuEdmw+JNrsI4yNCTk78gDTCMkD5hAyBI2LQSGJROzy'
    'BGdoNmcTNmKmRd/UC1cuqhU6GFfRnia8jmBB+4Oxdewn6VBxkvD1YbTeEutb/+uJ99UT4Rkn/Nuz/Ow4uhgNx/nWg5OimHRXVs7P'
    'zzvnG51serwCveUKpXgQKYLKd1c/3DxQ+FA8vaEnGEi+yC7wKEBkVNlNhIdL9/AD/qHU299dyRjcPEPB21401VpQcwdp3uBlIvb8'
    'lHOJGr1JRz4dc8XWrDhaftoGBSTjylZO2T1dWBkKXd4GOxu7iTj97hQHtI3cuRcfxdOUugWjZeMJg6u8HLBlLFf+7S+0zYwyDokX'
    'H8GAhSv0zaYFfV4pSR6IkpZAdvzkaO5O8OYo1wKc/wCMdBQSAJ2/sW/v3QXunLeaphC6xbVHpHW7NNxbsDQnCcl9Eg+Gg+emwyEj'
    'xFIFCs1TCC5P73jTpmDvLIFF1+a3bZN1N5gLul6Twam+KtMJMHNe9DSZPs553f7gmbhVnVTKbL53aAglmd0FihCn5EJlVPNE3H8q'
    'VfazyeUdK3SHjlJufJYex8DjtE4yqu09wCi8NC+Z9bvyO991baUz5jD0+ATDQK1KJXi7LXoedrn5znrK+CxOh7zZs4ISGktoX/gA'
    'p3IbzukCph/nJ9nQGoDA5cUEXDExXSLFSwMsKmIy8IVZ23gi5HzqjEUT1CNGMCnyNkOKowI6CfqnfPCzMLK2HmUNfteJdl14Hqkp'
    '6tEqHXFQTS3b3IFPcM2udzUW082ZnTfHzoAjNFN4+HVM/7CtQoQbyKkB+jF0ylD0O5H4I/O93wFP0CFf/ZnfMMUoiGyYD/oIyCNj'
    '2tIVrwwWCmRYYPliR46Wpx2nTrSHEDHxsFsKMARRwnYZo4laKsXks54d8ebJeqsTvXbwHHkEv1tqRTpls51c8MbNIPcw4iTF5HDW'
    'zgtuLyoxmRXVimMjdaIHxBTRrvIA7QKYE+238LvhMtjtBmYTMifLPifrWflIgeCUc+tKo0M+P4r2MC7em9jnEu7cYLHsRAcHCHVO'
    '8sUh7pfxO/wmqFby9cDEQ5fQo5xLLp8sHTU/NLOWWKvMrMUPh9BWS0SSqqPmd1f6eNPSi+cQ7037/QIjkwfWBCPP0KgdjYjZBgLn'
    'KDALgsvQfWvp1GY1Qc6+WIJfyLHc0xyzDA/PWaG+0mrP2Z/l8OJhxZhZOJYMHTs1ywVenbjINrseAg2EThQeECpUHLNFXWgSYFK7'
    '/JvGwY3ZmI0HuyLnYc5sGn+68Yqd4TARbB7A9QWXhLpNcKzJAYKtnsH6rRcDSNC6lXgOeH2okjJ4qycDE/WM290YptSYPnh7LURo'
    't8uFcfBPessXTFpns9+xVQLMUqtVFaI9eXnKjJwhVfHAUm0jKDCq4fRO/TZymk7QUsi7pxyoQVu4GjTrlJvlmRcGWCxhC0TcvtJ5'
    '8izqbqrNkhBcuYvk5FozqrTGjzZb16tSj9bLXVqr79K6E348zR3Tu4305ffzpNLHxkfG59D9qtGuabbX6CMJ0JgkeYlQjiyhcCym'
    '+mYfcbPXvJlwmxctGA0j9lwbA4tJdgiho/E9MdaQlsQfO5elI8K+bD1dsVLqRF8gZ7hNv81luBNV1jOH4tRwY6Zom2bTcLyxNpwO'
    'Bf2kkBqCJihFReyIJMESfDBVavh+ZspunhQjHnNptw3bYZtFMsAf/vCHBpFmxSYhYzMmMDyvPr7/BKGAxChRgr2mrXmPLQaa357B'
    'YIBEkDxGNI5f1O0E9bZIHuGP3+isxpCt4C2d2Xjpdo4X7z6+/CvVtPKP5qfrN+vXbzauv7y7/vju+t3ba/72v335uL97/enz7vX+'
    '8xfv6N83u89fXe+/+Pjq3673X3/8uH+9/5leXu+/un7zufXdiheLIO+/FzQx2oJkCMAT0Jw5jqJ58PXrt4c/Hnw9fLZ9fdhixuLr'
    '1+/WfDvT8ynHeEOI4aIVAtBKqdj4DUC+g0j13XIP2lEM90XEqcY1T2HVdk1iZ1rUivzr3uHDnRY/qgLPAeDCoRH/Twf6q2d93FTS'
    'k1Au4oueuzaCjOSgMXD95U2YM7SCUMP9Dl7uG2QkuM929nf/vv/jh4+vdrEAUeLSloyvpv5bJRqD4dEE1F0clW0cg1I19001u+9I'
    'svlgaqqPTMpRITpFfCzmVQx5atVhMhBUdh8mbR+4c76yp1DTfrbI14e9/c8fwUSbfmG+m42HDxtaeLNli7Am4pr1rV/O7vtKGXco'
    'Yq/UlLd/3fXfvNp9Vy71v/23OxT7kkaw4Yw6+gJa2/etBTdNsWZtcKIu/3GQyo1vDdZMffvGCiFOA7b62zfmqL/5L7813BSXG/S8'
    'UQ1mrlZjLDA/L2gB9WYkZjXwGqaUxgxT++px+/K/UvObkp7R/3qJBA/iGnZgYy18H3hAvBMGkI3JbHG4rPp2oCnZPY8JnBPdHGpG'
    'z5q62fqaH4LMqyqSFpUfBjWvoZ33Hs2ZPjQOVAHC8sq3+weotzw++bTf8Gsol/zic03BX8c8X1FEPyoZaR/6cr335QX9/9P1++ef'
    '/0p7kCgoi1alKJ0OtO/Zd1dFaDB+Q4eBJqADoOZz2GotWnNsVuO/8wEd7HUQeLDeHXPYKrsu87ko3LXdBgUxv7wHDlNG4x3KfjGF'
    'y6m/FQ5Ts9GIu9O7t4152xKUcLwRUWEmD8/Gx3cNocB0aemmw3LHMnD3Zj0mbXSAF1QDpJXERVNK6tgw9+WgkQI/CSAPap7b5w6N'
    'iNHHcNyv3cb9/ZXNi2jecdra6bYba8ttLcJlMNeFXnCLb0TrmEyhhdRNl9pl1qh3EozlTB2LhUmvdfOtji3tS6QDbxoMWc5rnt8s'
    'kESzz2PaqiMiSSo+FV/V/tqjKDbv45krExL8CHSsaVoDD2dc/zaKaaN1yGJpwVoxJCymtheHVgYuBq5oDU+UDGVv47ErBv6JdSeN'
    'h72/4HXZMgXij8ff/OP64B9fvx62vl5zEd+tff163SgbehwgE4t2zwHg3XRRBNpRc4naFu4//WwoduzYJNda0TL9wwIujQiNh06A'
    'D1F3HwNZCjTtIgjpCTXM/XAQ1BjOhMHlsTUromU193bIp17buZxll7rcLsu22XaE1VDRzalxwImuwcGUKMffZUwrGtd8OlYz89K+'
    'bgT83AFPOaqF4Nk2mV37TaOXl+GQUy2Nu8vNFp+hNXF+QrFEjnPpnDU+uXKJZVK3+gi7Yw7ZJtK9U1lsqBqIln9bWThS5myWUOVc'
    'ajnNBPTQXskGSrSOL/WXxDwOtZZ1ZI6cpYfqtnEltUtj+rXcKXex2VrIdha+oXkd11mzUvV4/uTxZRcaXsuM1IU3Uhet+dzUm3Wf'
    'SXyzUcNceUXbL+UqzJF+AWbISIV8WJkn2uhdJeAj/iA+FNj3L9h949vDh/j58KHb2Oe12gl0Da8RQpY0F5ZyQbu+u55Qt9P4oR0o'
    'n5uyLeti6C/TuWwxyZG3cMX+0WUiylUHTFll4oq/ydFmWOCvY3rVWDBzX975M/fxnT8S5hxrLOjBm8+NmglsOKMDHhTeOeYVwYK0'
    'X4rYt/dLldrPtNnYOQqO12Ch1DBs+kozQ6dg9aAvsmyYxONwzp1Dh3AZ75SPU7s82l15uXE8ulrygJ53wn57Q2iVw527rOZtHo0K'
    'X+fh74CszxrpeI0GjRp4UI4tVdIYl+OriyYJ4dDHDO4qzww8G2pqJIF8h8bGqX56HkbxMMUSZNyB8MPJuqxN1uZ0jVantIMJLDca'
    'w79ckM1vD9+Z+4LuQ75nlgSeE+o3L+Kf4oJ51Yse0yOoxh/4ROupUU+jhhaD5gd5UeMffmUB6zUlLC7CpY4c6009hzKRz9llL7vN'
    'urKCEBmnekfGs4nAHjNW/8l1jVUBZlMlY0YlNrfZ6dTo90x8EJI2AdYmlzXBjAmbU9PAQCooD8YwDSACcn+74LWhXZOPcu5wV/wh'
    'lF3NW4ZNpU1ehLzRNXRzDHa6+nr5WZPXVadle8VVNOa/cuXVDZ0KWzs70WrrzqRs6WfLlmRRseSbDfn7ZBW86VxCCwa/RFfSDH9d'
    'VmctknGVdaqFlBcq0rUapWK9vccrtTK3C7YjT9kdwb6yOmLYfrD12LY2/KGoat29ndk/ca822jcqMPInjToq9Kaa+j0GKFBjuziP'
    'EO+ozfQBOExcuYrVK9Yds2kMCf6XLDsmKe9V1ofX+A/ZdNCpnAgoyYuxCIU1q07bYtW8FS2vecYeQ2FicXMJRlisSZucEvaKWINc'
    'whIV8WxlmG4/W5kNtxsCJbS8zBaem/fuTNmLThRAHPkKeH/+Wn6w1lsOgmeT7WfptjsNnq2k23QgJHm/WaU1KHgm2/7J4C2m+24n'
    'CtloE4MAVEM5T9YaHMNPLp9O1vGLGM2bAynn0B5h7FPHYB9mUFn7FB9D4yQN5BUlWid5zS0mDpbH4ebbZkl1c+M1WrbVbZ6bVmk2'
    'n0X2XPCnlCbzGc2qTujSkgFTsTuhtNnk3SxTg+SVHOaT1xGzQ+MW28zyt2eD9GzbdOjZCp48F+qbe/5AufWG0k3cJlC+tWKNo84g'
    '61+IwcIvKYem+vv7d+Li04lezIhZi3qXbLgeNWEoDAcoWjXZaDJN8hwmJHKMwUQPPQG0J27QqO29aTxNUQwMz9nIAHW3g5XYnE3Y'
    'nJUW0atpepa0+GB9R3mTj0dHJNt2nA3ty88vf2TWFRxhs1U1G8Ft1Rda7BvrIkqvP5ZIkjZqJpbw6maEGaVv9EPCZrI6RpBPbdJT'
    'SYoYCU/pDxIiST/6EwOArF7svnrx9OnG+mr0D1q80fb2dsQAH/pzMyoOxoecAc+rgR8hrhxbTet63J/2NwCK3bssjAmwadHqxWv9'
    '36a/TVxgnji5tMqOzAE15R8RSXh/og4+PnRte+ocLzmJK7hlG+hxyEQKbMekrl5ssuoNdjLu63DDjmCX1d+CZQycYGai24KtGQ/1'
    'SSL+8H0iDMy967UiFXf27BxqpjfZbArTi2fPorW16Nq8fk+rVgDt6MNj934voUIGeM+j7hA54Y2yxZiV7KtEHNe/JTG01svR2vdP'
    'V7mc76kck+I97QwnfNKsletwDebrNMZUZeq4V3NJjQEr7dhi609j1pGLgqZ6IbWNaw+GF3k78szAdny/ilM1yCdeQl1N2gbpgMZA'
    'QM4xyN6uJGInDmC0NrGpxy1fB6lgxm5SYgbexAOvnhczRLrjzE4uPIM7jCwx6AapzCBQj6XwM91gg1MHeATUpOYG7A0vVh+tbjzq'
    'PTac2NCUvPak+Qj+/TYwmf/lCed8ulr/9SkbJ3jt8T+u4VPKqptqzrV1noyaj9TRtUc80PUl4/tTmUnLB9aUsb5+SxpqxPoTMcYu'
    'pVEgVFpYyksbO/rKhPfNCD+ScVpfXfNGuD93hPvhCM/58rQy9v3S8IaD3y+NbzD4wcdHpcHv+4P7pDr4/nc0tm5ggzSPbkmDwX86'
    'f/D9sh5RT2QLCJPIZqdaRc+oPjIbBh3uG6tqUe/udrxmhdGADK6rlkvn7ow45CYEMEHdh7a5gzPgnTbYAPIuXM7r67KYk3Ah08Q+'
    'WX0MYrGDk4RTLxxBaQCTEgHUJSpVBkqQDalchk52ZXA9C2SB4+h0OrwcWAuuA0Rdt7AcGnpXj8rREFFstiI+WXPv+vZPz7Yf8PVt'
    'X3EsGn8Cksaf4tFkE/ztM34aFvywzQ/H8vCAH36eZfRInGqfwXFKBshgq7i5cKT8JHe6/hH6w48f9iBbqItA3j9JRnHeASdJTRYB'
    'JmeXgXNimibTDFBVdCSMhvAheLICW0QPsejznYvLmK16pQbwUtg0GbKTVw5Uda/U6Wxs7Ge+PTvvTrfpHx7SLuMibj0AE5hMzxJ4'
    'IchIN5kDp2Tb+HfquyPQpMV8HsGMvQ2caDEk3GJIHq1jgjomn6awKWJz9x15Lbbv592zeAi/CP52g2iyoo0mEQBlcdWSm9pu2jLx'
    'WzFKBmnsW15e6XY6TdVzyFuFMJSnQf/M49CUM5e1AQIDX7l4RjKuwLu95ZLRyenbwdvRMXvVtA1X8I0Nkomhv+lwF270elwKUVPO'
    'SvtCjaudGm0t/Zx01SJokObF/taD1Qf864X99c7++oxf29/0/F5CaZMutQSakj77oPQvbh5QZ/nnJcYcKYi+P02jdIC3Y/qONm49'
    'UEKP+J0k7H84+8s0npykfcbcprl5FnePvTfv+FJqnL1kb9Pn+STpF1sP1pB9pTa/31ZblFcqNr9oNk2t/82C1aBDZlaVGl882H5G'
    'v7oTFIsf4zPqGFqOB2qQ9nzVdFsdddFkkwLp0QM/u99wvO8N08nrdDhE2/E7mnYZ1REF0mxzeXGXWEHAAuGncfFAwd6HlaCwci35'
    'RMb84mg6wl/aAKILbvwl/uU6oCWZN9krLutkmhd/SbJRhB9bD6bUlAd4H5+9y7VRJom2SipfMaPpt20lmLBt71kmXiiYtxFL2G5L'
    '8a41TfCcuhVKx+Wnad3mQv96m4Vb5zWLvLqH9J48UmFNvL62Wex8ygctW64344K2fvpWcsnUwwYXhfH0pcSNWW358WvSYnc0Q1fO'
    '29EJBzv4gf990/IkQ451xF/6l+bOnMNrN/E2ehghmsK56lopybaWcCVZvfR9YPLjI2Wgrm5KgXgBbYY1D5CgF3pZGxrLwhqFN7E2'
    'w1aMxcJVNeJwLhBzWasJl/hyQAxQOFP4RbBCvNXx7MlROrsoYSx6lY1WXNuMEoyePFsDeppjY+BF75CBhv9TB3Fb6Q+N9trT9afM'
    '4K5t/HntifMgj4HeTvnX0zHJ3mudx+nYb4uolbdqrmpAdPSZzi0Ex8KiwhXfW85gFUPuGAu2dSXrpiG2pnrutdrGhy+Iy+M587FT'
    'FBSy+IGCf5ok8JYySwKtwgEOVel5lx3qaMNdx15g7Xu+lY0HwIaw0hBTIQMPmzvVNP4adx25u6IMHga/WcOaVzwf1FtHTasCA7C3'
    'ZsxFb0dN2niyiqBhVjev7gNPVaRfQgITlAW2t1qH3sVwatZRjWe0BUP47tBRYetk+1d4iX6/uv7EtPucuCUbT+/5I7TzOB3n97BG'
    'xGlc1bX//O//h+jdjFN4WRMLDYka5X+YjZzpmkv1mXkIMZj0nMQtZwGdLUMtBipdviaSWgwzwWwEl3PjdEJTYGB4k03M9kdpTsXS'
    'g2tcp5K99hoJJngnlwwubHhk68AlGpR+CfsyafgFJQAGHsYekcTIUuQsLWzK8GXj4WVUxKeU/tOHv6z8l0+7f+EgQtQyKqoA9qsE'
    'PYYC1u0mqIE4r1yFI9hjteoiQrGjjh8N6v7YqNBDxbEfJLKNI4BDRIYqeJNVLL1hLbbyDLsWpd560Dz4x4PDpdaDleNWaNlimgps'
    'B/aznWdumI5Krr30Rv166V+TVpAsjJ+uc9P1HA6r5i9YD2LdsvIPt6t8xbaiZnhomLe/hMlos9kpJ+QNSMOzWLWX104ebFZ6l61Y'
    '7uSt6/nqUi/HMVFSPOTQSYHHrvsmIZGcXUzVZTfwkRUXWapHWw7nV4Op4Du/buq48cCUjWHs1JJ4i4GBuMobe9fyE6LDU+7jvFvu'
    'DF+UlDthpQFzx0arC/IKiYwTWhMp9LcKCMOrk3/xahK2mEPjpNMkd+tl+onRiUI3ggvPiUCC5vXZfexCbjSIMXudwYGbDpS8nxLz'
    'TcOZZ8M4f0CvTp6P89Krfu49r2wHJfe8Ynulb6n3LS19y71v0KCeJqUE2Am9NP1siGBcIlSuPn6y8XKt3BScPV6OExryIQ+75rpM'
    'hsPsvJxrxvCz5epmJhME+WFSzgSLYM6WzyaaCyc1drbnVOfYSb+SltYV/REoMD7mKV8y1WdmKgJ+4kL5kSlzvBfM1eK3Yz3M5twv'
    'LrqeExhYF8PkgJJw7LWN1xXDfItNtp64znQFPspv1At2fWUjYqE9ZyINXZb+PhqqrxJV3SpZ4P6HOyL9h7oieaqUXC4kBliRR20B'
    'gGiVzYJDb51b/XXu5rHjuTj4xoyLHXc2vVzOiNNQJatYPk2bRzS8v00p5LUoON/cjvlb/YTmmGyepszA+laaoWXkXZyDMI9NlITt'
    'u9Pp0ET2jGGEmVNX6p39hWqKTe9e7JeFBc3uXtCvcUaqqSn/FTV9CYf5y6eFJR+U/EgO714T3FkWlo0t/u7FqWPV/OJwLN69ON9X'
    'p2EUeT1WHeGhMT/n80awIE9ogUw5cvu0K2o5FRua9e5VLYaOqWm/hBMK28+r19bgr996r6bqjiP8qmGBEDKz1qupsuukI9tLT0lD'
    'TBAzTBCFO8wtoe1GpBeJHgK9lQbxksTD7x+vP9Y+0dOTjcfAinvy+M+Q9Vt1G5DvpOSN1VF5Ym/C+081gi3dgH5i/3i4OpXVUqyP'
    'Mqruin7K6rg5r6+OqvOJGiST0rmiIs5s9HYw1z/JSXwsoK/RCA7Phn4IyKd8Olv7Q6lm825H1wI3q1/haPW/ygHKehp+ajINsEf4'
    'FS0O1QoseyqJJoYNZoDVWwsA0xEDE7OWk7XjXZqTT7ziebAtf4enG5vi7cB94UdRy5rc37x2/mseVdpLY4XOMxxYmt6Jyo03FRMj'
    'eMcaWryTX1Uo8MLjCJdR7EhlvYTWvDV+m6NSmxZ8q2QTXfY6WnOuNQu8usxtLJFBISbpiDmLqpoFYgqvtmrqsRhjR8Msmzabjnh4'
    'jFa4LbCtFDFNjoM/5iWZgR7zX7YePOIfwm+tsjgFUWbrwYvX+M9JFlahyoXymDcKDrneQLX4K4Fo8WvK4bqA58TWym/cz781xMuN'
    'vYakLMszNv4I/IbEukk1ajYFLIaiN9yWP0Ly9OMHavg5XzVgeB7yCNygN9Cjbj0YXMSskmQBZMcU8pb1qZwNHyrpdbf8ZhfFksn5'
    'QgaBStThEKbUfZBk7+JLtNqUepReJANZjPTxJcl772PuADeLW/J0tdwInOQqJtZ/XwlLWzEDU9Psv0zTAbUZT8f082U29IeNBT1j'
    'mcwkZHrF+b7V7MYFx9IGkde4ZCeK0N0RKDLeNYPzgqUe5t0q64IVek294ihl8gUKEMYsZ+UigMdoEPLg5AhbO+DI39Pas8O/eLUb'
    'gVuI6gyIuozlOYdUb0W9aRKf+swGt2cJRoBVaemEN55Kj4KU3AnlxYo+U0tfCb1fpvNxDZGPNbSYmeY97Hdu3w/uutlYl5UcJ/Zs'
    '4Bjp3k4AuGI84s5w68HrdfyHfUHKYBLpB/QmNKdHXOCPCjxFqvDKSTpUCM4/0x0Y1T2B/Umj7mYB9wpimS61+kztTTjjmzINz3ji'
    '5IEtL+88uDe1C03TTsyjz8B6LHQBxosXgIxuMbU71RtGYNX8eN0wc8Ftk/H0BNvqSWn7T9tggwea3VTmD1jN0WodOJuC6wQTlKTm'
    'eOWdaYvZNetgzmlpsjaerBoOeCsKzqDSiRHjDJJcMhyTFwN/36s5ldbWvWPpqUeMz5/gP50OLqcROBTZizS+0bG7fenqjHf78K6s'
    'ZFuiYCDb+mOHRln5bXSH/VlaQW6fb21XPF7n+bwaQASqVJYLZ2zb0bpywruuFJEW6l1ff4Xz6+/g/lqSr25lkqksX1NkUG5CJ9o7'
    'qnNKjrW1eppalYynHHCD3g+2qNvHfq7MutCZ1hGn4MzUVI115nnPXnHFi9RCKtqiRNuvUiGWcKtyhKpUv7uyB95GO+jLTrROLdhg'
    '/DsUy/GnJSg8XzbzJe/Ntxa769BoSkPmir8LHHjRcOMaaqbAFxjmOuDOHd7bfHErfp+wh00FDTDVjaqsQ7FB33zF5VWgqLmTFnNY'
    '0mJWOd5AVgx2nt96WsuedZe5qXcs9gW61UVrwNNDuaPJbPkiI9Rv+k+8PX+tThTx9vxybxZ4JqMh6pesYuRmrVamRH4VWbW058wR'
    'Xaueyma4boJr5PzjkbGBuF92wWL/t5INyD0JsmFvOcqOdfaOpWoWYq9YPHdDD+Xwacu/amFkNyLjewJjdGt9q20PNs8Vg8UAOx7a'
    'L+ocjNciB9DnGTAEY1JyKeNBCWyv6jiep2J78i8b0DiV2T0nQnGVysqlLJoF936Pv8d/SqeG46vfCZxjXBRsBHMq+63V2A2n3ufO'
    'VexpAsHIaHRB4W5+lVchTmA28Gn2WhVXvsAv1uzcXJc5jhv7CmQZOrRWTJ+tD/XzIQcOjiO5S3XGH/C7ozMkhy90NJkyJPg5g9Mw'
    '1Dabjx0hGgAb3ExgH+YBhasBTqfEX0zGx553mJjphQGNDG7zlSDHd0F+ogvxsLq7Bj+Rm9KlQ/am1erEnnV9q8LaDCoONlRVp8fJ'
    'jXUZkKEltmN0kg0HuRpEXdBKh+2LLdEOuRqGTeBk3hAgbKf+HpxBCWYN6uFl5L9Zh5j2+M8ba49hsP/k0So8OuZJbuuPVkWX8VPf'
    'Hlyw4pt6AorbaU37POM9WO4tmU1CHnQXtYQWzXXKLFquyAAsgEEeQHbKCa0x5dVCIgTp1jmdDUwk3wKtbIPN0r/N18yW92Lsw3Wa'
    '2rVaFe1vGSHPGF3NYFiftkNbhIkARNV1Vh8IDB11c+vBl/3XyyR+IfTTIB5m4wR2CvmDne17sBI3xXCQAhGd4Y1AorO8meLNZ//N'
    '+eQ32FKHfguv5KMpMf4NBcLlweSnNfAvmXeDpWF7AfwB7weAbdUSHO/9IiqFtbXvV5m7OaHfT55uPJWJnhy/j7GtFxkNy9qjR6zc'
    'm0oAB/MoDJN7ltPLPMlq33rw51UWko+I3fAej2eFVQOAhkzTVrTRbBGtk+hbJR9lEgG6zhYnhjtu6pviuDdJnBfP8zQOXrJ5jj6q'
    'Nln18GLE8a/RoBZSocBtoU8NwZPrWaqP29Z4BT3lSfvFrLf1dZmb/JeXefndMOY9jd8l4+W/vPAP4ZVyDZPy0zyGBbOaolvrTx6Z'
    'h8+zYaLMvPK9Wodf6krYRzseVnM1sZdE9Gog6ZS35oRvB1sPPoDKhzxg7Eqi/dPX3O+fX/NKUCJCxtvqsqXzeV4pXN5y2cDYHnwc'
    '11U7hg3cwubMH1Y9cFZsCmWU3EQ/rploeefN6K/rrDlFKv01CP5rv2efEY3sA6yQwgGQWFVbDzbWmbICo2xKqNzbO3cW1Q9Ur8rf'
    'rr3eeEoUuhKO40bNOG78LuO4Pncc1/8Tx5H2+wcl+aJ2GNfuOozrrx8/+v5JeRjXn9TsO09+j2HcmDuMG/+Jw7j2xB/GJ3OHcf2u'
    'w/hoFf9VhvFRzTA++peGMbxtL48lvkaly/gFA3qXvcv0qi9mxLN4uCdJwpPA9ML8zP0jnMMv8SXtP//9f0Dg++f/9T/5z//5/zU8'
    'h4CjkaAsNAZJP6VG8nUujKPeJWAd7OPnbBSP/Yya/p14O2xFnscSXIsgs3ej76GybP5o1GrghoUHBivM5glyULP3SbCOmN99PSo8'
    'S1Vq6UEa/THaOFQ2mcrY98jzj1QcFBo3Hfv5v1hhA1zTA3/QQ1WAunyknocH3//AkZB5kI0nq6VzmIov6+3Mlcl/zpCIv0ntUHx3'
    'xdNfGa7/JeNh3WD+RU7PlVPL7MU9hJfuFx9m0C56T2/ZvxJJOHIHUyzfUpjN8JI408F7fOOpU0MBTCKrSLyiAv3MwgrXfm2FwXpa'
    'WO+Y6xv79QSVl4/1sZff96qByjsdGCIMSiUqHNzML3mNW/wryPsjTfgUqpV6Mvc+Byepl9MnrRvbK/dO+9fQT0IovrAxlTX52wnw'
    's+/ZXgrLt0BupI37FF4dVe946r9fZoSBn74d8AVN/iDa5xNJxeeV3LzlyLhbD+QZjmUYq7pyaMbKhdiBceUEPmo8reIvDuIYyQxW'
    'Cqc0HXYqLhXP7iuuaC5oBYmNS7M/hwqp5QA3aysa1lZkzUddZe5mpSMo++bT+2xAOXcv6DAb8xkcElIwq4EInIpsesCUJZ7zCPul'
    '90k/okX5IUatYaKE/nba4sJ+I031pUHLHNSdaEqlwQhdHktDQPsPIm25DKUfzv1sPCjVsqw1dAKCXVJqq6kBX+ZXMD/fBLQY5LM+'
    'UHNywP+rNgt/oDx2MyGerPjATvWsQFqxvl+LG1szGgJ0YfOXYTQ69gv0SmaU5rbDW7q/ayuk3FurD1f879oCW/SiRjDcQzbJiXCn'
    'ya9vg6FM5F52nmmmxhVeStvf6BgKF+6PWAQrIOj8d1iw/1mHwVp56wsxV9z+V6XwOcfCuinxX2ntyigpYozhSmkaXIOq04zZKW23'
    'lVmq5Pod5qo/6aK0T7aRyj/2J796EOZ3W4ocOFXyZDYdiuK4v5KIm2m+stZZW3Fp6Uga5bUZ+ItNeZGncwIAr638/f27PW78cjpG'
    '5/vQtQ36Xb5kc9d/LhAcDj37HSnZEzabbodRoTmR+fRM2yovkkFELTKmcfrlh42Xr/Zf48LRAfN1iuzt3kd1q2tpgAFAInzfuvmv'
    'qCAolKijMlM1FFIhdEsh9jaiNovbdW0G40RYlzzYJW0OJ4LUZpI9xm9cuN8wD8o5D0v3qhKKDwxTS6GvPMAeU7wwVDB9GHUcbluX'
    'njwsHzU/KMEuNn6nE06A1euj8n5ULPQ7BMq1ugcN561aIBJuTXDlINQEwttYCHXAYXEgb75uteBYKAYPn9K+F/PYGDFYxC8fsN3C'
    'fHUjH6Adpgbs3DlSDGO2+uE3DF5s4NArMem9mMKYJCqzjX/mBRX+3cfLhR8OMOd5wNytOZy60/6JRk8MIvWa2Jv5bHqWniUWBLmC'
    'ekyEK7DHUuRviXZs76I9R9qaiRIcZW+mvOTAjy4VIxNUN+EMvV8px06oKcgFW7bhll9KqGWESsaAJHOHwxra+mDjt44Ox0/1ybJc'
    'v9LJ/JDPBuL8Nwd+1tpN8GdLpaBZrf3jhI/tIJIt4/3OI0iP9tBGb3l+zs4p0Uk6GDAQtvkCN2v/PeLfXgQxdRmP+H0ynmkryvun'
    '3b6qXkAdej9rtFq0V9oKYKFUZ96yoJiDeJrGyydxPskms8khCuwBhMFzFOIUtCHSekoGUJ+ypYfsm7T00PwcIMjHEvUaBhri3pEM'
    'jhN2T1Bg/6LIxpvR+UkiiAtFlg1h/4fAfXnUjImgptPsPDpPx7RHtWBYHxdEAmPUwqF9iQkCBCLnZktoKTzK6cBNxox2QkcyMecp'
    'TLT7p0LXZ2ly7sGZQ6n/cbzHWZoYRBl6/BKBozNVSIyGr2xh8DpKQqzgC6BD0S5C5EiDymHlW221r6FkT02MDIRZokY+00+tujq+'
    'fXelyZY12c3kgoV2a/431cRquM1oFzb1/ELlYdnPtBRUQVv4YLB7xjj3tAkgyFxjmsCqhibZWHP/Wors0spsHghFHrZATuF4Y0H6'
    '4UaK7Jg2HV4CvYLBxS3sEYoD+DZ+K7+phMWXCgqOBaLy8AvHwAejkjq45lEwlL20N5SgE8QiiNaWB01auWlwwWUdbhpacMtWs5lp'
    '1Ue0NUefGtxvZmKQj1F9qkQmEDJo2eLVpcylqYRXmR306oRNshQ2R3yoM8TptkaZuA/PJAguHe5cXux0dIqWseAwM36veVbuKTKT'
    '/E/tz1aIJ5ueRiNgWnkfLfL4/pvd97s/7u1//Azs8UbOTPfyQJjuLpuMNbwJp97v412TWIkp/QX7qVuXLETi6zgBXmLIbefND51V'
    'ZhGptE7hp+YFo8W2FOJnmPXj4R6RKaRsysHHtddsNs1zp82Nbu49bgZt4LyCcGzDiYI6bQxyMS4NQRoRjmqUZRpYLMjPkomeCyfZ'
    'KCm/Lxe3d56iIQwGhxnA0HP57oOdEnsU+QX7Da7viQ39jWy7QyV2IMMBmu4NvWy2LAIZiQhjOmpz2gyA5yKbN0pk5nw8kOiUN/cY'
    'zOk9WPpmozmZJkck2S7zBecyi6PEo6DdtCvUEHKfES4tDavVJjhS+L0AG2lTp9O8C6b1uDqt5Tnl/nLmlqPCpGMAz3bMDHgGjnzS'
    'mYHwep9fUrNH0WxMokgeXWazxhnDtMEAlg6pezWLCdkQT4Q3ia6UwrtnwqGqTzkkDh9sSDTU6+wiC1OKcVxpHdq1hayirfBYcMoL'
    '09zovowiHLtpJYnx7IF+PLSYgFfRKR2/PATjU8T26P3UrUkPB2gx0elG795+2P3x1e7r51/e7e9xOh8tjXEgOeCsrf4D2uSLdhz1'
    '6X6af87o8Mhb7KiizShoB0WAdHZHyLU9eYcH6fqaXVjmtQRZ2c+FiceCHrMl/L5gUY1ZTf/Pf/9/vruSaGHMuo7ZJboxG/MCBd6V'
    'FfQ3Vls3//z3//fbZshSYmI9Ns7ZDfszYlaqe4c9wDl04KiBc1cDpTU4FPcpe32JxTdNhxrMf+P5NNh6313ZHjU/NIsOjRBfYbVa'
    'NywC1X0vspaErfrGJElU5qcq2C6+JXC7psXKzIbtLYwRe0M4AY7PzhQKnp5XdC1NpwWTO3H9xKTF40tJQG/QzU7ZRBtM4WLWg1uI'
    'CYhofz/G2VZmgamMmnzCPjSswXevM0hziBQDngw1TKUTNM5zbFUdYVeajQyn7X2aLiJcGdMD1GCOJOjRDhFLiU4ppc7q9xbPbM++'
    'PLMmrWbMX0zjcf/EFyHoFGeaYBwIXhv+HH1OciaqSidMglfU+VAmCQpkIvPTv0O059uS3wSHOwiqif61I5aablsRvCsXZv+RfWM0'
    'Sr2vlWXgoxA6ycwbah3eAfc2kunhd5vCVXtvqEVW2xBIuUEYU4Z/kWXBW087ktxdyWwcZe7YIJSg7bHZPvZ+IrLsnCaXuYQqtZGu'
    'vGp1+LQXtnv2+6aNJOUO5fBwyISkmneZlSqtzZslb7Gl7JCez3rIoDsJWGITdM1rbYsOAvrSmTPGNKhBP13izfmdhJuIkOB/CN15'
    'HT1FPw8aLHhBKGbZFT/YnxE/mPNplOnw1ECr4/NsCim4K8Iq74u5xGdv5EYCrJ/loPP/0k6JwmhnqmHIsDk7mcLspVtRWbBw26ig'
    'CPRadh8o73ntcLurEzqoZ/GIj4kTILSzFDGP3+G0ier37651lBj2Vk+DMhqMLXKxAE8zHU9mhTD3lFCOBAE8iBrSjsYmf9ENIHIX'
    'FPKenTXhwyL4JZy3OCH5VjvZMEUbsaCxC8kOZCHltyMEa8DBikuRYSd6l0DVlRZRMpoUl/jCVnypLyDj/pYWZRJL6ALueklhpC85'
    'T5MaoO09ooHITeOFAXWBfgYZr1nmj30LAww3vYf46zzvMSXI4C+2yBRhdFZ+0B07jLXYeyaMumXK1ldXrQ/JBWUZZWc86qXO2sZK'
    'i7iNdHyf8QaH+yQdeUFqdp+8myZeB7pLyG7filxGOkrCLct+2nQL1o+C5jfj/pnhzDlHWNXt5QFeHCTVdNDUGIzqsqYTJlAWSGs6'
    'eZFNcEsVH/ONStPzdEtwKikqHyiyYdZV04vxYvvjp8778SRxyVWaQvta8xvYG86mVgHlV9QyUdp8qUp1iOEGAQpllfF+OkqmgbYJ'
    'euRRflw+HbAV8EdsYkWJy+VDGZnwyfGC1PRmA+OupoHwWkaF2YxYaFs7MtkHloUKk0i66BeptKulMmWvevFa8nPIqi9xrrAhz+eP'
    'H/d/fP323Tv2cfv0/N3u/v4uMRXojaRN8pI6wC+CLZX6YqkkW3jETdl6IKke8G3ccp+tL28eyO3i1gMcVseMkN+V90ySmmj72YoU'
    'FVpOllp0x9Om75825tzoK3I/nzLcEY5UHmgVIZPtC2kEjEBZGN1RWdSiL/MQMVN/nGSjg5xYl0NsCCPaQOFWmLecescy0x67bYTt'
    'LSftNu/nKKGZ5u9j4O/wzoJtmTZX4wqM5bLmFc0Arbj0qxc8xAlukoybXh4aimE8yUsNksrvnwIaiQRa6ZHNw8DopfR1BYbrId/p'
    '9PUbo8HssvaSxUCbx5byZTzISlUQ5WR7BVGRF9yJ035OKmmnSTXtr7je6AjRybXGXDGOZ9xxJn2ej7zDDFw9g3vQ+MPRCzrLOZjy'
    '0dsiJvKV33uI8CBm5pQkPT42v/dOsBnyT4QikV8iseFn+nwwALP4HbO5tTMiNbbm9+Md+vGuc3QebW9Ff9ZTkXNqC2/Pm3JCl1Fa'
    'bW/AMPc5XskpaZNxj4JUAGsIE3EPa7SpAhLOGBTNnONVcAj7z3L0//Pf/ydTVqTO0ni2zUv3cFsRDBe//sz7aJmybSwMP6vXZPqK'
    'l9zq97bZ+e5ocuIu4IWzgxoZLGbeId7rJM5TO0n563iQzE9+RF9t0uezIpufFJ5y+6nAMHNyDkfsNTlIDb7eNeIHVvHXp4T6350p'
    'GUdvQtyD5KwdHY35TBIirOzSmsLbaMfJ+a9gvxluQsCngUvv2BtiPD4lfKdmv1KTwQkO4/EpHnPm2FcD2QfO7vKtIPpLmthxEUkW'
    '8HyZYYX06vhDcm6lCdwUvyymw6X/Cp75GMwCAOCHrLtlWUwuN0GbtBcnLNaZA8r1mNJICuzEfhIOk2s+4jra/wgFdPDxeV7+/Dy3'
    'CV4CScf/LjwDzQx/afZncKy3yXHC+KkpHV6Z70bY8VIEIpQt57VoXau14kPT1ac3a6Uq9a1NpQdlUCvW555qtW1CULufrKBn16a0'
    'qDbJXMERJTQcQdzYTHz6eLlw9NiPfNwErfI+ih0MJGU/CbMn3p1l0qEZAP6BqBbcyBiNcCXz1aLsmyVtst+Vd6KQLw0Aexvgk5sV'
    'T3PoJffVP35KewK5UVDp3U9VnUIb+MS/RAznNWy/0thvHlGZkCArv/n04S9uuWSTgIBglOR/3/XNuqpF6YeguJrEnqmTSepZiyCh'
    'ucuqmptQhjobFFej8k+VkZYhMt+9NWhePReeYuH84Op5ODQ5SHzpMT0kHCfkplIk9o781xfKzG1YorCIv6WJ5grOlfWZiu9l57cT'
    'o6QLqVBuQufuI3JdLc2QC0J3HR3c0coNIRgTfhXUIdx7pQ6Pa6cSuKl62lExODP0yZRjGUy7HTIJ4K1N4jjPMNFbw8ZJMo8pDdsk'
    '9h6IiO5qtTxrbVIvpeVow7tbscBsjmVcx8ovepKccCXEZSEOGvEICWIfuWINd7y4VOYv715oZZtT/UJQalW929MpSO04q31MIzed'
    'R0M8Le+YNbyuZuZ6K/UyBzo6hi0rM+X0zU28+VAZAyMXH/kdZ3vYg1XcbYRjwQZMYjgJ3t6Te1l0FoSVHDAtRz75CmN86/gbZrk8'
    'BUHflQ+/ZdjNyDF7HjztcXgrjTZVcAwk+YvOvR0kccOvTvjp6qjV6PadDlvNaqMj4mx+wSaqWi1R0rN2rsgG8WUjj4BmROVC1Nxk'
    'e0y562QLpXEEZQeC4bG50ngglitVbj5QoEvlIVNrErJy33aNhZBagrBMdJ1UUldbfV2OAESCuXtdEGluqceVzYLJ3cuGrFJDYrf1'
    'QCSlu1fDwtPCelA20cNfQQ+nyaVYoeYnxDT0ZwCTyaanuLQQxfssNxcYqp/s3Fugo1B4K1GbtQ3alWjc7aNeP3Ro5ezG/ZMmEOWg'
    'Qq0Kab0QivnFl/39jx/4zBplszyZTfjUsgOjbGRZK9nrQA8L2YI6Dlr/zNv/xx7DsE011USENmLNqXxmvqlsGOZfMpxXq9XJJEMz'
    'Pzuu3vVodLt4TFuTew19MvpoTAn68Zixv6IpjLwlj4kg146gSWh1Ij47aYUmUSzwaZM4h3qqOJlms+OTUvw5MY6mcmOY9HCACDY2'
    'nSa9WWpQxtQNUaxa8/4UiiTqXdQREzf2atCPJG1CdGQlODW3UUT5aIZzGNXQtiBxp3LI2CiRxn4wBOI8nTdgmQtXWfP8BL2k3ZEI'
    'iTL0kn4Mq2a2oohnYNam0fNPb2EYOU1olKDeQC1qe5vmDPxGI6L6EhkUDp07oPGIc4nT9uXzu5wNZsUrlMSIS5Dc0TIaEuP47DgT'
    'Px7qTzxNomAZi35SNZG7wesXGQlxNNdQwvOL19lULbg0vVGFe69e8rosWAmiQHL8/jObkKj9l98a8FEWdPi+a6A16pS0Hz7u7/64'
    '//wve3zBLPZs8XG0vC3Qpnz7Qt2ITWxNNjKlFGyesho1Z2PsQF09BxxR5BxuEZennzgeyIvP8of/lbBI/PMt/7v7nv98ka8mzdu/'
    '7vLPV7vv5NUXzf5FykRsHv6BqDr849Nn/ku1vlnrMoob0f86f3qzIX8e4f0G3j+2v56YX1+koo/y5500zsHW8uNzafd7af+bz1oh'
    'g4/yK4a4l18I7iW/EOBLfn3WRPJHEr56+zdqAvb9vU/PPzCs5uuPH/bx496NmapXnz9+MlO18o+mLJlrvnO4To8Q3vpa/s3YVOKa'
    'Sfq6oJNuGBfJ9TgzOc6Or2n5nFxj57zmu4lreLld4w7/Gjgm12A/rnlHvZZd91p222uwFrRc4uszWuHZdTwbpNm1RFJsfbeS+jcM'
    '1VBq/j0Dx5q8PS4bPAIYlQ8FbJswbXgQ1elt0dlUhccY3fMurgfpmY9dcR4PT7FwsF9AWvAQ0v2Qn7D2JQ4YqWrBtiUeJ6OnLgqu'
    'RhV06DygY0L0VaVGwtwMeVxRDKTdYu1gOfRmtcq5AN+WlgTje+zFaZgbNBT7wlbkJ+0U2Rdqu0bVakfTGV/y2j3lgNIdBlE6kQK9'
    'xiArDD2NcNAZ2YRm49MxIvXQiMsWM8FZFR/rTmNCQ3tlc/NMaKtKYAoOfavDUxfQyoQflqvzEEb8Pq02+GLmO11aOOmwyLqtlVRG'
    'jpEHbulRCekyaCwiXvHtdhgGFfCc13Bvvz5Oj67Pk96ktYmV+eRR+yBe/mV1+fulla2v+eHSd6YhNT3jmFjasXmTyifWnJWBhQfL'
    'QJ5VNDbnZQlWid91MSFhZLUAwTWcEQRwyqsjL6artXNi4OI3q1mnCUvA4wxqATorxxlbU09x+b45f6Rb1ZIwSLVtCCOKBUXtSwQT'
    '9/wmNH2KRTY2AYQQHCc755+HVdKEPQdvfG/HdbOIiK5rqyWKPONwH2yA8Yy+rlb7FbejswrGammvURtj/M+jXvv2xthJ8EeOOUsb'
    'qW+WTI++xby5MSHBSrhNtR++byIh823vyjPEIr9mdO7rk2nra8+SsImXTGOrv519y7ODf2wfPty+/tO4l0822dTFxQRnCzxs4u78'
    'cfoijjnN9wAkyMNmJ/CmWHgfU2GbfCsZuXFJWTpl6xLl5ThsdWCCpt6ZXDcNgfKEnTTXK2NUiOEwxGESGAsjPxJodbkyC8j6PLVC'
    'wo6vJedNLYs/m0tpz9AkwvWOSFts1aIWFiR3cbF801RKQQKVVDlVe9yyv55R2l2Vb7TmjKixcCoxw2UzPiNdMsAx89rZuNb4v5nH'
    'Z0a+hNSRFo0cxtV4CV52PJDzg22SVJneCW0jPthmetd2932zAs9Uy4TelrarYQOMCj7Y10zTzZKZvzxu2X5ToQEdGScAF6TI1hI4'
    'C9j85nZThQjG3C6ZJoxp865a8n9RS34dwUZrjsV6niQ8dCLehJbNpRUwf/ZlhtNB2Alk2cHbrp38Bf3e8bvtZbFLy7tDR5fro6vb'
    'YC4mWz9cj5q5AQJlpYA4dtocFaEsGBFJwmoEhEW8Cg2gnKBHKyyQ+jxVgxu/dvQI5goRL4Mf4ETs1gFRt5GO2Z8TH2TOOtE+/ZYo'
    'y+ptgEiK0B2cpTnCuue8QnDrRyJuMvGWgT93wrnfrfl3mL0q1cryCo2N+SgBp79Vnr7yJEPOFp2nOXoAo5BxdHQu4Qa0xb+6nvpb'
    '6zXkEOjGxfdgzBrVcKXfD6c+tEOskIUYkKrhPNAFXqXT4tIdCmPV2Y7NgUnPoY2kfqvZDfc9A2CayF6CTU8PzAFE80Emd+18Kd/q'
    'gkXBZf5sLB5ixN+Jqz/NfMxWO/BO51ceJUFIIxrxKKNqjXB34hY/tfJOH8FucSX6bNwdz9lhndUJs2kO/M9YlDHGnBFNgJWmgBiw'
    'oom9y6Y5upNMCxO1XvxheUg6i9xEc3PAlfR+oWlceBKaOSQuBXnYfsw/31VTlDc5ZC2fmc+L5mqrA3rJxs/HfeJ6sulLVShNWY4I'
    'tDqVjIC5see9PahgyZeLqWtg5Tfl8mXVaC7uUA1/Yc8wqbquF+7zwg7MHa0or2MucsdPuArKqAT48nI0aPZHA/WaicxFTXg413NV'
    'bgHXjEjgQptcJH0sX6Kqprgu/JAWJy/39oyvo3V5nJeLm6hJxb/HHRfmLKiZOss8C/nimx5fsgVu2zFoSAp8ZXOYiprFp4B+TH3n'
    'qB0VM88qLYtCciCE55H0ToUO2ajCTrt3/hoVhBDQbdoPrYwTuoCRnoDhiqrQ4iBpcWicQeI5MFZ5OB3fMnjErWaRXOMytps8OhAr'
    '39Hg0DnCceg3Jw6o5y2/CYtVutgrgI/kmVCOBmX324WOdNm4FM+hx1oqf353nL/JyXo7OtloS0Qi9ltsR5Np4uwCx5zHM4BDcTv4'
    '19PteHJ9xOrJGlQbR658XZoL+pBPa/9/bd+23caRZfmur0ix3AOgBIGUy1Xdi6TIkWTZVpVK0hLp0rhltZUgkmQ2QSQKCfBSas5j'
    'rXnoh5meh55/mA/o9+4/8ZfM2fuciIzIC0jVdK1liwAyMu5x4lz3EWGv9FnxgiU4pvpMS1M8YvoN3VolTp35PW5y0m2CUZniJCnE'
    'ighAE7XTHg/C+ayAXFZTBUNByYQYPQRSYmEX9MxaXThZfAD1GXFT1Q8c3pciCxPPdCQfbjZCR27ikc73dscAyJ3v9eLgK6F06on0'
    'mVTLnL1VUule9bQn3zqVW9RgbW9u9txRXy3AWs0Xxfl8iUwmszN0UCgkDIPWWMWcoTQYJLzEDCmuurCjWiVQzSo92m0aNCktC6xv'
    '4ouwdUfT1US2Uu+/apTJ/fhXNAljndZDvjzozANUtYbUozs1gRZzb940jeX/uJtSeYj1zsoj9vYGmGf+y+5muqdKCU3UQt7NE2sV'
    '0c01DeWjDcGVfqL9SPlHt8aavmsxXQPtay/OxoQQt8eqm8J+ZVrSj7tffJJfbmxj2hef+PdXGEWVgNSIb2Mm2Nu93SXsBsiDV1zC'
    'H4iYqvrb7tIU9PpoQszX6rMUsxQkVlN1UD7WqBvyonZv9OUE2DcwrzkxDeXDAimlWL/98NhH8BtpeLNahhwmfBOsOspLoUlgubAm'
    'gluK+WstC3mUxhhJ0q5eH/fZ5jBMVs7a1+Urr68vAiZri7vGjoFqdio7BY54Tpdg+bMbpkB2kQJJjvS4i3X2h6pyWcDBnUqOF15t'
    '2r89EfS+zvlo+bSY5HTTUc0qfjMTCOylvIGi2uAnj/35lLkG+othcpfG+vXW4Icvq80hUe9IppJtQRSrPHV99HN9kWQb+EUKI02D'
    'LNlBtE7HrN2h6zhqRKUDBFhy9BlrIUsczdXRMKk2w3ts4wfJow9+9DuGLdY6WhFKw125XFThhGtfun2W4i7JwkQVt5wOqVXPOXVt'
    'LYerIhQD21FhlTWWHKFz7jJuiofqXTKMXoLfR+cLFK3oa+78Jzs0RnSc6a7Hgv0qZcza0i2xi4b7VEzovXO0XEx/l11jxrIRjL7y'
    'ZZic8Zm8HDN9lS9YM2Lxk7wgHCWaN8RmxhtE8Quun+ooo9vK7w/0SO72ltjJ9qpDzXJ7VWdmpLpj7zLNbIvZ2LeoAlIZfLylibPO'
    'JjyHV3s/GOZhOqbFr+Num+bK77bV7riKqOu9YrVEQksSB83Q2fOqgO6tEvvc+42Stsavp9VdmtKI076TOjuuiHVEIO2nRGsfJr2f'
    'GLsSmvGGdTPe+iEQmjEcQkvTTXB3uYjRfYeUiNSK++ojirG8/zD4gG8I9T6mJ+YascRbdgjf6gSIBvsUSUYN3WatL2Dg8bcf+jO4'
    'htSNosaY8ccm56mloOXHFK1tRCExB+ZP2T3hk0V6IvRz4ea8JSr6lveLeXPL1VYGEvIh8mbKRvj/XZj7bSuz075TumK8LQtoUUa3'
    'Nw7vm6LMUQ4eK28AM7dvO0tK/Debc/n4A7jAbrOddVUawOmBDW95gDHhl1FxfCzfld+svjva6tSEixq1ibvJUr6Pg/jVdUXbB8MO'
    'd+1t8wK10GJz2SyT81W5pNPfMkunIdftATHV2nvvL1XRVDhFLQ6f6tcZXozN5YfS7D9FPTReQ2urMAec0FgZ5FxzTTPT4prrT7Y6'
    'h7tykO1it9wbiFOVs+/skFxSp7P8RYtfb6en/MUgElovoobqEVh2G/rn3Cztvv6c0BfnJ01nf/+k29vfUY/Y5b/T4b+xectoFOTT'
    'cPNFIU2e/dAd/rWQwsgCR4hSAroSjwS+wEm+3GEZIt6oQ6oaOLLJKPC/PPjpXQswpG4xBcvZuafqL/NQk9IPWsH9rDbD3rgchOZ2'
    'RUDVrjyWOh4kvflVL9JB+oVQX+ZWHII2PM1brl7w3NhjFwEj3NYnpsclbkL/aJqez/sRnGt2UVGjL/9uaxjitv4y2Rr97WBQjalq'
    'fDX3XrCfTLuB/rSPyoIx8McH67WXXOEiW81N0F0Do2lLMgx9fNrGTy+fukqY4+hcg7i3ncWqrmKPa1fbDR4Gx+Uz2x1kyI4nA6qs'
    'H715L+4k8nGrAQ63O7z00tm12u+EMfXJtdVHFO58auksT6GZxZ1wnp5pkTHkQPhyKWx2BhTtawV9Gt27nRn5ZIx2zD8wRc5+oD1E'
    'IHQJQt3GAmCCbmFb/pNawbwdWHREcopM5du0xB8hbwdd7RXytlQKcnRa5EdZOwn57sWrw4MWAsJaa8iy3+G3Pnw1VBgnMCrLtSEf'
    'eBALmCD40k7wziFL1eFTpBT8OIhbcKUK8eQ77AIfCwJBRZ+7OBErduBLeGj79jPFEQ9dW71HFH22ahvTwtODnjYjjf2MtM+DNzcF'
    'M0F3xDgEtxJw/fnyFbeSafZfPQyk85Hdwr/owzrrMSEApEUEwzZiJaQx7wEwA84qECLHi3QhUn2ZpQsNf6jFjhyGoRLHIpqVUchG'
    'Wa8KwK4TmNbnIkBrq8tTuAkYriuFtwnONv0KLHRkIh1A1fQ2ka3dM4+rIR13k76LDbOU5QO+krr89A8RbsZAYqqLFFHXcHaDwAtF'
    '5w2gg11gheu6C6Lgy6X5nP8+nTfRe5ODP3ybzGUO5nINPThf5ueZNbLMp7RTErHLKt4foTXIwvNQBLGnfEgrxX+HyWluUFzhUy+U'
    'bCfz4IwKTUPq+thUi9wqwnJeyjW2CXfPLbkOl4jVzzWT5/vfbCHgMpM3Jr0Pw0S/n+ezlcjH+P7lV/JdKO6C3/52iKDca37+avSr'
    'XwOTL8vO+P3Rl3hT9v0pv76YwSVyKbupdy3bqffhg7MegWssaya99+AahgRZ+wAOmh2MwCiT3QRlKp3ozN375+lVHzEd+Hw8LYqF'
    '8Ja8g9UQ7PWhNkrM7T+u6Ih/ieP/8YtPs5tE/kHeOflDB1kgT5M29G4wsR+dZ/BFsvmY/XD+i8rQXcoWLJY4FO5MXcqamniCdK7m'
    'gJNB2YyIxjlNCOpD1WOM0FLhMQJnGb+/KCOFK0uNEDqOByPsupt/si/cffjmgqsVapZOyNzIo9O07J9R4+KsGvo74Bvx+07QDKDm'
    '9M4fJkBtGiYO7WiYqBMm0Q/Onq0WF/A0w2cCm5bKgBBn+uLEIIF7vTjxiOKQQJAjxsh5LjO3zPq/PXj9SgM69KP6jufH130drtyK'
    'eXbJ8LkGjLZsHYUBVHKE+KzVXKqdMBdGcc9ymnyzUIjALF4vBJsZjr86e85AspI/FQWJJEK60oXesamc7VlFQhGpbKFtqUt1Yixs'
    'ujgjJ1keZTPnPzsk2uN4XFzBtfgy3MnjERhsHMPffLUlD0/jh6f28CsPzKfNAF9xPLqSp6hgM/lSDjr/DpNrPrrmo1N7xL/6frU+'
    'H3flM3M6PC2umCUR5+Ia/1zin9ObDfgCMOrwSTkXofYttB2PN65+n09+kP+T8yxbbiSa94Lb4/EG3Nhg9dR5uNndlDbUXBhcXeEW'
    '4UkT2pFOp7gP+3/h9jOoRFOn2h4vdY8PXYsRUrb+1OKpAG5BUW8+E4enmf4gwoQPXcLdLaTi46ClhBF1Xs3BtXXAH1TRpw8reEn7'
    'HiJMUrf13euDQ++OEl13uiV83UKWVmXDE1jPcVXs20VeR5/6uDvJLxzkHco8JJDmxt4PIXcAVYkeoFKOWmbBoXFuMcS8Jv3d8V7M'
    'oz6UtV5d7W6O98A9NB+fp0f0NZNTjEKDEezFL2ZKdJ28IFwIQ2DLJRAPwIzIuaZEAo6EOZVTXvtW62h3U4YVG7tDYOk1c+aG7EC9'
    'v8npBanckpsEAHC5RbIXankDKu7WL5u6s6TzvN/blH837YmLZtEz1s8WC7fit/R00wVQSbuUAzfV20JqGJ1nZYkQWAyDO1Xnc5mO'
    'SS4XGeewtoDm/R3yhZiCoL62+YyHHXg+VBhUMg3186ROs26E3yj3SYk5gtpW19p7LtkvwF+ZKwKQkT5u5P3olw/2/+GLTzf9wT+9'
    '//HDjz9+YOzIjz9+8V96oafcaX5ySsySPiYSTOri3HgX3H9OWV8e8Xkd9E4z7egrVhR/fDc0QPzk+dW8z472WdFAbobeSQ5HBku8'
    'C/oKMisUlh8/hrQNNZrr7xMVp0RIPMoWc9k4VJvw4Km3t1EYdEn6iWfmEOvAdDV+Lgx7mOUivrcM3zCBYRfE/OKthpkQU5Ri3z0U'
    'Hm7K5dlaM0WO+8uZpUJq8l4TS9Nd5UDo26KtKUWGoC3YAODHkC5pZWJj+Y61tfQuDZVTl77m+aMwV5ESheBGlqs4RSqgX+OuzoBp'
    'bc/yGefDqmepB2zzQfJ3W+Ha9LVOOVEOj49CLV9W5p8FWPugFbUX6H5oejcJWowrrCF5V0er8icLCE7sPfbHltvGMIQNLjhaVNsB'
    '8tIfRTacysXIvg6cCeZpUUyzdOYX3xlxnIijhhf4zR1XqjcXHub4XsXqvflxhs/k3PUjJuDmY3OXOVBy9GxEObTP4y41VroX2R9+'
    '0avL0GfvOBa2ARknt3WAbjxLMymhQ3HDUc1uWW4UpLdtNsyCcH1QLJbhnAObK0qURqQ5y1iBeL2xYsiNXC+oOsieFedwDRGm0X4f'
    'VkEKQyoMZrBCXYiQJnsEMaLIbWdJEKtq8TqlCtnlqfvME8qFKpHSMCzNOWJZ/SSnT4ekhWpxSfGqx6Clay4pXQEt7lJ3qATkfr0B'
    '0aBoZ3QLoh3BYP0dXIpwxxQ1CdOUrN3jTE1ic/Px1mqD1OCQB7C9q20tHO0x4kpqmxtUtDYyuBcYbdWt7anrtmfCXHauZeqOBjHC'
    'TIqtfrgJ8MqTf/+35KNKt3h+BI76xgJ//A/NUfGsUQcrFaMO/8ONyk/8HFTMxDZhYf5wQz69et6cPRO8+RLUGrbpLG2KP5IRk4l5'
    'Rp2QhlklJvxNqoTQOaWaSL+RLArCLdP2twH+hbfI440tA2ZGLc5xU+schGjMvIOh23EP4dlpAbFhpyh2QPoJZHnm1BUu0op39nkX'
    'Yb+uonE6ORExitAcwpyJFCUP92w4ruEYaBrK43Rq49EvnSM6gD5Udoeq69BhVbPq94fg6uiFafjTLSOFe6afgtokoA3UWTFKniDp'
    'do5nJH4bO9t5zeLznQu79dExDBrvffGJJ24/3kZ23uLu4sdaXz/GU8/fAungJkiEERzogZKD0WpGN5x+HRz8iAk4s8sNOacqN73K'
    'Lp/Jj9WSQJMqaxGArgaw4B3eC9oond/bCGeXrCZiLJW1Lo0XqSSmdi2lJKl0kpKjmN1NVBKgMpvX2XLkRAfm/6JqGFKgNKbpSAFM'
    'JX3Kj6AiGEKwo85Yqiqg85ldQx40vTQlRIp0XarpPoQTkxSETRvDJua6PwivohYxVye2wmJ3YotV12/ju/yzkEUGTNJjL/Ttj1zn'
    '1H2l4oY+RlSh/bjK7kiiI4C9b/vMiAEMfw+1tKcJITlYFnOTAzQaOi8bpOEqJAhGjyJc+qRLDIv1BOO9l/GCbHPJvvjEOUH4QTRk'
    'XDEeLv94ml09HAOMbRt7YmNvVswyRxv1bLqBu/P0ZDL5pjYSO1GJPLI+CN8c07pmF/Z072cTCiqREQT2ZfB9mLpyNbZh1TY1BWWz'
    'e1R2T/rhQGmJwavKcuTmNsCVPjssDMK7wmmaIDoU8yVlRJA77/eoanGhH05ReSq3v4viVJ8I6RmvFaeOZm/S6/0fZ/0fTD+C0E+X'
    '95UXPbB/R4NICsaADovVIhQpgo7Gce/TIp04cGumgNAkEasFXMtiZg+Cbk2hkF2l53Nhc3XSeyEW9ZOZe+pGvG0yG/vtWSBAJ1ER'
    'D3S5REXgI7jFXOYu/25NCYjxwb+JYhOvTz/O5vWN0BMuiJcnYuTs9bMTemwsWjQ86Ao5lB7YeLZ+g5wswaQujF1cWO73hd74LSoh'
    'm7lQu6MhlLXx6zY25x1Uhqw+xFz8dKNTUSn227pevRIKZIuRZtyZajh0pdVa7NQSZoZZq2/reo1i39mFVbmkVj/W9wEb9aFyq9Qf'
    '1Hm16QMYrJkW9Au2bW15Ry5rWgRDDhGDUmji+gi9ZWvH6yuavf1FwDr0AqE2gJSPJZQ1Y0Z3gxGj9CA+DTR5+FxU3Gd0GLl1GTqd'
    'zj+/S+ZbXHMJVx9j/2PS7SB924DMpbjjSrv7Djtfu7uCezncZOeD+PhFit7N6LVwh50HuwtFtNMBb9qxcfwdqdkeOxuWUbtWQ0DV'
    'gDMEvK/FP1SnOSrncMede157sVsTBaDQulwBTOFbrCLsZd4Lh8I3LPJ0GiKya2rG2zCwWxLADhLYhfi6exT6B1JZrbdTvZ/omwe5'
    '/i6bzm/taGUsCkq6WyYadjss9+eicIdV2u5vm6LbVO/31xbYafDPAfY3BhZNi5nlpICZAT6DwnTa0YZrI17WBrZYvq82d0aXL5j2'
    'OJe8Mwm/m/EzvvTqBj2LkoqZiZvWYJHNngbJ6AknWpDW1kUBbzMedoalGKkNW3sctUaTe6E8ZpaMM1rF5ZILeAU1PTyOZK2kQexd'
    'zISUrV1B/K1+B3VNzRPkk/wa22JNp9umqLt3+8EadcUq1eLi2ZWit+5CqoA5YLl5Devk71PE4GWaZ7ECSYYATC+0pP/zP/8fyiRI'
    'w4LQRmHa5+lEePiSmLWDwHBDOGGpUW3mkUQK5LasJfbgcJFl7/isihUAUzckRMM3VGqPDr57/e4noDUM7VCkR0fZnMEI2wrsNguj'
    'Fv3tozCjw+QXwpVPJ/I3QL0FcFPVwjcvXh4+f/vT2+e/ff7sUIhU89GTZ8+evzkcel2Mj2wVIgN0dBshYzWJkykUTuF0DCkTuthC'
    'Jud3kE+C3+sGPKCJrXX5f0+pGj5RQZ7KABCCu3PqchO6T1Hz/vFO+EZQHd+L02BGb4dFnYW1Dsm/LrWp7q2zMblJ5laMFfLYy1+D'
    'kCdndWeBn//5//a8o06GDezwieRMxN0o53frBwERgXk2jz1Ig6/eUIZNVUynsELTj+ff/y2B/29SpdrDIwNbnIvkfhoWtZeLhb5E'
    '+tV4sS17InO1T9UXJc6gGNhg9RTjIGr5/gbEUdUpbAyTDT1ykw2EAQGEwse8KLms0NUUyw7ubSN6pBUrefDQcoCzbqIuKy1nFlMo'
    'zCgXG5RTXx7Dt6dMSM5hxSsI6pQphFOQ3vUpk7kyjzW+wvelWES6gIoLQvIruAHmaQTia9ChagB4b2nz1ApZB83q9LTxjSuUYpUf'
    '0H1rBQP0BhPNW2zuQu8tF+Gn5Go76b/qTzXNO/2p8G1ZyOeBuVNFJa6DEtcsoRY+SzqdlmV+Muu7eVO3fbDoCPqgJQnuVmznXP79'
    'Jb2vRmc386uPWIF5VeSaRa6jIkbafO2OkbAZR5b06Ug32f6+WYx84aaHkX8UoDtVPQ+QLzQALW7WG7pbf44VobqUukPopOVVKcGi'
    'Opa6bo6O945/QegrHEtrrd8pye2jL7caO8rtnOZ0OczJMMPsNMh262bcoee25LV1RRpZbe1BMwu378adWNyOeMSOjLMdIc/BGlna'
    'jk4G8JbQ7qCmyjcdW3fNqFpS1QZ9Qaqni5O2ONHxtEPynp6tkbyxlwKBe3rWNZaKsj2Ynnl+c2qC3r2WpNsXIsfkSD4BsLx0OmUq'
    'C6G+q7m8nbVcDkyTMJpfgz6fz+kShykHqB4d4oX5y1ICR4Hoi9x4ZN7uJXIz9CbZRS/wXZ0WxVnJO9YadKT8yZs3P/3h+duDF69f'
    '4Zb+cuvL34webY2+lP8effUbmT8U+P7N108On//0/duX5vZHb51xsVo+matrsA1vO6xv6NradrE/R+nshQ7f/2TTkU3sl8Sj1b94'
    'dXD45OXLnw4OX7993hre9tBeflgcH8sW3qnrKqEJfYJeBspo9XlU1WowgrpulY969Wgq1cvbWyO3dCLN3q/NkpCBcGLvK9rEhc94'
    'adMFB9GGT4Ov3wo5rIoLyuNfy3JOizmzKGC5KZr/wUoiVKD+epVsFkljvmefI0m8Ph6HRmwr9RpzG6AH1UoPmolNjqqGvJ/zl7+2'
    'NMuys19ll5D95sKcyHEWNsefDQR3Ad5TGvJmCPmzQoIg2Kwy8idwsIe3/KzAmZ7pXSTyTG31Z9LMwmamsQHW6dV1ZJscRq+KIFiM'
    '0os0nzIcZl++ueXZ9giUTY33cQYlbm1zPEh69u7oH8titr98jHWrQjTAFxzJERchqSebnEBOPbvjq4Bbh1/GOpAHJlhv6zFAvsNt'
    'uC+/VFB3tekKV+08na0cp1ZX51/4wcUTXIkkF4pCrHU9TRGHUctg7upXtfbGD8Wqh2i/mYMLxfaw4WwMYh/xltefuUBADiEicsmT'
    'RaZ2thk0evsbdVzIekd9TJvWQPCDht/zEzoDu/UXUaVmmNLEMZPrkT/vcW0m10XH9iIu+m3RaBYbFxRAu+vCVnpQYIDQAaS6pY4g'
    'PW/kZL5yg251Mq+XcDecJ0nob2MLLVYz20Ahk39hUsKa+obJSRGVQtd3PtfHPvRprwRNQlMwh5Fej5o8yBhCYFFn0+PtZOJmMQCs'
    'BdFZ8c4lvG0VpxvlPxhPi7E/Ev31x77mnH50ukBao3IEv9z9C5KBi67TPxihpSqzRIW20oXdlPZ8YYVMkbLSESumkol8p2vxU9T9'
    'Hi18QAcQjrodJkRhDjipxs/T4/Wj6aGwxeG7Ttx2rNxORmKk105NiM6ta0iFYXp0uPdLDdoxXjpIPDzqua6cFE1GPmmAP1aUJdoe'
    'OoYO2tL0YJe2gkPoWrttMniQZNu7WADjWNqvKirwenc2697W9qEfZDLJJ7MfZQKgkJDpqw3GAKhCQ6Scuh+CWAbQwrNs7tGUXchF'
    'qu4PJwVBmYmvr9EX6tnDHG8oj6gPYBkiPnJ0h2l7q2WDiWuDsvu7LYOuM7Wku84SkZXO8zLrL2oZ2xYaaRUF67ff9b3NXuf9rVa8'
    'UXGmXul2f2MEuL+9l/DHnsj6N72PwAKRo3pWD+mn48QRBToRbLEt+1UybU8/w3zDji47G4oWepku27KQfuq+HyxgIsidXbGUt9nJ'
    'Qv7CCZKhsqjJcvrQiVlRh8nlL/fvt8ZGR3JDnYM3BeMpIS49L1vJJXTZ8L974YQ/z4rQm8leiFhp1OsxvRkiXyvduml9c+W1XDTn'
    'yu+/I+BV6dy7e/BKagbUkO4R7CcRmr/iYXLRTLS05HAqO6MzT6KRqThRJI+hcjCO3paKnZnmfNQz3711PZA6y79eB/zeDiby6TLO'
    'wk5GpALpqK7pOsXM3bLpUW5ZarfN22Ug52K0dtGwYC9chfdF4LlCDDgccNoCo7w6t1pIcnafWUO8Er2Ib45vg+pey500viGsR8OB'
    'JrT1WmdeFW0HfQ3SQnQah3W0gpu2WU5a1CdLM3u3KtGX2fzh+Poh/gq9KEsw5VCmzxdAezzyPmAjTXrJcml5plcQJMtC2T14OSJ6'
    '9OR0qUKnZSNcFNMSTfGSyBx/ITVLFcpAihBwjJwD3O9llpUO2WCi6WOSfm7iSRnGUGlFdPKbqXYmRTvHchMpTmVZZdfMmDRmJJsk'
    'wxKnNBAUzG4u04LzNs6S8iwnggq83JCz7jjLqGniEZT2yVKMqL5Zrpa1rI+H3x92Klvc/MdoINKl7IL7arXcH+E7dHH4rQqr+/r5'
    'y59+9/wHqKNLGH321RRE0UVT3rv2V7mLvvu4O3ZelqucfvPwMYXvo0WMpOc8qGZD1IgyTeQEQu1EBppc9eMIOZygSx4xt5Kx7paa'
    '3XtPnuWTss8wif7g/dYHlHUBOmxSkZt0BY5XC5IzahqyCYPG1U8aFhO4E2IReOdn6WKas6i0dQkGx9ZpyIBxRQ4ukUDc+zQG4f+r'
    '5UGm+V8iq0XVzWEy3kJst42Gv1W6gmzG/fNYJ61/zik61xTP1Ev93jlD0gxe1eKCT/YeJ1/iiXQP2nKY2TUpV16+LQpmAAKwJaZu'
    '1pyxsJZKpGOf7mziqaeWtt4/rvUeIK7n4WYYuHFKuTenxbKQWwJq1LwMQvnQTWJg9N4hoN+dcZA59wMAhuwHLF6OCDRg55Y9zvPl'
    'KfzK+82Z201+NUhe9fG6ouyeY34Grk9s+X3jNVqgLPV2FQ2GBWYIY7TMQ3gWs/Mv6aeDPjqu7lm6GMPVOy+uZH6irnKxxt2LtStr'
    'FXV8HHVc2nx/SxW1QagZDsNXY8o1lbJh9udjt8DOg1dz6ZIWOldenwy8MNJeQmnUC3JfKAl7/gZoRu+lsk/qyi605h0QhM8p08eX'
    'Z2+ot7oMbdvIwMfd+d4hA5rdrQMnAbsujB4HIDZOTgENZsIcIfl6mpdyyySGEsG7u/VWAny5CyCZ71VXVHwROSREdIIEp/UOKmZH'
    'We3uGSXef7ug1VptwEKBwJR5HB4531RaJYj6jvtURfDMN/ZeII/nGQIswAElj7YShYkpq3aQKS3juIXpY8igh0H54tNKOLH/+Nfe'
    '4GZoseJqfwafiJ1bcUNadB8u+ea8b6nfl8Wc/fuY3AyjNSbmNdkg7+DdA8I7TD3yWN1JOtb7OaGQjAt1wqvKndqlFNEkvl4GJ5hM'
    'ey78PzJlvYAU62bRp5Trc/FgkJ2k1HbLrEFfMKit+2+BRQMAg8Acz1aIBui1VYk6dJcANtO5yI+44EKYgIhSkodRcBna8XfPxpM9'
    '2vh2N/ER9SmBXbPIz8xlIEzcZj4DI63xAIFLD8J6bbIUKQEjBHcJ3C5XDVzTcVxARJCQtUzG17Z3dT2HBgczy7YrGbLlwotAfdZf'
    'aYznjncJ5JjUyGi0PcakdR37453bwVXsgFviYTjTh+nY5gOmChVudCc/1RYHN1BcA2zP9wIXHE4hDrBMcLwvmPuGKfOwu3Fk2te1'
    'awpbL/RHbZNyjjBdVzyeGUOxXzc3fjCt0xJuFEyMTomrNpwTA1AC7WJKNoXvi+eEWRxPCszZarbMp7VDz+gWOUpCq7NqRDhMa7Y8'
    'Iuk8QyiUshYMMlSra+60klcwv03RLEAJkCdMWh8b5bzrMvyqvgzfijAiY+MFfseN+dT1GZT3FITXj0J7lksXL2ciOOgJxsTKA86Y'
    'L1nbVtUm9quiE4vA8UVzPbB7MN+XhQYWk25pWVqnsXO1rTUL8NTd7uC6ugfCuKjJIpVPYzqyaVo39XxSmckNLyDjM9LdOywO+dux'
    'FwbGt3C09QX8PZBKDUsDjYKnhY9yBgM39Ap3vY++L1V1zfX4+c//8+c//6+f//y/f/7zv9jCpHBehesc2SECpFaZTOlcg0urot+W'
    'zrFBW0h3KH/UcqDanVP6S2eUHBZYZfXR16sJNxCOgplIhnge6nV8Ka10W9fFoJunQKd0lzqAK5A/UBY/uEVp6q0zSPDMiXaxbZz1'
    'fIuSofLI5k/jjbDzuUbhzuBFtq2SqKws7xVICObLhYkVcrbIZb+oTISwTIpE7yEADU0i/UAw1nCzsca6GIVXSFasHbnK7CNr+8Ds'
    'ZdXd1nzGO3A2aGxFla6NF0Aqx859OHZFfzH+nuVad2Q9m2uNZnzxyST9m4DMc+llcMrADcAjlRGVJWPYoCevCtBiyyNZhRuyHfgz'
    'P/j7WhtMP8ojIW08j/Alod0x7QhKzTLlO6u6lJNxNS4yRg/nLbTCgIGo5gB6Xk8tTJpiKvydk91cD/UclW6VRiH+IsLAaqJFwJlb'
    'FEhpL8cCBNuuUC1S8ZAP0+WSd9hSzxXUptW1TRqbLn3eV6wUyK1fLYpPKVm41lVr3KY+onuZ61E+FxpzITX1n4hc9RC/Dki8/Wiw'
    'XMRkJD07mcplUur60+9Jk3Amh2D9fBXKNQXXMmWnnLShJ/JFyrkA0KKjEyJOHi2n15YjFG1epjMF2p4FzK1uiAd0+EV/MFfgrr0g'
    '6rVsebCp18xJ5I7LwHd4MB9lDXbQVgcDa8lOvY5UqTf9ZxIrfemzyZVri/RJvxiFsidKoxrn4BCLRkjpDmqEAqBFJqDDgNRxFqJd'
    'RpZBzoLfGYoKN9vGJF5z/y+YkzLcirMsxVZQIFyKqhSFJxNFxabHt9qRvX6vknNL2QB6ngoGcQc7Uflbp2IQERY6+RqVe6enCK8N'
    'g5cw/EDolZHI4kELAP0ynfnYxfIssJK3NmeSnhqtta8U/UOhxBpbs2thDHZ2BtaaTuXIWsx4AkPaJYQ8d7gQQQOiJJ3lwYMgqACc'
    'R0BnVJDfpTDLJ6d3IbFL9o8ZvYJf0Y/tSbA9GpvsGXnzsnOTlZcKZnHrXacnMqUooDKxsf220PNUdsfS8mRfnhbTzAt1NkW3E8tv'
    '84ssELZhH0gXZ5RnHpLttib7lc+/zNbA56GPyHSIV2gyyRB6vyPmD5A+TRQQGbELc25nm6vkOJ0oLZK9frxMmBwHAROXhC4yJq30'
    '+b+1RSGbCh6bLm/f/zieb7VPNqYyVKRQTuAemyOYSQ+lzabdAm5Iso2E9b/DBkIzi+b++IYZMJaUaTu2yPHTgsFHxy+WqSw9Ph1A'
    'qweJQx7mJyf66eA0nYN3Ov4mnyJcVIoUl6zgbVZmy079Ig1OiwnTLZoM6ZJTa36Oso36b4fbaDXd253me5CDkn7F0TzVq8ttEPQ+'
    'fPzCHu9uyruuKvmoa/bk5//xLwodwm8P8Bn7pdSx4/yOOXYOqV4HRZbxXok54dL25znQs8fFlUjQ02k+hygtdfCaJxCiKjL1PZhD'
    '8Bqr3d2U8QXCCpBCZyTJImiOrIM6x9JHbhl/iLhdZC8r7HKX3Ne83DiVLss88tmNbP74mTk59BMGqB/R58b+eqMg5HUC5Ox1zd2W'
    'iwwdbp78gEjYv8jfZpqloV34N6pL2R9d9/DnkbxfkS+dNOsdXGSgh1XkVJ53XbNqr/zBbSUtA2aIRaAQQO4TT8uV9Wxqr7CDMWs8'
    '1pVCR20qSkG1M25XVVttHXtZ+NekOhC1/YQKVKq1ne/w3Zc9Pz9pLCE9C7u5FHvcuixITO9163KoVfFJ+65t0GEtCCtcHa1ZtnSw'
    'DoH+bNAyxQrHxkwypp1HOlWIGkOal8shlSUKjVxa1lNT+9hOHSXvGObl+RyTHI8M39US1dxBgVNhwCk3YMYQ/QVYO6OEQyRXYF5P'
    'E7Weg7PJruYFb7B3QuOxHX4vlyEc8JzmvGtZNRXyawbMthksZ4ZaR4ZV00X5uKDd9/+w9+GXe4wN8qFBLbeGHLFKaXaZXnfvD5cR'
    '+I7StGm9ylgnF24LX2G8MzbdrhCJjSgNpQpLNWFlqMsi7QFCjm4X2Jzg385hplFAQKzIcnUE1wKMrrbT1CpgpJr1OOFyNUPL3Mwn'
    'ckGHKzQv4F+yrFKfNJfF58ZAmk3FvKrccG5arncrQl+tNbXVl+8AUXfsP7nS7rV7KY/XiB31tUNCHvnm9c8DOzpFzJ6j1pA3L6Pu'
    'wGo2MfeBXJrDLVpMIaE5u5GIIgUyf2LSbTmlELUepf6mNylQ6y3dANUjsmhrTq3d8/AgpedCwMKisyc5xCRlxcyoY3oCL6sq34YI'
    'o7sTXFYl62di6pkGV6tdzMHV1VZP84vDonjp1Jnrl/CsY/leEm4SCGX16oYYKJ2HJjmckSDSuvPISFg6DhIkkcfFwk9qx6S2PWwz'
    '+MBhpYaycoz1xd1lShrAk0GTIItcnD9kOrCjYjGjMaSh1hHhL5bkOGDc5ka13VGNXlqjOjAQzmhFfHzloIJHbhzHtS8ke77q1sOo'
    'Ucm3n0ThhGoim/Xf2Qnpeezcn3im0lJ1QfuaIMpiq2PfAVs0kKW1wwhdVSrn+/dAsv0Qud4MEzgaMTAVzM6LyYMH1Tsu/DMKeWb4'
    'HI45VDXbSUqlzLLYDuwPzDIt9e7vJ/ie3OxEkcyJW5T6Rld6XcWVx2bcQ+qF7W5vp1A4/CTqpDEJ+ZfqZFgQMyLGI8kYfE6DEdRD'
    'R61Jek01v3OvswAukU4x7mK71YbgIuMb0euUI0Kb+SDquMXW0/9tN9+r4up3N/O926wFDZW2qoLK0FqCbnWRPdtSDEGONhUp4ZTJ'
    'gDQUHJLEdKQ2HX7UjHb8SAlWP3IwLTanBfmHGXn9dteHMUziHfTw9SxTaEwvRZSg93J9VFDBQ66qc8QxdRl9D+i8hjw9o+RZQI4q'
    'EzxpEozY6Z1M2GtUJHmgkVEp0PS8XN9RUu0xEnenklJDZLVvq1Gto4cKn+zdDtYQQFei3Uroq6rzkrRN+2ssWCo86ViqJxSSqzcV'
    '1nRaQFlg14cwysNAzSPXcunkA5xL3ltQjcsdBMxuMNXqeROvHzshpACr5U4T8+LQFNi9UP5Wqim47dTOilC2iFzA1daXfA1TRpoE'
    'g2y7/qincuaMu7IdeYlRmcNip92MTH7l3hWvze066Vt0shVXLyvJpqrtSA8F9VGufBmUpaf8s1Q/ZcdWmN7kWgQzKjtOVOPKA3kq'
    'Ba/lxhk3hcVZ1f5zZgjEPLWr4ZwffuDsRsXKar6OdNq4Qr8L5uApTekTmupNDgk0lCdFMTFR+Y8r3l/SOLEublf2Ya62edqaRjk+'
    'YxBJUxv494B5IV0i/kt4FvMuBd4Xn7w/s4z4DRBjnDQE1JihM80pdIzLUNMCH0NXaCl4UBV0yDPkUOm5MKwsfY0K8ErvxrsBqG2x'
    'e93tfOfLmiC55VQ98BZYOMdGlQecJ0Vli/Mr0r4JDCNkFpgqvQ9g4LqgkwNza1Wrod12EmaWAdM0Gunnm3YhMVh6jFX3A2Zo0iGY'
    'MmFHOi77iqySbFpj8vFh8mggpHxrtPVr3MQseXo9L5Z9w2156MpeDRPDafE/XePVr7YGrvlKtG11YAxzrIR7UfgHJnxYx+vRCMpL'
    '1rtKal5hxB8QGEK20PeG+1vhhu/xwM0QsOSYJ+rQfBCfGRkcWnu3d+GaLfHOrKWpqyYNgwTVpV8D/9AcGBLylvjSfmNHup/7YK80'
    'srouaKQXSsa7la9jKUP3B8MW9FpYPnhSdpIAOrFJkdpROnBHScle5IxEm3sLMLkjgVH0FLUp5hgLAkCgGRfSEEz1F58sOtyZFrRr'
    'ms+yxX9WNwWIL3xtpnH6KaU1PimW5QE6zc7hr2lr53grIoxQlaYeucB4j5ed0aCMh8hLtR1W8aBBDq44IDRVteOEKaXgkIFgJSoi'
    '8yUax2a+UOqioO5CStJjZxC6ad+AP9AZBDXRVAymJHU7ve6UHQWyeaXyHa6gkruhvgefU6fZ4Cb057szE1o+0iFlmQpTrq+Udc1h'
    '2QXvtJiMuAXfvPrWqX9Nf7Q0rI2v/uNfE03Fie2n+v0FrZLVMYIHhaoUl0hjbB4A4bUUm4akc9Km6XBVqCudlteFsIuAh7gKtPpt'
    'UUB7+XVxBA+3YjAM9MALi+pXX2j2gjtY2VyNqYIo4JTLLeak2N0ZwABqc8y996nBUcilOWeOYQVfu1a0t3KZ3WEz0E6dVYvc9Ami'
    'nbeYZOvJk2G3dhoSuTs6AFzL1YwcxnmBUAlPC9QfAO412fJSOmyrzMBM16lRAptbbsyHeTsoC6Bil9wBx3eywi45gPrwHfAHKFCZ'
    'LTe6BkiXwIoHvY984eAT1JeKvk2a0rptp9ccWtPJpHJ6Gjadk+15qZ7JFSlU1hViLL0qENwBipjP2iygdjH4bNQNEqw6PqXCtM+Y'
    'SO3yWXtIz+7a2wMjnBf+Mgpf4TXSZlN1niy8V7oIYeBQQPc5eLrwcqpA9qkR1utkWizpI3CcpbQrecEk3CZQzuk+x5b4EAYVhiDH'
    'd0oicHeMEL1Uqm+VQk5kzjcZMzEGeCKal3Y8TWdnCoQ7VQSBCmGwgSuIbcwktsSs2wkReqsIJ8yTjBBhhP2tGBEvfJRHSZyXzMHr'
    '45ve5x4rkbGXcF1aDGSAcls70AJ5YL8zrorxnsLpDlkZNa6zba7qQbaE5lLPruFy8UUFC1IkwzUxvj5wdJgcMEmv9L0eeM+QeGkX'
    'RGEyqKIaOSH8HQu/P0KvA6Sj43P0+lSldxW3KkBT5r72acKWAOzqwLKRZ8wX24i9Z9NUFQupdNsOO2NO107wM1gMOXN58iB5ZNnE'
    '/DI4LY/IBzcfkX+P9fmoXKSc6rtvA5+Dz/dJ4RWoATSN3+Ok/2hrK/llkov40W9rZ8BU93/TC6o5BDltHxopbVhUAQhCuFSZYu22'
    'AVEEpb9GWupBEyrFdx8AWdXjnFfPVlDi+ZXwBrX2win/GCWkkVP0eMNIiiW5sm9VhplGeaRJ2mtNg+Szo1mgpwYvWs9ecSJ2FLHk'
    'bfbHVb5AEC9DexUiqAqn3tb4+2ImLM9qhoiQUgPtqMqgu2nJ0wOPPFt6xvqq3zFwS2aMSu3eer/zBBhTnmwnjY10IH3BA5tk+Wnj'
    'ZYaL8aTYwEg5oB3XVADScv8+62I0ICymUc3+BQdKFb8NwLmiGiazIuECPBIZHt44PT/HfI88FVAYR0L0hXvr9+aL/ByJXodJ1YvP'
    'Rk4eyXo9PBGRDDia2TRoRhMaCH/hC+yEtMYQvWXU4VeGiJmP9eBzOhJUUu8Iwt5rvZBvL2Wr8K2YyvPIAhmput1AneHkKCSbC4VY'
    'ZnypJi1MDOMeQIURkExXU/UWH9VfZQPVYdaxT6qjoaeeN2A8ByLdEOe4tpHf914Jw3AfMcd4lR++LWCh4cc32eJYXr/f+/AerefJ'
    '3yRffdDaO4n1q1ZwH7/F41JNQKJaLQ5vreXd2gq67fpX36JV9lrOiVsa3rqgDXVMxU/VVa8EIB/EzAJuJzpwJ49+Y1CLuJ7B2V4I'
    'I2VbjkCMimLwjqHgqadfXhPrjDvqimj4F9DQOTmcmGhCdxbZtYazqlLbEU1qGRH+Vxb3DIPNM6K+0GUKjsncTCivjpL+94ziYFAw'
    'PkwvobAi8tQgiO9+9vrV4dvXLxHi3YOXE20CoPjDxL6qrcF/ZeqRYeIUaKEpeSc6lNVxDTivAoze++DoK/80oo5oCOkM3Yby6K30'
    'uvchygdL2lOjOJYbTV793F0Wjt7DxrvEn7MVgG2nFaTtyGBgKig8i8eVNlJ9AXNbVn7l9D6w+1XWOqieg+UJq24t5MOomivO6KXd'
    'Z70Ix4W/L4Bz82JVGiSdhXvujyyTIF7y0JAtlweOTHF8jMvDOmCg9QEtFR6gRVr4LJ7YcfGffd7Rt3XHnc872FNHff+aRKaFZdeC'
    'Mdces+qGteRIZID2o0jKyIiiyeQOFUMZEM0O1NpfPtghPt9UtEY7Ed3SG8Fol8Mbcqzl3dtuVvmwUWUjS04FF9XoephAT9is1KIr'
    'HR3b/3H244zh/viVZqqMyTKoHcJ+mzlUiCBaxOEcqFLXYyN4wIP9FpyDDax0NH33wjEpf92Ypwg2pAvsWqoNsK7vj0M2odakFhl7'
    '2E4mOAdNM/a8Nwjy/hmUeZxkrAXSSeejgef0DeMbFiscErMWJ2qvqKuMr6EdM9eP8JKxYFTSuZnZoR3Wxj1NNS5NvF0FjIeelOD3'
    'dmi5OioSRGi1LLWXd8erVWpurayJkHWPyewh+w4aiVpcx01HIP3+7cHrV4i/KrP+mh65tFXkjJnSpByYukMdB/M/Zf0y7gYe7+9X'
    '+hD2C0YXGQ90L+UIuTcRTzSg8f5PGWiWAb3fa6SZGiYOA171IjzCsH+haizSIiuFDh4GFFrHGv7eOsQOuuZTBmGBuWLpCvbpCexS'
    '0NkM6rqnnXsesLhq1MUGtNWAHysNzQP/0oeYV6seuMvZiVNBSCJVg3KBVH2ghaej45YCq+8q5EgCHDA1k2wL53WSz5xmG9ahuczc'
    'vQAnfefe7qam39mTT8jog78AWt279/8AsbwxVg=='
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
VERSION = '2026.10.20.2146'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
