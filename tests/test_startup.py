#!/usr/bin/env python3
"""Mock credentials/native input only; no privileged installation or host input."""
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='nxvnc-startup-') as d:
    folder=Path(d)
    common=['cc','-std=c89','-pedantic','-Wall','-Wextra','-Werror','-I'+str(ROOT)]
    for intel in (False,True):
        binary=str(folder/('intel' if intel else 'native'))
        flags=['-DNXVNC_STARTUP_TEST']+(['-DNXVNC_INPUT_INTEL=1'] if intel else [])
        sources=['NXVNCStartup.c','NXVNCInput.c','tests/startup_fixture.c','tests/test_startup.c']
        subprocess.run(common+flags+[str(ROOT/s) for s in sources]+['-o',binary],check=True)
        subprocess.run([binary],check=True)
    objects=[]
    for src in ('NXVNCStartup.c','NXVNCInput.c','tests/startup_fixture.c'):
        obj=str(folder/(Path(src).stem+'.o'));objects.append(obj)
        subprocess.run(common+['-DNXVNC_STARTUP_TEST','-DNXVNC_INPUT_INTEL=1',
            '-c',str(ROOT/src),'-o',obj],check=True)
    main_obj=str(folder/'main.o')
    subprocess.run(['cc','-Wall','-Wextra','-Werror','-Wno-missing-method-return-type','-Dmain=NXVNCMain',
        '-I'+str(ROOT),'-c',str(ROOT/'main.m'),'-o',main_obj],check=True)
    app=str(folder/'main-test')
    subprocess.run(['cc','-Wall','-Wextra','-Werror','-Wno-missing-method-return-type','-Wno-incomplete-implementation',
        '-I'+str(ROOT),'-framework','Foundation',str(ROOT/'tests/test_startup_main.m'),
        main_obj,*objects,'-o',app],check=True)
    subprocess.run([app],check=True)
