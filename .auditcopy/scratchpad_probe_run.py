"""Probe: what does the headless Godot process see for res://src and the routes table?"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import tools.godot as g  # noqa: E402

OUT = pathlib.Path(
    r"C:\Users\NENESC~1\AppData\Local\Temp\commandcode\D--Works-source-chaos-world"
    r"\f74d4dea-bd49-483e-8ff6-0da7926f84b2\scratchpad\probe_out.txt"
)

r = g.run_godot(
    ["--headless", "--path", "game", "-s", "res://tests/_probe_routes.gd"],
    capture=True,
    tag="probe",
)
OUT.write_text(
    "RC=%s\n---STDOUT---\n%s\n---STDERR---\n%s\n" % (r.returncode, r.stdout[-4000:], r.stderr[-2000:]),
    encoding="utf-8",
)
print("wrote", OUT)