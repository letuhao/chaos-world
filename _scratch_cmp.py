a = open('_npc_head_dump.txt', 'rb').read()
b = open('game/src/contracts/npc_events.gd', 'rb').read()
print(len(a), len(b))
for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
        print('first diff at', i)
        print('HEAD :', repr(a[max(0, i - 60):i + 20]))
        print('WORK :', repr(b[max(0, i - 60):i + 20]))
        break
else:
    print('identical over common prefix')