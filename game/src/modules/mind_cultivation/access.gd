class_name MindAccess
extends RefCounted

## Module-internal accessors, deliberately NOT on the facade (ADR 0095).
##
## `MindCultivationApi` sits at the 12-method ISP cap
## (`tools/arch/rules.py` `MAX_FACADE_PUBLIC_METHODS`), and `path_def` was one of
## those twelve while nothing outside this module ever called it: its only caller
## in the whole tree is `test_mind_path.gd`. A cap spent on an accessor nobody uses
## is a cap not spent on a verb, so `recover_next` had nowhere to go until this
## file existed. Same pattern as `qi_cultivation/access.gd`: moving it costs
## nothing (`tools arch` counts only `api.gd`) and leaves the facade publishing
## verbs. This mirrors the exact reasoning that freed `attach`'s dantian line
## there — `tools arch` cannot see a module-internal accessor.


static func path_def() -> CultivationPathDef:
	return MindPath.path_def()
