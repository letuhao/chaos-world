import glob
import os

fs = sorted(glob.glob('build/logs/17511*'), key=os.path.getmtime)
for f in fs:
    print('=====', f, os.path.getsize(f))