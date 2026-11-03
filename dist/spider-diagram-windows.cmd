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
    'eNrsvcly68iSKLjPr0Ap7b4850okMZAgeDJT1ZREihqogZMo3boLkABJiCAAAuCk+8qsVmXPrDfdr9us/+Bte9n77j+5X9LuEYGR'
    'IEXpnKyqZ1ZnkEggBo8Idw+fwuO3f9Dsob9xdG7iz8zTn37DX5ypWuPfj3TrCB/oqga/ZrqvcsOJ6nq6//vRwh/llKPgsaXO9N+P'
    'loa+cmzXP+KGtuXrFhRbGZo/+V3Tl8ZQz5EvJ5xhGb6hmjlvqJr67wI24hu+qZ+2HUPTXe7CUMeuOvutQJ/+9Ns/5HJcRx1wBjT7'
    'jfzMe8vxCedPdM6DnjnV9Ve2O+VUjzxTHYeW4nI5qG4a1pRzdfP3I3x4xOFg4fNMHesFaOd4PTOPuImrj34/0lRf/ZZ4c/In6Rw+'
    'cvDR8n7/kyhOfN/5ViisVqv8Ssrb7rgg8jyPxeElh1NwZq+xIM/xnFyEf/D5T1IN2tH0kUc/AUi66l66qmbANHGGhhV8w9SxjbVA'
    'quPHTfRxLUZPyUchbNfzbYezRyNcmKAMPssNbdN28dGfRKk4VLTRCD4XMisJmZXEkizpg6hSIQk4exiNy9WHPkdGLxJAw08UD+CT'
    'TKCb6MZ44kffXVJHwKniRoZp4reFa34BEHBWvkYQjDnfVS1vZLszMmf4xVR9/YsgcoKYL33lCFp9EfKyLJe/xhu0bEuno3Ttqc5G'
    'OCJzwp7lQjDFvBB7jKMeqg6+cO2FpaVevdqGFX9HIR0a7tDUuSEdGpmF4Sb6TKZYiga2s7iUL4XlYVQ7atBVpzUqB5QXyrRZBlLl'
    'oE7kT9QpvguXo/oTjlBAExax0ivlhaZQzCucwOcrppQv54S81BQkfFLMF00RPsCXJrwW6ZNc8KiCT6AWV8qXuEq8k8KY/UZClWpH'
    'lK14hOPkJrbnE1bhDV3D8U9/4rhCgas6jrkhDAX+A5cZ6IB1OqCT6/mcoxqW/w3YykyfDXRX14A12sDkTjjd9HTKmjaer884IDDf'
    'sMZ5aNR3N9zfOOC3ixlQTz74UDN1+h24D5TO0+5+50wbULnt2y7wo/xY96+guS+/MJg1yiW/kcK/fIXWOe6//lfuy0z1h5OmDq+/'
    '/PLFAa6mux6laWC4WPYbp6nu9OsvX/OkqO5x/8j9go9+4b5xv5hImL98/ZX7Z2hxiAU+AjGrjrV/KwST+Zvnb5CPc9w317Z97m8E'
    '1lxuMP7G/TwqjiR99Ct8dVRLN/EJ+YNPgG/Dd2EEfEjB77OFr2vwRB6URYX/lTWDFAgPdUkXNBWLqcOhjmvzM+Ve+GhiL3UX2xZG'
    'vD7EJ669EvHBYKSOlKApz4eZDp6WsZhmY0NaRZOHpJptUbB1RWdAwhMGwaAyHNJa8IzBrhV1LWweFgUWMzFE+mhrpL6tev72E1aO'
    'VWetTigijgfqF7FUOgn+5ytfyZzp1iLnTVTNXn2DDUngnTUn4Q9SgT/Bv3mh9DVozSaAlBRe0shIpmy85ZFMJw6esPFWRlplINKK'
    'SQQjWIAv/jlY9L8gpuQImuAu606P/prEA0EQgP/H8UBQhaHIR3igF/WSXonjQUWsKKqUwgNRlwRJSeAB3frieCCWREXUY3ggyIIi'
    'DNJ4IBSFkqBEeCAOoPVSHA8ETVSLxSQeSMUSXx4l8AAwg49WLMQDWFxZHG7hQTTSAA9STwJ8oXOWgQfyiaicSCIggXg4FpRSWFBU'
    'NV3h41ggwLQJWhILxJE8KJaysACXOUCCPwMXGdjrnGe8AS/8Bp9dZGLwiHKav0wMTdOtvyKzMTzHVDffONyvuX8wZihSqpZPC+aN'
    'IZQh+/Q3TpAdqE+FieDbyNTXtO6vZOcPPtP9+hs3XLguoMU5gvprYt//xom/pnZ8mE/c039N7/bhc0An3wAunVMB5+FxTnLYiAYL'
    '37et+HgMC6vnEMBfOVI+ZwBH9wAmAEgHaF4Xnm+MNjkmPkcvxghKKdU0TEUepnoZm49iYj7It5nqjhFgnsCGv8SgHZT0T2ApNNyV'
    'wnKxBnj+T6xHUoas8UAdTsdk9N+4pep+QfoFHCNLHzwB9IRHSGsjEzGOLi7FkZFtMdgKQr7I5UBYN/Uc3StPuDMU1pvqsE2+16Hs'
    'CXfU1se2znWvjk64lj2wfRueNXRzqePUc3f6Qoc3VRd0ihPQBywv5+muwagtnH067fgTtk6UUw1UJgDsxcwKsBQ1HVBA/pYxSMKV'
    'YFAh4sISzGAcMKWebRoaK4YrzDbPPLCW+PLHAFi5uJ74cwcikPWGKeLIEjqqphGqAQwgtBvr4DjohwEGEvxOqLZHhdyPgcvGPhGg'
    'LVwjJFUgF6GURCKF4BBBIVJqxXClzAPirCYwDhCq1KGOZEcHiI3/DIID6og7yWFmWAER8ilkItz+668JoMQkUEUClEwfrkNq5slU'
    'ZQIFXMDDLnx97YeLilrNwmOEFk66GCxDfCC7+FVquHlrBiW2CIF0m4se66ZpOJ7hpech2ZaGslOCvzEYc6Y+8r8xIAHnC38m8ufC'
    '8tSlruVAZ7fGIOZhfdjZNh5oqZ4xAAl9Yq90AAIETWtMqpCO/lyIdfuNbJnQbwaBb+MTKcwQyrCchZ8HXkvXndK9YU2ANv2M1Uwu'
    'WubaJpaEPKELt43wdOv/mr2yu4k7i4ktfLrRRaubx8pOailSZL6bqqXYSHIuJR45GnLwSIiGF3u0k9cQkL6ZKBsMJ4apRQyBVWbY'
    'lCd04IbAC+wxCDzpNd5Jdwm6l5HuCTqHevk3buE4ujsEzeBXzgTtB6DAbsnS5fmiPksPVkzubMDFdRMtCX+L7Rgh5hyEiEl2vWvu'
    '6IaWRJFyAtMQ+yr4JGAYDuz+ZDEz2Up8rnCh2b5Ch0VJ6Ztl+1++AbqoQIHa18zNJk5GrG5QIZib8AHyF5xcH3AvX4wA1fSRujD9'
    'eCN5Io9sd0eE2YhYEhPMxNo0cVDJNgFi3nENWNZNZhchQbJWfib6T1aHYcltNNvuK+RO8R4DrSteHi1/KORE7FXitxa6HO6sKC/n'
    'katCHYaj6sK3EZ1HMWIixSzVpTtwwMHkcIf+mYysCaWi17SdWC+G58cqp8AinIHwDTEFHFY7jaTMLdGRCBrA7l0/ogI+SSqJTYRg'
    'PpMuEmicL8XYcyQSZoCRuRrbGB2rmZ8OQtGT7WJ0fg7jRFtwTNyQ8dHRvi8UBTsNIkDY6M+ojyXXTVQSglfet23To70TeQ5KOrZn'
    'ULHS1U3VN5Z6HA0ubH+/5pLeq3Cmg7GIKeAj/raO6XX4F4f5jtQXzCeBzVsxK1BMkhm7Bug2+DMHO5iD9tUclZQ9HJujq/4X+QQw'
    '3Vl/Zeip4Ai2kJDhX3zjTmAj3ZJWzMwUzLQYnxv6LWyB/8PmKQYLY5RbdcSwTsT8gioz1cBKZNLoXMHwoXtUKhOknwJfIDt9gi3G'
    '8Vyg5JfNDE11oJuoAw6n25rGbhGktEXjh+9wUbfeTDXNg4UGimtoV2G7ehaxhDJJUgzelp8DWMeuyow2EZYntxPS5detMsTHA13D'
    'IoDyPmb+jC+0DgjKXxE/TqivwVHRYIAPttuhQ0QcpYjKNnw60jwsvwVYi5MUA3gAj+ITktdc23FouVDcRF1dU72JviXSsiI56rv5'
    'xuXkaLtRraXqxbgM4dZJdT7EkoFpD6cgu9mL4QRap2tBt4SFhyIblTPiag1rP2/Zmh4bVIgxIeu03a1VVgdAl4Adv8J601mjDe9Q'
    'jpg9heFtTFDbpvFdwj7dy5IC/A4TBoU5LeRERrktDiLjghd3mVEJ9o/UmWFuYoJrgp4cV89RigomgFkFVGuzggowM2/Qs4YEIYZo'
    'hTY+b8/U0i1UYGyWmSjIt0CHKFP5gq5YDrQ/aDBYilBzBIg8aDmQLgyPg5/4grRCFUTuXcsG4TVyjLvtZxGJMeahiqk6HqA/YaLZ'
    'ajadjlAGSo+K8ttw60CSUtKsT9wJX4YQYxA0i3XNYNtZdL/6kUbYpJIrxSXS6UALdWhg/2TX4BZGbmZbNsGoEy78mKkiEaCJ8Rja'
    'IQs9MtZEnbC5me55KloIvAkIsmypJ/ZMd5Bdg6ATrHiEcqQyMg9cYmJ4oKhHNuOYJhj5Z3Pw6oTLKURkCDUWPobmJT5hvhmq5vAL'
    '8Kzlistxkkjq7WQNWwtAhpom6NB4/jUt9hYzBDAla5sk3ZFRsZlgQ+HyoncSjRy/7iAzhuewAp0tUjthVMsIzR6RpVjBBMHCfAGu'
    'yp4w5x8UB16qUXcj6JW69/UEGIjGGYCbKJkyWw508pQWUdkKBnwhg2WEC4MuD2ZXIgJ+HD1OOJh09swHekMrbNTrmW99RDDZtvLw'
    'n6FWyiG21YBgYQPLGgWQai0nwde/qDCEnL4GytZ07fcj313o6KyiuKfpQ9tV6QySgSMlM7wMv4dbc+gMCOYiv0TPLVEEUvyMIX05'
    'LvqWd2kFsSbzhpez9FVaDntHi05VzgKLiQd7VPl4QxPVyy0cDQg9DYk9fReKWOUPQUKaVi2Q5eiCQN2HBXrfhbzscbrq6YDBORAA'
    'YA8eYdQR2zf+l6m+GQH5AMcLq/wNZzZhS0Gsj3EyGlaSL+PAaSszdLJzoY/d1bXFUNeAJQdiLX5HA8/+ccYGwLa2cHKYBkq4bKA8'
    'UAoNmOOfuGOOstTArKHwgRk8QCMQpr+U0ChxEvHUCfBULPk14aehfRBSjCnYCCp6Bz5CyTEvRVj9NOm8E5WEmqdskXYC0aJmBhm4'
    'seWwSFZh2/T7Ykg+o3IoXmSYKTIqJyxK0TTgcrZ91V94Kf+KtJOlpaoRiEIaO8yvlcVWifNXEPeZz5l392v2lphFiDudgHsGMchk'
    'FfsqBCtB8Q4UlFHSzhUunGmPPzhHMdN2fGESLaro6zU/Ovvb7UyKSX9rhrmNbCOh4kZ4UaIJ8gH0hI9vr+8SgZAigmR3+izEX4zq'
    'QZ7lzlQz1US2ySLbgvyuPTpAvqQvlOe2wXSS85o51NTMFtnMgmxz1FaXOse8Zf94xJHxbuwFiLb4Qg2kLibekKcX5jhLqjIssv/H'
    'pdui8mvawAafh3p6peLTEVcupVJAHEHH+32QeY2Axpgt7gFFKbkHhHL1118/hNBKkp2gR1gkPEUO5OMPedg+piMFjCtSxtnyRhEu'
    'X2MTMBF3kxoRr3Zq32EThyBVvNnQV0xqZ0cBRPPINhWyxSvbNdGxt0p7634GQXvLCJCU50U+Ls/TbxEq8qG4UJS3xIWEjMD0rpSI'
    '8IHIirg4EOGMHOKM8h8GZxIyRCYXLgW6WyD6xbRVGf3WRNgjixNYYvi47SWxJvRbwjIcX4WivJzEZ0wMtdRtXCN9djBYPiVbUIRi'
    'Ht6F/xEp7l00l3abpaO+ItPMLg/Att62UxYizQ5UdPEEs5TlNxGzZZTAA7Vtb0y0bWRIl0kD6h6NKG4XICvL5cWSFxFtsEYBOyEa'
    'bootiUIoMmINUCyTHAj+lrdKLMysIsnwEJHfqmYakVgb4KW0VSrvG84h0nNxq2ZktUpgTYTV78VxJOmZghiG92Rpx/vXPlxpS11G'
    'uLmlPCRNQ3J8WHcwrB2u91LklrBstFIBkiFHDju1R6OkgpkIbsyyFSUKjAzT16kLYcPOOHxNzfcgvzCCASWocveUfIyTlrJEsN1R'
    'XwDXBQ7jkzLqz4KsSkV1F5vZGVgc6zdoKYhlTWDAR8EKxlRbA6Hv2NTDgqSXsUl279AHscN1kVjntH+H4HnMSADtXmKzILseaOQI'
    'aoQ2DtYDm5yYkys0PhAXX+09T07MQ7HX6As/v6YjvDL05F3W3ZjZG43iyRiyLTfLHhfOTr/Pp/xLlUpl28H0npgReDlGBjGb7p5b'
    'GrNwiGm9/4VNcLgc8q9xub8kJuT+P4FYh66rr1/fE7z+CCkrKyg4NiFXGDSYdmBuW3LfCb+NNhghITbtiD8sbenF74WVZUQFsgHc'
    '0nCeuChX4lGUS1vZUnW+6TMHdoVv6shn4ZYshOKXOxu2qgHsNx5HDuz8su3DTdl2igfp+ZFdYvQh056yvUUWM+MHspWikfZeGFoA'
    'Ewt4DVEhETHD77KNx4Myw5ZIGO7B0QU7o3N37nSkE6I4HhwQkdnWRyKFI92jGMZkIRj+OCXT7LDGJKSwLFdDZSswheAsCDfGkMQL'
    'bSmfMUYVUijZEA9jWyhCfdgQkYmoAfeDOWKEtNu1SHjhLpc4mVU64pBXZzmZPxXlv/+4R6gZhwulUAc2+Z/psWRU8SM06TDuk22N'
    'h+vOzIIZ142J6sEYfTCbSV9Agrjptz2+ANbEaWDYZ5QNf2PBlzQ0b48RBZ3BeeLyjknlwl5Jhg8kbhbtFbaYWn/kMMFo+IhudG9P'
    '8FNAzHT0MR4lRi6dwEsImPvr4Udb3t/jmYq4M0o6GkCLBO8kiD8dfpIjqEnkFz5iBJHNSYnvFgBljgYExSMBonXWvQ/7npT97o5D'
    'zu7QsYYmlWCVt0+8/JDNgw6TBpT+7bCwmqQtXPngEPceBEqAs23AKQZRNFux1FuVgyj+ZOVQQ/r2bQIzSc6KfsFquZX5dacfO7PC'
    'zPA8aPfrrk13t8uexdbtaNdXx7sh2RVpmBBf6DTgYTbvsLNZybVUskOx8cFHNshi2rYriX/KlkQTAOctM+cz3D/UXbRNGh8/FJIF'
    'yI/xb221HOJ1TLdIxBhvmSU/HC9L3WJxnRbZY9Yox/YHwzfS1cPA+30xKtsVAW3SZ0fj0nOGOn7g7OY1fWdkcMx6tGXOLqXYSNTa'
    'vmNoWxUMpkTuUfmkA1S+hF1kW07KeL0jki88rrZ9um8b7iAcKePNyB4uYuwkAf5Ozh6GtmadZEtMszkwU4faEiLHnw7DRhh0tADB'
    'xrkH4mi7PaMHkcNKaT4VbenFwHOUHtQWMqU9OKV3PH4RJH9hUjnOH1p7fz8aqaZHQ8F2h2uE1QN9niUNiSn0qu+7X4jVkvh/J7ap'
    '6VuhxyG17NRKYnOW9g+EfsRYGeIIjbsZEscsiUOOj1k5YxWllDpZTlSkxzOLGRUX5kn8q21mQZlyUWS1Y8zGGT6ZGGomo9wDVxrt'
    'SKExhFnkmeqGLHKCuEj8MdlRyafUGahED/FDDrEmJ4kZ8LXYfvOeGCAHYlY6wwAIEQlGUuQze860sDApL3tPilUnczxf2H7cWcWm'
    'Mmm3jQuddA2lXdbTA4gGo+L39BhJRVnruXO4O+LuWSICiSQiKO0Opk6BqO4VUeOE8/mzaJSqEtx1RDLnJPFjO2ZpT3zs+73TuHZ7'
    'ph8Y0SLxB0ujO5JGkPFhj8yt+/lcCSmdT2TxBb/+mEwOIYhb2RHKycPqRNkkHt1Mbe9jKuxW10mTScYpuf0mk0CVDuIwdxMkdtrW'
    'VZecyssym4oif4hNfbeCmrAxvudnODzjSIZZPhrLXvkp5uRJn/pDjkYz28yM9RfD4jx3PDhJefDE0p8Sx8USqDMie7wXp9+9KMoY'
    '12EYepC9YLepNNslkAA7Tz98LJdNRuQp0/5jHr+PeZiYw203Se8GfduOwScjDz4YipLsxLL93boyrsdA9QwvcXo6pOuDThBHxTNp'
    'Ew2fW2ZDIWYKJdV3GJjeC+JOWtJI1Ba/3Sz97IURzgHTiCvVUZ2wXHbjh/mu4kZWIcUxMcDycF2C9EuFz/QZaDIPckQ9qaPNxLq6'
    '/6A0dpjDTFQnCDHIrV/EEnHICiP3a4BPQ9XVdqz/gVvs7kOyoYFiS+77A/y/8fV+N3HH1mGqiPlyeaGUPFAlBJFUZLJCNZl8IZw9'
    'F6S1+du7/oosE//zlxwLdsxQlLGXPEsd9vEdJDprntyUyarn/clihrHwqufAouaI6QaRjisAVfz63snmH3GqeftEM1Wxix+zmifG'
    'g0lzt9W2PQeTYy2wlGTbNnyGZB8Ov88wvDBY41GTCfPlljDzQ0z9tFeSM/lQR/EP7NezDMfR/Sjoj57fTGccYcc8PqJjbUG9HWaf'
    'DBqGyR5MDZ9mAAy+0KgkU53huv0aL5OzXYOw3UAd3hnIyTBI1ca7vFRRrDXVWJUtY13W+Jnwsd+xXs4OtsvOfhMD19WXumrug1eO'
    'BRLvOCe8tUHGT9lmHlnNYqkBMEnWujL8CUi+EaBxh2nEIelJxI85u+PbOIsNY1PPTpgErpp3yWVHpoxUXF4IaEKdkhKpE+m3ZHJI'
    'IS/HJQxi30sn/BCAZ+fiUk+RD8X8D5nTgT6n6bRGo5HOy3IsOpIlh82Kf46JuULSIf6epOnpyLcj91HwMEdCAqMJK/MHn+yPGs52'
    'J0ZrY1qxFUmmyKG2jo8m9MzvTukZdJjHRnELIG1ntZbQJ2nKDjR2A/wnqe87U2QMXdsDmcBwY0uxL0VGGDpAiD9+2pPm3AmNMELk'
    'V5dK6TiBRJyLIIcJTL7n6Ib4/oGND8qN/AFxg0HwCD5859wTracPP3hMT0mSCTZwnGjscCcuK5OKRDlM1JCSlaykDZb/cGasXOb5'
    'o3c09i0bQrK5gBN8LOHQZwDPiNz5rcDSif9WYBdToLSIWcZB4KT5+4/4o+CGAfxIyv9+FNJZQGZHHDnqT7GJHfTHLOW/eZvZwDbx'
    'VoYjA88V2kfhvQ5HJA1UEf4dnf4W5bk/EsQjTHJPfru/H0lHhczXUr5E3sNekioh8rREZcd7zNfPuqjsbEQ+oEwxox+Wgf/oh+ff'
    'x8YLdDq3Zxa30R0zGwFU4kRhmVNUtHEQZSon5IRJrhh/wAlLJTEMCYBQRU6kyhdHRlAyyzk59lDMyxxvljm5GnsGTfHLSlQqB58a'
    'pfj3nPi2d1DADu33BlWBWeOKXMUs5UoJuOHZBKavpOL04X8KFqZ7aQjC3n5d/d1+ZzCZ0DF0mkt3LPJcpVFJdcyzjqW9HWMGahev'
    'Vdnft8xVOBn/5vYjhWMuvPfmD4YhToQiYmtpKRT3trd+F8MUApegNOGXSW4R2dugt7A+zA6KaSITl+SuC5GH38V8ReLwhwlqkoC6'
    'EpBfOS8DTPgz9hRhm4i4WOS3nJeKrEwuVrWS58u0vejp3hHN7HeXD4GVVJwnihYV9hexU8hVcpWXvT0Q58MhpN6IKJRH2lsKsQfw'
    'G5ZdjD/Iib3yS3JyodllMVUJUAVmU2oo5HcZfyPCK3uBJsaUHUCze26Az3Mb8pNtPIIS7Tz42UXOnmLAlTgDFuPAz5D/lHJSXsD/'
    '8ZkA9srfysCf9vMA1bAG9uq9iRYBj8qqgN6qoH34gYQAj8M1zsGS8zid8DCCpMjxe0GgJvF3IYBnfGodlfh4c+IkV87HGTHsVJVc'
    'vnILmwrsNJVqVLmM9CM1imnMkZJI8HIA3Dnb0Q/gZDgp+RKsSiW2d8DWB4/5hhjfeYR8BarD3oMbUJGTEwOqlLCZGOBke+mV4psU'
    'TIQUnwfUQiuwK+cV/BinBXgBM9EQlHh1ZDR7xz3VNwMbFOJ38FwkeF4M8VyMSViCHMPzcIllTpnkeQEJjX0oBh8U9kFBNkaeiOEn'
    'OfhUBn0F9sK9wKPS9S5XwUNjKmxqIbaUivDPlHKxp4BrfJn8wIUqAzj5spBmK4KQqFAq5rCdHOBeonlgvqQhbCIXtLNHXDhgEDNB'
    'yStFzDAjIsqURdLuO+A3QYwrY3hmmWBfWeCSlbJAhSURlxLsM8pEImtRgW9CBZdCemclPP+9lZA4maysFCwxfAgQAZZaovhAfysT'
    '4f0Oc0Qh07UDUADaJ6iIHdAPCn4o4otlsYmEixsqPG4UhyhRishDcpKH0iaSem7/MmrG0jiA75Ghg6QBFGAWcygD0p0JNnD4mIO/'
    '+0UtU1fdHLot1Hdnu8iVe8WJIMMCwr7KT2QQ4KE/WGAed1qhZAImEFEC0AM+7u0YPr07y4RyKyoOKpBalUY5FNMFnEngbeF3fDIp'
    'J8vv3499UDCH7y52hStOchUiB/CNEo4VpGr4/J7UTsNk3x9lcSnHBCHcJHuIQDDFgvyeoDycHrAzoqQsACUzGX03ztm+974kWkoI'
    'oqDI7dBMdxeoZBXYrdTppvNh+Zjy+Ug/yvMgXKrAWRlqlPIKkM4QBQV4iP/JnlFG7rEXGt9VvckhjAmIEjBHBm0ipfyVU7uzjNyq'
    'V0zt0cX0pkt4jLCU6caxlN/bx/T36VmoDIvAmUo52FpzZQ+oGn9na/dCoN6XdpgZSvH3u3Ud3zWm7+voQBSNaLmIuCohZ8MtK8UQ'
    'ZByImCaV3/BWPnbTqO4SOICjckNT9bzfj1wQaU+JyTH+lNx4wZ7DmyBVLQA0aBDDAivH7vxE49vvR+emTS7nM7wwmROmyxzbnG9z'
    'mM56Yy/c4JUHg0SjUthQpsHotwW0SG8P/ZnZNMjQYEC/FShUIZDkuBqCyC5XieBinuWRYWKTBSzIhlyAMe8YPRca9LPnoQ6tYQrB'
    'AG7Vc2xn4TDIuVSiSxreHEB0p69OOBSHyQThRTJHp9gel5wSDtX/A+YlsBLsnBocGwI9CmFmfRBLOUnvj966I+bsC+qlRgxQhyNo'
    'Y4AGp3Lo6mErenR6F31Jg5Bq6p6oAqytezIReHsKuaEWgSTpWDVXHXOYacK2AIGiXK1fj06xyt//5X/QNWdjmQ6OTs991zy+Z0v8'
    'DgyYkCwaDyYhi6Pu0Sk+yu6gfXgHVS/Vhc0mjSIjeaZ6O4fSnhgjf2d/cfT9DkyusesYPoPJ57azOeEc1fN1gsvawgE5guYTJMfq'
    'j06x+T8asfVwCJ9BbBzEmataw0liXPSeUXLMTtfYeMgg8VqnDbpsxyw/r+HDekGN7EU8Pwxdzhf+Yd1j/uEBAZfmI3b1mQ1oRIBY'
    '+Nkw9A+D4QEXMoSCfONWE9UnmfqGtmMAJKoHKEz7DzImp6A8OiU1syHpfQCSG0PzUtDYFrs2NkjbYOke9hwlSmZgAuM4QXIbGwFl'
    'IysJb7X2FgOPuqo8Bm7QEmt4H0EeOIaLgBjCMVQRus2OadtaXAvTDsEQcGXDtrLhuvhjWURV0z7LIaBquFZfcNRTfQMY5OrcfGEM'
    'p+jKxOvHcew19GoBd7+yPN39w3mGGozpUywD7wFLjDGkCbZXbdHEh8UdYq0PhsFRBrW1+jB3B+5GxgBE4XEaZop5AaYlAAd6+W6o'
    'Wa9bYJOlPgzwpmpEskLVsgFGlyMpAkBcUE84jJ4hZGOvLLYGuvfdgDeDDt6Bru7qcfJm84lvKUTfDQh2wJrdmsULewGPc0PgDNM/'
    'lgFcUKnos0ygTa/p9riRTZn0amKbeiRrseb/aJLX4qNIkH02xcdmKYhVOIpeZxQgwz06vVVhv/Rj882KU98+q8BMFmyGWnpOdV3M'
    'jhu/g4AEVGNusiHoTxuO5i/CvRiY1wmHUg+eplrCThccpONQcAYKRnksYj30zKi/cXTW78BeH5Ep8arQw9Eph78AfG3zW4FAmYDb'
    'SQwSHU5Hpze67nghZ8cjlAAgiY4EyIYYkLoyAByDXnhBrIkE8plKr1SY5X8rOHsnM1JNd0htdMRIqZGUULdNJqBFPILTkDWQjZRx'
    'CTYvpHBYzNsm9Z2dVk0zq8tg58YswigeYlweY6qBrEFKB2zqgB5rhKTi/XWtUbpHYKikGKrZWW2mUDH99bN43sbgjw+h+RnDFx+F'
    'yglqP8FUEJEAbaEgtWFIvUZEAhYuDquEB30nOK3mZj9C12YOzAfXCLJOhHOfhdl7QK2psJlT6H7xSIDNApRTwF6PanGePfKp5mPC'
    'g5Xqah5BMN3SvP0Q1qERgBB/sXZh9OSa2AgvtkE9gDxopWCOf2MpQkifeEVJOLSGvUJnUyREj3WfY4epMZKSBCZ5VO+m6iqxop3+'
    'Zjs4k9xSNRfQDL2cEfR+8vu3An2bLoXpfBfA45vk965SCM7R6RP83FXCHo2gK5vAhhd6ReUKdKCnGbMWTsotDCA1JeRRTOWyLHgF'
    '7JOENG0Ndrhwl7qGKhb+3gWk57sqIh3SBv10EJjbNPRBZtgKvNNsNJdU69EpdwtpjDmxA6w7QfZMWPMnxJTAIR5KKq1k4wfwoR1b'
    'S0sPqCJjBMAL/v6v/50DDJiG0Mc3nJFrz+iFObaT57qWZnNAiLQpZJtB0xhhmdyCEsC9LzfRy37RoLhbrMoWprokjCnLhErA/UI0'
    'upevn1gTEiC1UwxKIIy+CwZ8w2Cg2u6nICEhU9mQfJetao2pXBMCHLut9jNiKW2NWDSgfQxJQfFJpTyQbT1ka7X/eHVU3x7ZjHz5'
    'YVLpFRngl4e7y6+f4jeUa7UxQ1mCj2K65PSUujoJAwW+t8VIhaNT4f/7v3YxUPEoVEBPxd3FpKNTaffb4tFpMf72kA3inPGF+NAc'
    'a9zB5MdbY4AdCDY0crMqfNwFhkl3gtvkNpAsQ7Iqn17Az09uFBkSzD7hA4cUnVADKST2LRZ1frAAktBJx/QR00TTJtakdRPQEOUo'
    '0F0dGiRDLagBeWRQ/TbFB+0hr6oxazq0i+b0sJ0/RvK9p8yB+6LZw8UMzx8dtrXViNBOlBIVMw9pJAkOyGEmqGz0MKnH/f1f/s9Q'
    'aAWxbIhZI9B7hxp0nruyhuYCpdDoFsdgd/yMShVDd8bx6rNoqsmKBvP8BJstFwzYow4s2ILx8Ql3adtjUOkv7KFHJPdbY+Dq96OR'
    'MdRTXUKnKRqwh2uQ/bD1QqKdL3l89XWnZKkhEbpTot59yc+0nSX9NaD6g4mSBOHtX/LwZGdpe+AZoIAD67pnn+DNwsRqb4YTVUtO'
    'ZEC13yvW7SSofVqps2EYmSQytqIfJLSwqX30RmWDgOpYR3HK+yjXCny36wdj2CLD3s3FWLEjjjyGrSKgCti8HWPoL0CRSd7meKBZ'
    'I2z9jpArmUSi4xHT1Uz1kVoDWiR4TkkXaRkmOY68IEkgSm/R5K5eCYqRboMtv8qxBAswFBLle0J8GA5JuYCKGzN+Rio0wEMzhQFz'
    '+ctfyMe//hUT1QHegnJKVWokW5wZ1jjQRIDm0f2WMGXOhIQmkHtLvYTvHniQT5qhUjQHYhvJzuzbNoMoSTeAFemLT79L8t4XnUAi'
    'ZLLE2g67PxNP56uuxWFqWlgxFNba1PF8Edz7CcvtcIMN+f2ZMAWE4SAhnAoXmeC2YR7R/qD7Kx3Wi1oyiIcVDy/ObO0ztnkSjP6O'
    'UB59SEaJcCQVxcdiRTqGFnEN/MKZxDL6jQtsnSlL3S9ehMyWrvrmhqKkg2gWKoPEWAfwjHX0BRyddojZcs88143ItQqfQ+sqrL83'
    'dHF+qb7Df8U4DP9wdSV72Hc0Ij8I9rAZ96BeSEq5gIU2jN8l29FJwLMwJwNmSoPfIfWS8f/sq8BuKJCBl+zDq08PCoTqOoHrO4c6'
    'OiPBi1kIjG8YxGefgZaERR5CRaMrFruYBQV9x+C4+gwcLDLyIEjaMxU2A3cHRdOXTAAhAOUAoOrf/9t/39vomTEe72qTvos3+Ts2'
    'eZypZca3nYSGnfYUov3r056eiepQTzY5+bsrQID08Qep1DGl2ouGknb3cMx6uaVfH6AV7FSGEmINFd7ohMTF7BF5lDKJwzaLD9Oi'
    'KCxm4AHaJa06MM8g3Bpo+c8ugWLT6Zm93vWe5rhA7YR+2ClF6yhGk8uQMAxjt8K6Je99ZMLqiDeJ+cIn6ekakVF/fLbIwWJYFfy1'
    'c5yG9Z7aTpKBgM6Cv37EPBykRY9auqfHgoRQkIlvKr+EQir6nr5QZwqe/z2h2HVCZu0rGlihnVjZXdryfsdR8stHOAxJAPD5kDPi'
    'idniLCwiySUScDCl2B05G31h++Gc/vF8ZxgN8KN8h7CtFZqWEs6JPWM+Ov1jVgkUrE8H/YRaGPP/fn80DD0xGEovf/gSOsHo/002'
    'jti8G1VNy7a/YMgO4Lerk9zGKcoPJvwLCdUD1IcFsVlkJgmmtR3UHr9+/9Q/0J72WNk+uEOmLcoGPoni/tjAkJFtcfw2VJ+pu7e+'
    '5nt+x1uM1nDHO/e8PhTo51JF9tqTk1RktEh0Zsy7QoI12WohK8bv382Av8encksOyTH48EtmcCK6gq0NR8Ov2LMwShsrINvlJsAO'
    'ovinoe1an9NVCA8PMQ6B2qvgoSv30xIryognHCFqakIBwhpOLd3zthguc4N/YjR6YjR/eKS/GU7IH+JLCvvoIGEQYcnSD7J2wlyO'
    'jziaoR1YEhPRUxJQmBEpDDHZbQAlTS0DwS5cVCrmxWfZTB8+lvBUXfakx48vNSRpz36RBQrNqRXCckG//jBggpxL2A3aUTa/H8lc'
    '8aMw2mjKjGCkX/9IGPk8L3DF4FBUHNDPIQ4LPtmFOFVCz4dgDqY3illrGCf490Ie3YrFFSMk1CuEEr26UjdRfAMmAcL9fkRc1sgw'
    'v4VxSCzkzLYC9v31Bw1HjHLBsKaIIkbfFznZzJVzxaXy9sFBk3yvu4aNNuYfAL4SrkY2+CJA/yngB7AnJmGHbcTHu7kmQTDYj4D9'
    'I1P/8RF+jgZJxoLdNNgJNtJDyBAP1ETGYvzyI7kRyVKVyF8nfHCZ6aVDMUZBvv47cQkiosRn64eQyL7p+jzn3hO3hiJE6uQViVyj'
    'bgHiuiQKpOGFpyuCAzymbcOQq46D54FsFlBOC70fVYstJ40pZ8TDQE9A0JUmPXBfKGul2tTY1pnLiwUTEzwPo0MDy8ph/d8SGgl9'
    '665BQra9CYbPUC3JZkNHAE44PT/Oc/8FLw75dWW7U5BGgfPT71QQjx0GCAXyr6jeQFs7HLPbUF2Q2PFILqCh5CEY3Bf65DMyPT0v'
    'HorBrGkzQ7Y/OFQwBJu6a/8gp2IwJ1kW+HCC3jvORby37pY68QNndK+GFASuJ6PW45RFHNjoXw58ywDtgoaaG4F3ofAVfeK0pXf9'
    'h3H3PTnuGp5BhqENh7rj/37EDv2e5F892zpRHXrIDZTsAj6IKyw7miMO5gvDPeJoPmOagdJGpyK8MBxYh6CN3Y0Ys3ESLGLxKPw5'
    '6p/mQ8Tj87/9Qy6HvjNyTS8JYye3nJJrrpbB6QwXpi9wdcPEktAE7RuLpYZSHozwhOmaGKkwQieOjffA+Kpp5rlcDjoKdDlyl2po'
    '5Asfs6uCj0JfLbEc6i40f6ZG/iJa7IhzbVx11dTd6KRLZCOl9TrEwJ9heaavE0FcF/bKMm1VSx3491InuYMzzuTg4/a+EQK+cGBr'
    '07MA34KVFt0JK319aW+Fr5x2yRvM3Z0Z/UIr3sJ/F7kmOaC2E15c3Su6XLsgpnTxYVsBpsQMSPqnZGaDWKeJ4f+UJvdYwTPf2p4J'
    '9i5FwtkNsAkBlE/M3L4qdztCiy9s6xcMt4XtdKwanzkbt87kdgFppCgET+HoF+Y4wUZiLF/DV5QuMKe/PWYAzGxNNRO2I7Ifm7o2'
    '2LBWOzQMkE7CRIy6Yy+AX4jsrXN6NSJcQSOjx2wPJzScZjjBGAiP84BD0C0E4KIlyGkY0/b8KFBmK2tHYusmQzW8IQnwugh7ijD4'
    'IA8TaeYctgOU3unvTFIh5WgChTRqtdUsc+aOFQKmQg+mZPok4j0iV0NM/rh9rxewW0rf1MSHh9p/wRiTtAUB+sHkP9HshMQHb6jI'
    'dppx1DI+onfsbvF1xN5wY4nkju9nF7QHWK7TZFwTgJscTX1hxgcTl5aSE39O4/PYIMg3Es/CJnR/DAlro00updl5WiIeW/sUrs2O'
    'tm6RUmMziJS7E9Vwu8YWOR3Pc7G9l5GehmfsV7qHuWFczyfp2nXV0/POBk9YkmMBaGXZRHs1cQOpA7Th08A4cpSRbtje0DUc6sKg'
    '7ROWQoWNLdHm9Ke//ESSlB8xmI6+cUciL8p5QcjzEvyUKkcn+N5bzAhpwfsOC6ELcr1beNwG0+4kA/RAa/FIxnQMcEJuQob3NRoF'
    'QMMC+KCRRFoeEPlMtHyjmR/dSgsLGwCCAZUjT+GhcUQxaKiU44XHK1lMFUozeCWaPSLbPwpH5AcReTAIMQwnvLQRWDIwNppY5CYL'
    'ShyhFAqEH0IUcE8A/xcXs6igSgRiGHFQBAPH1aGjzwMW6GSwUQQkTMMJNkvMT146RvEkNhfhzGL9icqiKDPAIUeqVqCPTzi8jhlb'
    'pxNNRUWbC9xzwKlBSLWt/NFP3D+f7EEFMS+UhPIWKlRDXCYoyfys1OPCUDNicvg6gf8kEBTFTi+g4gg5iAo6xDNTJBsCLCx5ortZ'
    '6x80yBDSM0goLM3QQS61yZF0+wFgX1JzzJgxpvzB08x433gsulSlYyMhpX7U2Qm3xYMo9CoX0h1iHbUiBDTNVcnpaZh6WgeWBiYn'
    'vJxcx5t1uYG50GFJfcOMMAUPWVMwScKmsDpMsEpAxkX2F66FYbN6mNRp43FM4HSBCjZ5DqdrEYigKCkS8iUFSY4VYnqI9AOQF3SP'
    '1monV4Subni2GBNqHIJFxZK0hUW3JFqYnG2EtqdUCmEKIerVHgvoZd4xgsTEMMsFJx2p3gjVjMAt6CX5DKNoQAzdHNFJJDRAsoUh'
    'uvjqII1ZFCyUgTRXXVnZoH2LjEHtHB3CF3J8kwJ2EuFNCCupB/o3iXr5Gh8b7sIHjo/hmosx3ha1PuH5WZUcnEk4SNny4SyQpfZt'
    'B5F6hFHVxDrvxY70JyeEuxpRzoRVKIGo+ALRDrHyhJ5xhAcEgTz7JAzuJoyfdUvkbPQ2T9ngsEYQtB1j0EE9lebXOASdpOI2Op1j'
    '7h2PcxeWRbMjOYsBoOwE+SPe2QGwcv90dAGEadoOniIhauE/HVHgh7S2o9uotg8WBrFQ6DNAnCUJCMbdg1FQsJPAqmRtTakujABb'
    'cE4o+WSBQdeToChhDrvGkQBXtTbUagLgenF4vzgbf2JbEn0FMsXXxBBOcDeA4hvcDkBcxxGtiBUQB4TMyHFtYCgeYFGL8rCgE3Ii'
    'iMBKvEGR1HLIugnZ67ZhgdZelLvrhBksSAYv5MT4wDNmDoaxsgPx7DHSu6EZuktJLL0cyfa/cTQvVjiDgcWMkGNGdi3uCzv+EMRJ'
    'x046BNYVoGaaXyo4rwHVaH2G0wnqjSdzCioQhor0l0wERdYp2QbSu5eZSypPW+5zyK0ZRBdRVjTGGsNzX8jOPTbpsOCql2AcHlUD'
    'MXUivkyuBWUtsVUg0ohKz/WT7DWBEB9ROTVu+3q4YBuc5WkikwdIBUke9kuwpPtQi8+LAsgpGTtMNUAMPD+Al2xi15GIRZYccx+e'
    'cCztE74P8sHguLaQqbO7vW/vNAWCMblEJhwt5QW46LiLAg6xaBA2rwRlWfwRRlDl8KhZsL+t7BAGsjkmJhoEAbpCoaRD7hmGJboP'
    '8j7+/X/9vylUJ1sSDsXRbCGHoB06CWhOFSJxUYUkIcjnuSawDhUlZLL3oJEyFL9DoGAABy2sJG4tbB3vriatJYWaAEZmzGTWTVAe'
    'ybzrQNha8ihQanmh3W97mk0bS6PRpU2wJN0YcFd7gRlXAjtwFghf6VIlIUbhzmOyINlr2QEi3IFHhkV2A7oilPCYgYyjQWIHzapY'
    '2TGrqXOHwHJths70mHjmnL1Xie4rVCIgmdi2T2lRlnFCcN0h8gBrDA8+0sGyA96YgyFZHyYRic8j2g1OBHGZDSjhOCSfGPOvRSv/'
    '/hwVxeLWHAX90jvs6NG4b9GJmRN6XOaEJpjDtaK5ZMKjoqGCk57GdxpGLkyeBYdy6Q7EVJpI92bYRYuSe7sYoydroZEkMYGDc/qV'
    'gUtw2OJsK8qWR115Nj2/GSoq8Q0SKo7J1lfAImykm3Cn2x4xEyVRzsD6bFtFuFLYw1CG7FYzinLvL5bIy5kmC6KAB2IKDvHS8BuL'
    'wbfUybsQcwJCxN5DZQ3Vh22839GwFngn6BIhE6VT7m2ASc9OqOuNmHU9pgUEJwei5ChYJqeukJXgEbOUWvM+rDBhP/0V8y8Tu1DM'
    '7EkvZ8o2SgeXUYfGZeH0+4yCqUn2fitAk7Rt6g0LIKIXXwcGK499I7HGE3JUFPO4kbuxiaEOJijAVBw7WRPkIRz3BdDx6xGZUSAT'
    'B72bNH0P5zm6aZIzu4GVdocpcGe0KgKKO+hnoz1ZsuHQtmQTi0AS+Wl+4T8yRDOdcnJ/tslgzHszJhNNAIif7IKf8KzEL2kJUYd0'
    'hM1/Z7JlHEGPTG10HNe1tmc+OpNMMk+FLDUIYFfJRkQUVksnh46/fnqosVGm98EDkyimBkjyY+84Mp+ZL/s7M0PuTLf9MWpq2m46'
    'tuHjZBWcrj6BjUNFkk+kgDeNgQuzwVb3M8k5yX0MP5ikOsDlYydW8LR3brDJkdPfobBHjSZoO6Wm5sTuG9sKNPt7T4pzwRy+T0o1'
    'OscpfmBtzX0YnkDVOgYvHhPTVaJHH33v3lJL9vg+6HWGAuHJpomNZi9qMWf4QYR3uv/QKKfvuTQgTey3SVz8NLX/hzm7nx2bwOb5'
    'AaXPo4RsERBhGFiRdeCflGQn/hPtMj9eopyX8O3FT/KQGnYstLcdKq5bR3lcfUgyErXIb3MT+Oh2ncwhdzyc3sHPrIM5WXNy6Rpa'
    'EnK8XzqKrEk5p2ckROGn2GFiPAZFL/KAxSNuPnIhMbRAv4KCZZL2xsET1LhNdcOeBU7a3/AkLSC5Giavt91gPTJkpKQM1tmQA9Yk'
    'CwJgLzYdNBeLkyJeehRva++2PlPXpm6NyRV7eIVJojfi8o7i/0iHiXnFjEXhpIYpiY4yiAZKduzx2IwfFkd9mRgHiBuD5KeJlJVP'
    'UEl45Vok/QatpfZIKrVMBxpNoY0fwvDRWFBNVIylrCYFPZbWOrtkGzMDspK4uDuKXWBwBSlEE/buKPb3f/3f/v6v//vf//X/AJWb'
    'ladHxjJLRykiWFmLpnnYXbjACiJf2FEuLGJY2r6mzlm56EmPPRlG90Tsa+AimJAw2/2ewi+sMCY93FeOD6GPrcQ2h8DB6W4qViMi'
    'Jvr6Cr+nSKRO1O4wsYdP6JND9nSCJhfNo7I5sSyzLD4u0fk/riJFgNwasZjAraAH1UOKYlGCesjrY8FMLC9JkphJ4ZbuxY9fXpDz'
    'fTZm9KMHMLO2C1IxHsnynclJojgV8jwMqsqOdiNlyO1D+y4mouaY78yhsj5gC07MSSJrTmxntM4wY2nscgtXpTmX2Hm4nzIzpTkY'
    'h4fB6bs2xYl4dNqg6al2FpGOTtuLwSRVKrvDAUKJMeYA0iP+2pmFwiXpsmLpe3/azoqWOMUwnGFcsh27RuEPTBmz3XNw492/TaKY'
    '7f5jt+JFyV/pEwZF95MZYFmzhwJC7yHrTFx7MZ7EFFZ86rOnH4eD3W528GoQh03XYrdOEu4WZfwgyRFJ6MMXvCukwFHPHX4mjgD0'
    'pn3ulDF08zEQ7zMAvFvMBviQ6p2fAyO8b3M/OIR1JA5ss6QAVFhmBwEZAt1898nr95HYjMPCDrcHCTg+jLoH9E0m4IreHh2QLnX2'
    'hb5hTJ+5JwkCCQn7VPBxdh6EtFwZ4/EdTOYV2UhUeiFWNqclV7lQQ9sOFksRMLweh2QKe4d9kzhfxBA8vAe7/u4s7SC505LwYTGz'
    'ODeR/Sa7dRBbSQfsDMyeHPBQknTAStI+9hQmYwuLZ4z0vX2FzlXDdo032wLG3FrEFuKCXij72dP8wX20hxIJvZ+rzm6WTSTviVLw'
    'fAKOxI21h1kGiExyZmNWPhCQfBKEYJDpDax8cfGTPqHHPeMC746MdjR4RfW42QLzIlNzGUZu5bm//AX19L/+lbljfHsrKAPlYY74'
    'wYK7uk6STjt0XoL49nOQffOEyxF+e8L9+c+48f/5z1/zR6c7hkziyY6SkhkBZa88O7IxEDwF+//7/8RghS+E01JPnW4EsaegS5no'
    'G/KxRM0bJk8OJtKS7j8tRQC5mo0zjiZtnW/6rUDE/lALoLHP6H8bL+C5Bl0vXO4LMxJ6Beo9yDFIcvg2OI6Ffl8WiSAR+/9Xel8l'
    '8eIG7rwFDVMID6SHbl0aDR3pIP7Cz9RAAoNncMjCWKIgaZsktVZqRaANpl9EugE8O7cXVjpYfys/f7bWgLV36wy3OgsfjkzBYWYd'
    '2GSIOR+WNxz8PzLf+Q9SKjKxEueAeAZ/M4IRnJGvBSNWYSIFL6OzKFKCJPAVOz6UphZ4dUHSIYSnrj7KlMhZgViaJuocSp4xSA/K'
    'UpfJ4yxkZHikGX9mn2FJLW8CK2pr31UzD7jAyzsydPyZnu2IgFgk/47QfXYqb+FeAGs8Ov3bT9wR48LfuKMkVaG/OuYtl/ArCz9F'
    'BzZxpuszZwId43ecUeLhJiFX2By7doQ8JG4ceMZuVCHP0IJA0qzSytRHf4T3uV1p2GERvwZ3cbIOefaBOzKwDH9CPpPsftC6gDyL'
    '+quIK5G+XUcFN9FHlkX+G2eBjE4fTUEcJ0Ci9ZQ+ItnQ8NnP4kDUiiJ7TM3AYVuhU/+fFjwvDSfi6RNKDTMS/ZD0YdMSeMSKfnIw'
    '04DHzoATb6iBETm4RCckZtKPIqzQYUMd9CSwL+bOQfL2dFLXg26jh9S/k2e9OqzThck+mEZ45Q6NJODo88EpPRgBbIVVHZym4vTJ'
    'DUgszCQ6uI01iJGIyZLRdZc0IA1jQsM+IntG2EkAKQAWQtghGZrRsRJUHJHAwTCfblSbLT6bsWAz9jEqlt7lHLQgRsOiAWgsw3Rw'
    'tIGjEdFB8fCOlr2A1taO7hokKHfk6rq5+ZYc6kvUKRr+aAAuWSsqMASF64YflQzS+zJnWGzRSTjUFhwFWNwjwMp/JjQmJOlFSNIL'
    'ub2SHBYK8vFFFJMT88WKWC6LklgslQRR5kt6TihGdJQTSqU8LwiSJPBliZcrKbri0xSk85IgCQdRkB1D0HOCXGosmVegp/hZi/CQ'
    'QDEYYTSVKLvFr7sECsV5RP8iHpQArA2qJZEyqIiO++hi00xU3TgBviVRfbtBGoeXD0uwpPTJcux0T3SR1fZyh1MFnMQmNvtwrk6i'
    'mSL4RaKE6f4P2wNBu3TyBRhWBLM3jCAZkhOVXsRJIhwTkzgmJnEsMMIS9ZqkAMyB2qAmcE3iy3lFlgWBV4RKWRSkCMskKV/i+Yqk'
    'COVKRZJ56V0sU0oVfpjCMiETy+JsMBg0ghvjDTGsYzcV/5pIjMAxLm+nF1JLtIN1w2MvKuag1bPQ54IGirA+gwYx+DAGEtM+Iojo'
    'gbes9p6QDwbNhNckRm0Bn/sSDzIGUTnGXwBTNh++HjE4cYTjH9MwTDacwKeMwcdkCF54Dg5nlKhp73AzKYlpUhLTSFoIkmhK033V'
    'MBPMrJSv8GVBLspSsVJSZCWGYoIs5oF/8UXgc6IIjK78Ho6NeGXI8ykcEzNxzEnemhgc+YNSRC0k/MeK76DBch3fRes0ULUx5Suc'
    'hykjw0J//2//PbGaajqTB6HwjF23ENszn4jsEUtPTxJnkBsRyOEli9gIuWKE4gHOYCRt6iLKCBxshR4qYccA2I18eHsi4P8GKGcQ'
    'YyfhHDMvbCAUsqUvJpe+mFz6BtXQotNvYfaPH4YE0kFIwIcAl5IAl7ZxNTqnAaSGmaNp4Oq/McRCCLGchFhOQnyz7eOOA6oU8wBQ'
    'SaiUpGK5VJLjcgK8UirlIkgKMsgTJVl8j75kWVX4UQpQKZO+iAWIMQsftezgsxs+hH3x7//yPximwdfwOREV0s8LYc1Cor2BrW22'
    '2tZOE/dnF7avpQ5FOV+LKsWkE6iT3PPTxSN44t3W4vv8nh6uyZZDpJL4Pn/C1UXkDMTd/8Gu75goQg/2vAtBllxzWEfUhLqn6USB'
    'Q1tt2st4ziMj1HCyeqDp/PB8zQd7IVwxzEK0p4cUNz5wCZAG3mv0M1NO3JgFjvoD3+vgDEpSn+NHe6FXPxToZsYugXivt9+D3nIf'
    '7I1cTFnA2zft9/p4Cfpgt0d+sCeSLqjAkqC8uz7tZGftD3aGgZPvdXH/Ua5CT04Ex8YK4Y1p7+Jaciy1j1KL4UcX2rzXF39A44U4'
    'uy7E9wi0t+gxWZ3tZTFZKzh6GE8EQJKnJxIUhDf62Hgsmx5NQcGDnOjNUJLKyc21nNxcRTRcNdUpEedJ8r6xbWuxDVbOS7CpooqE'
    'mnilKKV1cV4q5yug+RRLglCpFBXlB1q5DteeWLL/4BKAaFZdPTiWyPbKPEcuqc68PmlsM/MLTjK7qzdpIYkLoKm7e6M+yd25MX2G'
    '+DCCe3ez1KWg9e37t8NGT6Lzvhray9BkRMycXOz4Pjurr0Z3CKTgjimGeBw22+bFeQurgKGzYYIKEpure1lRue8oTkoS+5Qk9pFL'
    'XeLiXBkEtpIkFyWhDCKnWC6msU0oS/niHmwrH2b7CeGrJOGrJOHDC2ISwqZYyfOVckng+ZLCK5KUAK1Sycsir5SLclkulZS0wUD5'
    'iFmK3mwDpchNNZFVLWWGFlJ26DN7HYe3XMkXBV4uKkVFKJXLlXIcXrGs5EtKUVIEUSpX5PKnwBVS4OK1ORG0aSNgygrIrs6JQayI'
    'eV7hRaEoFPkyL1UqCYAVOS+XpZJUlmSlXC59DmIxBXFwkU8EdcqsJKTsSuFdPjG4RbGcl5WiWJaKRUUqC2ISaSsKYIYkixUAXSgX'
    'PwW3lIKbgBMBnbJQCGkTBaCRx/0XIvDE4BYqfB6WvgRalMgXy8VyXH1SipU8jEeU5YoIeqBYfpfWMi1gEYwpVVpI6dI0/3wEXFGo'
    '5IWyoCAigC5aSiADLyqghJbFolCSJKVYTFObIB0EHaMfku8ZHVEEhAjilC4tpJRpcpVR3JyIRkOhpADUxQr8V0oxkMtAb4qICnOl'
    'JIP+rHwOYiEJMb1UKYI4pUsLcppB4P1GVMwGdBjQe9Ji2z2fLxYBUUuiJCoSkFxsAMBH8kB+CujSPF+sSJ8cACMnEngYee+4ILgw'
    '/ohEz0KNaHgpaUYopxk2jWeKM0GhJORhQLAqFeDdRbEUp01YqjxwcuAnslCShUrlPRzfZ4EzZuMAPIDdxbEcYSTINxp/8Oro418H'
    'qqfLxZNC5bVQrFYf29OX69a4elZ9rMI3+F29KBTHjed29+6iL5y1O/zLdafWhXc1KNC4qpI/j6tq9cwfWK1Nd6qdX9UnL09GtQHt'
    'Qf0aLVI9mzxLd6vqIX+g74r/TH5D/53bx+oP+GNOX/p3r/hJwR/nrc1T3VQRsDoBr2UF32/odyP4/kC/S1rjjMdPXfp906tfX+Cn'
    'F9LexEp9N1LfX4eNa1KfAHGx9geN3msEH5mn5stTqdclszTGH8Nqo1ntjs8a1dr181PPHgelBzJM/cWrgC1N6XwH82zMYL78Yhd7'
    'UnEMV8Gr8zbWf5jAD9+rJNpLzHf/bDKc1aLFgJovM3j/cGPB57sneFSr4GNnEMF/tn8851U6ntqwOlidLauX8Lt6ZuLz9uPZonrZ'
    'rN6OYdAXV9VmtbquXgwK4uoM5q97cYbIturW4Hf97LF7ebZaXZ2tho2zlXJ7vpo2a49KuzapPdRatU59surX1o9qvVVrXZ7Xni8n'
    'vNZYK6Paemhcn1/p12crvbEu07Yfu9DeENorXp1Xi3r9rNZtTIr69/0vF2C4rfPqxar6NL6otmH2JwD6unZWUB6rlytCW9A3PEv8'
    'adbOHp8b1XGjsK5Wj2tIO6tHKPsI8HWvqgHltOqT6rhZq427l1edemvYrZ+PVUDMVtNoiteb6aDWvb64bo/Hw6cr/q42XTTWXelh'
    'hX0DEiE91intxv/UzqGv+tl4eIXl7ibwflwDGB9hjpu1sO8zqD8mcLah77PuU309frmcnK2hb7fRKrYfzpSzx6cmf93xlo2COIal'
    'XNVw/Be1x2qheu8Il05rvJZv3t6cWqU17z43L2sd8nD13HroqublxdnkP/abx+5zrXnlzO/aM+/i6Xxitq/l167jVoVx88pij6sr'
    'Q7eFG3V193xx/j//+zG8vrhuteyLxy7MSHvj18Tx3Vmnq04m/yE+FdSbm7k8dRznyemVp61Gd3P8sHIXg1FbUNvq3CzPu/eLYvnV'
    'G5zZqvBoCMczv1vu3T+IM3Gzvjt/lYbrpfRS6q55zXvjR08dXW3Zd4Xui7Q07VfnWHoaCoZyZvWn7fliNttYIDiPNs2N5WhPx/7s'
    'ylgPRkWrXVVmm6X64JqyI8pF+3VuzK4Lq/O3e8Er36jaYNLrvvWkt4fyVUmv8G/Trl1xr3xhNb/tKG+9ktUoPV0tjx9e5k7n+OVe'
    'eHi7Vx420N/CVFW5O3f6y1a3/NbkJXEmO8/u6/HcuDUfOivpRbl+ncj111uxtSqbD3LzrfVgNdx1pfPmw7Jp9bf++XWr05s+aw/P'
    '1qA3UK4f+XunfGsvFs8zr6j0FdWd8OuH+2vZeT1uXa/0kSMUqovj8rIldfiOFEz4rPgytmf8mX2jvnabV/FPVWd+flnrUip/BCz5'
    't6dXWNCJOgdMaAm9p9ZF+Vl86PiT2+WV051rpn+3HMgXVaHfvdEeVuVFr7exjZfy8fzhUj+bFvW7+97I9tYF/+ausn5qtCbP/p1f'
    '62i66I/qnZvqg9m/3ZQXLyN3KTlar7t4eXi5rc9g8Q1pMGk1gEmuNzLuouax7Z01R1ftysBRJa1yrk8684tayViZhVfXv72fX3vW'
    'bCLcr0W/J/fm5sIpnPWbXaEldvjjmjJSqjx/vCjW7wcT4XFpOMW1tK68vWpkpKPOxcN1N5s7nU3qd6RQt+n+O/DHjqbd8o4/7enm'
    'vFvoCreXgjyct62rBX8rC7cFsyAOHX/d6fXt+1b94a71MKl3Ow/2wHqRn2GDEJqVJT+VxtWH2aryxHaeeetm3mvppe5zYz3tOYN1'
    '2VSP3fbc3Ly1esNFl+8OS7Or1+XNwOx2+TdY1nFRIiA1BP5tfZ0FcP2y+kxZ2vPd2SNjafgdSqlVvn45voMCd1gAvp5N/k3fn4t1'
    'rd/YqLdLu6VLmwcTnj8NAc82g7verHThzI1na2GN+7e9zVzo17Wm8mxaXX5u9m56V669VMd3vfX9s3lz/Sr1Xh56/eKl8DB76Pu1'
    'pXxnCs8V8b5x7FVqa6Ewmk8rKl9+8EvC7NZvPDiv82m1yq9R2KsK0r1UaWq3dzeFJ7dcqJ43pesl/1xxVFlQppUb6+GlvlkU9Pmi'
    'V5GPi5Vz8UzUFi+Ll85Mei50/E2xrNql20XprdRoltuq03kVr9fy9fG9y78qs3vkHndV9UIyLevm2q+q56+Pl2PGVuAF7ESDR3gG'
    'v/EF2adsEHcHwZeAA9GtChtgG9i/b4mzWXE2GvpXZn1dd+2KfHmHhYRjR+0bqvVSeTO7rV5HXkudt/Fm2L9dPpt64WXencn+i/4w'
    'LLvG1XLSE+t8r96C//e6MFZXuv7S95bruWw9L986jV6z1TuuXPMVVxXLnfPFU3Gmb3rH/KzgLkS5pi8WM+utu1JepwPt/E5tqfKy'
    'sXgUEPKLJl8QVXn0Kqz7U+Ft2G8pnn4zPHaeN9rcm5Uuy6pjWIJ1rFeX0q0pL/XifL6UAUfJYCsXnuhqhnGrLWZXzqtZG16NS7PF'
    'fF7q3SFXDGfovLhhO/XTmRugOw6FEAF8Opva9uoZ/+GinhmvZ+PVf/zfVXt1cU7W+qZ5eXPZu7IIXq6eTeCAz5denfLC/8k/nbXG'
    'j5Ts5ojal/1aGxnXE2Fc17CSPcq4ZrC+PcK48H1t+DZtXlyMKs6mfOd0Kz2VFwu3y7sHs9JXOmr59qbvTUYLvmktn9cDcfT69KBU'
    'r/s1/aGxOb9ToKf75kb3vUmvoCmXQqtQvjHnhdZrv9TojZqSvplVBp5T2YjWeihob2rn3D5+erEWr2V74MiXUP+heWvdKct+ob65'
    'f7SKqlh4XJdnI6v/4AP3cgt1bd4vzq57fu/ltTQYHg8vtIceImnpZtGbzl9vp32z4Ha7pftO2+VLdaGudN2uX1idCXxBqdblwhh6'
    '4rGnG/m+U7p5Pb6YNp2Hm0pPebv2Ko/Km1qYvJWNwmvrZik8LvhB7+n6WDWeleXqjq/cwiw1quK9d9+zB3LbaiycijxZ8l1RvxZ8'
    'tTfdKJdzaz33e1fLRb8001RxshpY56rzunwtNweOgFxHuL8WHlbi4+Z26r7M+3xf7XWkirS8W78snlzhvH97tzFKj0u327ua60XR'
    'tG48qagtFtdl55xsKLh89VJ6/d5b3+98D88uayMcgBvw8g75cja/f5YnRff1xvQlV+LN0v2xoB77XcuSa7DfLF/qi7fOsn9jNtTa'
    '4Npu9h9KF2ermztvee0/Lda88+TKm+O2JlsXw7Uw2lw+z/lnq2ypx7IruOVRq3xh3czhjwn/n+aOLvR6utCxmktVlVr35WdnNHg4'
    'f7i1KlXN3fSfhLlZt4uF+tztH+tl8RqaLpTsYXnT6D7cllxnuJFd7Rw4+rFtLcq9ijNfDUtT2TdLjTdhs5jf16rQnQt/7erdMG2P'
    '6q4VwA+hLN4KG6FX5Hs3xnFxdv48n8361ftxsTAvm8OX+WDDv/TOdcO/nBfuHowSv7zU+sO+eeuOpPVNYVnxH0qO8vRwPx4MLoW3'
    '5vr4srJsCZ11RX8G2bSnLcqDdkl1nUX3Vup15/JtuVNWLza3IOO/Dc+L5lttMzCdUdu4rfRGd/elzvz4WpZa8mB0XZReQHd5EhR1'
    'NHX4xbXfeJX0ulR8UYrKSpsi/r+ebZTOvefo69tKXX5dO/2FwlcafvP16WLEC7zQWnY3xfNr2MnPF7gfPFEc0YDNMMzo052B4Avd'
    'GT5aonGvdbWueP8grZuNp4p5LcLCuoN+0W0UHu8epnLFeK68ScO35lujezEX7wZv/buhtq5flHrlQq3XcPyu5qvHb7yuWjeVx8qg'
    'P5gLz4Va11XtsrkUnMrL6PqhVXLF49YalnZRHs4X/Rt5LsumPgetrNczO/3SMWzUPv9cuNSXduG6udHO3pa95dVwbPasRkFravp6'
    'Xj9edqfC6HqpDuWl6s6rQ3P6ciddz6Wy35mOq1XvHTumPyk9dSbSdPnsHy/ehh1hXn8uX0z0Rb11M+jfiHfLVuVO7fiAGJvCVXF6'
    '+WK8HLeMdrnXLt+/bs7KD+OXxbUldpfPemuw7Oqm2it3Fb7MV5xpU78piq3psy/cLu70xZPKV1TD6falRkfpCGurKHdFRRZaJn8t'
    'b0Y9d1Cp3zvrO+e2NzovXJYf+m+vICPWr40OfzdeO4um7Bb7d6pVcQovrnHsjDp9wqJKj/6ddtPr3oC4ass3lmrMjr3S3bxw4Qut'
    'h2GvsVo9o4lFIXvuzBZApPIumZpJXj3im9fL0oN5f1/cmMDabnzR7C+cvj/vi9ei1VDeBNDz/J5reNpNrdw9ni1s+VjtFu4KV6uh'
    '21UG9ddK230VWm9X1libbO61iaI9H8/ehobx1pIbZWFSKwv3VflVXmyG5UFjdecNLvvek1NwBUepTS4s6HXTlK7mm+a80tcWglbp'
    'tQuF5rTWmfqPglyZru/qy6I6ehqVxHpzU62q1PR2rMryrXYvaNrdjX4zX51VqqvbQnOovXRksdfqLietyqBycbbU2kX/tvAo3vrr'
    '0fKuba2vpZez5ePQ1eXZZr70PF1oHV/35setibQYlG5KhXnP6axA/T3XNo+a11lIbs8tt8ut1vGNU7u/WLzoveExvxkIfetpPj0f'
    'aePyfAmTaJeVDb80uwW5dnOsFzfWYin09N55oVZc1crTqrwpCddjp3ChLoURbxujeRvkUO/YNfp1RZ4+lsak1L0710a91bTzthgp'
    'tfnC8V6Focpbs/lcrdXKXlUyKu2SZXtPtYpRaB735OmbUNh42oPcO35xHu/E6sDU7ePHgumNyr3j58Ly2ipsnmHf9WErnFWl57PF'
    'FCrxhY2ijbBS5Vq4ncGyvbqlq+Xb3eXZYgW8p9J5abjPgjO67j0e87LlVu4b7aU5LBTvNWyEFxrdij8qKm3/4cYvjHuObIJubngS'
    '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'
    'L871k/faqgmgWM6vLP/2zdSOOxVTeurdSY7Sk2bm6KLV3TjXrdbmjn/SO5JbqUvlW/3mlncdZ9Fqr89Abmqb5xfTSklxS6o8aS8G'
    's/rlTClfDpfistEre9Vq3Rh2fwwxza/mN4YzNxRo766zvHw6Piv7TU8YTDbTp1ZP6PE3i0lvI8uy+6Y689GZaDcXyzOpUL31W8dN'
    'ybt0+JuOLNWH56OL3kA+F58F53qkVK+PX2xLHW9kpTE6LndHr1fKW2XVmHTOjy/m7eLTjaAZvaa5ejkvFV5qbuXptnE1d+zKxlmr'
    'ln19fDUrdaXFqNsA5bliNlvl+WvntTUVoKMi3+iWRXd+d1mT+dnseL0Z9N/u1M05Nl+/vJgvin1R0Eyhqa1G5wI2f3d53bicX9vr'
    'zfV6uHSuL8rdy35/XC5I6qvyMtbbb2VLGCnzzejlceoZgs2Xus/+ul9VK3Ot3BYu/fO62m6Pnp2729LM0OYXt+5KK6zOcWTNyYuy'
    'aF6IM82r1Ceb13ZrWb51/Pmgpft3fo/vr2fCeHoz6fSfbPf/Z+/NlhRJkrXB+3oKKrtPBRSRgDvgQGRllcTGHkCwOEt2/l2+AQ6+'
    'L2x1UuTczc3cz4zIzPXIPMf/JudJRtXM3HGIqKo+5+8jv4zIVEtnOO62m5rqp2pqaqtJoSbuHG9hTLdc/rg0ga+PHv+5HPKxHYo9'
    '6NBD1T3kF+NnfztWXLk4cJ/K4iZ7NFtcMTtuhdoY+MtWGOj9y+5DasOC1PmyuM0e1+1F3cmOnxV7V7WmIBlh4e7/Q80ZNEJXmK6c'
    'dicM3LkkWZuxtOx2ao1Asqauq7qu1jAcRzLt7ajfaOvH0WC24lzg49mVWzeNjVkqFXa+70PTVH+tuRO169mcpz32xb5xxMXLFUr1'
    'tZO1jrt20C6NKtOx3Dga6kg6rbvBYt4IT5tj3lnMhm2teXI5tT5tmFvFcgqF2al5qoWn+8Fe8GoTTZw+FDqFR75SPMy2M70wLVaA'
    '1pvFuqsVF6tmSRWz7qAp+/unat/Ni01DXC1q99Odlh0AWq098nl8+oPUg9e6V9xt8jAsr8EOnx4kK+DnD9mmuHQ3p/lLb7EqDQ71'
    'Pm8FatUpck+103wxmbYrhrAdCm13t+U68kNdrA8ns+Gk1NHaVauiehXfNLWF0B5KWYE3Z4eHp/z9o+prnJp3nGq/aNrqYDbZLvv7'
    '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'
    '71zPhitd7ZflJm0/wmao6nhmeJnoG415Ulk5PpUxvWh949Ox/jJv7W+tgM084ilHs5CH2+Zl13/T6Y0NxGPXa+PP5W5LyPi2puqj'
    'aisZ6oJ1zopMk7erutStmsRSzCG7JLt7KiIOVTGS+Eb40i1lfs0uVDmXEqcwgXnFq9ng+jexy/6WWMY4N7KOLCiwUFMnG9fSuqYv'
    'gcnWkHN7UvMnxslKtrP04wybuM6GnarH80ePL7tSKFgzUlfeSF0ly7mp1zs+k/j6fgNz5VVtn1SbMEf6FZghI6zyYWWuiNC7RsBH'
    '/M5gX9+9vuLo3ZN79/Dz3j1H2Jf12smZLa8TsixpLuzK5TyFfs5Cm4jS9lhy+6ErT2RfDP1tupQtJvH2O1yxf3TdlWR/u/UBU1aZ'
    'uOITOdoMC/xlTLdaK2bup7f+zH1464+EOcdaK77g9adWwwS2nC8NDwpTjmVVsHzv1yLhJf1Ko/YxsiyYOQqO12CjNDBsektfZnB2'
    'w6Q8m0yQaiuccxfPK1zGW+Xj1C2WqCtvNwZGblweUD9PGbYBGPXDkHJXtc/x6SjAoPcpIKvZRjpeo4HdXh6Z6rGCL1RkJxWvHFFw'
    '7Uc9JlgHkoGCswhVFEhSoKNQ79eR00j1GCBbOjLMWw6B339wviN7k5VMXaNsqlAwky22J6YDlx3y5N5bYwbr3mP3CSngYZCIFt8n'
    'Zn7zol71FlTrd3yi9dRXrdWwFoPuB++ixd/9xgp2GmpYXYUrHTnWm74cOk4+Zze818McMBhGsZ9hNou8dCno8pnTTE5mNqOy56SR'
    'z4zasZgYRSOjQIsNMsxrw2xOQwcDqaA6GMM8wJEqfHLBe0M/TR5qyh9JjeIGRaiatw1jkwE75Xy7KKDEMaB0ze3ytRZvak7r9qqr'
    'KfJ/485rGjoVtg4Ooq3k1kvZrp99W5OF25VnupHa0aMt8KZLF1ow+JV1Jd3w92V91iIZV9mnWkl1o6Jc0qpU69Eer9ba3K4gR54O'
    'nnNi1kcM5Aekx/a15Q9F3RjgUWb/xL2+375RgZEfKfy9rDc1IHxmfCr1IU2L6PXhu7dtXh8mHaA4nWPfMZvG2QF/nEzOSMp7MekD'
    'NOjnycxPWqq1oabYBVdAj66ZxNmzcD/a2PZ8mIbCxFLdzAhr9l8uCTdc7EGuYZ2q2Nsc5k/2NufDJy2BrtzYYMflCuL9qpW96kQB'
    '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'
    'JpahHXvLdIOezErd4C9vm+PYrEwunF8cOeDkK+W1pYbYj00ryqUww4bXFuObZcIx0Yj3K7cQQVRhMZ2RWHtG+GKzEFN7EHb4nn+u'
    'zgf39E5mWLktzFNza7EQ78uA9sWV0NyirfRojIFBZQ3iHED45dSZEWVqh2bpVrxRV9yel6K33RY92muSlTm27ZVgxdPKHqUJ4Kcb'
    'bF928/kQnOFKvOWOYi4eoVn5YbfmFebuDxYXaMi6FVI9Gm4PlLWQKV2GTMrz17ytBd+NP6t+cSXzv6yU6rq5dR0G4K2VsMdXxjKc'
    '+VQLP+LioBCdOTdwwXJlXcPQ3tBZ+eVqbNvCy+puSE6eWeA8C6gMV0li83TralieuFUvF9bVKMx7e+xi0utBdhLWN5TV3oQaXRPz'
    'Zm8PRF+yVdTA4rWSTaMg5FIEa3SiYIzW3CSCylACUtA1NL4j1jRSmdAPy/svCsGd7xGnEu2ewp9WCldr9zxwvIQ1cIsXRMr3w9C2'
    '0ZxYSBTB33SId11DbPHG9sgES0NFLAe2I8bzhQod4TnDKllVPRvTOLBW2RRtkckkKwRQ1sClGVvfAFuJj2AYfNI+YmGCenVCXIon'
    'Wn7/+s+voUve39vfa+79sA8n29H1F73luLnd3fviumfe9R7G2/S31zkxemR3MjvZZptVqxXZZr94uD+if5wQo+EIaqQw5n6rOBrM'
    'E9dJX56Bza06wTaqERXFIrEHFAQgGwaC25l9A0/1LesUXCAYo1xeHIv3s4Lv+jdETk+NuQoV1Ws9G84TattvDdSWcxOWtcwwjCN1'
    'tJOl6G1KG3yuJl6fCXcVXHxK0DvVjdohsVp+cZWwExoHXpqsh5q2OSqdcBYe24v3vncit3uTiANCMosEztRSvNZswTwNg7akNqWW'
    'pOCBiTcs3NKA28pG4ugPKwAHtAyI6OqOtdXsDai4slBNdAfxuRLDfd3nUMYs7GlrKAULpzkqKRVWksQ5mCaSQOH3ur+8vGGQVzQT'
    'ZWGIlwyxjKiiLncRd0MtjwqpuZDcFHxIacewpt8Qx9mYaDWt3L29d4jBIqSIeWDo6jmeI2jvFHgdREdk5fRzYLgdTtLEB72ZoPAU'
    'MMMf0uOimQ/6u3xdRmuCATt89FeZQvDbmuxWshDzpZfk0RJvz+PcrlAhI9DnbPlnFgViUZfdqifmEky9+xv7ROzwf8VDDk2DOb0b'
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
VERSION = '2026.11.03.1139'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
