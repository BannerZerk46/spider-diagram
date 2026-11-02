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
    'eNrsvdly60iWIPieX4FSWlbcmxRJbMRyI+J2cxXFTRQ3UcyuB5AASZAgAALgml1m9VTWjz01YzZ/0L8w7zN/kl8yx92xcpEo3Yis'
    'arO6iwQ4HO7H3c/uxw9++QfVmngHW6Pm3sr4/odf0C/KUMzZr3eaeYcKNEWFXyvNU6jJXHFczfv1buNN09JdUGwqK+3Xu62u7WzL'
    '8e6oiWV6mgnVdrrqzX9Vta0+0dL45p7STd3TFSPtThRD+5VBjXi6Z2jfu7auag5V0pWZo6x+yZLSP/zyD+k01VPGlA7NfsM/M+52'
    'dk95c41yoWdKcbyd5SwpxcVlim2TWlQ6Da8burmkHM349Q4V3lFosHC9UmZaFtpJ7VfGHTV3tOmvd6riKd8ST+7/xBXhkoJL0/31'
    'Tyw79zz7Wza72+0yOy5jObMsS9M0qg4PKTQFBWuPKtIUTQk8/IPrP3FlaEfVpi65ApA0xXlwFFWHaaJ0Fb3g6YaG2tgz+HV0eYgu'
    '92xUii+ZsF3Xs2zKmk7RwgR1UFl6YhmWg4r+xHL8RFKnU7jOXnyJufgSmxM4bRy9lE0C7hdG43K0iUfh0bMY0PCK4AFcCRi6uabP'
    '5l507+B3GDRV1FQ3DHS3cYwvAAKala8RBDPKcxTTnVrOCs8ZujEUT/vCsBTDZnJfKYxWX5iMIAji13iDpmVqZJSOtdT8EU7xnPhl'
    '6RBMNsPEitGoJ4qNHjjWxlRPHi0s3Yw/I5BOdGdiaNSEDA3PwuQQXeMp5qKBXa3OZXJhfRjVlTfIqpM35BvqMyJp1gdJvqkT4RPv'
    '8O/CZSvenMIU0IRFlAe5DNNk+IxEMXRGNriMmGYyXJPhUAmf4Q0WLuCmCY9ZUpIOimRUAm9RuUyOkuOdZGf+b0SoXPmOsBUXc5z0'
    '3HI9zCrciaPb3vc/UFQ2S+Vt2zhghgL/gcuMNcA6DdDJcT3KVnTT+wZsZaWtxpqjqcAaLWBy95RmuBphTQfX01YUEJinm7MMNOo5'
    'B+qvFPDbzQqoJxNclA2N3AP3gdoZ0t2vlGEBKnc9ywF+lJlp3iM09+UnH2aVcMlvuPJPX6F1ivrv/536slK8ybypweMvP32xgatp'
    'jktoGhguqvuNUhVn+fWnrxlcVXOp/0L9hIp+or5RPxmIMH/6+jP1z9DiBFX4CMT+6+jtX7LBZP7iegfExynqm2NZHvVXDGs6PZ59'
    'o/445aecNv0Zbm3F1AxUgv+gEuDbcM9MgQ9J6H618TQVSoSxyEr0z34ziAKhUOM0RlVQNWUy0dDa/JFwL1Q0t7aag9pmprQ2QSWO'
    'tWNRwXiqTKWgKdeDmQ5KRVRNtVBDqqwKE/yaZRKwNUnzgYQSH4KxPJmQt6DMh13lNTVsHhYFFjMxRFJ0NlLPUlzvvMSv57/utzon'
    'iDgbK1/YXO4++J+Rv+I508xN2p0rqrX7BgKJoe09xaEf+AX6Hv3NMLmvpLUknuDFRA/+OVi7v6AFT+PVRsLSWd79U3I5GYYBNh5f'
    'TkZhJiwdLafGazlNji+nzMqSwp0sJ6txDCcllpNIsPhysjlWYrXYcjICIzHj0+VkeCbHSNFysmNoPRdfTkZlFZ5PLifH52hxmlhO'
    'WGA6mvhwOWGNBHZytpzRSIPlPCkJlp3M2YXlFO5Z6Z5jYS3Z2xczd3kx0WoFa/lnoOmxtU+7+hE40ze4dhBLgSJC93+Z66qqmf+E'
    'SF93bUM5fKOQ9KT+QV8hBU8xPVIxo0+gDpaa3yhGsOF9ItqDu6mh7cm7P2M5HFwT6fmNmmwcB1a3iED9OSGFv1HszyfyF6YFSdif'
    'T2VvWA5Y4enAM9MKoC4UpznbH9F443mWGR+PbqLX0wjAnylcP60Df3UBJgBIA2gWG9fTp4e0r8xGD2YIlNxJ0zAVGZjqbWw++MR8'
    '4LuV4swQwDSGDf1ig3aQ3n0PS6EiGRHWizVA03/ye8R18BqPlclyhkf/jdoqzhdEhoAqeOmDEsAyKEIkMzUQ4pDFJTgytUwftiyT'
    '4ak0qM6GliaS654qINW5qUy6+L4Cde+pu642szSq/3h3T3WsseVZUFbVjK2Gpp5qaRsNnuQd0PDvQTs33bSrObpPNOHsk2lHP0GQ'
    'Ia1RR6o9gL1ZmQGWIrsDzIG/XhgkZi4wqBBxYQlWMA6YUtcydNWvhlbYF2UZ4BDx5Y8BsHPQeqKfVxABrzdMEYWX0FZUFVMNYAAm'
    'wVgHqaAfHzDQp69CdT4qxMR8cP2xzxloC60RIlUgFyaXRCIJ4xBGIVxr5+OKSAPi7OYwDlBxlImGyI4MEDX+RxDjyGK7Sg4r3QyI'
    'kD5BJsy0v/6cAIpNAsVjoARSuA+pmcZTdREo4AIu6sLT9l64qMjG2Lg+oYWTzgbLEB/INX51MtyMuYIaZ4SAu01HxZph6Laru6fz'
    'kGxLRZpMgr/5MKYNbep984EEnM/+GWuDG9NVtpqaBgvanIHShd4HAXVwwWZ09THoy3NrpwEQoPaZM/wK7ujP2Vi337Dkg34vEPg5'
    'PuHKPkLppr3xMsBryboTutfNOdCmd2E1k4t2cW0TS4JLyMKdIzyR4F8vr+x14r7ExDYekc7R6mbQy/bJUpyQ+XWq5mIjSTuEeIRo'
    'yEEREw0vVnSV12CQvhlIxE/muqFGDMF/2cemDKYDJwSe8YtBbzld46t0l6B7AdE9RufQSv5GbWxbcyagp/9MGWCLABSoW7x0GZrX'
    'VqeDZZOSDbi4ZiC7/q8xiRFizk2ImGTX1+aOCLQkiogJTEPYJ6OSgGHYIP3xYl5kK/G5QgvtyxUyLEJK30zL+/IN0EUBClS/XhQ2'
    'cTLy3w1eCOYmLED8BU2uB7iX4SNAVW2qbAwv3kgG6yPn3WGdNCKWxAT72ukpcRAFNQFixnZ0WNbDxS5CgvRb+SO2Ri51GNY8R7Pz'
    'vkLuFO8xsIHi9ZEfDik5EXvl6LOFFkPJitTeDOKq8I6Po8rGsxA6T2PEhKuZikMkcMDBhFBC/xGPrAm1oseknVgvuuvFXj4BC3MG'
    'zDfYE+DQa98jLfNMdcSKBrB7x4uogE6SSkKIYMz3tYsEGmdyMfYcqYQXwLi4GucYHXszsxyHqqcvxcj83MaJzuCYOyHjI6N9XykK'
    'JA1CgLDRPyKzKrluYP/HFa+MZ1mGS3rH+hzUtC1XJ2qloxmKp2+1OBqULO9ty+VUVqGZDsbCngAf8bd9zDxDf9Ew39H6gvnEsLk7'
    '3ycT02Rmjg62DfqZBglmI29nmmjKLhqbrSneF+EeMN3ef/XRU0IjOENCH//igjuBjUQk7XynTzDTbHxuyF3YAv27zVMMFp9Rnr3D'
    'hu9EzC94ZaXo6CU8aWSuYPjQPTIqE6R/Aj6DJX2CLcbxnCHkd5kZGspYM5ANOFmeWxrXVZDcGY3fLuGibt2VYhg3Kw0E15B7xJfq'
    'l4gl1EmSavC5/hzAOnMU3/cSYXlSnOAuv57VwTsu0DUsAhjvM3934Qt5BxTlrwg/7onn31aQwwAVnLdDhohwlCCqL/DJSDOw/CZg'
    'LZqkGMBjKIpPSEZ1LNsm9UJ1E9nqquLOtTOV1q+SJjsp36i0EIkbxdwqbozLYG6dNOdDLBkb1mQJupu1mcyhdbIWRCRsXKSyET0j'
    'btb47WdMS9VigwoxJmSdlnO2ysoY6BKw42dYbzJrpOErxpHvT/HxNqaondP4NWWfyLKkAn/FhUFgPlVyIt/aGQcR0ILz15yaGPun'
    'yko3DjHFNUFPtqOlCUUFE+B7BRTzsIMXYGaO0LOKCIIN0Qq56tw3ppaIUMZns76LAt8FNgThpmTB0mD8QXvxqXnPW4H5hxDjWG+T'
    'fQLuDLxiKLYLKI0Z42XTmQwx1GtOQSU8NBQHiEykU3bGXoXvgmKiY9SJde3DdrXq2ybFKRImDVcurmUux2poFwNLx5KA2ujplWVa'
    'GEvuqfDyotmDgcZ+XWgHm/1TfY9NBItaaa6rIKvfBSOfgqlE5v3cWmk2YsGgvBAzP45G+GXEENASY2cCQScsYGPWXbQDmoZH91Ra'
    'wmpAaIXQMdTN0QmXzEQxJl+AD213VJriWPzeVXI/WwA81FMiDf3aX09VWf6CUiVdEn24Ozwqfyb8oVAZ1r2PRo5ur9MOWYyNd0ad'
    '/rQGpi4dp01yF84WT4e6Ai/QgTsr4N/h5M2jyYu4JyaMD7g8CSkzSXODwXwN+fcZKZiYD7lLPkYcAaOKOKtPrtGuwwlTyRF1CAvA'
    'UK5lcsEC/NcV2oZEW5IhygnIoYTMbLI4AYuk40wxsSbkLqGyxVeBF7bz+IyxIarF4fR9cajPHoopOXGqSuQxcb1svDRyvt6owb3L'
    'd7nr+mLUV8Rfr6nm54bixZ7DZscKsr2CWbpk0LCXnW+BaXiuCCTa1uPz4+suSc3mDa9DnLjxygIt59yfQ6IN1igwBlnsdKQTE8sy'
    'oZ6F3gCuRdnxfRP4K57V2BiXqiT9tix99pqhR2ZxgJfcWa2Mp9u3KOD82ZuR6ElgTYTV7zlYk/RMQAz97peM2bfXPlxpU9lGuHm2'
    'DZHk70J8WC0Y1hWfWC6yF0wLiRpAMsSRw05Bk068wSV2HS8x/ESFqW54GtHtD34o0NeT+R5nNnowoARVXp+Sj3HS5PTQ5P76dgzA'
    'VULD+IDRGFf6/sgICscr19jM1Y37WL9BS7yiahJ9ggEfBSsYU3kPhH7+drIi7mVmYJddaBxcsSkS63xqeGE8V0wwJQljgXYfULNM'
    'hncpTXE1kIlpeAksgCmKQPQ13P+61A5TRwEFLXzjr0jHisAJLNiY9RlIiz9i27v8nokVMx3e1Nzg59fTrZeES5QIw2sqWkx3RZpt'
    'cnPnzP55w7a6apB9yvCTZfnc8ntPzQhUuCmaubfmljgTb9GPh1/8CQ6XQwgne6WbX3KI89+Het2fQK1DNuXXr+8pXr+HlnVptz42'
    'IY9oN+/Us3DuaX1nXzwSMExCbbqyMZg7M+Te2++5sF3nD6BB/OxxVS5HI1XuRIU+feebtrJBKnxTpp6/D+r7Nn9qWSCqxiBvXArH'
    'tf107lyJxkuH471NgcOcaqp+hBVK5yKSv+jYu6gbQGfv7Q8FMPk70SEqJFzZ9DVXdny3NGwJ74/f7Pa7um1+VdLhTrA/5WZP5cW2'
    'PrKFH9kefLhZgsDwZic6DXNZU09oYeKF6ZTPPMYYZ0G50SfYkX9mfMYYVUihWCDexraQCvURqxJj4kVEDbgfzJFPSNf9A5gXXjG4'
    'yaySEYe8+pKn6FPhN2/HYYWWcbhQEvFC4f8X3Q4+VfwWlnS4IeuLxtttZ38nL24bY9PDZ/TBbCYi7NgEcZO7y9u18Sa+B040n7Lh'
    'b2xXlOyZoT1TFLawO41FIB6tDPZbxbRy5k1Nhg40bn8bJmzxZP0RhwlGQ0d0o7lv7EoExExGH+NR/pZgbEJFwNyfb485e1/G+ybi'
    '1fCFaAAd7FVPEP+pXziNURPrL3TECCKfkxSXFgBlmnjq4+68aJ019yNeiwsCiojEuLF4Q1AdGWvoUglW+TwU7TcRHmSYZKf3r7f5'
    'xpMBe9IHh/hmhF4CnHMHDh+4ws+CHM5eDsJrki+HFtK3b3OYSRyL/QW9lt4ZX0/FZ4Luz15Y6a4L7X69JnTxWqjaxHJ822mD1C00'
    'Cf6m15V2PWV2HZJrW4AJ9YVMA4oydW8LmkyupXQ5RgIVfERA8qe+XY7902VNNAFwxjTSno/77yozl3aOxc9Fa10C5LO+gwvuw3jL'
    'IV7HbIvE5v+ZW/LDG9nOSjGSNi1ij5dGObOuItsVB+vJ62FEzHWEv/QioM1pUHdce75gjt84uxlVu7plH/MenbmzcydsJGrtrfjQ'
    'sxd034h8w+TjbjD5En6Rcz3pwuMr23FhHOl52O053GSk95eeTK3JJsZOEuBf5ezhnvOlENPENBtj4yTaNKFy/Ok2bIRBRwsQCM43'
    'II7EbYGcEAhfOuVTkUjng52j00GdIdPpDk7ujY3wJCR/8bVyNH/I2/vr3VQxXA2dC7pOBdHrgT3vn62LGfSK5zlfsNcSuNpEm1uG'
    'qp3FBITUctUqic3Z6f6AFDorozpzNmkVson4Z7whR8e8nLEXuRNzUky8SOKm+Qsvboz7+K1lXILyZIviUjv6anZhTyaGmsnwk2Ar'
    'jXSEzxFcJs+TbvAiJ4gLBxFgiYqvToITEz3Eo49iTc4TM+CpMXnznhogBGrW6dEfUCISjISnL/Z80cPia3mXZVLsdTzH6w3cx9bM'
    'n8qk3zaudJI15K55T28gGhSu8kaPkVZ0aT2vDvdKQIx/QojDJ4Ry1yMiTkBU3lRR44Tz+SBRQlUJ7jrFB0yT+BGLk38/JOX93klw'
    'irXSLrl2dBNvRsSDLjj6Zm30ymkuPD7Uo7+t+/lDTCc2H+vHF/z82xyxCkE8O7YkJk+RYGMT7+hetPY+ZsKedZ10mVwIX33bZRKY'
    '0t/9hq4TJOq0qykODpe95DZlWfoWn/p1AzXhY3xvn+H2o4AX3PLRWN7Un2KbPKfhuIijkSOnK33/RTcp15mN70928NjcnxJxnAnU'
    'mWIZ78bp900U9RnXbRh6k7/guqv08pZAAuwMufjYIdPIIju1/mM7fh/bYfI33K6T9HXQz/0YdDLy4IOhKMlOTCIpL9vKaD3Giqu7'
    'iWMNIV3fFNofVb9Im8jxeeY2ZE5dob4IuZFlJxY1fsojWlg/cgTLlAsOKTo40XiD7PngQQwylosRHGwmdxYLGTvMiifyiqvtOh6f'
    'xq/RQfwafd4suYbJ8jCzCdln3L0QvRPWu9z4bbt4cXczcyI70EmB260q3C9Rw0+PaeB5ECI+cnL6AvuZ3z7LgTpMo8Py9whi0OC/'
    'sDm8Nc1Mna8BZU0UR71CCTdi7vU4/tBVc6YB/w474fH1fvds4VlsaCSGqAyTS8aHMkFMGZ6s0GGAb7CMSwcnb//67s7Npc2O1y9p'
    'P+zzgssA9ZLxsxt8XJZGx2GS6gle9Yw336zQSS3FtWFR09iJhZCOygJV/Pze4Yvf4uDF+aEL4mzgP7Z/kBgPyrJ1bsC+cXYi1oKf'
    'NeF8N8NHso94g7krLigf1nj8aMKRe6bW/SabHqRXnGTt1i3z37Bf19RtW/Oi8EcSjn56KJLoTR+yNs+gPnFB8bmT8GmY7PFS90iS'
    'kuCGxGcZygqt28/xOmnL0THbDRwDV0NafQxS1Nm1/To8aCkKMZLO3JaXxu+rYW+HGIiXww4vH9CNgetoW00x3oJXiIVUXzn2cCYg'
    '44cGLkbgX2KpATBJ1rrTvTnYABGg8a3jiEOaGtpW/ti2f1yM+1Fy/tTjRFPfwk2rd8nlymG+kwjFENCEYcklsruQu2T+GiYjxDUM'
    '7Ok8PZPIAM9Ox7Ueng4Nng9tLAB9Lk9PXk+nGi0IsThRP5vUpUjwmMLPJHXI93RuV0N8O9pICwrTODgymjCRvvmgUtTw5Y3VaG0M'
    'M7YiyVO8xOvz0ZxDmetZh4IOM6hRJAJw25daS1jW5FQhcvsD/Pcn91dP8U0cywWdQHdiS/HWKb4wiAITfxTEmKLIseDQHcVEEQZc'
    '7jRiIhHxwwjhGcsfOcTCvn905YN6I31DBGUQRoMK304PQ7Dc1Sa3G30nzqewgVSisdu3s/06J4bobaoGl3zJTHqj6Y/bjBcTJb3j'
    'uzjzpiSbCzjBx85EfwbwCzFMv2T9/IO/ZP1MtkhbRGkJQeEkCT/v6LsgJSm6xPV/vQvpLCCzO0pxdCVNsOnXO8/ZaHcoreEv7mE1'
    'tgyUxvVOTxvWzLoLE8He4ZPqPPy7+/5LlBjzjmHvUFZM/Nv59Y67y158zGVy+DnIkpMaLE1qyFeeowSffhfy1UaEG+rwF/rxU3be'
    '/eYJO1HjWTKd5zOLxOiVmY0AylEss01LCvL2YGMqzaSZeZqPF1DMVkoMgwMgFJZiifFF4RHkDDEtxArZjEDRhkgJ+VgZNEVv5ahW'
    'Gq6qufh9mj2+OShgh9Z7g5Jh1iieko1cOpeAG8rmMH05BU0f+k/AQqdXqwzzZr+O9m6/K5hM6Bg6TZ92zNKUXJVPOqb9jrk3O0ZJ'
    '8hyUh/ntvgVKpgT0N/02UtjGxn1v/mAY7JzhEbbmtgz/Znv7dzFMwnAxUhN+GTjt8JsNuhvzw+yAPyUydouT47I0/OYzMkehHwaY'
    'SQyylYD8xIwAMKGfsVIE25xFi4V/CxmO9+ukY6/KGVok7UWlb45oZb27fAhYTkHzRNBC9v8i7GTScloevdkD3oa5hdSrEYXSiPa2'
    'TKwAfsOys/GCNDsQR8nJhWa3/MlLgCowm1xVwr9F9BshvPQm0NiZcgVoPzE28HnqgH/6goeRIsmDrh3E2U8YsBxnwGwc+BXiP7k0'
    'l2HQ//hMAHulGwLwp7d5gKKbY2v33kSzgEeiwqB9u6B9+IEIAYrDNU7DktNoOqEwgoSn6DdBIJsD70IAZfTJOkrx8abZeVrMxBkx'
    'SCo5nZEbIFRA0sj56GUR0Q9X5U8xh0siwegGuNOWrd3AydCkZHKwKnJMdoDog2K6ysYlD5OR4XWQPUgA8ZSQGJCcQ83EAMfiZZCL'
    'CymYCC4+D8gKlUEqZyR0GacFeAAzUWWk+OuI0bw57qV2GFtgEL+D5yzGcz7EczamYTFCDM/DJRYoaZ6hGURo/gUfXEj+hYTYGC5h'
    'wyshuBLBXgFZ+CbwyOh6l6ug43MKCLUQW3I8/DO4dKwUcI0W8Q+0UCKAkxGZU7bCMIkXcnwatZMG3Es0D8wXN4SaSAftvKEu3DCI'
    'FSNlJB5t8rAIZUQWt/sO+E1Q40QUqCpi7BMZKvnSJVBhSdgtB3JGmnN4LWS4Y2S0FNw7K+F6760ERwl4ZblgieEiQARYao7gA/kt'
    'zZn3O0xjg0xTb0ABaB+jIuqAXEjogkcPtnwTES4SqFBc5SdIo2QRD0lzLtI2Eamn315GVd/qN/A9PHTQNIACDD6NdEAimUCAw2Ua'
    '/r6tahma4qTRtoXy7mzzlDjg54wACwhylZ4LoMBDf7DANJK0TM4ATMCqBKAHXL7ZMVy9O8uYcmUFDSrQWqWqGKrpDJpJ4G3hPSqZ'
    'i8n6b8tjDwzMybuLLVP8PC1jPYCu5tBYQauG6/e0dhIw/P4o+a0QU4SQkBwgBIIpZoT3FOXJ8gbJiDRlBijZ19Gv45zlue9rormE'
    'IgqG3BXL9HoF+VKF60adZtgf1o8Jn4/sowwNyqUCnNVHjVxGAtKZIEUBCtF/LDNExD3ehMZzFHd+C2MCogTMEcCaODH+xBPpLCBu'
    'NeBPZDR/KnQxj2G2AhEcW+E9Oaa9T8+MPOGBM+XSIFrTogtUjX5ftu6ZwLzPXXEz5OLPr9s6nqMv37fRgSiq0XJhdZVDnA2JrBOG'
    'IKCBsKek8gv6jIf/aSLNwXAAR6UmhuK6v945oNJ+xy7HeClOyuuXwxPfs4zgHlexY8Gv538kCDnffr3LGwZ1sDYO5X9uw4VxIL9R'
    'WPeiT+iXjav5XxT6o++2wNADzL9kScchHPhsHoLCT/Ecdl30N4+nuoGazKKK/qiyMKwrA6RCn/3loVagNZRKM4BbcW3L3tg+5KRQ'
    '20NXqqYGsdwBRC1td08hjZeCxxRKZ333HbVHJaeEQhb+DfMSOAKuTg0aGwJ6GsLs94Gd4TjJKNqQu/P384L3TkYMUIcj6KIYDEqh'
    '0G6Ov6J331vRzSkIJ009YW3fb+sJTwTK4Yy/WoWApL5YgCmOMqNQWg3L9Cyc6Gunm8gnffcdvfK3f/lfZM39sSzHd9+LnmOknvwl'
    'fgeGLpr2cDxwA13objQaVHS5g+7tHeTdky4sf9IIMuIyxb06lO5cn3pX+4uj7w9gctlPCvsZTC5a9uGeshXX0zAuqxsbVAUF7vwc'
    'AnffUfO/N2Jr4RA+g9hoEAVHMSfzxLjIt4fwmUJN9ceDB4mSyx/QruyMnHeidA/WC964vIjF29CluPFu615HiQQxuPf43tFWFqAR'
    'BmLjXYZheBsMbbSQIRT4jtrNFQ+xbmpi2TpAoriAwqR/yppegvLuO37zMiSDD0BS11X3BBrL9D8lFeSoMDUX9UwWAj3wwQTGcY/I'
    'baYHlI1YSfilO3czdslulOuDG7TkN/wWQd44hlJADJEURNAdrkzb2eKaKMcSDAGtbNjWZbhKvy+LyKvqZzkEvBqu1Rc06qV2AAxy'
    'NGq90SdLtFuJPkmIxl5GG1fA3R9NV3N+d56hBGP6FMtAXyNIjDGkCV9WndHEh9Ud7JAPhkERBnW2+jB3N0ojfQza7uwUZoJ5AaYl'
    'AAd6+WGo/V7PwMZLfRvgTUWPqZGmBTA6FM6HAOqCck+hABlMNtbO9NdAc38Y8GbQwTvQVRwtTt7+fKKnBKIfBgR14Dd7NoslawPF'
    '6QlwhuXvywD8T4l+lgl0yaf7XGpqESa9m1swTaGu5Tf/e5O8Gh9FguwvU3xsloJwhLvo8YUKeLh33xsKyEsvNt9+dbJ977/geyX8'
    'GepoacVx0Bdt8Pz4kOKYaZSIbaIYIPdIsiYki4F53VNI60FHx7Yg6YJTgxRSnIGCkT4WsR5yQJZ8rxX3O7b2d3hK3Dz0cPedQr8A'
    'fPXwSxZDmYDbTgwS7Sndfa9rmu2GnB2dFwUAcQAkQDZBMac7HcDRSYpe7DDEkK/A0MTfgcz8krXfnMzI+ryitZERI0qNtISKZfgK'
    'WsQjKBWxBixIfS7hzwuuHFZzz0n9aqdgzl7qMpDchqZskXqIQu98phroGrh2wKZu6LGMSSreX9+cnvYIDBVXowBNLrV5goqnt5/F'
    '8y6K7/gQmhd8fPGQUjlH1k8wFVglQO5O0NpQ1LyKVQI/IhxWCZ1qnqNpNQ5vI3R5ZcN8UNUgxUY495cw+w1QywoIcwLdTy6OodmA'
    'cQrY6xIrzrWmHrF8DCjYKY7qYgTTTNV9G8IKNAIQol9+uzB6/LGqCC/OQb2BPMhLwRz/4udDwX2+INYeDK1q7dB+UqREzzQv+Cor'
    'CpbEsUcusbuJuYodZd9/sWw0k9RWMTbQDPlEDNj9+PcvWfL0tBbKXbwBHt/Ev6/VQuDcfX+Bn9dqWNMpdGVh2NBnBaJ6WTLQ7xdm'
    'LZyUBgzgZEpwUczkMk14BOwTRy2dDXaycbaaikws9PsakK7nKAjpEG2Qq5vAPKehDzLDTrAB7Y/mgVg9GuFuIY35+9QB1qFPiBPW'
    '/Ak1JdjzDjWVTrLxG/jQFdHS0QKquDAC4AV/+9d/o2z0LfIA+rjAmTrWinxr2LIzVN9ULQoIkTSF2GbQNAqiTIqgBHDv603kk2PI'
    'oXhdrbqsTPVxpNIlLykG9wu26EZfP7EmOAbqqhqUQBjtGgzoiQ8DsXY/BQmOiroMyQ/5qvYob21CgfO/mfUZtZS0hj0a0D6KOkHq'
    'k0J4oC96sGi1fn9zVDsf2Qrf/GZa6SMe4Jd26+Hrp/gN4VpdlI4twUdRbujTKXU0HOkJfO+MkTJ335n/7/++xkDZu9AA/c5er8bd'
    'feeuP+XvvvPxp7cIiKLPF+JDs81ZD2V6PhsDSCAQaPj7TnB5DQyDSIJGUgwk6+AU0t9L8POTguKCBvOW8oGGFB1CAy0kdhcLLL9Z'
    'AUnYpDNS5Fuipy7WpHcT0BDpUWC72iQOhnhQA/K4QPXnFB+0h3hV2femQ7vInR628/tovk+EOVBfgg+5f71NtJWx0o6NEgWlWVJx'
    'xh/Qwwww2ch5UZf627/8X6HSCmrZBKXIQBt0yILOUI/mxNggLTT67kwgHT9jUsXQ3ed4lVU01XhFg3l+AWEbfsLeJRtYIIJR8T31'
    'YFkzMOlL1sTFmntDHzva03SqT7STLqHTExqwJnvQ/VDr2UQ7XzLo0dermqWKiNBZYvPuS2alXq3p7QHV2wbSJDBv/5KBkqu1rbGr'
    'gwEOrOvJv4InGwO9dtTt6LXkRAZU+6Nq3VWCessqtQ8+RiaJzF/RDxJa2NRb9EZ0g4Dq/I7ilPdRrhXs3e7b+qSDh32di/nV7ihc'
    'DKIioAoQ3rY+8TZgyPhO9nBD8ia3Rth6C5MrnkRs42HX1UrxELUGtIjxnJAuomWY5DjygiaBUPqMJq/1ilEMdxuI/DzlZ5OAoeBA'
    '3nu8h2Hj/BLIcPOdn5EJDfCQtGjAXP7yF3z5T/+EsvIB3oJxSkxqRLZoZvzGgSYCNL8PtyBgyuw5jj7AX1pyE3v3wIM83AzRoilQ'
    '23Aqas+yfIiSdANYcfqpph/SvN8KQMBBMJfU2t4GbDtdMdABfMUx0UeiEVkgZa1LNp59J+Q9GICaTY0P+PdnwhQQDDcp4US5uAhu'
    'F+YR+R80b6fBehFPBt5hRecTV5b6Gd88jjd/RymPLpKBIBTONvGxcJCerkZcA91QBvaMfqMCX+eJp+4nN0JmU1M840BQ0kZoFhqD'
    '2FkH8Mw0tBdw972H3ZZvzHNFj7ZW4Tr0rsL6uxMHzS+xd+ivKA7Du91cuTzsFgm6D4I9LJ97kF1IQrnf8MfJ0Y4liKP7gGehtAso'
    'LRz8DqkXj/+PngLshgAZ7JJ9ePXJWYDQXMdw/eBQpwUcn3gJgdETH+LCZ6DFkY+3UNH00Q9PvAQFeebD8fgZOPzgx5sg6aJvh6Jg'
    '1IsUTR76CggGKA0A5f/2P/7tzUYL+mx2rU3yLN7kr6jJ1EUrMy52Ehb26U4h8n99eqdnrthkJxsf7r0WIID7+J1M6phR7UZDOd3u'
    'oXzv5Zl9fYNVcNUYSqg1RHkjExJXs6e46MQlDmIWFZ6qorCYwQ7QNW3VhnkG5VZHnv/LNZDa9L1g7a89J2kskHVCLq5q0RpSo/GX'
    'n1AYxnWD9Uzf+8iEVRDeJOYLlZxO1xSP+uOzhc8Ow6qgX1fHqZvvme043wfYLOjXbzEPN1nR047marEgIaTIxIXKT6GSivaevpDN'
    'FHTE955g1z2eta/IwQrtxOpes5bf3jhK3nyEwxSD78d/LuQM78SccRY/IsnBGnAwpai74DPl4Zz+/nxnEg3wo3wHsy3/4+W3jfnu'
    '+++zSmBgfTroJ7TC/P3fH4+GIYcCQ+3ld19COxj930VwxOZdz6vqZf8LCtkB/HY0nMj5hPKDCf+CQ/UA9WFBLD8yEwfTWjayHr/+'
    '+NS3SU9veNk+KCFPPco6Koni/vyBIUZ2xvG78PpKuS76mu/tOzZQtIYzuyrzhlBhmD6p8qY/OUlFegdHZ8Z2V3Cwpr9aiBWj+x9m'
    'wD+yp9LA5+B8+NDNxeBEtBVsHigSfuWXhVHa6AXEdqk5sIMo/mliOebnbBXMw0OMQ0C9aeChrdxPa6xIR7ynMFETFwoQ1mRpaq57'
    'xnD9bfBPjEZLjOZ3j/Q3wgn5XfaSwj56iDCwsmRqN3k7YS5ndxRJRw8syVfRTzSgMOlRGGJy3QGKm9oGil24qETNi8+ycXq+mEMH'
    '5y5PevyEUpXj3pAXl0AhabNCWErk9jcDJkirhLpBfpTDr3cCxX8URgu5MiMYye3vCSOdoRmKD849xQH9HOL4wSfXECeP6fkWzEEZ'
    'jGLeGp8T/Hshj2bG4ooRJGRXCGn0yk45RPENKM8PkvdTvGWNGOa3MA7JDzmzzIB9f/2NhsNG6V78prAhRp7zlGCkxTS/lY4fHDRO'
    '6Xpt2MjH/BuAL4WrcRl8FqD/FPBjkIlJ2EGMeOhDZPMgGOy3gP0jU//xEX6OBnFSgus02AsE6S1kiA7URM5idPNbciOciCqRoo75'
    '4DKTLyzFGAW+/XfiElhFic/Wb0Iib03X5zn3G3FrSIU4OXmFI9fItgDeusQGpO6GpyuCAzyGZcGQ87aNzgNZfkA5qfR+VC1qOelM'
    'KeAdBnICgqw07oH6QlgrsaZmluZvefnBxBjPw+jQwLNyW/8NTCPh3rqj45Btd47CZ4iVZPlDRwDcU1pmlqH+EX0l5eed5SxBGwXO'
    'T+6JIh47DBAq5F+ReQNtXdmYPYeqhGPHI72AhJKHYFBfSMlndHpyJDxUg/2mjQu6/c2hgiHYZLv2d9pUDObkkgc+nKD3jnPh3Vvn'
    'zJz4DWf0TQspCFxPRq3HKQtvYKP95WBvGaDdkFBzPdhdyH5Fe+KkpXf3D+Pb9/i4a3gGGYY2mWi29+udf+j3PrNwLfNesckhNzCy'
    's6ggbrBcaQ5vMJd0544iKYtJkkkLbSrCA92GdQjauN6IvpolwcIej+yfo/5JykN0Qv6Xf0in0d4Z/iYxDmPHn3TF3/TaBqczHJi+'
    'YKsbJhaHJqjf/FhqqOXCCO99WxNFKkzRJo6FPnrjKYaRodJp6Ciw5fCHY0MnX1jsfxf5LtyrRYUbGySEVlCi/SJSLRxJ5BYlVXvY'
    'p3/B2UweP1hnUSDf+/gJynJ9MYiEvNiA/w5iPvic16m4COFFk/RIRn0NYoJeHza5UfLIgDL+kEwQEOs0Mfw/nFJNrGLBM89nwn92'
    'QgmXG/AnBDAnMXNvvdK6EqFbssyfUNQqSKWZon/miNn+ItMIMOwE0Ui2yBglxrhm8J2QIC5gznz/saU6CcYAzRGaJG0T2g0gIt8k'
    'ufNp2fXvYp+4Q6fO8GdL8KwB9w0OOyCyw3vhKC6For5QWerrHT5pNbFWNuLF5LAB5dqaYeAIo8BndC423vatIUBRroLP+qb81Ahq'
    'EJmCTD3zJLqGZEP4PR1Kpwdk3z4bG4z5zfwO2IoNPoX4CQSOZ40LUQd3hJr/wdQQaAQDPLVR8JBjns98FEGFz8kEUSVfAnc7jBnF'
    'XVlTLFbRSL9+eqixUZ7GVt145PNkgDibx5UAv4vZPX7wHOvV5CAfo6am5ZxqYh8nqyAWDJTqvYJI/p4Kvq2EmAORYJ85Q4wzQ/3G'
    'tNQDyyK2sYaC0tLjQxoHqXn+QIgi4mkKjpxCKkgsRwVSMUCzwptCqvWjAW1UMHnv01CZTO4JIzCDSY/CsAItCjncpwG8aDdbU3BY'
    '1N2PCpVyssf3Qa8QdIg2YOeW5aJjyzoIlBBX0K4UljHEGPuR3EanVI7Cp4Ekg74u2m9nlIO+UhXf+fY1zcA4uhCWj4Qb0edCRMRl'
    'eDg+HVy29m/jMv+RIhxPQCsalnsFtMAZEA96pb6U3cnX31rXOlGFfbRro3T+dwkdaxogZKDHXwrTjL4KBkDE2+3ir34lWyRfAgvs'
    'ivj+K37Dijlk0U14TjC5PwrWFj5H0sG/jQMoHiiw82psDc7M9b0FPy9tp16akwdHV5OQow9/RPbQiba6whrxH2IhYGjzmmRYg5XD'
    '0Rn4SxHQArndWY6B25sFJehrLIZy8MsCE+IXFP8ENK+EKYcsJ1iPC7piUhftHXBYHI5dBWJGTQfNxaxb7M5A/pryu62vlL2hmTOc'
    '+xjllkv0hn0+kdcGd5iYV3TOJJzU8CDJ3QVKgZo9azYz4iF+YO8Ce5ijE8RBGlviuJpsvM8wvzAXbmQFBK2d0DBhYcuxShKfoAuU'
    'CyF0/MXsuKiqn2wkrOz6SUnOauNFOnOlWTjRAvX//j8Uac2d+G0BHk00ww2f+EciYr0FR6evAFbSDL8iSdlwpRpxvQSdBokeshRR'
    'b94eexQyHIBEwn4vVv7bv/7Pv/3r//G3f/0///av/+ZXx9EKhD6BVt/qpOi/kaWiskEItH2Iss2c5jkiQSowxSSJk+LneAmmNZl4'
    'CbdnX0jYlKxfCiY2zJt0Bno7ERsTnQAl2ryfcuXsrRKOd7DIxHyJ1p309w2Qy0RHQBCdf0Ug+YE3OHyCjAuf/oJ7R0srnqdcWrrS'
    'laAK5czJiIwNDETe8EFIoYiMr1SswyiCw/CjO1YXuozjvO/0Ro0HcoHIZmRt47aJhxrFyl/EiABbp7oZSzP0ZXygkAC4J1iI5h5F'
    'tn89b+TRJFW+UX/5CxIW//RP/sGW2Nrc45cpHBqPEqHgQHn0GSj0+b4M/PjHmfcz+VpkeGTnHivdRM3HHxx335kJ8rEpfNYb953I'
    '9IRPvXxBs4z07GBpkJ9vGmXtwVjgThygW9TC0QLLF+OFMosduESPoPMImnNhiOZSc078YpHcII8f0f2JNKjEF+EbXkNk3OGFAOGn'
    'usQcRyQZHDMiC/Nxr0gESEOPOS3PfEuKi4SH78bUQrWGiAqMW/7BiaTcwpU7mhuPDwsI0tH8CLFLmlH0Oeq7TzoUk6cnIh0bl/fI'
    'qdBrfkRc5w19Ez/yaeIHD3ncom0m5iRxrCemBJoFlFIhln3PUcihMD9g5w8Xj3LayMOJds+u6X9z9u57lRDj1Src3ffuZjw/qXW5'
    'Q/x1S0zJd9+f0a+rYfIOPs8Xyy/yh/Njm4lt1skKmUhWLM/b73im5bznIOv23+cky3n/sczcUXYKUuJD0f9kigq/2VsBIbmQe3Pg'
    'k7N5zEeFSj2/9ONw+BmWb14NnJOwb/qZ7zF3i44k4NPbOHfgF5TMMEsRdQVd420ddMz7c2GQ0M3HQHy6AGBrsxqjQuJx+hwYYc7/'
    '961rMxFR6kctE7sw1CwwAtV/ODT0fSQ24rD40bfBCYEPo+4NfeMJeCRfsAlIl+SzDA754fP9b0RpI/2M+tS2zuVA7VMTKsbje+i0'
    'YeQWVUjG3sucFueaJL71KyyWIGCYvxMfZXyHfePwEIQhKLoIpP71NFJg95Ca5NuB5EON77QOVhXuwN+kfyNJFdTEHfg1SR9vVMZj'
    'C6tfGOl7coXMVdVy9CMYB4rR2cQWokQ+avHZcOPgmxi3EglJIFzxv26ROF0UnRH6BByJr2bc5gTDOknBQseG/c/VItsbTW/g2I+r'
    'n6SExKPFFd4rR253JMbGpVYblLiFOMoNkAKZS1ZGwniK2xpBMmFicYQJKFBQDqhvfwxsjXswRBDjvKf+/Gck+P/856+Zu+9Xhow4'
    'pnuX1MwwKG/qs8TfewI72BYRrHCDOa1vzOh4SDC6KVgjQHHErVF2J8nQpkTehLfDOTAgj6vZhdiJswCMX7JY7Q+tABJL0YPOZhso'
    'RzbQxqG++NsDbpZsGKZ9SNLoaRAvAnLEd25THN7y+0oS6uO0tVDggCh2NiS/fhgxGyYfIPEVkQ3ibbyLFkiw1eHjuqFv8dcsDXz2'
    '72RFoA3fvohsAygrgnEXC7BIBEqGCcQuWw3o7es2Q0NT/BRv4SZQePQHhAy2emF5w8H/F/8TwL+RUXERK9Ec4GCAX/RgBAV8m9Vj'
    'L8y54GFoNs25BEmgR35gxim1wKMSjtcO41k+ypRwspHYOTKyH+z/ujIoU9kmD2nhkaGYS/QzmpQ3ljeBFeW95ygXt2TgYQsPHf08'
    'ne2IgNyJo9sBNZ6HTZGwoY1TAtZ49/2vf6DufC78jbpLUtXdPTz0SQmecujW9bP1wj36UPKdtrLn0DG6RzN6j8oMnDwRmvPzIuJC'
    'vHMLZX7KR1yGPAg4DwR5+Q/UP6MuUMLpRxV1yKPb4GMBfoe0f0Hd6agOfY+v8fFjaJ1BPKvru3XAqiNP91HFQ3Tpp7n6Rpmgo5Oi'
    'JajjGEi0UUCK8HFNVPZHdsyqPOsXkx2PsC3iAYBa/21D09xkzn5/QVrDCjuGkmErpEYWqpArG4VCu36QKg6A0FEWfbREKC5FNzyS'
    'NyXYqtU90B6m9xTohrGNXETerobfdaHbqJDs7Gb8Xm2/043hXxh6mBMU96JQpHz8ncSnAVvxXx1/Dw5skqNbJEWr74mLIkvRG9hJ'
    '5OuSUT5+kq3DQWengj4if0bYSQApABZC2MPONLSlGrw4RdIgSvgRve0vvj9jgTAGIEwQY2gxghbYaFjKmHwjAQM4URzngAQFcb0F'
    '1cMkkm8CWt7bmqOv8BdlHE0zDt+SQx1FnaJ0jDjgiCwgURiCyhXdi2oG+Uf8bfDYouMQrzM4srC4d+jT3JjGmCS9MEl6wen1VTX6'
    'bEOMYtJshpdZUWQ5ls/lGFagc1qa4SM6SjO5XIZmGI5jaJGjBfmEruhTCtJojuGYmyjIiiFo0fc7R77q0PF8aRHaCRSDEUZTeeql'
    'BQpF84giC5CXGLA2eC2JlMGLKFYn+vLCRVQ92AG+JVH9vMGpburuPBPWiG0RRfWwsHZjmXbPlzucKuAk/n5U5AZPuuhxzmki/0E8'
    'YLQ73dKCYUUwu5MIEn9HK+IkEY6xSRxjkziW2BXBZ5T9vY0YrnG0mJEEgWFoiZFFluEiLOO4TI6mZU5iRFnmBJp7F8uknExPTrCM'
    'uYhlcTYYDBqBG+MNMazzP6XycyJym/K5vHW6kGqiHfSuG+T8VlCSDO0S+pRIbJjfZ9Ag2iKKgeRbHxFEZLfhUnsviA8GzYR53KO2'
    'gM99CRLsozARUJVj/AUw5fDh/O3Bdgsa/wxzqWA4QTiHt7PIWWHX9/yQ5NjYTHuHm3FJTOOSmIbj1vFJOFXzFN1IMLNcRqZFRuAF'
    'jpdzkiDFUIwR2AzwL5oHPseywOjE93BsSksTmj7BMfYijtnJtO5oon5ysODEZiHmP2ZcggbLlWpF6zRW1BnhK5SLzrSHlf72P/4t'
    'sZpnu4CYwi9I3WxMZr5g3SOWPwtH9uOUbcgEBgUJ+QgpPkLxAGdQuuWTTPkROKgVl7isEMh6kDIcpXcH/D8A5Yxj7CScYz/gIFAK'
    '/aXnk0vPJ5e+Siw0MKh0/DG56HjCb4YE3E1IQIcA55IA585xNbZB7XootQ1J9Pt3hpgJIRaSEAtJiOvn4RxxQCU+AwDlGDnH8WIu'
    'J8T1BHgkySIPmoIA+kROYN+jL0FQJHp6Aih3kb6wB8hnFh6ysoNrJywEufi3f/lfPqbBbViOVYXT8mz4ZjbR3thSD2dtq98TH/jJ'
    'nn83J1TlPDV6KaadwDtJmX9aPYIn3m05Luff6KGGRQ7WSuJy/p6qsIgzdBFX/2DXLV8VQQLgBggu6TW3dURcqG80nahwa6tNaxs/'
    'lKWHFs6lHsh5Y/Rdqg/2grlieEzqjR5OuPGNS4Bo4L1GPzPleBszS5H9wPc6KEBNsuf40V5IbrosEWZ+lrr3evs16C39wd5w5vws'
    '+jyA9V4fo6APP739B3vC+W6z+KudlPLu+nSTnXU/2BkKmX6vi6ePchWSoj1IGJQNUzq/i2vJsZQ/Si26F2XcfK8v+obGs3F2nY3L'
    'CORv0WK6ui/LYrqW73Ej2u3YgrtVGmd38h0fxA4PU45a6Oshuzny3CDFAyl1l4wkMSlcxaRwZZHjqqkssTqPTxfPLEuNCVghw4FQ'
    'RSYSssRlnju1xWlOzMhg+fA5hpFlXpJ+Qy/X7daTn40syFIWzarjf7gjlJUZCn9F52J+15nlu1/QJPsfE0l6SOIK6MnHRaI+8cc9'
    'YvYM3sMIPgxyyVwKWj//QFDYaHBWjMJH34nLCLs5sc/L/7ALFo/kEICPRidwxwxDsLqu+Lwod2NmUdR6gJIuDovX3EsB8e8YTlIS'
    '+6Qk9uGsk3F1TgSFLccJPMeIoHKyIn+KbYzIZfg3sE28zfcTwicn4ZOT8KEMlgllk0VfIxdzDE3nJFriuARospwRWFoSeUEUcjnp'
    '1GEgfcQtRVJvQi2cSjPyqp24oZkTP3TB2sfhFeUMz9ACL/ESkxNFWYzDy4pSJifxnMSwnCgL4qfAZU7ARXk9I2hPnYAnXkA/t2cM'
    'YonN0BLNMjzD0yLNyXICYEnICCKX40ROkEQx9zmI2ROIg0yjEdQnbiXmxK8UJhuNwc2yYkaQeFbkeF7iRIZNIq0sAWZwAisD6IzI'
    'fwpu7gRuDE4E9ImHgjl1UQAaudQ/YoUnBjcj0xlY+hxYUSzNi7wYN58kXs7AeFhBkFmwA1nxXVq76AGLYDwxpZkTW5okyIqA4xk5'
    'w4iMhBABbNFcAhloVgIjVGR5JsdxEs+fUhvD3QSdTz84IQ3aiMIgRBCf2NLMiTGNc63G3YnIacjkJICal+G/lIuBLAK9SSwymOWc'
    'APaz9DmImSTEJOtrBPGJLc0IpwwCJWAlajagw5gkco6JezrD84CoOZZjJQ5ILjYA4CMZID8JbGma5mXukwPwyQkHHka7d1QQXBgv'
    'wtGz8EY0vBNthhFPGTaJZ4ozQSbHZGBAsCoy8G6ezcVpE5YqA5wc+InA5ARGlt/D8bc8cPpqFoAHsDtoLHcoEuQbiT9Y2Nrs57Hi'
    'agJ/n5UXWT6ff+4uR7XOLF/IP+fhDn7nS1l+Vn3t9lulIVPo9uhRrVfuw7MyVKg+5vGf510+X/DGZufQX6rFx8p89KLnq9AevF8m'
    'VfKF+SvX2uVv+QN9y94r/g399xrP+d/gj7EcDVsLdCWhH8XO4aViKAiwCgavYwb3dXKvB/dtcs+p1QKNrvrk/jCo1EroaoTbm5sn'
    '9/rJ/WJSreH3MRClvTeuDhYRfHiemqOX3KCPZ2mGfkzy1Wa+PytU8+Xa68vAmgW1xwJMfWnBoJaWZL6DedZXMF8e30c9KWgMj8Gj'
    'Yhe9357DD8+VE+0l5ntYmE9W5Wgx4M3RCp636yZct16gqCyjYnscwV94ezzFPBlPeZIf7wrb/AP8zhcMVN59LmzyD818YwaDLj3m'
    'm/n8Pl8aZ9ldAeavXyogZNv1y/C7UnjuPxR2u8fCblIt7KRGcbdslp+lbnlebpc75V5lvhuW989KpVPuPBTLrw9zWq3upWl5P9Fr'
    'xUetVthp1b1I2n7uQ3sTaI9/LOZ5rVIo96tzXvux/2IWhtsp5ku7/MuslO/C7M8B9H25kJWe8w87TFvQN5Ql/jTLhefXan5Wze7z'
    '+VQZ0c7uGeo+A3z9x3xAOZ3KPD9rlsuz/sNjr9KZ9CvFmQKI2WnqTbZ2WI7L/Vqp1p3NJi+PdKu83FT3fa69Q30DEiF6rBDajf8p'
    'F6GvSmE2eUT1WnN4PisDjM8wx81y2HcB3p9hOLvQd6H/UtnPRg/zwh76dqodvtsuSIXnlyZd67nbapadwVLuymj8pfJzPpt/spkH'
    'uzPbC/Xj0S7LnXX/tflQ7uHC3Wun3VeMh1Jh/h/7yXP/tdx8tNet7sotvRTnRrcmLPq2k2dmzUfTL87vdM1i6squ9Voq/u//fAaP'
    'S7VOxyo992FGugevzM5ahV5fmc//Q1xllXp9LSxt236xB+KyU+0fUu2dsxlPu4zSVdaGuO4/bXhx4Y4LlsI860xq5fXFwVObXbGH'
    'fau44Cb7LTfK9fe06h7p6UtPUzpWK9sfcVvDWtgp7mXC6FLBHC67681qdTBBcZ4emgfTVl9S3upR34+nvNnNS6vDVmk7hmCzAm8t'
    '1vqqlt0Vj0+MK9YVdTwf9I8D7tgWH3OaTB+XfUt2Hj1mt270pOMgZ1ZzL4/bVHu0tnup0RPTPj5J7QP0tzEUReiv7eG20xePTZpj'
    'V4L96ixSa71htHs7biTVFnOhsmiwnZ1otIXmsdM2q85e7h09WDa1chwWa53eYPmqtl/N8WAs1Z7pJ1tsWJvN68rlpaGkOHN6336q'
    'CfYi1anttKnNZPOblLjtcD26xwUTvuJHM2tFF6y6sug3H+NXeXtdfCj3CZU/A5b8/ekVFnSurAETOszgpVMSX9l2z5s3to92f60a'
    'Xms7Fkp5Ztivq+2duBkMDpY+ElPr9oNWWPJa62kwtdx91qu35P1LtTN/9VpeuadqrDet9Or5tjFsHMTNaOpsOVsd9Dej9qhRWcHi'
    '69x43qkCk9wfBCRFjZTlFprTx648thVOlYvavLculXP6zsguHK/xtK655mrOPO1ZbyAM1sbGzhaGzT7TYXt0qixNpTxNpzZ85Wk8'
    'Z563us3vub18XKh4pNNeqV3rX+ZOhXmlhSv1m86/A3/sqWqDtr3lQDPW/WyfaTwwwmTdNR83dENgGlkjy05sb98bDK2nTqXd6rTn'
    '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'
    '/rA9GbYELzt+roh26fFe8EQQVHpDsyX392K5qti6pQvV9qQwEie9dHI7KT3l0vVDq6YZ7cow3VsfxEkZOIlqQe9uFms1L+U972jX'
    '3HJ//ig/7trrbtU9LJxXwTkujsNMv7FzBsODcHA7DbMxa5mS2NxJOckumFlPyBQFIVesN2Bj5JVVcayRO9DU1jG3toqbZKmryI9m'
    'TTtmkgBM5uEorGsL0SuDMN+pd4yQunWzd7ljf9px5+ZoNJHX7mAhPHuDrPjUyMtudbJo2dXX4XqU1QGIkttie9cvLJ5Lyv20r5pA'
    'x9crs1ErvQxf5tPss9BQxcbitfPq2sPC0Za65c6L0jrp+cWwUNcGk5Xzai6sk55bnCqPwt19pdFph0NZlcfTqbNtzkX3XrGetV4N'
    'zgQw0rXdWDjOMy/7R+FBMtp9tfxyqg3U8kGpvZ7GZT176A+axc3OPSzXo9Go1n+ZNSylNZGUulQZn/YaMEDbtDIQHxR3vKsmdwWl'
    '1x6bk356UlafvELR1VetUdJuJ8vySZh3H8YgFMwrhbZRN5VyelGuFh4zurxAnvVVy3VHTvlZ3AmzXW7tKfYs3xdgTgvg/+4qrZxe'
    'Si93DWVTsivpY6Nf0q2s8uROik6udOrkxWN3vwLRSutNWqOJ2FOLxtGQ1tNd1QK20y5UQXS0nl/vC7ql5dpTKVden1rDFsjKBSc/'
    'Fexae3qw2qLQrrm99lOvY5SLlmZaXndbtPSVPkuWGof6c7HaHT49tibj1/LWmkxa67vKKatZUnv4OOnkveXUaabLd/fD9sDzXrNP'
    'Ta06Vi1be/WKT/PmZr14LbQXYt97GA129lZP1ub5jVotTMz0anvcaUKhK++ntuYqDWs86yqu1aj37OLYKhXXo/lqU9k+zmHhB9mK'
    'NnBsb9EfteRhWW1ardKDYDwL3UnL6uad7mGiLbevglJYZ/MLr6wa6eLgNNjvcs4m+dx8XsvJzWlW7yXnYm+sm+Oy8VivblzbfDbn'
    'i0m/uT0A+/yitlxRUsqj3aM6zjTHZbdWdCwpM211HweH18M4q87cpmA17MJzJy0V5G5BXrXTw914PrFGnfxg3VSdSroyEV5Glf5q'
    'aLqdjVMpPLbLnnvYaTlr7srWcezYltWbPZtmVZAqx/RQf1Wfvd5T7ylXP9w9Tc3Xhz5I22L5Kb85tIf5wWHRa2yE7BJkzcn9c6HW'
    'MUW9J2ttzd6IJVHIzfut3GlsZrbHqXTMuJ3Hl1reOcy2K3FkeftZbnzMDB/NQmNjWWZ1UpmqjiQcndxcEzIjqzsZSKuClNGXp+Xq'
    '7skZdxuT2ujkysBEAz8nO2UhMztpj68TODhN06rZu8FshlMwrJZpW1sv/bpX6rBMo4mSz+uuvTFK8ngqmrlRdfE47nd62aNQnfS2'
    'e+HYGQ0HIyC5njU/dXL1Xe3xdT+fz6S7nFqaSRO7LreHmcfWfFbIoo5xnTNfCidtqjYPT6I9GlSmevUoPzva6dg9jObSs3PojSeD'
    'x3Lb3bj9SbNd1saFtfk0bs+eVuJ6++z2LXXhmDBIOLFt8/G+um8fjmNX2HvZmau7FcuYVyfC5mQOVbOUeyqO1YX5VBkVDvZwNMr0'
    'qqN2d9FYbUsjba7qNeVFGvcy9vxRNObd8cmUmquMmqnszJzZKFRn9ZxlrZ+yE/HZ9ERVLM6XheeuXXt42Q9K2+5S2ex3x6ndfh5m'
    's6fjxJyXnI4n17KdkdB7KDinbenlNBSUwzArZ3e9fa5mu8fawXPbmAzz0Ab+tpUdHw+e9/AsVdVicg6DK99pec/Zm8a0Yd3vaneO'
    '8/Ka37nV/Q5osGj3xNaisRkNJjnRAp5w9uyVTpPeSCgVdr1SoeMcvKl3XyotOxXHHVXWy1Em05oVFUXfFI41pS0DBa0DvyX0lGZj'
    'Z76e3FbnfimAMH2adHZOJWOW9HnTGmtWUek9N8xprimcRj1ZWSZfaoP7ee5+K3cazigvr+1axyj2zSkwm49Tw5Xrhl5t2xPJEluF'
    'SmcJzMe2PT/l7NkcRj4x1r3TOHnqPTx3ehOlltmK1cHM3Jak0dGYlB6aW+u5VbO6vVzFy+p6y6jfF1fHmZ2rnjrDkjXe57ReMWnK'
    'ufk6X++Ps+7Qqjab69e123IXcDobPVO6y5t2tXAca/NHu1RUZu3FzDK3xVbTsySrNc6JtXZHaxiCXBplngf3ecCrctusSJmC0io7'
    'NXHX7FT0ZNXqLnfdZ7Na1bTpdChYM+toTg67nqUcAOvNjupeW3nrzLiWGR4t/X5WK+d3IM8KL9mHvCG2p8PusfgyKjk79ehZxbUs'
    'LA5C/dDZPL28PLbVWrPzvBserIbudE5ZVzmMuwDW3qA3HLWHo8dNdbPZOI3VbK4MBnNBO02t5GxmzXXxvggc62pUnVrp/YOg1DeD'
    '3mNNBvBMtgvp7TBZ3gyrrVGhI85GsNWG3So5dqFd1QbCNmkeslOhvs51Cxs5WuW8em1XahVHRU2aFPRdprBIOsmHstrxhFEvXSun'
    'T82F0ok895v3Fa3SrPS9VvlQlGANqvp+sukJWQvQd05PzgalU8Ys262pUGx1paLX2/XXNVe0klD5AUTCF3Go69vRYbGt23JSWIPI'
    'sGscKmtHcB236Xbn1sxpjTKjktcCzqlv2YeX5d1k1NQetPtX034YwwntSNZGb86P2bu7+ePxz/VPaq5ZMp/FRbdfOvUblZowrLZb'
    'dXs/sl7dmVce29Vy0lQ2NrQoPR1HruUmO83m86Q/bD73R1Z7sDj1vdG4Wz5pIzirBaWRGz5Pt8oM+PT93VNZADH41M9UevXha7+r'
    'bklAdSYgoQKKbKqVB8OcLrTtZAy/9Pun0aBTFO8Fu28vnqxie9EsDLN6U5WbxlZXc0Wp7y27rbVmbiXNlo5Oe7SdebNk9WXvPOf6'
    'uUFeXJnFkQCSng2iqNGZb0eljXQYZTeyUVqq0nBUzbysV6fquO5MCsXZOls8TWrapPIyfm7WVvqo2Dha2qzudEZWpVPJlgbqWh7m'
    'qq+vSmdedGYvBZDQa9WWuSxt7MIyKybl9QF2oKhrujk1s4PWwB3372tG5VQdWSBGjWREMUMhv30sDJ21sB9poydbyz7ty8KxLeRE'
    'u35v7ZzX5bQ2erSP02N/cUQ//P0hXdJ66Yoy1MTD/uUwWXU7g1ZWGGntKnAGh9ZwJHcfW82NeDq4Vs2yGiCXAb9ldnqKLQ4mkjky'
    'HoYvu8ag1ZlujFz+tfDiPTaVUv919OLah0n9eXx47bvb+ZPV1ZViSxQtV7IanlpsWiAEiNtS/uDVGuKuPqy1naex3urbzsnqPW+n'
    'ujfX+v3tqCGIhc06C1BTzQhA3PV7uZpvDp379TYNeGE8PqYd2d0lR0L5MBFLj1NpkDeseeGlaJnNo7Oo9obOXC+W5tNcd5bbqobV'
    'LMh2T+kqxfqhbHuaLL20p1UQNTeGqGbahrL3juJzsXW38dTmugZTLs0y0/RgbZq7ydC2HpurVQHWEEH/vqU/P5nmrFwuDVp1d95u'
    'D4QXZ6uKlaLT2s6TtlJ5qDyP05v+tLk14DhKcyHTP+y8pqwOm525Ye2Bk6kkd8NCsaFK3Upb6VjVzcP9RNvOXNUDiSCjG/9hvW99'
    'Pc647XFGEurj1x4IQZ3DtDA1a0bBzlq4FK1Db9idguhfLkvLubDqOFsvW5021VL2uegtTtK8CoKoaSePIODvRFWqPxcyxdGyMhxZ'
    'Fi4lSNfD9PBVmAC5rt2/9AetruI0s56ly954vh3OGjtNyfWOZcXZ7L2aZ/XyUief7rxWc8648FqoTmfuvKQrUufFzANvNgZpyhY3'
    'k4pgK3LOGhV2mro/LaRX1yw38335dX/sZJvKdm3NTPO5A8LRCXXX0ljTxNH80N6Pn9xS6cHbtZJrsQ0YKucBP995yCvj3LO3P1Rf'
    'zfH0ZFRh9CNcGHnQPDj9xakjApOf20wGx22+cippj/lGut8eJcXXojCudoBp0WsVWc88y8+eed8Xxcq61F9NW0U5WrhTqBxX5aeF'
    'iW797UV/us1NZ69OtXL2oS4lC6/Jh25mPVps1+ZLz3kxxg9JPfp6a82Wkv748OLW3MmqmW0NBgczJzSTliZle90n4OZGgDNXBU3u'
    'qU5+3pZHHvB0/VOpmtXay8FkVm5N+45bke/VycPAyjbb2UN3sLPMvFmTRcOemHCOW95zdu9uKpu5+pBzvLaxzxyBWzltbalpi1OA'
    'SutY0tqj1lAcTayxtOlndtYokzW6j+NCxexVnvCmLZwQr/D0qncbp8ZDZWra09ZBLWpWazQdd8T0djYcdxRnMBg9iXrVruZED1in'
    'nlIpZtzuSm/pd16tMD6NJw8gRcyynd5p5k17ZWBTl1ZXtgrdF9PtlXSpbT/198NOuSw2NbPYXC8Nq1/dVNuDg6uq6nS7Hr+I8B8D'
    'pICG2lD29zWA7P/Mv07dEw/qTikA9dxalgUn9K7+bGzF2kzb7icDz8wAOyvrbWFtjjvpWVFTdrtheVId9J2sU2wAyrPbq4eR4/Z2'
    's9akKLrridnTx7t1vqbOxNlscqqP5kmt5Lbag/Gh5Hp9UxPGfWNizexD2SqtAWP0p3vgjSvK6dHL7ZLlvupVhlpn8TJWs6acLCxy'
    'y6n38Fgbz2tN1x0thkclqeyU/fDUtXrd6mHoTDRdE2ZSdSh2lqI2knQ3s7XrZu5YEduDnD2YSu1xTZhKeFnCqdSOWzOfybfz3sSW'
    'dtVRebY5dkFW6XvV0+gZ8NvcSx/Ka3kqTmq5RUeYuAMlfSzv7x70VngZRqi/tO5GxmHRbxZn1lDYT3P9pjXdpvd3611u06huV4eZ'
    'pqlwNCeZsr4DYFxZtcXQUlrqSlweko1Wa96qzGethSyOtN5dpfMATILgToyhKpRmA0WoW5vRqGKC4FY4bitbMZdcwH+007YuOpPX'
    '9nI0zsgnMTfub6VSxbZHaqWpZHKv9mBb1QrKS220KA7dDWzNPNvJGkW1O3puVNPbTF6ZLOemttrm6iNJEKXhsa3qubZqy+3abmL0'
    'QEiF7fM0ye1OrcqgXbUtyRgU1NL41NrlgDfZ3W0b9cd6G4bYltZbawv8R9Gw6s+d1v4/AoXFjqaK3rHYU5v6q73pdBar9LqXzjVe'
    'Xg5a3Xg8FZL1ZLuevqs3Ip9mveJdOen/Fs1tfQuUsZatzJqe7PbGu0Fl0O+BULAri2nPzAttt7ke2oMhrPzMtgRjaHhSbtXIPqQn'
    'ajbbzPZzzaIgya1B7zkH4sVhYvU62uJpZJ76p5GXfWmuKrozfy72hZ3sPNdOE13UYUyi/ADNF04PuXFxejiND/2jPj1kSoKcNE1D'
    'yKzMbEWsjEuqVTouXqyyPR8si1VtPjSO3u5xUyoakq4clGdVrmt5vbd3S/N+wzInycow1/LSu8W+s9AnXnu4KcqPJberJNP7x518'
    'aD8ft8dRb9ee6LWXse2eDFvZ9fKF7j650ZVmezOcT/NbVNs01mN30HsaWL1H50HdtYquMsgW15VsoSqIY7mZWTkZoVQp3d01Vq1L'
    'DOGsa/2et95MhRJghoK9EXrDova6WryUms91qSBLzV6xtZNbr2Ym2emWu8azdW9ZmakwUntVz+5o8mtWVMuZ0e6YO7W8bXWWzVrl'
    '9tayRSF7dOYVRTbTFW/3qpcsbVl6lucLxZbrUms2AnrebWwLp1G+JcD/8uuhdJTc0kT1noXJwMiqnvWcc0rDUnYAmN8s755Wneyk'
    'VVXG2+f6vjstVoud9DhTVouHgVvMFCu5+2FD1Ieu7pyK+Uph8GrnalvgwHM5SylUcpWSdy9KNXv6dDjNpPGw2R9mTtOmqy5sa9w7'
    'Niq79cAeHIx5+5SBc1CdpaVVd9150bSXXVEeV8fAeRcGnXxH776mD+NFrtFRVmnVSXuvlTpIgZEPkrtZS956Vmvuhupy1tnf3W/+'
    'yllJ1tI5ceXIsHw7yfREszluT46d4uJJlUXLUxsgzhij/un+1D+0VctVNvKkPZ+La3dq9fXNyCt0HnbSVvUmWbn/ZEpWsjDYTyWn'
    '4qyVgiNPhruN1us8bta99tPktEOOs1HqbipmpbtVNoMxiNrZaedVKKYtqXR6qq9absV7vXu0Hrfc3KQi19QyLKnaLu0ft5q6eHAn'
    'NUGYtCRbUs2T9jw8NgttPdk7Fq3DYiYYprFsj8TVwD5kmxvJyGbESn/dEs3dY+s0lXfV+0Wp1c8p2X651BdabVcFxs7MNOn/RWO3'
    'eVm+asfBXOt2p3ZO1L3eVOwb6nZdzIx79YalDCpj3RxuM0lxUnEz47zeH5fSYtfQ1pL87OYFwBB3lbu7p1dt+Xa19/dZw67PgEWe'
    'PPTGQ+HlJCpopy9VnnpdkBfU57zQ9RqLwsBdtKuzUnc+blq90Ut5Y1c62jQjqhhHpbd4FS1hsC3ON4CO88XuqzaCQfTq4450cF7z'
    'ujUby1p/2PZGuaKnrWTHNDNzWAJpp+XkfkOc3g2fgAyUj7Ny2hIsTRwLQ2V8d6c8DilqR3VUFXpy9TV/d+9l78tHpzedAznqC0N3'
    '7x5buUqrk57I6UZBHs0rE7XVGneKQ7notttya9E6ue2hk83nRLElBOu6fjW3g8JxNl+1u9OWOTfrFmBqC9CBYaWdktiy9I0wswtC'
    'q3awj1l3VVlllFVOGOjKdFs2AVk+S3f38/r4T4H6aVQ2149OJb8HzrE4Undbd2iduqJerh7F7mRwEAHGG+YIWLMKHJnOtGIBN9uu'
    't1G10TH7j9JeWuWLlqXZ5cZIardc2+0Y4nrUyFaUfaU9GqTvapauA0x3zEx3VBw96KfqLD8upF8L+thtWiOzXOmNJ7sJ8J93m87g'
    'efHStt1aVqwW5bl4bA2yXmcnzk7VZCOfnjQWB32gbOYDwVGaHbl4j371+1l9/3xfGnSmu0O9Xiw8Jl9kU3+Z5NfrirRK17r9tlnM'
    'dqu1znIysQpSrVd+eFUyp22r3Dskvdf0uh7tYJ1Zi4q7PrxGWn+cbXbbRqHYHh8PL73FojV+LT4X67Xk9P5YHet2wypVK7P7zkE1'
    'Cs3adjQSC4pZEnrdjvq8K54GY0E5GYesPhyUO05uKDe9ouNqr2JZMU6759W+1BWd2qidtwxhrXkZe3JwR+1qQQMhEeALiGNlWMxk'
    'Juaz2HHmtV7PXa+nAsiPQF/ELbCk0hNQmEXX9gqaJJij2fzklca50a637o/zd3frzeX5epqWje3hNOk+vFSPQCyVZPZoJUEEHk22'
    'uYbamZya69Hk0DCfD4fGYbOZG4VaWzkcm6jZGlV7SrO5sq2MMFzmd0qvZC1tVWtuKoX+8imfzx9HfQMk5NyDMKrerYXRyeobo6Eo'
    'LAr1hlp8zmuVZ7NVNl9kVzY0U1X0sTapmqVJ9bkjWAflpf40clueBeRiOocFy7zWyhVrUtcPLyfBa5VfS0Ov21Vnui3BJh9O1UnF'
    'ztdso30qepP77foup7v9fDn5vFXcw0Kti9qhUB68VOZq+qkztdLu4k6+9xajY/4lMz1vupddHzeHLOy0LE63sK25jpV3nyqP7qD7'
    'Mlpkd8vOMtdFIBIb406h215rrvJYzz0Yc+c4aU70cWNX32ZNI5eplHeb0eN9vnocl2oAIWkQJ+6H7amX0aqPlj1pmV421zJtAxj7'
    'QU/ZDaRBU3gShZqLZoZM7ynfGJQ6We2+JJ2Mdi1zBP7+JIymSmExLNzdz+r9u//17w/0E+n07B8f/MDUQULz4MoP5TXH9CF4E8fw'
    '3MvrNul36oyVOc8HirHKMc+Ln6ZMZLkQ//Fh5bqmc5tOK3pqr25UU5FVMWXYyzT+Sr+ouvyvW9GEgdmKKGMCNc+NbeFtDN7692dE'
    'P3UZT21jUBbOxOUIV/bF/SUWNVvSPMyPssdMWnh/iaVGwVbGhk3Btv3squ/e/LqIJy1cBJTOYbj1FgXp/jtbi2jw42ImlclkS5lS'
    'JZPJFM+iS+fzlVQhW8mWy/mSkBHK+f/CKOvZ790Do4G+ve7VZ7m9xGh+PVzis1t6rfC+Fo82jmvIM27TrTfM5KGxvLQsX0mYtI7C'
    '8F7HZNFZsQDnsuG6yttLY/NfRcyTEQm9Lrp+RllFl89Dt7srAAc9TLyCGYj+7b//33emqR1xACwTIosF/2///f+JsTx5Z69jlEEr'
    'zBYVwBKt1eadtaLXsbWh6uGQ9SOlouIpeCKTwoxXMbrtFpPVBYgTmNAvzHCUil2sPE/45jcsU8IztrSbGKy0rClnSRQpf9jbvALs'
    '5uNFbuE32Zsi16nm7AJemDoqWjUV8/Pm0TCgaUz9etQUP9XdebMXqVRYeZ5f7N2cbxcR0LMXEdAfGcxQmuq/drQKFSFVzORyJYzJ'
    'UC6/CSvun+G/FridOg6DAOPEWRhgHNYHugkbzuUiPnr2Ij76I0H95VwwWV0qmylkcoVKOVvIRUM0FwrFVCVfKOQFjKGfLwh/Ppc/'
    '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'
    'Ro9/rK+qfL15Iv+h9jn+Alf7yeg/7Z7Dow=='
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
VERSION = '2026.11.02.1343'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
