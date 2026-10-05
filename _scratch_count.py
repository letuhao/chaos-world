import re, sys
from pathlib import Path

sys.path.insert(0, r"D:\Works\source\chaos-world")
from tools.arch import enforce  # noqa

FUNC_RE = enforce.FUNC_RE
p = Path(r"D:\Works\source\chaos-world\game\src\modules\npc\api.gd")
text = p.read_text(encoding="utf-8")
public = [n for n in FUNC_RE.findall(text) if not n.startswith("_")]
print("npc/api.gd public:", len(public), public)
print("private:", [n for n in FUNC_RE.findall(text) if n.startswith("_")])