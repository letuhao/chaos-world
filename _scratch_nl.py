p = 'game/src/contracts/npc_events.gd'
d = open(p, 'rb').read()
if not d.endswith(b'\n'):
    open(p, 'wb').write(d + b'\n')
    print('added newline')
else:
    print('already ends with newline')