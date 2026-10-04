import io

for P in (
    "game/src/app/domain_boot.gd",
    "game/src/app/domain_scene.gd",
    "game/src/app/item_workbench_app.gd",
):
    s = io.open(P, encoding="utf-8").read()
    print(P, s.count("\n") + 1)
