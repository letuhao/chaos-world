import os

for p in [
    'game/tests/modules/market/test_zz_probe_def0128.gd',
    'game/tests/modules/market/test_zz_probe_def0128.gd.uid',
]:
    if os.path.exists(p):
        os.remove(p)
        print('removed', p)
    else:
        print('absent', p)