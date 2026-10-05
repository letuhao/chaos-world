import time

PATH = r"game/src/contracts/npc_events.gd"

prev = None
for i in range(40):
    with open(PATH, "rb") as handle:
        data = handle.read()
    current = (len(data), data.count(b"\x00"))
    if current != prev:
        print("bytes=%d nuls=%d" % current, flush=True)
        prev = current
    if current[1] == 0:
        print("CLEAN", flush=True)
        break
    time.sleep(20)
else:
    print("STILL CORRUPT after 40 probes", flush=True)