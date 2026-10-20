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
    'pWIkI9kePPtaXwJgC18gmq9j9+17Nul9LLaN8kqM1bo8DjEFoLG0GR8T/2MbZzbINelS0PeGQbrngYupoQocE5a0FF3aE6MwMTgx'
    '5UygoUnLcTJslerS1sa+u1cNmglHgvVKOvHQCJHEUXNYLLsUGLFHpZnwB/BTENIZSQnuOUmoXkf18C7lLKbyAtnwh9tR063TMcs9'
    'dzC+tnAgqNbI0ODTjBu3Ww4iEQldz7BwyeF5wCM1BA54Ot1oYtRr1Ko49LDVa9pW3y39e3nYWqBua4sZTNdo85SbCgZkTK79RQ2E'
    'xOWx0jVIQ81DeM19gG1HZ/RVOE36fdk1jOSN3bEqmU/Nji01jY24y/aBBVtIMmD+ZZLBXds+Le7wTMholEkKvOtgKUTUidUwQGJ5'
    'ay5zBrbaxxf8Nr/YdGy1lLv0yv3dllO7Kp+rrr3fyzhyYJw0TEOAJxcWgxla78NlMNmOmE2FOE+Sajpmn5DaQ39VvIpO3xOYxLY5'
    '2iTbw3JhowhQN0TJOOJ5IkrCkUFgkQ0UCh87NqfiyD7vZS+Mp3RdhCcvigSHBnSWpUThNeDrQVTrFMqN1A/Goi6smmiHBT/3bf/Q'
    'aliRBo/ARCeXxXCpTbkqFac/Jhi5G7MJJLNrPnfrDH5bnliL3iIXT9Nj3Q0o73YEVMvW5zrQEmwbU2waWmFuupDv1JTn/ELPvxra'
    'fBPHHdz+FYL2Njq29ijqfa6HaNNgqdt49gDL8HGWs3xf0lwSFgbDd3/QqdjKydm3m1u6H+aCew2s+2DuTI00StGA3RpcR7oiuuyf'
    'kpW4KOL+STJwiNJe+PVuGxwpbeCD3H0r7MHN/msisYTCQoYeMMGKjEQrl8CZeZetTxqSSQG8DetEywfAbEdJ4ze4i8ZvgfX4QpQ/'
    'mwDhy1m57XoQEL1D+fOTRMo5JV1FtXUnvpGW9AN8pN/FfeSwz1boMBwTysn7U8Q0JMprgmAWNooglcMdsBlN0rG4dBIFN2bv6T4C'
    '3fDAWggl8c///f9ellaiX7NslHe8OGh9Ve+hCigTeRolRaxkml5dK6BfBsmwiP9mryn37u+btdeRh6RvUai1xfi2qkZTI9uK0syd'
    '9NMNmAoM49GkqbeQ2p0kF5PmihkgzHDdLInC7qyJfe3a2vojGEqK0PxBKApnz8Em/2uUed+jQ6On825s9kJs8r9Gm1dXFPB8ulGV'
    'isPqawIrlrNEibJI9Jmr0Qu2NxDrW4kMZlAr/NklVmc+gd2BiyFvVDxSsMV55OKok09ShNqBnZrN9YXwooIUq8AN3AkJo4XvWsVt'
    'LdXG6EEQKs9kURcc/soqyOdhaNfiwuayyS2n8Q4deB5rDHxgHPc5c1QyhYt9ArdzSx8dlW+DI746hI7Kf0yLE2Pz2SipWMskmlAU'
    'hohQDI+Xu866U4iCdnQEu9LAbpG9fNpgEI58Yh27/IrG3DxSusEa+NZgP7pMKmTxXIsfLM5Bp9MR5nfSy+LpAFauu7JGuDAPDluH'
    'IlQ9YuOHBStjV2+egYBdAp3o0Ty1/2lyyWOZp/Ifx2eWdp0T5bkmQv6g5O17qxpdEzsLGcVRImtjl5y5NM+5sEVqFIfny7Z15j6D'
    '1doABPEZTNOQdm6STCc2qkEvb0oRxkFc5MKj6qQZo6TkmjvWqxvZuWsHZ9x8peCy1PvezysrJbZofTia/IB9gumVdQseOxMdF0be'
    'yLDYYze0GPbsMUVOp66ye6OMiPAhwmWP2xFHG+GAHLG49CQD9nqNg/B4/WxE24SwI6xcldjFtGscHk/V4SdIAkM36CRviTusuZar'
    'LrGhqWh9sMhyCA3xtWTiseYIHfRpx/uXkL7D6muX7jbjb4mg2c6LVamuUTpYiZ3PcJyOGA4lbnMKsuskiXG72h7urNeWMEoPYb7A'
    'eSRZu7vCWiYsUd5odbKjIzqEVg0O0886A1I2GLDmls2+bxMiZqJsNhCUWA5KuLYubVtsJdr37UKkrcv1conloITnkAv5CwxUhxlw'
    'LU04JUgaxRd875ykENFldCroDXzIiaXbpSud/ixLIVV1U5llKi3PGlWDc+R1jf8YpwmICD9T0S1tCP9y+130JJ3salf0oht5nsPM'
    'qkt2Otg5wKxiBAsFGlRL+XX5CouIS/kqm+aJKC6YmAOOu8VnNSBDdaUu7P5AhGMXuD3H//lfdnreYMuE2zyeLWGWi1wAnsUeDZaL'
    'cIDfVmQk4pTvjjY7HNMOLHIL7oZexV7tha7JN/eMmzpk3M/YsdJY/0mgWzFmoIPdk4/QhTXHrc7ROY3qT/ANxLXmt/JGLIPntZOa'
    'z/ft78D71mtPLEzAH9c1pN+EoG7qMzW1hggRCIL1gG2Jq40voCpqTBnrbRYBsbYdWuDppZgZZNRIB1rE7jgrmgdiQ3zYYnIq0NgF'
    'nIfEdshGycuhTalpvlvpD75zIl3Jz+wSANLYcjvQUBmx2yGcyEqmRqumScmwO0GOz4Wtqok0LWVdByJnh6MFzFJb1atjlIneyDA1'
    '3I5yboKXeYFtgKlMsoL7tp3zKC2eARLxstUvD0ozWiKKpVWj1aw39RKSuKxSO6Vr7W12DmFtnvieQEMdzq9zhxJIzTWPZFcTWm76'
    'Js1+c5dzm5MW5lbM7zYOJEF9KquBnwsazOY2mPHyzq2Y3G0kxOQSffNhVkCVxwOSNx/f/1DTuLa9OrftksJu/vB6tzQBpLegenpL'
    'dcF282ewzdI4fVhesNtAX831ue2s3FZ1ZX7dtcZ8RoUDA6QwgFJ/9cBx0JdflmLgKwYsRb7H22Zwcr3pv9rgp+ZpIOCWs87Sy8jY'
    'cKvyzTIodWNX9bDR8rHstquJIM+ngrEkC2gvGfpWdEBnbFxrpoS8b8GIdqNmTVB/bggTkEzSp3K61e3LX6nT203IrS7TcHGBFPRO'
    'qM9PAVRf/4UkufB24FncP2UJzAJoCnNm1LesO6lP0XwMwA46i6boXABCvVZgQWXyVPp2CvMtCG5qe3o6nWbnb5OjYv5dQsw20gOt'
    'zRkrt/AJHMXCJm5r4fNkYfU15GxfVB9K+NtaqDZQOXL3fRV3PW4YmoAsupGsd1c9rGQuEWcTOgvzBBx06eAc/pEvERb9GtHeNmt7'
    'NXy3yAzZA59Dh1Z89/c5JDxnNiHOccxhcgylgidMMkV4YkgeoSYeqlkXSxC5REYAxZfgQD+jvouu6YXPoLO/nxYQkFgKEOigwDtr'
    'XWrfWGkQ9fQezIm17NUXnv9Xpymzv+YU2t+tptYZTLlzjvZuQ2669FTNkSw1sM/nMfc7QMr4yZD2pfGFAAKhKMX9yVkdoTUbrHOb'
    'mBMztODLDmM8eSWBHgUGO8ic0CRamNFdg4MkIHyMlCRSfIXDS/CjShm1+a/fXZWa2/Bbu+GmTBmbqHjjhmNJf3VsST6cHVtGoum2'
    'xa3owU9fzr+sRIfLq8e8lIGvHb+jizOk6XgNZRtWDEi1NgXIYCVyjmjARQb/ZMTlhnywLRIiNhXuomS03olef9jbFxqTLp+zNGZw'
    '2xPgfqFJeIitk2D/w3iGSDWIlyXBuJF8O+dAEpKMflX+EPyuRqBnAe3D7JjD+XMqJslg3+HeNzrR85NpNkpnOA0QmUZ7l8TDjKKn'
    '/X6S59HTj2+k5INO9JEzQoGtGWYxgmjzkWBiPWq+SqfJUXZhA9cGY+3aMYmqmW0DJW9UP5bw7bJPWArEWEiJ2D3v7H188+Llp5/x'
    '0nByVP9jyiqy+1yW8E8jP8nO0T6Gj4+gFWig0oipOOEP+5cTPhYHyJmY96cpByvsRg1dbrONCG6N1DJdQmkNsNSpjHMVx63RjQ4a'
    'in0ah7glDk0vr968ffnz3v6HTy9h7BzCRhfL1dhkeRt+fozZ61hErefxlHb/hVnbqh+H0waeqWUBJ37EG4gqCMvSKgBJNMM89O61'
    'L7sTjp7Owa6gHoCywTKKGhjB2QXZ9GwPeozPISSjBtAUzNPGowVxNHK2DGnT9+LWUpxZZiS6ivcyzsaYBoCXBWdIIWKGbSbRtdj0'
    'FmFxetHY5NdhhcY///2/mw886203UTHUzRtioUZTNAiAqSuiCZrjESf8a8qa70YH1A4nndVoe8GCuA7UOgBogJe9OElzu6yQ3llY'
    '2I2+fhl/d2Web76y36nJpSlLZpq1o8CcooaURGtz9nR33hfByIg94RpphMinYa4BnLiWBIbgkzvcK7IpFEtQUxDSaDrwb5dNsK4s'
    'zLdt322F3xsm6kyAh5tSUi1W5Iy5+MQ/MiJniFwiLTtZBQ3/lKGmvHhtqkl9X88uviDB8THYrtkbZr02t1v2U5gHzpocLe7QZXA0'
    'J0IPWgUF3hm4ky9jjyGo7qvVP63CfjpKEBpMrrC6KCnSEZ0yJAb0RHKE7FP2l94Xf15pobQ9RcbLLIZysr7rVnxmW7C1oXB9RmNv'
    'HgStN1uHbWccV8GbLDQrhSGJJ2lzwlDRy1jKG6a+ndqYI0cJQYcWvYpGCV0zCJn3kWCy0WYVQDLNGV/rgV8Bsm/UjYMu87+tCIyv'
    '7NMaAqMDtul6pwcE0cVYKlaEeGkCNcvofnERUTpomQgKBmLdJQL6hAjtabd8opi8hGMzrEmmMzbD6chtjQQ0x5x5MZPIGUL4NviQ'
    'GAnftJOd4hD/0uH26UzSJX7Ou/ISL5r6AWUQGyIuZjn2x/fi/WWzGhMG3G6ynzXlaPj7cG5nKt8Ukn+kCrGN+yYFzjvcTNNCBvNs'
    '5htL1ixUM9Bpi3LE/bPte1nsMZZuKNXxXmT31YBALJryQhXixR18slywG4PnQFkY/OFSjThwBNw2Vunf1Vw0+VeMY7oemoMKvRuV'
    'DggHuTEzn+qkpx3Urfi+uDlLQStTMVzCa90n4zooa6yb6BXwA+g0CTJaNowOPXSIds4hDsa976LqYFoak4iJNdG3EVTyBxH0eE6r'
    'Rj44Z1Oe5t+yLYp+Zsd0MxcS3MLgeNoe4oKEwiL2h256mo271HZdyS5T/02+2AzVFt5osvMOBqJbdnslznnD7cAW7LUXDYOOrQgj'
    'hsalYQ4U1Gy/ftFg07dt5QLhmxLQwaTr4UeeqsR105v4e+afvXUA6s+7AbV907LDCYfNWz+V2atYopdNC8ZgjVYgZ79hGkivYg+x'
    'tF3fAUoJ38r6lEhsIp3Mb11lB2fdBd8ARdG+HgObj5vOxSVyViqXB2cuZqwkC1ItPyfwXyH8xWi4cohEdm7FCBXAXQCyqNowIZAD'
    'GESXOiKCQonPVIHGuq37BoizrNoHNc6psGrzD+LByaGdV7WJ5pUBu9+PrSMSgW905e+8k6xnxV86GZj+OYExAwNhS6RagNKT8HYz'
    '0Wn+tQMBhoN5ypajFWvhRk2hmGovj/rIjvHI3TEurZ9XXsDjDoS4xuwASmxHCBg/Da9YDoopUjuN3lMY2iSS8oro/0oUHUK+oALc'
    'h5i9+OvLT3tvPrzf9JsapTRCIjm4YM1l5wvtLegS4BFlRGchO4reJ+fJFMvEa607TRhi32PW6KhCzDfQRKJsdUhDPZNBwrQmPOMQ'
    'mHBI89mExuVbHza0g260tI+wdSJHySEZiaM8ANmlQB8w96I8Gs7yE6OhLHnDwsbvo0RV8EpILCUYuAvhzyunolov5Xy9l8+CCMZi'
    'Rf10ODTcVE0k4xquLiD5TmgFXmejxHezFbggFvmDyMlE6EekuqzuQN2pxgpAZleaLHgytHRqs4KCVBY7gBaz2dqqkUrySfLOV1XB'
    'r4kFrJWobzupmm1rNelemZh9jcamMfzzbRUZzXAkBJGcDWAvyFI5KxAKkT8Yb+h2qF3lORzaF7vOgCEh3qqN4KvgD11wvjwQ1kV0'
    'tZ4lGmaBw/bFPYRTwTjvhZfNUXiKA5HAcUUk0GptOmNHjzU/6piHTZ+Fl9fvmRk2Yq6jDv9izYwTF1jrALYqUYEicVgIDYK5r/70'
    'Bwx+u9lZbn23qvkVKut7//7I2g0YlKFJT40oaK8AkhGkh4T0tjNA8NiYE0Wlq3cFXz0GQQLpfv70BrlXszFkBaODdaR0ovvihG75'
    'KbbqDldzG9wlZ3Or3MY234ZKUmsCdCUE/smMqQ4HxXywebGV/RFquk6rU6OjET18N0KsY4lvDPE8qxsyUdeX9DEakmaY9fazZ4Qq'
    'Hz+EfSQ9GhnDR8imCbSQz8M7ZlONXoyt+8ScP2scO5khogTcqRatHf1LQzYajnajhcVGaYQReJqbGLUqirkRCb7Iq8c6JaCXFOEK'
    'YxG0M+0ncnUrsDfnpy3O7pyOK7ZEa6eOKXrJjXuipXaErNkLqLxb2RMZb8iddL22Daci9fyVlwW4hWVRzuSlWZWAOQmskhZxKquz'
    '8ekYCrcmXQzsfXIt42Y6rmW4OR+gcRk/l7x5uJKBkwBb04Sv1BJxTeg+GcfsiYXCuiYwFLmVYK2T93lSiGDiSi4F4RMq9NdkfMyC'
    'smxS5BXp1kRUGbhoqBxHHiGMzZdEm51/gZhQsyMPsHmQOiAOwUPQupiYJZGwXX7y5Hh6OpuwdTId+qYqXLmpVug5XI0NNeFzBNPY'
    'H40RYz9JhxpVCV+/jzZaYlbrfz3xvnosPEcV/7qVnx1HF6PhON9eOimKSXd19fz8vHP+oJNNj1cht1ylEkuRxlv57urHmyUNNoqn'
    '1/QEy8dn2QUeJWwZdXYT4eHSPfyIf6j0zndXsgY3W2gYwVgWhkB3AdAbfEzEUJ9qLtOgN+nKp2uu2J4VRytP2oCAZFxB5VTdk4WV'
    'A6fL2wCzsf+Hk+9OcUG3zPW8Fx/F05SmBWtk4+ICVR6S9gpf+dcfkIE3G7EjFFJXywXj20NLrHqFJHkgSFoG2PGTg7k7BUNHuzYc'
    '+o+IqI5GgrDor+3be3cJjs6opimAbqPgI5OWPRruLUiak4T4PskegzDpCOnD8WSpAw3kU0gUn97xpi3BblcSRF2H37ZDNkFk5oVo'
    'r6ngRF+V7UTocz70tJl+VPQ6/ODZrlW9T8pkvndpCCQZ7AJBiBNyoTPqeSJ+PZUu+9nk8o4duktHITc+S49jRO+03i8q7T3AKjw3'
    'L5n0u/In33VjpTvmMHTlBMFAo0o5e2pkm54X6dx8ZzllfBanQ0b2LKCExBLSF77Aqd2G86aA6cf5STa0BiDwZQkTyPPZYgdmBFFF'
    'BgdWmLWNi4HkyR6LJKhHhGBS5G0OQM7JW8NcrOsbUdbgd53opUvmo3m6e3RKYaMRm7aNDnwCNbvqamwEOGdP3hw7A47QTOH7L2P6'
    'h20VImggpyaCj4FTDly/G4mjMev9DniDDln1Z37DFKMgsGE66MPYy3bbFXcLZgpkWTivuFk5BGcy69SJ9pBQJh52S+mIwErYKWM1'
    '0UulmXzWsyvePNlodaJXLu5GzhlyaRTplM12ck0Br4vcw4oTF5PDCzsveLzoxFSWuFGSSakTLRFRRFhlCeNClCbCt3Co4TbYnwZm'
    'E7InKz4l61n5SIOglHPrI6NLPj/o1jAukMmN4255IbVSCCYPDhBTi/iLQ+iXbXwt+03CVcnXg0MJuMwWPs0DriXKJwtHzffNrCXW'
    'KjNr8QNd8VAtEYmrjprfXenjTUsVz2F0OJ33M6zM/Ny+7WhExDbidY4CsyD4At23lk5tFhPk7GQVpNvGLsN1c1aoE7TaZvZnOdxz'
    'WDBmDo4FQ0dOzXIJxk5UZJt9ChHmg24UXhBq1KQm9AtgU7v8m9bBrdmYjQe7wudhz2wZf7vxir3csBFsHsD9BUpCRRMYGJwYh3Qu'
    '4FsXI+yg9RfxPOv6nEUTbujJwORI43E3hikNpg/aXhsR2O1yY7Sh/JYVTNpns9+xXSL0pXarIkR78/KWGT5DuuKFpd4k23B97noz'
    'xpFJNu5GCn73lNM66AjXgmFJqnbPvDAIshKOQNjtK90nz6LupjoszTLs8j650Ywqo9Eic2dVmtFGeUrr9VPaaPk5QW9sXMkkcfnc'
    '/XmeVObY+MCBNxRfNdo1w/YGfSTpHJMkLwHKkQUUztxUP+wjHva6txMOedGB0aRjT3UwsJhkTw+6Gt8RYQ1uSRytczk6wuwL6umK'
    'lVIn+gw+wyH9NrfhblQ5z5y4U5OTmaZtmU1D8cY6cLoU9JPGypB85dJUxB5GklrBD71KA9/PTNvNk2LEay7jtkk+7LCIB/jDH/7Q'
    'INCs2CRkbMYEgufFh3cfwRQQGyVCsFeEmvfYYqD5dQsGA8SC5DFyd/yq/iTot0X8CH/8Snc1lmwVb+nOxkuHOZ69/fD8L9TT6k/N'
    'j9evN65fP7j+/Pb6w9vrt2+u+dv/+vnD/svrj59eXu8/ffaW/n398umL6/1nH178/Xr/1YcP+9f7n+jl9f6L69efWt+teoEh8/47'
    'CRNGKEiWADQB7ZmjKJoHX758/f7ngy+HWzvXhy0mLL58+W7dtzM9n3JGuCbCJ7bCcLXSKhC/CafvAqr6/rYH7SiGXyLBYQ9qnsKK'
    '7ZpEzrRoFPmXvcPvd1v8qAI8Fy4Xnor4fzrQXz3rvKacniR+ESfz3I0RYCQXjQnuX0bCXCFMZNzv4OW+CXkEv9jO/su/7f/8/sOL'
    'lziAaHF5W9ZXS/+1krvB0GgSAl48kG3Wg1I39003L98SZ/Pe9FSfx5RzSHSK+FjMqzhAqhWHyUJQ232YtL3nyfnCnkJN+9kiXx/2'
    '9j99ABFt5oX9bja+/76hjTddXmxrIq5V3/jtvHxXaeMOTeyVhvLmLy/9Ny9evi23+t/+2x2afU4r2HBGHX0Jcdv3rQU3TbPmbHCh'
    'Lv9xAZgbXxssmfr6lQVCXAZk9devTFF/9V9+bbgtLg/oacNBmQ21JFZjzDA/LegA9WbEZjXwGqaUxgxT5+pR+5pRPBx+U8pzWL9e'
    'IqmGuIdd2FgL3QcaEO+EAGRjMtsclFVfD7Qk+90xgHOhm0Ot6FlTN1tf8kOAeVVE0qL2zTjnLcibdx7MmTk0DlQAwvzK1/sH6Le8'
    'Pvm03/B7KLf87FNNw1/GvF9RRD8qFQkPfb7e+/yM/v/x+t3TT38hHCQCyqJVaUq3A+Pb+u6qCA3Gb+gy0AJ0AdR8DketTWuNMJew'
    'u6ADXAeGB+fdEYetsk8y34tCXVs0KPH1yzhwmAIJJkPBF1P4kvqocJgaRCM+V2/fNOahJQjhGBFRY6YO78aHtw2BwHR5+abDfMcK'
    'AurNegzamAAfqAZAK4mLprRkOItqikmJK4kIHTQ8h+cODYvRx3Lcr0XjPn5l8yLad9y2drstYm051CJUBlNdmAWP+EakjskUUkhF'
    'ujQuc0a9m2Asd+pYLEx6rZuvdWRpX/IieNtgwHLe8PxhASSafV7TVh0QSVHxqfii9tceRLF5H+9cGZDgR6BrTdsauC5D/dsopo3W'
    'IbOlBUvFULCY2lkcWh64GLimNZlRMhTcxmtXDPwb604SD6u/4HPZMg3ij0ff/HR98NOXL4etL9fcxHfrX75cN8qGHgeoxKzdU4T7'
    'brqcA+2ouUxjC/FPPxuKHTuQ5HorWqF/mMGlFaH10A3wY8/dx0KW0lK7fEN6Qw1zP3kEDYYrYXF5bc2JaFnJvV3yqTd2bmfFlS6P'
    'y5JtdhxhN9R0c2occKJrUDAlyPGxjBlF45pvx2plPtrXjYCeO+AtR7dgPNumshu/GfTKChxyqq3xdHnY4jO0Ls5PaJbAcS6cs8Qn'
    'VyqxDOpWHmEx5pBtIt075cWGKoFo+drKwoEyV7OAKvdSy0kmIIf2WjYxQuvoUv9IzKNQa0lHpsiZe6iijSvpXQbTr6VOeYrN1kKy'
    's/ANzeuozpqTqtfzR48uu9BkXGalLryVumjNp6Zeb/hE4usHNcSV17T9Uu7CXOkXIIYMV8iXlXkiRO86AR3xB/GhAN6/YPeNr99/'
    'j5/ff+8Q+7xRO4au4Q1CwJL2wkIuYNd31xPodhI/jAPt81B25FwM/WM6lywmPvIWqti/ukz+ueqCKalMVPFXudoMCfxlTK8aC3bu'
    '81t/5z689VfC3GONBTN4/alRs4ENZ3TAi8KYY14TzEj7rYh9e7/Uqf1MyMbuUXC9BgelhmDTV1oZMgUrB32WZcMkHod77hw6hMp4'
    'q3Sc2uURduXjxtnrasEDct4J++0NIVUOMXdZzNs8GhW+zMPHgCzPGul6jQaNmrifnImqJDEuZ2MXSRKSp485aqs8c0TZUFIjBeQ7'
    'JDZO9NPzgg8PUxxBDigQfjjZkLPJ0pyukeqUMJjE28Zg+JdLyfn1+7dGX9D9nvXMUsBzQv3q5QfUgF9e9yLH9ACq8Qe+0Xpq1NOo'
    'gcVg+EFd9PiH39jARk0Li5twpSNHetPMIUzke3bFq26rrq4i98Wp6sh4N/O04NAGU1XXWBFgNlUw5nDDRpudTo18L8+MRI+jsImy'
    'JtgxIXNqBhhwBeXFGKZBiIDcRxd8NnRq8lHuHZ6Kv4SC1bxj2FTY5EPIiK6hyDHAdPX98rMWr+tO2/aaq0jMf+PJq1s6ZbZ2d6O1'
    '1p1B2cLPtm3JhruSbzZB8OM10KZzAS1Y/BJcyTD8c1ndtUjWVc6pNlI+qCjXapSa9XCP12plbxegI0/YHcG+srpiQD9APXasDX8p'
    'qlJ3DzP7N+7Vg/aNMoz8SXOUCryppH6PAxSosV2cR8iO1Gb4QJxLqFzF6hXnjsk0jvX9Q5YdE5f3IuvDa/zHbDroVG4EtORlZITA'
    'mkWnbbFq3o5W1j1jj6EQsdBcghAWa9Iml9zhVEJX0sIyNbG1Okx3tlZnw52GxAhaWWELz817d4bsRTcKYhf5Anh//1p+atdbLoKt'
    'yc5WuuNug63VdIcuhCTvN6uwBgHPZMe/GbzDdN9hopCMNskFADVU82S9wRn/RPl0soFfRGjeHEg7h/YKY586DvZhFpWlT/ExJE4y'
    'QD5RInWS1zxiomB5HW6+bpZENzfeoAWt7vDetEq7uRXZe8HfUtrMLdpV3dDlZRNMxWJCGbOpu1mGBqkrNcwnbyIGQ0OLbXb569Yg'
    'PdsxE9paxZPnQn1zz18od97QuknIBMi3Vqxx1Blk/QsxWPg1nQD8/vburbj4dKJnMyLWot4lG65HTRgKwwGKTk02mkyTPIcJiVxj'
    'MNHDTBCzExo0GntvGk9TNAPDczYyQN/t4CQ2ZxM2Z6VD9GKaniUtvljfUt3kw9ER8bYdZ0P7/NPzn5l0BUXYbFXNRqCt+kyH/cGG'
    'sNIbjyTvpM2xiSO8thlhR+kb/ZAkmyyOkZCmtuipFEXygyf0BwVRpB/9kQOArF28fPHsyZMHG2vRT3R4o52dnYgDfOjPzag4GB9y'
    'BTyvBX6EUDm2mtb1uD/tP0C0695lYUyAzYjWLl7p/zZ9NHGBfeLiMiq7Mgc0lJ8i4vD+SBN8dOjG9sQ5XnIR13DLDtCjkAkU2I5J'
    'Xb3YZNVb7GTc1+WGHcFLFn9LkGIEAGYiui1BM+OhPkkqH9YnwsDcU68VqbizZ+cQM73OZlOYXmxtRevr0bV5/Y5OrUSqow+P3Pu9'
    'hBoZ4D2vugu1CW+UbQ5Gyb5KRHH9PYkhtV6J1v/8ZI3b+TO1Y0q8I8xwwjfNerkPN2BWp3GwVIaOezVKaixYCWOLrT+tWUcUBU31'
    'Qmob1x4sL+p25Jkj1rF+FbdqUE+8hLpatA3QAYwBgJxjkNWuJGInjohnbSJTj1u+DFKjFLtNiTmiJh749DybHR3RpqKy4wvP4A4j'
    'RwyyQWozyMBjIfxMEWxw6yAeAQ2p+QD2hhdrD9cePOw9MpTY0LS8/rj5EP79NuOY/+Ux13yyVv/1CRsneOPxP67jU8qim2rN9Q3e'
    'jJqPNNH1h7zQ9S3j+xPZSUsH1rSxsXFLGRrExmMxxi6V0QindLCUljZ29JUN75sVfijrtLG27q1wf+4K98MVnvPlSWXt+6XlDRe/'
    'X1rfYPGDjw9Li9/3F/dxdfH97xhs3cIGZR7eUgaL/2T+4vttPaSZCAoIiwiyU6miZ1QfGYRBl/uDNbWod7odb1hhmh8TsFXbpXt3'
    'RhRyEwyYhNOHtLmDO+CtDthE2l14nDc25DAn4UGmjX289gjAYhcnCbdeKILSAiYlAKgrVOoMkCAIqdyGbnZlcT0LZAnH0el0+Diw'
    'FFwXiKZuw3Jool69KkdDpKfZjvhmzT317R+3dpZYfdvXOBaNPyKSxh/j0WQT9O0WPw0Lftjhh2N5WOKHf8wyeiRKtc/BcUoGyCCr'
    'eLhwpPwoOl3/Cv3x5/d74C3URSDvnySjOO+AkqQhCwOTs8vAORFNk2mGUFV0JYyG8CF4vApbRC9i0ac7N5cxWfVCDeClsWkyZCev'
    'HOHSvVans7Gxn/m6dd6d7tA/vKRdjou4vQQiMJmeJfBCkJVuMgVOxXbw79R3R6BNi/k+ghl7GwGgxZBwm0PyaB8T9DH5OIVNEZu7'
    '78prsX0/757FQ/hF8Lcb5J4VaTSxAGiLu5baNHYzlok/ilEySGPf8vJK0ek0Vc8h7xTCUJ4W/ROvQ1PuXJYGSHz3iuIZxbgDT3vL'
    'LWOS0zeDN6Nj9qppG6rgKxskE0F/0+Ep3Kh6XBpRU87K+EKJq90aHS39nHTVImiQ5sX+9tLaEv96Zn+9tb8+4dfOV72/l9HapEsj'
    'gaSkzz4o/YubJZos/7zEmqMEwffHaZQO8HZM3zHG7SUF9IjfScH++7MfpvHkJO1zMG3am624e+y9ectKqXH2nL1Nn+aTpF9sL62j'
    '+mptfX+stimvVSC/aDZNrf/NgtOgS2ZOlRpfLO1s0a/uBM3ix/iMJoaR44EGpDNfM9NWR10M2ZRAeczAr+4PHO97w3TyKh0OMXb8'
    'jqZdjuqIBmm3ub24S6QgwgLhp3HxQMPeh9WgsXIv+UTW/OJoOsJfQgDRBQ/+Ev9yH5CSzNvsVVd1Ms2LH5JsFOHH9tKUhrKE9/HZ'
    '21wHZYroqKTzVbOa/thWgw3b8Z5l4wWCGY1YwHYoxVNrmqw4dSeUrsuP0zrkQv96yMKd85pDXsUhvccPlVkTr68dZjuf8EXLluvN'
    'uCDUT99KLpl62UBRGE+fS0KYtZafmCYtXo5mmMp5OzrhLAY/8r+vWx5nyEmM+Ev/0ujMORl3E2+j7yOkSThXWSsV2dEWrqSqV76P'
    'YPv4SBVoqpvSIF5AmmHNAySbhSprQ2NZWKMwEmtz2IqxWLiqRBzOBWIuayXhkjgOEQM0nCn8Ilgg3up49uRonV2UsBa9CqIV1zYj'
    'BKMnz9aAnubYGHhpOWSh4f/UQUJW+kOrvf5k4wkTuOsP/rT+2HmQxwjLTvU30jHx3uudR+nYH4uIlbdrVDUAOvpM9xayXuFQQcX3'
    'hitYwZC7xgK0rmDdNMDWVM+9Vtv48AUJdzxnPnaKgkAWP9DwL5ME3lLmSGBUuMAhKj3vskMdIdwN4AJr3/O1bDwAMoSFhtgKWXjY'
    '3Kmk8be464juiip4wfXNGda64vmg3jpqWhUYgL0xay5yOxrSg8dryAZmZfPqPvBEWfplFDDZVmB7q32oLoZLs4xqPCMUDOa7Q1eF'
    '7ZPtX+El+ue1jcdm3OdELdlEeU8fYpzH6Ti/hzMiTuMqrv3n//Z/iNzNOIWXJbGQkKhR/vvZyJmuuVKfmIYQg0nPSdxSFpDZcqjF'
    'QKTLaiLpxRATTEZwOzdOJjRFDAxvs4nY/iDDqVh6cI8b1LI3XsPBBO9EyeDygUe2DyjRIPRL2JdJ8yooAHDgYeCIJEaVImduYVOW'
    'LxsPL6MiPqXyH9//sPpfPr78gbMD0cioqQKxXyWbMQSwDpugB6K8cmWOYI/Vqkv1xI46fpqn+2MjQg8Fx372xzauAM79GIrgTVWx'
    '9Ia12OoWsBaV3l5qHvy0dLjcWlo9boWWLWaoiO3AfrbzzA3TUcm1l96oXy/9a8pKJAvjp+vcdD2Hw6r5C86DWLes/uSwyhegFTXD'
    'w8A8/BIWI2SzWy7ICEjzrlixlzdOXmwWepetWO7krev56tIsxzFBUjzknEiBx677JrmOnF1M1WU38JEVF1nqR0cO51cTU8F3ft3U'
    'deOFKRvD2K0l9hYLA3aVEXvX0hMiw1Pq47xbngwrSsqTsNyA0bHR6QK/QizjhM5ECvmtBoTh08m/+DQJWcw5b9JpkrvzMv3I0YlC'
    'N4ILz4lAsuH12X3sQjQaRJi9yuDATRdK3k+J+KblzLNhnC/Rq5On47z0qp97z6s7Qcs9r9le6VvqfUtL33LvGySop0mpADChV6af'
    'DZFlS5jKtUePHzxfLw8Fd49X44SWfMjLrrUuk+EwOy/XmnH42XJ3M1MJjPwwKVeCRTBXy2cTrYWbGpjtKfU5dtyvlKVzRX8kFBhf'
    '81QvmeozExUBPXGh9MiUKd4Lpmrx25EeBjn3i4uu5wQG0sUQOYAkXHtt43XFYb7FJltvXGe6Ah/l1+oFu7H6IGKmPWcgDV2W/jYa'
    'qq8Sdd0qWeD+hzsi/Ye6InmilFwUEgOcyKO2BIBolc2CQ2+dW/117uax47k4+MaMix13Nr1azojTQCWLWD5Om0e0vN8mFPJGFNxv'
    'DmN+q5/QHJPN05QJWN9KM7SMvItzEPaxiZaAvjudDm1kzxhGmD11rd7ZX6im2fTuzX5e2NDs7g39Fmekmp7y39DT53CZP39c2PJB'
    'yY/k8O49wZ1lYdtA8XdvTh2r5jeHa/Huzfm+Og0jyOux6AgPjfk1nzaCA3lCB2TKKdmnXRHLKdvQrHevanHomJrxS2qgcPx8em0P'
    '/vmt92qqYhyhVw0JhFyYtV5NFayTjuwsPSENEUFMMIEV7jC1hLEbll44ejD0lhvES2IP//xo45HOiZ4eP3iEWHGPH/0JvH6rDgH5'
    'TkreWh2VN/Ym1H+qEWxJA/qR/ePh6lQWS7E8yoi6K/IpK+Pmur44qs4napBMSveKsjiz0ZvBXP8kx/Exg75OKzg8G/q5HZ/w7Wzt'
    'D6WbzbtdXQvcrH6Do9X/LAco62n4sckwwB7hV3Q4VCqw4okkmlg2mAFWtRYITEcETMxSTpaOd2lPPvKJ58W29B2ebmyJNwP3hR9F'
    'LGtqf/XG+a95VOksjRU673BgaXonKDfeVAyMoB1rYPFOflUhwwuPIyij2JHKegmte2f8NkelNh34Vskmuux1tO5caxZ4dRltLIFB'
    'ISbpSCaLrpoFkgWvtWr6sTHGjoZZNm02HfDwGq3yWGBbKWyaXAf/lpd4BnrMf91eesg/hN5aY3YKrMz20rNX+M9xFlagyo3ymjcK'
    'zqXeQLf4Kxlm8WvK6boQz4mtlV+7n39tiJcbew1JW5ZmbPwb4jck1k2qUYMUcBiK3nBH/gjI048faeDnrGrA8nzPK3CD2UCOur00'
    'uIhZJMkMyK5p5A3LU7kaPlTKK7b8ag/Fsqn5TBaBWtTlEKLUfZBib+NLjNq0epReJAM5jPTxOfF772KeAA+LR/JkrTwI3OTKJtZ/'
    'Xw1bWzULUzPsH6bpgMaMp2P6+Twb+svGjJ6xTGYQMrPiel9rsHHBSbIB5DUu2YlG6O5IKDLGmsF9wVwP026Vc8ECvaaqOEqVfIYC'
    'gDHLWbiIwGO0CHlwc4SjHXBK72nt3eErXi0icAdRnQHRl7E851zprag3TeJTn9jg8SzDCLDKLZ0w4qnMKCjJk1BarOgztPQV0Ptl'
    'OB/XAPlYU4uZbd4DvnN4P9B1s7EuCzlO7N3Ayc89TIBwxXiEznB76dUG/gNekDYYRPoBvAnM6RUX+KMiniJ1eOU4HWoE95+ZDozq'
    'HsP+pFGnWYBeQSzTpVefqL0Jd3xTtmGLN04e2PLyzot7U3vQtOzEPPoErEdCFyC8+ADI6hZTi6lecwRWrY/XDbMXPDZZT4+xrd6U'
    'dv6EBhu80OymMn/Baq5W68DZlLhOMEFJaq5XxkzbTK5ZB3MuS5v14PGaoYC3o+AOKt0YMe4gqSXLMXk28PFeza20vuFdS088YHz6'
    'GP/pdnA7jcChyCrSWKNjsX1JdcbYPtSVlWxLNBjIjv7YpVVWehvTYX+WVlDbp1vbFY/XeT6vJiACdSrHhSu27WpdOeZdT4pwC/Wu'
    'r7/B+fV3cH8t8Ve3EsnUli8pMlFuQifaO4pzSo61tXKaWpGMJxxwi94PUNTtaz+XZ13oTOuAU+LM1HSNc+Z5z15xx4vEQsraokU7'
    'r1IjFnCrfISKVL+7shfeg3Ywl91og0bwgOPfoVlOLC3Z3lnZzErem68tdteh1ZSBzGV/FzjwYuDGNdRsgc8wzHXAnbu8t/niVvw+'
    'YQ+bSjTAVBFVWYZik775gsurQFBzJynmsCTFrFK8Aa8YYJ5vva0FZ91lb+odi32Gbm3RGfDkUO5qMihfeIR6pP/Yw/nrdayIh/PL'
    's1ngmYyBqF+yspGbtVKZEvhVeNUSzpnDulY9lc1y3QRq5PzDkbGBuF92wWL/t5INyD1JsmG1HGXHOqtjqZqFWBWL527oRTl80vJV'
    'LRzZjcD4noQxurW/tbYXNs81g8MAOx7CF3UOxuuRC9DnGTAEa1JyKeNFCWyv6iieJ2J78i8b0DiR2T3HQnGXSsqlzJoFer9Hf8Z/'
    'CqeG4qvHBM4xLgoQwZzOvrUbi3Dqfe5cx54kEISMZhcU6uY3eRXiBmYDn2avVXHlC/xiDebmvsx13NjXQJahQ2vF9Nn6UD8dcuLg'
    'OBJdqjP+gN8d3SE5fKGjyZRDgp9zcBoOtc3mY0fIBsAGNxPYh3mBwtUAp1OiLybjY887TMz0woRGJm7zlUSO7wL8RBbixerumviJ'
    'PJQuXbI3rVYn9qzrWxXSZlBxsKGuOj0ubqzLEBlacjtGJ9lwkKtB1AWddNi+2Bbtkqth2ARO5g0JhO3E34MzCMGsQT28jPw3G2DT'
    'Hv3pwfojGOw/frgGj455nNvGwzWRZfzStxcXrPimHoPiMK0Zn2e8B8u9ZYMk5EGxqAW0aK5TZtFyTQbBAjjIA8BOKaF1hrzakAhB'
    'uQ0uZxMTybdAKttgs/Sv8yWzZVwMPFwnqV2vFdF+ywp5xuhqBsPytF1CESYDEHXXWVuSMHQ0ze2lz/uvVoj9QuqnQTzMxgnsFPKl'
    '3Z17sBI3zXCSAmGd4Y1ArLO8meLNJ//N+eQbbKlDv4UX8tG0GH9Dg3B5MPXpDPxL5t0gadheAH9A+yHAtkoJjvd+FZHC+vqf15i6'
    'OaHfj588eCIbPTl+FwOtFxkty/rDhyzcm0oCB/MoBJN7ltvLPMlp31760xozyUdEbniPx7PCigEAQ2ZoqzpotojWTfStko8yyQBd'
    'Z4sTwx039U1x3JskzouneRoHL9k8Rx9VmqxyeDHi+NdgUBupQOCOwKem4Mn1LtXHHWu8gpnypv1qztvGhuxN/uvzvPxuGDNO43fJ'
    'eOWHZ/4lvFruYVJ+mkewYFdTTGvj8UPz8Gk2TJSYV7pX+/BbXQ3naNfDSq4mVklErwZSTmlrLvhmsL30HlA+5AVjVxKdn77mef/j'
    'FZ8EBSJUvK0v2zrf55XG5S23jRjbgw/jum7HsIFbOJz5y6oXzqotoYSS2+hHNRst77wd/W2TNbdIZb4mgv/67zlnZCN7DyukcAEk'
    'V9X20oMNhqzAKJsKKvX21t1F9QvVq9K3668ePCEIXQ3X8UHNOj74XdZxY+46bvwnriPh+6USf1G7jOt3XcaNV48e/vlxeRk3Htfg'
    'nce/xzI+mLuMD/4Tl3H9sb+Mj+cu48Zdl/HhGv6rLOPDmmV8+C8tY6htL68lvkYlZfyCBb0L7jKz6osZ8Swe7kmR8CYwszA/c/8K'
    '5/RLrKT957//dzB8//y//gf/+T//v4bnEHA0kigLjUHST2mQrM6FcdTbBKSDffyUjeKxX1HLvxVvh+3I81iCaxF49m70Z4gsmz8b'
    'sRqoYaGBQQqzeYJc1Ox9EpwjpndfjQrPUpVGepBG/xY9OFQymdrY98Dz36g5CDRuOvbzf7HMBqimJX/RQ1GAunyknocH63/gSMg0'
    'yIPHa6V7mJovy+2MyuQ/Z0nE36R2Kb674u2vLNf/lPWwbjD/IqXn2qkl9uIe0kv3i/czSBe9pzfsX4kinLmDIZa1FAYZXhJlOniH'
    'b7x1aiiATWQRiddUIJ9Z2OH6b+0wOE8L+x1zf2O/n6Dz8rU+9ur7XjUQeacDA4RBqwSFg5v5La/ziH8DeH+gDZ9CtFIP5t7n4Cb1'
    'avqgdWNn5d7p/Br6SQDFZzamcia/HQA/+Z7tpbR8C/hGQtyn8OqoesfT/P02Iyz89M2AFTT5UrTPN5Kyz6u5ecuZcbeX5BmOZVir'
    'unZox8qN2IVx7QQ+aryt4i8O4BjJDlYapzIddiouNc/uK65pbmgVhY1Ls7+HGlLLBdys7WhY25E1H3WdOc1KR6Lsm0/vsgHVfHlB'
    'l9mY7+AQkIJdDVjgVHjTA4Ys8ZxH2i/VJ/2MEeWHWLWGyRL67bDFjX0jTPVlQCuc1J1gSrnBCFMey0AA+0uRjlyW0k/nfjYelHpZ'
    '0R46AcAuK7TV9IAv8zuYX28CWAzqWR+oOTXg/1VbhT9QHYtMiCYr3rNTPQuQVq3v1+LB1qyGBLqw9cthNDr2C+RKZpXmjsM7ur/r'
    'KKTdW7sPT/zvOgLb9KJBcLiHbJIT4E6T3z4GA5moveI800yPq3yUdr7SNRQe3J9xCFYB0PnvcGD/sy6D9TLqC2OuOPxXhfA518KG'
    'afFfGe3qKClirOFqaRvcgKrbjN0podvKLlVq/Q571Z900dpHO0ilH/uT37wI86ctTQ6cKHkymw5FcNxfTcTNNF9d76yvurJ0JY3y'
    '2gr8xZa8yNM5CYDXV//27u0eD34lHWPyfcjaBv0uK9mc+s8lgsOlZ7+jJHvCZtOdMCs0FzKftnSs8iIZRDQiYxqnX3588PzF/iso'
    'HF1gvk6Rvdn7oG51LU0wgJAIf27d/Fd0EDRK0FHZqRoIqQC6hRCrjait4rCurWCcCOuKB1jS1nAsSG0lwTH+4EJ8wzQo1zws6VUl'
    'FR8IppaGvvIC9pjmhaCC6cOo4+K2denJi+Wj5gelsIuN3+mGk8Dq9Vl5P2gs9DskyrWyB03nrVIgYm5NcuUg1QTS29gQ6giHxYm8'
    'Wd1qg2OhGTx8TPtezmNjxGAjfvkB222Yr27kB2iHqQE7d440hjFb/fAbDl5swqFXctJ7OYWxSdRmG//MSyr8u6+XSz8cxJznBXNa'
    'czh1p/0TzZ4YZOo1uTfz2fQsPUtsEORK1GMCXAl7LE1+S7Zjq4v2HGlrNkriKHs75RVH/OhSM7JBdRvOofcr7dgNNQ25ZMs23fJz'
    'SbWMVMlYkGTuclhDWz/Y+K2rw/lTfbAs969wMj/lswlx/s2Jn7V3k/zZQilgVnv/MOFrO8hky/F+5wGkB3sYo3c8P2XnVOgkHQw4'
    'ELb5Ajdr/z3y314EOXU5HvG7ZDzTUZTxp0VfVS+gDr2fNVotwpW2A1go1Zm3LGjmIJ6m8cpJnE+yyWxyiAZ7CMLgOQpxCUKIdJ6S'
    'AcSnbOnRCLMDF9kxAQ9PpVdwkGgbvgYDRRBl/Fa6IRL/D0lXL0GOiiIbe3HoxojzRC11IK7XoBZ7aW8oyQMI1Yv0DQV1/psmvrOs'
    'Jx69r1h+rWZSWOhjK8qThJhnFO7yVYRaqVjiYQSLV0OJAdMYr4pd73gweHnGgeTplCGLW2NCjDpNmpEwh6Tc0awA9+FJAkKzw5PI'
    'i92ObvIKMhtiY/zZMca+p5F05H9qL7RKd+j0NBohBpH30UaK3n/98t3Ln/f2P3xCrOhGzkTSimZE77KJT8OLdkyz38e7ZoE85yPE'
    'YJsqqAnM0j3MBfASS2Ynb37o7vGVTq11Cr80pm6abWlIlmHWj4d7BKHgiqgGo1dv2GxK5bDDjR7GHg+DDhzblgLNwuidJm0MKLEu'
    'DYkMITfgKMs0EVRQnylJPccn2Sgpvy83t3eeYiAcvAs7gKXn9t0HuyUWdfgN+wOun4lN1YxqL4cK1IjkhVBir+lls2UjRhFJNybU'
    'mBMeQPwNSZSNFpmYGg8km+DNPQ6+8w4kWLPRnEyTI+JEVlghtcLsA90pGHeLBlIF5D5HJLQwrFZ2oCDgp4BYNpu6neZdsK3H1W0t'
    '7ynPlyu3HBQmHROgatfsgGeQxpjJLIQ3+/yShj2KZmMiHfPoMps1zjisFgwWibO6V3OYUA35HxgddKUVRpwJpxY+5RQmeMs32VDV'
    'j0UWlhRjptI59BPHJ8JdeiQT1YUpZXRfVhGOuDZv/IF+PLQx3K6i03Q84CUYnyIXQ++Xbk15OKyKSUU3evvm/cufX7x89fTz2/09'
    'LudHt+K4fZwg1Hb/HmPySXHO0nM/zT9lWdHMW+xYoMMopgkn7Wbz8VzHk3d4ka6v2eVg3khQlf0SGHhskFq2XN6X2EFjFqv+89//'
    'n++uvPT243Jue8eYPVhr3fzz3//fr5shCYCN9a5dZ+fp74g5qe4dcIAzwMeVAmecBlprcOrkU/bSEQtd2g41cP7K+2lioX13ZWfU'
    'fN8sOrRCrHIgPpZJ1rrvRdaSNENfGSQJyvxSBdsxtyQ8qhmxEh/heAtjdNwQIoDzaTOEggbjE10L02nB4E5UWv8UgcSkAL3BNDtl'
    'k9opnbrFVAePEBsQEX4/xt1WJlmojZp6QiY0rIFurzNIc5CAA94MNSSkGzTOc6CqjpAlzUaG2/Y+bRcBrqzpAXowVxLkHofIfUO3'
    'lEJn9XuLd7ZnX55ZE0Sz5s+m8bh/4pN8dIszTLDfPp8Nf48+JTkDVWUSpsALmnxIQwYNMpD55d8iO+9txW+Cyx0A1cT82hFTubed'
    'CMbKhcE/gjdGo9T7WjkGftQ4R0l7S63LO+DZRrI9/G5T+A7vDY3IcocBVxKkneRwHXIsGPW0I6ndlcrGseGOA0ILOh5b7UPvFwLL'
    'zmlymUtqSZuZyOtWl09nYadnv2/azD/uUg4vh0xAqnmXXanC2rxd8g5byg7E+ayHCopJQPyaJFneaFt0EdCXzpw1pkUN5ukKb86f'
    'JMz6BQT/Q+DOm+gp5nnQYAkZmJh4SgccP9j/rFEGv1Pe6wX7FkznX8J9aIxwTQ2JBXTruASDHbejMqvgEKP4cfda9mSXsVg7RGB1'
    'bATNLB4x4j9BjGzmC+ZRMFw2UQnr3eU+Jnm5cspoo8HRHS4WRDRMx5NZIeQ6FRQkLy7nUUPG0djkL3qkIycilvfsLgcvAokgwXWL'
    'E+JMdZIN07Qh9BsvwavhApT22xHC5eOqhFh62IneJhA2pEWUjCbFJb6wHVXqs7bQoNExS2IJHs9TL7Hs+pLrNGkAOt4jWojcDF5I'
    'SpdqZZDxKWSK19fxYrnpPUzXnO8ztgQV/OMTmSaM1MBPe2KXsTb6mUlkbcmsjbU1a8V/QVVG2RmvemmydrAyIh4jXchnjLIg0deV'
    'l1i57pMn6+dzoOde8HcrchXpcgiRkP206Q6sn4fKH8b9M0Nrc42wq9vbQ4BngFTTBQfGYlSPNd0ZAfsvo+nkRTaBniA+Zpl20/M1'
    'SnDPaFw0QGTDnKuml2XDzscvnffjSeKKK3+E8bXmD7A3nMFMThy6/Y5aJk+Wzydl2RBenCGCAISy0G4/HSXTTV9OBEneKD8u43ug'
    'Av4IJFaU6Fa+ZlEJnxx1R0NvNrDuapwFv1F0mM2IKLa9o5J9YO6mMIVkin6TCrvaKkP2mpcxIz8H9/kcPDKbUnz68GH/51dv3r5l'
    'L6OPT9++3N9/SVcHZiNlk7zE4PtNsK1IX2xFBIVHPJTtJSm1xPqQlT7bv90siX5ne6kX90+POUZ5V94zSGqhna1VaSq0XSuN6I63'
    'Td+/bcy90dfY6XzL8EQ4V/RNq8Rl7QtoBFd7mb3cVe7Sxr/lJWIy/TjJRgc5ESOHQAgjQqBw7MpbTmBjyWOPgDbs87bjX5v3c7TQ'
    'TPN3MSKgMGYBWibkapwxcVzWvaY5RCbULvWshLghTZJx06tDSzGMJ3lpQNL5/VMEpyEWVWZk63Bo6lL5ugbD85Dvdvr6jeNxvGR5'
    'JDN2to5t5fN4kJW6IMjJ9gqCIi+9Dpf9lFTKTpNq2d8gYO4I0IlgeS5jxjvuKJM+70feYWFUPcl60PjD0TO6yzmd7dGbIibwld97'
    'iLEvhr5UJD0+Nr/3ToAM+SeSQcgv4cHwM306GIAO/I4J19odkR5b8+fxFvN42zk6j3a2oz/prcg1dYS31025oKsoo7Y6COx9jldy'
    'S9piPKOgFNzlw0I8wxr5qIRp5igAzZwzBnAS8U9y9f/z3/8HQ1ak7qp4tsNL99JfSwDPrz8xHi1Dts1G4Ff1hkxf8ZJH/c4OO385'
    'mpw4FahQdhAMg8TMO0R7ncR5ajcpfxUPkvnFj+irLfp0VmTzi8JXaT+VQLhcnBPCekMOSoOud4P4kYX29SUh0Hd3Ssb5cxB5Pjlr'
    'R0djvpMECCtYWkt4iHacnP8G8psd/iX8LyKDO/KGCI+PRNBQJfuVhgxKcBiPT/GYM8W+FvA+cDeWbwXBX9IExkUuTwRIywwppMq7'
    '98m55Sagq3teTIfL/xU08zGIBYTgHrI0NsL1JuolwCbh4oQZNXNBuRlTGSkBTOwX4USl5iMUgv5HiJSDj0/z8uenuS3wHLFM/O9C'
    'M9DO8JdmfwbXZlscN4xfmsrhlflumB2vRMBC2XZeiRy12is+NF1/qhMrdalvbSm9KINecT73VE5tCwLa/WIFPbsxpUV1SFeqPiNI'
    'aDiAuLGV+PbxauHqsR/5uglG5X0USwRwyn4RJk88bWPSoR2AB7oIC9zKGBlvpfLVouqbJfmwP5W3ImIvLQDbe+OT2xVPFugV9wU6'
    'fkl7A7lVUO7dL1XdQpt6wlcLhvsajl9h7JtXVDYkqMpvPr7/wR2XbBIAEMxC/O8vfcOaalP6IWiuprBnbGKKevp6FDTaqarCnyrU'
    'WQG4HpV+qqy0LJH57p1B8+qp0BQL9wfK5OHQ1CD2pcfwkHCmhptKk8Ad+W9vlInbsEUhEb9liEap5tr6RM33svPbgVHKhVAous25'
    'eEQU0DIMUfk5BXOgdRWdHwgTfhX0IdR7pQ+PaqcWeKh621EzuDP0ybRjCUyLDhkE8NYWcZRnWOiNIeOkmEeUhmOiw04UD3JSu14t'
    'zVpb1CtpKdpQGys2cM2xrOtY6UWPkxOqhKgsZKIiGiFB9hnXrKGOF7fK9OXdG62gOZUvBK1WBbY93YLUrjMWgf+ayWMgngB3DOGt'
    '1zNTvZV+mQIdHcOakIly+uY23nyorIHhi4/8ibNF4sEatBXhWnC4GTFdA23v8b3MOkuMixyBMo588BXC+Nb1N8RyeQuCuSsdfsuy'
    'm5Vj8jx42uMEQ5rvR1Kvy19M7s0giRt+d0JPV1etRlrvZNhq2BgdEWXzK5CoSrVEi8/SuSIbxJeNPEI8GWoXrOYmW8SJ9pJti8YR'
    'hB1IR8aGRuOB2KJUqflAgC6dh0StKcjCfTs1ZkJqAcIS0XVcSV1v9X05ABAO5u59gaW5pR/XNjMmd28bvEoNiN02A+GU7t4NM08L'
    '+0HbBA9/ATycJpdiB5ifENHQnyGcRzY9hdJCBO+z3CgwVD7ZubdARqEBhkRs1jbxhkTibh9V/dChk/My7p80EdMLItQqk9YLg+E+'
    '+7y//+E931mjbJYnswnfWnZhlIwsSyV7HchhwVvQxAHrnxj9f+hxIKyplpoI00akObXPxDe1DdPoSw6o1Gp1MqnQzM+Oq7oezS8W'
    'jwk1udeQJ2OOxjigH485+lI0hZmt1DE5vNoRJAmtTsR3J53QJIolgNUkziGeKk6m2ez4pJQBTMxTqd0YRjocor84ieHU2JulJs6T'
    'OoJFMI+I8v4UgiSaXdQRozW2K9ePxG2CdWQhOA23UUT5aIZ7GN0QWpDMPzl4bLRIaz8YIuY33TcgmQvXWfP8BLMk7EiARBV6ST+G'
    'XSnbRcQzEGvT6OnHNzBpnCa0ShBvoBceCOuTEHqLVkTlJbIonLx0QOsR55Ip6/OntzknaBO/PGIjLgFyRysYSIzrs+OM9nipP/I2'
    'iYBlLPJJlUS+DF4/y4iJo72GEJ5fvMqmapOl5Y0o3Hv1nM9lwUIQDeXF7z+xUYhadPmjAR1lw77edwO05phS9v2H/Zc/7z/9YY9V'
    'xmKhFh9HKzsSXJK1LzSN2GQ3ZPNQKsEGJ2tRczYGBurqPeCAIueEd1CefuSMDM8+yR/+VxLT8M83/O/Ld/zns3w1Zd785SX/fPHy'
    'rbz6rNU/S5vIjsI/kNeEf3z8xH+p19frXY6jRfC/wZ9eP5A/D/H+Ad4/sr8em1+fpaMP8uetDM4FDuXHpzLudzL+15+0Qw7/yK84'
    'yLj8Qnol+YUUS/LrkxaSP1LwxZu/0hCA9/c+Pn3PgQ1ffXi/jx/3bsxWvfj04aPZqtWfmnJkrlnncJ0eIcHwtfybsfHDNYP0dUE3'
    '3TAukutxZmqcHV/T8Tm5Bua8Zt3ENfyMrqGVv0YkiWuQH9eMUa8F614Ltr0GaUHHJb4+oxOeXcezQZpdSy671nerqa9hqCaz8vUM'
    'nO3v9sxYsMnmuGhoYMckysKDiE5vy4+lIjyOkjxPcT1Iz/zoAefx8BQHB/gC3IIXo9pPugj7XaKAUao23LFkROT4lYvSW1EHHboP'
    '6JoQeVVpkDAgQx3XFIcybrF0sJz8sNrl3BDLFpYkyvLYi5Q/N20j8MJ25BftFNlnGrvmNWpH0xkreS1OOaByh0GeRJTArLHIGgic'
    'VjiYjCCh2fh0jFwptOKCYia4q+JjxTQmOa/XNg/PJBeqpAbg5KO6PHUphUwCWFGdh4Gc79Npgzdcvtulg5MOi6zbWk1l5dj3+5YZ'
    'lWINBoNFziHWboeJKBEg8RoOxtfH6dH1edKbtDZxMh8/bB/EK7+urfx5eXX7S364/J0ZSM3MOCuRTmzepvKNNedk4ODB1o93FYPN'
    '+ViCVOJ3XWxImNsqiKEZ7ghS6OTVlRdj1No9MQG7N6tVpwlzwOMMYgG6K8cZ20dPoXzfnL/SrWpLWKTaMYQ5nYKm9iWHhHt+HRoz'
    'xcIbmxQuSE+SnfPPwypowp6DEd+bcd0uIqfm+loJIs844QIbYGzR17XqvOJ2dFaJclnCNWo1jP950Gvf3hg7Cf7IWT8JkfqGxvTo'
    '28AbjQkxVkJtqkXwfZOLlrW9q1vIBn3N8ZGvT6atLz0LwiZjLa2t/nb2LVsHP+0cfr9z/cdxL59ssqmLy8rMNnVA4u7+cfIizvrL'
    'egBi5GGzE/hHLNTHVMgm30pGNC4pc6dsXaK0XFOdU5wJmvrHcd+0BEoTdtJcVcboEMthgMMUMBZGfi7G6nFlEpDleWqFBIyvLedN'
    'bYs/G6W0Z2gSQb0j3BZbtaiFBfFd3CxrmkoliKGSLqdqYVv2mDJCu6uyRmvOihoLpxIxXDbjM9wlh5hlWjsb15rzN/P4zPCX4DrS'
    'opHDXBovQcuOB3J/sE2SCtM7oW3EeztMT2133zcr8Ey1TPJjGbsaNsCo4L19zTDdLBnuy+O2nTc1GsCRMet3aWJsL4H5v61vtJvK'
    'RHDU45JpwhiJzyu2+Z/VNl9XsNGaY4OeJwkvnbA3oa1y6QTM333Z4XQQTgJVdvG2azd/wbx3/Wl7VezR8nTomHJ9fmubTsNU64fn'
    'USs3AKAsFBDXOlujwpQFKyJFWIyAxHRXoQGUY/TohAVcnydqcOvXjh7CXCHiY/Aj3DjdOSDoNtwxe4pKbnjsWSfap9+S51b9B5DL'
    'DrKDszRHYu2cTwi0fsTiJhPvGPh7J5T73YZ/h92rQq0cr9B8mK8SUPrb5e0rbzL4bJF5mqsHjuwZ56fmFm4AW/yr64m/tV8DDoFs'
    'XLwJxixRDU/6/XDrQzvECliIAamawsO/+0U6LS7dpTBWme3YXJj0HNpI6rcabLjvGQDTRvYSID29MAdgzQeZ6NpZKd/qgkSBMn82'
    'Fp8vou/E2Zp2PmarHfgH8ysPksCkEYx4kFG1Rrg7cIvnWRnTR7BbXI0+GQfGc3YZZnHCbJojAmMswhhjzoghwEpT3MhZ0MT+YtMc'
    '00mmhckbLp6svCSdRY6fubngSnK/0DQuvAnNHhKVgjpsP+bf7yopypucNJTvzKdFc63VAbxk46fjPlE92fS5CpSmzEcEUp1KRQQa'
    'sfe9vahgyZeLqWtg5Tfl9uXUaC2eUA19Ye8w6bpuFu7zwgnMXa0oryMuckdPuA7KfuH48nw0aPZHA/WDiYyiJryc66kqd4BrViRw'
    'ik0ukj6OL0FVU5wRfkyLk+d7e8Z70ToxzqvFQ9Si4rHjrgtzF9RsnSWeBXzxTa8vQYE7dg0aUgJf2RymImbxIaAf09w5b0LFzLMK'
    'yyKQHAjgeSC9W4FDNqqw2+7dv0YEIQB0m/RDO+OCLmWfx2C4piqwOEhanJxkkHguiVUaTte37L5/q1kk97gCdJNHB2LlOxocOtc2'
    'Tr7l2AH1peU3YbMKF3sFItR4JpSjQdmhdqFrXDYuRdTvsZTK399d529ystGOTh60JScMeyK2o8k0cXaBY67jGcChuV3868l2PL4+'
    'YvFkTVwRB66sLs0l/osPa8Ts5TYvmbcFRyw+k9LMHnECBAGtHKdO7R5XedF1gdGYRKqRIBfEAA1ET3vU8tfThdKYDSUcBUpGHCWF'
    'Q9lwYePGzK0aB7HwAMo3jlwpduCwviRemCNKdujHzZJvyM0RISc7Wz2EKJ3slKIwEKYTS6TfiLXU2Fs4lfm7Hjfoaa5wiyVY3dXV'
    'hjnqsylIq8k0G00K5JIYn2KAhCGhGNTOHHGG0iCQUIlzVJjm/IFKk4gr5eRot0nQqDRtsNTEA5F1/eFsQKDU+F/Ey+R++BZdQlkn'
    '7TBd7g1mGU0tQPUYTomhxdqrNU1l+79uxSw8xH4neZ9Hy9nH7cPWarwjQglJlcG0m0XWwqKraRrKh2E5sNNPZRwx/xHQWDB2KSZ7'
    'IGNthPlw4OK2LbIpwCsnhvy69d0VvblRwNQHm3r1AWbhUkAq8q2sBI92Z6uA3gCZyLJz2ANxVEt5t1WogF4+DTjqpvtNxTQJhLbk'
    'DsrXEnZDZsr5gF4MkNYT6jXDpqG8XyBmLtaCHz5bn3xFDR9nhU9hwjZBm2N+yVcJFFPtwrulOIOo5oEOEskiTdXFh6Mm99n200Vz'
    '64syRpf3Fy6Qpc1doMdAM5tOT4EjnrJJMP3Z8pPQGk+BKEWC0uki/YNrnDawdaeSvakVmzZvT8W7K2veKZ5lg5TNdESyineqAoG+'
    'lG+goDXYyQM+n3G09+a0Hd2ls2a5N9jh027zlFjuyEQl9wVWzFnqWn/m8iYRGNhN8j1NvTzFnrfOnFW7w9Bx1DguGIIwRf3fsBe0'
    'xcFa9duRA4YDgPFytH5oZ7+p0Z1qZ0tMqQ+VxdS5Ey6sdPsqhUOijQkarjkd1Kqcc5a11RwuhyhaClF+kyWSHK5z5jKusodiXdIO'
    'KsHuY24FZq3Y1tzYT86RGLHhzPx21NnPCWMWlq7xXdSITdmArXf6xXT4l+QSK5Z0oPSlh3Z0yt+ockj0OVuwqsfiFVUgihLda8xc'
    '9jcI/BfMOMVQRsDKwgdGRHd7je9kfdO+ZLm+qVNVUt1xdInkFsVq7KpXAWMZ/Lyli9O5XVgKr1Tfm+Z+3GON35y7bZgKvVvXuqEq'
    'gqE3slmBlIKMHCRHYsOKAuaDSmhzbwElrvVfj91dGrMSpx6S5g78nMaVnXMMyGbM8bLbUeNn9l3x1Xjtshpv8RQ4OJ4/hZquq+G1'
    '6SLG8E2sOiS32xUbUc4Lf9g6xBNcvY/YEnMBW2I1OxxA0zAQFfIp4Iwqss3SWEDA42/Tt2cwHYkZRYkw45dVylNKQcqPJVrYiQQl'
    'bKk95fwFH0zjY8KfU7PmNV7Rt9TPJlWQK+0MOOR9ZC4kQPhXN+Z+3c5s1kPKPB9vzcOY5cHtjcP7MctTlIPFykcEjttVyKISf9M1'
    'p59/BxU4X22nQ6UOcHqgwyv2MCe86WRHR/Qs9KZ7NrjViAmnJWwTDpNL2TG2wqqLitZPhgc8D7bVClRdi9VkM49Gs7xgo78iiYc+'
    '1a1GeQK2eefet4poXOShGoNPsev0L8bq9kNo9ruIh3oLcK1zc8AJDYVBxjRXJTM1prn2ZItxuCkH3i40y70BO+WMfcf7TCXNNZY/'
    'q7HrnWspf9YKmNazoKOyB5behvY7A0u9rT8v6JvRcdXY336Zb+1vsEdo8j/X4L8CvHkwC6bTcPMFLk2W/BAIf0GoMNDAIZFNlAyO'
    'E4lHAlvgKC02uQzHsBGDVFFwJIOOZ3+59/OPNaEeBcQk/M3mPRF/qYUalV6uDdenrWnsjfOWr25naXZHhrJNbSxHjclFI5BB2o0Q'
    'W+baOAR1ETJvuXpBcwPGzjxCuG5MnKCU4yY0+8N4NJEs5D/y1xWq7rDRxpO1duR9/T5a6/yp1XJzcp3PJtYK9kqlGxhP/azUGQN/'
    'rLNefckZLrLZRBndBYExdUvavo1P3fzZyqcsEuZ5zN2DcLRzi7mhAsZlqPUKDw2wZXOL7SXIT0YTctqPxqQRDhIZkUUBh9sdVnrx'
    '+FL0d0SY2vTGYiMKcz7RdOYnkMziThjFp1KkBz4QtlwSuDhBHONLCW/XuXc7MXKlhHZIP3CSkl1PeghH6ByIuo4EwALdQrb8Tr1g'
    '3fbUOyI6Qa7oLmvi+8icwKb2EsQ2FwzSP8nSflKPQl6/eb+/V4NAuNVSrNjXeNeErYYw4xzqlMvVRT6wQSygguBKm16dfS5VDp9C'
    'pWDHwXELLkQgHr0GFFhfEDAq8t34iWixPVvCBhevP1M847bpq7HOrM9aCTDVPd0badXT2K5I/TpYdZO3EmyOGLrgOgbXni/bcC2a'
    '5vGLhQENPtBb2IrWrbPsE4IQs/Bg6MJXgjqzFgBjRE5FzMfeNJ4SV58n8VTcH0q+I/u+q8QRsWZ54LKRl5tCqNYBVOsTYqCl1+IE'
    'ZgIaqZWZtwHONtsVqOvIgAaAptnahEC7oRZXbTbcjZrGN0yTRre4SmwyhK/A3YwdiVlcJDFyNXKu53gh8Xa9YMDGscIM3ThRcOVc'
    'bc7fxZNqPN5o768/RBNagwldQ8ujIh0l2kmRDllPyRG7tOHdDnoDLzzxWRD9yh9ZS/HfoHKaaCgu/6tlSrrRxDujhNOQPDxU1SK7'
    'BZGc53SNrcLcc42uwwK++qnkUjx4vAaHy4RqDBqH7UieR+l4Rvwxnjce0jNh3Ck//akNp9xL/v2w8+ARouwlySk/r2+gJsH9CT++'
    'GcMksiBoalwSODUOD432CFRjXlLpHYBqaHOQtUNQ0DzAILxktMV54Z1MdGzu/VF80YRPB34fDbNsSrQl38GiCLbyUJ0l1vaXGRvi'
    'n+P4f/3uanwT0T/I/EV/2EAWsaQZNzRusLBfjWXwWbS6zeMw9otC0J0TCGYFDoU5U+e0p8qeIKGmGuAkEDbDo3HCKgSxoWqwj1Ah'
    '4TE8YxkLX8wj+TvLEiEMHB86gLqba31g6MOTca6W4LFshMyA3DmJ8+YpS1yMVkPeIyAj3m963SDUnNz57QhRm9qRiXbUjsQIk6Mf'
    'nD6fTc9gaYbfHKo0FwKEI0efHWuQ30YjTP0gcUjAyHGMkVFKK1ckzf+y9+G9OHTIT7EdT48umzJduhXT5Jzd5yqBsQl0JAygoCP4'
    'Z80m1OyAsxFk9zSrxKuphAhMwv2CsxlMrY7TsRh7joGyol+zjJEkXLriqdyxMZ3tsUOh8FRW17bYJJtQEjaenjIlmfeTsbGfbXO0'
    'x14vu4Bp8bkPyb0OCGwcw8cP1+jjSfjxRD8+tIH5pBvEV+x1LugrGliNNuig8992dMmfLvnTiX7iv1Lf7c/XLfodYXGfZRecpw7n'
    '4hL/nOOfk5sl2AKw1+HTfEJM7SdIO7aXLt6lg7/T/6NRkhRLkWQeYPDYXoIZG7Sesg43W6vUh6gLvavLBxE+aYQ74uEQ92HzG8FP'
    'QyWqOFVhPBcYb5seg9jX8qrGUgHUgkS9+Y1xeKqJC4Io775JuLmFhH1s1ZRQpM5Xs3dt7fELEfTJRxdeUp/9CJMs23r9YW/fmqME'
    '152AhG2b0NIsr1gCyzl2xX6YpuXoU1+3BumZCXmHMiscSHNp5+8+dQBRiRygnI5aos6hYXYn+LxGza3eTkijrtBezy62Vns7oB6q'
    'n0dxn23N6BSjUKsDffGbsSBdwy8QFcIusHmBiAcgRuhcM0cCioSz2sZ87Wurna1Vmlao7PZDRS9YMzNlE6b7VcpWkEItmUVAAC6z'
    'SVqhlAnAUbd228ScJZ6kzcYq/buqX4w3i5yxZjKdmh2/ZaSrxoGK+mU+cFWsLaiFzijJc7jAYhoMqbKeRdxjdDlNeA1LG6jW3z5d'
    'iCXw2qtbz3DanuWDi0FFy1A+T2I0a2b4SqhP5piD4NliWnvPpFtF8FfO/oCQkdZv5KDz/fLuT99d3TRb1wdfDr98OWTfkS9fvvv/'
    'a/u25Tay7Mp3fUWKXR4ALRCiyt0OByWRIalUZXWrJYXIakVZrSkliCSVJohEI0FStMzXjnnww4znwfMP8wF+t/+kvmT2WnufW15A'
    'aiI6oqIEApnnus8++7r2fxvEkXKfypNPxCwZYiEhpK7OTHbB/eeM9fURf2+C3q1xCuwVexT/+GFogvjJ88/LIQc6ZEMjuRkGJyUC'
    'Gaz0Kfgr2KxwWH78GPM2tGihv09UnRIl8ahYLYVwaDbhwdNob+MwGJKME79ZQKwD09X8uTjtYVGK+t4xfcMEhl8Q64u3Wm5CLFEO'
    'utsWGW7O7dnZsERO+itZd0Ja8lETa7NdlUDo26GvSdp9JB//5V8Yx5Cv6WViZ+VD62vtQxpCUJe+5uWjQVSaV5lCdCPLVSyPb2e/'
    'xV1dAKXafisXXA9rnk/dY5/3sr/fifdmqG3KiXJ4fFRq+bIK/3yArY86UXuB7oeuH2VRj2mDDWzucLRCPFnEcNLosT933DaGIWxw'
    'wcmmGgXIS38W3XAuFyPHOnIumKdVNS/yhd9858RxKo46XhA3dxxMby49zMm9itV7/acFPlNy149YgOuPbSpzMOMY2YR66JDHXVoM'
    'thehD7/p4TL09TiORWxAzb9dnaCbz9pcShhQ2nHSstuWawXp7VoN8yBcHVSrdbzmwOZKSlURac5qUCBfb6oYchM3CpoOimfVGUJD'
    'RGi078chSWFMg8ECXqgLUdKERpAjiupiVoYuNIvXqVUIlefuM08oN6pGUbn4aa4Rn9VPcvp0SvpQIy8p3fUUtHTDJaU7oI+7Yhyq'
    'Ablvr8E0qNoZ34JqRzBYfwfXotyx6EzGwiMbaZzFRmxtPt7YbFScGfoAyDuQtUi0x8graRA3uGhjZggvMN6qpO25664XwlxdrXXu'
    'jgYxwkyLDV9cR3jl2X/+R/ZRtVv8fgSJ+toSf/wX7VnxrNEGKw2jDf/FtepP/Bw1zFI18cP84ppyevi9vXqmePMlmDWM6KwQij+S'
    'iZCJdUab0IbZJBb8Ta6M0AWlmkq/la0qwi3T97cF+YW3CArRKzAzWnGBm9rmKEZj5h0M2477EZGdlhAbD4pqB7SfSJdnVVORIu3x'
    '3jE/Qtqva2iaz05EjSI0hwhnokXJj3s2HddxCjQN43E+t/noH70zOoA9VKhDzXUYsJpZ9e9tSHWMwjT86Y6ZIjzTL0FjEdAH2gyC'
    'kmdISs7piqRvg7Jd1Cw+3/phtz86h1HrvW++8MTtp2Rk5y0dLr5sjPVjuvT8LtIOrqPSFtGBHik7mJwvGIYzbIKDH7EEYnG5JedU'
    '9aZXxeUz+TJsCSypshcR6GoEC94TvaCdMvi9i3H26WqixtJY6wpzkUtiaTdySrJKpyk5jtnfRdAAVdi8KtYTpzqwohdNw9ACpTMt'
    'CAlgKhlTeQQTwRiKHW3G0lQFm8/iCvqg2aWpIVKl6zNND6GcmKYgYtoUPjE3/FF8FXWoubqwAYvdqS3W3LBL7vK/xSIyYJIee6Vv'
    'f+IGp+ErQRr6mHCF7uMq1JElRwC0b3RmzACOv2192vOEmB2sq6XpAZoNXdYt1vA5ZgjGjxJc+qxPDUvtBNO9l+mG7HLLvvnCNUH6'
    'QTJlXDEeLv94XnzengKMbRc0sbW3qBaF4416Nt3E3Xl6Mpt935iJnahMfrIxiNyc8rr2EPaU9osZFZXECQL/MuQ+LF19PrVpNYia'
    'irL5PYLfk3E4MFpi8mqynLi1jXClTw8rg/AOOE0zZIdiveQZUeTOhgOaWlzqhzNUfpLb32VxakyEjIzXijNHczT51f6fFsOfzD6C'
    '1M9yTfu0XvTA/p2MEi0YEzqszlexShENNM17n1f5zIFbswSEFok4XyG0LBX2oOg2DArF5/xsKWKuLvogxqJ+snC/uhnvms7GcXsR'
    'CNBJNMQDXS5TFfgIYTGXpauA2jACYn6Ib6LaxOvTz7N9fSP1hBvi9YkUOXvz6sQRG6sOCw+GQgllADGevV+jJku0qCsTF1dWfXul'
    'N36HSchWLrbuaAplY/5Kxha8g8ZQ1YeYi1+udSmCYb9r6OGVWCFbTbTizlzToYNVa/WwUQIzrht809AbHPvWIawqJXXGsb6PxKgP'
    'IaxSv9Dg1XYMYLRn+qDfsF3rywdyWdeiGHKKmJRCEzdn6D1bD729oj3aX0WiwyBSaiNI+VRD2TBnDDeaMZ4epaeBLg9fi4p0xoCR'
    'G7ehN+j864dkscWNkHCNMfZfZv0B0jdNyEKKe66021PY2Ubqiu7lmMjORunxSwy995PXYgo7i6gLj+igI9m0h3D8Han1G3s7llm7'
    'XmNA1UgyBLyv5T+E05w853DHXXhe92M3FgrAQ5tqBbAob3WeYC/zXjgUuWFV5vMYkV2LLd6Egd1R0nWUwS/E191PcXwgjdV6OzXH'
    'ibF5kOt/KObLGwcanEXRk+6WSabdDcv9tSjccZNG/V1LdJPp/e7GBx625OcI+xsTS5bF3HLygLkBvoLD9PrRxhszXjYmtli9r65w'
    'RlcBmP44V44zi/8252d66TUdepYllQoT153JIvcHmiSjJ5xoQdpaHwe8yXnYm5ZirDbu7XHSG13ulcqYRTYt6BWXSy6SFdT18DjR'
    'tbIWs3c5E/Js4wrid807qG9pnqBC5Hcgiw2D7lqi/tHtR3vUl6vUyIvnUKrBpgspAHPAc/Ma3sk/5MjBK7TOYgBJhgLMKLRs+Mu/'
    '/h/qJCjDgtRGEdqX+Uxk+JqYtaPIcUM4YWlRfeaJRgrktqIj9+BwVRTv+FvIFYBQNyZEw/c0ak8O/uH1u5+B1jC2Q5EfHRVLJiPs'
    'KrDbIs5a9LePwoyOs1+JVD6fyb8R6i2Am0IP3794efj87c9vn//u+bNDYVLtn548e/b8zeHY22J8ZqswGaCj2wyZq0mcTOFwCqdj'
    'SJmwxVayOL+HfhJ933TgAU1sY8j/e2rViImK6lRGgBCkzrmrTeg+Jd37nx/Gb0TN8b20DGbydvyo87A2Ifk3lTZV2jqdUppkbcXU'
    'IA9a/g6MPDttBgv88q//d+ADdQoQsMMnkjORDqNe3m4cBEQE5tkyjSCN/vSOMhBVNZ/DC804nv/8jwzxv1kotYefDGxxKZr7p/hR'
    'e7la6UvkX60Xu6onsvr6XGNR0gqKkQ9WTzEOoj4/3II6qjaFrXG2pUdutoU0IIBQ+JwXZZcBXU2x7BDeNmFEWnUuP2xbVe9Q1V55'
    'OauYwmBGvdignIbyM2J76ozsHF68iqBOhUI4ReVdn7KYKytT40/EvlSrxBYQpCAUv0IYYJknIL4GHWq17K1snnohm6BZvZE2vnOF'
    'Ugz1Ad1fnWCA3mGilYgtXOi91SL8kn3ezYavhnMt3M54Kvy1ruTzyMKpkieuoieu+IR6+KyMdF7X5cli6NZNw/YhoiPpg54khFux'
    'nzP5/68ZfTU5vV5+/ogdWIZHrvjIVfKIsTbfuhMkbMVR93w+USLb3zePkX+4HWHkf4rQncLII+QLTUBLu/WO7s6vU0OobqVSCIO0'
    'vCkl2lQnUjfd0Snt+BeEvyKwtNH7rYrcPvh2p0VRjnLay+UwJ+MKs/Oo2q1bcYee21HX1j3SqmprP7Travth3ErE7clH7Kk425Py'
    'HO2Rle3oFQBvSO2OWgqx6SDdDbPqKFUbjQWlni5OuvJEp/MezXt+ukHzBi1FCvf8tG8ugbPdm596eXNuit6djqLbF6LHlCg+AbC8'
    'fD5nKQvhvudLebvouBxYJmGyvAJ/PlsyJA5LDlA9BsSL8FfkBI4C0xe98cii3WvUZhjMiotBFLs6r6rTmnesdehY+ZM3b37+4/O3'
    'By9ev8It/e3Ot383ebAz+Vb+e/AA6Pd44Mc33z05fP7zj29fWtgfo3Wm1fn6yVJDg216u3F7Y9fXrsv9OcoXL3T6/itbjmJm32Qe'
    'rf7Fq4PDJy9f/nxw+Prt8870tm17ebs6PhYSfti0VcIS+gSjjIzRGvOoptVoBk3bKn8aNLOp1C5vb03c1ok2e7exSsIG4oW9q2gT'
    'F77ipS0XAkRbMQ2+fXvIYVVcUB//TrZzXi1ZRQHbTdX8j/YkUgWar4disyga8yPHnGjizfk4NGLbqddY2wg9qPH0qF3Y5Ch05OOc'
    'v/2tlVkWyn5VXEL3W4pwIsdZxBx/NpDcBXhP6ci7IeSfcxQIgs+qoHyCAHtEyy8qnOmF3kWizzR2fyHdrGxlWgSwya6uM7vPaQxC'
    'BsFqkl/k5ZzpMPvyl9ueXY9A2bZ4Hxcw4jaI4142sHcn/1RXi/31Y+xbSNGAXHAkR1yUpIEQOYGcBnbHh4Rbh1/GNlAHJtpvGzFA'
    'vmMy3JdvAtRdY7niXTvLF+dOUmua8y/85NIFDirJhaIQa1tPc+RhNCqYu/bVrL31U3U+QLbfwsGFgjxsOlujNEa84/VnLhGQU0iY'
    'XPZkVaifbQGL3v5WExeyOVCf06YtEPygFff8hMHAbv9FVWk4prRwzOxq4s972prpdcmxvUgf/aFqdQvCBQfQ4bq0lQEMGGB0AKnu'
    'aCMqz5sEmZ+7SXcGmTefcDecZ0kYb4uEVucLI6BYyL8wLWFDe+PspEqewtAffm2MfRzTHhRNQlOwhpFej1o8yARCYFEX8+PdbOZW'
    'MQKsBdM5551LeNuQp5vUP5jOq6k/EsPNx74RnH70aYWyRvUEcbn7F2QDF32nfzRBT6GyREBb6cNuygf+YYVMkWdlIPaYaibyN0OL'
    'n6Lt9+jhAwaAdNTduCAKa8BJM36dHm+ezQAPWx6+G8RNx8pRMgojvXZmQgxuU0eqDDOiw71fa9KOydJR4eHJwA3lpGoL8lkL/DFw'
    'loQ8dA49vKUdwS59RYfQ9XbTYvAgCdm7XACTWLqvKhrwBrd2697U96GfZDYrZ4s/yQLAICHL15iMAVDFjkg5dT9FuQzghafF0qMp'
    'u5SLXMMfTiqCMhNfX7MvNLKHNd7wPLI+gGWI/MjJLZbtrT4bLVwXlN3f7xh0nZkl3XWWia50VtbFcNWo2LbSTKskWb/7rh/cH/Te'
    '3+rFm1SnGpVu9zdmgPvbRwl/HIiufz34CCwQOaqnzZR+Bk4cUaETxRZkOQzFtD3/jOsNO77sfCj60Mt83VWF9Ev//WAJE1Ht7CBS'
    '3uQni+ULp0jGxqK2yOlTJxZVEyaX39y925kbnegNTQneDIyfCHHpZdmglzBkw3/vlRN+vajiaCZ7IRGl0a7H9GaKfOPpTqL13dVX'
    'ctGcqbz/joBXtQvvHiAqqZ1QQ75HsJ9MeP45D5PLZqKnpURQ2SmDeTLNTMWJInuMjYNp9rY07Nw0Z5OBxe5tGoG0Wf/1BuBpO1rI'
    'p+u0CjsFkQDSEa7pJscs3bbpUe7Yakfm3TqQCzHauGnYsBeuwbui8HxGDjgCcLoSo7w5N2wkJbuvbCHdiUEiN6e3QbjXSqeNb4no'
    '0QqgiX29NphXVddB34C0kJzGcROt4LprlbMO88na3N6dRvR1sdyeXm3jX+EXdQ2hHMb05Qpoj0c+BmyiRS/5XF6f6hUEzbJScQ9R'
    'jsgePfm0VqXTqhGuqnmNrnhJFE6+kJalCRUgRQk4Rs0B0ntdFLVDNphp+ZhsWJp6Usc5VNoQg/wWap3J0c+x3ESKU1mH6poFi8ZM'
    'hEgKbHFOB0HF6uayLDhv0yKrT0siqCDKDTXrjouCliYeQemfIsWE5pv1+bpR9fHwx8NeY4tb/xQNRIZUXJCuztf7E/wNWxy+C2l1'
    '3z1/+fPvn/8Ec3QNp8++uoKoumjJe9f/eemy7z4+mrooy/OScfOIMUXso2WM5Gc8qOZD1IwyLeQERu1UBrpc9eMENZxgS56wtpKJ'
    '7laa3UdPnpazesg0ieHo/c4HPOsSdNilIjfpDhyfr8jOaGkoZkwa1zhpeEwQTohN4J1f5Kt5yUelr0sIOLZPYyaMK3JwjQLiPqYx'
    'Sv8/Xx8UWv8l8VqEYY6z6Q5yu202/C7YCooF6eexLtrwjEt0piWeaZf6gwuGpBs8tOKST/YeZ9/iFxkerOVws2tRrrJ+W1WsAARg'
    'Syzdor1icStBpeOYbu3iaZaWttE/boweIK5nMTGM3DzluTefqnUltwTMqGUdpfJhmMTAGLxDQr8742Bz7gsADNkX2LwSGWjAzq0H'
    'XOfLT4grH7ZX7lH2t6Ps1RCvK8ruGdZn5MbEnt+3XqMHykpvh2wwbDBTGJNtHiOymIN/yTgdjNFJdc/y1RSh3mX1WdYnGSo3a9q/'
    'WY9kr5KBT5OBS5/vb2iiMQl1w2H66ky5olE2rv587DbYRfBqLV3yQhfK64uBV8baaxiNBlHtC2Vhz98Azei9NPZFQ9mF17wDgvAZ'
    'dfr08hyM9VaXqe0aG/j4aLl3yIRmd+sgSMCuC+PHEYiN01PAg1kwR1i+nua13DKZoUTw7u68lQBf7hJIlnvhikovIoeEiEGQ4XTe'
    'QdXiqGjcPZPMx29X9FqrD1g4EIQyj8Mj55tGqwxZ3+mYQgbPcmvvBep4niLBAhJQ9mAnU5iYOvSDSmkF5y1CH1MGPQzKN1/ORRL7'
    'r38fjK7Hliuu/mfIiaDcIA3po/sIybfgfSv9vq6WHN/H7Hqc7DExrykG+QDvARDe4eqRnzWcpGe/nxMKyaRQp7yq3qlDypFN4ttl'
    'coLptGci/6NS1gtosW4VfUm5ITcPDtlZTmu3rBrsBaPGvv8OWDQAMIjc8eyFaIDeWpVpQHcNYDNdi/KIGy6MCYgoNWUYBZehH//R'
    '6XS2Rx/fo/v4iPaUwW7Y5GcWMhAXbrOYgYm2eIDEpXtxu7ZYipSAGUK6BG6Xawah6TguYCIoyFpn0yujXd3PscHBLIrdoEN2XHgJ'
    'qM/mK4353CmVQI/JjY0m5DElr+uhj3eOgkPugNvicbzSh/nU1gOuClVulJKfao+jaxiuAbbnR4ELDqcQB1gWOKUL1r5hyTxQN45M'
    '9772LWHnhf6ga1HOkKbrHk9XxlDsN62Nn0znssSEgoXRJXHNxmtiAErgXSzJpvB96ZqwiuNJhTU7X6zLeePQM7tFjpLw6iLMCIdp'
    'A8kjk84LhMIpG8kgY/W6ls4q+Rnutzm6BSgB6oRJ71PjnLfdhr9tbsMPoozI3HiB35Iwn7oxg/N+AuP1s9CRlTLEy4UoDnqCsbDy'
    'A1fMP9kgq0DEfld0YZE4vmrvB6gH631ZaWIx+ZY+S+80KFf72rABT93tDqmrfyLMi5qtcvk0ZSCblnXTyCfVmdz0Ija+IN+9xeZQ'
    'vp16ZWB6g0Tb3MA/AKnUsDTQKWRaxCgXcHDDrnDb++jHWk3X3I9f/vI/f/nL//rlL//7l7/8m21MjuBVhM5RHCJAaqhkyuAaXFqB'
    'f1s5xxZvId+h/tGogWp3Tu0vnUl2WGGXNUZfrybcQDgK5iIZ4/fYruOf0kZ3dV8MunkOdEp3qQO4AvUDZfOjW5Su3qaAhMichIqN'
    'cDbLLcqG6iNbP803AuVzj2LK4EW2q5qo7CzvFWgIFsuFhRV2tiqFXlQnQlomVaL3UIDGppF+IBhrTGxssalG4RWyFetHrjL7yNY+'
    'sHpZuNvav/EOXIxapKjatckCKOXYS4dT9+ivpj/yuU6KbFZzbfCMb76Ypn8dsXluvUxOBbgRZKQ64bIUDFv85FUFXmx1JEO6IftB'
    'PPO9f2z0wfKjPBLSx/MEXxLWHbOO4KlFoXJnaEslGdfiqmD2cNnBKwwYiGYOoOcN1MOkJabi77nY7f3QyFEZVm0c4v+LMbCZZBNw'
    '5lYVStrLsQDDtitUHwky5Ha+XvMOW+u5gtk0XNvksfna133FToHd+t2i+pRThOvctdZt6jO616Ue5TPhMRfS0vCJ6FXb+HZE5u1n'
    'g+0iJiP52clcLpNa959xT1qEMzuE6OebUKkpupapO5XkDQPRL3KuBYAWHZ8QdfJoPb+yGqHo8zJfKND2IhJulSDuMeAX48FaQbr2'
    'iqi3spURUW9YkyQcl4nviGA+KlrioO0OJtZRnXoTq9Jo+q9kVvrSV7Mr1xf5k/5hHMp+UR7VOgeH2DRCSvdwIzwAXmQKOhxIPWch'
    'oTKKDHIWPGUoKtxiF4t4RfpfsSZlTIqLIgcpKBAuVVWqwrOZomIz4lv9yN6+F/TcWghAz1PFJO6IElW+dSYGUWFhk29wuXd6ivDa'
    'OHoJ04+UXpmJbB6sALAvM5iPQ6xPIy95Z3em6anTWsdK1T9WSqyzDVQLZ7DzM7DVfC5H1nLGMzjSLqHkucOFDBowJRksDx4UQQXg'
    'PAI6o4L8rkVYPvl0Gxa75vhY0Sv6FuPYnUXk0SKyZ5TN614iqy8VzOLGu05PZE5VQHViE/tto5e5UMfa6mRffqrmhVfqbIluZpY/'
    'lBdFpGzDP5CvTqnPbFPsti6HIeZfVmvk69AnbDrGKzSdZAy73xHrB8iYZgqIjNyFJcnZ1io7zmfKi4TWj9cZi+MgYeKS0EUmpNW+'
    '/rf2KGxTwWPz9c30j+P5Vsdkc6pjQwr1BNLYEslMeihtNe0WcFMSMhLR/xYEhG5Wbfr4nhUw1tRpe0jk+GnF5KPjF+tcth6fDmDV'
    'g8YhP5YnJ/rp4FO+hOx0/H05R7qoPFJdsoG3RV2se+2LdDitZiy3aDqkK06t9TnqLu6/G5PR+Xzv0bzcgx6UDYNE81SvLkcgGH38'
    '8wv7+dF9edc1JR91z5788j/+TaFD+Nc9fAa91Dp3nN8p584pNdugyjLdq7Em3NrhsgR69rT6LBr0fF4uoUpLG7zmCYSohkx9D+4Q'
    'vMZmH92X+UXKCpBCF2TJomhObIC6xjJGkow/RCQXoWWFXe7T+9qXG5fSVZlHPbuJrR8/syaHfsIE9SPG3KKvNwpC3mRAzl/XprZS'
    'dOiYeMoDImH/qnxbaJWGbuXfuC51fwzdw58n+n5gX7poNjqEyMAOq8ipPO+6Z4FW/uhISZ+BMMRHYBBA7RPPy1X0bFuvQMFYNR7r'
    'YNBRn4pyUB2Mo6pAapvEy8q/Js2Bqe1nNKDSrO1ih2+/7eXZSWsLGVnYL6XYz53bgsL03rYuh1oNn/TvGoGOG0lY8e5oy0LS0T5E'
    '9rNRxxIrHBsryZh1HuVUoWqM6V6uxzSWKDRybVVPzexjlDrJ3jHNy8s5pjkeGb6rFaq5hQEnYMCpNGDOEP0GWDuTjFOkVGBRTzP1'
    'nkOyKT4vK95g74THgxz+IJchAvCc5bxvW7UU8msmzHY5LBeGWkeBVctF+bygR+//+96HX+8xN8inBnXcGnLEgtHsMr/qpw9XEfiW'
    '2rRZverUJheThW8wpYz7jipEYyNKQ63KUkNZGeu2SH+AkGPYBYgT8tsZ3DQKCIgdWZ8fIbQAs2tQmnoFjFWzHadcni/QM4n5RC7o'
    'eIeWFeJL1qH0SXtbfG0MlNlUzKsQhnPdcb3bI4zV2tBac/sOkHXH8VMq7d+7l/LzBrWjuXcoyCN/efvzyI5OlYrnaDWWzetkOPCa'
    'zSx8oJTucItWc2hozm8kqkiFyp9YdNtOeYhWj1q/05sUqPVWboDmEdm0DafW7nlEkDJyIRJhMdiTEmqSimLm1DE7gddVVW5DhtHt'
    'GS6bkv0zNfVUk6vVL+bg6hq7p/XF4VG8dObMzVt42rN9Lwk3CYSyZnNjTJTBQ7MSwUhQad15ZCYsAwcJksjjYuknjWPSIA8jBp84'
    'rNxQdo65vri7zEgDeDJYEmSTq7NtlgM7qlYLOkNaZh1R/lJNjhPGbW5c2x3V5KUNpgMD4Ux2xOdXjgI8cus4bnwh2/NNdx5GzUq+'
    '+SSKJNRQ2Wz8zk/IyGMX/sQzlddqC9rXAlGWW53GDtimgS1tnEYcqhKC798DyfZDEnozzhBoxMRUCDsvZvfuhXdc+meS8sz0ORxz'
    'mGp2s5xGmXW1G/kfWGVa2t3fz/B3dv0wyWTO3KY0CV35dcgrT924h7QL293ezaFw+MnUyWMyyi/hZFgSMzLGE80Yck5LENRDR6tJ'
    'fkUzvwuvswQu0U4x72q304fgMuNb2evUI2Kf+SgZuOXWM/7tUbkX8uof3S/3bvIWtEzaagqqY28JhtXH9oykmIKcEBU54ZzFgDQV'
    'HJrEfKI+HX7Uinb8SA1WP3IyHT6nFeWHBWX97tCHKVziPfzw9aJQaEyvRdTg93J9BKjgMXfVBeKYuYyxBwxeQ52eSfYsYkfBBU+e'
    'BCd2fisX9gYTSRlZZFQLNDsv93eSBRojc3cmKXVEBroNs9rEDxU+2YcdbGCA7oluL6FvqilL0jftr7Foq/BLz1Y9oZIc3lRY03kF'
    'Y4FdHyIojyMzj1zLtdMPcC55b8E0LncQMLshVGvkTbp/HISwAuyWO02si0NXYP9G+VupYeC2U7uoYt0iCQFXX1/2HVwZeRZNsuv6'
    'o53KuTNuK3aUNWZlAYu9fjMK+SG8K92bm23SN9hkg1QvO8muAjkyQkFjlEMsg4r01H/WGqfsxAqzm1yJYkZjx4laXHkgP8mDV3Lj'
    'TNvK4iL0/5wVArFO3WY4F4cfBbvRsHK+3MQ6bV5x3AVr8NRm9Ild9aaHRBbKk6qamar853PeX9I5sS5uNvZhrXZ52tpOOf7GJJK2'
    'NfAfAfNCvkT8l/gsln0GvG+++HhmmfEbIMY4bQioMWPnmlPoGFehpgM+hqHQ8uBBeNAhz1BCZeTCOHj6Wg3glcG1DwNQ32L/vtv5'
    'LtcNRXLHmXoQLbBygY2qD7hIiuCL8zvSTQSGEbKIXJU+BjAKXdDFgbs1tGpot72Mmc9AaJpM9PN1t5IYbT3mqvSAFZr1KKYs2JFP'
    '66Eiq2T3rTP5uJ09GAkr35ns/BY3MZ/8dLWs1kPDbdl2z34eZ4bT4r+6wqu/2Rm57oNq2xnAGNdYiWlR5AcWfNgk69EJykvWh0pq'
    'XWHkHxAYQkjoR8P9DbjhezxwCyQsOeGJNjSfxGdOBofW3h9duIEk3pm3NHfN5HGSoIb0a+IfuoNAQtkSf3Tf2Int5y7EK82sbioa'
    '+YWy8X7j61SeYfiDYQt6Kyx/eFL3sgAGsckjjaN04I6Ssr0kGIk+9w5gcscCk+wpWlMsMBYMgEAzLqUhWupvvlh2uHMt6NC0nmVH'
    '/KwSBZgvYm3mafkp5TW+KJbVAfpUnCFe0/bOyVZEGKEpTSNygfGebjuzQZkPUdbqOwz5oFENrjQhNFez44wlpRCQgWQlGiLLNToH'
    'MV8od1FQd2El+bFzCF13E+BPDAZBS3QVQyjJHaU3g7KTRDZvVL7FFVSTGpo0+Jw2zZY0oV/fXpjQ5xMbUlGoMuXGSl3XApZd8k6H'
    'y4gk+ObVD878a/ajtWFt/Oa//j3TUpwgP7Xvr+iVDMcIERRqUlyjjLFFAMTXUuoaksFJn2bDVaWudlZel8IuCh7yKtDrD1UF6+V3'
    '1REi3KrROLIDryyrX2OhOQpSsIq5mlMFVcAZlzvcSWm4M4AB1OdY+uhTg6OQS3PJGsMKvnalaG/1urgFMdBPXYRNbscE0c9bzYrN'
    '7MmwW3sdiaSOHgDX+nxBCeOsQqqE5wUaD4DwmmJ9KQO2XWZiphvUJIPPrTThw6IdVARQtUvugONbeWHXnEBz+g74AxyoLtZbfRNk'
    'SGCQQe+iXjjkBI2lYmyTlrTuovRGQGs+m4Wgp3E7ONl+rzUyObBCFV2hxjKqAskd4IjlossDaheDr0bdYsFq41MuTP+MqdSunrWH'
    '9OxvvTsxwkXhr5P0FV4jXT5VF8nCe6WPEUYBBQyfQ6QLL6cAsk+LsF4n82rNGIHjIqdfySsmMZnAOKd0DpL4ECcVxiDHtyoicHuM'
    'EL1Uwl/BICc655uClRgjPBGtSzud54tTBcKdK4JAQBhs4QqCjFnElph1D2OE3pDhhHWSGSKNcLiTIuLFP5VJEec1a/D6/Kb3pcdK'
    'ZO4lQpdWI5mg3NYOtEB+sO+ZV8V8T5F0x2yMFtfFLnf1oFjDcqln13C5+KKCBSmS4YYcX584Os4OWKRXxt5MvGdKvPQLpjAbhaxG'
    'Lgi/x8bvTzDqCOno+Ayj/qTau6pbAdCUta99mbA1ALt6sGzkN9aLbeXes2uaioVVOrIDZSwZ2gl5BpshZ67M7mUPrJqY3wZn5RH9'
    '4Poj6u+xPZ+Vi5JTQ/fXyNfg82NSeAVaAM3i9zgbPtjZyX6dlaJ+DLv6GbHU/d8MomYOwU67p0ZOGz+qAAQxXKossQ7bgCiip79D'
    'WepRGyrFDx8AWeHnklfPTvTE888iGzT6i5f8Y1KQRk7R4y1jKVbkyv4KFWZaz6NM0l5nGSRfHc0SPTV50Ub2igvxUBFL3hZ/Pi9X'
    'SOJlaq9CBIV06l3Nv68WIvKcL5ARUmuiHU0ZDDeteXoQkWdbz1xfjTsGbsmCWan9pPd7z4Cx5Nlu1iKkAxkLfrBFlq+2Xha4GE+q'
    'LcyUE3rouopAWu7eZVvMBoTHNGnZv+BAqdK3AThXhWmyKhIuwCPR4RGNM/BrzPcoUwGFcSJMX6S34WC5Ks9Q6HWchVF8NXLyRPZr'
    '+0RUMuBoFvOoGy1oIPKFf+BhzGsM0VtmHf/JFDGLsR59zUCiRpoDQdp7YxTy10shFb6VcnkeWSAjhdsN3BlBjsKyuVHIZcYfYdHi'
    'wjDuB5gwIpbpWgpv8afmq+wgHGad+ywcDT31vAHTNRDthjjHDUJ+P3glAsNd5BzjVX74oYKHhh/fFKtjef3u4MN79F5mf5P95oO2'
    '3susX3WC+3gST59qAxI1WnF4ax3vNnbQketfnURD9Vquidsa3rrgDU1MxS/hqlcGUI5SYQG3EwO4swd/Z1CLuJ4h2V6IIGUkRyBG'
    'RTF4x1Tw3PMvb4l1zh0NRTT8C1jonB5OTDThO6viStNZ1ajtmCatjEj/q6s7hsHmBVH/0GUOicnCTKivTrLhj8ziYFIwPswvYbAi'
    '8tQoyu9+9vrV4dvXL5HiPUCUE30C4PjjzP5UX4P/k6VHxpkzoMWu5IfJoQzHNZK8Kgh676Ojr/LThDaiMbQzDBvGo7cy6sGHpB4s'
    'eU+D41htNHn1a6ksnr2HjXeFPxfnALadB0jbicHABCg8y8eVPnJ9AWtbh7hyRh/Y/Sp7HTXPyfKEhVsL9TBCd9Upo7SHbBfpuIj3'
    'BXBuWZ3XBkln6Z77E6skiJc8NGTH5YEjUx0f4/KwARhofcRLRQbo0Ba+SiZ2UvxXn3eMbdNx5+894qnjvn9NJtMhsuuDqdSeiuqG'
    'teRYZIT2o0jKqIiixeQOFUMZEM0O1NpfPqAQX28q2aOHCd/SG8F4l8MbcqLl7ftuN7ndarJVJSfARbWGHhfQEzErt+xKx8f2/7T4'
    '04Lp/viWbqqCxTJoHQK9LRwqRJQt4nAO1KjrsRE84MF+B87BFnY6Wb478ZxUvm6tUwIb0gd2Lc1GWNd3p7GY0OhSH5l62E4WOAdP'
    'M/F8MIrq/hmUeVpkrAPSSdejhef0PfMbVuc4JOYtztRf0TQZX8E6ZqEf8SVjyajkcwvzQzusjTtaaly6eHseCR56UqLvu6HlmqhI'
    'UKHVs9T9vDtenVpzZ2NthKw7LGYP3XfUKtTiBm42Ahn37w5ev0L+VV0MN4zIla2iZMySJvXIzB0aOFj+czGs02Hg5/39YA/huOB0'
    'kfnA9lJPUHsT+UQjOu//uQDPMqD3O60yU+PMYcCrXYRHGP4vNI1NWhW18MHDiEPrXOPvO6fYw9d8ySBsMHcsP4d/ega/FGw2o6bt'
    '6eEdD1gcOnW5AV0t4MtgobnnX/qQymrhB3c5O3UqSkmkaVAukDAGenh6Bm4lsIauQc4kwgFTN8muSF4n5cJZtuEdWsrK3Ylw0h/e'
    'eXRfy+/sySdU9MG/AFrdu/P/AHFLZeY='
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
VERSION = '2026.10.20.2112'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
