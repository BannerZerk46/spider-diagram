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
    'lt+qwIfkrdFbe9bLfrAxRwPbs9wB19iOSvRznRvZemGcqTy63lB3pbF1UMoc2bN5xeq8TMHOzzut/nY1XclTvbvd9U4THVhEd/4y'
    'cPtdwavys0xxcCI9bpkxOot+4aFnDzf2os62+hvx+fm5PWbc3oEcGcZsY7itrSudXHc/dQeVvVV3222nfBrnC5X6s6yX7H6+WrEP'
    '3bLR3Q6AZgejFb8vyKtRQa5sDpvdst/QNi+0cDoOWwd94u5HmQ2pNLkW/8TRW3M1ks2tbFMNU+PlylTszYDf6ap0mnaeR5vTnufd'
    '4ZNu6N22NW6PJ+MM9TAp6fXxaHXkapXT86A51ouct91uN41B/1CbbsdKnl0yz6Mps1Sk6mDHdR2+9XRwzd0GLHelONmpFYZUenn9'
    'wVs4zK4k8G1rflyS8jMNzPxMbRjqgtloCXsvs9qORfPwWHcY59AcjDJthmHKnYnSqtbXp5GyHAitqqnBMJwXTaw2+H5/7HDAaLWN'
    '5zit+k5WDHXAiyRt7jpDWnfOVAaD49nhST2V97sp15i/OM+SNiDX21N78v+z92ZLimPLouB7fYUqd50KKCIAMRNZWWkxQRAQQDBD'
    '7rw7hSRAIDQz5k6z89Yv/d7dZt3Pbf0d90/Ol7S7r6UBIjKrzvR2a9vOENKaly+fl3um0tuKql3THLusOTvgbp630Qm+mEO5oDQ7'
    '01G/OYB+8uqgXnpIW+028K+lXf/5ZApKurIu50azjthI9KebZbeemnZmz5X7VuHuqJYaW7Ogp+qtoWy2m6KzGsjDWr5lTZVuQT08'
    'K9VV06uUgAfZOQfTnWYSysNWvJ1OxZ6dryjm0VUHD4V+56iWy41B4zHfyzu5/vHRynpuqaS35fGwllDndr/jOg+FUTOdbU+djdjb'
    'S+barm6Uel9NA3e7TtzciIZ5U6rbrlkYNAGTzuc9Z7XqbMX1gyNPx2OrP5I2bt8u9xuDWbkrPUhbdVgGfmQtVh73UmdjDUXJSYxu'
    't7uO+9K8c+R0o1O1rW6/Oeo3xE1m+FSWnOL9rbiRQFDp9K2G0t1JpYrqGLYhVpqj/EAadVKJ9aj4kE097htV3WyW+6nOci+NSsBJ'
    'VPJGezVbajk5t9kcnKpX6k7vlfttc9muePuZ+yK6h9mhn+7Wtm6vvxf3Xqtm1SYNS5bqWzkrO3krsxHTBVHMFh5rsDHKwi679sDr'
    '6VrjkF3ahVWi2FaVe6uqH9IJACZrfxCX1Zm0KYEw33psmSF1a2dusofuuOVNrcFgpCy93kx82vQy0kMtp3iV0azhVF76y0HGACBK'
    'rAvNbTc/eyqqt+OuZgEdXy6sWrX43H+ejjNPYk2TarOX1ovn9PMHR26XWs9q42jkZv38o94bLdwXa2YfjezsWL4Xb27LtVYzHMqi'
    'NByP3XV9Knm3qv2kd6pwJoCRrm6H4mGaft7di3ey2exqpedjtaeV9mr15TgsGZl9t1cvrLbefr4cDAbV7vOkZquNkaw+yuXhcacD'
    'A7ROqT3pTvWG20pim1c7zaE16qZGJe1hky94xqIxSDjNREk5itP23RCEgmk53zQfLbWUmpUq+fu0ocyQZ33Rs+2BW3qStuJkm11u'
    'VGeS64owpxnwfzflRtYopubbmroqOuXUodYtGnZGffBGBTdbPLZy0qG9W4BopXdGjcFI6mgF82DKy/G2YgPb6eQrIDraTy+3ecPW'
    's82xnC0tj41+A2TlvJsbi061Od7bTUlsVr1O86HTMksFW7fsTXtdsI2FMUkUa/vHp0Kl3X+4b4yGL6W1PRo1ljflY0a35Wb/ftTK'
    'beZjt54q3dz2m73N5iXzUNcrQ8129JdN4WFaXy1nL/nmTOpu7ga9rbM2EtVpbqVV8iMrtVgftrqYbyu7saN7as0eTtqqZ9ceO05h'
    'aBcLy8F0sSqv76ew8L1MWe+5zmbWHTSUfkmr243inWg+ie1Rw27n3PZ+pM/XL6KaX2Zys01JM1OF3rG322bdVeKp/rRUEqvj5LGT'
    'mEqdoWENS+b9Y2XlOdaTNZ2NuvX1HtjnZ63hSbJaGmzvtWG6Pix51YJry+lxo33f27/shxlt4tVFu+bkn1opOa+088qimepvh9OR'
    'PWjlesu65pZT5ZH4PCh3F33La63ccv6+Wdp4+62etaeeYh+GrmPbncmTZVVEuXxI9Y0X7WnTeeg8ZB/3Nw9j6+WuC9K2VHrIrfbN'
    'fq63n3VqKzEzB1lzdPuUr7YsyegoelN3VlJRErPTbiN7HFrp9WEsH9Je6/65mnP3k/VCGtib3SQ7PKT791a+trJtqzIqjzVXFg9u'
    'dqqL6YHdHvXkRV5OG/PjfHHz4A7btVF1cPQUYKKBn1PckpieHPX7lxEcnLplV51tbzLBKZh2w3Ls9Sb1slMfYZkGIzWXMzxnZRaV'
    '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'
    'wOpJMI/9MXKZTjBS2EuOOb2KjnAtGNYxD8tzTw2wi8IRiLnmQtfJ88i8rA9LEucVLv+aG82oNho/yXTTV1W+aKP6SevNn7ThlGfP'
    '8sv0bvPz+d95VPvG1kfGs9FjqdVuGLY36ANJq5plRYVQDiyhcAa15mEf8LDXvZVw/Is2jCb/e6aDgcctRzDRcfOeFDNo24JfUMjW'
    'EWORsJ6ueLl1ou/5qLJCQ5vbcBKZ7GdOoKtJAk3Ttsym0ZhSHTgJFfpKIWgE41OaijhyTlKc+BDHNPCdiWk7PipHPOcybptsxw6L'
    'Dpc//OEPLSLNmk/LhN3gIDC//Pj+E5RKUsPFiPqazolt9jiJ9x/D4YRU2CJFDp1fNE4K/Sakz/LLfTpTMGWreEoyHx46zvH83ccX'
    '/0Y9rf49/vT1zcbXN/e+fv/u68d3X9+9/crv/pfvP+68+vrp86uvO8+ev6P/vnn17OXXnecfX/7t687rjx93vu58podfd15+ffM5'
    'ubPqZRAp+u8FfY9YkEwBZEpaMyeRxrtfvuzf/XH3y97jJ1/3EhZMv3y5s+77KZ/OODMjMouXSQgLLa2C8Zu0Fg642I8jpwMtRbwt'
    '0tPjmrC0Zt+YxOGERlF82d67+zThn2oAdrDUiMDF/+cD/atngzLVUiAJmAS7oXBjBBnJQWOSbFSZMFdIggTh/Q4e7hgkMcR7d3Ze'
    '/XXnxw8fX76y0HkkTuDI2NtDfMs5dgeTJ0nGHIj+sUfEnKdAgQZ0ZpFlHoIeX6LRsJahbKOzv9RSsFgVQWyiq/GX3S+7u3+n/+59'
    'Ge8t039ptVRcKE1C7jz6l2hDF5lXPy4T44vdSlzm+moSx8vmr79tvv7VO1LYP5gJaE5zzClmgOwpXoOMj2ytvLI+1HYfnpofeM59'
    'G2apcS0cjqI/tnc+f4RuaGYKZBi37t5taeNxYpuwkQ9a9a3fzqv3tTZu0MR2ZShv/+2V/+Tlq3fVVv/Lf7lBsy9oBlvOV6kvCNd9'
    '3wl20zRrtiwX6vI/Dn+9td9ig+v+Pts5uQy0xf19VhT3/Yf7LZf3pjqgZy1H/BZYTZwh2Q70rKR93ZuXGZ1i9Bgewsa7WL/VU2ID'
    'yjbDj6U8g3j2MslExj08ReiAiKMQTfFM5FL2kbTN4Q52f1dLcpgrUzYXutzTil6QQJx8KfawfeqWv4Tar9J8jXbeezRnvqG1q3Y9'
    'VsP3b++i3+r8FLN+y++h2vLzzw0NfxnzekUR/VGrSOzx+6/b3z+n///09f2zz/9GrFHs7rSvq03pcmB8j+9clGEcxCWdUVqAzqWG'
    '1+GotWmtEaYad3JDwIJZs6b97mTWpAoBwMe1CP2WO0t6jSprHuYM3T0UfjFD6LbPoYe5YTQS6/fubWsRW4JtmRkRNWbq8Gp8fNcS'
    'CsyXly87rA6tAD5z3mPSxgfwhmqBtLK0jKUlo/DUM9AKiiwAcWh4js/tGc2nj+m43Xi6+PyVveZo3SEE2OW2jDVxrEWEHxYG8RU8'
    '4ksxpmczGNeV6dK4zB71TpixHPVjcZzqJZf7TdJyX9KieMtgyHLR8PxhgSTiPs9p0kREUlSOpy8aVuBRFHut8spVCYnNJjLXtKwB'
    'UgC8GlrlrJXs8dlYsrEXBcuZ/Yo9q52XA9e05jrLhsLbeO7KgX9i3ciQZ6/leF8mpkH844ldf/9KZzkd4V++chN31r98+dqq+i/t'
    'ohJrnM+A9h+7lCPtKF6msYX8pz8ZSngGmOR6Eq3Qf1jvHuL01z136SNN3sZEVrLWu3RkekINCz93DA2GK2FyeW7NjkjshZSd8pk3'
    'dm5nxZWujstKk3YcYTfUdDwzskz0leY8qVCOz2XMKFpf+XSsV+at/bUViJm7vOToFvpw21R24zeDXllBnFm9Nf5cHraEwq2LfIZm'
    'iRwX0jkbMgsVXqukbs0klmMO2dXXPVMVcaiGkcS/hC8dKXM1S6hyLiXOYILrFa9lgwjcJC77W2KR4NwoOrKiwEpNnW1cSO8ymL7k'
    'JxN2bk9q/sQ4uVLsLP34iSaps2Gn6vH8yZPLzjRXn5mpM2+mzpLF0tSbDV9IfHOvQbjymrZvql2YI/0MwpBRVvmwMr+I0btOIEf8'
    'QUKDwPfPOCpp/+5d/Hn3rmPsi0bt9MyWNwghS1oLS7mgXT8KVajbGSIxDrTPQ3ki+2Lob9OFYjGpt9dIxf7RZdJT1idMRWWSivfl'
    'aDMi8JcxPWpdsXLfv/NX7uM7fybMOda64gvefG41LGDL+dLwpDDnWNQE6/d+KxK20a90al8Ts7FrFByvwUZpENj0kVaGqcOaZ59P'
    'JsMsHYdr7uKURMp4p3KcupsSd+XtxsktG8kD5ucph6MOgYoVcu6q9Tk+GJW+KcbngGxmG+l8jQatBpRfTkRXMWQnFa8cMXBtRT1m'
    'WE8lLYbgR4cGJCkg72FIchapngc1PsyxBRl0I3xxtCF7k41MXWNsqnAwQdfHYPgvl7F3/+47cw3WvcvuE1LAi63e99KHKr6e172Y'
    'Vz2Cav2BT7Se+qq1GmgxGH5QFz3+4Rsb2Gho4eomXOnIid705bBx8jm74lW3VVdXkU/nWK9+eTWRBUgu0OQW0lomJzMlYwYXN04a'
    '+cyYHU0yIbn80zvIYMVEzGkYYKAVVCdjmAf4GIXPLnhv6KfJSzl3+FP8KRSu5m3DWGmTNyEzupYyx4DTNffLv7V4U3fattdczZD/'
    'jTuvaepU2Xr6NFpLbkzKln62bEsWXU7e2fzhD9cgmy4ktGDyK3Qlw/D3ZX3VIplX2afaSHWjolzSqjTr8R6v1draXsGOPBt8BLfh'
    '+oyB/YD12LG2/KmoXwZ4nNk/cS/utS9VYeRXmsJY6E0vELYZd0N9SNMiQnK0NtMHYGXhSSDO3Nh3LKYxsv+fJ5ND0vJeTvoAQ/hh'
    'Mht0aicCWvISssKOzhbdtjjrb0Ur654P01CEWOQmgyAsTtIxl4QbLvYgt7BMTTxeHeZPHq/Oh09aAsm1ssKOy5u3bkzZV50ogArz'
    '7wX89Uv8zM/XHASPp08e50/cafB4NX9CB0JW9OM6rcHAM33inwzeZrrtOFEoRptUIqAaqnm03uKEn3IndrSBv0jQvNyVdvbsEcah'
    'ooxhYyaVrU/pISxOMkDeUWJ1ksc8YpJgeR4u9zcrpptLb9DCVp/w2iSV1Xwc2XPBX1JazMe0qrqgy8sGI8hyQhmzqbtZpQapKzXM'
    'K+9DDIfG5bpZ5f3Hg/zkifmgx6v45SEDXN7yJ8rtN7RukryB8q1zdhp1BpP+mfjh/JJzHru/vn8nkWud6PmchLWod87xGFEM/3fE'
    '9dGumYyms6wo4Bklxxg8T/ElgMjFxR6NvTdLZzmaQTwF+86g73awE+P5lL20aRO9nOUnWcIH6zuqm308OCDdtuNcw198fvEji66Q'
    'COOk7g2FS7TvabPf2xBVeuOBpJ21KXaxhdc2I6wovaM/JMcum2MEQdgWPZaiSHXyiP5BQRTpR39kXJu1s1cvnz96dG9jLfo7bd7o'
    'yZMnEePW6J+bUbk73uMK+L0WhMfiJjSJbUR9f9a/B2z73nlpPNvNiNbOXuv/bfps4gzrxMVlVHZmdmkof49Iw/sjfeCDPTe2Ry6e'
    'mIu4hhM7QE9CJlJg9zyNYGRPbG+ys3FfpxvuDa/Y/C2Q5MDbZiG6LRi16VB/SeIuvuZE3IR361fmgtIwOYWZ6c1kPoNHyOPH0fp6'
    '9NU8fk+7VoAh6cUD93w7o0YGeM6z7pBtEWS1xdivHIJHEtffshRW65Vo/btHa9zOd9SOKfGeOMMRnzTr1T7cgPmWj7GJmTpuNdyd'
    'Y8IqHFtCWGjOOnJRYFDZ2yZiDdOLuh35LT5MMw70fxrWk+C3rhZtg3RAYyAgF+9mb1cyCX8AwGCbxNTDxLdBKii4W5SUAWzxg3fP'
    '8znSYnJlpxeeIMpLthhsg9RmkG/LUviJMtjg1AHMBg0pvgc32rO1+2v37vceGElsaFpefxjfB2yFzWLov3nINR+tNb99xD4T3nj8'
    'l+t4lbPppl5zfYMXo+Elfej6fZ7o5pbx/pGspJUDG9rY2LimDA1i46HEGFTKKKAwbSyVpU14SG3B+2aG78s8baytezPcXzjD/XCG'
    'F7x5VJv7fmV6w8nvV+Y3mPzg5f3K5Pf9yX1Yn3z/PQbbNLFBmfvXlMHkP1o8+X5b9+lLhAWERYTZqVXRixWJDMOgw/3emgaKuLsd'
    'b1hhUi+Dj6zt0rk7Jwk5hgImyTNgbe7gDHinAzbA1ldu540NzdgQbmRa2IdrD0AsdnKycOlFIqhMYFYhgKZClc5ACcKQqm3oYtcm'
    '13OsF5SZTqfD24Gt4DpB9OkWbUbzdOtRORoiGdVWxCdr4V3f/vHxkyW+vu0rPEvrjwCI+WM6mm5Cvn3Mv4Yl/3jCPw7lxxL/+Hk+'
    'oZ8kqfYZ86niVw+xioeL+OBPcqfrH6E//PhhG7qFRr4U/aNslBYdSJI0ZFFgCo6EOSWhaTqbAIGNjoTREKExD1fhIukBcX2+cXMT'
    'FqtealyHNDbLhhy7WCA7gdfqbD42bj37j0+7syf0H57SLoOCbi1BCMxmJxmCa2SmY5bAqdgT/HfmR9nQoqV8HiE6ow28dfFv3GKk'
    'Ke1jij6mn2ZwdeIojqfyWEI6Trsn6RDhPvzuEqmnxRpNKgDa4q6lNo3djGXqj2KUDfLUdwi9UHY6yzUgztuFiP+gSf/M8xDLmcvW'
    'AEmnULt4RjHuwLu95ZbxkbO3g7ejQw4WaxupYJ/97Emgv+zwJ1zq9bg0oh6mtfGFFle7NDpa+nPaVUelQV6UO1tLa0v813P71zv7'
    '12f89WRfz+9ltDbt0khgKelzaFX/7HKJPpb/PMecowTR96dZlA/wdEzvMcatJSX0iJ9Jwf6Hkz/P0ulR3mfselqbx2n30Hvyji+l'
    'xpMXHET9rJhm/XJraR3VVxvr+2O1TXmtgvlF81luw8qu2A06ZWZXqfPF0pPH9Fd3imbxx/iEPgwjxw8akH75mvlsjT/HkE0JlMcX'
    '+NX9geN5b5hPX+fDIcaOv6NZl8FK0SCtNreXdkkUBNoV/jSRS2jYe7EaNFbtpZjKnJ8dzEb4lxhAdMaDP8d/uQ9YSRYt9qqrOp0V'
    '5Z+zySjCH1tLMxrKEp6nJ+8KHZQpoqOSzlfNbPpjWw0W7In3WxZeKJjZiCVsx1K8a02TA6tph9Jx+WnWxFzovx6zcPu8YZPXeUjv'
    '4X1V1iSY8QmrnY/4oGXv/jgtifXTu0qksR42uChMZy8k/dNa4qehystXozk+5bQdHXHSkB/4v28STzPklGX8pn9u7sxnyLYW42l0'
    'N0JWklO1tVKRJ9rChVT1yveR2wIvqQJ96qY0iAewZlj3AEkeo5e1oQ8vvFGYibUZjWUsjrdqEUfMjHjxWku4pIkEEIai9CLchw3i'
    'Scdzc0frHHmHuejVGK1EbBojGP3yfA3o1wIfAy8Ljkw0wvo6SL9M/9Bsrz/aeMQC7vq9P60/dMAIKbIgUP2NfEy693rnQT72xyJm'
    '5a2GqxoQXY7gny5y3GFT4YrvLVewhiF3jAVsXck6NsQWa0Bq0jahqUF+Ky9GlWP9YJDFH2j4p2mGIECzJTAqHOAwlZ52OU6UGO4G'
    'eIH179mvOg9ADGGjIZZCJh4+d2pp/JYoNLm7ogpeLguzh7WuBGRoEJq6VgUOYG/NnIvdjoZ07+Eacv9Z27xGNTxSlX4ZBUxyI7gE'
    'ax96F8Ol2UY1nhMLhvLdoaPC9sluuQh+/m5t46EZ9ylJSzYt5rP7GOdhPi5uYY8IFoKaaxGuxXY3g3VQtcTCQqKxAh/mI+e65kp9'
    'ZhlCHCY97AMrWcBmywiigUmXr4mkFyNMsBjB7Vw6m9AM0C7eYpOw/VGGU/P04B43qGVvvEaDCZ7JJcPAdWL7wCUajH4Zh+hpGhMl'
    'AMbTBo/IUlQpC9YWNmX6JuPheVSmx1T+04c/r/7rp1d/Zh9oGhk1VQLSWHKXwwDruAl6IMmrUOUI/lhJU2Y1jh/ys6rdHhsTemg4'
    '9nO9tnEEcKbX0ARvqooDOrzFVh+Da1HpraV49+9Le8vJ0uphEnq2mKECsoTDxxe5G+ajSsQ6PdFwdfqvKSsALSb83EWfe3G0dfcX'
    '7Afxbln9u+MqX8BW1A0PA/P4S1iMmM3TakFmQJrmyJq9vHHyZLPRu+rFcqMgdC8Enb5ynBIlpUNOQRYEort3klrM81OvRaIHod8S'
    '+U396MgR022gQvyY7k2dN56YqjOMXVpSbzExUFeZsXetPCE2PJU+TrvVj+GLkupHWG3A3LHR7oK+QirjlPZEDvut4hzx7uS/eDeJ'
    'WMwppvJZVrj9MvvEoFthdMOZF9sguS/7HNV2JjcaJJi9niBUlQ6Uop+T8E3TWUyGabFEj46ejYvKo37h/V59ErTc85rtVd7l3ru8'
    '8q7w3sGCepxVCoATemX6kyGS2olSufbg4b0X69Wh4OzxahzRlA952rXWeTYcTk6rteaMqlztbm4qQZEfZtVK8AjmasV8qrVwUoOz'
    'PaM+x077lbK0r+gfQbjjY57qZTP9zUJFIE+cqTwyY4n3jKVa/O1ED8Oc++VZ14tNg+hihBxQEo69tgkGY/R68cnWE9e5riD0/o0G'
    'd2+s3otYaS+YSMNIqr+OhhpCRV0nFQ/c//D4qP/QCCnPlFLIhcQAO/KgLbgmSdUtOAwiujaM6GaBRF6Ig+/MeHVA0KZXyzlxGqpk'
    'E8unWXxA0/vrjEKLYoQcx/y1cUILXDaPcxZgfS/N0DPyJsFBWMcYLYF9dzodWsiecYwwa+pavXG8UEOz+c2b/f7KhuY3b+hbgpEa'
    'eiq+oafvw2n+/tOVLe9W4kj2bt4TwlmubBss/ubNaWDV4uZwLN68OT9Wp2UMeT02HeFHa3HNZ61gQx7RBpnhwIlmXTHLqdoQN4dX'
    'JYyI1DB+yaUVjp93r+3B37/NUU11jiPyqhGBkHq2MaqpxnXykf1Kz0hDQhALTFCFOywtYexGpReNHgq91QbxkNTD7x5sPNBvol8P'
    '7z0ABOLDB3+Crp80MSA/SMmbq4Pqwl6G95/qBFu5Af3EYfsIdaqapdgeZUzdNfuUtXFzXd8c1RQTNcimlXNFVZz56O1gYXyS0/hY'
    'QV+nGRyeDP1Uqo/4dLb+h9LN5s2OrivCrL4h0Op/VgCUjTT8FDMNcKD6BW0OtQqseCaJGNMGN8D6rQXwFkmASdnKydbxLq3JJ97x'
    'PNlWvsOvS1vi7cC94Z9iljW1971x/raIKv1K44XOKxx4mt6Iyk00FRMjZMcGWrxRXFWo8CLiCJdRHEhlo4TWvT1+XaBSmzZ8UvGJ'
    'rkYdrbvQmiuiusxtLJFBKS7pyN2MruISubnXkoZ+LHTewXAymcWxIx6eo1UeCyP2zAT1GMfBvxQVnYF+Fr9sLd3nP0TeWmN1CqrM'
    '1tLz1/if0yysQZUb5TlvlZMpbjHRLf6VhM74a8ZZ6BiZBt7Kb9yff2lJlBtHDUlbVmZs/QtgJbKG+G/HFLAZyt7wifwjJE9//EAD'
    'P+WrBkzPXZ6BS3wN7KhbS4OzlE2SrIA8NY28ZXsqV8OLWnnllvt2Uyybms9lEqhFnQ4RSt0LKfYuPceoTasH+Vk2kM1IL1+Qvvc+'
    '5Q/gYfFIHq1VB4GTXNXE5verYWurZmIahv3nWT6gMePXIf35YjL0p40VPeOZzCRkvorr7Tdw45Jz0oPIG0KyMwWe7wjCHnPN4Lxg'
    'rYdlt9q+YINerFcclUq+QgHCmBdsXASeHk1CEZwc4WgHGK3XT5N4MfZPKrcRNRgQfRnPc6SsW0ui3ixLj31hg8ezDCfAurZ0xIyn'
    '9kVBSf4IlcXKPlNLXwm9X6XzcQORjzVjnlnmbfA7x/eDu2521mUjx5E9G/qwmHqcACjc+Ik7w62l1xv4H/iCtMEk0g/oTWhOj7gg'
    'HhUwodThhdN0qBGcf+Zz4FT3EP4nraabBdwriGe69OoLtZfhim/KMjzmhZMf7Hl548m9bNxoWnZqfvoCrCdClxC8eAPI7JYzy6ne'
    'MLCw1sfjllkLHpvMp6fY1k9K+/3EBls80RymsnjCGo5WG8AZC9wUXFCyhuOVOdMWi2s2wJzL0mLde7hmJOCtKDiDKidGijNIasl0'
    'TJ8PfL7XcCqtb3jH0iOPGJ89xP90ObidVhBQZC/S+EbHcvvK1Rlz+/CurOJbomAgT/SPpzTLKm/jczieJQlq+3Jruxbxuijm1QAi'
    'UKeyXbhi287WhVPedaeIttAc+voNwa+/Q/hrRb+6VkimtnxLkQHfCYNob2jOqQTWNtppGk0ynnHATXo/YFHXz/1CnfXKYFpHnIIz'
    '09A19pkXPXvBHV9lFlLVFi3a76o0Ygm3rkeoSfXOhT3w7rWDb3kabdAI7jEsH5rlPO74wrWEL5v5kvdyP+FwHZpNGchC9feKAF4M'
    '3ISGmiXwFYaFAbgLp/e6WNxa3Cf8YQWUKM6VUVVtKDaXoW+4vAgMNTeyYg4rVswmxCNPVww4z689rYVn3WRtmgOLfYVu7ao94Nmh'
    '3NFkWL7oCM1M/6HH89ebVBGP51e/5orIZAxE45JVjdxstMpUyK+mq1Z4zgLVtR6pbKbrMrhGLj4eGB+I29UQLI5/q/iA3JLcMfaW'
    'oxpYZ+9Y6m4h9orFCzf0wBcfJf5VCwPOERnfEhija/tba3tofq4ZbAb48RC/aAowXo8cbqDnwBDMSSWkjCcl8L1qkngeie/Jb3ag'
    'cSazW06F4i5VlMtZNQvu/R58h/8pnRqJr5kTuMC4KGAECzr7td1YhtMcc+c69iyBEGQ0aaZIN98UVYgTmB184l5SC+UL4mIN5+a+'
    'zHHc2lF8zTCgteb6bGOonw05HzbwkaEkO+cPxN3RGVJMGPx4xuDHpwxOwwjy7D52gCQX7HAzhX+Yh3+vDjidinwxHR960WHiphfm'
    '6TJw5BeSEKEL8hNbiAdB3zWwjjyULh2yl0kC8GLrXZ/URJtBLcCGuur0uLjxLgPguaQsjY4mw0GhDlFntNPh+2JbtFOujmFTBJm3'
    'BN/dmb8HJzCCWYd6RBn5Tzagpj340731B3DYf3h/DREdizS3jftrYsv4qW8PLnjxzTwFxXFaMz7PeQ+ee8uGScgP5aKW0KKFQZll'
    '4poMwAIY5AFkp5LQOlNeIyRCUG6Dy9l8W/IusMq22C19f7FltsqLwYebLLXrjSbaXzNDnjO6usGwPe0psQiT2Iq666wtCQwdfebW'
    '0vc7r1dI/UJGs0E6nIwz+CkUS0+f3IKXuGmGc2+I6oxoBFKd5ckMTz77T06nv8KXOoxbeCkvTYvpr2gQIQ+mPu2B3+TeDZGG/QXw'
    'D2Q/4MarleBw+xcxKayvf7fG0s0R/f3w0b1HstDTw/cp2Ho5oWlZv3+fjXszyUtiforA5H7L6WV+yW7fWvrTGivJByRueD8P56U1'
    'A4CGzNBWddDsEa2L6HslH0wksXmTL06KcNzcd8VxT7K0KJ8VeRo8ZPcc/anWZLXDixPHb6NBbaRGgU+EPjWzVKFnqf58Yp1X8KW8'
    'aL+Y/baxIWtT/PKiqD4bpszT+Fk2Xvnzc/8QXq32MK3+WiSwYFVzfNbGw/vmx+f5MFNhXuVe7cNvdTX8Rjsf1nI1tZdE9Ggg5VS2'
    '5oJvB1tLH0DlQ54wDiXR79PH/N0/v+adoESEitf1ZVvn87zWuDzltgH9Pfg4bup2DB+4K4ezeFr1wFm1JVRQcgv9oGGh5Zm3ot/2'
    'seYUqX2vSUyx/nt+M5LsfYAXUjgBkoJta+neBlNW4JRNBVV6e+fOouaJ6tXl2/XX9x4Rha6G83ivYR7v/S7zuLFwHjf+E+eR+P1S'
    'Rb9onMb1m07jxusH9797WJ3GjYcNfOfh7zGN9xZO473/xGlcf+hP48OF07hx02m8v4b/1abxfsM03v9N0xjetlfnEm+jymX8FRN6'
    'E95lvqovbsTzdLgtRcKTwHyF+bPwj3DOKsaXtP/8x3+HwvfP/+t/8D//5//X8gICDkaCstAaZP2cBsnXuXCOepdBdLA/P09G6div'
    'qOXfSbTDVuRFLCG0CDp7N/oOJsv4R2NWgzQsMjBEYXZPkIOao0+CfcTy7utR6Xmq0kh3gRZ+b0/FZGpjxyPPf6HmYNC47NjX/2qV'
    'DUhNS/6kh6YADfnIvQgPvv9BICHLIPcerlXOYWq+arczVyb/OVMi8SaNU3Hngpe/Nl3/U+bDhsH8RknPtdMo7KU9ZE3vlx/msC56'
    'v95yfCWKcEIRpli+pTDM8Jwk08F7vOOlU0cBLCKbSLymAvvMlR2uf2uHwX66st8x9zf2+wk6rx7rY6++H1UDk3c+MEQYtEpUOLhc'
    '3PI6j/gbyPsjLfgMppVmMvdeByepV9MnrUv7Ve6Zfl9LXwmh+MrGTPbkryfAz35keyXb5BV6IzHuY0R11KPj6fv9NiNM/OztgC9o'
    'iqVoh08kVZ9XC/OUEz5vLclvBJZhrpraoRWrNmInxrUTxKjxskq8OIhjJCtYa5zKdDiouNI8h6+4prmhVRQ2Ic3+GiqklgPcbOxo'
    '2NiRdR91nbmblY6g7JtX7ycDqvnqjA6zMZ/BISEFqxqowLnoprtMWRI5j2x2ep/0I0ZU7GHWWib57a+nLW7sV9JUXwa0AgkGNKXa'
    'YIRPHstAQPtLkY5cpjKdToe5pJlePRkPKr2saA+dgGCXldoaesCbxR0srjcFLQb1bAzUghqI/2qswi+ojmUmJJOVHziong1Iqzb2'
    '6+rBNsyGAF3Y+lUYjY59A7uSmaWF4/C27u86Cmn32u7DHf+7jsA2fdUgGO5hMi2IcGfZt4/BUCZqr7jINNPjKm+lJ/t0DIUb90ds'
    'glUQdPE7bNj/rMNgvcr6QswVx//qFL7gWNgwLf6W0a6OsjLFHK5WlsENqL7MWJ0Ku62tUq3W77BW/WkXrX2yg1T5sT/95klY/NnS'
    '5MCZkqfz2VAMx/3VTMJMi9X1zvqqK0tH0qhorMBvbMmzIl+Q13p99a/v323z4FfyMT6+D1vboN/lSzZ3/efy0+HQs+9RkiNhJ7Mn'
    'YbJzLmRePdaxyoNsENGIjGucvvnh3ouXO69x4eiA+Trl5O32Rw2rSzTBACARvksu/x0dBI0SddRWqoFCaoRuKcTeRjRWcVzXVjBB'
    'hE3FAy5pazgVpLGS8Bh/cCG/YRmUa+5V7lUlQyAEpkShrzzAHtO8CFRwfRCRyjQ76nhYPup+UIFdbP1OJ5wAqzcnm/6oWOg3yP9s'
    'bQ+apV6tQKTcmpzhNeT0iSYnc1lVvazVJ5AS/j2fhgmro9hmNOMCSYdmBRYN/JMEySyQQMd2BcAt3PjJha6F38JA8eNT3veShRs3'
    'CYsp5kPCWyCxbuRDwMOZgcNHR4qSzH5F/IThkQ3guveFGGOQjBtkQG228Z9F2bh/9xVxebuDteEJc/fyCBtHhmJJGxmkuDZJR4v5'
    '7CQ/ySzMcg1XmbaGACtLk78mTbi97fZCdRsWSpCavZXyigOhutKMLFDTgjO4f60du6CmIZel3OYpfyE5ypFjHBOSLZwO68rrw5lf'
    'OzucONYny2r/SieLc6UbEPVfnTFdezdZ0y2Vgma1949TFgyCFL5X0WObd2Zt32K43k79PDmlCkf5YMCo2+YNYrr958gBfGaqMrOo'
    'lkAvtwNGZIr3XritVq2xVanhfTqjK7/PxnP94uppYJlxPaapQ8/nrSQhzm97g79Vk7POFc3sprM8XTlKi+lkOp/uocEeICW8sCcu'
    'Qeyd9m42AOtkvxU5BWibY/gFIJ0PXUJvCVbJBocZB1tomoKynIw3o9OjTPAjyslkCG9GpCEsojgl4uXk2af5mPhhgjCBtCRyG6MX'
    'zp9MIh0AHbk2+3VL41FB4kM2ZuwWEjAGnOq8RzKb7KGTPDv1wNlxRfFxvM1VYkyiTD3+EvWpM1OAj5ZvOmIoPipCgu1zYF0RxyLS'
    'p0kFghonl2ZvISr2yJxbSBpFg3ysr5KmPvbvXGixFS12OT1jE4R1ZpxpYXVDZ+wOW3pxo/Jjxa+0HHRBx8Vg8OqEUfuJ4SBlXmuW'
    'wUeIFtn4pn8rRXaJC8S7QpF7CcgpnG9sfj95Sjk5JAbHW6BXjm2WUna/ooeAEsffKj0rYfEViUJ9gag8NMYx0M6opQ4urRTaZTvv'
    'DSWFBgk8YoPmSZNRbhqUc9mHm4YWHF/QamZZ9SfGWuCbWvzdLJKhHmMU1YlMAHEwsqt3l4rKphPeZXbS6ws2neTwoGIBggFbn2jO'
    'jNuIs4Ia1uGPK8qnHV2iFWw4rIz/1bwqtxRnSv5PvelWScKcHUcjIHR5Ly2O+s6bV+9f/bi98/EzkNRbBasQKwNRIbrsANfyFpy+'
    'fgfPkP11Rv9CmFbWJRuRpFQugIeYcvvx5g9dVRZ4qbVO6ZfmDaPNJgpYNJz00+E2kSlsBlSDRQNv2Oxo6E62S8PTeRjEzXkHQURA'
    'SAh9tHEvxry0BDdFpLfRZKJp0oL6rGfpwXM0GWXV59Xmtk9zDISh7bACmHpu372wS2JPIL9hf8DNX2Lzq6Paq6ESO8RqAO29oYdx'
    'YvHUSOEZ07FeEDMAOo0wb7TIqsZ4ILk2L28xNNV7KChxK57OsgPS01f4unaFlWuShzBu4goNhNxnvE5Lw+qDCukXUTxAetrU5TTP'
    'gmU9rC9rdU35e7ly4qgw6xj4tqdmBTx3TT7pzER4X1+c07BH0XxMilURnU/mrRMGnYM7Lx1Stxo2E6ohOwozia60wtwz43zgx5zg'
    'hw82FBrq5Xw5CUuKq19lH9q9hapie/HEfaoLR2MSXCTV0x//iC0lrsC7+nLPKlQX0TEdvzwF42NkKun91G0oj3BucTjqRu/efnj1'
    '48tXr599/25nm8v52G+Masnpc233HzAmX1HlHFa38+LzhA6PIuGwGx1GSRwUWeg5uKLQ8RQdnqSvXzkgZ9FIUJWjdph4LIQz+/Xv'
    'CLLWmC8d/vmP/+fOheQ+YzF5zAHerfmYNyjQu6zZ4t5acvnPf/y/+5uh+IqF9cQ45wXtr4jZqe4ZeIALT8FRg1C1Flprcb7zY45h'
    'E/91Wg51/9/n9TRIgXcu7BfFH+KyQzPEF3JJcsnqVtP7cpJIEq59JkmiMr9UyV7+iYAHmxGrLByOtzQu+S2RBKLUUCj0B97RjTSd'
    'l0zupGGQkJaOz6UAPcFndqoO5xAKrxY9eIRYgIj4+yHOtqoITG001BPxoWXd13udQV5AfRnwYqibLZ2gaVGAVXVEXIlbE5y2t2m5'
    'iHBlTnfRgzmSYBXcQ2YoOqWUOuvvE17Znn14Yh10zZw/n6Xj/pGvT9ApzjTBWgjvDX+NPmcFE1XtI0yBl/TxoUoTNMhE5pd/h9zV'
    '1xW/DA53EFSM72tHrKJdtyOYK5eG/wjfGI1y721tG/iYitwHv/OmWqd3wF8byfLws02Rqr0nNCJr2Qg06iApK4PZyLZg1tOOpHZX'
    'KpuwnxsOCC3oeGy1j72fiCw7x9l5IYlXbd4ur1udPv0K+3n2/abNi+UO5fBwmAhJxTdZlTqtLVolb7PlHF5fzHuooJwEIrFJIeeN'
    'NqGDgN50FswxTWrwna7w5uKPRNCLkOB/CN15H3qM79xtseIFpZh1V/zB0Zn4gyWfVpUOjw1QPF7PZ9CCu6KsMl8sJNt8qzAaYPMq'
    'Bx//mzglGiPO1CCQgTk7ncLw0q2oqlg4NiqYCL3E8oEqz2uH7K5J6aAvS0d8TBwBb561iEXyDpfN9Lbi5hZOnmFnCEIbLUZKObsC'
    'HTQfT+elCPdUUI4EgW+IWjKO1ia/UQYQuesWec6hp4jIETQWrlsekX6rH9kyTRu1oPUKmh3IQtpvR0g9gYMVVzzDTvQug1ktL6Ns'
    'NC3P8YZ9EnNfQcZtNG3KLJVEDPzpFYORPuQ6MQ1Ax3tAE1GYwYsA6tIWDSa8Z1k+9v0lMN30HOqvwxHAkqCCv9ki04SxWfkphOw0'
    'NiIJmqTwVijbWFuzETFnVGU0OeFZr3ysHayMiMdIx/cJMzjcjunMC+60e+Xdm/E+UC4h3D6JXEU6SkKWZV9tug3r53Tzh3H7xEjm'
    'XCPs6vr2AJYOkood0DYmo76t6YQJjAUymk5RTqa4c0sP+X4o9uL2MpxKijEIimyZfRV7GWvs9/ili346zVxx1aYwvmTxAHvD+cwa'
    'oPyOEpNzzteq1IYYMghQKJund/JRNgusTbBZj4rD6ukAVsAvwcTKipTLhzIq4ZWTBWnocQvzrvdIiMFGh5M5idC2d1SyP1gXKk0h'
    '+US/SaVdbZUpe83LPlOcQld9gXOF3ZI+f/y48+Prt+/eccTep2fvXu3svCKhAl8jZbOiYg7wm2C/q774XQkLj3goW0tSaonvFlf6'
    '7Et6uSR3pVtLOKwOGe+/K8+ZJLXQk8er0lToB1oZ0Q1Pm75/2phzo695CPiU4Q/hvOuBVRE62Y6QRiAIVJXRp6qLWixpniIW6g+z'
    'yWi3INFlDwxhRAwUQZJF4sw7Vpj2xG2jbG85bTe+XaCFOC/ep0ATYs4CtkzM1QQ2Y7use00z3CwuGJsVDwnpm2bj2KtDUzFMp0Vl'
    'QNL57WMAPZFCK19k6zDMe6V8U4Phfiiedvr6jrFtXrH1ktVAW8e28v14MKl0QZQz2S6JirxUVVz2c1YrO8vqZb/heqMjRCfXGgvV'
    'OF5xJ5n0eT2KDgtwzQLubusPB8/pLOfU0Advy5TIV/7eRr4KcZqnIvnhofl7+wjMkP9EYhX5SzQ2/Jk/GwwgLN5hMbdxRaTHZPF3'
    'vMN3vOscnEZPtqI/6anINXWE19fNuaCrKKNOrFRDa1/gkZySthh/UVAK0BNhIf7CBmuqQJ4zokZccPYNEFX0WY7+f/7jfzBlRRr6'
    'jd92ePk2biuC6eLHn5mPVinbZvbwq3pDprd4yKN+b4ddvBpNj9xlv0h2MCNDxCw6JHsdpUVuF6l4nQ6yxcUP6K0t+mxeThYXRdzf'
    'Ti6g0lyckyt7Qw5KQ653g/iBTfzNJWH+d2fKhHNRIYtDdtKODsZ8JgkR1ri0lvAY7Tg7/Qbxm8EzBEobKPtOvCHB41PGd2r2LQ0Z'
    'kuAwHR/jZ8ES+1qg+yB0X96VRH9ZDI6LvLgAG5wYUUivqT9kp1abwK30i3I2XP53yMyHEBYAZz9k2y3rYnK5CdokXpyxWmcOKPfF'
    'VEZKgBP7RTjpr3mJq2//JQzQwctnRfX1s8IWeAFcIP+9yAy0Mvwm7s8BE2CL44TxS1M5PDLvjbLjlQhUKNvOa7G61nvFi9j1pzdr'
    'lS71qS2lB2XQK/bntlq1bUFQu1+spN9uTHlZH5K5giNKaDmCuLSV+PTxauHosS/5uAlG5b0Unxtoyn4RFk+8O8usQysANAcxLbiZ'
    'MRbhWuWLq6pvVqzJ/qe8E4N8ZQI4dgKv3Kp4lkOvuG/+8UvaE8jNgmrvfqn6Eto0Lv4lYriu4fiVxn71jMqCBFX5yacPf3bbZTIN'
    'CAgOUP77V76TWr0pfRE011DYc6syRT3XFBQ0d1l11xaq0OTv4npU+ak20zJF5r23B82jZyJTXLk+uHoeDk0NUl96TA8ZZz25rDUJ'
    '3lF8e6Ms3IYtioj4a4ZoruBcW5+p+d7k9HpilHIhFcpN6EI+ItfVMgy5IHTX0cEdrdwQQjDhR0EfIr3X+vCkdmqBh6qnHTWDM0N/'
    'mXasgGnZIZMAntoiTvIMC701YpwU84TScEzi74H87q5XK7M2FvVKWok2vLsVf9J4LPM6VnnR0+REKiEpC1ndSEbIkMnJNWuk46tb'
    'Zfny5o3W2JzaF4JW6+bdni5BbudZ/WNahfl4DMSz8o7Zwut6Zqm31i9LoKNDeOayUE7v3MKbF7U5MHrxgf/h7N27u4a7jXAu2IFJ'
    'nDQh23t6L6vOghdTAHTmwCdfEYyvnX8jLFeXIPh2lcOvmXYzcyyeB7+2OVmX5s4qOaOT/IuPezvI0pbfncjT9VlrsO07G7a68EYH'
    'JNn8AiaqVi0x0rN1rpwM0vNWEQGbidqFqrnJvp9y18keSuMIxg6k9mN3pfFAPFfq0nxgQJfOQ6HWFGTjvv00VkIaCcIK0U1aSVNv'
    'zX05AhAN5uZ9QaW5ph/XNismN28bukoDiV33BaIp3bwbVp6u7AdtEz38G+jhODsXj9fiiISG/hzQOJPZMS4txPD+//f2dtttJEma'
    '4L2eIsRUNwAJBCllVk0PKYmrVCoz1aWUdESqcqsplhQggmQ0QQQKAZBiScwzV3X2nJmL2d45p/cJ9mYeYO6n3ySfZO37zNzDPSIA'
    'UjXV0z8pMMLDf83NzczNPluU7gLD7JODWytsFAbWpWazvsPuUou7/9OuHwayc56lhydd4OPBhNpU0oYxsPS3b/f2Xr3kmXVWLMps'
    'MeWp5SfGxMi6VXI4gB0WuoUMHLT+huz/1ZCgcjMrNVWlTURzqZ/Ct9SNMINLgpP1eoNCP+iW58fNux7L1ZdOhDVVj2FPxhidK8Fh'
    'OiGSWTKDQ7l+4/Lh9RNYEnqDhGen7NAsSRUMbpqWME/NT2bF4viklk1PHbGl3hQuPUx3QWfTWTZc5A4zzYIq1au1PJzBkCSjSwbq'
    '4sYYDXsp2iZURxrBpbudeVKeLXAOoxlhC5pFq4SOjRpl7kdj4OfLeQOReV411r04wSiFOwohyQfD7DCFBzW9KNIFhLVZ8uT1czhG'
    'zjKZJZg30Ir53uYlYexkRsxeopPCRMAjmY+01Kxzb9+8KOkwqzGuokZcguSO1tGRFMfnoHLx41S/5jKpgWWi9kmzRD6LHn9biBIn'
    'aw0jPB98X8zMg8vKO1N48Ogp9+WcRhCDxePzN3QhMf+vsDeQozyE8u2qg96pU8u+fLX37P3ekx92ecGs/mzpcbL+WIFaefsiw0hd'
    'plA6mUoJuqdsJt3FBBxoy86BiihKJo/E5elrZjf59o3+w/9qkif+fM7/PvuJ/7zVt67M898948/vnr3QR2/t87daJzIN8QdyBPHH'
    '6zf8V1r98f4WMemE/h/w1Y9f6z/f4PnXeP4b/+u37tdbbeiV/vNCO1eB8PLPJ9rvn7T/P76xBgmlykcE7NdfSFWmv5CuTH+9sUL6'
    'jxb87vnvpQvg+7uvn7wkSOj3r17u4cetK7dU37159dot1cYfu7plPvPO4XN+hGTdn/W/BV0lPpOkP8/lpBun8+zzpHBfnB9/lu1z'
    '8hmc8zPvJj4jZu8z7vA/A5XlM8SPz+Son5XrflZu+xmihWyX9PO57PDic7oY5cVnzQvZu7ORhzcMzcRw4T0DM2den2UOIQfEGEQF'
    'j13SOfyhptPrcs2ZCY+I48surkf5eRjodJGOT7FxwC+gLQR472ECU3j7igSMUq3Q4ZpdlFiwq1LFSQMDOQ/kmFB7Va2TcDfDN1VV'
    '9QRyiwebm0Pe/HZwFLXkF232ZCmKuScxBTKfBMkolmZGBbt4lIRFB/PirQzJUof1k9mCd7+e1exLuYMoFSlKYDIw94a1LxMfDUZ5'
    '02JyOkE6IlkI5TxTHGHpsTEgl/86qJvdc/m7Gtk3mN/Xpqcta5fLsaw36jFW+m3ZhAg4LXe2ZD/l43mx1dvIdeYIr3DNiGpwnlFn'
    'kdaLl95xrldgkH5GDP/n4/zo80U2nPa2sWF/+01/P13/8+b6f7y38ehdeXDvjutIy8iY+MsGtmxReZAt2TDYj3AY5KqisyV3KyQo'
    'PtvCgsTp4yKY2nhFkKWqbM68erS2ronDxN9ufjrLqBhPClgL5AidFHSynuFOfnv5TPeaNWGSWvsQp02LqtrTNC3V3z/GHlGpqswu'
    'SxIyABUX/HnQJE24eZAfPp+0rSLS1t7frFHkOXOa0C/jobzdbI4r7SfnDSDZGgsy12P8T0C9/umVc5/gSybWFf4aeivLn6EjvbtI'
    'EX1LhVBzK77t0j3zEnjjIRKufyYE+eeTWe/d0JOwSwotc2u/K/73cP+Pjw/uPv7895NhOd02PugSn9MxD7y9OpYqMxITa/N6QPR7'
    'uPJEQRYrr2ka0lToPKMXMTmVVjqdmIjH3NyRZ5oFiLJtmQITFQd5aTfJaBDT4YjDFXCOR2G60+Z2pWRIM585J4HjW81l1+ria3dX'
    'HfifJLj1USWMzi7meCHqGKvlBVSthOhZ2uTM3HTrYXzOlvepftG1ZEad41NNRq579zmlkyjOFMGLSWtMQLdMz53aCWUkn3dK+Fzj'
    'IUTcyUjPD7oqmY19ELtMvPTdDG7zbofeBoEHl8svrn03fwf4Grz0j0nT3Zr3v/75yI9bKo3oyMUGVJmYfCtRDIH/3l16mm5BYPGa'
    'x8JEmHfTwf+tOfjbDHZ6SxzZyyzj1KnWExI+Ll6E2GIf1PquWE4Ruur5KB4YPtnB0y1PECvmYieciuATv92C63ZMQ3taeZ/Fxn12'
    'GO9R+7gDoqX9QGNA/RcN/Y1hdOns9Of8NNdZiidJv6IRAikiP8XuU5WaKBsx0hkDQ0U1pf3kGzg7JNwtPyPcudousgmcbs1oULzQ'
    'pR0ke/JbM05brAKySsLycJ6XSHFfciPhzlAU5Gwa7JZwOVXuv1n3b7CgTeLWXRi7KvPEgZ7wqL6i9XWHlq4WU3dCAVKiYKZ41nAF'
    'cuOvrcB4bu06Coks6xq5MKE9NmYIt2NqiL0YG5Si7qfmdg9q+S6fzS+rs2NiFt+JO1fl79jD0t5xTxoDq/Zkg5HuBS7FsrjDDPzS'
    'ztoRlP1Robf3vObvbUG6gXvAYqIxZyIaKlCBUENKPyDE1vNRQF1Q+4RuAmpp+jfcnOA18q1+SCTwhNxI3rgAyguG29NAsZiVwEdN'
    '1bzjHCTRBfh9KgQDTVeMV5uVGE4201zsPnSbUzJYFXhaurOxZkmMne3iQ9Stqwg4+IYeaaFoYLanssuUvjxun8y7m70BaKiYPJkc'
    'isBUzJ6aiWpGFSSyEzU+BAyQFxX8GQffwFKdZyO/wRnr151kX3FALaKJP/606bZRVK9XDmDpbCVlm1xSVqJI1UAdUwFvnp6Nuodn'
    'I4vDSdzVT3yutwtk1aZumZEoKDf7mB1iSwtVdTUY4ud8fvJ0d9dFT/ogymVfsYtWVCOGqlPFnQ8tS+flbiVfvLNTTtniYz8HHS2B'
    't3SwaRhuQgo4TGXszGrScBxt0rKaOEdKeAFJ7zTokG4aftmDY9pZL5SArrOnWGMsWCXUDHSTqqoGLY6yHlMHjbIgJLIp/tn81uEo'
    'rnW0ZIvrYDdlsq9+w2ejgyq0jqnxKk3CYnn5JK7W6GJ3DvyowCnzbFQP6F0ZmldMavkuhrR7heu7U0WwnDzoJydf9zVjEyMh+8l0'
    'llWehhN+E7jUobod/DcwCwUmgYQGzxZMnopceQFbKjpTSGuiJ5Y+a2CwBEc0yGlpalZMT6KkVWLXmSflBifdJhiVKY6UAsSI7jTS'
    'm9+jXjifFQzNYqxQLiiZEGGIQFMs7MKoWasLUIs3oL4jrqx6lsOfU9Ro4r0O5MfVWugaTrzW6eOHQwAITx93YilROJ36Nn0h1zL3'
    'cVVylq962pG/ltrFaPza2tjouK2+mEHcms6Ks+kcmV4mp+igcEhcNVpjlcCG0hCa8BEzyLjqwo5qlUB9q0xw1xnfpLQssH6JP0TU'
    'OxwvRkJKnf9D41Zux0/RJK7/tB6K70Fn7qGqFawe3anpwph7889pLP+HhyntjljvrDxkb6+ACef/eLiRPlZ7hiayoTznmbVq9+bs'
    'hvIRQXCln2g/Uv6jpLGi71pM10D72omzVSFo7pGatUCvTNv64eGdT/LkygjT/vCJkb/GKKoErcZ8GzPB3j5+OMdNBPIEFhfwMCLm'
    'rD57ODeTv74aERO3+i3FLEWL1VRtlA817oa8scsJfT4Cmg4u7Jw2h/JhgZQKsCc/vPaYAMYaXi/moYQJbwerjjpUeMkwn1kTwSnF'
    '/L6WpT1K84wkch9fHXXZZj9M5s7aV+Vzr68vQjBri7viZgTVbFc3H9jiOZ2M5Z+HYYpoF3uQ5EgfPFt1o1FVLgvYu1HJ4cxbXLvX'
    'J8re0TkfzL8tRjkdf9Qoi2d2qYIbWJ5AUW3wvAd9fstcDN1ZP7lJY916a/Dsl9XmkGiypFDJtqCeVb6/Pp66vkhCBn6RwtjVIIt4'
    'EP+zZNZu0HVsNWLqAcAsOfyCtZAljubqsJ9UxLAPMr6X3D/wo982ZLTW0YqiGlLlfFYFKK786PpZirskCxNV3LI7pFbd5zTTtWyu'
    'ilH0jKLCKmsiOYLx3GHcVA/VX8X73dTFefXBYiEv7Bp3hoWOl0MZZb9e4gASd83bpmsvthsGJnrpLO8TtTc6yDunzyW2q2vqiSIU'
    'P9WiGr6wTy3hmAZlVYzokHQ4n41/l11iybIB7rHlj35yynfycSx1Vu5tzSDMT/KBiLRo3iC1GUIRdd71U31/lK5bIzsZB0pRI9N8'
    'wOii/BmpT/W/vdX3Ga1cG398V97trq+vf353F//7+f379z15dGfD8kwH34b2XK9StI2H16hrUumaeuWxp/DaGeXn9NqBq5eeD0uq'
    '98BvSUODLGb5n6FQjZGYq+P3mZ8hrBkJtxEw2z754b3BdmtVp3YFecP1CxZjx0JJeBDg5zVNnC5twgvhy+lhLx126ssdSBfjXFWS'
    'ttrdHEdd7xSLOXKykn9rktmOt9Ys30xxoEW1lQCW9QgdbttMPacv/yTFRFvP/C7CdzebdxOU8AEOI0x+Nv8e7GYvPe66x1gJBZEC'
    'g9DHF/LLJtbdorYhLKSVbJbyPnHJWJZ1VzEVifjbTZkdoZ903jO6KrxR7tdvlFfPN4FKw/luabqZTEEEO3Tf4YYilemOejFjLPsH'
    'vQP8BTCCI/oKr1Bz/SUj4ZKdQtoQxyNNu2E/r/UFCiH+7YYeN64hdfSpCfp82NRkguOsf00jChDbM4/f5RM+mqXHch7P3Jy3xO1f'
    '830xbe6P2srgcN1DnlohhP/VhbndtjLb7ZSyDIXAsu4WZSQNgtO8Lsoc5eBT9RpAiDtGWVLi/7Q5l59/gFax/AbZuioNYPfgOnm+'
    'izHhyaA4OpK/VX+p/nZHpTM7z2qsMe4mS/k+9uJPVxVtHww7vIy2zU/Zgt/NqbhMzhblnG6p8ywdh1qch2xVx4Nbf63Jr0LSanFJ'
    'Vs/jUM5pLj+MsH8Tc+NwxcFQBeJgh8bGRec8bpa+Fudxv7M1fMGVg60gdhy/gnpeuaNP9ih1Lw3nOG/xPF8ay3Hei4wg51FD9RhB'
    'O7r9exJLezQKJ/T52XEzHMW/WR6P4rhHHJSyNCSlQbxlNAoK5Tj5oqA7LysphX8nrDC65SWILiGHiZgDb/Ukn2+zDDGZ1GVaL8yy'
    '0SDwEN59/3MLdKmSmMI5bd9Sc6r5UErpe63wk1abaTgXvdDzQzF6tSuPpI57SWf6sRPZtP1CqLd9K1JGG+LrNUcvdDjQ2Hmg9bT1'
    'iemoiezRPRynZ9NuBDicnVfc6ME/bPZDZOG7yebgP/R61ZiqxhdT76f9yaxl6E/7qCxcCP/4cNL2kgscZIupGU5WAL3akvRDd7O2'
    '8dPhrH7FwHEsXYO4t0uLVV0FjWtX2y/QDDDOZ5LczZCNUgZU3aZ1pp24k7IXnuiFLk53OIymk0u9DxYp2iezVy9meJbqbXp5Aks/'
    'zoSz9FSLDGFXgFuhgshnwJS/VFiywa3rhZFPphXE8gNTUu0E1miE6pdg1G0iACboGrHlb9QK5s1ZFJITWadyi94eh8iTw2AQBWUu'
    'lYMcnhT5YdbOQn58/nJvt4WBsNYa9vGPeNaFi5BqsYTuZbk2bA4Ps4IrLX60HXyzx1J1gB8pBfchImt81AuW5EdQgY9Wglal710k'
    'kxXb9SV8oof2PcUR911bnfvU0zZrhGkACkFPm7Hwfkba58FfXwYzQc/YOEi8slf4/eUrbmXT7L96sUjno3sw/6EPPK5HLQEyGTE2'
    'W4jmkca8R8kESMCwMAxn6exSpidLZxqgU4tu2guDeY5ENSujoKKyXhW0xhFcNaaidWqr8xO4nRjyMJW3EfY2/VQsuGkkHUDV9GgS'
    '0u6Y81+fPuRJ10Uv3kvMBwyfpIlltV9HQCRD3Wl+VMxnQ4IOQoMUPzoAt3ahP67rLsyHH5cWFfFTOm3iSye7v/8hmcocTOUYunc2'
    'z88ya2Sej3nvTUw5q3hngNagC09DFcTe8iVvvX7BFebUwOLCt14p2UqmwR4Vntad16/+kctIRM4LOcY24Hm8KcfhHGgSuWbO3f/t'
    'JkKCM/li1DnoJ/r3WT5ZiH6Mvx98I38Lx53xr//QR9j4JX9/M/j6N0CNzLJT/n3/Ab4Uuj/hn88n8M6dCzV1LoWcOgcH7jYSUmNZ'
    'uyLeh9TQJwzgASRodjCCS00eJihT2dgn7tw/Sz92EXWE30fjopiJbFmZNibevm6jxNz+84KhIhfY/h/ufJpcJfIf5HmUf+irDWx0'
    '8obOFSb2g3NSP082HrEfzpVWBboLIcFijk3h9tSFrKmpJ0ifbA5dGS4vYN2b8kpK/fQ6jGKbK4BL4Hzl6Ys6UriyNF+h43gxANVd'
    'fbY/SH34y4X/Kxgy/eFJyIOTtOye0uLibsn0OQBG8Xw7aAZgiHrm9xPgivUTh8fVT9QfmPgcp08Xs3N4M+I3oXdLFUCIhH5+bKDV'
    'nU6chkeRcqDIEQXnLJeZm2fdf9x99VJDjvSnhjHkR5ddHa6cinl2wQDPBtC7kI4CVSo7QgThYirVjpgZprhlGX6+nymIZRavF8Ih'
    'LdOE+h1PwLKSPxcFmSSCDtOZnrGp7O1JxUIRS2/Bl6lL/FPZ8ChJlofZxLly94lHOhwWH+HlfhFS8nAAARvb8LffbMrLk/jlib38'
    'xkNHajNAAB0OPspbVLCRPJCNzn/7ySVfXfLVib3iv/p9tT4fHspvZh35tvjIrKTYF5f4zwX+c3K1Bt8SxsU+Kaei1L6BtePR2sef'
    '8tEf5P+TsyybryWamYXk8WgNrpK4Rdd5uHq4IW3o9XNwdIUkwp0mvCMdj3Eedv9K8jMwTzNRGo2XSuN912KE5a6PWjxfIC0oLtMX'
    'IkU1E3REWQtCl2N3Cqn62GspYUydR3NwbO3ygRr69GUFgGp/hxiotG39+Gp3z7s3RcedkoSvW9jSouwsu2VwxX6Y5XV8tA8PR/m5'
    'A2VEmXVCva49/kMoHcBUohuolK2WWfhynMsPUdlJ9+HwcSyjrstaLz4+3Bg+hvTQfH2WHtJ3UXYxCvUG8D94PlGm6/QFkUIYpF3O'
    'gckBYUT2NTUSSCTMYZ7y2LdaBw83ZFix80QIfb5iztyQHez89zm9alVacpMAiDi3SPZBLbNFJd36ZVP3qHSadzsb8t8Ne+MCq3SP'
    'dbPZzK34NT3dcLF80i71QLvVkhoGZ1lZIkgbwyCl6nzO0yHZ5SzjHNYW0AIRQrkQUxDU1zaf8bADT5oKJU2mob6f1DHbjfB7lT6p'
    'MUdg8Oq+fcsl1wY8MbOZANTUhzDtD+7e2/njnU9X3d7n/XcH794dMIzp3bs7f98JPS9P8uMToup0MZEQUmdnJrvg/HPG+vKQ7+uw'
    'jJoLSj+xovjHd0MhDI6ffZx22dEuK+rJydA5zuEYY4muwV/BZoXD8ueHkLehRnMlf6LqlCiJh9lsKoRDswk3nkYUGIdBl6SfeGcO'
    '1g7uWUM5wwicSS7qe8vwDbUa17yYX3zVuPXFFKWgu3WR4cZcns0VU+Skv5x5VKQm74UzN9tVDgzJTd41pchhtYk7APjFpLyA1cby'
    'bWtr7l1kKidB/czLR2E2LWUKwYksR3GKZFW/wVmdAXXd3uUTzodVz1L32Oa95B82w7Xpap2yoxxiJJVafqzCPwuw9l4rrjTwJ9H0'
    'wyRoMa6whjVfba3KPzFgOLE34p9aThtDuTZA62hRjQLkoz+JbjiWg5F97bkrmG+LYpylE7/47hLHqTh68QI/zKPK9OYiFZ3cq2jS'
    'V+8m+E3JXX9iAq4+NKnMweajZwPqoV1ud6mxsr0IffhFrw5Dn1/mSMQGZHjd0gG68cztSgkdihuOanbLcqUw0m2zYTcIl7vFbB7O'
    'OdDjvP8uNBliIVpOFYSODhXlcOB6QdNB9rQ4g6uRCI32vF8FwvRpMJjgFupclDShEYQrI9OjpQStqsXn1CqEylP3mzuUC1UiwWdY'
    'mnPEsvpLdp8OSQvVQuTiVY9hdVccUroCWtwll1ENyD29AtOgamd8C6od4Yr9GVyKcsckSgkT6aykcSbPsbn5cG21HwJfXtEHQN4V'
    'WYtEe4TYpRpxg4vWRobreOOtStqeu255Iczlj5unbmsQxc602OrBVYCon/zP/5F8UO0W7w8hUV9ZcJl/0BwV9xptsFIx6vAPrlR/'
    '4u+gYqZeCgvzwRXl9Op9c/ZM8eZHMGsY0VliH78lIyET84w6oQ2zSkz461QZoXNyNpV+LZkVBATn3d8a5BeeIo/WNg06HLU4R2Ct'
    'sxfihfMMhm3HvYSnsMVmh52i2gHtJ9DlmcNapEgrvrTPDxGB7ioapqNjUaMIHiPCmWhR8vKxDcc1HEOhw3icjm08+sfSEe3CHirU'
    'oeY6dFjNrPr3OqQ6evUaQnrLSOHu66egNgloA3VWgpJnSErO8YzEX4OynRc2ft+4sFsfHUOv8d2dT9xxOzEZ2X6Lu4uHtb5+iKee'
    'zwLt4CpI1RJs6J6yg8FiQp+hbh2+/pDpaLOLNdmnqje9zC6eysNqSWBJlbUIYIED4Pol3gvaKIMp2hjnMl1N1Fgaa12iOXJJTO1K'
    'TklW6TQlxzGXN1FpgCpsXmbzgVMdmKGOpmFogdKYJucFdJr0KT+EiaAPxY42Y6mqgM1ncgl90OzS1BCp0i0zTXehnJimIGLaEHdi'
    'rvu98ChqUXN1YqtsAU5tseq6bXKXfxeKyADyeuSVvp2B65y6r1TS0IeIK7RvV6GOJNoCoH2jM2MGuPhb19KeJ4TsYF5MTQ/QwPy8'
    'bLCGjyFDMH4UZU5IlqlhsZ1g+PhFvCBbXLI7nzgnCGeJhowjxid0OBpnH9eHgAvcAk2sPZ4Uk8zxRt2bbuBuPz0Zjb6vjcR2VCKv'
    'rA8iN8e8rtmFx0r72YiKSnQJgvtlyH2YunIxtGHViJqKst17VPee9MOB0RKDV5PlwM1tgHx+ulcYyHyFJDZCBDLmS8qIInfW7dDU'
    '4kKJnKHyRE5/FxWsPhHSMx4rzhzN3qSXO+8m3T+YfQShxC4zMQ96oFMPepEWjAHtFYtZqFIEHY0hGMZFOnLw60xSomlMFjO4lsXC'
    'HhTdmkEh+5ieTUXM1UnvhGjpTyburRvxluls7LcXgQDuRUM88A8TVYEP4RZzkbsM0TUjIMYH/yaqTTw+/Tibxzf8i7kgXp+Isd1X'
    'z07osTFrsfCgK5RQOhDj2foVsgYFkzozcXE20ARMMz3xW0xCNnOhdUdDcmvjVzI25x1UhrxTRAX9dKVTURn227pefRIqZLOB5oQa'
    'a8h9ZdWabddSuoY53K/reo1j39jfVqWkVj/W/UCMOqjcKvWBOq82fQCDNdOCfsG2rC3vyGVNi2LIIWJQCp5dH6G/2dr29opmb78K'
    'RIdOoNQGSQ9iDWXFmNHdYMQo3Yt3A688fLY00hkdRq5dhqUxBF/eJfMtrjv608fYP0yWe3NfNyBzKV5ypN2cws5WUldwLodEdtaL'
    't19k6N2IPgsp7CygLhTRTgey6RLC8Wek5iNd2rCM2rUaQv4GkiEAqC2eptrNUTmHjO/c89qLXZvKAoVWZbNgkuliEaGD81zYE7lh'
    'lqfjMGeAJg+9DqW9JUVxL8G9ED93r0L/QBqr9XSq9xN98zDsP2bj6bUdrS6LgpLulImG3Q4c/6U48WGVRv1tU3Sd6f32ygLbDfk5'
    'QKfHwKJpsWs5KWDXAF/AYZbeo/VXBjCtjFNaFtvjjzu7j3PpZZPwb7v8jA+9+oWeRd3FwsRVa2TLhoWi6Q5nCJPWtowDXnd5eIOY'
    'Kt/ao6g1XrkXKmNmyTDjrbgccoGsoFcPjyJdK2kwexczIWVrRxCf1c+gZVPzBBlPvwNZrOh02xQt791OsEbLAqtqOAvsStFZdSBV'
    'QC+4uXmF28mfUsR0ZpoJtILxhgJML7Sk++t/+X+pkyBREEJlRWifpiOR4UuiKveCixsCXkuNemceaaQAEcxaYg/2Zln2M99VsQIQ'
    '6vqE/PieRu3B7o+vfn4P9I++bYr08DCbMhhhSzEGJ2EUrD99FAi3n3wlUvl4JP8GuMzAC6ta+P75i71nb96/efaPz57uCZNqvnry'
    '9Omz13t9b4vxkdLCZIDfbyNk7C+RXIXDKWSTYbnCFlvI5PwO+knwvH6BB2C7lS7/+9Sq4RMVZFINAEZInWOXPdP9ipr3r7fDL4Lq'
    '+F2cqDX6OizqbljrSSNWJd9V2jodUppk9s/YIA9a/g6MPDmtOwv8+l/+e8c76mQgYIeBJXsi7kY5vVk/iM0J+L1p7EEa/OkvykBU'
    'xXiMW2j68fzP/5HA/zepkkHileF+TkVzPwmL2sfFTD8i/2p82JrfMz0ua86TX/GZ1/UJQ2AAfqVDhx/np1nyaljmor1OtnA/pmjq'
    'kwU8d+XH+z6uVqTtDQKNE81bVN1juMsNzEXzUv1bRdOf0i0Jtz6zAD/ObnD7lsk54w2vJZ2RoaIwAVvAktXuBh1t27LeFxqGKmP3'
    'BlLzJzXgQXN9SxWCuKtfQQs8TuFXJXMJJ6ISSYH7dA4QvakXeGbuPfkBbgjdP37ef1d2H/cPel91999NP724kv+8vHp/EP7xbmP9'
    '4G5v43jh0Lilzafp4UkWOWzSsfPIwhq9q0sAznFcvjrqTkK0lh0HMGi60773X5wr6AZbodecwyIMs3OHirDl/ViGkerTA/sXAWhq'
    '/FxkR3389+5AnFsAC8a6K30h+gRugXnCYtPIdPYOaEGkp8DZ/oODGghwFR73kaakjT/uvxvJvN5zAc0fewHj8UNnoMpjTfVaTQjR'
    '4ZzQU5WtpknWvFc5eagHovkmMHkCiEZmVW1Rlmuc9MVts2VIdR/nDaIVifA0nxLoDjZg+7RbaD5pK4pmJpkQ7VBeyuqaM5/P2DCb'
    'XfoUGNKRdAw0ocskV1C6lDvK3ALPsvG8VPQ8NGDYjBFVabra6GBVzPNPV7IRJj4h7qcg7GSCB6ksXK9+t5oOROxYT4YDQ6wNYc+x'
    'Yydlr+k24Ui7JzNhDe7PD5KdHd0foJkeFdiupeH1DhUTyyNaIYYpHW/+FW1XJ52MX9qv41ub2j9OmYWbAEyg5KDHB4OSqjleHXoX'
    'D+9rwR/psJQC60kuUrwbjd2krie1Er3kIVLXbnuML6AK0g2lhqxyqsgqp8nDep1w4cZHD/keCCsKQYNRdIkBmdxLTnvJ39U+lLat'
    'sRWF/ld7EUwdXX7/Nv2hudNa81/xo/byutpSxl7u4xPDmDdyYiX3kvs1niBfxjhvQVz63KG8eYZONEb/N5QdeNTMA7y6VnjnPcS2'
    'q43tA+5AsfW/uvPJvbvawgU0t6IxSAqvnq4rBw9fW8+7H1iUwgDnnDvmPrSKCnS9Qu+2kg2U/OfFGXI3kYsZY4oliZ/sQg623dIO'
    'anMjwrYDg6TVlxZu/zyFsXtkT50Y0qvs4KPSPL1uOUzrQbIGoWWN1xFlIEGU8SE/ULQKHO2pSQnHhaaXEkGnu5jASkS00SP6eWaj'
    '8LzXsZvyp39ADddfz2E+it4914RCrsCLvIzf44GL5dAnP1qww0FVqXA45WSxfT9XGrmBmy9LtnjpBn0M9Xp7863OXliHFvX4nHVw'
    '7qpLjTbVizGspUI/qcz2YavBMfQnuqTU+rrEn+vQHVPBiRbEtwMCwGHHh6i7nVB0uams0/DcMs0ArkSjNnBBnj7co7HQpXEfRq8A'
    'WcJ+jTVwYHxPXNpmix6ixWth+Nqd4HhQZ6bqfCCT/VPPP9/Ux17z/1OEL/BVJ0BMnatvHH377pslseIpPOYoiH2kXgWvRdfI19tV'
    'A61fhI3Snc19+cBFsPjvMUFh8T8Fpb/ZbiurznwilL9bf7/RPYBPH5u+QNMXtbrCTrdU5jnnn6JOxiVJWhGfDUsHC6GPIBTY65F6'
    'O+zzD9GUDrzIaa/rbmuAIxPFylDJAqpJ9+8f9CopIngzDN4EG9q4jWuHq7zZT+4/0Gt8XSd8GvIAz4+SgK1Fym1VuTqRiSaVN3zI'
    'VLN85M0rilykaOsd2aUIKesGQ3jZdSV7Ch1ZUT5CLUtmTZ7Q3ZtRdaY/Yo/4q9TID40q7qPghPTj/1qHP296McyP/YV+pVtv3fl0'
    '6OSXq23+lEf55PTVpOtfwOvqK3N1gDdCmxNCu7fY0Ugq8z5nIorDKYwGvZx4n1Jx1MdRMW/v5N6Pz356trvvjOgHg8NueZKOMpV7'
    'UY32KvYgOHNOShF7ihnS64AhvfXL4odJZMfyKqqXy++q1uPdFY98k4IJqh0V2eyHopuHB8Ukor39/MBHtbijqR3pHTxTb3UiaH0v'
    '0E4DMt2WvxylbvPNy+605yiTlfPBYQXe+clkbW2hF+ZHVONS/MF20Bfn/e9SgsiMj5innVc5Lcks7K5W8z055YsXj671KPXlrfBc'
    'XQ4wF5zM8KNY+U3LNcZKzBkHHNVrpIdVa2XAYxwUHy2IS0CJ72XVRXVung6eb/W226rbD0oc7AzUjvZcdGXmV/ykeMVC2ZMsBQRq'
    'hx4MV18OAxdT4jV3FEsxsRzlx8NaVll1f7C6QsfWvZIa8HB/oNyPhdJ70Em5ft3revB2+kXta7BC+Ga91tbVtXQYAQg2Um9+cr6H'
    'lFN9CHyFxS985txBVvZ6SwTaKzkrf7PZ830hWd0MTSRwPFl2x57jKklv1a+lhnuziuoVRbqZCXR/n07MBwfQnVT0jXW1F7FF1+Vd'
    '2N8H09fPGmZg9YvO50mU9iOBv6NwMCKGdoWhMpxVK/oMi++ElkapE/Zhff5VqdjHByKpJHsniNjSys2fsohCe+Bv1idBZITShrVN'
    '1sSH5SsGXIW6tOWYLZ74EbmEPWiIeuAgIaYkTOhIERc3SVP1YirzQKuyq9qj4+inUEBpgctyhlkD34NHMFyKZB9RmZBRHYuUEqiW'
    'Pz//3XPYkt/tv9vv7v/xHcK4Jp+/OrjX6+5s7X/1+cA9O7jb25F/DzaOnR25Opkr3WZHUzjXdZt35d13E/lPpcQYJHaLFkbptxnL'
    'TZm4TfsKAoWutQkO0IyaKFapPeAgCPR2MLCVYyEw/V7SplAlI3DG5dX5IL8oAWR4Q1TZqbFWsaH6/oFPKQez7U8O7qUKRFNaJhTY'
    'xEI5lBSDTekTILXkjHIpV6KLT028ZLZRPyXeyq/OuH5Be1EcEO1Q8wEzI6lkEYi9eB7Gv7Dfj4Q5IC2oauDklhoX4SvmMowHWtrV'
    'WtOCxy7npUpLY/aVbogYDw2AYyGDns/27pvZH0t1daVa+A5yxKRO+rrNdJpU9qw3UoLKaYFGapXVNHEmdEMRGPyej+7d23bR//aR'
    'fEKYgRz5NKShLQ4Rd0P9gAtZ5JTeFLzJZMfQ0u+Y42IqvFood3//FfIAKCuiDAxbPXOKgffOETMufEQpZ1QAR2g4y9IQeGGGyjNA'
    'Xb7JjspuMR7t8bpMaIJB4yECoS4h5G0rdi1b6PHSS7+xGq//pnLsR4NEQS7wjycK5EOtB+7N3CWYxY923gmzw/+Vd5keAWt6s2hX'
    'gOzgs+7OI/n8QDhor2MBqCvMMVT2q1SCsyzOG0jQwmwgIue8UoDDpEm1+zIo8p39fXSdKTuNFBi7Uu14nD5602phq4XGzPB6dZSX'
    'Utclb015k3TZkUlSb2hcl9KUxSjdEGXtPRIa737ROfL5i28vZSRPeWNFs2kAIGLB6nZpW126CvX3E026jWR5am7VMsLysjFAVObF'
    'gj7qXaZklS9u6S084SwyFcRKYZwjTf5kaaJokV9o5r4SB+C4KE5DvxEHOhubFDV+Q+2sN3AfMbDPdseR2GVDFERw0HaXjYD4zmj+'
    'DtLx+sOlWsboMgpnTE87rgajT8wzswWMHJqztpIzvQ9j+K3/S0jwbH/zwAf34pTYCk8sczoJpPfmrerZ/tcHvZu1zvYeVO2t6guz'
    '7qLu2rF/Vb91ZcORBaAGAV7dhhsK79Pd3Z2BJ0AaeS3p7I/eFYD6iY8z7TS50sXYuJL/Bjbms7wsQXstr8ymVHvelmMmoMtrkykE'
    'IKpJiJ16NNC8qkdqz7Q8nfNnIllVrxCKbYkPjgw3mb3cCiW9I8VIlncXyFBnI9S71soLR+Y0mFJelHcwjvULuKBeAKR/aRGrsuOn'
    'b1Vh6WBHJzPMKqeMU/imTCXYZuAsQuzTPgggnVy27H5CTnuYA50aRZl1p9U1oLeVRXx6PULuEkhZl1lquhMg3m5bP8LnXwR0+6mV'
    'bm6Mc+s6Ndup5c8KOubevQp6F+bC2gmpWSV7Ay/Wyh898jmzrM7HjxzRBg8fPjJyDXJnUZbW1AQ49RCOhG0M/JxIV137KllLkO6F'
    'R83aerJmetja/YH8Vp8kOV3s4WN5xgxUwDrANaK0E1w+wrN6O7l7dyiC0t27/eRuPk/H+aH8+nAoA/nAk/uXX4D2dJr98gtkt4nv'
    'm0IriSqv8YgyKYOYbUV5Fg5PIhw0WvnaE/rdlpdhAjRIVngUJQpqyFVM5zmOM6X1/aLX1/zWylTvPkka225Pf1ZPVnl44uIZGPBl'
    'f71bbG6mm7U0MrSzxZnXzABTWUamfSQZ6Ccul9g4j/OJudwaoaHfAWFo/W2J2/iGGPVaJkyisGPPttyTsOrpLLuGXUuJimEbOgbS'
    'qNpz8GplR7Nwj0X9J2+ARFqYDhvq85xIJ4IjnM8umW/fXjWNSBZgjo4ms5VKuykcFg/dtiBKiGy7VMY+WafuAaIuXHYHJTEmcU82'
    '/vjVp/v9B1eJkxnmOE72azjOnZMHnQOZS5T+uv/ba0t/zdJ2VD9OOm2FqvXvHFiQMxrYX7977yCsHyqmzQ9qUYTktxM6ZGUj3sVr'
    '1+7vD3rXf/mq9l0Fw6HhYos4XZrFx4SrDBSUOmx75X1K25aogyX0PlFTVEkAJFRuKDMf51sqTzPiMashuWWrEnqzFQ21SYgwWLXY'
    'JxiZ8yyrElGR4tiGlqvIuoWAgd3o7xuDD1bTu5VTvd/nGQ+D8DxnUv/mepbGOKXQqgREfcsEWUunxIuWKpu5dtXB10GZX0x0vtKj'
    'OWUPWQ9Ehc5nhZxHiFhV9wsoMn5nXRQKC8/zZZIl5qqRGOgXsLqBHWu4jOob22aybsUzBp2JTO2xi/n3fXjNucRJ9bxAV702EKvY'
    '/zOa5upmtLloxgdTXiR/Sjp3O1siqG0g14xon3dFzbzXwx93NrBTZbuiq/v0mJW37w56Vq48gHrKD+7q372dnn2Wy2f3Dw6QTUNr'
    'f/9evnnPut+/D2o+oPk36XzQYh+k1AeW+sBCOLutHDBLWeaXX6TQLyz0yy8sVWqR5Gr/8ORAo9rrCKBQ70UAZfpKYoBi/PFhduZQ'
    'pKjXdWehP/zts3afwlkjXUGL+M9Ut9dsvUDJwi06TqkdVfns4VZCGG5f2eptqcXad6W/qluaRQxJWZyCWXO4P9vXrj2QDt0/CBtz'
    '8PWiOVuqep+7hRuvqa07Rbvz63/6z/5wgxnQ0jYXihGqdoN+BNut5wm2pOsmG+nyv21sgS/63iXTy8Jx7i5vAfyhqN2OpJUuQ784'
    'XGScWorrLs/bwIUBUUjaUw16p7FK3dX0bIjzYAfJbyr7fR3q0fmG1439y9zCzVejypkO9nIIDy6/NnanfTNjKmgtNqbqaaa+gB+3'
    '2CAhQh8AQfTSHgAY9P6DTcLMy9JvGeyxTN1oS90+OuYCtpW8efVq7/33z1+8QPRdOs221LjfUdvsTQ2BLTb10I+oeVsxaWSphRtQ'
    'S9p09Yd/2c2dem6+nT/BwqVQjrb+awb4u1blo1Q9Yf4l3gBzNcV7bXrZ1ZVD3OaVmMob2g0cbl27pEhxqSufjfKZqilAlINHfKme'
    'qWhE7X24/RKqxt1aX6/aGA6G/QB5ky7pXbjnM0TlKJ+rl6ffKSqZKGBxhjs0HJj/9q8DtLAGGAxqa6e//qf/b80VHhbzeXFmZvNw'
    'BPRT1aqGl7pSotjA+Dxc5GO4JAF8BXjfYBguDz2R+SOA1WAp+6Cjw+iWbFh8NCdPTjELBlk/WZ6qRvHxBhfPsTYFv5VP/DL0t0Iw'
    'Jp65G+Aj5rDXEM0q/N4nYi1XXuSM0zkCUfTuRJ7t5nBmG/srnu6+qK8HlEiglD+K7o66+8JZoaLNtMT+uPrblRjHRUI2o2uDXVEI'
    'GZDIgLs20F+4rANqCm1Ik4xvopsmL6XtZqKPW9Ydv/xbsvhWJy/keSUTkpdRCVa4hNbz61/+xa5shYjtyX+D3AjgEUAM/bcQPLm8'
    'xJFvfYa2gi8ZnixfwTMqeMVRKOohX0mRf4l80xA7xvHxbmwn6XLAdG2TQenFQnBvqnIjbj70HlH+tCRZigze/tVL9RAKvvP3j50Q'
    'tq3NKW0yrnud5bMAdKxtGugIUlYTumxOXhbGXtAFmq5Kd3yG69RhwmOZde9MZ7rfPeTDpiu2dW08dNBi5D3oH+7+rtYSkr9DFRoP'
    'lDXplTnwo6tARP3GFqODrSm8QOeWH3XqiGtcQNT0M/3OQYVkqGdZOgGCz1rU3RhZ67iw7h4XqI6DZn8f7+83XPFs6WOHyKuDgwpp'
    'a2k7ItBZQ6NoVmwg3zl/Cev72uN/+9cARamGH9bkP25H1rlVjY7WDXONfFKrZXrmCqvqSodwr/4lksEIFepaAzRpMpYDQQ1/+IPn'
    'dm0ZqxNjyxk8KoeWKhCBPlhSN0ZEcCetXmvE4O15OA+BQJFDoMC4W5JqCTUSq8KBL+TuUN5FjFpq5yMOEQvW0kQSFhoWxs3S6khw'
    'svDCq6oY86IH09nh/KOsCnnKh99ubib3v55+TO58+v7Vyz0D3acXVUumosMsH3f5vZBuuZhR0Na6LWgAkLX8MwzctUpEXPsHn7Ao'
    'vL7BCtA0DfmjO/ah99jl3CipiiTrnH0ck7NCZiUbF5Pjkrft1aWjHe4uTRXyxzgxJIBEHW+Fd/+iAWqI3r36QR1R8dX2rSBhlCtx'
    'YwiV42KFe9dxcQAzxChbheIjbwN0leOi18iFq6LgvePCd/y4aAiF7SJhmY3rjnvSXnWlIJNGcPp4se6NAhfLEaugH4eiRLhmx042'
    '9ce0SzWl20FNEdb5VWsQ9j0Wvl5yAH16XKjPm8e9uWa5aomTa/gyzcQ49T3rCpsx5QYtVmmRPYlErUJX4ikIFianL6tUflODoVPX'
    'KohS1SnQgOhV16vIjb2YcuNFR96cB1HkY32z4dzcyfeLnFv9dFybG3m1p200tY6WyFh7zWx5FVdo/+RgJxQMLKqlNedeS/e/hDyK'
    'gCZvhcZ/V2/f6eGrN4zLoVIfubFYd8RcpGrzHwVy5ziaj/pE9JkPxwVgtcF7O7/AIJRkMzB8MSX1Oa9XauKWMh3nF285GF2RR8m5'
    'Tbt5hNmLkDXUssPXd5T6ukXYn9V8QNfGiPtOLUQCYDwMrTCIByxCXZgRhbSaNEO5GnMEn5v9z3C3ucO5CjwvXdQWPa3aDDJ164oa'
    'aApnoalwlak5WaTkEuPLDc0vZ7Hx5exva3pJdKyB7ePm1o/EYsO4yIXzXuSgK8D9xthXevDhYzi6iUTICq9c/FkYh6tWl3Yv8sZu'
    'vF6tr59kK3d0cMYZi655dlNiGms2meDx3Y0wi4LuJUDpaPnuGgAlFRV0rZ+sqR11tIZEvlk6qrLWatBuZUOhrxUTVNEK812xkBfr'
    'Gkub2kYCXCjPeaJpAPKWtx9mVOlWwBo4D9TNEC6PmRozjRmhw996awr/RFhrMYvQPCscMywpEnnlhDm81c7UzINU8wjU7StLg2h9'
    '4wj5j4xulZjTFr5dXQZUCX9IgsL2PmGnydqreNTjjnupvq+Djz1LiBSVuAxKXLKEbimz5ojgkh9Pum7eVJwHyB7SthILHgmT2M6Z'
    '/Pcu8ycNTq+mHz9gBaZVkUsWuYyKmKLna3cnn804LMKOYe/smPHAF25GH/tXPp44eFYGHhB6/RE36z3IWh83YsVkKZVCmGbJS1/B'
    'ojpQvLr/REw7/gM7Cmutf9GJGFKUo5zmdDHOxLrL+ws5x/7mp+hVRLRXt3w3/rcJfuEaOVb314l+YU1VdkmQ7opRRbFCjb7It+X5'
    'cVum9+F4ieI3Pl2h0/Hmp1LqxqdLxWHP2e6NTytZzKAa2w6C82xWygqADQrDHY8VYGbkPc4bhwMM36PB9BL8+WxamuWQVnna82dC'
    'KtKq5mcVCRW2a+arLGES7Yyy806QfQ7OtyUNIdagY+VPXr9+//tnb3afv3oJWfnB5oPfDu5vDh7cH9z/5sE3Mn8o8Pb1d0/2nr1/'
    '+4Y27ZP5fFpubWzM0ovBsej6i+GizGaHFoohVL7xbQq16J+y2ek3v92Ic2ptIOR3YyQrtdFReIV0KMf2k6kmCbRp2gr71Xd93nI3'
    '6Yfp5LlOo39k05qN7AnYr47w+cvdvScvXrzf3Xv15llrout1+3i9ODqSrbBdRy0GJvIT9DLwZtXsZwqyHIygjrLMV516XmVF6Lav'
    'Bo4E4BpUm21hJ+EC3Sa4pqysA0a36YK80shu4uu3QgbNCbrYAc7aeTYuphB6SDa0mP7eSsIcXf/cNTl8epIdnr5lnyNMzvp4mEtO'
    'hClbqVeY24oB1Uv3mjLcYdWQz3j44DdMWUiz3MvsAiiQUxFy1K/D7zGkeUa8Oq9jDZBc/lkQEAX1Uc7hTS3D5cAbJnZdNqivvki8'
    '2cxmpkEAqxC2dWQbHEanyiU6G6TnaT5mYtwd+cstj/kphTdCvtKjDK4KNeK4l3Ts28E/l8VkZ/4I61Yla4V8cQjgLETIFutyFsyY'
    'nKc6Q3FSdrWFGesAilOw3tbj8+RxRIY78qRyBK1NV7hqZ+lk4SS+OrD3uR9cPMGVJnWuwrjW9W2KjKw1d3hXv6ooa3/Q+0GLDZwo'
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
VERSION = '2026.10.21.1424'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
