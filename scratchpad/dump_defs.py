import json, sys, io
sys.stdout.reconfigure(encoding="utf-8")
ids = {"DEF-0053","DEF-0059","DEF-0111","DEF-0119","DEF-0147","DEF-0085"}
with open("docs/deferred.jsonl", encoding="utf-8") as f:
    for line in f:
        d = json.loads(line)
        if d.get("id") in ids:
            print(json.dumps(d, indent=2, ensure_ascii=False))
            print("---")