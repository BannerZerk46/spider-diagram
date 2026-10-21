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
    'eNrsvdmS40iSIPheX4H2kuqMKDpJ3EdkZMyQdNLpvJ23s6YfQAIkQYIAiINXzYj0U8s8zvauyP7B/MK+7/5JfcmqGW4efmVUd4/I'
    'RGYEAYPBTM1Mb1UzfP8HxZy5R0sllu5G//GH7+iH0GVj8dudatyhAlVW4GejujIxW8q2o7q/3XnuPCvehcWGvFF/u9tp6t4ybfeO'
    'mJmGqxpQba8p7vI3Rd1pMzWLb+4JzdBcTdazzkzW1d8o1Iirubr6o2dpimoTD5q8sOXN97xf+ofv/5DNEn15SmjQ7Df8b87ZLe4J'
    'd6kSDvRMyLa7N+01ITu4TLYsvxaRzcLrumasCVvVf7tDhXcEGixcb+SFmod2MoeNfkcsbXX+250iu/K31JP7PzEluCTg0nB++xNN'
    'L13X+pbP7/f73J7JmfYiT5MkiarDQwJNQdE8oIokQRI8C//D9Z+YMrSjqHPHvwKQVNl+tGVFg2kiNAW94Gq6ito4UPh1dHmMLw90'
    'XIovqahdxzUtwpzP0cKEdVBZdmbqpo2K/kQz7ExU5nO4zl99ibr6Es3xjDqNX8qnAQ8K43HZ6swl8OhpDGh05eMBXPEYuqWqLZZu'
    'fG/jdyg0VcRc03V059n6FwABzcrXGIIF4dqy4cxNe4PnDN3osqt+oWiConPcVwKj1Rcqx/O88DXZoGEaqj9K21yrwQjneE6CsmwE'
    'Jp2jEsVo1DPZQg9s0zOUs0crUzOSz3xIZ5o901Vi5g8Nz8LsGF/jKWbigd2szuS4qD6M6sYb/qr7b0jvqE8JfrMBSNK7OuE/8Q77'
    'JlyW7C4JTAFNWERpyOWoJsXmRIIic5LO5IQslWOaFINK2Byr03ABN014TPsl2bBIQiXwFsHlOEJKdpJfBL+IUJnync9WHMxxskvT'
    'cTGrcGa2Zrk//kAQ+TxRsCz9iBkK/AUuM1UB61RAJ9txCUvWDPcbsJWNupmqtqoAazSByd0Tqu6oPms6Oq66IYDAXM1Y5KBR1z4S'
    'fyWA33oboJ5ceFHWVf8euA/Uzvnd/UboJqByzzVt4Ee5heo+QXNffglgVnwu+Q1X/uUrtE4Q//W/El82sjtbNlV4/OWXLxZwNdV2'
    'fJoGhovqfiMU2V5//eVrDldVHeI/Eb+gol+Ib8QvOiLMX77+Svw3aHGGKnwE4uB19Pb3fDiZ3x33iPg4QXyzTdMl/ophzWani2/E'
    'H+fsnFHnv8KtJRuqjkrwH1QCfBvuqTnwIRHdbzxXVaCEnwq0SP4aNIMoEApVRqUUGVWTZzMVrc0ffe6FipbmTrVR29ScVGeoxDb3'
    'NCqYzuW5GDbluDDTYamAqikmakiRFH6GXzMNH2xVVAMgoSSAYCrNZv5bUBbArrCqEjUPiwKLmRqiX3QxUteUHfeyJKgXvB60uvQR'
    'cTGVv9Acdx/+zUlf8Zyphpd1lrJi7r+BQKJI60Aw6B/8AnmP/stR3Fe/tTSe4MVED/5buHZ/QQuexauNhKW9vvun9HJSFAVsPLmc'
    'lEzNaDJeTpVVOVVKLqdES6LMnC0nrTIUI6aW05dgyeWkOVqk1cRyUjwlUtPz5aRYiqPEeDnpKbTOJZeTUmiZZdPLybAcKcxTywkL'
    'TMYTHy0nrBFPzy6WMx5puJxnJeGy+3N2ZTn5e1q8Z2hYS/r9i8ldX0y0WuFa/hloemoeso52As70Da5txFKgyKf7vyw1RVGNf0Kk'
    'rzmWLh+/EUh6Ev+gbZCCJxuuXzGnzaAOlprfCIq34H1ftId3c109+O/+iuVweO1Lz2/EzLNtWN0SAvXXlBT+RtC/nslfmBYkYX89'
    'l71ROWCFqwHPzMqAulCcZaxgRFPPdU0jOR7NQK9nEYC/Erh+VgP+6gBMAJAK0Kw8x9Xmx2ygzMYPFggU7qxpmIocTPUuMR9saj7w'
    '3Ua2FwhgEsOGfuiwHaR338NSKEhGRPUSDZDkn4IecR28xlN5tl7g0X8jdrL9BZEhoApe+rAEsAyKEMnMdYQ4/uL6ODI3jQC2PJVj'
    'iSyozrqa9SXXPVFEqnNTnvXwfQXq3hN3PXVhqsTg6e6e6JpT0zWhrKrqOxVNPdFSPRWeFGzQ8O9BOzecrKPaWkA00ez7047+BUGG'
    'tEYNqfYAtrcxQixFdgeYA3+9MkjMXGBQEeLCEmxgHDCljqlrSlANrXAgynLAIZLLnwBgb6P1RP/eQAS83jBFBF5CS1YUTDWAAZgE'
    'Ex1kwn4CwECfvgnV5agQEwvADca+pKAttEaIVIFcKC6NRCLGIYxCuNY+wBWBBMTZL2EcoOLIMxWRnT9A1PgfQYwji+0mOWw0IyRC'
    '8gyZMNP++msKKDoNFIuB4v3CQ0TNJJ6qq0ABF3BQF656cKNFRTaG5wSEFk06HS5DciC3+NXZcHPGBmpcEALuNhsXq7quWY7mnM9D'
    'ui0FaTIp/hbAmNXVufstABJwPv9nrA16hiPvVCULFrSxAKULvQ8C6uiAzehoU9CXl+ZeBSBA7TMW+BXc0Z/ziW6/YckH/V4h8Et8'
    'wpUDhNIMy3NzwGv9dffpXjOWQJvuldVML9rVtU0tCS7xF+4S4X0J/vX6yt4m7mtMzHN96Ryvbg69bJ0txRmZ36ZqJjGSrO0TDx8P'
    'OSyi4uElim7yGgzSNx2J+NlS05WYIQQvB9iUw3RgR8BTQTHoLedrfJPuUnTPI7rH6BxZyd8Iz7JUewZ6+q+EDrYIQIG6xUuXI1l1'
    'cz5YOi3ZgIurOrLr/5qQGBHmvAsR0+z61tz5Ai2NIkIK0xD2SagkZBgWSH+8mFfZSnKu0EIHcsUflk9K3wzT/fIN0EUGClS+XhU2'
    'STIK3g1fCOcmKkD8BU2uC7iXY2NAFXUue7qbbCSH9ZHL7rBOGhNLaoID7fScOHwFNQVizrI1WNbj1S4iggxa+SO2Rq51GNW8RLPL'
    'viLulOwxtIGS9ZEfDik5MXtlyIuFFiLJ6uwDOzTkSnRSsfLvolfJSzaD9KYQ9egz1ItR85DQrNF/CEkvSduHJVi7i3fo6J14PXR5'
    'qupINZytLxWQ25yJi4g7gcHvRPy4W2cj6/q7eQmWcNhqCojdMh3NV81sVZddbaf+GrOqtHS8FKshrAtbDkyyGC/SWIa7/HpRBzti'
    'oWtYR9DpF4HT8Yv/DsjPr2iN7n2HoCUjOwIVXLbjDxHhiY8sAR/wR5oDDDAAc9AkJQCeQlFyQnKKbVqWXy+SQkiFV2RnqV5IuqBK'
    '1newgiXCR/M7k42d7CTMBKzXp7X8CEumujlbA0s3vdkSWvfXwpdxnoM4uc9+ktpO0H7OMBU1MagIY3Al31C9WGV5CrQB2PErrLc/'
    'a37DN3SmwMwK8DbBvy/p7JYO4CvQabl+w7LxYT7nfbHJfUHFPFpw9pavA2P/XN5o+jEhz1L0ZNlq1qeocAICY0E2jnt4AWbmBD0r'
    'iCDoCK2QBe+8MrW+fuhTXGS54LtQtfA5mr9gWdAJob3k1LxlxGD+gRHuXWSfgjsHr+iy5QBKwyQYNzRqf4iRUX0Oquy5ZoIlIzIR'
    'z9kZfRO+KxJYw6iT6DqA7WbV1zWNcyRM67NMUvisp0qkLoPYIyjUoqdlN6ZhYiy5J6LLq9oQBhq7e15BCd9OxCaDjx1YZiV0uDjO'
    'kYVH90RWRIwu1jXIW0SDez6nmcj79DUxbAGZs2xS0Q1mR7wmiXB3GKpgMAEoRI527mPI0e0NVI5Jh4lQ0PUuZ2muHVQlog2aTJKN'
    'fxc1xJKR5cLyZGiAhqx1JuuzL8Bfd0siSzC0P4ERY8M4+wEnhU9lVFpvoTDLQR45Sgwn6UMGzsfwNuQhMdMLKCn2E57RO5fDegWW'
    'TZHIyXHhAvznDQocoCBCZLfzyAREirG/OCH3IpP8KrUm/l3wts8JkqvA8rtlcsboCO2ScAbWM+qzj6LAZ24Q0X/sG0uem0Xukncq'
    'V2+yROa6VZXuK2Z9CSs4Xj4yzcV8fL/ac9TsVEaaczhL/BU6pK+by6F5cimjU21ryfkJ1Iq00vGKnZAkdLyyQNec82tEtOEahY4C'
    'GrsJyNTE0lSkAqE3QH8grKSnE/4TLmp4+rUqaU8LTV68pmvRa5FzkLmolXM16z26MXvxZiwVUlgTY/VbLpE0PfsgRp6yK2vPvb72'
    '0Uob8i7GzQvHYZrX88lhtWBYN6xYLlblwVoGpQ+QDHHkqFNQclNvMKk4wTXmn6ow13RX9dXuYxC8/3o239Ocp4UDSlHl7Sn5GCdN'
    'Tw/p3992oAJcD2gYH7DnkvrYHyleZlj5Fpu5GWpL9Bu2xMqKKpJnGPBRsMIxlQ9A6JdvpyviXhY6dnNHevsNdT+1zuc2EcZz2QAr'
    'z2cs0O4japbKsQ6hyo4KMjELL4FyPkc5Q4Hy+Z/X6nFuyxvVid74K9KXYnBC4zJhGIbS4o/YLC6/Zf0ktPpXtTD49+u5szTlxPCF'
    '4S1jKaFWIqUz7Y69ME1eMXtu2kqfsskkSbo0yt5SM0IVbo5mzv4puu74SzDB0XLw0WRvNOMLhzj/faTX/QnUOmTuff36luL199Cy'
    'rsXXEhPyhPzv50Z/Ul14VyQrFjBUSm264crnLmystzy0VxzswQAaGrJgUqocRyJV7kyFPn/nm7qxQCp8k+duELkIoqm/tEwQVVOQ'
    'Nw6BM1F+ufR7xOMlo/G+T4HDnGqufIQVipcikr3qc7uqG0Bnb3l0Q5iC2FGECqkwMXlN+iNkScY3opZwROvdHrmbga6bkg53gl0d'
    '73YiXm3rI0G32PZgw4g3BsNdnOk01HVNPaWFCVemU0qKYuz6xjjrWSBy1aL8NvOiP8W82F8/F35+PQ8hsjNTmCv6Q79u0Ac49vPs'
    '0kDKvN8MZRImIlrvYGipxb9g6yFHzS3NDdINHNf3bYfmATYlsfFNXnAOOpDFwYS8mydcJUdceEPEpKM3lxN2I4Ljz3JqinJRhkl6'
    'wKmcGzrFPPy76wGcKw0B5Pt7IoeXCaUt4ILzYKTvu8o5S1/hC5V86lXFiAwV+I2sGckWzyYeMawQ+DDCDjaG6rwSfwh5gz/YBMuj'
    'RfIs50Agd/tf35908rbKEFicN6kgHkAX+8+xb/SWBziLURFzFDJ2n8QuLDEpfADKrO+TT3AULlhW3ONHnCBX5F1EJx/JqvHHGnlo'
    'wlW+zEX5KbLIH6ZrmrrzjlSeMGsnMUbxg0N8NUUnBc6lP4gNnd4XUc6Ll8P4evrlyOD69m0JM4mTMb+g17J7/eu5NE6R+cULG81x'
    'oN2vt2Q4XgtFnZl2YIp5SHtDkxCEt26068qL25DcCvaltCF/GlCamfO+rKn0WoqRiXUhXT7ixWXPXcUM/afrim0K4JyhZ90A99/U'
    'jagcdz1N6+PpGtcA+awr4oo3MtlyhNcJUyUVar/wcn44ZG1vZD1tIiP2eG2UC/Mmst3w1569HiUo3Eb4ay8C2pxndSaV8SvW/Ttn'
    'N6eoN4PzCWfUhXecO2MjcWuvJYhdvKAFNukrFiTzDgsy5Wa51HuuPL4ReIsSyS7z7i7h9kd6f+3J3Jx5CXaSAv8mZ4+iy9dyzFLT'
    'rE/1s3SzlMrxp/dhIww6XoBQcL4CcSxui36KcPTSOZ+KRTobBqLOB3WBTOcBIe6VkHcakr8EujuaP+Q8/u1uLuuOijYG3KaC+PXQ'
    'PRBsrkn4B2TXtb9gJyhwtZm6NHVFvYj+R9RyNcJ4Nmfn4QYx8n3GdZZ02sikUwmQOL5HJpymiReZM+tUSL3oJ06yV1709Pvkralf'
    'g/Is4nGtHW2zuBLiSaBmOtEkjMz5HYm+1XSNPM+6wYucIi6cLoAlKr76Ne3jSvWQzDNKNLlMzYCrJOTNW2oAH6pZ57n/oESkGAlL'
    'Xu35qsMm0PKuy6TE63iOtx7cJ9ZMPDNA2XOl019D5pYz9h1EgxJTXukx1oqurefN4d5IfQm2CDB4iwB3O/fhDET5VRU1STh2Wr14'
    'hxKYpqoUd53jHWZp/Egkyr6dfPJ2734airlJW3dBmgIY16pvzMbpDeS7tdEb2zli292PEn9+F8OZzRd6TH79OXssIhAv9i0I6TRy'
    'bGziAPFVa+9jJuxF12kPyZVk0Vc8JAlT+kfQ0G2CRJ32VNnGyanXvLA0Tb7HRX/bQE25LN8KW7x/L9AVL388llf1p0TM6Dz5FXE0'
    'f8/ZRjt80QzCsRfT+7OAIM39KZWxmUKdOZbxTpJ+X0XRgHG9D0Pf5S/ACHUV365HGFJg5/yLj+0yiy2yc+s/EUD8WMAqiN/dJunb'
    'oF/6Mch0IsMHM1vSnRi+pLxuK6P1mMqO5iS3uvkNOK7semm0IBO+3vdFhJK+RuqMcSxsTXm/So37pdOOZNRC6DPmYySKtFkYgu36'
    'TkZUNQtIYCGHadZn/Q7ycFqq7H5BHWbRVsl7BDGob19oDoc5qbn9NZzWmWwrKekTu0ffKWlup2tHdvqF+vN3iKomfQlv7iy5yDmM'
    'eRCRo7h03iEV5ifhyYqsRXyDGVw23Hf11zdDF9c83S9fskEK4RV7EfWSC/a2fpyRxjsP0rIJr3rOXXqbKTQqOxYsahZ7MBDSEXmg'
    'il/fyrH/Gfn1l7n1vqXJfsx5nBoPOmPl0np5JUU+0UKwZ/ZayIf+qCuQueF/CGBN5iKmvHgXMv2neLz9XvERO+8Nv/7Efh1DsyzV'
    'jVPpsFacllWR/fUhU+MC6jP/A8udpeLCZE/XmutvUQ9v/FwfXd6gdfs1WSdr2hpmu6FVeDM9MsAgWVncCtbgQYtxxFe88FldG38g'
    'g18PVwvXU9iub89KgGurO1XWX4OXT6Tn3shuvxCQiWTy65nd11hqCEyate41dwkKYAxoMm4Yc0hDRTHFjwW9k2I8yLgKph4fM/It'
    'ili8SS7c9fSBs2y3CNCUVcGk9vb7d+nTC6gcn9QwsJsL3sfC3+c4UAd4dpZKan5kpO1+yKsM9Lk+33c3n6skzydyDoOzRK5lFSe0'
    'vShL148LI6ZwQ9Pw98OpiG/HUZSwMIsT7eIJE8h370eJG74eVYvXRjcSK5I+fcI3+T964kTu9pkTYYc51CgSAbjta62lzCp/8xjy'
    '+QL892f3NzdrzWzTAZ1AsxNL8dpmrSiCjok/zpzIoMlK5qBQcXiZ4c7D5dEGiT2RxVrs19+/IYJ+exvEB/VG8h3ZeGGmCCp8/XAA'
    'H8sddXbDrXJrnGKaTFADmVRj749lBnXIdIvvUzWY9EtG2hVJfojiojyQj4YSL0zpdHMhJ/jY1tfPAH4lgeV7Pjh96ns+OMcQaYvo'
    'UCpQOP3j3u7Iu/BAOnSJ6/92F9FZSGZ3hGxrctbHpt/uXNtT79ChVt+d42Zq6ugQvzstq5sL8y46BvAObwpm4f+7H9/jY9HuKPoO'
    'nYmGf+3f7pi7/NXHTI7Dz0GWnNWgSb+GdOM5Ot4t6EK62Qj/jjrslX6CA9vufvpxbajxvD+dlzOLxOiNmY0B4gia2mVFmQLZio2p'
    'LJWlllk2WUBQOzE1DAaAkGmC9o0vAo+A04UsnyikczxB6gLBFxJl0BS5k+JaWbiqcsn7LH16dVDADs23BiXBrBEsIelclkvBDWVL'
    'mD5ORtOH/vpgoU2KVYp6tV9bfbPfDUwmdAydZs87pklCqkpnHZNBx8yrHaMjkmx0CufrffOERPDov+zrSGHpnvPW/MEw6CXFImzl'
    'dhT7anuHNzFMxHBRYhN+dHzo5KsNOp7xYXbAnhMZvcNHI9Ik/LI5iSHQPzqYSRSylYD8hBwPMKF/E6UItiWNFgv/8jmGDepkE69K'
    'OVLw24tLXx3Rxnxz+RCwjIzmyUcLKfgPYSeVlbLS5NUesA/+PaRejSmURLS3oxIF8AvLTicLsvRQmKQnF5rdsWcvAarAbDJVEf8K'
    '6BchvPgq0NiZcgPo4FhU4PPEEf8bCB5KjCUPurYRZz9jwFKSAdNJ4DeI/3BZJkehv8mZAPZKNnjgT6/zAFkzpub+rYmmAY8EmUJB'
    'm7B9+AcRAhRHa5yFJSfRdEJhDAlLkK+C4HuG34QAysizdRST483Sy6yQSzJikFRSNic1QKiApJEK8csCoh+myp5jDpNGgsk74M6a'
    'lvoOToYmJcfBqkgJ2QGiD4rJKp2UPFROgtdB9iABxBJ8akASh5pJAI7Fy5BLCimYCCY5D8gKlUAq50R0maQFeAAzUaXE5OuI0bw6'
    '7rV6nJpgEL+B5zTGczbCczqhYVF8As+jJeYJcZkjKURowQUbXojBhYjYGC6hoys+vBLAXgFZ+CrwyOh6k6ugrVgyCLUIWzgW/teZ'
    'bKIUcI0U8D9ooQQAJydQ52yFolIvcGwWtZMF3Es1D8wXN4SayIbtvKIuvGMQG0rMiSw6DZlGKCPQuN03wG+CGiegLEUBY59AEemX'
    'roEKS0LvGJAz4pLBayHBHSWhpWDeWAnHfWslGILHK8uESwwXISLAUjM+Pvi/4pJ6u8MsNshU5R0oAO1jVEQd+BciumDRgx3bRISL'
    'BCoUV9kZ0ihpxEOyjIO0TUTq2deXUdF22jv4Hh46aBpAATqbRTqgL5lAgMNlFv57XdXSVdnOorCF/OZss4QwZJcUDwsIcpVc8qDA'
    'Q3+wwCSStBSnAyZgVQLQAy5f7Riu3pxlTLmSjAYVaq1iVYjUdArNJPC26B6VLIV0/dflsQsG5uzNxZYIdpmVsB5AVjk0VtCq4fot'
    'rd3PFn17lOyOTyhCSEgOEQLBFFP8W4rybP0OyYg0ZQooOdDRb5tPqm59WBP1OWpsieRIUONk4GHBInA5EZB0hkQyFKK/mDsLiE5f'
    'hca1ZWf5HhYA6A9rxIPefmZmCWdykEd8YcieSUP2XLxhaqZ2vM+id/xbEkN9m3IoacYCD+CyIMSyggP0g36v29FUaEhzNwx6Lvn8'
    'tlXh2tr6bWsY0K8aLxdWDBnEQ5BwOCM9Hg2EPkfK7+i49OATEKqN4QDeRcx02XF+u7NBefyBnXvJUnz4YVAOTwIfLoJ7WsUmfFAv'
    '+BgDcnP9dlfQdeJoejYRHGvuwDiQhyaqe9X78t1z1ODLDX8MHAQYeoD5e97vOIIDnxiEoAiO0oy6LgVh2rmmoybzqGIwqjwM60MD'
    'bKn7qF24Dkdz9wNuLiBKvtjGmmTwJrohZHQ6JP4eBgKM+FJybT3T/kr87Z//L8KEebLlBYGOAjAN18Snhfqu5Lsf6O2//fP/fLW7'
    'nryLJwDdBO33vt79QLdvvlxw0q8DDDKBoiQJYHtLbe5GTRKycwHVjQn2T8VEa3F7/okoOnF9JYKPiDShVog6smOZlmcFyOMXqgdY'
    'bUVVwqzlaFD+of0OAeITz+5+acLAovUMmifSSEog78Y7MDV0gtxEVjRajKvJUQTdbPCN33z4QnqCQi/0Xfz4SgU80rsfDRnozk1M'
    'dVDd99oGLwTCKJicrpqVbRsdY4unJgASp8qgsxxmsq4fCX+/N7RNyIpyT6D0cJQuulPvo0xhjMeqrrqAHMFWcJgpPyne/0gL7ndq'
    'Hu7wbDgF6OHuB4F+AHzl+D2PoUzBbaUGiVwJdz/qqmo50WZzlCMOAGIsA8hmKNVgrwE4moHHg/VEDPkGuB7++EPue956dTJjVhhV'
    'SWJjKRhxE0zumHIqoCchaOwjgfdJArXLhGLuDUROmusQ6DKcF1w5quaco8wrnQJvvdblFFZwtrwnQEvcoVgUirj6363wAx5O0Kdf'
    'T31Pj2VMTcn+Bsb8vMe7H341AtDkWptnqHh++1k87yG3/ofQvBjgi7uUXWKJWFg4FUDhcAMDu4e6aOsDgcYTJALBKqGdDEs0rfrx'
    'dYQubyyYD6IabquL5v4aZr8CalmeLQPofnFw6ARE6Ryw1/E5s2PO0SdLHBcacM09WPAORjDVUJzXIaxAIwAh+gnahdHjE6pjvLgE'
    '9R3k4b8UzvH3YA8k7nOEuHo4tKq5R24ENSLfheqGn2JBMXIccnJ8MeiLIKy1/fhuWmgmiZ2se9CMARwLAdHCv9/z/tPzWuj4Mw/Y'
    'exP/3qqFwLn7MYJ/b9Uw53PoysSwoUND43p5f6A/rsxaNCkNGMDZlOCiWGUxDQMeAfvEwaqLwc48eweG7o8S/r0FJCiRMkI6RBv+'
    '1bvAvKShDzLDbuh3DEbzqO18QYK5W0RjgXsyxDr03TCfNX9CNQxdnaHAJbrpxt/Bh26Ilq4aUsWVEQAv+Nu//CthoQ+QhdAnBc7c'
    'Njf+B4ZMK0cMDMUkgBD9phDbDJtGsfO0CPrdXBGvka8Unw+KQFFUn/yBbTuADy081EA1TssYxC0G+OCMSCfBZVhx8k/UiGf3Ndae'
    'VPZ+h94HssW03ZTCFJxO/Rk10G8NfVcOGQ/Iw490FtlnPAG/x/IM1fo764Lq5ch+sir4hAf4pdN6/PopIvdZRQ+de5BiXuhMt/Mp'
    'tVUcVQfkuuBe1N0P6v/7v29xLfou2C+vKj/o29WYux/M7adgJrPJp+/hyqWAGJNDs4xFH53QdjEGYPsgRfCx5XB5CwzdZ7+NNO9N'
    '18FHv/14gH8/yZ2vqA2vSXw0pDjhF0R/4i6RxPNuqZ/iMQu/6BojMa1jQr5ZRwLQECkvM12z/JjDD1Qc85JLqr+k+LA9ZI6WAzsU'
    '2k0aon8ndbPtMwfiS/jJtK/vkydlrCljS0BG+5kVvLUWlB8d7CQ/N9/BPoBQUwRdaIb2oiEXDbJYc8STMdM9pPrFRzmHIukzdkwC'
    '3QOOV9nEU+3LimCeRyDhoo/FgU6G/Bgg91DxPfFomgswoR/MmYPV5YY2tdX2fK7N1LMuodMzGjBnB1C4UOv5VDtf0BfpDl9vqnMK'
    'IkJ7jW2qL7mNcrOmewBU7+hIfGPe/iUHJTdrm1NHA6sXWFc7uIInno5eO2lW/Fp6IkOq/b261E2Ces0UtI4BRqaJLFjRDxJa1NRr'
    '9Oa7f0KqCzq64ph6N9cKvXeHjjbr4mHf5mJBtTsCF4OoCKkChLelzVwPrAdznnRfvNOXELXu60R4ErFhhV1FG9lF1BrSIsZzn3QR'
    'LcMkJ5EXNAmE0hc0eatXjGK421DkF4hg2xYMBSdN3GOXoIU3ciFr6Z5AmdgJuxXg8c8fAObyl7/gy3/6J3T8BeAtWIS+HYvIFs1M'
    '0DjQRIjm97gCshxhyqwl9j8T6GgoJ+W9BR7k4mZ81RX0QAIfIeeaZgBRmm4AKwBw3Cdy4looRfa2uvtOTfGGCxqHQa65oPseGFSa'
    'rKPNTrJtoM8xIbJAylr6w8T3YHWpFjE94t/POKoRDDf1vSS0vnJxFdwezCMy+lV3r8J6+e4DtDpIYSA2JjJRPwwZzu25Dlk01fHF'
    '7wkFlNB3kWL3v6IgFyBGUyLwZ4dani8Mv/Tl6ddPjAgniEVmXxH38Lp3W5sCWSzSoAW+OQOJhnPwEMV9KaP01d8PX9D5qwAiH+IZ'
    'dCYAZCd8iBhEzYnd1b8TrGbY8quAVWxVPVvRORRl57opI2d6wJOIL8jta3pwmQWZA+zB3xuB/bE+d0ADQi+Ec/z7JxbB9irwD9gP'
    'fZ3U/GfpVQ/GErLDkMPeE0G8IKqIvz7+xW/iM+PwI6Xv4hahwzft7cWYEJAWlkEIYUPxgIx030ULzN8P2+S/IrHmt/SucM0rVD7A'
    '6a3X5hQ7O/wOJ5+ZFpw4+65Z6aq3YEBPUrGqT0GCU2nfx801JdaR0A2h4+DLNyIMp5wFA36JEQt4j+zqR18AW0ioRv4mHA8Aml+o'
    'iA3c/ejjyMhrhKq5MYrAuocBHMANZ2YjaeJPCgnTAc//rnKg5ed6hjFTM1CkAqz1iQyZO8jlDDwOKef3oQaHNvyi02jg11dqfLA/'
    'zYv9vNOIZ2BgXpvIeREnulxDLfQkAKf4GVBwCs17kGr+FOS5XIPCfxbA8fQZOIIsmndB0kPfGkNZTVfVFf9hYF1hgLIAUOFv//1f'
    'X59ibbG41ab/LNnkb6jJzGXsPzZh572lbKlnMR5QYVFhQt9M23vQqIeIA9W6ZRNamq6DCamhoNb1Gsg4+VE0D5fm4VlFf4cucgb4'
    'FzeNVhVZrfgDCaahH8/bPTc4U9NQ0RJRumAW5ngIb0zC/JUR4j1OYPChn5tAa8ZbLi+8LxnsffTz5qCSyNJVHTVmbSWkxycZyS+R'
    'jYYUvB+49gcknO/MxN//S8VicLAtMCZj/SCIdX5YZmqgOaW0KGCGtoqPQDsbS2jHIvaIotUzUFNl3TF9ezSgiOFXP1vEtJDc/wwH'
    'wHntEVPs+J1eSzBJoJeGnMDRKIJ3CLRx68JT2gN82ci3car5VjSugXIY7MVNKhlDhXH2rMorWKR1VZSmcEtlQM/Cqf/EdB7eMq8+'
    'EfNo4JzgAEJ0c1VVRfFR40j4tkJSFUeZROgFrKkuQb/QUVYRVmtnpm18TpbiPOUIaxBQr6okKL756VwdFAO9J3Bg13dxAJ3M1obq'
    'OBdkGcSGPzEaNTUa9e8d7dGjCfm7xHqiPvqILjBDNtR3eSNhLsE49s9lBK6Cwsh+CDrplow2gEd5F7cdlLipXSg8okX1RUlylvXz'
    'vRYMSiK+PunJHNIqw9yc7+ug+EcIxPaff/vTgAm3mKNukOZ//O2OJ9iPwmgiV2MMo3/794SRzJEUwYaZqUlAP4c4QUbGLcQpYHp+'
    'D+ag3dwJEyLgBP9eyKMaCfmNIPGjNsifIe/lYxz0R3ueQSp+meOQMmKY36LknCAPyzRC9v31Jw2Hjre+Bk1hrc9/zhK8nhWy7E48'
    'fXDQ+HirW8NGPuCfAL4YrcZ18GmA/lPAT0EmpmEHMeKiE/mXYYbUz4D9I1P/8RF+jgbxBq3bNNgPBel7yBD57GL3Brr5mdwIb8pP'
    'HddBfXCZ/aPGE4wC3/47cQmsoiRn66eQyGvT9XnO/UoyF1IhfKd6Op3Ld2Th0CLOqo1dkJizyRtQN00ThlywLP2IdFM/wXp61UF/'
    'vd+0tVfEPjHfN++vNO6B+OKzVt8yWphqEJIKMmwxnkcpk1+vGoW3+m9gGoli37aG85idJUpv8cOXZjB0BMA9oeYWOeIf0XHBv+5N'
    'ew3aKHB+//7SJx4q5F+RdQNt3QicXkIVOrLPfdcBGD/PFU0ETetXdPt3589FYIcpZh8J+sUXyUAw3sfh+wPwFTpNy3J/uwu2U9zn'
    'Vo5p3MuAd9oMn/6fRwVJ1fpGczhU+aDZd4R/0Jh/NIyJHLbwQLMAfcM2bjeibRZpsLB9nf9z3L9/UAnabRMZA/7RFwkAE0QaHnwb'
    'ul2X1CfMG3RoSRyESkU7gfVDk37b/pBCiPzTYu+CITrBXeKwdrSNAh+Oi3HRuY9SeJGNhp2tKPBLEF+IPPH1Du8fmJkbC2GVn0JL'
    'OJaq6ziEHxp9ASQJXwMGxUxoH+gmyhRN+wJgwXBSUxf/AuOZLZHf/aazCm8U+tGCf2+4DpLUhwDpAxeJVQkcIM5Oj1kcMHaDALOf'
    'UO6qMvbrI88N5pZ+yAvRPeAmduYo5u8NLhNhUPvM2XAGdfkgo2k/24BkEKpfHgcIEOB+uB998zWAFbnVVBk75O9+L+4FkLwObsU/'
    'TzZ2wS1N00FbdDTAtfCwWZSi7+Okz2h/z86y4JiCOJro9/E6lEPELhLZBTae0rOEoSjFAmevh/P8JXTZyQRKKEJejNRWr6De1/P8'
    'o8sNVmcwvbnNDBsn4aceok1n/qYyXOPNLvAWuBt5QT1kJQRZ+j8rNp3YZvc6YP+RcinOQCvppnMDtFCtSabXEF/KzuzrT3M+pgN5'
    'Z0TWQYe03aWEzTwkv0AgXX//yf/KXPpVLSxM+rF+H8v4w/WcuHM4+jhWktrdebYIQcWia1zg74/g2eurGFRq3Yg2P5jGLyiVHFTR'
    'hXxuHP305evhI7PTs+8fo313Y8EebU1J10dnVUa1w5/wlQ0eQ3yPDzYMDkSDcaGicEfqd/8WlF4dt7cIS9ABorp8DMrC5fyO4lrA'
    'vmU/7R1/lyfEmCsaQVrj6IMyEubrAK9CTYfNJVQ7rHXGX4J+rfWNfNBVY4GP60GbtFO9YdU8Vq5xh6l5Rem60aRG+bh3VxAIavbN'
    'xSIhhXsoAw0kwRLtfgpPXvHti5nnfkaORce3xLpe2NoZavsJ2uup8qMvT7/n0QXaxxnZZwkyiqviwHuishNmM53Xxot0YfGYeJMo'
    '8f/+P4TfmjML2gI8mqm6Ez0JMksTvYXbvm4ABpZKUNHfbnqjmp/+EnYablLNE37g4fWxx5kHIUh+9sDVyn/7l//xt3/5P/72L//n'
    '3/7lX4PqOKzka5agZV6+18ExvUgviHaj+IqDr1hfvvWAYzum3/qXePL8Tr8R6KuAIPURsXxF0xvECXGoyA8UhflktpqVXVe+Nv6H'
    'GwEk+SIEhfQaDERBD0DIoOjTVyLRYRyt0oNI1uZKl0nECQx81HhoFvjSGxkmuG3fGkeZLFeXI1xy9NHqaDKJL9MjgfT/e38p0dz/'
    'EX3w8LKRJ8Ov8o34y1+QrfBP/xTkoyTW5h6/TMBftPPST+P5Izr+Fx3bnoN//nHh/up/JSBKH0ZpLY7rm0v4K0POGzORTKRDfaey'
    'Kn2N7jy17luQpRe6mREWODMbkB+1cDJBHcR4IS8Smz/QI+g8huZSouCvxl4TNf6Xwc80gJgrJ76WfsZrK8nV+YYXF6mSeIVAtCiO'
    'r7wir06YC+2v2McsyzSc6AvmyVFcDCf6aHSsDkUnTfjPUppHkuX7jx/NS3XD31CHjmS/moXvv9iAvzbyDmGek/bnhT+yg2QHeic4'
    'Uy+Qc1hSYKoIcq7SYivxBdtYfQlYif8R2vOVDUYQfz3n7pO6XToHK57L+EOzt7U4XOcVXRo/Cqj5d6aKvUcVS80J/tLrFe+FUUS7'
    'QeNUCdmW/dT6IKz6h6u5OBbaXYx8nLccF0v67kfVZyM3qzB3P3redHlW63qH8ZfO7n48o5+baVA23hWhnCXuXPeaYGf4bIMSAMxE'
    'NvjfMXnusufwnKh/m5S5y/4TZ0nFqbHBx3d9KAafzI8Nmn0vIP6ZQv0lcPjFMmGyo1I3KP04HMFJRe9eDcNRbXdgBGe1YfYbZ6nh'
    'PXBIJuLtACA0fU0QXSN/Pt4s97lkFejmYyC2rwDY8jZTVIhB/CQY0Sl1b3sOjFTeT5Aq5js0I50II1D9dyfwvI3EehKWIEsKl30G'
    'dd/RN56AJ//M1ZB08cJEycG38uJCHRpplsSn7PDrKXHnFlSCx/dRlnLsCsQ5y7dY+90P/Bz72a6zWB8BsVMCjRenQL/BvnEQD2EI'
    'igGD1L99AgaYPX5N/7R7/9MCb7QORhXuIAgIvXK+BtTEHQQ1/T5eqYzHFlW/MtK35Io/V1XT1k5g1sh610ssxIN/DONnk8LCUxzf'
    'SyQ2popKcB5jKkk1mZb6YThS5zy+z0MUfX3zjrj4fK+fcZfUj/2S80/x3sjWR98AwJFQh9h4aPu7H+LQQQrkrtlHKbMvaSXhNk1D'
    '9W2laBsvCp2C+vbH0Eq6BxMKMc574s9/RoL/z3/+mrtmd+AhI44Z+2MS32N+VZ9F3xS9+3EGO1hFMaxwgzltYIZpeEgoWRrsKKA4'
    '36tRdmbpAHRq9+nroUwMyNNmcSVueBF8/J7Han9kBfzh+z9ks0QfOlt4UI6sN88mvgTBHSfv+/+zASRZ9DSMlYIcCY4AIRjs/v96'
    'j/d14m1vUGCDKLY9A69QlNcUbeEkstmUDeIim+6KBRIGqQJc17Ud/v6CjrPAz1YE2gjsi9g2gLISmKUJKyuVzhKdJnfdakBv37YZ'
    'GqocnE4The++hEIFhAy212F5o8H/p+CjNT/JqLiKlWgOcMT3uxaOoIhv81rihSUTPozMpiWTttHhUWCcXpjvnvuAs+oio/ajTAlv'
    '2Y5kZOBtCZbn1qAMeXf342xtijh5DP0bT8ory5vCivLBteWrtjc8bOGho38vreeQgJyZrVkhNV6mDPiODs9+ANZ49+OvfyDuAi78'
    'jbhLU9XdPTwMSAmeMujWCc4YhHv0aZ87dWMt0fcv79BXBj31HpXp+NwnaC440gkX4kxwKAtOq8JlyMWB95f5L/+B+G+oC7Rh9UlB'
    'HbLoNoi/hx2SwQVxp6E65D2+xrtKoHUK8axe4JACq85/eogrHuPL4LCQb4QBOrpftAZ1HAOJ4gR+Ef6kCyr7Iz2lFZYOiv1QfdSW'
    '7wGAWv/FI0lmtqR/jJDWsMEurXRugl8jD1X8KwslrDlBKhGOZ8KdjPkdSj7QdNffXxoG2TUXtIf5PQG6YSIEj8jbUfG7DnQbF/ox'
    '+VzQqxV06unBha5Fx5nhXmTCL5/+QNyQQGwleHX6Izxr0E+w90+XC3yIcf4PegN7sQJdEpUl9p2Cqe04UR+xPyPqJIQUAIsg7GM3'
    'IAqOhy/OkTSINxLGbweLH8xYKIwBCAPEGFqMsAU6HpY8RYp/4H+dybZ9RILCdxqG1aPzr14FtHywVFvb4JNZbVXVj9/SQ53EnaK9'
    'oDirxF9AX2EIK1c0N64Z7msMkhgSi45jchdw5GFx79DHpDCNUWl6odL0gqxQWVGcyOWaoJgsnWMlWhBohmY5jqJ5klOzFBvTUZbi'
    'uBxJUQxDkQJD8tIZXZHnFKSSDMVQ76IgM4GgpcBjHnvZI5f5tUXopFAMRhhP5bl/GSgUzSPKC0H+bcDa8LU0UoYvooSGcD/99c5R'
    'lCjAtzSqXzY41wzNWeaiGokIUVwPC2sncUjg5XJHUwWcJAhHxQ78dHABH5fpy38QDxjtziNaMKwYZmcWQxIEtGJOEuMYncYxOo1j'
    'qXgO3hgWRGUSuMaQQk7keYoiRUoSaIqJsYxhchxJSoxICZLE8CTzJpaJnETOzrCMuoplSTYYDhqBm+ANCazb+Gzi19TmeSLg8ub5'
    'QiqpdtC7TnhcqYz2PqrX0OfBT6AJ+gwbRMGtBEiB9RFD5MdJrrU3QnwwbCY6gjZuC/jcl/BYYJTgCKpygr8Aphw/fPRsGChC419g'
    'LhUOJ0xVcfemv6PLCTw//rme2Ex7g5sxaUxj0piGjw7A+xUU1ZU1PcXMuJxEChTP8gwrcSIvJlCM4ukc8C+SBT5H08DohLdwbE6K'
    'M5I8wzH6Ko5Z6RNp0UT9YmPBic1CzH+MpAQNlyvTitcJf+v13s9DRhsPo0p/++//mlrNi/glpvArUjefkJkjrHsk9uXjwxXwwTfI'
    'BAYFCfkICTZG8RBn0EmRZ4f8xuCgVhzfZYVA1sLTTtHJtID/R6CcaYKdRHMc5BuESmGw9Gx66dn00ld9Cw0MKg0fyh6fEPHTkIB5'
    'FxKQEcBcGmDuElejRQKlzUVf6PSPS/w3hpiKIObTEPNpiOuX2RxJQEU2BwBxlMQxrMBxfFJPgEeiJLCgKfCgT3A8/RZ98bwskvMz'
    'QJmr9IU9QAGzcPHnEoNrOyoEufi3f/6fAabBbVSOVYXz8nz0Zj7VHv4G43nbyo/UMUD5mNvFekLYmBK/lNBO4J20zD+vHsOT7Lac'
    'lPOv9FDDIgdrJUk5f09UaMQZeoirf7DrVqCKIAHwDgiu6TXv68h3ob7SdKrCe1ttmrvkuThaZOFc68HfFbZWj84He8FcMTqp5pUe'
    'zrjxO5cA0cBbjX5mynEYM0/48cC3OihCTT/m+NFe/EMw8r4wC47DeKu338Lesh/sDR/bk0cnG5tv9TEJ+wjO1vlgT/jUQBiV/+mI'
    'tzrrpTvrfbAzlN78Vhftj3IV/6Db8JSGfHQw5pu4lh5L+aPUornxST5v9UW+o/F8kl3nkzIC+VvUhK4eyLKErhV43HztdmrC3Sar'
    'q3M3dHz4dnh0lJGJDj7fL5HnBikeSKm7ZiQJaeEqpIUrjRxXTXmN1Xm8B2xhmkpCwPI5BoQqMpGQJS6xzLktTjJCTgLLh+UoSpJY'
    'UfyJXq73W0/BySLhiSPxrNrBmeORrMwR+AMAV8+NWpiB+wVNcnAOetpDklRAz85Fj/vE55In7BkcwwjPNL9mLoWtX37bIGo03BDk'
    'fybQdxlhNyf2eQVn0mPx6G/nCNDoDO6EYQhW1w2fF+F4Rh5l5Ico6eCUf9W5luz/huEkprFPTGMfPl8oqc4JoLBxDM8ylAAqJy2w'
    '59hGCUyOfQXbhPf5fiL4pDR8Uho+dEJRStmk0Ve9BI4iSU4kRYZJgSZJOZ4mRYHlBZ7jxHOHgfgRt5R/yBLUwkclxV61Mzc0deaH'
    'LpqHJLyClGMpkmdFVqQ4QZCEJLy0IOY4kWVEimYEiRc+BS51Bi46tymG9twJeOYFDI5sSkAs0jlSJGmKpVhSIBlJSgEs8jleYDhG'
    'YHhRELjPQUyfQRweIBVDfeZWos78StEZUgm4aVrI8SJLCwzLioxA0WmklUTADIanJQCdEthPwc2cwY3BiYE+81BQ5y4KQCOH+Ees'
    '8CTgpiQyB0vPgRVFk6zACknzSWSlHIyH5nmJBjuQFt6ktasesBjGM1OaOrOl/WNMYuBYSspRAiUiRABblEshA0mLYIQKNEtxDCOy'
    '7Dm1Ucy7oAvoBx8bgAJRGIQY4jNbmjozpvGpW0l3InIaUpwIULMS/BW5BMgC0JtII4NZ4niwn8XPQUylIfbP/4ohPrOlKf6cQaAP'
    '8fhqNqDD1D8xLiHuyRzLAqJyNEOLDJBcYgDAR3JAfiLY0iTJSswnBxCQE048jKN3RJhcmCzC2bPwRjy8M22GEs4Ztp/PlGSCFEfl'
    'YECwKhLwbpbmkrQJS5UDTg78hKc4npKkt3D8NQ+ctlmE4AHsNhrLHcoE+ebnH6wsdfHrVHZUnr3PS6s8Wyg899aTWndRKBaeC3AH'
    'v4WHPLuovvQGrYcxVez1yUmtXx7AszJUqD4V8J/nfaFQdKdG9zhYK6WnynIy0gpVaA/eL/tVCsXlC9PaF97zB/qW3Bf8C/33G8+F'
    'n/BHX0/GrRW6EtE/pe5xVNFlBFgFg9c1wvu6f6+F9x3/nlGqRRJdDfz747BSe0BXE9ze0ji7187uV7NqDb+PgXg4uNPqcBXDh+ep'
    'ORlxwwGepQX6Z1aoNguDRbFaKNdeRkNzEdae8jD1DysKtbT25zucZ20D8+WyA9STjMbwFD4q9dD7nSX84zpSqr3UfI+Ly9mmHC8G'
    'vDnZwPNO3YDr1giKyhIqtqYx/MXXx1Mq+OMpzwrTfXFXeITfQlFH5b3nold4bBYaCxj0w1OhWSgcCg/TPL0vwvwNHooI2faDMvxW'
    'is+Dx+J+/1Tcz6rFvdgo7dfN8rPYKy/LnXK33K8s9+Py4VmudMvdx1L55XFJKtWDOC8fZlqt9KTWinu1ehD8tp8H0N4M2mOfSgVW'
    'rRTLg+qSVX/fXyEPw+2WCg/7wmjxUOjB7C8B9EO5mBefC497TFvQN5Sl/jTLxeeXamFRzR8KhUwZ0c7+Geo+A3yDp0JIOd3KsrBo'
    'lsuLweNTv9KdDSqlhQyI2W1qTbp2XE/Lg9pDrbdYzEZPZKu89qqHAdPZo74BiRA9VnzaTf4pl6CvSnExe0L1Wkt4vigDjM8wx81y'
    '1HcR3l9gOHvQd3EwqhwWk8dl8QB929Uu2+sUxeLzqEnW+s6umqcXsJT7Mhr/Q/m5kC+0LerR6i4OfP10sspSdzt4aT6W+7hw/9Lt'
    'DGT98aG4/I/95HnwUm4+WdtWb+M8jEpLvVfjVwPLLlCL5pMRFBf2mmpSdXnfenko/a//fAGPH2rdrvnwPIAZ6R3dMr1oFfsDebn8'
    'D3GVl+v1Lb+2LGtkDYV1tzo4Zjp725vOe5Tck7e6sB20PVZYOdOiKVPPGpXZuANh2O7QG/p4aJVWzOywYybc4EAqzomcj/qq3DVb'
    '+cGE2enmysowoxmliUVjvO5tvc3maIDiPD82j4aljDLu5kk7TOes0SuIm+NO7tg6b9E8a6622qaW35dObcoR6rIyXQ4HpyFz6ghP'
    'nCqRp/XAlOwnl9pvG33xNOSMKjd62mU6k63Vz0zaVOfUFjtH6M/TZZkfbK3xrjsQTk2SoTe89WKvMlutoXf6e2Yi1lZLvrJq0N29'
    'oHf45qnbMar2QeqfXFg2pXIal2rd/nD9onRejOlwKtaeybYlNEzPe9k4rDgWZXtJHjrtGm+tMt3aXp1bVL7gZYRdl+mTfSac8A07'
    'WZgbsmjW5dWg+ZS8Kljb0mN54FP5M2DJvz29woIu5S1gQpcajroPwgvd6bvLxu7JGmwV3W3tpvxDgRoP6kpnL3jD4dHUJkJm23lU'
    'i2tWbbWHc9M55N16SzqMqt3li9tyy31Fpd15pV8vdPRx4yh4k7m9YyxlOPAmnUmjsoHF15jpslsFJnk48kiK6hnTKTbnTz1pasmM'
    'IpXUZX/7UOa0vZ5f2W6jva05xmZJtQ+0O+SHW92z8sVxc0B16T6ZKYtzsUCSGY+ttKdL6nmnWeyBOUinlYJHOu8/dGqD69ypuKy0'
    'cKVB0/534I99RWmQlrseqvp2kB9QjUeKn217xpNHNniqkdfz9MxyD/3h2Gx3K51Wt7OsDPodc2pM+BcQEFRT2pFrZlHobPbSKJA8'
    '2259O+yq3OClelgPrelB0OWM3dvqx1N3OPMG5GDGbZ5Wu/pUHwzIEyzrgmUwSFWKPB1q1wCuPBZefJb20io+BywN3UMtuUBWHhct'
    'qNBCFeC2uPw3fV6iK8q4epQbO7OrMseODuWjGeDZcdoabrgHa6u9GJ6xGDeGxy01rihN8UU3BuRWH9aHT7a5kxet4aH9otdrK2Y4'
    '6QzH7CPV2XTGbnnHt3TqRaLb1YwjlQ9Ufr5dSzIpdFyO2jTcasdabdeFAnlAyl6BYtqM1FQarXp+ZAv5QqnJ1Hbki2TJPCWupbrR'
    'mVSOXl7dekOJz7BSiS7SijfxJv0N85Lvu0dWkE2u4XEnrtoUerLVX9G1A1/LtG1yJW7aiHu0CvIDoxtGveYW5NLq+XERsBV4AJJo'
    '+gxl8IseYDllgro7DW9CDuSLKtRAIMD+fWsUN+xmPnOf9MqhYpsS/9hClaiMJY812ZhIJ33QHfb5A9M/LY6zcWP3oqv5yXaw4d2J'
    '2pkJtva0Ww7pCjmsdOFvW6UW8l5VJ2Nnd9jyxsvu1K8Om91hRqqRki3TQr/kjdiNehxmyE3e9mi+rHrexjgN9uJqPVVKLbkr87uq'
    '90whyB+aZJ6W+fmKOozX1Gk27oqOWp9lrJejsnU23KMgW5pBGRm1sGMaOr9T2e12xwOO4sFKDw5tK5rWULzNk7XSy7OnBbfxtltu'
    '2EJcMZqhEnsMJPWoaIfojoaCiQCuimvT3L+g/9GiFrVVcbH/j/9bMPcPJbzW9eZj/XH4ZGC83L/owAFfHp2Kzwv/F78qdhfPPtlt'
    'EWo/jss9xLhGmHHVYCWHPuPawPoOMeNCz8uz07r58DCXrKPQsgbSUCbpfGPX6ujSWOzLQqM+dpZzj2wau5fDlJ6vRh2xUBuX1U71'
    'WGqJ0FO7eVRdZznMK+Ij1c0LdX2b767GXHU4bzLqcSNNHUs60sZhRiknuV8yM6OJ4a0Ec2rxj/B+p9kwWuJunK8c288GK9P554Ow'
    'mRvjjgvcy85XlO2Y3dSG7nCy4qazzOxB6QwRknJ1b7jerhrrsZ63BwOu3e/ZJFehKuLAHrj5fZEi82KhwucX0BOJeqrz7T5XX2Ue'
    '1k2rU5eG4qnmSM/iSc4vT4KWX3XrO+rZI6fDUS0jay/ibt8ipQbMUrVAt5320JzyPaPqWRK/3JEDWq1RrjxcH8XHrXHYusOnnTfm'
    'NopML/dToyRbq91KaE4tCnEdql2jOnv6+dhY25PtmBzLwz4jMbvWYeKNbKo0brSOGve8swfDp63K0rpRdxhW8byaYJWwQEHLV+HO'
    '1++t9f2dz6HssTxHA7BDXt7HN8Vt+4VfsvaqrruMzZA6185QcsYdGAZfBnmzm1S8U383rutVuTytmc1xh3so7ustZ1dzR96BtEY2'
    'f8z0FN54mB2o+fHxZUu+GIIhZ3ibsoV5V3gw6lv4o8Pf0dZSqeFQpfpGcyfLTLctvFjzaafUaRhSQbGP4xG11Ssmm69s7XFGFega'
    'NJ3nzJlwrA46Dc62ZkfeVkrA0TOm4QlDydruZ9yad3WueqKO3rZdLkB3NvxnFlqzc3/U4CACflAC3aCO1JAlh3Utw25KL9vNZlxo'
    'L9j8VtBnk+30SE6GJVVzH7f5VkfjyN2jMp6N9YY9Zw71/E5yO5wljjrtxXT6SJ2ah8yjtOtS/YOkvoBuOlQ8YdrjZNvyBg1mONjy'
    'DaEvyA/HBuj4p1mJ1U/l41S35j2tIQ3nrTbX32ZqPNPlp/May0zAdhlRojxfW6RXc6srRq0w7ERkxb2yRvi/Kh7Fftux1ENDqvCr'
    'gzX2RFKqus3V6GFOUiTV3Q2ObKkGkrzkIXkw8nFEATYTYMbYlwwYX3zJ8NEa1bYyUAZ0u8McmtWRpNdoWFh7Ombtav651VnzkvYi'
    'nZjZqXmqDh62dGt6GrdmyqHywA2FfHlYtdyB4sqZE6nKRl16lqbj6ZZ6yZcHtmwK+o6ypMm81ulyNp3pHmBpPWG29cZ1fsvzuroF'
    'q2w41PtjLgOC2iVf8o/qzszXmkeleNoNd0+zhT40qnmlqaiHbSWzG6ypeW0nz/idbG8LM309aTG1LSO4/fWiUHDe8GO6S27UXzLr'
    '3Yub8U6zPrWtvAgPS9WrdOvTcZ1u7bpSS+67gBjH/BO7fpxok0xX6wnDntBeHYtCZzHxagY92L2o3eluoOryUBiIpEBK1rqp1lm6'
    'u35xqYbXUr2RTEqyZg3GTLUv9qmDwfIDWuSprk7W+ON8aE+lSts6tKzGcF7KPwqd8WkFOmKlpvXJ1uJgeU3eZsct2ZCs/MTWMta8'
    'P8Ysint2W0p9OKiDumrydUPWNhmHa23zDy7V7cyG1f3+BblYRCxzNyYFKpXzGJiZ+NEzerJ65Dp6u80edWBtdZfWx541drdjukYb'
    'VfFEgZ3nDm3NUeplYZDZeCafkQf5Vv5pP7MH4rSyknr2iuqenoyFsjy2laWovGQ2p5mmnbp8VaCWZYFqF/gV7x1nwrS6bznTx7Ez'
    'svI2ZYnl5YMBvR6bzNP22NxKY8WjFGnYy+eb63J/7T5TvLQ+tCo7Vp6P5hxdaR4LBdl3vWVknm8obUpRWnW1vt0XpcK+kW/OlEmf'
    'p4fdwW7ZlabSQ3Gn9Fi3kX+mG+5hvmv1jEONmRR3zzNb5TfH7c5xVKqbqQ23me6S8aZcnctvh1Z/D+ZvSTk+K07fY+yhLfSEbjdT'
    't8rtB2+iDmcZ8jilxsZouy7NlYWw3cEkmoJ4JHf6IM+X6xmVPRrejhqqw1K+zO7LwrrAHzmqtrDyD/KOmpOmNt/2QA91MrY2roj8'
    '+plb4Fpte6vMh/t1/+TNxfLWs5wVNZNJY7PdyuWy4BQYTepxhumMypKWb2aG/PpE5Y+O0uGHmYn13KILU101M8953ZkLw8xLflcz'
    '8scXkLsuiMJNgXkpemt4icwfRWWOXpJqVGMDy7ayuafdqfVY9PbAe6T+pGq/UNa8NnzOkLxhS+1qb6fP8mxbQY2QVHUguXNW7Lmd'
    'uptfDC1eB9tccxhSXHfn2swstY4FZdWligd3PB/PLJHvrMeueDi4cwUIIFOr9KX+co9q5aenZo+lN8PJdr63n3e97fBJqptbtV41'
    'ahmSAsYrtXqkXVqrQpFvTtoVg/MqQ1ebKPyBBfNfawgPpw11fFSm+cJT0xPXjdHWnAxtw+uZgkC15Llq9tnSpr6tKc3ts+q+zMfV'
    '1qjcbeyEzto0JnltRI9FftRyV3N6OaK7TWNVX49Je+rtBL3PGquWvZ0+9YXxozusSdTQykw2I9WagVk3rnrkfDms79bTErP1FJkb'
    'njrzQ8ZqSzVhKPMCO9oavGQ3XJttTLtzcrDrUxaZ2SpeV7FEodVlqQm3W013GbO3nJfcyvOp0e6+7OYvjK2cxFavPhlMuxO9034S'
    'd8f+rqc6Q0UWC4ai7gDJrH5lJxbGTJn0dLtyFDSLH1qAw3NVnRasLa2daly9U5iSxpSbS2aLGw6b/ZWt1NXl1JUplXvMD8jxkzIQ'
    'uc3Wo6fjiTWmph2q3KctOiOSZrMubTdjlR0yNbFdJZ9mhjCEP8AdejasDRguO3lrsIWXwClftJuG0W47ee7IDMWG3BEyLOX1qdaQ'
    'tlYvxxo7HNd3C+PUVopgBRWm1SfOXk9Pu3Vj2t+7li1kxP1UP3KzscyNh6PdamAb+5L1VCiUFx+KWh3t6tPEXYHS7JEWO20bXH1C'
    'rbaNdb193PF1IVPXden0aBRL2rPSeuE37vY4FkfbjVw3JODX+ZY4VacSm1mN93Z3IOVns0FpIz8V+drUGwl6mwIj0e086uOOI/Km'
    'bbvUdDCkBjZr2o/KSjwdW4Z3lLekWActfuzWJ2aRZtuTg2dtyW752JQ3tkBV+irXn7BMe6aoQsWz5fHee2J2graRJ4vHU1GEnjyu'
    '705ty+4frOH++eHkFB5/b1zvgXeZuqCMYAzb5fxRHxXFxaKap59/+80PiBJ3exQF58ngbolioyzKtvHjtzhE2vODune9uxv7FvzM'
    '5jAXMNqEGKYyBTHe88S5e/SRWXRqBcq4+pJK3BtGdb/ibQlQEZ1qYeFdIldPh8uhgyrWBP7YEkoQDL6JlPqoqd/ttZQ76izriTpL'
    'e/LPAlj6H5xU8ef6CMf15vNk2JphhRwnUIxIcbQkcUwy+0ESuBzKdZdYkiEZqPBW1PoDee1L2v+uerDVL0w7m8noRM5lnFOc2Ejq'
    'jwft+JziswzwgBJnGQTfMQ7XZBo3gvLa/EvtRyr3V4seeD+i43nCBLMfiZQ854eTPHUnqOL8eH3naXQ4jhMl6CcrQKGhOmgzCwY8'
    '3suXynK7XZbcRZg66Ma5knFXwQl8quXc3mH3nr0GmGqubzeomvvfudkAH7NyJT82PH4F50Mmz1h5X/ptmpSTDYefQQtpO3Uczfsa'
    'R+dXXGkZf/MrSGyE9vxDfz6T0AusjHDs2W//5X/nePzvHI//nePxb5HjUS4X1MJFjkcV0xR0tz/P8Zg9FZ9fcA5FaZ4vF8okmuUH'
    'uIfxO83S83Ox6NNBmGdRLXefls3nRf95WB5UDgttuME5FwOzr5SGlSG15kcHR6r2yMNg1dRr/ZeN3GNPraO57a2emXbJ7TygfJIp'
    'puVF06f5xJ9iYVAs7F9KxTzA82B2AW64Lz+UAFZcvxDDU34e9J4n5UeY+2VzWDmQ3WH/BWbfmZVHT6un07PeWIoP48PMrGvP+TzQ'
    '1R7mv1AqPze7hQex4D0WHvbqovDv92f+MJ/uptPqtDbVle2xvrae1gLf5TOHcl/dSr3admswlb4jiOPTi3VYdR4q9S19ZHZKsefw'
    'lWHrZGSGR4svP6/Gw/223BSOAlntgp4zmzFGeUi5+a5KrfXxSi+M1NJkNNruKV0+VEia4zb7Jy+vaU8rnRQ9Y92cM8956WneG2ee'
    'FotKW8h4Un7flerLY5fc1Pe8Os+QO5Ps7+J6CtnJ96okWKlPT8WVRc0lZg/QH9W1auWlnnhUMnw1X6g/Z9ZgT5XbcGM98L38ARBV'
    'adt5L1Oq0n1yRXXy2/EGt7x/8BtsLuX2oDjh+KXdsF5kT9PGq9pDc02fuAE59UTDrItgjWQ8F4DkDARjb79VOwDjlh4vnBbr6pK7'
    'Vo5uZVIdkuvNtrWe2Ie+ppmeVBF7aF7FlTgePj7OJgOqU2sK0iNT6jqVftVmtnWPs/PlbX2rTgfuYlyxZ/XdQ1vMyLxkkm7dU6en'
    'TYMn82ZeXgCPG/wcLKo3x4+P8sar9PtUe9c59LxJzT7Q6+FgTOvc0cvXC0fervf44WOj0Sk4VGXQcKn1YKpmlnNyR/aZrTgcm+Px'
    'WBvSJmn1F1ZjptjHOlXSp+MmD3YxLb6IQ2MrZXpg7gwm0iDqvKMy3X6fKW0WFjmcWLWRs+qWKTAst0+G2zjpSqYv6cxo2GIscchs'
    '9PlDd3C0at3usUWO1D5jSxVGaKj1BmlbltftHYqgN/X00sNa4kSbk/llz5tuKo8bUXic7ehddSg4hUJFmw1+DjFtn7Z1zdpqIrTX'
    '6u8eR5mi4DYdaro8rkfdITUk695yeOR53j7J1nZepM2mtysy+ULD7WaajPNokfU+z1RmpfnDcMqX6BfKqs3FQi0zMQ15ceTF6jwj'
    'DOarJ/Ek7avLfinzsO2xozqlaMOmvp+UuPykbEujRvVpa5nS0TrIhlnLPG24AePNB1UwniW92RW2q/6qu6agI5asDgTa3rYeyzy5'
    '2WQOx+n41JKPJdR85fFh67FjmlJ0qqns5yUKNd96rFUftzXzcKwdZjur9iAMHsfjhZBn5JU4Wai9k2BQc3F7nE+e145GmSQ3eHEP'
    '44IsbRWhRz26pYrc681frFaD22jK9qFh75X8voRG1lxORK/5QG8UR6osj6tedyc0LHc77apuyx2S48OGWqzry/54ZNqLASkNd5Y9'
    '0UdrKn+cb4Cv90o/l0OWat6wBQMqittDftIvO+v+bDtlOtsHbrjKHDdPFJPpP3lqH/jLmu9o7fTwobZuQO08N1xnjsvapGJl+uWZ'
    'uRONEUhGINz9h8DpPHpbfrSwanXP3b7IsrHqy/NGXXp0ZWO03SrbrfqoW5a8Mde99mNNO/Y64wW1BT6eWWwrG321YVly5zgOgKY4'
    'S3U7UBq2SdlqqT1s60dEvBTJVpZWxjjuam6N7Qmj/vTxqCs9+bRsuJOXR++0OuatybhbU6unLaVURo+b9cywSHJ8qp4k71To7Hlb'
    'GqjDUZGskyVaYA7j9VgjR4wAuF5lKluVmSyqrDLMbDvVqbN/ENvb/LCqDxcTqTDaqZkOaKtSic6jq1dqd54rNrNb5WFant0duirK'
    'hku/FDPV4Xy7Or00W5MF2zlU2rThKqLFUA/S6WUyGNUEnV93+dp2t6bq02JlWOkOxt0BW1droiEotuBsNuqEr3XlDE9vxofiQ75Q'
    'UhyVUvKWJbaZjal0xoP1vL3vH9vUvFG1zW17bA23W+Zo7rTaoj32bFlxh0p7Lq8MW1vWl4NZbQqa3rN8rth3W0drN8uYHX3UEeov'
    '+lqb6n2Vk57ndWdODw6PHihXm+5MNOai0RVBhZ/PMnZeH/WFehnVXjsZThrn645BD2qNJ7dzfFnplfyaZ0A/7vU25zhUNFWZrtfs'
    'ceFI0vzwhd8qHtV4otTMarLvlnl9PN/xZdEqUo95a1TZ1XdDoSKOmfLm5NYRA65X5dOLfdB2D9J2Myo53qA/2Ygv9JPNPO0G3lHj'
    'G1z/UXHGD9X9Zs4tDyUZhf08GFJb3jW0jF7zjFJ9vJsfjru1ove5Br1dSXx/Kh0zy5YxrewPYs3IvMzadGO5YvuAD832U79oZ2ja'
    'lEj1QTwx0mba2emAWf0JfZg156VJflN9cDX2JVM+5VH1QlT7cLVy1eqz+b3beloBGnVB4FbWS1VTjf7sWX2oc1N+YVCH1X6+eZnX'
    'tNOBPrL2sVEnSbHSL9GysVkB88ocpdV6WBH5qvncWOzK7nDJs65KCQY508y12KlU+nZ/OyypT5PHfrepa7MVy7jd07i2H1bYukKZ'
    'I28gjax2b3Sqd+Tddvcyc7cb/eTUtb76snMmdKGo6qNo9WTLKGSUzaj9VB1kKNfuel3FkCilrOQPw55RUzWeHFSOrg4SxPKo4mC/'
    'W677tsxVunO7/sJSe2bWrLPLbaM7e2Ke+JYCjLhV1lfjBQfzLHnjYXvBr9bSaOWcLCFD8tVu3VE2w86c3lQKRdKaR7rGozQp9frN'
    '04uzfRbHbV3m2u6u1aEaU70pVJenR7FVK2qPx5EnNsEyHNW31mOnSxvFYXckSJ2XyVY/dU5PznrXGrbI7XDYyRfKPA8mdV5c0zt5'
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
    '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'
    'UDqZSgm6p2wkzfMxKNCm3QPlpiiYPBLG0x+Y3eTL9/oP/6tJnvjzDf/7+nv+86O+dWXe/O41f371+jt99KN9/qPWiUxD/IEcQfzx'
    'w3v+K61++3STmHSy/5/x1bef6T+f4/lneP4b/+sL9+tHbeid/vOddq4E4eWfL7Xf32v/v31vDRJKlY8I2K+/kKpMfyFdmf56b4X0'
    'Hy341ZvfSxdA93d/ePmWIKFfv3u7hx8Pbt1SffX+3Q9uqdZ/buqRuaHN4WZwjGTdN/rfnK4SN9zSNzO56YbpLLsZ5+6Li5MbOT6n'
    'N6CcN7RN3CBm7wY2/BugstyA/bghRb1Rqnuj1PYGrIUcl/TmQk54fpOe9wf5jeaFbD1eH4QWhvnEcKGdgZkz784yh5ADYgyigm2X'
    'dA5/qOr0rlxzpsIj4vgiw3V/cBEGOl2mwzMcHNALSAsB3nuYwBTevsIBo1QtdLhmFyUW7LJUcdJAR+4DuSZUX1XpJNzN8E1ZVTWB'
    '3PmzjY0eLb8NXEU1+UXne7IQxdxvMQUyHwfJKBZmRgW5eJGERTuz/EcZkqUOayfTc9p+PanZl3LdKBUpSmAyMPeGtS8THw1GadP5'
    '+GyMdESyEEp5JrjC0hMjQC7/dVA3u+fyd81l32B+X5ueuqxdLseyWtRjrPSHcggRcFrsbMp5Ggxn+WZrfaAzR3iFO0ZUgfOMOou0'
    'XjR6x7legUF6gxj+m5PB8c1l1pu0tnBgv/i8vZ+u/Wlj7W9W118cFN3Vx64jNSNj4i8b2KJF5UW24MDgPMJhkKuKzhY8reCg+GwT'
    'CxKnj4tgauMVQZaqYn7m1aO1dk0cJv7W/KfTjILxOIe2QK7QcU4n6yls8luLZ7o1XxMmqbYPcdq0qKo9TdNS/v1t7BGVqsjssiQh'
    'A1B+yZ/d+a0JNw/SwzfjulVE2tqnG5UdecGcJvTLeC5vN+bHlbaTizkg2QoJMtdj/F+we/3TW+c+wZdMrCv0NfRWlj9DR3pnSBF5'
    'S5lQcyt+6NI90wi8/hwJ128IQX5zOm0d9PwWdkmhZW7td0n/nu//vN19sn3z1+NeMdkyOugSn9MxD7S9vJZKNRITa9M8IPI9XHmi'
    'IIulZpo5bip0nlFDzIBCK51OjMVjbu7IM80CRNm2TIGxip1BYZZkNIjpcJvDFXCOR2G60/njSs6Qaj5zTgLFt5qLptXF185WHfif'
    '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'
    'PF8vjqaDyWxbfiEfL/4F1uv2g/8f4vyhdw=='
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
VERSION = '2026.10.21.1529'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
