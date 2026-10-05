for p in [
    'game/src/app/domain_boot.gd',
    'game/src/app/item_workbench_fight.gd',
    'game/src/app/item_workbench_app.gd',
]:
    d = open(p, 'rb').read()
    bad = [(i, b) for i, b in enumerate(d) if b < 9]
    print(p, 'len', len(d), 'ctrl/nul', bad[:12])