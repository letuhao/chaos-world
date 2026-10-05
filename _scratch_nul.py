d = open('game/src/contracts/npc_events.gd', 'rb').read()
for i, b in enumerate(d):
    if b == 0:
        left = d[max(0, i - 14):i].decode('utf-8', 'replace')
        right = d[i + 14:i + 28].decode('utf-8', 'replace')
        print(i, repr(left), '||', repr(right))