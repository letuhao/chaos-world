class_name CultivationPathContract
extends RefCounted

## Reference contract for mod-provided cultivation paths (ADR 0184).
##
## A mod adding a new cultivation path must provide three things:
##
## 1. **Seed .tres per realm** — one Resource per realm on the shared ladder,
##    placed under the mod's declared content root. Each seed must carry the
##    fields listed in `REQUIRED_SEED_FIELDS` with valid values.
##
## 2. **A provider** — a StatProvider subclass that calls `RealmRate.factor`
##    for the realm factor. The provider must NOT declare its own RATE_STEP
##    or read `RealmDefaults.ladder()` for a per-realm factor; the only
##    per-realm factor is `RealmRate.factor(rank_id)` (ADR 0066, ADR 0116).
##
## 3. **An api.gd facade** — a RefCounted with at least `attach(actor)` and
##    `panel_state(actor) -> Dictionary`. The facade is the only file other
##    modules may reference.
##
## This class is the validation authority: `ModuleRegistry` calls
## `validate_seed` when a module declares `provides: ["cultivation_path"]`,
## and `tools/cultivation/audit.py` calls it for every declared path family.

## The fields every cultivation-path seed must carry with a valid value.
## These are the intersection of the three exemplar paths (qi, body, mind):
## each seed must author a work budget, a breakthrough pill, and a recovery
## elixir. Path-specific fields (dantian_capacity, sea_capacity, …) are
## authored by the mod's own seed class and are not checked here.
const REQUIRED_SEED_FIELDS := [
	"progress_required",
	"breakthrough_item",
	"recovery_item",
]


## Validate one seed Resource against the contract.
## Returns a list of finding strings; empty means the seed is valid.
static func validate_seed(seed: Resource) -> Array[String]:
	var findings: Array[String] = []
	if seed == null:
		findings.append("seed is null")
		return findings
	# progress_required must be a positive number.
	var progress = seed.get("progress_required")
	if progress == null or not (progress is float) or float(progress) <= 0.0:
		findings.append("progress_required is missing or not positive")
	# breakthrough_item must be a non-empty StringName.
	var breakthrough = seed.get("breakthrough_item")
	if breakthrough == null or not (breakthrough is StringName) or String(breakthrough) == "":
		findings.append("breakthrough_item is missing or empty")
	# recovery_item must be a non-empty StringName.
	var recovery = seed.get("recovery_item")
	if recovery == null or not (recovery is StringName) or String(recovery) == "":
		findings.append("recovery_item is missing or empty")
	return findings


## Validate that a provider source calls RealmRate.factor and does not
## declare its own rate constant. Returns a list of finding strings.
## `source` is the provider's GDScript source text.
static func validate_provider_source(source: String) -> Array[String]:
	var findings: Array[String] = []
	if source == "":
		findings.append("provider source is empty")
		return findings
	# Strip comment-only lines so a comment mentioning the constant does not
	# satisfy the guard (ADR 0188's rule for every guard).
	var code_lines: Array[String] = []
	for line in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	var code := "\n".join(code_lines)
	# The provider MUST call RealmRate.factor.
	if not code.contains("RealmRate.factor("):
		findings.append("provider does not call RealmRate.factor")
	# The provider MUST NOT declare its own RATE_STEP or NEUTRAL constant.
	if code.contains("const RATE_STEP") or code.contains("const NEUTRAL"):
		findings.append("provider declares its own RATE_STEP or NEUTRAL; use RealmRate")
	# The provider MUST NOT read RealmDefaults.ladder() for a per-realm factor.
	if code.contains("RealmDefaults.ladder()"):
		findings.append("provider reads RealmDefaults.ladder(); use RealmRate.factor instead")
	return findings
