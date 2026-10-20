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
    'g4qxHS07YsYG9J01Eq+94iFtlZzGWCw02nJh3dl0F1VPshNQ+Q5EwmepbxirwW66enSUhLgAkWFT25UXrui5Xt1rT+xXtzFID4rr'
    'BnBOXdvZPc9uRoO6fqffvljO3RBOaEu2l0Z9ss/c3Ezu93+uf9Ky9aL1JE3b3eKhWytXxX6l2Xh0tgP7xXtdl4ZOpZSw1KUDLcoP'
    '+4Fne4lWvf406vbrT92B3exND931YNguHfQBnNW8Wsv2n8Yr9RX49O3NQ0kEMfjQTZc7j/2XbltbkYDqjkBCBRRZ18p3pjWe6qvR'
    'EH4Ztw+DXqsg3YpO15k+2IXmtJ7vZ4y6ptTNlaFlC3J3PWs3Frq1knVH3rvNwep1/ZqoPG/dp2w328tJc6swEEHSc0AUNVuT1aC4'
    'lHeDzFIxizNN7g8q6efF/FAZPrqjfOF1kSkcRlV9VH4ePtWrc2NQqO1t/fXRbQ3scqucKfa0hdLPVl5e1Nak4L4+50FCr1Ya1qy4'
    'dPKzjJRQFjvYgYKhG9bYyvQaPW/Yva2a5UNlYIMYNVAQxfTF3Oo+33cX4nagDx4cPfOwLYn7ppiVnMdbe+O+zMbVwb2zH++70z36'
    '4W93qaLeSZXVvi7tts+70bzd6jUy4kBvVoAz2DX6A6V936gvpcPOs6u2XQO5DPgtq9VRHak3kq2Bedd/3tR6jdZ4aWZzL/nn9X1d'
    'LXZfBs+esxs9Pg13L11vNXmw24ZaaEiS7cl2ba0V6jYIAdKqmNutqzVp89ivNt2HodHoOu7B7jytxsZ6one7q0FNlPLLRQagppIW'
    'gbgbt0olV++7t4tVCvDCcLhPuYq3SQzE0m4kFe/Hci9n2pP8c8G26nt3Wun03YlRKE7G2fZrdqWZdj2vOB21rRYedyVnrSvyc3Nc'
    'AVFzaUpaummq2/Veeio0bpZrrb6owpSLr+lxqrewrM2o79j39fk8D2uIoH/bMJ4eLOu1VCr2Go/epNnsic/uSpPKBbexmiQctXxX'
    'fhqmlt1xfWXCcZQnYrq726zritavtyamvQVOppzY9POFmia3y021ZVeWd7cjffXqaWuQCNKG+T+s931cDNNec5iWxcfhSweEoNZu'
    'nB9bVTPvZGxcisau02+PQfQvleTZRJy33NU6UxnXtWLmqbCeHuRJBQRRy0nsQcDfSJr8+JRPFwazcn9g27iUIF33U/0XcQTkunr7'
    '3O012qpbz6xtQ1kPJ6v+a22jq9nOvqS6y+26urY7ObmVS7VeKll3mH/JV8av3qRoqHLr2coBbzYEacqRlqOy6KhK1h7kN7q2PUzl'
    'F88q1XNd5WW7b2Xq6mphv1rWUwuEowPqruWhrkuDya65HT54xeLdetNILKQmYKjsGvj51l1OHWaf1ttd5cUajg9mBUY/wIVRevWd'
    '250eWhIw+dnlqLdf5cqHon6fq6W6zUFCeimIw0oLmBajWlaM9JPytLZuu5JUXhS783GjoEQLt/Ll/bz0MLXQrb857Y5X2fHri1sp'
    'H314lBP5l8RdO70YTFcL67njPpvDu4QRfb2yX2eycX/37FW90byeafR6Oysr1hO2Lmc67Qfg5gaAM+d5Xelobm7SVAZr4Om6h2Il'
    'ozdnvdFrqTHuul5ZudVGdz07U29mdu3exrZyVlWRTGdkwTlurJ8yW29ZXk60u6y7bprb9B64lcPKkeuONAaotPdFvTlo9KXByB7K'
    'y256Yw/SGbN9P8yXrU75AW/awglZ5x9ejHbtULsrjy1n3NhpBd1uDMbDlpRavfaHLdXt9QYPklFxKllpDaxTRy0X0l57bjSMm3U1'
    'PzwMR3cgRbxmWp3D63rcKQGbOrPbip1vP1tep2jITeehu+23SiWprluF+mJm2t3KstLs7TxN08arxfBZgn9MkAJqWk3d3lYBsv8j'
    '/7Ue19JO26h5oJ4r27bhhN48Ppkrqfqqr7aj3tpKAzurGE1xYQ1bqdeCrm42/dKo0uu6GbdQA5TnNOd3A9frbF4bo4LkLUZWxxhu'
    'Frmq9iq9vo4Oj4NJQi96jWZvuCt6666li8OuObJfnV3JLi4AY3THW+CNy+rhfp3dJEpdbV3u663p81DLWEoiP83Oxuu7++pwUq17'
    '3mDa36sJdaNu+4e23WlXdn13pBu6+CpX+lJrJukD2fDSK+fRyu7LUrOXdXpjuTmsimMZL0u45ep+ZeXSuWZuPXLkTWVQel3u2yCr'
    'dNeVw+AJ8NtkndqVFspYGlWz05Y48npqal/a3twZjfAyjPj43LgZmLtpt154tfvidpzt1u3xKrW9WWyyy1plNd+96roGR3OULhkb'
    'AMa5XZ32bbWhzaXZLlFrNCaN8uS1MVWkgd65KbfugEkQvZHZ18Tia08VH+3lYFC2QHDL71fllZRNTOEf/bB6lNzRS3M2GKaVg5Qd'
    'dldysew4A61cV9PZF6e3quh59bk6mBb63hK2ZpJpZcyC1h481SqpVTqnjmYTS5+vso8DWZTk/r6pGdmm5ijN6mZkdkBIhe1b67LX'
    'HtvlXrPi2LLZy2vF4aGxyQJvsrlZ1R7vH5swxKa8WNkr4D8Kpv341Gps/0egsNDSNWm9L3S0uvHiLFut6Ty16KSytefnnf5o3h/y'
    'icdE8zF181iLfHrtFG5KCf+3ZK0eV0AZq5nya32teJ3hplfudTsgFGxKUmpt5cSmV1/0nV4fVv7VsUWzb67l7LyWuUuNtEymnulm'
    '6wVRVhq9zlMWxIvdyO609OnDwDp0D4N15rk+Lxvu5KnQFTeK+1Q9jAzJgDFJyh00nz/cZYeF8e4w3HX3xniXLopKwrJMMT23MmWp'
    'PCxqdnE/fbZLzqQ3K1T0Sd/crzf3y2LBlA11pz5pyqOeMzpbrzjp1mxrlCj3s411ajPdtqbGaN3sLwvKfdFrq4nU9n6j7JpP+9V+'
    '0Nk0R0b1eeh4B9NRN51cvr1NLA213lz2J+PcCtU2tcXQ63Ueenbn3r3TNo2Cp/YyhUU5k6+I0lCpp+duWiyWizc3tXnjFEO4i2q3'
    's14sx2IRMEPeWYqdfkF/mU+fi/WnRzmvyPVOobFRGi9WOtFql9rmk31r2+mxONA6lbXT0pWXjKSV0oPNPntorFeV10zGLjVXtiOJ'
    'mb07KauKlSqvNy9G0dZnxSdlMlUd5VFuvA6Anrdrq/xhkGuI8H+5RV/ey15xpK2fxFHPzGhr+ynrFvvFTA8wv1XaPMxbmVGjog5X'
    'T4/b9rhQKbRSw3RJK+x6XiFdKGdv+zXJ6HuGeyjkyvnei5OtroADz2ZtNV/OlovrW0muOuOH3eFVHvbr3X76MK572tSxh519rbxZ'
    '9Jzezpw0D2k4B5XXlDxvL1rPuv68KSjDyhA473yvlWsZ7ZfUbjjN1lrqPKW5qfVL+RGkwMgH2Vsu5PXitVrf9LXZa2t7c7v8K2cl'
    'UU1lpbmrwPJtZGstWfVhc7RvFaYPmiLZa60G4ow56B5uD91dU7M9damMmpOJtPDGdtdYDtb51t1GXmnrUUbpPliyncj3tmPZLbsL'
    'Ne8qo/5mqXda98tFp/kwOmyQ46wV28uyVW6v1GVvCKJ2Ztx6EQspWy4eHh7nDa+8frm5t+9X3NykIdfUMG250ixu71e6Nr3zRlVR'
    'HDVkR9asg/7U39fzTSPR2Rfs3fRVNC1z1hxI856zy9SXsplJS+XuoiFZm/vGYaxsKrfTYqObVTPdUrErNpqeBoydla7T/wrmZvk8'
    'e9H3vYnebo+drGSsO2Opa2qrRSE97DzWbLVXHhpWf5VOSKOylx7mjO6wmJLapr6QlScvJwKGuCnf3Dy86LO3q729zZjO4yuwyKO7'
    'zrAvPh8kFe30xfJDpw3ygvaUE9vr2jTf86bNymuxPRnW7c7gubR0yi19nJY0jKPSmb5ItthbFSZLQMe5QvtFH8AgOo/DlrxzX3KG'
    '/TpU9G6/uR5kC2t9rriWlZ7AEsgbPat0a9L4pv8AZKC0fy2lbNHWpaHYV4c3N+p9n6J2VAYVsaNUXnI3t+vMbWnvdsYTIEddse9t'
    'vX0jW260UiMlVcsrg0l5pDUaw1ahrxS8ZlNpTBsHr9l3M7msJDXEYF0XL9aql9+/TubN9rhhTaxHGzC1DejAtFNuUWrYxlJ8dfJi'
    'o7pz9hlvXp6n1XlW7BnqeFWyAFk+yTe3k8fhnwL1w6BkLe7dcm4LnGNhoG1WXt8+tCWjVNlL7VFvJwGM16wBsGZlODKtcdkGbrb5'
    '2ETVRsvq3stbeZ4r2LbulGoDudnwHK9lSotBLVNWt+XmoJe6qdqGATDdstLtQWFwZxwqr7lhPvWSN4Ze3R5YpXJnONqMgP+8WbZ6'
    'T9PnpuNVM1KloEykfaOXWbc20uuhkqjlUqPadGf01OWkJ7pqvaUUbtGvfvv6uH26LfZa483u8bGQv088K5bxPMotFmV5nqq2u02r'
    'kGlXqq3ZaGTn5WqndPeipg+rRqmzS6xfUovHaAeL9EJSvcXuJdL6/etys6rlC83hfvfcmU4bw5fCU+Gxmhjf7itDw6nZxUr59ba1'
    '08x8vboaDKS8ahXFTrulPW0Kh95QVA/mLmP0e6WWm+0r9XXB9fQXqaSah83TfFtsS2510MzZprjQ12lntPMGzUpeByER4AuIY7lf'
    'SKdH1pPUcifVTsdbLMYiyI9AX6QVsKTyA1CYadtZ53VZtAavk8O6OMwONp1Fd5i7uVksT8/Xw7hkrnaHUfvuubIHYqkmMns7ASLw'
    'YLTK1rTW6FBfDEa7mvW029V2y+XEzFeb6m5fR83WoNJR6/W5Y6fF/iy3UTtFe+Zoen1ZzndnD7lcbj/omiAhZ+/EQeVmIQ4Odtcc'
    '9CVxmn+saYWnnF5+shol61nxFFO3NNUY6qOKVRxVnlqivVOfHx8GXmNtA7kYT2DB0i/VUtkePRq754O4bpReiv11u629Go4Mm7w7'
    'VEZlJ1d1zOahsB7drhY3WcPr5kqJp5Xq7abao6Tv8qXec3mipR5aYzvlTW+U2/V0sM89p8fHTXcyi/1yl4GdVqTxCrY127Jz3kP5'
    '3uu1nwfTzGbWmmXbCERSbdjKt5sL3VPvH7N35sTdj+ojY1jbPK4ylplNl0ub5eD+NlfZD4tVgJAUiBO3/eZ4ndYr97YzaljrTLZh'
    'OSYw9r2OuunJvbr4IIlVD80M6c5DrtYrtjL6bVE+mM1qeg/8/UEcjNX8tJ+/uX197N78///9QD+RSr3+/cwPTB2kEQ+u/FA2cUwf'
    'gjdxzLV3et0m9U6doTphCUIpVjnmefHTlEksF+Lfz+aeZ7lXqZRqJLfaUrNURZOSpjNL4a/Us2Yo/7qSLBiYo0oKJlBbe8IK3grw'
    '1r8/I/mpy3hqG5ZXNH46wrlzcn+JRc2W9TXmR9liJi28v8RSo2ArQ9OhYNvPkrNUzO37N79O4kmLJwGlsxhuvUFBun9laxENflxI'
    'J9PpTDFdLKfT6cJRdOlcrpzMZ8qZUilXFNNiKfefGGU98717YDTQt9e9uiy3lxTNr0epW6O39BrhfS0ebRzXkOe5pltvmMlDZ2ns'
    'Wb6SMGkdheG9EBTJnbMA54rpeerbS2OTjxLmyYiEXpc8QdUoTZVqKMeh2705gIMRJl7BDET//Lf/68ay9D0OgGVCZLHg//lv/7fA'
    '8uQdvRYog1aYLSqAJVqr5TtrRa+FhakZ4ZCNPaWi4il4IpPCjFcC3XYTFG0K4gQm9AszHCWFk5XnCd/8hhVKeMaWdinASiu6epRE'
    'kfKHvc0rwG4+8uxe383eFLlONWEX8MLUUdGqSeHuJK0vpn7d66qf6u642ZNUKqw8zy/2bs63kwjomZMI6PcMZig59F87WvmymCyk'
    's9kixmQold6EFffP8F8L3E4dh0GAceIsDDAO64xuwoZzOYmPnjmJj35PUH86F0xWl8yk8+lsvlzK5LPREM35fCFZzuXzORFj6Ofy'
    '4p/P5Qcxpr83FxrW6VxOk/GdRE2nhDZRbCfC+JOlbD6XE7NFMVc4CjWNWZ1y2Uwxg4G008W/MI8fxWU+ngehDIr8bryZxEkU9cxJ'
    'FPUeopDT/SiWc8lCGeCmlC6kSxk/XDybR6GUTJdyZUDamWwmL2b+dB4/uql7PA9KBEGR4HFUpzM5ibWeOYm1zvASUFFAauz0hngm'
    'Mrd8LpssiYUSZgBLi4Xy0blJ47wLxWI2W8ims38+tcy0rOZyJ1PLhUM+CbaeOQm2nqMcu9IGkNMUSf6vgjuXjnLtFvK5ZDmTLol5'
    'sZCBwUbSHWREMVlK52EL8pksfBL/E+nnd+5RZzEtDxA3nyhkA6LAk3G4fsKeABnyVOKRVHaajmluMf8npeidU2q7MLXIRZCKnTAy'
    'DSFgYnxMHEmdfu4KhrRSkY5Rmm7TEogSENalL9obVg4GPsYEKroGRNDZv51ONK8N5jN/k9KGbj6zUfsDId5qTptJV6yBKGw0dUs0'
    'TnIAKHGLiVFUXMplgmm53Ysgb51/aRxmHdwYZ9N/Z/hdgJN3NuK9PDL+veNYu1mNR0gzy3yCnAhwf8hX7AUMTv+jZC7EL8aSiinv'
    'oi1t4bTOiV+iiflcZdU0Z7DB96YM+x1JiYjbGuSnmaiU9XPOuCb3IrLp+MSYayoi4R38H43O52IjWRzDLLSWjgOIJMfCz2uPsssc'
    'M1V3prWPZl50ghAMlHYxMqv3E8X8SfLFzEk6g8xJOgOezwrPkfufgwh8rPOXM8hkTlISZE5SEjzCdlydAH9CcAnK/8uG/ONEHJmT'
    '+BSZk/gUD4HMA6fggoHor8LK/M9Ctm8H/D71Dgd8IlZlTsSqlo48MyFLYW3BEiskY6xcVf8vBIz3SXWYM/aEU82ecKq1f/7b/7kC'
    'NhkzdnO8FmWPMtn097i8U2Ew/6fEDPt4Q8zSMoBJ+XtRWCrhsFyQhTD6x0SlyB4kLexDJMUwAib4xXMPIh2mHKb0q1tKoI6o3loT'
    'xVklhRuez/pNXBfs8G1Ql9M80erK8nhSYNYEyi2UNJjnn00KlMwYuzgK6UJ5i3miMwszUZtTlhKZpwU7ljV+ok08YyI628az7Am7'
    '7oPI1DFXURbLDDnPU16TQ8YJr+zzTryhAFDMCBv1DvfNGzvNTZw9aiyIPYONFfjUfvr2e8qVHc3yPv70u/8gm4brCb8IHwRX+PAx'
    'yMCXtNeAupjkaToxN37NS7qbGZT9JXb+N1kyNpJ7Hr9Aeq0r/C0940vXw/g67CU940vMFw57y96yH+dB05VWswefzi8lEM7VS3fv'
    'eurqQrjF7XiW5C79rsD2XgC7MDNVoV+7EDomyLbmhfCIh97TZEloqmvgL24cTdJhFJLhXrqqo03Pr39KpYRbPxU7JW9DUswTvrE0'
    'bVeYtxHBDxUWAOEYxAXZgBX8mGG2QBC+VWx3omMncM60GXRurR0LxWcLRprks2nfNB56vQeY0OdzTk3OL4RzjqXpkeE/emRYhR4Z'
    'w0yP7KzSo1guinKGHvPTrCKzAmU5W5jk6VHOZPJ5+fyLv5qdVqv3r5Vao4FLylnYc/9jt9fq4NDOGet5yUnU1UYMitSeq//arb0+'
    'dKHYV6ELEk/6QnhGFAV/GyiCw99RAwE3LXwL97DzfNN723LQLIzo4V8HD51urdWEYrlrAFPYl8l6ZcHB1FwhhmhFomBQGB8HD/Bz'
    'rdq56UGFbpxUdEhWWU5VCVPhucA8MP6NJ/j+6ScM9AOogaK+fCDMyPuJZKwmRUVMg0GhVhHwgo8z4j+xOEHG8g5z7bm4hV94fV/R'
    '4p5jzkBsRmZl8OCxrxKgVA8Tkm8pJhVyR5hwEqfF1YpTWBD4FvbTkADJYj9fv/F+aHCaIlx+5OgUtTg6FhO2wB9i64YQ+yrsLoQ9'
    'HMALYS58g/OFnfHWWYdwxOCZdYS1KZFvsCKRCaHGy1V5FxoyndjG1tEA7xhUH1DDBa4eVIedR76dIGOHShBhT/8uATwAQQkzFRYD'
    'ZwOvNOXOXBse/zlnmbNhBFC9q3oxOP3Y+NpQzK6HGRNxsS8ofWr0NwYA6mEwLn/0F5TyPfjBJxr81oEfvQdGl4boweAQRLEjZBce'
    'SUkWlMVXTZSCgpY1B6jNB2Eq6a6KmAx4oKHkGKriv7z+iYOzok6lte7h3sXiiEBhT4BYzSVXc3lOK6ihqP4zMdNXwjnL4ggHd+tI'
    'FvxewQTWK/gtrT2zB0SVVYBN9Q/OsHPTptkYRF5gSsnihcDqoe4GU0RCN2IyD/hrOr0SagZIUxpMJDicE12i8xCMFAOb1RSq7aoe'
    'LiCMzZ9SLH7BQP2Kds4wFRz5VyGN/2gKbThyNTD65yCt5sURPDDehLMmArIlOFUoDOWII7mKoKlv+H8w3dRvwmXwH8EnF5CZMAwg'
    'vpI8xn0wro+S2kd4wbA20sCB6rgaiKOAW2Af90KMtB+EWmDQIWoRAIOAcIYcxIZXIWEGB4DrBEvEOCAM4EYjYaHPsI8JRSHzKPE8'
    'lt9Kexgboi4FsAEbK7B8a0JSfuuYTBBaVhXWKR4IHFX8ihQ9cJAEkBagCNcG+LsVbhXfE1g2zhIB+afFOUud8U7OWFsZAVAlADil'
    'EYRt0dcuX8erN4iaBsurM24c/ssKAVOoaxuVq6vP+LszIQb8GHKTMJyz+DUtk0ER0BCvRuTaGIOICECw9uE/Bhdx6h4Z18upbkp0'
    'pv2e31YWzrEkcBA+zwb74W2BTAtc3R60ztu4FiyYKhkhmHaa0p3y5pmmjY2A9BfQIs4FxHbMyirpwE+hQgKme6RcCTpBfIPqlAum'
    'XNtqLuJtrn0BCJh6sCCIyMMViSeFDqpgcJ58/QCKANJWqoTQiGAdtC+blgYDJRYWhH3LAjQ5XUMnmywH/Qg1Q10DGVmQJSc9gekS'
    'Sp8zNdCes/dLw9wmWRc5wVcmwKRlQDN7gNozIgkwZ3dO4iHGQsScxAjAAfWAaXQDAAtnf00FODAF05iZJLDheeIzIo48HA438emM'
    'Kkou2RMmAHUWHiclOssgoiOJGdhFzXA1JgjSCkmB+A1ETdLhZLrfP0oc4QHGhB4rsKIpJOv4ANgY9gNpe1L4LfWTDPTFBU5zqzr4'
    '9QEwsgPUHUglnGb26+s3jnUjKOYDsewi4FiOgJPJpHIRHEXGPF1ETh8SdaiRCWrQIn63fPYiQOlK8nSO+C6cb4jZqUngBFChh7gN'
    'oQSxGxw1VIlxOSod53oolot6qjluxErFAIifpCuhNVkAj5XExXuAVmCLY/yVyn/C8Ah3/eMfMIR4ciVZsdjnJQz/C9ImDir4ouuh'
    'Ei+2hNcfgKtMnwufBFo340fkBXDiFbZFq8fWMHu66sGq5agEUMnp2qD8y3SYON2IKXHoz1GROggsqmNSc2uGp85UJ6Z8SvJm4jAu'
    'xf8BncMXNsNPgMmBGF6D/BW0v9IAIj01hiEE4wQTyJpskLuI9oxfr+GjNhViG+HjEe8cFzD25ZbIxjEcxs4N/H0eqfq7IEbL+8VM'
    'LzwerDhLLE41jjv7ipRMggGG0Px584UPkUaOj/78r8kmgX3/TK99FAu77e0tFc9t9PXPuLMmAcj5Xxsn3w9s5fon/6AFZ/UDHyzq'
    'huGk6NpBjTA71PU7hwNfn+CDq6NxBoeGXtLzBVNR81f0HGHZGA7B4XDA++7BjS72BcInHBDWGkK734ffgYDnNv69k/0WAwTnkp+6'
    'cCJJju/iAUPbqDUf/rXbGzdI8Pt8TkZ5FDCZLZOeSBdxDlz5TafTGrJyBvAw+BEwIP4Bid/x8AGk8zkWHdbue4+sKGpu8BPbHHwi'
    'WxaKrsEJkXWgf+hNENMR+LjshgT63KWM9VecfzKNS86wChsJhHLm0bFULe8nJJg4JZkJVhwideHXX6OzTHLDiRvTk8QTxOOCzJ6g'
    'Hn93VJnNOlqPOHKqR09Uj56O6rEliNYjYx7VY/ndsR49RWBcRgCH2XfUyVrTlQhBi5HMKRHOYIIDWZaA9qA0JbiGZAGh9uKwGirR'
    'SFqxrarrlwiIQEjZiiWFCjEPQPWxI7IksKaNPQmfjIHlOhNAu8BIUJp6eh2YolRiyJE4+/SXy8DnyPA4y7VFLDTX3GFPQJFByKGI'
    'u5J7qcFAQp8c3EE0khG/QRIwduZKINEAY6Ec6QH2547q8yQOF7JVJRlCU4gGFIZuuS4Lj+an4OgwYnSB4V3ZhwiJ8nltH5JYA8Dj'
    'oji1QRlP1ydMXE2TdBWQigoKYWossYkjDGwI2SHBCn+dI01LbOBU+62EPczVHTQpY4up//a3z+nLsnQ5/fK18O2XlJZERUNMJoSI'
    'gn+MVfm8VPdISJE9OqG6MLN4nFuSWWENRVo21hjUo7Y45n5D7DRYPFgMqPI7yNPw9LMRwejGCRqH9mFV1+p1pDe0PH4Q3rZsJBkp'
    'j0cLy5xdogEpvqzp95YkwCCewCUWAReRvwUugAmisD/Q9i5O8ij7sY9f8DZ97gEH9YltCRTiI/ELcSkVtgHq0o849UOPAqsMG2kk'
    'SRyhFSCRBAqFku2Vrwz8DGv3L/6PpK4aM2/+hXX1LVx5aBNRArX4wW/6Q7Rp/uBzO2FVI0lqTBhIAGNvAJGXIbTDSn8Q/JfRlgLz'
    'HPWN2gisEXlL7yLD9ncGI32z8U5ME/E4QgN/yz9H++FpyaOd+K9OenhnKmiOpYMVPMv0Fw+NLq2s2LPkzZMgnhtKUPxCuARGuRCB'
    '9c/nlqbrjFztiIrpugaTJNoEEHX+JcTa0AgKOYxKkLiDk6KnaIMB3YRDQISQUrYfN4TZ3KkdfKBm8OFobVYznFzqv4XBpv+eilnG'
    '7B8YcvofM236j606seJ+8OnP0uUBcEQi9eFLIsAQ1EwSzz5fKPy5BX4yHfk9x9/x4MDJ1DWqm6AeHgvexIWwvQqauBDmV2F9DsFs'
    '6IH2+DN9xuj/X+Ks1S7bnuA9q/btLRwxE/fREaejRu+xMV7AfxVFHiTif4iwEQayOmoUv/Gjy1EkID+gyFiEn0vsgLeCf1hFIgJw'
    'ir9g29fMroKsCcXO901OqzUOAAVUpgOSEEtc6kCtdL8IKmxQxJ2ZSJcJPFEbJSFrY12TPojLxKoLUjHrJAYYh2lpuSIE6OdKc1Fe'
    'C4WzI8uiAFLGnGgkqarIUGe6XvKYYBgRSsE4ghjN84RUuOqR4hY3VvnCF5RaQxnGou1g47uGXz61u2ZfaPmsLz66D/E7boj/FYkK'
    'dpacS27MwlEETQaqax8rclR4LSjkUSiwbb4WJo4qLa85VAmsOUlRoLkQ3AIZ5b25J11YzphBQkTQeYR0R9Ey01yFfCrTMkgEBK5H'
    'uxlIyqe0l/DTStrFLkVi/KPgyEeCwjFDfdBHQhDfguLXCIH8T1LG+sAdHKdlyPy8YTb095gNYKBYNSbj/4f5jp91xnPQvHVSLnw5'
    'euOZ9Jt9op3Bd+9zIszO8cFnJ/Qkf3HMT/DXSUe1dElWY6m/u4nUDJC5cB5PQqlVDOAEKJUag/UVM4A/kfVg/dDcj/YHh3XFhwe7'
    'ZV7R+GjXo+IOk/+Q49BDjuOrv0X8XSgEYmE2eCzFnvjH010EMKsdwdyfwtsbkKRZHYNkyKwy8TRYVAAA/uZ4Vbkc+9dWNZOOrCoX'
    'iRgg4cRPZORgVdgJ4YJwMF3kAJGt52KxCNNjS5LA558YovBFah81hdYcN+k/E1pj1iFeitl43CT+ffuVW31cQk4hSZPQvYz4ufBH'
    'xDbEKzMLEUjYJFEiKxEYi87R5oN/zek0ylq4SayEcMOehIiFibca2pncpP8c8GCcJb0IEQ1XGZA6LdS4oAVXU7jfQDLASL7+QyKu'
    'hlmbjnFsUDzQlSw1xQ1ag4oAA8AMeSgcvMHBgBD8aprbMU0iC+9iat9qSx6PQH+vgD4GqBiFxSNyGbRJKPR7bb7L74fjIQ+av1D3'
    'w5u6OLDQkHi0BmxISJQcLxaTLoQJM+FJnIP/9EmQkognL4XYJHw3wXfxiFoFFqI1jRlIqriqLxiiT6njOHShGZHJ/GNHaj2uKA4u'
    'gQgSaxl9NkiVD2iNTPNkZte4M887KmN22cb344EzFbjy8OWAYxAsBpqdozJNDF4QeKsotNHCxeKf03AElMhsFdXy5my2ZMBG4fz6'
    'BxP/+nbqSiIBsw70jUdaXHc98WD/iD595SgQmboPAh2CkCnSWMcayM14aYrxl/A7kYhHaamMRBTPQQxKfda+AMnE4tbancdk3Mlg'
    'J+A1joSfMmN2r02nuFYBYIQTJuQnTdyYBLABH/9FiGWE39jrdi1sUgH+n7+EdY0UgWoK6rOvQzsySVZc8RF0ybCsZsQmFyHGha8b'
    'BECAmmdJdgU0Vv3zf/k/uE8Dc0Fnfj7sG3p2MusaUBt+mcVBuw3e/NoDrMmoFmJ3feLJyHlFYTEFf/6htefAb8EfSUlx8UfaaDPJ'
    'M50kkBsPNV/IJYRvoV/nZsa0D76aAlqqA7lDWoZz80JahSP8O7tkRjQLZsN81IB2nRTqzrWp93dG2v75P/0/UPJtGb+N0AtqGemX'
    'zexTOKCYh8TQowW9YUKOJqPBwvc+cS0HxMyopze3FlogOl6jF5wnLbkNhyn0/ALu2iE5hIxpQCGD1cX2PzAHchjSH7+jBxjZvz6c'
    'afKZIDmadMncOj6cIfE4+/g7biXd7Tv7m3b5y1es++0s9fH3FNT9+Mf1Tyc2fqYWJ1vvr2j4hKHgc6QEmtwYjpQ9VIgFbmoyAIan'
    'Pugq/oqd+z5pyZnq3QHbB/OInWeUcHVJm1shFzRGtwgPp4mFmLrkzidMt+jshBzzjtzyBGuPHnXEXLDyYlBeLLLyBb+8WOLlRcaM'
    'sFK81XxQKsdKlfBQwV7ezVG1K6OjjMtchs5chj7PaMgk4pG/JaFWcmNkFnXuUMO1rqF2xvceT3JfKPleVS3uhMO+BS+ianccQR1R'
    'EGPXj7x3rt/13nkrShLl8tl9psd4g2r9hj/735BNjr3zFo5qOiL1/EVBswmCXiBkkuoIXwSrg/iazYWEQoMh14jMyMV6pHQKLJNK'
    'Aj3K7ySVAw8o8O1BdThegqMV9SkfJw8IakyZDaeS7NVrlOi3Brv4iFJ4dF+u3+7Lv2dtPwRr+568M4EWWfNE/y+INgT08ZI/TiIr'
    'HQ7mM7IRX6Jyw5tvsEsgvipxX97402H/HNlq3sCfzgS3HedhsNHzcXJy3gS+h2/4e4R9QkAxOSXsnOeX35/m8YfjOYacEPMo9e3k'
    'JrmWwA6i2/T2lN2MMJtxBksG969GzilisYjs1Q94NcYLGd+f+A9ZObY/G83VJiS2vcN3Ehf7Mz8qqI4xTjnKqbbrqjqiC9rXCKMW'
    '94cdqY5sW5w7ETImLjjCtKB3eH+c/GYkckIguiZmBPNcxi9wmEhVhscsXNfY24VFB0a2H++uLjV2gz3Q+gYCLJIFn0UG1iZgnzzJ'
    'yKDtAA6Kk0TjSnJHjzs8Lz6flBIyERkVuPRTXgsLR3+/4cUYUA2ZtcufgIsOQ3K4Lit0xsd3uG1MVI2sCvfawPNHC+STgYhLEvbh'
    'qMAKoSMXd3BTNIdjLWyZg5FlakSO0O8N5FmDASyKqoqCmC2yL66HGmyUTvAmkoON6ft4ZMXdLRykd1bcOgFQrpJjYh0p/3wzaHTL'
    'QpXDjCF7v/53Ns0KN83CTbuMFrGoyAyLWFRkBkUiOxkpSo8u8LhSnDO5sgmcdTweisSTfXfLEHjIjUcmL2Hnkd+TgDOZ7FvcGPPv'
    'lO+IgegyYMC7ncwfkoogGOjSHukOj9hACoikMESHQRT7L/ECh0D7fs64QvJ2VXgDMeKv0HkL+qBXJM5JdInUIS95hSXWlWYzZFKu'
    'T13fIpDrokiH26TvmQOzz2JSw2RRYuI/yUAwMybuoq7AV8uEqopPwYJd+WseLCUqeILFtFD1pu5QcIjIKaHClTqzsDeO85Y0BFhZ'
    'wqO8Jmm8+Jdg+ZeEDBnJxD3AlWOnkM0zOnm2WMilklUbfa3YCuMeIdHgdkeyYJM1wUfqEVwLSO6g0sxoxIBzw9HTWvkrkYRWHyR5'
    'HostLwSNi4TLwNynXaPLR1SWZU3fAO6HmrLKjmiEilsRKo4HlEohSWQDSLIRrNTjNfLpUPx46Axqv/3E3BpcE69rBQgPYEadThEb'
    'bVTu6YE+mz55haVxNLTEbzUj6mdJDAxsRcg3+37MkQXE5o7xDwEd6Wxi5MKFvlo+W4QONjITNkIADFSAQHoV34YWe8vNANMKH68Z'
    'H3lLvIAXcAvnGJFhdxEwkcQkogmSu0KSFpFoH1lN6Z7ubK1LDs3/uCGKVMG6YWsQQ2497YuATOuCbTMO9gKmyD/5nK3PsNL3OPNz'
    'po8+b0N5iolzZf2g0/UagGEf9cQEwVZl/roIzbjS13iNg6WTpq4czkM76iVjiH2Eg61LEx79IdwahkZhkVHgglX+ObpRAW8WMkoB'
    'lwZ7KEa00n4jGWwEt/STEKPGP8IrfAasmokD/WZv6ceVQGpnkihCK4jqHCN2CQAuNoEagNZ/Q7E8ym5HtH6fArkTHVB8qRCbi4l5'
    '2JFcnMmHEWM1fQThMhfHpkVfcDyugyIkvSlfCCWu7ue+cK5PB1lzkyS84ayGZW5jYhIbYQZxBq4RojrdBob6QCUMcwCZmDwkgvek'
    '44YPOfoQYUuRMkEjV3y1WUV8FfZxYjrHMcRC4Zrs8Ki1Jrt8dGhRS3mkUpq06GRzj0jpZEjEETArPDbIzPCRFtFlB9YmheNzo0YG'
    'gdwDZdgZF3cH8Ch5JVwJP//sOy1c+B71OBoACslVaZ4u05x7cBKujuEAYZPtIWxhEvfQ3Z4U4Z4oVCqThJ3NcNsE7j9fNtQdk2MC'
    'lC8IV8c7be1gp5ccPN6pkH9TYU8VmGY/dFIlRcwJv4a3yTgWxbVCdQzQGlIQ/PHL14bvuQErzp9o0c+/4bfp9ptAf91vMMRfvuJ9'
    'v29/XEfNU0M8Xo1kuKeZAoKO/wZBI5PFN2QW+g3L0t41krj29AbvyXw+QtloAWGIIbLt3BIjBD4WP3PnoU/C5y/QAVbqofqIv4bq'
    '6FSEY4y2Mj8+Zg12zMRkphS1i225E4HLdb/QSdQGxz4hh6EjVqFF5atPQyBAJ+uY7zB4xUgLKZe37EKWNict808R15FQLY0zfccl'
    'g9p9Pv8ipCJGMt+3g/t1AJ9AXURm6XuQ/Ca4+HX+3tc5/xpaH2cSIk9o69dfTxej5E+I65exRQ2pOdZJHJf+DRbdn3swLlnV9Fgw'
    'BQ8PK/wvBCSYZyP5zlFAUMqRfqnBjg2cNQF7l+fsHZ6MjL+oYXvoQsrb+zloLx6OB0cBAxDz6ThnATq4NsDj0g0BGRjy4HIRi8fk'
    '8huIJE6hShaBLrYyXY9zXuySj4u8oaRz8CWXEUSRRLVZR2gSZBczOMsEbImmc57Sj/3EVL7UhxbxVHgGHBN14OQCQ0iTn2GCQDf2'
    '8x8ANCwdiMIXoeXhkr2BBfX3NE6CDByeSwFPTJw+X4XQe9T0u2v95q3vsXXsZtDBraQ5d0AuWruxrwwhXvmVLwSF0AvsOh0htKgT'
    'j/UBJwmDZEO/FDrwwTHpWmOsgwIkIJvf6AsV/42DCRs/veK8IVUi36pT6AghFxAEUw2wpknKtIGdx7rxeDxQqzEgjMDx6ayPD8SW'
    'oaIMHMP50Yc5fcjmj/wtl9/Z0/neAlEcx8g28ZlYJfoFaxLbz4N3tFYhdmLjXcLkRVJivRnb8t2BLeOhDjbqNsrB6IhEA/Js8EuV'
    '8Ae2EI/+lm0mIgH8u5qNyU8TPu6Zw2bih8iFQa83v3rn0zeuo6kCHwpCKAaqIUrBwgwA+bK0Hd5ZipGdghzBfNsVhr2JHMtzvIGH'
    '4h3M3gBmGlXq7FD73s8RuSUgRh5dRCQiFCHK3Oj4BfkQLzAevSEjHqcfwu8fqIkT/TLIm5KPeZKupWte7PzvzK8pUL9yhzjfxyVS'
    'm5YCamMrvHZKSKTiEZfCgBunVj6xPwkkbPAv1b+iP1E/QpwQDJxMuKxv7zpUCwf+XT7SiFhMI+5+gl832jpXThJ+41v8kcsZ1CnV'
    'j9w94NeiaJyoUvTd6sItvWIWBOATg6tuvvU32sulr7mOjEJ723foAqPFUei+vAxrHU3yqOC1EPFZ5F+0YBm+RVwt3y7Ut/BkoYE5'
    'UGmpruyHh3BD++XnX3//ePYF7Zcyv91y/us58Hq/SivrGn1Sfqdfukc/PtKPGftxRj8wTOj1ufDts/wlHqhunBmKTuT1/jHgXvB6'
    'EcCVq9YMDx2j+LzQf0cshErtzxvhIyxj4UKgh5Lwq5DJ5/EXPXwhC3bkDtYO24KTDv9PN8ujRwrViDAWLAG9TPgvXg7OGTIogTaJ'
    '8T3SZ+0LyYP4F0RCtOCjVBjVJf6BrfzydRpLx79d4F+R/83Ev8X/4MjlBmg5XhVFlz2QAsILw8ggMKMtiQxAX2ba5tiYC9Cj6lMU'
    '8kn4R1ECQzOpegSbsBd88uH1s8/QIezm5Etk6sSUbnCiG0SL+XyEq13tovSMV0aXKiN4rxmR9+QLBJUSUCLOkKyC6pcV6lxXhs/T'
    'zRk760oktyvoL6YgcREDrS2wFEgrdTxJIbVBFKCAdD1nTSJ5dFC6j82Y40NKwK//QuIS/z7D7yi+O+wzEeErIeagEjh4lYsIrRk8'
    'CDCy39h40slMnrYYZoefdNz/dLKYh2/6iUoAz9A7k8jwWQC3DAvCLnv8dlIQyOK/EOnNxOmBasBCY4/4S/bpIvfJdEC4nMH/JiLu'
    '5efPIKfCVqeBPnyGvzJ/TNPjjj/iB14gzR9letx9+fI5xnjrKUh+TmxOq4g8c4GevkTg+/xviMujAwghKHJUAugQI74iGFQCgYMW'
    'A0Et6Zn89iec8qQlKV28VBaDZTpPA1lKYnzV2Pm5bzepMM03xUBDTpqbZMkgtzJNwLwULIAsG4HJ9oJbTBSB2z6+b1ZKormPXZCi'
    'o6aoFjHzdKuK34VWNIyNLKu+QwaACmv/6lhph0Zg3/1i7TF7sMt1dTwWK/Y0DeLknpxmZNmpBizIXA0qJVmU4YtA089u05NiUaLK'
    'IHVEnEWkFU3IXxdS/dHVcO7CvJI8YLqYsw69X6mqlyT1ZNPcouiAMZ1VZtlGZoBiK/ihT2AhXZi9GoszJwS/GnNCwE67qs1cowK1'
    'Im0PugLCOu5BdNHstSpIsmO6QShB3jpfcfRrQY+h9WpiSBoqUE0zHtFrQ5+9YxXGNOI5cGRJ9W/14LvQExo+8IF/psZMi6safaTz'
    '8xTFy2nSwTMLf9Lsuq1vaeUaxKgx6R3Ij0VYbWaomiblHQrhe/a8j/PWidOO9BaP+wegF6h7fWU5E/P8CEdcm2vgvuGlU5Lw4HRg'
    '0ByKpcWdUDF8CByg+XqSPFlImntoj/5Zcx/Xk1jEfhf/E5NzaA+cQ3u+eTvkDP3tCmoda8aCa1echPEXSMZCg7ZmLFvGWybiPfIW'
    'dAOIvFwGtOMAAkon86UiPM/oWRRz8DxB/qxASsa/iQWxKE5Ir/W3Kf13fs3deHiIzyC8lMWU9Ss4mHIsLkiKZHlugJt8DBBjIUYk'
    '53Ki4xXCMxD7vDP/KwtLwiJRagZFohRWpqIG7m+9x4fnBz+2AJVDBfNkFhkfchIWRreKvIFlwt8ZJStmS+cU2Yd+5wtZdXLOIu7g'
    'C2WiFqkCbhnGnUmKGeYNjF8Lk2KmlOZexfIV4wVlvBaNVw1i+ISuGqQtR44LXiSLJVjZZLqE9PEiHBI6paiqxWtFa1CpNP0Hki65'
    'JeMyhNMUc2JeLEWnKU4zmUwxnKaaU/NqOZxmQZVKUzUyTVHNSgU1Os1cPpymVJKmE+l0mgSbIaZA4JCnSlZNI3D8ySIUkJ4nRX8N'
    'OFD9yRr4K4VrwOMZSZbVQwiLOsX5D9wtLomXx1xA3B4riIoDXD/yPGcPMEeCHBYk7Y5piRxSmUQjYyHlYpQFw4FITmD83foBp+An'
    'fUY3fopxFXjzRrQwArJeMLXZ91RyRx/IFACM2iyiBBaRTyvGfUU2IlRUORJTOUtqqLvIZKghppOgaT0CDgSCKcQwaFacsODaI11X'
    'ZH6S7KE0zqd5we5mYZgvrqWjqFpM6xLG3MXWY4Y6Yz4VH7gKLc7JMUn0qPJTdxL6RQQEFUZAlA2KHFQn6qDCu7/X0H+VmLN9lISh'
    '1wPG2GLmRoCZXdTTF6kHu/WKLv3h+z293wdOFrP3NUm+A0uEIkH7KSzvK32gXfrtK3yQIfWtS2wvtrgP8/gxY+qcauNm0JZN/pzM'
    '78JXMQGqtnHoCvPM8NWHzikhZaML6KiNzGs8QljtPb4InHRwaEeF7X0cC6AEwGno3XqiycLtf/9/DxqcAB7bTXKFzxTQ4IJUD46p'
    'oyeY/wggB3zgFx/Qo0ZC/wzHKEyalNyRfEjkXUI/FDr8e/yyZ1/29GVPXygqQ+gQph5uvFg7kNhCMZUMRe3PyNO3P4tfLkgcmYQf'
    'RPqQ4R/k8EOGPmTpQ2Rl6Sv940/hgr2bkMCAP734kaWI1D236uG/dnihwf5kcKr/Khzgyn+Fvh8n8/v8mY0GGoCvK5R0VlRKZv19'
    '+RKqPtz1BOaF24lTw4BnDIsHMz6aejrOJkgcIKIsD5k0j7Fs/iNalqF/5jEiS4YRCi3cdWTjiw/IENGDuZUwIrZH7mkXHH9MfWaP'
    '3/z8iAqBGOWGcNQpYA8l6jtCiAZlKRjolN1FwztoofiPsbh5h4Fi0FdfiXR54YOQK/FbC1EdezDMBF5dR64UfiAEazBtqBFogqex'
    'CBDHabyhdpC0iyYqemAcGCeQVH3+7Sp/MEsmLixxgWEsSxqLr4+gO4UxaCQB1RnqOe13RQ47rGfqAl5cAz7HyIem/9NXKnJ4mWvR'
    'G8p8mbwThZlnBsob5BmQkDhyEI0ME38wORCDmZtbDFoJBIJkLKCYf8CrP4T//r+zII9MSxhztZmBwTWW3EuCCEoEH5hbik7JzwH8'
    'PHJrQaQaIBpOCAL0guc5UNL4GB4LxbmTq0nXSbi328yIUeu/nSBRJCn8g46BUXOZdFQ75AeHjDG0N0F8x0wpRD1wBL9hR4QAYwwD'
    'ThD1MVxPJCcoxFwb/AMsXQQoAIA4AwWzERwVeTX54otGFMqMXLCIn3FkRskxMkogB5G47qwNDH4517hD5VTdonwdzXUSVnXpgrlv'
    'T/uJx+0M76uQqlQRYn/gpQvjjyvfpTI47ivgEYZ4Yn27HrIKqs2ca6ht9GhkkdewaWI0/FHIOt4F98yZStdhSGR2AynOjzrIddU0'
    'Qbr6IQl42UXnqMYPTc/8cQBgPdUhZz80YUmBQiMCeRT3FCOrxqwLwffBwkhIOEeyQ5ySAIIDC+Fwj3/3GCJ04r83+HuUdCMOLKiC'
    '0Y9hNALPEUr5u5DNpDnfCOJaztcjTnDb/IieroyueR+CmJgnpg+K/zslPRg2cSFcsj/pZJaes/iYp8c8PpbosfTlGBFieM53jmXo'
    'vD5n1pn0BUl7vrn+BNdm2EWxbPoI1fp9oL4kwGaIYLNi/AhLcosQRQCkjQlbeMM9mr4aIzSiBCfbpsU28dT+HuHMRLJpRkrtqdSe'
    'lZoflYoysUC1bNw4mxUtsRsYnote+Cd39f2/AIQsX4nLEjmELtEIm7pksSiUsJSALjHLECOLhjkx4ei5Kg9HfnUUSYHdcEkerSnz'
    'T3+gcALRMVvHYy4gcjxhzI++R+1WP4eNwkrQ0WD+kV6gCsX182iVbbbKYu5obT1aW964iH5gCDWwYBFqFHp3EGyRo1gaNoDg6zch'
    'l/ZZX2zwGGtfsiPGvMuI+4RD8Ds53aSTaYpZF7mV78InOkS4cf5pcq/9U9YOTbYcSeOHkI+ieFv3D5WbfqPHAkrjzUkU4Mkx7koI'
    '4qXw4LZ+PDEyWF4FscIQczCZPKwZBCb7s6rhBUaKxPWvlZu7XqvDRgP4HtEHmotYeQqKS3HJMKZuIay7NiiCMhciIwqmE2zFviM9'
    'vQ7t1YDviK4RxiMyiLEmmfKoZfD0aMzxk4E6WZb5M8AbSCLdQZWH08LLzLiMrFase8l4R8ACIQ3gGig/Zhj2w/2i4uRqTE4lf+CS'
    '/oEfLvwEXrGwCfT3Noid4RGv+XWDI5IIdOyBZWADoRbInmEwqZjfR/B8/odUzBgNmymY50R1AsUj+cSQDvko1RkpE1jML4qETWpo'
    'lwoSqfJVEjyBib8kJHjjmef1SeOpOcwFBwktv87GgtmGdlyXAp9JR/cXUMdB8RkYzWO6Aa58RNezCwwS60YJ31e2kEEUabY5PkFi'
    'uJlb7ddaWGxO0HXONFUsUHkYiFrV73jwhw/UX0guUauO44DTHAXuz2QGppOAEo/HkBy95JHqSPY3lHOKnHHynmL3YTUyvLxTkUX5'
    '+27V6/8AF4DksB3xB1rGib6yVYQO3+dCCGMRO0/mwKgX4HuhF1ibUX5ygqbTCD/JXkX5yUj7IUINRfqPEYVLyKVEpJQdKQeOeOLr'
    'YBi0FqtdoBT4dvxqwlftC0O3NJCg4T1rOMpHnzQs8UVehQ1Pjl75DXPBDo7NDdv1JS65DwfwSOwD+vF/+fRGh3dBFW+PKiLc+dWM'
    '71VjDoJU6ZOQRSfPiAtlmqKB4YA+HcmyNqLg71LtS2yUzJhi/NjHEETzD3ygf9Kg8U6D4gXzDxd9COWSPhJQIJ6BEu38PJI3wMcu'
    'nrlGw6Qf+gCjhAN24TB/h3SVtA4RlUM0HqCEJ7iAHjPkxAWs6FzSUVzLJvPBW5F7HbZR3mDoG44mVY55mkU3ANCCVo9HVA8YMx9x'
    'sYpGPwyKQ9fLPXYDDQM5EGFCQYJau2SSKuuIYh9yOyV0gFTUC/UZIA6HN8z47QMy5kFRtNAiISMCwI43s5tSyCphBWvFunA9dokg'
    '8Lqh8WGaGaaz1Ynp822YbIzkqwwEZglSnBK6MbI5w3GpM/cPkxHyqFJDswJOu850Snb0RQAx8OwELB2j/A5hA2gBocYhHIA/CHpw'
    'C/w+OXvFQQX5ihhVYhwhhVbkP+ufYWl/E7JfsEVqi3GGfpn9URmm4Y3IUr7u+gNtPuU3oAl/pl+EB/ye4FMS/WAJVNhPdIFFECM8'
    '4fcWfMByibAagiKPG/P9dhN/sd3Lk3a/cKj2b0gSADBeIExLi8TGBQYEORdDPfF4DY8Bgpe3BqA9pf5CjARi1pPmp9pgsVNQQTnn'
    'Acc1zq6ghG2hdkbxXUtdPQhAHnRH5yNy1HDk5Jj7Ew8ZptOVfnLHjeoUfMN+uJf4sUXRPuDTBUt4+w4AOyqWufuMUVkRKk4kTZTr'
    'mS6NnlC35z8nPqCfyVuvPfoYwZV3HFdGIJ8JjdA1x5f8B0E+Vo8M9wofoxITB1Kuq7tjZ45WjH6wE5MkH4DYGxxNSxFi6Y+YBiO8'
    'O+pFRSb+jvcehAUmGhWPot875gnD1hupACH9eFiBqOFpFb+8T3Uujm4dAJgzFuyOKbY1y2et7kgnDfDOvgcTF5lJAz74JYNPab9t'
    'dvfQCiFrsSY7ONm2iJ0OAJHz3yxary8TW+ZSpbDb69ncx+DJP1uXPwUDNtcQEvjvAA0CWKKr1F9d17/SH9U86pG9edvnO3uDy/7H'
    '8y9fcSeSO3TLo6f9N+EOH8XgpUgv8SkTvMsE77LBO0TF0fstKKgGnpksvjQzxZL8CkfrD6S+sBeX+ApvjO4/nP3yFSl6NpnB1vEx'
    'k8x9O/tDuHrbDgvL/Z12SKY/aeE8yqEjhDwy7iKgErDscRb0xUIli/LhDNaHUDrOkHD2N6HBX/2YegQVfkw8vt9c4q81d0wzvr2e'
    'kfsTrqP87Yyvy/GvSxKPPpyJwQtcWXQu+3BGku5Z6mN0FyncmM2WRdYcGTWpO2wSwBAalffseQ/Pjr9/YjJD3iSlb5HxoCj3jRqP'
    'xDdH0wGTY1UM0IhRrd1Q8JU8T8Lr/KFH4vY9iAogYcsd/dGzmvcCH1kEdeYr4jNUQDRRA8MlW+4HhnG1Gf0D+grdT7TZjPKRIAlh'
    'XueBlPopAiW/fFWCiaI2JrrwvhD7Zv1xpRJC+dvRNsiS5e8CSLySrHmwvMksrloAwDgQIFp/rXv5O3272+92DM3BOfrGoYD3xmSa'
    'T+G5iTH85uNwrh2Is4OKEg0sPC8TPx26L1mdNNdlNmcf93+3SY4w/UYRi661+L9nXSi7Cc8k+WZpApM5qsS3pN6NQzu/fJ1r3jem'
    'hvtwBpy7azpXZOBQHf/IHLuTB+YxlkySuVlyMiUBb6IrQeCiANID50f+lWd1JAnBNDwKmadF70rweCZAgtkN+bdBSMgGyAKQUpQB'
    'PwIJHywzAVKyQAy470b1Z1zzho5YLOmhbJqOohmY8y0prLUP7EpsxC0bA3v6ed+4I3c0LAb5R661C4H75gT+PFFVEubTY15en6nY'
    'F4aNglBN0U3347HguyANWyRiPUoBfInej95kuPGInI420eAeKBWPOHEGbtdRPQsWiL/b6g+CFrH4P8y778ip6vvRjEKHRJLAjqL7'
    'RIpOeVH032RxfD59Qp2TDMKJg6yCvL9iQV2c9NVba5MTWpscjB0vOCJPJkfsNLphRpzg8feF8MaVkxoJwseE17kAxMgjF70gGcgY'
    'GDGD/P5I74qMWuAz7LvHXjOlrUTXiy8404fC8xn6m7HzHb0zEL1Tj22EcXxJEFDpqniUFWBewsAGYLZL0/CVlm9EDCIiH3iR0EuT'
    '+8ZxJ7leEkdFHmzmUfztwDM3DPfkO6Dg/eJeUg4i7sd/tPdvNviCYgfSfWT8/e0fv3zlDeEjjoIxZdxQQ0uCYYy/nAo9hCLCz9gk'
    'dvTLV+66nEj4DbGldIEHdyO3o971W/ggFLjfAitOCNplgfqmcIgQ4cbIizhx7OaLN+OEFPrcpwjuiFyZ1iXNDGsFy3bqHMuqxePf'
    'fKyM/9G+U+cIVpJeDZ2vsTENKYUPcX0DAPHDGQZK7GIK3pbRd4F4MK4H/ZQDtgcdlX2+hw3yI5BWnOi331PHHflDOZLK/lg7euxv'
    'bIXZqtO1GCHUCavKTHW5hpwMff56/xjj8IBCRvx9hKIcOdQluWDK+oJFCrT/Ecdm0jqzG4hR41YSzQ8UWIaFIke1qn/ILyLhAwtB'
    'mAKMQYG6Oz99MKlOkCQAeb0S/kDnzUscCa4pDg9592/x48jOoe2d1uk0delpjlG+lrr/6uj0M58FZpmYmDt2S55dTzei9q5jJ8Rj'
    'I1dEnU8ZA/xkASxPAB8+N1VzY27gMmdJynGgnvRF6HnCFOcSs0dfkIsLqruZY6J/Z4Yij3KVfKTgZVgwQb3Qav/2vY721NHcr8/0'
    '6vN3OmJK/kjBy7Ag6+hYb6X7EbyIFZJ4zG7Misd88lcaxtdCsEU259z1HUHCYDe+wzhFb7FML9Qs/RRmjz0xe5M/h8GMdqxHCn/s'
    'K73gB5VhbAtdB4+HdAM7YVEzY77XCOxnhCK88bjAH3cmvYg6XRydU485XTCfilyGnCxK5HVBvheFAv6boX+L9Eakr6XMl++7RfDh'
    'eZwrIGi0OTTaySBX7vVRdZkNlIF+0lGVtazGkGYxvZoM28jBFO+zmZg8BIXyCxaakg7JX6mVi/MaoY2fLpHl48eKMFTIBQtI0QvD'
    'xcSvgdndOb4By2uKce5SEXVbY1OjC59Y+Vj3zIz1HMtGNkh/mxkCeT0WBD64G8t8nmZmGJwoNMFevLWuRtCuFDKjwK+zyPjcOzT6'
    '2jMjfINESHPyPh4PzKqAsHg4L5N0hX44L4kcU/xfeC3Rt8uGBsUmhXcDfjJ+4twUf8ddJ81dIwN/HebrwRc6ApHkrIN6Lr5oEore'
    'bOnQsuFE1b50QUcN0ggwXM4DQePzEUOkk88sZ54/CcgBBIkDruAntvB9ehZO9R1ahlXf5CcgHwyA8gyc24BeMacMluOYT9hfuhNS'
    'hiWJXWGkLLRzX6EdnCI08bzdlMBBU0K7N84GY0d+4/Pnd54YNuNWqigG5Sp0NguyMumah55vnjTjkVwplFigN+V+f9gSC4Ec3C3n'
    '+SHwhnaMDTOSTpsP9M1dd+Ks6bYM6v3EvH/Kj6LmFNJpEKXfxsQ5zmWDLQVRAPhoLgSxiLphb3uS0yGMJ/PjQADx+HFHxxEavC2F'
    'tiuwgChvYyEkhBJztObE4YgysKusK6K6nATv6QVSxyCOgw/gjDf5rCf9dBlo8vYt02+RNudbiHudCe9A1XeUEh9/RxukQGwr8qzE'
    'siK/Gmqg4MdcRWkKf82Rld2FKhBgCziVZxoQX5PXS05mR8rF9wGZDieLWK/L76igvlsLb7KIyQzx74G3nh+5glKnen6Uvz9+p6Au'
    'NOhVMpwk3mPGKrh3MY3dcsMpYOlLFDBRhmDH5gyYBpiqZHiX6FGCvcBKoveOpJ9R0IrLqbTSdGqY4JW/xVhixPi7/pstX0qA8XC1'
    'cO4gFaiuDIAIYgEO4eMf4XVeDAnxe2r2kUtR30J/C/8UYtivHxzCdyEKjsUROsb5E2uaJsY0HeZKCbAkAzN8DdTkJPMCMb4TJiyg'
    'UwD+lNjP+I+lkfdv8OzoUmrkFgw7L0YycgOG3Y5A/B7enox4l7IYZAyoKGCCL3S4W7oGF5LQGU84Rr4w5HeHtJyHVvPrXYdNMY+6'
    'a6ZsRjpHfk10zxLTD3IWI9imaPMUd+1t63g7iOkDWKOzJPz5dHLJK8OEorjfYS+Jd+Po9lwuf9xt0H4vSVcAT5oVkwW/EXhFEeGO'
    'GyNCiWsUyUP29nZaZB7nEY3p+TtL5XcWrgQLPEc948er6Aiy8WjHDLTxYmKP4k0wDQmFfw1miV+jTICze3u3KvqdpnJDWh3m6k+3'
    'QFzCrDA1RyIpMP7mVp5/LYyjHVTy81dc/DdIAlNCFYBBkpKyD3AnB2j8vWe/5/y3jxGmR8jTfc8y8A3+oXF+C3HgFSovQoTuDyNA'
    'eMoRaodhHCF3GEYwRGf3HxjNkbaRaak/CNH0ibCZx/FBr39iEdZRfRElYkz1wmR8P8UCZsk5+xhRWAVUIgIWYUvR9bgUCuFysB/R'
    '1UDiniEtExv0J/QDRq/f02X6UcET8ujgLgDHEPOrkRta/LvWGKKHb1Y4c/aOAbMg5EL9FQtBS6OBxZi9E4rta+hFfvMmLQJ3C9K1'
    'pRoyha4nsdBrMl22itwBCX0wIgcKOTL/2H/wDz4d78kMI1/SJ0S+7lFIeYwKFxH4/J3j5zMmomE67QeUdF1qAFNjhcavfP6MiKRf'
    'BaTn/A8rlM7O46dJFmfRUHbvrd/pwGBMWX4Nm+VuJh9rePtH2BPtJ12fBsaed/lOO+H0gjWKnyS9fKOKjdJHjRNIzaeQCXy5mo1P'
    'F/WP32VAVW26HwBHC3/4xyvKCmoB1tBOMIZ2ijI0H2cUKJ2J3/wRW/bH75SnkydAoQ5Z7kyo+j/UH/ZyiTa8D2ekHo3MI36GF9Jc'
    'FViaG9eCGXUwWveHs92zpozhfwJFSgrPTfTWwD4dWT4PMQRAxRGbz6/1wtsIx+6XCSJM60GE6TfLH/KiRoQXRdW2xtv9L2JBZ8m3'
    'TCi9JdQ9i4Qp5fWYvMBen/GYpQFFAHodsKx6yLLyJY1f/4BlYMcruqqnoL3eH28D/fEv0mTegjQJqjvRp714IDyfwO7p9RqhapcJ'
    'qXO0RCYo8SNfCFwj5JPQZzeJ+Z4zvkvud63kJzCG5lNJwet2BotadYyAY2eJ/FmQvAYz2QALJAnuCj3hzv75P/+vZ74sHzgYmJbq'
    '5zNICrcYz8czZzMfL3PjEOIJNuUtLE3uAq9XfhD24VKGlON0I/yUkOcJjGEU87N7EYWNnghoE3lLkeQpSg8ZSMXFt9vFSTsbaoS8'
    '/7mEOiGNdbBx9ApPqShGkcYkijIyGYadRPF7bi9HompIb1MnGCw8uJNd2Pl/yWEVMyfntBgVFn0hg84frbZ//FBE/OONiPiWO3rL'
    'fsXfwVT/3m2idJMf7zhYc7CEkdHrY7egScgbT7hxTExHlQcksfyZc1Ky8GaTIpiAYCWXzAc4YBLigAmeB/4tE3z7UWeZ75/x6Kr/'
    'gCUlRZkKcjklrvp6fKOP53XDG2eeZ64udXXqxa8ohwRzMdc85iASvWFE9nBKtEZ+UIwzYxgiWuzkZp+PDoB1mfuIAFnTSyH73aNK'
    'Oln0qPkuGJAv4lzSQkC4x7G/GTO+4aYYdeUDx/EeHkHKPISU+V+ElPcZ6Peg5SgnG46KcyPzI0FhfiIp4On0sQud1H8PG5/MfdeX'
    '67uedu8C2Fxym5jhm+y3R5w9590pChhlqtN4RE4GWg67VUBy8dVRXiDM4cXyh8d4FcmyLkIIg60jgsMuaR9BlXFMZAC2jL8KW9Tj'
    'X0YvLYtlyFTd94EnpBUGbmLJ30SDyEQ6souFyC6WGY3I/sdR0OdLvBMtXuClA1JDolrB10NG+RTCTgFuMgLhnDMpFBZFC4zhePc0'
    'Fw/QVVj8x6PL/4AzCbWLkeEfaRmPhJXwS+RGa4xcJlADgg9AjvAPUCP6xbwRUSzj6kNqi5KcBM5emCJ1P9DUbSzq3EVGANImoUko'
    '9svXDZRgDrb0tP8WF1xZ0oNPS+4SQQ5o6Hd143mONllDZaaVwnSK5ywm2i+x878xG+T+PP7jstCiZboajhQVqqYTOw7y4qhoyOND'
    'Z31rBhyrx94zJgVgnmxoAKKmInPFn+7ekHumqU8kJ3xBR7otGb67Grnj4Ihx/55VYw1DZhxinMo3+GtW2nP2aHcyYWkw8Q4gAJxf'
    'zVNXsW6v1Xm4EJ66rWaSpZ3Wpnu0XMb9gPQU15BlLPuZEh4NJcdgeQEjPwWW+uIakIHkerFzmAG6wBKiX3umixGdfXzjmFsQw4R/'
    '/tv/RolMuxJLrkUBJvAOlTTFrBN4CZkS3xzlvwS0BJ3uTxJeRpIyrlaaF2PaR0Nz5zcG5si+RtOq2UWtBTMNvj9fItBBwTDScT4d'
    'jzTgYq7SGAXE46+46wg6PN5rjrePHScMQt8DWKjYwjWNtyND9WRbpWSiDHGjotc3bPA8jTA+fKbb1sAJsuFTmF/WKB/7Serfn5tH'
    'SeSOU/8ej9aH2KNx45RpKV1VBYSAP895Tz+fLpPvkRZZlR+ttL8kkW0xrVj8dN14/9Rj2O5pj39pb/0eI8MLejyBMc6MIVFzJJZ0'
    '6BjciJyezdcTRKMSJnIjg+rW8ONHXvEAnGGEVAouGkZI5RFHAF9zGos+jcZxsr5zFzuiOIcp0ogHQRCRKdyT3WQGaBuvWF0IanKW'
    'ZCEq1xO6ym6Z6op7FKDPuovRaVYsS5afC/hxPfHTbwdOX991L+WJdDGdKRdMg9iXkUS5fgBNPlQJgzMzBx6JnEfwbUS0xedpNOk1'
    '8q7YEasI0vAats2PEgmbRVd0sEsKPhO9iOP37KoYV91T9X3EeRjTnJFdPMhxhsHoorTF1SaofeT51X6c5Qzrkqz0XhRUvA4tkcsJ'
    'NvkZ/4mIxNEIwO2bxkOv9/A5FqMKn/wXQCwUdYfuHPA6dE+4FMnIjIGE/YKsXT9yTxUj6tGGnLtBNsOTHaFEGDw7HcEou1jL4ISF'
    'E2Bb48fru2YQiK0SPE7XDrHtlJzVjwmkOcGGA1jTmeCvI4ciGheHvamABBODhmtKGFtL82O9RMyCpGr2d4aVjzosLt/3hv561M2S'
    'Ja49jYcfBpz2d0NLJN5b4bCw7/PLEvB9jQ50FqQlZ47zpOd6d3DRoc3Y0Lh1LqggyNfcBsgLfPPN+su3Rdj0wnSrHZVvCENEwaYG'
    '4MCyzvH4FP6pertFnIlhFIB6PQ8YkEBoZQQNWaEY91ZkVPhkG70gMZ5/shjWiR8vh+dPJSBKUd4K1WPoiUJBQ4CFnhkswIofSomf'
    'rcBvn4WSMUKlK7m4Uq0kh3E/Vatfly4mXH/XAo0Y8tjR/yT/ZSSupPA7iwWJ9p20H6/rJHiNH2uSlUVbULYUFCVV3LcgbrdGcaqI'
    'kJAz45QcExEny5QWG7NKXAnSVtoz9YDFA2j7GRM5C4aJb1iaIXb7nPveWSw0KcMJ0Sj46BHXBAbVemfBeeIDFPQiCQ6jqPPn0+Vm'
    'ySDDPJGRtKHLMAnpMkhCGg8CVWHYjg/CZSSP7IWfMfqDnxw24I8jmVH/P+LepL+N7NgX3OtTpGhdAxBBcNBgGRTJ1ljStaYWKZf9'
    'KLqUAJJkFgEkjExwKJL3d1e96lUvunvRvXmLt+iP5U/S8Y+IM2UmQJZc18/1s4jMPPOJEyfmKNsTeHlQVfciLd+Y67TSG7tJPlSj'
    'sXM1ZkNjy16yWt/+eGKhaVKGpoln6yup/miZ14iydL7ISCpE9CDM6NafwA0ZPNijlhSX3ul+W6lYVkzX2L/BrAhSd20gX/sDZMt7'
    '8IT+efiHNSTz2l//Az0E3w5acy1XMcKVuUarg4QRIo+tLEIexJxV+8gl9aXdxJTu1ETYGsRwVJalL1sz+gaSuvCDOPwETCleAhMX'
    'nuvRmo3TZyM+aYpa3tMnWl6tk8tFJbWtFH0UdoejMGFtwtRUk4bFUGXCCgz7SRoKrVprUFxr3rw5VgFBXim7FLXa6XToPU5ZwhkY'
    'x0cv08NDGOYkrZYNCIzsyl4ChUEsc3ImeBLTahubTQgpWfkjm9nmQVCrS467y/bqJXkUW9BWjGf9xEQS6gZqB8CbBrxZRkCu+z5G'
    '0fmVEu8R4fkCmE/ourhwJhqX19XkyRO9WTCwSZjjfpAQdCeR93bzBtad7mPxRR2YzANlx7zZGM+5ZLnxHGVgGAyK9O1gebkNUQKc'
    '2ThYjMO0PE4umBEo7BvbLMwSMv0ue3Vg6bLcxAmiX0BWjNboMTWOlV0h9eXYB5QwgGBifF+YIui6jMBcgE1aZUmZ+BBWMh14ZCwe'
    'vC2h5Qh2RHbh1vSCt0yVzW3VetGZPMdM8Vk+1rxtuo064mATYQQtzg4+zOAw6hIQHxZqhs10uZgXY/BNXn2R24Qz1pzSgbQqZ5Dr'
    'z6ZNucDswigWzjk3K9iKLv2xt9G147MsK9g1ria9Cw06gIiZRJYD8M4g3HcJqlMJQON5QIhX6FTzFXhkfyeYw3vqrflduwUustfL'
    'zpsELhUA99xXNKVyOa20CiYYU43YCtfljR55eaNvdR6cm8syMmKKXayTfHgHRK4wWsIBVUaRhj0vllDXU1GF/e+Bwloo4s0GQbdy'
    'OMwkKbBNkZXAVYXdeseZAwaRHWCvUXiYxHBeSgv1fEeQnwlyJhbh7nI64F99GpmO4lpyhGw+lEIklAS5RF5Lz8loUlxIOMWqYXne'
    'p/7HJZZLgt7mp8TyDOHn9iOnXJPItyLaBR0sklyJfevKvmEZvV/4whU2jBInRuqXXBEkmij9eYobh6167I0bc0iMGGEwUGJ5i1Ne'
    'xoUZbF+udR5MX7xUeQjXnp/qroiEYhOcQFJHVoQ71nnVmFZlCFELFYYIqxCiIC30qxUUdebfJLc8IDLFC/4x7zQAHmtPg4btUYON'
    'yqlYgCSnyYi4jF21UAjYSrl6HV9ppJ93jbPrpYNJc09b35p9LX1QlZq6Y2gkhdcBci6JS0VaaqE+twLGO8YvkjEkvafCBmcpVcJ2'
    'uC6IjsjAn1lX+HGSDLzcoRDTOUiYg1SP1J2Y7oHdpLA2FjkjxBJ1nzLnhxotf4EsJJSK72OLhgeexxJMENKSyxJLL6hJDgSgDkds'
    '5eLeIc5QdUe0QwEMc7MFDL2PF4Po+InSJv0FYofF4FGBC19WchNE+Nd1GQ3a7Sdmy2vTD3LYr4qg8qB7T8qRG5mOxITTwPQsvet6'
    'zuwJe4tpRdPXlIU7U24DcWfKwhLOSyLiOBvrC1KesrwvZXK5n0wKT8gXSPhMyGtP0KdjyX1ZkY5HRsM7J+EigmUqC/RCOVm9LNU2'
    'fWKn6oELNHJx0Twc3+pWW7jJ0SG2dvNmEJ0mAs+C5irJEMcmVIYksvng8iCmHE3AHGNlRFx0B22LkbgcqHEH2NgGvHG6hDDZGiuQ'
    'JpyVrWpVYeBqAoksBzjI2eOQuzb0mKP4ZQwYq/HDfaaQoe1xOAULmRJFXVQATf5U0oNgGVWcJJAL1XKuPrlGj2DCZ91t1uod1CiJ'
    'QcWofloByAl3U4TcjTcVoq+NGN3z3Wauy/JbXDJvaX4YZqpEhKcJAZi5EkFdGffyug4g4MDOt0AhIEvLpjyxknxwsanKzNXoM7v2'
    'E2tBlBrdu77M/UjC850lgyNLOKnVy4Q2OZsCAqmu8i1K+jUhzbMRMznWCQvqaYgjCA460SsXJlh8/zjoGfL7JGPWn2hiPXGrRAGF'
    'ytSk6jMBKdNC4/IzESp592wr7CaI2jIBpLzjqGr6NYuOiRumAgwUIAgISFjPJtJHCTTMpkqQYyF6MsDWwzMFH0fvZsCL6v0pS9sM'
    '0aKLLQoSUUEXhDKnFNPYy2OgyAiECnDB6xT05YtiOlxeo4ZWDukqT9hxcpr8fUYkmkG1I2pH9V/CmalxACtbGMSiJlHwqruGyNUk'
    'gvLjJpthKzYJQtaUfaSseHthABqNdkuUVxDLADnT7PGumJum0NWlkqcwzl02X4GfTd5g3xiVl0u96hUHCAfNiVgcvWr9PZxoXoXE'
    'LJz3vEBaLoACT6wt55CO3kGryk2KGsbeNzqZnWgf0kyjNFKEpjXPxraeC9gETwwsJRzTwDw+YHn9+hM/U4fYXdrKWNl9EyenyX15'
    'WMpP9O6+Gd93OkEnkh8HkWi5XZGLSxBDGqPcjV37U7fsTTw8ZHtQP9uY2fiBboQ7sSNhFzkDJghdrqlZIiXsgSlaE/P1qB2NWkEU'
    'fivNlNyjTpxalY6aEsdhZivte37rft2zSst+39CVbHg5Z18/+1ASzHNKnVCPwVdGvEb/py2fToxcWu46OQKH8ZgTnuH4Etk7tlen'
    'Ud4LnhDdmck4I6lOOHip5w9jb23TiYRMjYiPmiRjCdQ+Dm7343hg8qRygHokxDE3Lkeb4xvjKCsk0qt3R1iE7yL2qKjpg8AS3aQx'
    'guTEa9E2FquSECiGkDxe14DY8Zqk+aEaWFl5t67vlt07X5N6YpXoSgRxCMCT/LZwfzQx2hGbb4NT90FCulZRMAgdWdEt5JN4zNOR'
    'yQJY/J5o1AUkfnDIjuEdhOKSD890fuKn+zBCg+kEq8MhRY8mDLv2UZ+a4XrvRE/g/fXI+TBNS3mg5TBofQKODV8rYAX5GGDbSes5'
    'kZxtEmqyLcbpVZXDiG4xaNT0e0XvMLKtyNEQKhsSJl0WOiG2SMy+SfTSmQFelxS8HJppjopXJUg3GMbgFtSzp6SkkqsRT4FjaAXe'
    'nB7A0RejOlbwP3GeJHUhMCQpGCwp73tYw4BKLpZSWG8PfgsDv0UN/G66ACI6mnagrESAKu5TPOM7j7yOg09rVmkIKe97ETYIPZNn'
    'w9Pko5JMFeqAWftziD3XmL8P/Te8jFdyYYLIRWmmceUVqNyL6lFjMtfjXmxi+ZvpXmuU8GwqaaUCxKi+hX3mDJTwM4maNN55zOJQ'
    'xnscUt3lc3KGQ3ibMuGLcNVwBQYxYgCJo6z4Wm5rDJ/7kn9PvDnpRK+FYkG8H3a2aXmDZhsljlA0jOIe08+aJZpvWJceGgJiSPIk'
    '/jWbKxFuP07O4yOm5Y9pRhdEvfaCrPN2zz3WcpQ7Iz4jlBhZ26KnUFI6gZUqPk0O0VFA63Q6HbOTI19bL1TN3VL8R6bG1NjFgyKP'
    '0z2q4Oxq5klxwBq58H4jCGyX/SKVVJjXLPl/5KUiEHcaG/eCj6jGvuDfnJrBheXiWAZShzBZV9ejyWVbGiTdxAo3MLAFXaEL3RXX'
    'WQVIk840QJ/PW07rL1ejsYduxtG/edidsDiK+s/l75uVCEMjnEDacO/g3SnpuHV6LU6xwgyIiXMWtMRYWlapVZ8wcMMmDBS2CWkY'
    'JJN4YpZXiA5a34oWPsB4y9Sgr+K3qZ90hGKz4GmBaYmRWnraqujOjWa4UkJU6Na98Hpe6CET2kmOjAYhsuV+Bl3Pmib6WSn7s7cc'
    'NGmqNCYOcAi+yWUuDJZiYsNk7acHkhNBH38+4PB21bjcExeQeyIhNGM2GJiK0mEKRdvf5cnXzhv/5KsranYblZZRlh+fOvqZ3q/Q'
    '+7mWBJbsp4L3Iy2NXz3YVNCPgaVRcOqPbd7Dv0+9zLJrPGqtL03el7/lGDojZyjh5t8ypakr5Bx1FhNNtzB+mfnwNELLHMXFq8mt'
    'ShaXFfPRdk0fvTwyrkBd7eX62gEM3iq5Xk02OpmKI2vZXkHgkc3ZJqWo7pmDnswN9qmBHI2cNteCpG92kjmaZqVhg95M6wb9MRKz'
    'mLOZcYK0ZOVBYDnSr02H1remI1loM8JvJe4slFXaM4IDhhHn6KqYMB12poiU5iosxIWtdmH0gH6mT2rfXUWS7BOv9Eqq0j0Dn/BR'
    'dbSXts6FSb60NJWjgwY+IaQqVKEqhPShhyFSryDCWSX4nEbigVH01IaxFELKaPu7atTgifZVOBgIojrRJxUAM7t4rFRYzImLEKcc'
    'Ayo04QEnPkPGchUQSPFGznb2bMzVkXTq43RkdG2eqtmKza1M/m6topzR0zQ+8qmWwDPCSY6mHJsZEuP3RIoIe1EWEe1bGdFBqyIF'
    'NOzJr2+lTFrvg9o4ENKaFWJu17cib8+3oosgPxRY6UkyZY0FcoSOYVpL8DfDvb3xZC00/GNnj7NKoh3LPNJ9B3kVypikydQS8juL'
    'GeO6seiaUDecbqkdPWhVYFtnRE1drMucTJbjGjJPHT/G87DIvuE6JMVxh0jwpuXGIo5IQSvEVnjn68x2AF1gwJtMEW5FHO2gebHO'
    'DIj9GES+NToug100hiNAscPiWVBBIpwFFLH3xmu8b2JZtSJrIgLo1XCO+u6SM0dzc91FrZVs0XzgdbCPNgPCHNs/LDXnxn8T0HFJ'
    '7BIa/1BGPPUgWJpqrVm1eHMbJ20m9yNRk7mplLUwJf34rQxKynLaLXgpha8IL0A9yWm5qyZn9eo5xatqyJM3IjG8Kwsb2GlBESR+'
    'GnlewwjYbEXwmr6xhpXAic4DEGSs+2rtqeA/OBya9RxwHAVfc8GjRfAE/vC9FvVjK25pOa2hM2C842I4SJwNWZxWlasQrlI1sdjm'
    'Ucff6FGwY+zoV2nbLuGC5mtVwN6dys8nQdcnc7ueY35Vr/05lNVjSPkwY/2aJw2wySxZT6q6DMhpWc4bn6e5mnAwkw9ZgKqJNqN6'
    '7VGgHA8lNpK6b/1JoDWuTzXA3IvmnkqB6h6t8S+X6xgl0KHNfDk37CoC892K7/HK/VxNqhxzwFhmaHryE8zMUWwkALHE6DvqmRc9'
    'X5J6m4zrYdmMc0AexawJOOp1zoxnBJbRN1s+B9N7oYWPpfDxvMIXgb019fFU2Sdq4SlnvC/fcWaRDQCWuBg0gco7iBmnqYFX4JzN'
    'UYHQw7KmVVSWxlWAhJhGVFPpgiuVaHWstEqZ45ZW1+deSz3COUx03lNCILfW8Bzoewsjvo+3nDYTzxf63BPaVb73NiWSt/neK0ca'
    'uMtr4t8CNf66HN+pxn/yJaFfdtVmu2kAMU3uydra5FxMVUY96LKgfkQwgOjL53dR89OHH0QzkgodK7GjpgnnM5zloFdtpME+UtLG'
    'cIWOvJMYD96iTvMwHQbOf7MprhjqpNOnQkUiVlH0LCWtD7VHjKWjI6UmpUlDlEj8KvpEbaoR4lmccvnOIOlnA1tUjz4C5ODjOKZl'
    'jIdiA0mgyN4X4+Pwq1o9ms95iSKkBSSIt6z4+AwthDkhggC4JgOH8H1jpEDKWz5rX1PoWAptlmw5CRvP4F6qK/hqmOCp2SB65zTO'
    '4Tfcl0i6iM6Lh2OjSz0Omio4OiOoxxd0BBGCt7ExMEHZEJ0XmnNZcloXjpC2poF0Ayc9boaKU0Nc+iWBUdMr3AFceQqm4eQ4tkg0'
    'RKAPVHh07hAoW4bKnTU5J2wI8SscSi5tQ+INH+Rrtx4PBCBdLbhDcy0yDA7Q1mCQXp2MjxpAFjWffp4kRw2O7M4xWW2sX0TgGvNB'
    'uGQ4nian2YkHxwSNLbFBKR2KXNeH1aLuXNSDu4By6Rw5anwu+eIbWgm5J+3Rv5uOvptD3Vl8Y2vupr/QMNXKkkcCC2dCGAgpoNwt'
    'G/ZD1602LFJMzZYFnq5tcANt6kU2I2oGDnHs4yX2LKjXqF87Ov3c7AecauuA8q9YxBq/l0tu/ro1fxl//XzLyHzMkUrYoDnhwBfz'
    '4jBYQ+A0/5CcubTcEHql8VCWx/jZGzPlbJoedRU+0IfWJjQ3jifduhgVLielNszmg5Z7aHmNcRReLmMMlbOpBOq3mi8U8z6qkYtH'
    'WPn8Jx0wunh455XL1WqHhAhVQ6Nv6IiJ3TOtzGcAZ9PvXpFKO6p5acyWjPllJMsiMXBMdmAalM/JlSOTOP7NQlZZTSQ8vn7uhCqd'
    'GpfXNqsKxNLek64ElwYC87U5bCHQVPiFJXYP2xJX4350IvdNszj2VSJSdHKBBBJcytPVuDCA5TCMOxIYsGvMTthtcyKOnBKZkTdG'
    'rZ4lKILZDTa5b1vC+hBh+E2IGepqzJkST0yQ9uvJ+TeYN0xcKQyof6GFjm0hbo+vPi56JjXl+uM3x/IGkd2A2fgdojKiJffpR62A'
    'yIxaGAPGCxeiUX5xUEaJFtJom9QIyRvXIy+GbX0iHmz8pbL2Oh1MJXqi07lu1Qg+GFGJdMOcmdvAHo6fftz0MIIRVpTPoqG/A8AV'
    'kNVTrkPYiZIOEAqy5/oHa5qIen71a758b7WNSETGLk5ujoCV4rFzfgPkP2+yCc3dIOwqo+wOIyqrH4p7RMNmsO4BfSgOXLDSBRPX'
    'NIE/JPUx64XFRBChb+A6kgxaHnMi8qPLm+VGgZjH5jqRy3VsE/ctiCRTjsUSaDJYZjY2mFSWVu4UCVtwR2R8+t1fsR3ZmK7N9eWW'
    'WddNQo5wKQ6wYRs3sKPFaO0rxbA0pfgvSQf3xc3xeYwbqsPpbMMvo2uVBEwKQ3RSXp3SQr5L8yIZU71GOp7MCqLImhLXNcSjdr08'
    'CAyC7VDbc1vuDWdT27BPDCyqdJJcQMhF9RIjPka+02zyieAvPmLYcZNNOpz/DeKbV8SNTRKO2550JrjdxsXL5DCeDcU83vVvvF99'
    'zwe/IcRla0hUQ4mV9Kfk4hbNLmhyL+7NHZjnDOUWvtywJyx1XpgDIXJoMUpkDhsIHyfDCfLjzCFwiuxHOAc3AzYSsnx4qBHP8RzM'
    'Eg3mBTurfabbxpANzuuZpii+bH/hbIe4cuY6vpmif+WiMLSq93rz0LJ4ZNrAKudrnt6xLSGN3eP5uu/JD4VA2bN/gQny5a+KlcED'
    'sVwrtAZBNgfalfMgUyT0EyY475m9wiOZgW3nYq0dpoCgdi6Cdi7W2zZ4sCMFSiZsvWoaJ5cjw061OoUwaVrdFML8a5s1ww/zodUN'
    'P0ytVjP8Txi+y4PUChnZdWFkN0z+pUs/mXLUy87YxGNWiN1+6txGQGZO0j6BLrNQd+qyiX2SvE0ba3O3WVTlj2tX5++8Oo9r10X0'
    '749rV+TvvCKPW3VRBc7F+xdNnHUjVTpxChPVMcmBwepMJADba5a26u3v0TdFYIjluzv/qEfec2BtR2+ClyqzWYkespYv6OpHK3l8'
    'w7+U3gdLZo3wL2h8TQ7vBePiI7U6jnstKKfAYoqQmW5zE9nA9uCTW4ojfIFR52Hby+jXWX/kJfX7EaYePRu6BpPiF8f6QukDJY8x'
    'EyG3m6U8g/c9RkGp5C1uSwsHuQL9wkFYRA+twamRwG1io3hVg/8YA1SIq8LAP1rlOyP/BLZtR0EQn0nHhfzZ8sziH5ZKuWA/W5ZH'
    'oVIuyk/pLpKsZ8bECHQj24OrviK8nDhPJZV/nw0SSwgyPF2ySrYtcYOvNc9z/zjLcmMLWY7Cm3mqLBClnO1NFfE58mmhqSOh1Uu0'
    'vpQqJapViYPwwXU9ci225LxFgClvlv7Uum5U4ppcINQlZwcBhQRyqdlA3RQCNkvfm0pWpPSCI9vWLkvUJEKJfaWYHm81StGp+C0v'
    'lt68pf2oGZV4RpcGFkYj9UOQgIz22X2iiOiQcJcTH0vFzBuZ/sV9d3HLLvv5+3uXscRVjTsX19G7e5cTeSQAnp+gRNJum6zcB3MC'
    'HT+qy1jyh+jRwmD5FW6T52usFQIzkWDGTuMue2L2HKYgLp02P22pQYfDmMiZ5x022BX3JEUecS/wtIDEjGihMfy7bPxFVh2fxcjE'
    'Bm+oQXp4mLAzneTIam3aRHt5JD69uIL5pjU2w8Q7NhCRsODA/mJUL9bPsFjuzI+YUhcOwPpkWzmbHBiatPHfV6950M3KL1ZMBSJz'
    'Nt7x9DvRF82tikizROKNZ3woRPZ6nJ1x6AJkjmnUYbVRhsCvIfbChVnlZzTOc5mnEQahNysKWiFwg2u3t0aA6biLjVsxOarjsyex'
    '/LDwY4DM0lABMhUXXFo7cdGCEAAVSqY8SUd8VDs8IqztvqY2OjD6Dh/WiZFeLlhrkSeFRI1hDOtfSmGkMc5XPK8XG7r9wGHCYS5R'
    'fQ2+Xx7mtkNb3gR3YAqHvnySHXoRT0Ae0q7olr0d1LrZjxdNnQN4ewMaFxJ+FjC5PHaz53LVgA+IQi4xdDmSQ03vw5MblsRfjRPt'
    'XPtYHp4EqxEcloWhBVTYUd8rfGUP/DvPmzIdNNMjit0qxIWh6W1i2a7mBfEvtJRDUcCgIXMC3KMFoxT7IG+cBYteSmZDy8WRHbB8'
    'ql2PG6G/zcbTjsduizlc9DIu1HSuhPjmnQ5XbNAbqlXdCod1ggK6A5uKB4/WJD2ivkvFnkUSM3imsD6zbgufI/Cu48zte7a+fSxm'
    'iPJK7Mq6PA7R2tNY2oyPiVWxjTPH4pq0+g2qFuRoH7jwF6prMRFES4GgPYkH020TU87EBJq0HNPBBqQuyWzse2bVoJlwJFivpBMP'
    'jbxHfCqHxbLLVhF7BJWJVIA7U25D5A+444SWeh3Vw7uUs5jKiznDH25GTTdOxyz33MH4ir2BoFoj7oL7MW7cbjneQyQkOMPCBUfS'
    'ATvTEDjg6XSjidGEUavie8MGqmlb3az078VBa4FmrC0WK12jeFPGJxiQsY72FzWQ55bHStcgDTUP4TX3AbYdndJXYQrp90XX8HzX'
    'dseqFDk1O7aELzbiNtsHbmkhyYD5l0kGd237ZLPDMyFPUCYp8K6DpRCpJFbDAIllg7nMKThgH1/w2/x803HAUu7CK/dXW05NoHwG'
    'uPZ+L+PIgfGnMA0BnlwEC+Y9vQ8XwWQ7YuEU4jzJf+n4ckJqD/1V8So61UxgvdrmwJBsusqFjcxePQYlOYjnNCi5QQaB8TRQKNzh'
    '2PKJg/B8kL0wTs11wZi8gA8cxc8ZgRKF14BbBlGtU+ghUj9uinqbak4cltHctf1DAWGlDzwCE0hcFsNlIeWqVJz+mLjhbswm5suO'
    '+dyts81teRIoeou0OU2PyzagvNMRUC0biutAS7BtrKZpaIW56UIWUROU8ws9/2oT813McXD7Vwjam+jY2qOo97keok2DpW5irwMs'
    'w8dZzvJdyUhJWBis4N1Bp2LWJmffbm7pfpgL7jWw7oO5swrSgEID9kBwHemK6LJ/TlbioiAmMBk4RGkv/HoPCw5qNvBB7q6Vy+Bm'
    '/yWRsD9hIUMPmLhCRviUS4zLvMuGIg1JegDehtWX5QNgtqOknBvcRjm3wNB7IcqfTYDw5azcdD0IiN6i/NlxIuWcPq2ihboV30hL'
    '+hHuzO/jPhLRZyt0GI4I5eT9KcIPEuU1QdwJG/CPyuEO2Iwm6Vi8L4mCG7Ojcx8xaXhgLUR9+Mf//n8vSyvRL1k2yjteyLK+auJQ'
    'BZSJPI2SIlYyTa+uFdAvg2RYxH+x15R799fN2uvIQ9I36L7aYidb1XipPWxFv+VO+skGtPrDeDRp6i2kJiLJ+aS5YgYIi1k3S6Kw'
    'O2tiCru2tv4INo0i334QSq3Zya/J/xq92310aFRq3o3NDoNN/tco3uqKAp5PNqoCbBhoTWBwcpooURaJ6nE1esmmAWIoK0G8DGqF'
    '67mE1cwnMBFw4d6NNkYKtjjlWxx18kmKqDgwKbNpuRAJVJBiFbiBOyEMtPBdq2OtpdoYPQhC5Zks6oIjVVld9jwM7Vpc2Fw2ueE0'
    '3qIDz7mMgQ+M4x4neUqm8IZP4CFu6aPD8m1wyFeH0FH5j2lxbMwzGyVtaJlEE4rCEBGK4fFyxxliClHQjg5hAhqYGLJDThsMwqFP'
    'rGOXX9OYm4dKN1hb3BrsR5dJhSyea5yDxdnvdDrC/E56WTwdwCB1R9YIF+b+QetAVC2HbKewYGXs6s3T5dsl0IkeztPQnyQXPJZ5'
    '2vlxfGpp1zkBmWuC2Q9Kjrk3arw1B7OQURzQsTbMyKnLyJwLW6T2a3i+aFu/61MYmA1AEJ/CigwZ4ibJdGIDEPTyphRhHMRFzj2q'
    'Tpox+kSuuW0dsJFIu3ZwxiNXCi5Lvft+Clgp8ZTWhwO/D9h9l15ZD96xs6ZxEd+NDIuda0PjXs90UuR06tW6O8qICB8isvW4HXFg'
    'EI6dEYv3TTJgB9U4iGTXz0a0TYgQwnpQCTNMu8aR7FRzfYx8LXSDTvKWeK6aa7nqvRpaddbHdSxHuxC3SCYea47Qfp92vH8B6TsM'
    'tHbobjOukYhv7RxOleoapYOV2Ln3xumI4VBCLKcgu46TGLer7eHWKmiJePQQlgac8pEVsSusEMIS5Y1WJzs8pENoNdaw0qyz9WTd'
    'vrWMbPZ98w2x6GQNf1BiOSjh2rqwbbFBZ9834ZC2LtbLJZaDEp7vLOQvsCUdZsC1NOGUIGkUn/O9c5xCRJfRqaA3cPcmlm6HrnT6'
    'syyFVCtNZZaptDxrAAxOZ9c1rl4c0T8i/ExFn2pD+Jfb76In6WRHu6IX3chz8mVWXRLJwSQBFhAjGBPQoFrKr8tXGC9cyFfZNE9E'
    'cc7EHHDcDe6lARmqK3Vu9wciHLvA7Tmuyv+0f/IGGxHc5JxsCbNc5AJwAvZosFyEA/y2IiMR/3l3tNk3mHZgkQdvN3QA9mov9CK+'
    'vmM8yiHjfs4+kMZQT2LSit0BHeyefIQurDludQ7PaFR/gBsfrjW/lbdixDuvndR8vmt/B46yXntiDAL+uK4h/SYEdVOfqak1BHNA'
    'vKoHbPZbbXwBVVFjdVhvXgiIte3QAk8vxCIgo0Y60CJ2x1nR3Bdz34MWk1OBxi7gPCQMQzZKXg1t9kvz3Up/8J1z3koqZZerj8aW'
    '24GGyoidDuFEVjI1WjVNSjLcCdJxLmxVrZlpKes6EDk7fCJgQdqqXh2jTPRGhqnhdpRzE7zMC2xjQWWSwNs3w5xHafEMkDOXDXR5'
    'UJp8EgEnrRqtZr2pl5DEZZXaCV1r77IzCGvzxHfaGepwfpk7lEBqrikfu5p7ctO3Pvabu5jbnLQwt2J+u3EgX+kzWQ38XNBgNrfB'
    'jJd3bsXkdiMhJpfom4+zAqo8HpC8+fThh5rGte3VuW2XFHbzh9e7oQkgvQXV0xuqC7abP4Mtlsbpw/KC3Qb6aq7PbWflpqor8+uu'
    'NeYzKuzDn8JWSV3LAx8/X35ZClevGLAUpB5vm8HJ9ab/eoOfmieBgFvOOksvI2Nurco3y6DUjV3Vw0bLx7LbruZsPJsKxpKEnb1k'
    '6Bu8AZ2xHayZElK0BSPaiZo18fe5IUxAkj6fyOlWDy1/pU5utva2ukzDxQVS0FuhPj9bT339l5KPwtuB53H/hCUwC6ApTG9R37Lu'
    'pD5F8zEA+9IsmqKz1g/1WoGxk0kp6dspzLcguK7t6dl0mp29Sw6L+XcJMdvI5LM2Z6zcwmdwFAubuKmFL5OF1deQXn1RfSjhb2qh'
    '2kDlyN31Vdz1uGFoYqfoRrLeXfWwkmRE/ELoLMwTcNClg3P4e75EWPRrRHtbrO3VSNsiM2RneY7yWXGz3+Po7ZyEhDjHMUe0MZQK'
    'njDJFJGEIXmEmnioZl0sQeQSbN6GS3Cgn1HfBcL0Il3Q2d9LCwhILAUIdFDgnTUEtW+sNIh6+gDmxBrh6gvPVavTlNlfcbbre6up'
    '9dtS7pwDs9vomC6TVHMkSw3s82XM/Q6Q3X0ypH1pfCWAQNRI8VRyVkdozcbV3CLmxAwt+LLNGE9eSUxGgcEOkhw0iRZmdNfgeAaI'
    '9CIliRRf4UgQ/KhSRm3+273LUnMbfmvX3JQpY3MKb1yzMeI3x5bkw9mRZSSablvciu7/7evZ15XoYHn1iJcycIvjd3RxhjQdr6Fs'
    'w4oBqdamABmsRM4QuLfI4EqMENqQD7ZFQsRWvV2UjNY70ZuPu3tCY9Llc5rGDG67AtwvNV8OsXUSl38YzxBUBqGtJG428mTnHPNB'
    '8savyh+C39UI9CygfZgdceR9zpokyeY73PtGJ3pxPM1G6QynASLTaPeCeJhR9KzfT/I8evbprZR80Ik+cfImsDXDLEa8az4STKxH'
    'zdfpNDnMzm2M2WCsXTsmUTWzbaCkeOrHEmld9glLgXAIKRG7Z53dT29fvvr8E14aTo7qf0pZRXaXyxL+aeTH2Rnax/DxEbQCDVQa'
    'MRUn/GHvYsLHYh/pDfP+NOW4gt2oocttthFxqJEFpksorQGWOpVxruK4NbrRfkOxT+MAt8SB6eX123evftrd+/j5FeySQ9joYrka'
    'myxvw89PMTsIi6j1LJ7S7r80a1t1uXDawFO1LOAcjXgDUQVhWVoFIIlSynr32pfdCUdP52BHUA9A2WAZRQ2M4OyCbHq2Bz3G5xCS'
    'UQNoCuZp49GCkBc5W4a06XtxYylOAjMSXcUHGWdjTAPAy4KTmRAxwzaT6FpseouwOL1obPLrsELjH//5380HnvWWm6gY6uYNsVCj'
    'KRoEwNQV0QTN8Yhz8zVlzXeifWqH88NqYLxgQVwHah0ANMDLXhynuV1WSO8sLOxE376O712a5+tv7CJq0l7Kkplm7Sgwp6ghJdHa'
    'nD3dmfdFMDLCRLhGGiHyaZhrACeuJTEc+OQOd4tsCsUS1BSENJoO/NtlE6xLC/Nt23db4feaiToTi+G6lP+KFTljLj7xj4zIGSKX'
    '88pOVkHDP2WoKS/emGpS39ezi9tGcHwMtmv2hlmvze2WXQrmgbPmMYs7dBkczgmmg1ZBgXcG7uTL2GMIqvtqoE+rsJeOEkTxkius'
    'LqCJdESnDDn8PJEcIfuUXZv3xPVWWihtT5HxMouhnKzvuhWf2RZsbShcn9PYm/tB683WQdsZx1XwJgvNShFD4knanDBU9DKW8oZZ'
    'aqc2PMhhQtChRS+jUULXDKLbfSKYbLRZBZBMc8bXeuBXgOwbdeOgy/wvKwLjK3u0hsDogG263ukB8W4xlooVIV6amMoyup9d8JIO'
    'WiaCgoFYd4mAPiFCe9otnygmL+GDDGuS6YzNcDpyWyNXzBEnScwkyIUQvg0+JEbCN+1kJzjEP3e4fTqTdImf8a68woumfkAZhHGI'
    'i1mO/fEdbn/erIZvAbeb7GVNORr+PpzZmco3heQfqUJsQ7RJgbMON9O0kME8m/nGkjUL1Qx02qIccf9s+14Wu4ylG0p1fBDZfTV2'
    'D4umvKiCeHEL9ykXl8bgOVAWBn+4rCAOHAG3jVX6dzUXTf4l45iuh+agQu9GpQPC8WjMzKc66WkHda1ssTpnKWhlKoZLeKP7ZLz8'
    'ZI11E70CfqybJkFGy0a8oYcO0c45xMG4910AHExLwwcxsSb6NoJK/iCCHs+/1MgH52zKs/x7tkXRz+yIbuZC4lAYHE/bQ1yQUFjE'
    '/tBNT7Nxl9qOK9ll6r/JF5uh2sIbTXbewUB0w26vxDlvuB3Ygr32AlfQsRVhxNC4NMyBgprt1y8aF/qmrVwgfFMCOph0PfzIU5W4'
    'bnoT/8D8s7cOQP15N6C2r1t2OOGweeunMnsVS/SyacEYrNEK5OzXTAPpVewhlrbrO0Ap4VtZnxKJTaST+a2r7OCsu+AboCja02Ng'
    'U2fTubhAeknl8uDMxYyVJCyq5ecE/iuEvxgNVw6RyM6tGKECuAtAFlUbJlpxAIPoUkdEUCihlCrQWLd13wFxllX7qMY5FVZt/kHc'
    'Pz6w86o20bw0YPfbsXVEIvCNrvydd5L1rPhLJwPTP8cwZmAgbIlUC1B6HN5uJpDMP3cgwHAwT9lytGIt3KgpFFPt5VEf2jEeujvG'
    'ZeDzygt43IIQ1/AaQIntCLHdp+EVy/ErRWqngXYKQ5tEUl4R/Z+JokN0FlSA+xCzF39+9Xn37ccPm35To5RGSCQHF6y57HyhvQVd'
    'AjyijOgsZIfRh+QsmWKZeK11pwlD7HnMGh1ViPkGmvOTrQ5pqKcySJjWhGccAhOOPj6b0Lh868OGdtCNlvYQYU7kKDkkI3GUByC7'
    'FOgD5l6Uh8NZfmw0lCVvWNj4fZIACF4JCXsEA3ch/HnlVFTrZYev9/JZEGxYrKifDYeGm6oJOlzD1QUk3zGtwJtslPhutgIXxCJ/'
    'FDmZCP2IVJfVHag71VgByOxKkwVPhpZObQJPkMpiB9BiNltbNVJJPkne+aoq+DUHgLUS9W0nVbNtrSbdKxNer9HYNIZ/vq0ioxkO'
    'WiCSswHsBVkqZwVCIfIH4w3dDrWrPIdD+2LXGTAkxFu1EScV/KGLo5cHwrqIrtbTRCMicIS9uIfIJxjnnfCyOQxPcSASOKqIBFqt'
    'TWfs6LHmhx3zsOmz8PL6AzPDRsx12OFfrJlx4gJrHcBWJSpQJA4LUTww99W//Q6D32p2llv3VjUVQmV9794dWbsBgzI0P6kRBe0W'
    'QDKC9JA73nYGCB4bc6KodPWu4KvHIEjM2y+f3yJNajaGrGC0v47sS3RfHNMtP8VW3eJqboO75MRrldvYpsZQSWpNLK2EwD+ZMdXh'
    'oJgPNi+2sj9CTddpdWp0NKKH70YISyyhiCGeZ3VDJur6kj5Go8cMs95e9pxQ5eOHsI+kRyNj+ATZNIEWUm94x2yqgYaxdZ+Z82eN'
    'YyczRJSAO9WitaN/achGw9FutLDYKI0Qn89yE05WRTHXIsEXefVYpwT0kiKyYCyCdqb9RK5uBfbm/LTF2Z0zZ8WWaO3UMUWvuHFP'
    'tNSOkOB6AZV3I3si4w25k67XtuFUpJ6/8rIAN7Asypm8MqsSMCeBVdIiTmV1Nj4ZQ+HWpIuBvU+uZNxMx7UMN+cDNC7jF5LiDlcy'
    'cBJga5rwlVoirgndJ+OYPbFQWNcEhiI3Eqx18j5PChFMXMmlIHxChf6ajI9YUJZNirwi3ZqIKgMXDZXjICGEsfmSaLPzLxATanbk'
    'ATYPUgfEIXgIWhcTXiQStsvPcxxPT2YTtk6mQ99UhSs31Qo9h6thnCZ8jmAa+6MxYuwn6VADIOHr/WijJWa1/tdj76vHwnMA8G9P'
    '89Oj6Hw0HOdbS8dFMemurp6dnXXOHnSy6dEq5JarVGIp0tAo9y5/vF7SuKB4ekNPsHx8np3jUSKMUWfXER4u3MOP+IdKb9+7lDW4'
    'foqGETdlYbRyF6u8wcdEDPWp5jINepOufLrmiq1ZcbjypA0ISMYVVE7VPVlYOca5vA0wG/t/OPnuFBd0y1zPu/FhPE1pWrBGNi4u'
    'UOUhv67wlX/+AclysxE7QiHLtFwwvj20hJVXSJIHgqRlgB0/OZi7VdxytGsjl/+I4OdoJIhg/sa+vXObOOaS7F4A3QasR9IrezTc'
    'W5A0xwnxfZLoBRHNEX2HQ79SBxpzp5CAO72jTVuC3a4k3rkOv22HrNhgbjT1mgpO9FXZTkQp50NPm+kHMK/DD57tWtX7pEzme5eG'
    'QJLBLhCEOCEXOqOeJ+LXU+myn00ubtmhu3QUcuPT9ChGoE3r/aLS3n2swgvzkkm/S3/yXTdWumMOQldOEAw0qpQTnUa26XlByc13'
    'llPGp3E6ZGTPAkpILCF94Quc2m04bwqYfpwdZ0NrAAJfljDXO58tdmBGvFMkW2CFWdu4GEhK67FIgnpECCZF3uZY4ZxnNUybur4R'
    'ZQ1+14leubw7mlK7R6cUNhqxadvowCdQs6uuxgZrc/bkzbEz4AjNFO5/HdM/bKsQQQM5NRF8DJxyjPmdSByNWe+3zxt0wKo/8xum'
    'GAWBDdNBH8deYtquuFswUyDLwinAzcoh+6tZp060i9wv8bBbyhwEVsJOGauJXirN5LOeXfHm8UarE712cTdyTmZLo0inbLaTa7Z2'
    'XeQeVpy4mBxe2HnB40UnprKGq+KkR51oiYgiwipLGBeiNBG+hUMNt8H+NDCbkD1Z8SlZz8pHGgSlnFsfGV3yMG6mNQVsdQ6HcYGk'
    'a0Om9TsaIY6DrOxE+/vDDhJuDQ+gX8bv8JuEq5Kv+wcSG5ktfJr7XEuUTxaOmh+aWUusVWbW4ge64qFaIhJXHTXvXerjdUsVz2Eg'
    'N533c6zM/DS87WhExDZCa44CsyD4At21lk5tFhPk7GQVZMbGLsN1c1aoE7TaZvZnOdxzWDBmDo4FQ0dOzXKJm05UZJt9ChHmg24U'
    'XhBq1GQR9AtgU7v8m9bBrdmYjQe7wudhz2wZf7vxir3csBFsHsD9BUpCRRMYGJwYh3Qu4FsXI0Kg9RfxPOv6nPASbujJwKQz43E3'
    'hikNpg/aXhsR2O1yY7Sh/JYVTNpns9+xXSJKpXarIkR78/KWGT5DuuKFpd4kMXB9mnkzxpHJC+5GCn73hDMw6AjXgmFJVnXPvDAI'
    'shKOQNjtS90nz6LuujosTQjsUjS50Ywqo9Eic2dVmtFGeUrr9VPaaPnpO69tCMgkcanX/XkeV+bY+MiBNxRfNdo1w/YGfSiZF5Mk'
    'LwHKoQUUTrJUP+xDHva6txMOedGB0fxgz3QwsJhkTw+6Gt8TYQ1uSRytczk6wuwL6umKlVIn+gI+wyH9NrfhblQ5z5xjU/OImaZt'
    'mU1D8cY6cLoU9JPGypAwgdJUxB5GkgXBj5JKA9/LTNvN42LEay7jtvk47LCIB/jd737XINCs2CRkbMYEguflx/efwBQQGyVCsNeE'
    'mnfZYqD57SkMBogFyWOk2fhF/UnQb4v4Ef74je5qLNkq3tKdjZcOczx/9/HFn6in1b81P1292bh68+Dqy7urj++u3r294m//65eP'
    'e6+uPn1+dbX37Pk7+vfNq2cvr/aef3z516u91x8/7l3tfaaXV3svr958bt1b9ZIM5P33EiaMUJAsAWgC2jNHUTT3v379dv+n/a8H'
    'T7evDlpMWHz9em/dtzM9m3LytibCJ7bCyLLSKhC/iXzvYp/6/rb77SiGXyLBYQ9qnsKK7ZpEzrRoFPnX3YP7Oy1+VAGei2wLT0X8'
    'Px3or551XlNOT3K0iJN57sYIMJKLxsThLyNhrhDmHO538HLPhDyCX2xn79Vf9n768PHlKxxAtLi8Jeurpf9cSbNgaDSJ1i4eyDZB'
    'Qambu6abV++Is/lgeqpPOcrpHjpFfCTmVRzL1IrDZCGo7T5M2j7w5HxhT6Gm/WyRrw+7e58/gog288J+Nxv37ze08aZLYW1NxLXq'
    'W7+dV+8rbdyiid3SUN7+6ZX/5uWrd+VW/+M/btHsC1rBhjPq6Es02r5vLbhpmjVngwt1+Y+Lldz41mDJ1LdvLBDiMiCrv31jivqb'
    '//Jbw21xeUDPGg7KbKglsRpjhvlZQQeoNyM2q4HXMKU0Zpg6V4/a1+Tf4fCbUp7D+vUSyQrEPezAxlroPtCAeCcEIBuT2eagrPq2'
    'ryXZ744BnAtdH2hFz5q62fqaHwDMqyKSFrVvxjlvQd6+92DOzKGxrwIQ5le+3d1Hv+X1yaf9ht9DueXnn2sa/jrm/Yoi+lGpSHjo'
    'y9Xul+f0/09X7599/hPhIBFQFq1KU7odGN/Te5dFaDB+TZeBFqALoOZzOGptWmuEaX/dBR3gOjA8OO+OOGyVfZL5XhTq2qJBCYVf'
    'xoHDlMPsDgVfTOFL6qPCYWoQjfhcvXvbmIeWIIRjRESNmTq8Gx/fNQQC0+Xl6w7zHSsIqDfrMWhjAnygGgCtJC6a0pLhLKrZICWu'
    'JCJ00PAcnjswLEYfy3G3Fo37+JXNi2jfcdva7baIteVQi1AZTHVhFjzia5E6JlNIIRXp0rjMGfVugrHcqWOxMOm1rr/VkaV9SWHg'
    'bYMBy3nD84cFkGj2eU1bdUAkRcWn4qvaX3sQxeZ9vHNlQIIfga41bWvgugz1b6OYNloHzJYWLBVDwWJqZ3FgeeBi4JrWvEPJUHAb'
    'r10x8G+sW0k8rP6Cz2XLNIg/Hn3zt6v9v339etD6esVN3Fv/+vWqUTb02EclZu2eITJ306UHaEfNZRpbiH/62VDs2IEk11vRCv3D'
    'DC6tCK2HboAfe+4uFrKUQdqlBtIbapj7eR5oMFwJi8tra05Ey0ru7ZJPvbFzOyuudHlclmyz4wi7oaabU+OAE12BgilBjo9lzCga'
    'V3w7Vivz0b5qBPTcPm85ugXj2TaV3fjNoFdW4JBTbY2ny8MWn6F1cX5CswSOc+GcJT65UollULfyCIsxh2wT6d4pLzZUCUTL11YW'
    'DpS5mgVUuZdaTjIBObTXsokRWkeX+kdiHoVaSzoyRc7cQxVtXErvMph+LXXKU2y2FpKdhW9oXkd11pxUvZ4/eXTZuebNMit17q3U'
    'eWs+NfVmwycS3zyoIa68pu2XchfmSj8HMWS4Qr6szBMhetcJ6IjfiQ8F8P45u298u38fP+/fd4h93qgdQ9fwBiFgSXthIRew67vr'
    'CXQ7iR/GgfZ5KNtyLob+MZ1LFhMfeQNV7F9dJlVcdcGUVCaq+JtcbYYE/jqmV40FO/flnb9zH9/5K2HuscaCGbz53KjZwIYzOuBF'
    'YcwxrwlmpP1WxL69X+rUfiZkY/couF6Dg1JDsOkrrQyZgpWDPs+yYRKPwz13Dh1CZbxTOk7t8gi78nHjRHO14AE574T99oaQKoeY'
    'uyzmbR6OCl/m4WNAlmeNdL1Gg0ZN3E9OGlWSGJcTp4skCXnOxxy1VZ45omwoqZEC8h0SGyf66XnBh4cpjiAHFAg/HG/I2WRpTtdI'
    'dUoYTOJtYzD8y2XP/Hb/ndEXdO+znlkKeE6o37xUfhrwy+te5JgeQDV+xzdaT416GjWwGAw/qIsef/crG9ioaWFxE6505EhvmjmE'
    'iXzPrnjVbdXVVeS+OFEdGe8mMnbMWPwn6horAsymCsYcbthos9Opke+ZxB/EbSIKmyhrgh0TMqdmgAFXUF6MYRqECMh9dMFnQ6cm'
    'H+Xe4an4SyhYzTuGTYVNPoSM6BqKHANMV98vP2vxuu60ba+5isT8V568uqVTZmtnJ1pr3RqULfxs2ZZsuCv5ZnP5Pl4DbToX0ILF'
    'L8GVDMM/l9Vdi2Rd5ZxqI+WDinKtRqlZD/d4rVb2dgE68oTdEewrqysG9APUY8fa8JeiKnX3MLN/414+aF8rw8ifNJ2owJtK6nc5'
    'QIEa28V5hERGbYYPxLmEylWsXnHumEzjWN8/ZNkRcXkvsz68xn/MpoNO5UZAS17yRAisWXTaFqvmrWhl3TP2GAoRC80lCGGxJm1y'
    'Sdgr4gxyC8vUxNPVYbr9dHU23G5IjKCVFbbw3Lxza8hedKMgdpEvgPf3r+VnYb3hIng62X6abrvb4Olquk0XQpL3m1VYg4Bnsu3f'
    'DN5huuswUUhGm+QCgBqqebze4OR8onw63sAvIjSv96WdA3uFsU8dB/swi8rSp/gIEicZIJ8okTrJax4xUbC8DtffNkuim2tv0IJW'
    't3lvWqXdfBrZe8HfUtrMp7SruqHLyyaYisWEMmZTd7MMDVJXaphP3kQMhoYW2+zyt6eD9HTbTOjpKp48F+rrO/5CufOG1k1CJkC+'
    'tWKNo84g65+LwcIvKeec+sv7d+Li04mez4hYi3oXbLgeNWEoDAcoOjXZaDJN8hwmJHKNwUQPM0HMTmjQaOy9aTxN0QwMz9nIAH23'
    'g5PYnE3YnJUO0ctpepq0+GJ9R3WTj4eHxNt2nA3ti88vfmLSFRRhs1U1G4G26gsd9gcbwkpvPJIUkTYdJo7w2maEHaVv9EPyYbI4'
    'RkKa2qInUhTJD57QHxREkX70ew4Asnb+6uXzJ08ebKxFf6PDG21vb0cc4EN/bkbF/viAK+B5LfAjhMqx1bSux/1p/wGiXfcuCmMC'
    'bEa0dv5a/7fpo4lz7BMXl1HZldmnofwtIg7v9zTBRwdubE+c4yUXcQ237AA9CplAge2Y1NWLTVa9xU7GfV1u2BG8YvG3BClGAGAm'
    'otsSNDMe6pOk8mF9IgzMPfVakYo7e3YGMdObbDaF6cXTp9H6enRlXr+nUyuR6ujDI/d+N6FGBnjPq+5CbcIbZYuDUbKvElFcf01i'
    'SK1XovU/Plnjdv5I7ZgS7wkzHPNNs17uww2Y1WkcLJWh406NkhoLVsLYYutPa9YRRUFTvZDaxrUHy4u6HXnmiHWsX8WtGtQTL6Gu'
    'Fm0DdABjACDnGGS1K4nYiSPiWZvI1KOWL4PUKMVuU2KOqIkHPj3PZ0hhx5UdX3gKdxg5YpANUptBBh4L4aeKYINbB/EIaEjNB7A3'
    'PF97uPbgYe+RocSGpuX1x82H8O+3Gcf8L4+55pO1+q9P2DjBG4//cR2fUhbdVGuub/Bm1Hykia4/5IWubxnfn8hOWjqwpo2NjRvK'
    '0CA2HosxdqmMRjilg6W0tLGjr2x436zwQ1mnjbV1b4X7c1e4H67wnC9PKmvfLy1vuPj90voGix98fFha/L6/uI+ri+9/x2DrFjYo'
    '8/CGMlj8J/MX32/rIc1EUEBYRJCdShU9o/rIIAy63B+sqUW90+14wwrT/JiArdou3bszopCbYMAknD6kzR3cAe90wCbS7sLjvLEh'
    'hzkJDzJt7OO1RwAWuzhJuPVCEZQWMCkBQF2hUmeABEFI5TZ0syuL61kgSziOTqfDx4Gl4LpANHUblkNz6upVORoiPc1WxDdr7qlv'
    'f/90e4nVt32NY9H4PSJp/D4eTTZB3z7lp2HBD9v8cCQPS/zw91lGj0Sp9jk4TskAGWQVDxeOlJ9Ep+tfoT/+9GEXvIW6COT942QU'
    '5x1QkjRkYWBydhk4I6JpMs0QqoquhNEQPgSPV2GL6EUs+nzr5jImq16qAbw0Nk2G7OSVI1y61+p0Njb2M9+ennWn2/QPL2mX4yJu'
    'LYEITKanCbwQZKWbTIFTsW38O/XdEWjTYr6PYMbeRgBoMSTc4pA82scEfUw+TWFTxObuO/JabN/PuqfxEH4R/O0aaWJFGk0sANri'
    'rqU2jd2MZeKPYpQM0ti3vLxUdDpN1XPIO4UwlKdF/8zr0JQ7l6UBEt+9onhGMe7A095yy5jk9O3g7eiIvWrahir4xgbJRNBfd3gK'
    '16oel0bUlLMyvlDiardGR0s/J121CBqkebG3tbS2xL+e21/v7K/P+LX9Te/vZbQ26dJIICnpsw9K//x6iSbLPy+w5ihB8P1pGqUD'
    'vB3Td4xxa0kBPeJ3UrD/4fSHaTw5TvscTJv25mncPfLevGOl1Dh7wd6mz/JJ0i+2ltZRfbW2vj9W25TXKpBfNJum1v9mwWnQJTOn'
    'So0vlraf0q/uBM3ix/iUJoaR44EGpDNfM9NWR10M2ZRAeczAr+4PHO97w3TyOh0OMXb8jqZdjuqIBmm3ub24S6QgwgLhp3HxQMPe'
    'h9WgsXIv+UTW/PxwOsJfQgDROQ/+Av9yH5CSzNvsVVd1Ms2LH5JsFOHH1tKUhrKE9/Hpu1wHZYroqKTzVbOa/thWgw3b9p5l4wWC'
    'GY1YwHYoxVNrmqw4dSeUrstP0zrkQv96yMKd85pDXsUhvccPlVkTr69tZjuf8EXLluvNuCDUT99KLpl62UBRGE9fSEKYtZafmCYt'
    'Xo1mmMpZOzrmLAY/8r9vWh5nyEmM+Ev/wujMOW92E2+j+xHSJJyprJWKbGsLl1LVK99HsH18pAo01U1pEC8gzbDmAZLNQpW1obEs'
    'rFEYibU5bMVYLFxVIg7nAjGXtZJwSRyHiAEazhR+ESwQb3U8e3K0zi5KWIteBdGKa5sRgtGTZ2tAT3NsDLy0HLLQ8H/qICEr/aHV'
    'Xn+y8YQJ3PUHf1h/7DzIY4Rlp/ob6Zh47/XOo3Tsj0XEyls1qhoAHX2mewtZr3CooOJ7yxWsYMhdYwFaV7BuGmBrqudeq218+IKE'
    'O54zHztFQSCLH2j450kCbylzJDAqXOAQlZ512aGOEO4GcIG17/lWNh4AGcJCQ2yFLDxs7lTS+GvcdUR3RRW84PrmDGtd8XxQbx01'
    'rQoMwN6aNRe5HQ3pweM1ZAOzsnl1H3iiLP0yCphsK7C91T5UF8OlWUY1nhEKBvPdoavC9sn2r/AS/ePaxmMz7jOilmyivGcPMc6j'
    'dJzfwRkRp3EV1/7jf/s/RO5mnMLLklhISNQo/8Ns5EzXXKnPTEOIwaTnJG4pC8hsOdRiINJlNZH0YogJJiO4nWsnE5oiBoa32URs'
    'f5ThVCw9uMcNatkbr+FggneiZHD5wCPbB5RoEPol7MukeRUUADjwMHBEEqNKkTO3sCnLl42HF1ERn1D5Tx9+WP33T69+4OxANDJq'
    'qkDsV8lmDAGswybogSivXJkj2GO16lI9saOOn+bp7tiI0EPBsZ/9sY0rgHM/hiJ4U1UsvWEttvoUWItKby019/+2dLDcWlo9aoWW'
    'LWaoiO3AfrbzzA3TUcm1l96oXy/9a8pKJAvjp+vcdD2Hw6r5C86DWLes/s1hla9AK2qGh4F5+CUsRshmp1yQEZDmXbFiL2+cvNgs'
    '9C5bsdzKW9fz1aVZjmOCpHjIOZECj133TXIdObuYqstu4CMrLrLUj44czq8mpoLv/Lqp68YLUzaGsVtL7C0WBuwqI/aupSdEhqfU'
    'x1m3PBlWlJQnYbkBo2Oj0wV+hVjGCZ2JFPJbDQjDp5N/8WkSsphz3qTTJHfnZfqJoxOFbgTnnhOBZMPrs/vYuWg0iDB7ncGBmy6U'
    'vJ8S8U3LmWfDOF+iV8fPxnnpVT/3nle3g5Z7XrO90rfU+5aWvuXeN0hQT5JSAWBCr0w/GyLLljCVa48eP3ixXh4K7h6vxjEt+ZCX'
    'XWtdJMNhdlauNePws+XuZqYSGPlhUq4Ei2Culs8mWgs3NTDbM+pz7LhfKUvniv5IKDC+5qleMtVnJioCeuJc6ZEpU7znTNXityM9'
    'DHLuF+ddzwkMpIshcgBJuPbaxuuKw3yLTbbeuM50BT7Kb9QLdmP1QcRMe85AGros/WU0VF8l6rpVssD9L3dE+i91RfJEKbkoJAY4'
    'kYdtCQDRKpsFh946N/rr3M5jx3Nx8I0ZFzvubHq1nBGngUoWsXyaNg9peb9PKOSNKLjfHMb8Xj+hOSabJykTsL6VZmgZeRvnIOxj'
    'Ey0BfXc6HdrInjGMMHvqWr21v1BNs+ntm/2ysKHZ7Rv6Nc5INT3lv6KnL+Eyf/m0sOX9kh/Jwe17gjvLwraB4m/fnDpWzW8O1+Lt'
    'm/N9dRpGkNdj0REeGvNrPmsEB/KYDsiUU7JPuyKWU7ahWe9e1eLQMTXjl9RA4fj59Noe/PNb79VUxThCrxoSCLkwa72aKlgnHdlZ'
    'ekIaIoKYYAIr3GFqCWM3LL1w9GDoLTeIl8Qe/vHRxiOdEz09fvAIseIeP/oDeP1WHQLynZS8tTosb+x1qP9UI9iSBvQT+8fD1aks'
    'lmJ5lBF1V+RTVsbNdX1xVJ1P1CCZlO4VZXFmo7eDuf5JjuNjBn2dVnB4OvRzOz7h29naH0o3m7e7uha4Wf0KR6v/WQ5Q1tPwU5Nh'
    'gD3CL+lwqFRgxRNJNLFsMAOsai0QmI4ImJilnCwd79KefOITz4tt6Ts8XdsSbwfuCz+KWNbU/uaN85/zqNJZGit03uHA0vRWUG68'
    'qRgYQTvWwOKt/KpChhceR1BGsSOV9RJa9874TY5KbTrwrZJNdNnraN251izw6jLaWAKDQkzSkUwWXTULJAtea9X0Y2OMHQ6zbNps'
    'OuDhNVrlscC2Utg0uQ7+LS/xDPSY/7K19JB/CL21xuwUWJmtpeev8Z/jLKxAlRvlNW8UnEu9gW7xVzLM4teU03UhnhNbK79xP//c'
    'EC839hqStizN2Pg3xG9IrJtUowYp4DAUveG2/BGQpx8/0sDPWNWA5bnPK3CN2UCOurU0OI9ZJMkMyI5p5C3LU7kaPlTKK7b8Zg/F'
    'sqn5XBaBWtTlEKLUfZBi7+ILjNq0epieJwM5jPTxBfF772OeAA+LR/JkrTwI3OTKJtZ/Xw1bWzULUzPsH6bpgMaMpyP6+SIb+svG'
    'jJ6xTGYQMrPiet9qsHHBSbIB5DUu2YlG6O5IKDLGmsF9wVwP026Vc8ECvaaqOEqVfIYCgDHLWbiIwGO0CHlwc4SjHXBK72nt3eEr'
    'Xi0icAdRnQHRl7E851zprag3TeITn9jg8SzDCLDKLR0z4qnMKCjJk1BarOgztPQV0PtlOB/XAPlYU4uZbd4FvnN4P9B1s7EuCzmO'
    '7d3Ayc89TIBwxXiEznBr6fUG/gNekDYYRPoBvAnM6RUX+KMiniJ1eOk4HWoE95+ZDozqHsP+pFGnWYBeQSzTpVefqL0Od3xTtuEp'
    'b5w8sOXlrRf3uvagadmJefQJWI+ELkB48QGQ1S2mFlO94QisWh+vG2YveGyynh5jW70p7fwJDTZ4odlNZf6C1Vyt1oGzKXGdYIKS'
    '1FyvjJm2mFyzDuZcljbrweM1QwFvRcEdVLoxYtxBUkuWY/J84OO9mltpfcO7lp54wPjsMf7T7eB2GoFDkVWksUbHYvuS6oyxfagr'
    'K9mWaDCQbf2xQ6us9Damw/4sraC2T7e2Kx6v83xeTUAE6lSOC1ds29W6dMy7nhThFupdX3+F8+tv4P5a4q9uJJKpLV9SZKLchE60'
    'txTnlBxra+U0tSIZTzjgFr0foKib134uz7rQmdYBp8SZqeka58zznr3kjheJhZS1RYt2XqVGLOBW+QgVqd67tBfeg3Ywl51og0bw'
    'gOPfoVlOLC3Z3lnZzEre628tdteh1ZSBzGV/FzjwYuDGNdRsgc8wzHXAnbu8N/niVvw+YQ+bSjTAVBFVWYZik775gsvLQFBzKynm'
    'sCTFrFK8Aa8YYJ7vva0FZ91mb+odi32Gbm3RGfDkUO5qMihfeIR6pP/Yw/nrdayIh/PLs1ngmYyBqF+yspGbtVKZEvhVeNUSzpnD'
    'ulY9lc1yXQdq5PzjobGBuFt2wWL/t5INyB1JsmG1HGXHOqtjqZqFWBWL527oRTl80vJVLRzZjcD4joQxurG/tbYXNs81g8MAOx7C'
    'F3UOxuuRC9DnGTAEa1JyKeNFCWyv6iieJ2J78k8b0DiR2R3HQnGXSsqlzJoFer9Hf8R/CqeG4qvHBM4xLgoQwZzOvrcbi3Dqfe5c'
    'x54kEISMZhcU6uZXeRXiBmYDn2avVXHlC/xiDebmvsx13NjTQJahQ2vF9Nn6UD8bcuLgOBJdqjP+gN8d3SE5fKGjyZRDgp9xcBoO'
    'tc3mY4fIBsAGNxPYh3mBwtUAp1OiLybjI887TMz0woRGJm7zpUSO7wL8RBbixerumviJPJQuXbLXrVYn9qzrWxXSZlBxsKGuOj0u'
    'bqzLEBlacjtGx9lwkKtB1DmddNi+2Bbtkqth2ARO5g0JhO3E34NTCMGsQT28jPw3G2DTHv3hwfojGOw/frgGj455nNvGwzWRZfzc'
    'txcXrPimHoPiMK0Zn2e8B8u9ZYMk5EGxqAW0aK5TZtFyTQbBAjjIA8BOKaF1hrzakAhBuQ0uZxMTybdAKttgs/Rv8yWzZVwMPFwn'
    'qV2vFdF+zwp5xuhqBsPytB1CESYDEHXXWVuSMHQ0za2lL3uvV4j9QuqnQTzMxgnsFPKlne07sBI3zXCSAmGd4Y1ArLO8meLNZ//N'
    '2eQ7bKlDv4WX8tG0GH9Hg3B5MPXpDPxT5t0gadheAH9A+yHAtkoJjnZ/EZHC+vof15i6Oabfj588eCIbPTl6HwOtFxkty/rDhyzc'
    'm0oCB/MoBJN7ltvLPMlp31r6wxozyYdEbniPR7PCigEAQ2ZoqzpotojWTfStkg8zyQBdZ4sTwx039U1x3JskzotneRoHL9k8Rx9V'
    'mqxyeDHi+OdgUBupQOC2wKem4Mn1LtXHbWu8gpnypv1iztvGhuxN/suLvPxuGDNO43fJeOWH5/4lvFruYVJ+mkewYFdTTGvj8UPz'
    '8Hk2TJSYV7pX+/BbXQ3naNfDSq4mVklErwZSTmlrLvh2sLX0AVA+5AVjVxKdn77mef/9NZ8EBSJUvKkv2zrf55XG5S23jRjbg4/j'
    'um7HsIFbOJz5y6oXzqotoYSS2+hHNRst77wd/XWTNbdIZb4mgv/6bzlnZCP7ACukcAEkV9XW0oMNhqzAKJsKKvX2zt1F9QvVq9K3'
    '668fPCEIXQ3X8UHNOj74TdZxY+46bvwL15Hw/VKJv6hdxvXbLuPG60cP//i4vIwbj2vwzuPfYhkfzF3GB//CZVx/7C/j47nLuHHb'
    'ZXy4hv8qy/iwZhkf/lPLGGrby2uJr1FJGb9gQW+Du8ys+mJGPIuHu1IkvAnMLMzP3L/COf0SK2n/8Z//HQzfP/6v/8F//s//r+E5'
    'BByOJMpCY5D0Uxokq3NhHPUuAelgHz9no3jsV9Ty78TbYSvyPJbgWgSevRv9ESLL5k9GrAZqWGhgkMJsniAXNXufBOeI6d3Xo8Kz'
    'VKWR7qfRv0UPDpRMpjb2PPD8N2oOAo3rjv3875bZANW05C96KApQl4/U8/Bg/Q8cCZkGefB4rXQPU/NluZ1RmfxrlkT8TWqX4t4l'
    'b39luf6nrId1g/knKT3XTi2xF/eQXrpffJhBuug9vWX/ShThzB0MsaylMMjwgijTwXt8461TQwFsIotIvKYC+czCDtd/bYfBeVrY'
    '75j7G/v9BJ2Xr/WxV9/3qoHIOx0YIAxaJSgcXM9veZ1H/CvA+yNt+BSilXow9z4HN6lX0wetazsr907n19BPAig+szGVM/n9APjZ'
    '92wvpeVbwDcS4j6BV0fVO57m77cZYeGnbwesoMmXoj2+kZR9Xs3NW86Mu7Ukz3Asw1rVtUM7Vm7ELoxrJ/BR420Vf3EAx0h2sNI4'
    'lemwU3GpeXZfcU1zQ6sobFya/T3UkFou4GZtR8Pajqz5qOvMaVY6EmXffHqfDajmq3O6zMZ8B4eAFOxqwAKnwpvuM2SJ5zzSfqk+'
    '6SeMKD/AqjVMltDvhy1u7Dthqi8DWuGk7gRTyg1GmPJYBgLYX4p05LKUfjr30/Gg1MuK9tAJAHZZoa2mB3yZ38H8ehPAYlDP+kDN'
    'qQH/r9oq/IHqWGRCNFnxgZ3qWYC0an2/Fg+2ZjUk0IWtXw6j0bFfIFcyqzR3HN7R/U1HIe3e2H144n/TEdimFw2Cwz1kk5wAd5r8'
    '+jEYyETtFeeZZnpc5aO0/Y2uofDg/oRDsAqAzn+DA/uvugzWy6gvjLni8F8VwudcCxumxX9mtKujpIixhqulbXADqm4zdqeEbiu7'
    'VKn1G+xVf9JFa5/sIJV+7E9+9SLMn7Y0OXCi5MlsOhTBcX81ETfTfHW9s77qytKVNMprK/AXW/I8T+ckAF5f/cv7d7s8+JV0jMn3'
    'IWsb9LusZHPqP5cIDpee/Y6S7AmbTbfDrNBcyHx6qmOVF8kgohEZ0zj98uODFy/3XkPh6ALzdYrs7e5HdatraYIBhET4Y+v6v6GD'
    'oFGCjspO1UBIBdAthFhtRG0Vh3VtBeNEWFc8wJK2hmNBaisJjvEHF+IbpkG55kFJryqp+EAwtTT0lRewxzQvBBVMH0YdF7etS09e'
    'LB81PyiFXWz8RjecBFavz8r7UWOh3yJRrpU9aDpvlQIRc2uSKwepJpDexoZQRzgsTuTN6lYbHAvN4OFT2vdyHhsjBhvxyw/YbsN8'
    'dSM/QDtMDdi5c6QxjNnqh99w8GITDr2Sk97LKYxNojbb+GdeUuHffL1c+uEg5jwvmNOaw6k77R9r9sQgU6/JvZnPpqfpaWKDIFei'
    'HhPgSthjafJ7sh1bXbTnSFuzURJH2dsprzjiR5eakQ2q23AOvV9px26oacglW7bpll9IqmWkSsaCJHOXwxra+sHGb1wdzp/qg2W5'
    'f4WT+SmfTYjz7078rL2b5M8WSgGz2vvHCV/bQSZbjvc7DyA92MMYveP5OTujQsfpYMCBsM0XuFn775H/9jzIqcvxiN8n45mOoow/'
    'LfqqegF16P2s0WoRrrQdwEKpzrxlQTP78TSNV47jfJJNZpMDNNhDEAbPUYhLEEKk85QMID5lS49GmB24yI4IeHgqvYKDRNvwNRgo'
    'gijjt9INkfh/SLp6CXJUFNnYi0M3RpwnaqkDcb0GtdhNe0NJHkCoXqRvKKjz3zTxnWU98eh9xfJrNZPCQh9bUZ4kxDyjcJevItRK'
    'xRIPI1i8GkoMmMZ4Vex6x4PBq1MOJE+nDFncGhNi1GnSjIQ5JOW2ZgW4C08SEJodnkRe7HR0k1eQ2RAb48+OMfYdjaQj/1N7oVW6'
    'Q6cn0QgxiLyPNlL03ptX71/9tLv38TNiRTdyJpJWNCN6l018Gl60Y5r9Ht41C+Q5HyEG21RBTWCW7mEugJdYMjt580N3j690aq1T'
    '+KUxddNsS0OyDLN+PNwlCAVXRDUYvXrDZlMqhx2u9TD2eBh04Ni2FGgWRu80aWNAiXVpSGQIuQFHWaaJoIL6TEnqOT7ORkn5fbm5'
    '3bMUA+HgXdgBLD237z7YLbGow2/YH3D9TGyqZlR7NVSgRiQvhBJ7Qy+bLRsxiki6MaHGnPAA4m9Iomy0yMTUeCDZBK/vcPCd9yDB'
    'mo3mZJocEieywgqpFWYf6E7BuFs0kCog9zkioYVhtbIDBQE/BcSy2dTtNO+CbT2qbmt5T3m+XLnloDDpmABVO2YHPIM0xkxmIbzZ'
    '5xc07FE0GxPpmEcX2axxymG1YLBInNWdmsOEasj/wOigK60w4kw4tfAJpzDBW77Jhqp+LLKwpBgzlc6hnzg+Ee7SI5moLkwpo7uy'
    'inDEtXnj9/XjgY3hdhmdpOMBL8H4BLkYej93a8rDYVVMKrrRu7cfXv308tXrZ1/e7e1yOT+6Fcft4wShtvsPGJNPinOWnrtp/jnL'
    'imbeYscCHUYxTThpN5uP5zqevMOLdHXFLgfzRoKq7JfAwGOD1LLl8p7EDhqzWPUf//n/3Lv00tuPy7ntHWP2YK11/Y///H+/bYYk'
    'ADbWu3adnae/I+akunfAAc4AH1cKnHEaaK3BqZNP2EtHLHRpO9TA+Rvvp4mFdu/Szqj5oVl0aIVY5UB8LJOsdd+LrCVphr4xSBKU'
    '+aUKtmNuSXhUM2IlPsLxFsbouCFEAOfTZggFDcYnuham04LBnai0/gkCiUkBeoNpdsomtVM6dYupDh4hNiAi/H6Eu61MslAbNfWE'
    'TGhYA91eZ5DmIAEHvBlqSEg3aJznQFUdIUuajQy37V3aLgJcWdN99GCuJMg9DpD7hm4phc7q9xbvbM++PLUmiGbNn0/jcf/YJ/no'
    'FmeYYL99Phv+Hn1OcgaqyiRMgZc0+ZCGDBpkIPPLv0N23puKXweXOwCqifm1I6ZybzoRjJULg38Eb4xGqfe1cgz8qHGOkvaWWpd3'
    'wLONZHv43abwHd4bGpHlDgOuJEg7yeE65Fgw6mlHUrsrlY1jwy0HhBZ0PLbax97PBJadk+Qil9SSNjOR160un87CTs9+37SZf9yl'
    'HF4OmYBU8za7UoW1ebvkHbaUHYjzWQ8VFJOA+DVJsrzRtugioC+dOWtMixrM0xXenD9JmPULCP6XwJ030RPMc7/BEjIwMfGUDjh+'
    'sP9Zowx+J7zXC/YtmM4/hfvQGOGaGhIL6NZxCQY7bkVlVsEhRvHj7rXsyS5jsXaIwOrYCJpZPGLEf4wY2cwXzKNguGyiEtbby31M'
    '8nLllNFGg6M7nC+IaJiOJ7NCyHUqKEheXM6jhoyjsclf9EhHTkQs79ldDl4EEkGC6xbHxJnqJBumaUPoN16BV8MFKO23I4TLx1UJ'
    'sfSwE71LIGxIiygZTYoLfGE7qtRnbaFBo2OWxBI8nqdeYtn1Jddp0gB0vIe0ELkZvJCULtXKIONTyBSvr+PFctN7mK4532dsCSr4'
    'xycyTRipgZ/2xC5jbfQzk8jaklkba2vWiv+cqoyyU1710mTtYGVEPEa6kE8ZZUGirysvsXLdJ0/Wz+dAz73g71bkKtLlECIh+2nT'
    'HVg/D5U/jLunhtbmGmFXN7eHAM8AqaYLDozFqB5rujMC9l9G08mLbAI9QXzEMu2m52uU4J7RuGiAyIY5V00vy4adj18678eTxBVX'
    '/gjja80fYG84g5mcOHT7HbVMniyfT8qyIbw4QwQBCGWh3V46SqabvpwIkrxRflTG90AF/BFIrCjRrXzNohI+OeqOht5sYN3VOAt+'
    'o+gwmxFRbHtHJfvA3E1hCskU/SYVdrVVhuw1L2NGfgbu8wV4ZDal+Pzx495Pr9++e8deRp+evXu1t/eKrg7MRsomeYnB95tgW5G+'
    '2IoICo94KFtLUmqJ9SErfbZ/u14S/c7WUi/unxxxjPKuvGeQ1ELbT1elqdB2rTSiW942ff+2MfdGX2On8y3DE+Fc0detEpe1J6AR'
    'XO1l9nJHuUsb/5aXiMn0oyQb7edEjBwAIYwIgcKxK285gY0ljz0C2rDPW45/bd7N0UIzzd/HiIDCmAVomZCrccbEcVn3muYQmVC7'
    '1LMS4oY0ScZNrw4txTCe5KUBSed3TxCchlhUmZGtw6GpS+XrGgzPQ77T6es3jsfxiuWRzNjZOraVL+NBVuqCICfbLQiKvPQ6XPZz'
    'Uik7Taplf4WAuSNAJ4LluYwZ77ijTPq8H3mHhVH1JOt+43eHz+ku53S2h2+LmMBXfu8ixr4Y+lKR9OjI/N49BjLkn0gGIb+EB8PP'
    '9NlgADrwHhOutTsiPbbmz+Md5vGuc3gWbW9Ff9BbkWvqCG+um3JBV1FGbXUQ2Pscr+SWtMV4RkEpuMuHhXiGNfJRCdPMUQCaOWcM'
    '4CTin+Xq/8d//g+GrEjdVfFsh5fupr+UAJ5ff2Y8WoZsm43Ar+oNmb7iJY/6vR12/mo0OXYqUKHsIBgGiZl3iPY6jvPUblL+Oh4k'
    '84sf0ldb9NmsyOYXha/SXiqBcLk4J4T1hhyUBl3vBvEjC+3rS0Kg7+6UjPPnIPJ8ctqODsd8JwkQVrC0lvAQ7Tg5+xXkNzv8S/hf'
    'RAZ35A0RHp+IoKFK9isNGZTgMB6f4DFnin0t4H3gbizfCoK/pAmMi1yeCJCWGVJIlXcfkjPLTUBX96KYDpf/G2jmIxALCME9ZGls'
    'hOtN1EuATcLFCTNq5oJyM6YyUgKY2C/CiUrNRygE/Y8QKQcfn+Xlz89yW+AFYpn434VmoJ3hL83+DK7NtjhuGL80lcMr890wO16J'
    'gIWy7bwWOWq1V3xouv5UJ1bqUt/aUnpRBr3ifO6qnNoWBLT7xQp6dmNKi+qQLlV9RpDQcABxbSvx7ePVwtVjP/J1E4zK+yiWCOCU'
    '/SJMnnjaxqRDOwAPdBEWuJUxMt5K5ctF1TdL8mF/Ku9ExF5aALb3xie3K54s0CvuC3T8kvYGcqug3LtfqrqFNvWErxYM9zUcv8LY'
    'd6+obEhQld98+vCDOy7ZJAAgmIX431/5hjXVpvRD0FxNYc/YxBT19PUoaLRTVYU/VaizAnA9Kv1UWWlZIvPdO4Pm1TOhKRbuD5TJ'
    'w6GpQexLj+Eh4UwN15UmgTvyX98oE7dhi0Iifs8QjVLNtfWZmu9lZzcDo5QLoVB0m3PxiCigZRii8nMK5kDrKjo/ECb8KuhDqPdK'
    'Hx7VTi3wUPW2o2ZwZ+iTaccSmBYdMgjgrS3iKM+w0FtDxkkxjygNx0SHnSge5KR2vVqatbaoV9JStKE2VmzgmmNZ17HSix4nJ1QJ'
    'UVnIREU0QoLsM65ZQx0vbpXpy9s3WkFzKl8IWq0KbHu6BaldZywC/zWTx0A8Ae4YwluvZ6Z6K/0yBTo6gjUhE+X0zW28+VBZA8MX'
    'H/oTZ4vE/TVoK8K14HAzYroG2t7je5l1lhgXOQJlHPrgK4TxjetviOXyFgRzVzr8hmU3K8fkefC0ywmGNN+PpF6Xv5jc20ESN/zu'
    'hJ6urlqNtN7JsNWwMTokyuYXIFGVaokWn6VzRTaILxp5hHgy1C5YzU22iBPtJdsWjSMIO5COjA2NxgOxRalS84EAXToPiVpTkIX7'
    'dmrMhNQChCWi67iSut7q+3IAIBzM7fsCS3NDP65tZkxu3zZ4lRoQu2kGwindvhtmnhb2g7YJHv4EeDhJLsQOMD8moqE/QziPbHoC'
    'pYUI3me5UWCofLJzZ4GMQgMMidisbeINicTdPqr6oUMn51XcP24iphdEqFUmrRcGw33+ZW/v4we+s0bZLE9mE7617MIoGVmWSvY6'
    'kMOCt6CJA9Y/M/r/2ONAWFMtNRGmjUhzap+Jb2obptEXHFCp1epkUqGZnx5VdT2aXyweE2pyryFPxhyNcUA/HnP0pWgKM1upY3J4'
    'tSNIElqdiO9OOqFJFEsAq0mcQzxVHE+z2dFxKQOYmKdSuzGMdDhEf3Ecw6mxN0tNnCd1BItgHhHl/SkESTS7qCNGa2xXrh+J2wTr'
    'yEJwGm6jiPLRDPcwuiG0IJl/cvDYaJHWfjBEzG+6b0AyF66z5tkxZknYkQCJKvSSfgy7UraLiGcg1qbRs09vYdI4TWiVIN5ALzwQ'
    '1ich9BatiMpLZFE4eemA1iPOJVPWl8/vck7QJn55xEZcAOQOVzCQGNdnxxnt8VJ/4m0SActY5JMqiXwVvH6eERNHew0hPL94nU3V'
    'JkvLG1G49+oFn8uChSAayovff2ajELXo8kcDOsqGfb3rBmjNMaXsh497r37ae/bDLquMxUItPopWtiW4JGtfaBqxyW7I5qFUgg1O'
    '1qLmbAwM1NV7wAFFzgnvoDz9xBkZnn+WP/yvJKbhn2/531fv+c8X+WrKvP3TK/758tU7efVFq3+RNpEdhX8grwn/+PSZ/1Kvb9a7'
    'HEeL4H+DP715IH8e4v0DvH9kfz02v75IRx/lzzsZnAscyo/PZNzvZfxvPmuHHP6RX3GQcfmF9EryCymW5NdnLSR/pODLt3+mIQDv'
    '73569oEDG77++GEPP+5cm616+fnjJ7NVq39rypG5Yp3DVXqIBMNX8m/Gxg9XDNJXBd10w7hIrsaZqXF6dEXH5/gKmPOKdRNX8DO6'
    'glb+CpEkrkB+XDFGvRKseyXY9gqkBR2X+OqUTnh2Fc8GaXYluexa91ZTX8NQTWbl6xk429/NmbFgk81x0dDAtkmUhQcRnd6UH0tF'
    'eBwleZ7iepCe+tEDzuLhCQ4O8AW4BS9GtZ90Efa7RAGjVG24Y8mIyPErF6W3og46dB/QNSHyqtIgYUCGOq4pDmXcYulgOflhtcu5'
    'IZYtLEmU5bEXKX9u2kbgha3IL9opsi80ds1r1I6mM1byWpyyT+UOgjyJKIFZY5E1EDitcDAZQUKz8ckYuVJoxQXFTHBXxUeKaUxy'
    'Xq9tHp5JLlRJDcDJR3V56lIKmQSwojoPAznfpdMGb7h8p0sHJx0WWbe1msrKse/3DTMqxRoMBoucQ6zdDhNRIkDiFRyMr47Sw6uz'
    'pDdpbeJkPn7Y3o9Xfllb+ePy6tbX/GD5nhlIzcw4K5FObN6m8o0152Tg4MHWj3cVg835WIJU4nddbEiY2yqIoRnuCFLo5NWVF2PU'
    '2j0xAbs3q1WnCXPA4wxiAborxxnbR0+hfN+cv9KtaktYpNoxhDmdgqb2JIeEe34TGjPFwhubFC5IT5Kd8c+DKmjCnoMR39tx3S4i'
    'p+b6WgkiTznhAhtgPKWva9V5xe3otBLlsoRr1GoY//Og1769NnYS/JGzfhIi9Q2N6dG3gTcaE2KshNpUi+C7Jhcta3tXnyIb9BXH'
    'R746nra+9iwIm4y1tLb629m3PN3/2/bB/e2r3497+WSTTV1cVma2qQMSd/ePkxdx1l/WAxAjD5udwD9ioT6mQjb5VjKicUmZO2Xr'
    'EqXlmuqc4kzQ1D+O+6YlUJqwk+aqMkaHWA4DHKaAsTDyczFWjyuTgCzPUyskYHxtOW9qW/zZKKU9Q5MI6h3httiqRS0siO/iZlnT'
    'VCpBDJV0OVUL27LHlBHaXZY1WnNW1Fg4lYjhshmf4S45xCzT2tm41py/mcenhr8E15EWjRzm0ngJWnY8kPuDbZJUmN4JbSM+2GF6'
    'aru7vlmBZ6plkh/L2NWwAUYFH+xrhulmyXBfHrfsvKnRAI6MWb9LE2N7Ccz/bX2j3VQmgqMel0wTxkh8XrHN/6K2+bqCjdYcG/Q8'
    'SXjphL0JbZVLJ2D+7ssOp4NwEqiyg7ddu/kL5r3jT9urYo+Wp0PHlOvzW9t0GqZaPzyPWrkBAGWhgLjW2RoVpixYESnCYgQkprsM'
    'DaAco0cnLOD6PFGDW7929BDmChEfgx/hxunOAUG34Y7ZU1Ryw2PPOtEe/ZY8t+o/gFx2kB2cpjkSa+d8QqD1IxY3mXjHwN87odxv'
    'N/xb7F4VauV4hebDfJWA0t8qb195k8Fni8zTXD1wZM84PzW3cA3Y4l9dT/yt/RpwCGTj4k0wZolqeNLvhlsf2iFWwEIMSNUUHv7d'
    'L9NpceEuhbHKbMfmwqTn0EZSv9Vgwz3PAJg2spcA6emFOQBrPshE185K+VYXJAqU+bOx+HwRfSfO1rTzMVvtwD+YX3mQBCaNYMSD'
    'jKo1wu2BWzzPypg+gt3iavTZODCescswixNm0xwRGGMRxhhzRgwBVpriRs6CJvYXm+aYTjItTN5w8WTlJekscvzMzQVXkvuFpnHh'
    'TWj2kKgU1GH7Mf9+V0lR3uSkoXxnPiuaa60O4CUbPxv3ierJpi9UoDRlPiKQ6lQqItCIve/tRQVLvlxMXQMrvym3L6dGa/GEaugL'
    'e4dJ13WzcJ8XTmDuakV5HXGRO3rCdVD2C8eXF6NBsz8aqB9MZBQ14eVcT1W5A1yzIoFTbHKe9HF8Caqa4ozwY1ocv9jdNd6L1olx'
    'Xi0eohYVjx13XZi7oGbrLPEs4Itven0JCty2a9CQEvjK5jAVMYsPAf2Y5s55EypmnlVYFoHkQADPA+mdChyyUYXddu/+NSIIAaCb'
    'pB/aGRd0Kfs8BsM1VYHFQdLi5CSDxHNJrNJwur5l9/0bzSK5xxWgmzzaFyvf0eDAubZx8i3HDqgvLb8Jm1W42C0QocYzoRwNyg61'
    'C13jsnEpon6PpVT+/u44f5PjjXZ0/KAtOWHYE7EdTaaJswsccx3PAA7N7eBfT7bj8fURiydr4oo4cGV1aS7xX3xYI2Yvt3nJvC04'
    'ZPGZlGb2iBMgCGjlOHVq97jKi64LjMYkUo0EuSAGaCB62sOWv54ulMZsKOEoUDLiKCkcyoYLGzdmbtU4iIUHUL5x5EqxA4f1JfHC'
    'HFGyQz+ul3xDbo4IOdl+2kOI0sl2KQoDYTqxRPqVWEuNvYVTmb/rcYOe5gq3WILVXV1tmKM+m4K0mkyz0aRALonxCQZIGBKKQe3M'
    'EWcoDQIJlThHhWnOH6g0ibhSTo52kwSNStMGS008EFnXH84GBEqN/0W8TO6Gb9EllHXSDtPl3mCW0dQCVI/hlBharL1a01S2/9vT'
    'mIWH2O8k7/NoOfu4fXi6Gm+LUEJSZTDtZpG1sOhqmobyYVgO7PQzGUfMfwQ0FoxdiskeyFgbYT4cuLhtiWwK8MqJIb89vXdJb64V'
    'MPXBpl59gFm4FJCKfCsrwaPdflpAb4BMZNkZ7IE4qqW8e1qogF4+DTjqpvtNxTQJhLbkDsq3EnZDZsr5gF4MkNYT6jXDpqG8XyBm'
    'LtaCHz5bn3xFDZ9mhU9hwjZBm2N+yVcJFFPtwrulOIOo5oEOEskiTdX5x8Mm99n200Vz64syRpf3Fy6Qpc1doMdAM5tOT4EjnrJJ'
    'MP156iehNZ4CUYoEpdNF+gfXOG1g61Yle1MrNm3enIp3R9a8UzzPBimb6YhkFe9UBQJ9Kd9AQWuwkwd8Pudo781pO7pNZ81yb7DD'
    'p93mKbHckYlK7gusmLPUtf7M5U0iMLCb5HuaenmKPW+dOat2i6HjqHFcMARhivq/Yi9oi4O16rcjBwz7AOPlaP3Azn5TozvVzpaY'
    'Uh8qi6lzJ1xY6eZVCodEGxM0XHM6qFU55yxrqzlcDlG0FKL8JkskOVznzGVcZQ/FuqQdVILdx9wKzFqxrbmxn5wjMWLDmfntqLOf'
    'E8YsLF3ju6gRm7IBW+/0i+nwT8kFVizpQOlLD+3ohL9R5ZDoc7ZgVY/FS6pAFCW615i57G8Q+C+YcYqhjICVhQ+MiO72Gt/J+qZ9'
    'yXJ9UyeqpLrl6BLJLYrV2FGvAsYy+HlDFydzu7AUXqm+N829uMcavzl32zAVereudUNVBENvZLMCKQUZOUiOxIYVBcwHldDm3gJK'
    'XOu/Hru7NGYlTj0kzR34GY0rO+MYkM2Y42W3o8ZP7Lviq/HaZTXe4ilwcDx/CjVdV8Nr00WM4ZtYdUhutyM2opwX/qB1gCe4eh+y'
    'JeYCtsRqdjiApmEgKuRTwBlVZJulsYCAx9+mb89gOhIzihJhxi+rlKeUgpQfS7SwEwlK2FJ7yvkLPpjGR4Q/p2bNa7yib6ifTaog'
    'V9oZcMh7yFxIgPDPbszdup3ZrIeUeT7emocxy4PbG4f3U5anKAeLlU8IHLejkEUl/qJrTj//CipwvtpOh0od4PRAh1fsYk5408kO'
    'D+lZ6E33bHCrERNOS9gmHCaXsmNshVUXFa2fDA94HmyrFai6FqvJZh6NZnnBRn9FEg99qluN8gRs886d7xXRuMhDNQafYtfpX4zV'
    '7YfQ7DcRD/UW4Frn5oATGgqDjGmuSmZqTHPtyRbjcFMOvF1olnsNdsoZ+473mEqaayx/WmPXO9dS/rQVMK2nQUdlDyy9De13BpZ6'
    'W39e0Lejo6qxv/0y39rfYI/Q5H+uwX8FePNgFkyn4eYLXJos+SEQ/pJQYaCBQyKbKBkcJRKPBLbAUVpschmOYSMGqaLgSAYdz/5y'
    '96cfa0I9CohJ+JvNOyL+Ugs1Kr1cG65PW9PYG2ctX93O0uyODGWL2liOGpPzRiCDtBshtsy1cQjqImTecPWC5gaMnXqEcN2YOEEp'
    'x01o9ofxaCJZyH/krytU3WGjjSdr7cj7ej9a6/yh1XJzcp3PJtYK9lKlGxhP/azUGQN/rLNefckZLrLZRBndBYExdUvavo1P3fzZ'
    'yqcsEuZ5zN2DcLRzi7mhAsZlqPUKDw2wZXOL7SbIT0YTctqPxqQRDhIZkUUBh9sdVnrx+EL0d0SY2vTGYiMKcz7RdObHkMziThjF'
    'J1KkBz4QtlwSuDhBHOMLCW/XuXMzMXKphHZIP3CSkh1PeghH6ByIuo4EwALdQLb8Rr1g3XbVOyI6Rq7oLmvi+8icwKb2EsQ2FwzS'
    'P87SflKPQt68/bC3W4NAuNVSrNg3eNeErYYw4xzqlMvVRT6wQSygguBKm16dPS5VDp9CpWDHwXELzkUgHr0BFFhfEDAq8t34iWix'
    'XVvCBhevP1M847bpq7HOrM9aCTDVPd0badXT2K5I/TpYdZO3EmyOGLrgOgbXni/bcC2a5vGLhQENPtBb2IrWrbPsE4IQs/Bg6MJX'
    'gjqzFgBjRE5FzMfeNJ4SV58n8VTcH0q+I3u+q8QhsWZ54LKRl5tCqNYBVOsTYqCl1+IYZgIaqZWZtwHONtsVqOvIgAaAptnahEC7'
    'oRZXbTbcjZrGN0yTRre4SmwyhK/A3YwdiVlcJDFyNXKu53gh8Xa9YMDGscIM3ThRcOVcbc7fx5NqPN5o988/RBNagwldQ8ujIh0l'
    '2kmRDllPyRG7tOGdDnoDLzzxWRD9yh9ZS/EfUDlNNBSX/9UyJd1o4p1RwmlIHh6qapHdgkjOM7rGVmHuuUbXYQFf/VRyKe4/XoPD'
    'ZUI1Bo2DdiTPo3Q8I/4YzxsP6Zkw7pSf/tCGU+4F/37YefAIUfaS5ISf1zdQk+D+mB/fjmESWRA0NS4InBoHB0Z7BKoxL6n09kE1'
    'tDnI2gEoaB5gEF4yesp54Z1MdGzu/VF83oRPB34fDrNsSrQl38GiCLbyUJ0l1vbnGRvin+H4f7t3Ob6O6B9k/qI/bCCLWNKMGxrX'
    'WNhvxjL4NFrd4nEY+0Uh6M4IBLMCh8KcqTPaU2VPkFBTDXASCJvh0ThhFYLYUDXYR6iQ8BiesYyFL+aR/J1liRAGjg8dQN31lT4w'
    '9OHJOFdL8Fg2QmZA7hzHefOEJS5GqyHvEZAR7ze9bhBqTu78doSoTe3IRDtqR2KEydEPTl7MpqewNMNvDlWaCwHCkaNPjzTIb6MR'
    'pn6QOCRg5DjGyCillSuS5r/vfvwgDh3yU2zH08OLpkyXbsU0OWP3uUpgbAIdCQMo6Aj+WbMJNTvgbATZHc0q8XoqIQKTcL/gbAZT'
    'q6N0LMaeY6Cs6JcsYyQJl654KndsTGd77FAoPJXVtS02ySaUhI2nJ0xJ5v1kbOxn2xztsdfLzmFafOZDcq8DAhvH8PHDNfp4HH48'
    '1o8PbWA+6QbxFXudc/qKBlajDTro/LcdXfCnC/50rJ/4r9R3+/PtKf2OsLjPs3POU4dzcYF/zvDP8fUSbAHY6/BZPiGm9jOkHVtL'
    '5+/TwV/p/9EoSYqlSDIPMHhsLcGMDVpPWYfrp6vUh6gLvavLBxE+aYQ74uEQ92HzO8FPQyWqOFVhPBcYb5seg9jX8qrGUgHUgkS9'
    '+ZVxeKqJC4Io775JuLmFhH1s1ZRQpM5Xs3dt7fILEfTJRxdeUp/9CJP/f21ft9xGlpx5r6cocdoLYARCVHvG4aAoMiS1ukczGkkh'
    'skfRluRWgShStQRRGBRAitbwdmIvfLHrvfC+wz6A7+036SfZ/L7M81dVAKmNmIiOFgicOnV+8uTJ3y9p2/rdq8MjH46SXHdKEr5v'
    'YUuruhUJrOc4NPthUTbRpz7uTcoLB3mHNtsE0tza/ymWDmAq0QNUy1ErLDk0re6EnNesvzfeT2XUbdnr1ee9++N9SA/tn8/zY8aa'
    'ySlGo8EI/uLnM2W6Tl8QKYQpsPUSiAcQRuRcUyOBRMKqtjmvfet1tHdfppU6u2Oo6A1r5qbsYLq/LxkFqdKSWwQAcLlNsgcalQCC'
    'dOu3TcNZ8nnZ792X/9+3X1w2i56xfrFYuB2/YaT3XQKVvJd64H2NtpAeRudFXSMFFtMgpep6LvMx2eWi4Bo2NtCiv2O5EEsQ9de1'
    'num0o8iHgEEly9A8Txo062b4vUqf1JgT8GwNrb3jyq0C/JXVHwAZ6fNG3o1+fe/gn7/5ct0f/OXd+w/v339g7sj799/8t14cKfep'
    'PP1EzJI+FhJC6uLcZBfcf85YXx/z9ybo3RKnwB6xpvjHD0MTxE+ffZ73OdA+OxrIzdA7LRHIYKVPwV/BZoXD8uPHmLehRwv9fazq'
    'lCiJx8ViLoRDswkPnkZ7G4fBkGSc+M0CYh2YrubPxWkPs1LU947pGyYw/IJYXzzVchNiiXLQ3bbIcFNuz86GJXLSX8m6E9KTj5pY'
    'mu2qBELfDn1N0u+efPzLXxjHkC/pZeLLyof2rqUPaQhBXfqYl496UWleZQrRjSxXsTTfzn6Lu7oASrX9Vs64HtY9W93jO+9l/7gT'
    '701f+5QT5fD4qNTyYRX+2YC9DzpRe4Huh1fvZdEb0w4b2NzhaIV4sojhpNFjf+64bQxD2OCCk001CpCH/iy64VQuRo514FwwT6pq'
    'WuQzv/nOieNUHHW8IG7uJJjeXHqYk3sVq/f6/QyfKbnrRyzA9cc2lTmYcYxsRD20z+MuPQbbi9CH3/RwGfp6HCciNqDm365O0M1n'
    'aS4lDCh9cdKz25ZrBentWg3zIFwdVotlvObA5kpKVRFpzmpQIF9vrBhyIzcKmg6Kp9U5QkNEaLTvhyFJYUiDwQxeqAtR0oRGkCOK'
    '6mJWhi50i8epVQiV5+4zTyg3qkZRubg114ht9ZOcPp2SNmrkJaW7noKWbrikdAe0uSvGoRqQ+/YaTIOqnfEtqHYEg/V3cC3KHYvO'
    'ZCw8spHGWWzE1ubjjd1GxZmhD4C8A1mLRHuCvJIGcYOLNmaG8ALjrUranrvueiHM1dVa5u5oECPMtNjwxXWEV579539kH1W7xe/H'
    'kKivLfHHf9GeFc8abbDSMfrwX1yr/sTPUccsVRM35hfXlNPD7+3VM8WbD8GsYURnhVD8kUyETKwz+oQ2zC6x4K9zZYQuKNVU+q1s'
    'URFumb6/LcgvvEVQiF6BmdGLC9zUPgcxGjPvYNh23I+I7LSE2HhQVDug/US6PKuaihRpzdeOeQ9pv66jcT45FTWK0BwinIkWJT/u'
    '23Tci1OgaRiP86nNR/9YO6ND2EOFOtRchwGrmVX/3oZUxyhMw5/umCnCM/0SNBYB70CfQVDyDEnJOV2R9GlQtouaxedbN3b7o3MY'
    'tJ775gtP3EFKRnbe0uHiy8ZYP6ZLz+8i7eA6Km0RHeiBsoPRasYwnH4THPyYJRCLyy05p6o3vSwun8qXYUtgSZW9iEBXI1jwNdEL'
    '+lIGv3cxznW6mqixNNa6wlzkkljajZySrNJpSo5jrn9F0ABV2LwqliOnOrCiF03D0ALlZVoQEsBUMqbyGCaCIRQ72oylqwo2n9kV'
    '9EGzS1NDpEq3zjTdh3JimoKIaWP4xNzwB/FV1KHm6sIGLHantlh3/S65y/8Wi8iASXrklb6DkRuchq8EaehjwhW6j6tQR5YcAdC+'
    '0ZkxAzj+trW15wkxO1hWc9MDNBu6rFus4XPMEIwfJbj02To1LLUTjPdfpBuyyy375gvXBOkHyZRxxXi4/JNp8Xl7DDC2XdDE1v6s'
    'mhWON+rZdBN35+nxZPJ9YyZ2ojL5ycYgcnPK69pD2FfaLyZUVBInCPzLkPuwdPVqbNNqEDUVZfN7BL8n43BgtMTk1WQ5cmsb4Uqf'
    'HVUG4R1wmibIDsV6SRtR5M77PZpaXOqHM1R+ktvfZXFqTISMjNeKM0dzNPnVwftZ/yezjyD1s1zSPq0XPbB/R4NEC8aEjqrVIlYp'
    'ooGmee/TKp84cGuWgNAiEasFQstSYQ+KbsOgUHzOz+ci5uqi92Is6scz96ub8a7pbBy3F4EAnURDPNDlMlWBjxEWc1m6CqgNIyDm'
    'h/gmqk28Pv0829c3Uk+4IV6fSJGzN69OHLGx6LDwYCiUUHoQ4/n2a9RkiRZ1YeLiwqpvL/TG7zAJ2crF1h1NoWzMX8nYgnfQGar6'
    'EHPxy7UuRTDsdw09PBIrZIuRVtyZajp0sGotHjZKYMZ1g28aeoNj3zqEVaWkzjjWd5EY9SGEVeoXGrzajgGM9kwb+g3btXf5QC57'
    'tSiGnCImpdDEzRl6z9ZDb69oj/ZXkejQi5TaCFI+1VA2zBnDjWaM1oP0NNDl4WtRkc4YMHLjNqwNOv/6IVlscSMkXGOM/ZfZ+gDp'
    'myZkIcVrrrTbU9j5RuqK7uWYyM4H6fFLDL33k8diCjuPqAtNdNCRbLqGcPwdqfUb175YZu3eGgOqRpIh4H0t/yGc5qSdwx134Xnd'
    'zW4sFIBGm2oFsChvtUqwl3kvHIncsCjzaYzIrsUWb8LA7ijpOsjgF+Lj7qc4PpDGar2dmuPE2DzI9e+K6fzGgQZnUdTS3TLJtLth'
    'ub8WhTvu0qi/a4luMr3f3djgYUt+jrC/MbFkWcwtJw3MDfAVHGatH224MeNlY2KL1fvqCmd0FYDpj3PlOLP4b3N+ppde06FnWVKp'
    'MHHdmSxyv6dJMnrCiRakva3jgDc5D9empRirjd/2KHkbXe6VyphFNi7oFZdLLpIV1PXwKNG1shazdzkT0rZxBfG75h20bmkeo0Lk'
    'dyCLDYPuWqL1ozuI9mhdrlIjL55DqXqbLqQAzAHPzSt4J/+YIwev0DqLASQZCjCj0LL+L//6f6iToAwLUhtFaJ/nE5Hha2LWDiLH'
    'DeGEpUf1mScaKZDbio7cg6NFUbzlbyFXAELdkBAN39OoPTr83au3PwOtYWiHIj8+LuZMRthVYLdZnLXobx+FGR1mvxKpfDqRfyPU'
    'WwA3hTd8//zF0bM3P7959vtnT4+ESbV/evz06bPXR0Nvi/GZrcJkgI5uM2SuJnEyhcMpnI4hZcIWW8ni/AH6SfR904EHNLGNIf/v'
    'qFUjJiqqUxkBQpA6p642ofuUvN7//DB+IuqOz6VlMJOn46bOw9qE5N9U2lRp62xMaZK1FVODPGj5OzDy7KwZLPDLv/7fng/UKUDA'
    'Dp9IzkQ6jHp+u3EQEBGYZ/M0gjT60zvKQFTVdAovNON4/vM/MsT/ZqHUHn4ysMW5aO6f4qb2cLXQh8i/Wg92VU9k9fWpxqKkFRQj'
    'H6yeYhxEbd/fgjqqNoWtYbalR26yhTQggFD4nBdllwFdTbHsEN42YkRatZIftq2qd6hqr7ycVUxhMKNebFBOffkZsT11RnYOL15F'
    'UKdCIZyi8q5PWMyVlanxJ2JfqkViCwhSEIpfIQywzBMQX4MOtVr2VjZPvZBN0Ky1kTb+5QqlGOoDur86wQC9w0QrEVu40DurRfgl'
    '+7yb9V/2p1q4nfFU+GtZyeeBhVMlLa6iFldsoR4+KyOd13V5Ouu7ddOwfYjoSPqgJwnhVnzPufz/14y+Gp1dzz9/xA7MQ5MrNrlK'
    'mhhr8707QcJWHHXPpyMlsoMD8xj5xu0II/9ThO4URh4hX2gCWvpa7+ju/Do1hOpWKoUwSMubUqJNdSJ10x2d0o5/QPgrAksbb79V'
    'kdsH3+60KMpRTnu5HOZkXGF2GlW7dSvu0HM76tq6Jq2qtvZDu662H8atRNw1+YhrKs6uSXmO9sjKdqwVAG9I7Y56CrHpIN0Ns+oo'
    'VRuNBaWeLk678kTH0zWa9/Rsg+YNWooU7unZurkEznZveublzakpenc6im5fiB5TovgEwPLy6ZSlLIT7rubydNFxObBMwmh+Bf58'
    'PmdIHJYcoHoMiBfhr8gJHAWmL3rjsUW716jN0JsUF70odnVaVWc171h7oWPlj1+//vlPz94cPn/1Erf0tzvf/sPowc7oW/nvwbe/'
    'lfVDgx9ff/f46NnPP755YWF/jNYZV6vl47mGBtv0duP+hu5duy735zifPdfp+69sOYqJfZN5tPrnLw+PHr948fPh0as3zzrT27bt'
    '4e3q5ERI+GHTVglL6GOMMjJGa8yjmlajGTRtq/yp18ymUru8PTVyWyfa7N3GKgkbiBf2rqJNXPiKl7ZcCBBtxTT4/q2Rw6q4oD7+'
    'nWzntJqzigK2m6r5n6wlUgWaj4disyga8yPHnGjizfk4NGLbqVdY2wg9qNF60C5schxe5OOcv/2tlVkWyn5ZXEL3m4twIsdZxBx/'
    'NpDcBXhPeZF3Q8g/KxQIgs+qoHyCAHtEy88qnOmZ3kWizzR2fyavWdjKtAhgk11dZ3af0+iFDILFKL/IyynTYQ7kL7c9ux6Bsm3x'
    'PilgxG0Qx72sZ8+O/ntdzQ6Wj7BvIUUDcsGxHHFRknpC5ARy6tkdHxJuHX4Z+0AdmGi/bcQA+Y7J8EC+CVB3jeWKd+08n62cpNY0'
    '51/4yaULHFSSC0Uh1r6e5MjDaFQwd/2rWXvrp2rVQ7bfzMGFgjxsOluDNEa84/GnLhGQU0iYXPZ4UaifbQaL3sFWExeyOVCf06Y9'
    'EPygFff8mMHAbv9FVWk4prRwzORq5M972pvpdcmxvUib/lC1XgvCBQfQ4bq0lR4MGGB0AKnu6CMqz5sEma/cpDuDzJst3A3nWRLG'
    '2yKhxWpmBBQL+RemJWzob5idVkkrDP3h18bYxzHtQdEkNAVrGOn1qMWDTCAEFnUxPdnNJm4VI8BaMJ0V71zC24Y83aT+wXhajf2R'
    '6G8+9o3g9ONPC5Q1qkeIyz24IBu4WHf6ByO8KVSWCGgr67Cb8p5vrJAp0lYGYs1UM5G/GVr8BH2/wxs+YABIR92NC6KwBpx049fp'
    '0ebZ9NDY8vDdIG46Vo6SURjplTMTYnCbXqTKMCM63PO1Ju2YLB0VHh713FBOq7Ygn7XAHwNnSchD57CGt7Qj2OVd0SF0b7tpMXiQ'
    'hOxdLoBJLN1XFQ14vVu7dW9695GfZDYpJ7P3sgAwSMjyNSZjAFSxI1JO3U9RLgN44Vkx92jKLuUi1/CH04qgzMTX1+wLjexhjTe0'
    'R9YHsAyRHzm6xbK90bbRwnVB2f3jjkHXmVnSXWeZ6ErnZV30F42KbQvNtEqS9bvv+t793tr7W714o+pMo9Lt/sYMcH/7KOGPPdH1'
    'r3sfgQUiR/WsmdLPwIljKnSi2IIs+6GYtuefcb1hx5edD0UbvciXXVVIv6y/HyxhIqqdHUTKm/xksXzhFMnYWNQWOX3qxKxqwuTy'
    'm7t3O3OjE72hKcGbgfETIS69LBv0EoZs+O+9csKvZ1UczWQPJKI0+vWY3kyRb7TuJFr/uvpKLppzlfffEvCqduHdPUQltRNqyPcI'
    '9pMJz1/xMLlsJnpaSgSVnTGYJ9PMVJwossfYOJhmb0vHzk1zPupZ7N6mEUif9d9uAJ62o4V8skyrsFMQCSAd4ZpucszSbZse5Y6t'
    'dmTerQO5EKONm4YNe+46vCsKz2fkgCMApysxyptzw0ZSsvvKHtKd6CVyc3obhHutdNr4logerQCa2Ndrg3lZdR30DUgLyWkcNtEK'
    'rrtWOeswnyzN7d1pRF8W8+3x1Tb+FX5R1xDKYUyfL4D2eOxjwEZa9JLt8vpMryBolpWKe4hyRPbo6aelKp1WjXBRTWu8ipdE4eQL'
    '6Vm6UAFSlIAT1BwgvddFUTtkg4mWj8n6pakndZxDpR0xyG+m1pkc7zmRm0hxKutQXbNg0ZiREEmBLc7pIKhY3VyWBedtXGT1WUkE'
    'FUS5oWbdSVHQ0sQjKO+nSDGi+Wa5WjaqPh79eLTW2OLWP0UDkSEVF6Sr1fJghL9hi8N3Ia3uu2cvfv7Ds59gjq7h9DlQVxBVFy15'
    '796/Kl323ce9sYuyXJWMm0eMKWIfLWMkP+dBNR+iZpRpIScwaqcy0OWqH0eo4QRb8oi1lUx0t9LsPnryrJzUfaZJ9Afvdj6grUvQ'
    '4SsVuUl34GS1IDujpaGYMGlc46ThMUE4ITaBd36RL6Ylm8q7LiHg2D4NmTCuyME1Coj7mMYo/X+1PCy0/kvitQjDHGbjHeR222z4'
    'XbAVFDPSzyNdtP45l+hcSzzTLvVHFwxJN3joxSWf7D/KvsUvMjxYy+Fm16JcZf2mqlgBCMCWWLpZe8XiXoJKxzHd2sXTLC1to3/U'
    'GD1AXM9jYhi4eUq715+qZSW3BMyoZR2l8mGYxMDovUVCvzvjYHPuCwAM2RfYvBIZaMDOrXtc58tPiCvvt1duL/v7Qfayj8cVZfcc'
    '6zNwY+Kb37UeowfKSm+HbDBsMFMYk20eIrKYg3/BOB2M0Ul1T/PFGKHeZfVZ1icZKjdrvH6z9mSvkoGPk4HLO9/d0EVjEuqGw/TV'
    'mXJFo2xc/fnEbbCL4NVauuSFLpTXFwOvjLXXMBr1otoXysKevQaa0Tvp7IuGsguveQsE4XPq9Onl2RvqrS5T2zU28HFvvn/EhGZ3'
    '6yBIwK4L48cRiI3TU8CDWTBHWL6e5qXcMpmhRPDu7ryVAF/uEkjm++GKSi8ih4SIQZDhdN5B1ey4aNw9o8zHb1f0WqsPWDgQhDKP'
    'wyPnm0arDFnf6ZhCBs98a/856nieIcECElD2YCdTmJg6vAeV0grOW4Q+pgx6GJRvvqxEEvuvf+8NroeWK67+Z8iJoNwgDWnTA4Tk'
    'W/C+lX5fVnOO72N2PUz2mJjXFIN8gHcPCO9w9cjPGk6yZr+fEQrJpFCnvKreqUPKkU3i+2Vygum05yL/o1LWc2ixbhV9Sbk+Nw8O'
    '2UlOa7esGuwFg8a+/x5YNAAwiNzxfAvRAL21KtOA7hrAZroW5TE3XBgTEFFqyjAKLkM//t7ZeLJPH9/efXxEf8pgN2zyUwsZiAu3'
    'WczASHs8ROLSvbhfWyxFSsAMIV0Ct8t1g9B0HBcwERRkrbPxldGu7ufQ4GBmxW7QITsuvATUZ/OVxnzulEqgx+TGRhPyGJPXraGP'
    't46CQ+6A2+JhvNJH+djWA64KVW6Ukp/oGwfXMFwDbM+PAhccTiEOsCxwShesfcOSeaBuHJnufV23hJ0X+oOuRTlHmq5rnq6Modhv'
    'Whs/mc5liQkFC6NL4rqN18QAlMC7WJJN4fvSNWEVx9MKa7aaLctp49Azu0WOkvDqIswIh2kDySOTzguEwikbySBD9bqWzir5Ge63'
    'KV4LUALUCZO3j41z3nYb/r65DT+IMiJz4wV+S8J84sYMzvsJjNfPQkdWyhAvZ6I46AnGwsoPXDHfskFWgYj9rujCInF80d4PUA/W'
    '+7LSxGLyLW1L7zQoV9+1YQOeuNsdUtf6iTAvarLI5dOYgWxa1k0jn1RnctOL2PiMfPcWm0P5duyVgfENEm1zA/8IpFLD0sBLIdMi'
    'RrmAgxt2hdveRz/Warrmfvzy1//5y1//1y9//d+//PXfbGNyBK8idI7iEAFSQyVTBtfg0gr828o5tngL+Q71j0YNVLtzan/pjLKj'
    'CrusMfp6NeEGwlEwF8kQv8d2Hd9KO93VfTHo5inQKd2lDuAK1A+UzY9uUbp6mwISInMSKjbC2Sy3KBuqj239NN8IlM89iimDF9mu'
    'aqKys7xXoCFYLBcWVtjZohR6UZ0IaZlUid5BARqaRvqBYKwxsbHHphqFR8hW7D1yldlH9vaB1cvC3db+jXfgbNAiRdWuTRZAKce1'
    'dDh2TX81/pHtOimyWc21wTO++WKa/nXE5rn1MjkV4AaQkeqEy1IwbPGTlxV4sdWRDOmGfA/ime/9U+MdLD/KIyHveJbgS8K6Y9YR'
    'tJoVKneGvlSScT0uCmYPlx28woCBaOYAel5PPUxaYir+novd3g+NHJVh1cYh/r8YA7tJNgFnblGhpL0cCzBsu0K1SZAht/PlknfY'
    'Us8VzKbh2iaPzZe+7it2CuzW7xbVp5wiXOeutW5Tn9G9LPUonwuPuZCe+o9Fr9rGtwMybz8bbBcxGcnPTqdymdS6/4x70iKc2RFE'
    'P9+FSk3RtUzdqSRv6Il+kXMtALTo+ISok8fL6ZXVCMU7L/OZAm3PIuFWCeIeA34xHqwVpGuviHorWxkR9YY1ScJxmfiOCObjoiUO'
    '2u5gYh3VqTexKo2m/0pmpQ99Nbty7yJ/0j+MQ9kvyqNa5+AIm0ZI6TXcCA3Ai0xBhwNpzVlIqIwig5wFTxmKCjfbxSJekf4XrEkZ'
    'k+KsyEEKCoRLVZWq8GSiqNiM+FY/srfvBT23FgLQ81QxiTuiRJVvnYlBVFjY5Btc7q2eIjw2jB7C9COlV2YimwcrAOzLDObjEOuz'
    'yEve+TrT9NRprWOl6h8rJfayDVQLZ7DzM7DXfCpH1nLGMzjSLqHkucOFDBowJRksDx4UQQXgPAY6o4L8LkVYPv10Gxa75PhY0Sv6'
    'FuPYnUTk0SKyp5TN67VEVl8qmMWNd52eyJyqgOrEJvbbRs9zoY6l1cm+/FRNC6/U2RLdzCx/KC+KSNmGfyBfnFGf2abYba/sh5h/'
    'Wa2Br0OfsOkYr9B0kiHsfsesHyBjmiggMnIX5iRnW6vsJJ8oLxJaP1lmLI6DhIlLQheZkFb7+t/6RmGbCh6bL2+mfxzPNzomm1Md'
    'G1KoJ5DG5khm0kNpq2m3gJuSkJGI/rcgILxm0aaP71kBY0mddg2JnDypmHx08nyZy9bj0yGsetA45Mfy9FQ/HX7K55CdTr4vp0gX'
    'lSbVJTt4U9TFcq19kQ6nxYTlFk2HdMWptT5H3cX9d2MyWk3396blPvSgrB8kmid6dTkCwejjn5/bz3v35VnXlXzUPXv8y//4N4UO'
    '4V/38Bn0UuvccX7HnDun1OyDKst4v8aacGv78xLo2ePqs2jQ02k5hyotffCaJxCiGjL1ObhD8Bi73bsv84uUFSCFzsiSRdEc2QB1'
    'jWWMJBl/iEguQssKu7xO72tfblxKV2Ue9exGtn78zJoc+gkT1I8Yc4u+XisIeZMBOX9dm9pK0aFj4ikPiYT9q/JNoVUaupV/47rU'
    '/TF0D3+e6PuBfemi2egQIgM7rCKn8rzrngVa+ZMjJW0DYYhNYBBA7RPPy1X0bFuvQMFYNR7rYNBRn4pyUB2Mo6pAapvEy8o/Jt2B'
    'qR1kNKDSrO1ih2+/7eX5aWsLGVm4Xkqxnzu3BYXpvW1dDrUaPunfNQIdNpKw4t3RnoWko32I7GeDjiVWODZWkjHrPMqpQtUY0r1c'
    'D2ksUWjk2qqemtnHKHWUvWWal5dzTHM8NnxXK1RzCwNOwIBTacCcIfoNsHZGGadIqcCinibqPYdkU3yeV7zB3gqPBzn8US5DBOA5'
    'y/m6bdVSyK+YMNvlsJwZah0FVi0X5fOC9t798/6HX+8zN8inBnXcGnLEgtHsMr9aTx+uIvAttWmzetWpTS4mC99hShn3HVWIxkaU'
    'hlqVpYayMtRtkfcBQo5hFyBOyG/ncNMoICB2ZLk6RmgBZtegNPUKGKtmP065XM3wZhLzqVzQ8Q7NK8SXLEPpk/a2+NoYKLOpmFch'
    'DOe643q3JozV2tBbc/sOkXXH8VMqXb93L+TnDWpHc+9QkEf+8vbngR2dKhXP0Wssm9fJcOA1m1j4QCmvwy1aTaGhOb+RqCIVKn9i'
    '0W07pRGtHrV+pzcpUOut3ADNI7JpG06t3fOIIGXkQiTCYrCnJdQkFcXMqWN2Aq+rqtyGDKPbM1x2JftnauqZJlerX8zB1TV2T+uL'
    'w6N46cyZm7fwbM32vSDcJBDKmt0NMVEGD01KBCNBpXXnkZmwDBwkSCKPi6WfNI5JgzyMGHzisHJD2Tnm+uLuMiMN4MlgSZBNrs63'
    'WQ7suFrM6AxpmXVE+Us1OU4Yt7lxbXdUk4c2mA4MhDPZEZ9fOQjwyK3juPGBbN933XkYNSv55pMoklBDZbPxOz8hI49d+BPPVF6r'
    'LehAC0RZbnUaO2CbBra0cRpxqEoIvn8HJNsPSejNMEOgERNTIew8n9y7F55x6Z9JyjPT53DMYarZzXIaZZbVbuR/YJVp6ffgIMPf'
    '2fXDJJM5c5vSJHTl1yGvPHXjHtEubHd7N4fC4SdTJ4/JKL+Ek2FJzMgYTzRjyDktQVAPHa0m+RXN/C68zhK4RDvFvKvdTh+Cy4xv'
    'Za9Tj4h95oNk4JZbz/i3vXI/5NXv3S/3b/IWtEzaagqqY28JhrWO7RlJMQU5ISpywimLAWkqODSJ6Uh9OvyoFe34kRqsfuRkOnxO'
    'C8oPM8r63aEPY7jE1/DDV7NCoTG9FlGD38v1EaCCh9xVF4hj5jLGHjB4DXV6RtnTiB0FFzx5EpzY+a1c2BtMJGVkkVEt0Oy83N9R'
    'FmiMzN2ZpNQRGeg2zGoTP1T4ZB92sIEBuhbdXkLfVVOWpG/aX2PRVuGXNVv1mEpyeFJhTacVjAV2fYigPIzMPHIt104/wLnkvQXT'
    'uNxBwOyGUK2RN+n+cRDCCrBb7jSxLg5dges3yt9KDQO3ndpZFesWSQi4+vqy7+DKyLNokl3XH+1Uzp1xW7GjrDErC1hc6zejkB/C'
    'u9K9udkmfYNNNkj1spN8VSBHRihojHKIZVCRnvrPUuOUnVhhdpMrUcxo7DhViysP5CdpeCU3zritLM7C+5+xQiDWqdsM5+Lwo2A3'
    'GlZW802s0+YVx12wBk9tRp/YVW96SGShPK2qianKf17x/pKXE+viZmMf1mqXp63tlONvTCJpWwP/CTAv5EvEf4nPYrnOgPfNFx/P'
    'LDN+DcQYpw0BNWboXHMKHeMq1HTAxzAUWhoehoYOeYYSKiMXhsHT1+oAj/SufRiA+hbX77ud73LZUCR3nKkH0QILF9io+oCLpAi+'
    'OL8j3URgGCGzyFXpYwCj0AVdHLhbQ6+GdruWMbMNhKbRSD9fdyuJ0dZjrkoPWKHJGsWUBTvycd1XZJXsvr1MPm5nDwbCyndGO7/F'
    'TcyWn67m1bJvuC3bru3nYWY4Lf6rKzz6m52Be31QbTsDGOMaKzEtivzAgg+bZD06QXnJ+lBJrSuM/AMCQwgJ/Wi4vwE3fJ8HboaE'
    'JSc80Ybmk/jMyeDQ2tdHF24gibfmLc1dN3mcJKgh/Zr4h9dBIKFsiT+6b+zE9nMX4pVmVjcVjfxC2fh64+tY2jD8wbAFvRWWPzyu'
    '17IABrFJk8ZROnRHSdleEoxEn3sHMLljgUn2FK0pFhgLBkCgGZfSEC31N18sO9y5FnRoWs+yI35WiQLMF7E207T8lPIaXxTL6gB9'
    'Ks4Rr2l752QrIozQlKYRucB4T7ed2aDMhyhr9R2GfNCoBleaEJqr2XHCklIIyECyEg2R5RIvBzFfKHdRUHdhJfmJcwhddxPgTwwG'
    'QU90FUMoyR2lN4Oyk0Q2b1S+xRVUkxqaNPiMNs2WNKFf316Y0PaJDakoVJlyY6WuawHLLnmnw2VEEnz98gdn/jX70dKwNn7zX/+e'
    'aSlOkJ/a9xf0SoZjhAgKNSkuUcbYIgDiayl1Dcng5J1mw1WlrnZWXpfCLgoe8irw1h+qCtbL76pjRLhVg2FkB15YVr/GQnMUpGAV'
    'czWnCqqAMy53uJPScGcAA6jPsfTRpwZHIZfmnDWGFXztStHe6mVxC2Kgn7oIm9yOCaKft5oUm9mTYbeudSSSOtYAuNarGSWM8wqp'
    'Ep4XaDwAwmuK5aUM2HaZiZluUKMMPrfShA+LdlARQNUuuQNObuWFXXICzek74A9woLpYbq2bIEMCgwx6F/XCISdoLBVjm7SkdRel'
    'NwJa88kkBD0N28HJ9nutkcmBFaroCjWWURVI7gBHLGddHlC7GHw16hYLVhufcmH6Z0yldvWsPaTn+t67EyNcFP4ySV/hNdLlU3WR'
    'LLxX1jHCKKCA4XOIdOHlFED2aRHW62RaLRkjcFLk9Ct5xSQmExjnlM5BEh/ipMIY5PhWRQRujxGil0r4KxjkROd8XbASY4QnonVp'
    'x9N8dqZAuFNFEAgIgy1cQZAxi9gSs+5hjNAbMpywTjJDpBH2d1JEvPinMinivGQNXp/f9K70WInMvUTo0mIgE5Tb2oEWyA/2PfOq'
    'mO8pku6QndHiOtvlrh4WS1gu9ewaLhcfVLAgRTLckOPrE0eH2SGL9MrYm4n3TImX94IpTAYhq5ELwu+x8QcjjDpCOjo5x6g/qfau'
    '6lYANGXta18mbAnArjVYNvIb68W2cu/5apqKhVU6sgNlzBnaCXkGmyFnrszuZQ+smpjfBmflEf3g+iPq77E/n5WLklN999fA1+Dz'
    'Y1J4BVoAzeL3KOs/2NnJfp2Von70u94zYKn7v+tF3RyBnXZPjZw2bqoABDFcqiyxDtuAKKLW36Es9aANleKHD4Cs8HPJq2cnavHs'
    's8gGjffFS/4xKUgjp+jRlrEUK3Jlf4UKM632KJO031kGyVdHs0RPTV60kb3kQjxUxJI3xZ9X5QJJvEztVYigkE69q/n31UxEntUM'
    'GSG1JtrRlMFw05qnBxF5tvXM9dW4Y+CWzJiVup70/uAZMJY8281ahHQoY8EPtsjy1daLAhfjabWFmXJCD92rIpCWu3fZF7MB4TFN'
    'evYPOFCq9GkAzlVhmqyKhAvwWHR4ROP0/BrzOcpUQGEcCdMX6a3fmy/KcxR6HWZhFF+NnDyS/do+FZUMOJrFNHqNFjQQ+cI3eBjz'
    'GkP0llnHfzJFzGKsB18zkKiT5kCQ9t4Yhfz1QkiFT6VcnkcWyEjhdgN3RpCjsGxuFHKZ8UdYtLgwjPsBJoyIZbqewlP8qfkoXxAO'
    's859Eo6GnnregOkaiHZDnOMGIb/rvRSB4S5yjvEoP/xQwUPDj6+LxYk8frf34R3eXmZ/l/3mg/a+llm/7AT38SSetmoDEjV6cXhr'
    'Hc82dtCR69+cREP1Wq6J2xreuuANTUzFL+GqVwZQDlJhAbcTA7izB/9gUIu4niHZXoggZSRHIEZFMXjLVPDc8y9viXXOHQ1FNPwL'
    'WOicHk5MNOE7i+JK01nVqO2YJq2MSP+rqzuGweYFUd/oMofEZGEm1FdHWf9HZnEwKRgfppcwWBF5ahDldz999fLozasXSPHuIcqJ'
    'PgFw/GFmf6qvwf/J0iPDzBnQYlfyw+RQhuMaSV4VBL130dFX+WlEG9EQ2hmGDePRGxl170NSD5a8p8FxrDaaPPq1VBbP3sPGu8Kf'
    'sxWAbacB0nZkMDABCs/yceUduT6Ata1DXDmjD+x+lb2OuudkecLCrYV6GOF11RmjtPvsF+m4iPcFcG5ZrWqDpLN0z4ORVRLEQx4a'
    'suPywJGpTk5wedgADLQ+4qUiA3RoC18lEzsp/qvPO8a26bjz9zXiqeO+f0sm0yGya8NUak9FdcNaciwyQvtRJGVURNFickeKoQyI'
    'Zgdq7S8fUIivN5Xs0cOEb+mNYLzL4Q050fL27253ud3qslUlJ8BFtYYeF9ATMSu37ErHxw7ez97PmO6Pb+mmKlgsg9Yh0NvMoUJE'
    '2SIO50CNuh4bwQMeHHTgHGxhp5PluxPPSeXr1jolsCHrwK6l2wjr+u44FhMar9QmYw/byQLn4GkmnvcGUd0/gzJPi4x1QDrperTw'
    'nL5nfsNihUNi3uJM/RVNk/EVrGMW+hFfMpaMSj43Mz+0w9q4o6XG5RVvVpHgoScl+r4bWq6JigQVWj1L3e3d8erUmjs7ayNk3WEx'
    'e+i+g1ahFjdwsxHIuH9/+Ool8q/qor9hRK5sFSVjljSpB2bu0MDB8l+Kfp0OAz8fHAR7CMcFp4vMB7aXeoTam8gnGtB5/y8FeJYB'
    'vd9plZkaZg4DXu0iPMLwf6FrbNKiqIUPHkUcWucaf985xTV8zZcMwgZzx/IV/NMT+KVgsxk0bU8P73jA4vBSlxvQ1QO+DBaae/6h'
    'D6msFn5wl7NTp6KURJoG5QIJY6CHZ83ArQRW33XImUQ4YOom2RXJ67ScOcs2vENzWbk7EU76wzt797X8zr58QkUf/Aug1f07/w9r'
    'M3Q2'
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
VERSION = '2026.10.20.2125'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
