import glob
import os

fs = sorted(glob.glob('build/logs/*'), key=os.path.getmtime)
print(len(fs))
for f in fs[-6:]:
    print(f)