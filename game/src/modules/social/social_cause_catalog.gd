class_name SocialCauseCatalog
extends RefCounted

## The authored cause catalog (ADR 0076). Every relationship change is one of these ids,
## so the ledger is a closed vocabulary rather than an accumulating set of magic numbers.
##
## Ships with the causes the cultivation fiction actually needs. A cause is a `Resource`
## so a designer can author more; this catalog is only the default set.

static var _shared: SocialCauseCatalog = null

var _causes: Dictionary = {}


static func instance() -> SocialCauseCatalog:
	if _shared == null:
		_shared = SocialCauseCatalog.new()
		_shared._install_defaults()
	return _shared


func _install_defaults() -> void:
	_add(&"gifted_item", {"standing": 1.0, "trust": 0.02, "tags": [&"gift"]})
	_add(&"helped_in_combat", {"standing": 3.0, "trust": 0.08, "tags": [&"combat"]})
	_add(&"spared_in_combat", {"standing": 4.0, "trust": 0.1, "tags": [&"combat"]})
	_add(&"protected_from_death", {"standing": 6.0, "trust": 0.12, "persistent": true})
	_add(&"taught_technique", {"standing": 3.0, "trust": 0.06, "persistent": true})
	_add(&"honoured_a_debt", {"standing": 3.0, "trust": 0.08, "persistent": true})
	_add(
		&"shared_brotherhood",
		{"standing": 5.0, "trust": 0.15, "persistent": true, "promotes_to": SocialBondClass.SWORN}
	)
	_add(&"robbed", {"standing": -6.0, "tags": [&"harm"]})
	_add(&"attacked_unprovoked", {"standing": -8.0, "tags": [&"combat", &"harm"]})
	_add(&"killed_their_kin", {"standing": -10.0, "tags": [&"combat", &"harm"]})
	_add(&"betrayed_oath", {"standing": -12.0, "trust": -0.4, "tags": [&"oath", &"harm"]})
	_add(&"slandered", {"standing": -4.0, "trust": -0.12, "tags": [&"harm"]})


func _add(cause_id: StringName, fields: Dictionary) -> void:
	var cause := SocialCauseDef.new()
	cause.id = cause_id
	cause.persistent = bool(fields.get("persistent", false))
	cause.standing = float(fields.get("standing", 0.0))
	cause.trust = float(fields.get("trust", 0.0))
	for tag in fields.get("tags", []):
		cause.tags.append(StringName(tag))
	cause.promotes_to = StringName(fields.get("promotes_to", ""))
	_causes[String(cause_id)] = cause


func cause_definition(cause_id: StringName) -> SocialCauseDef:
	return _causes.get(String(cause_id))


func cause_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for cause_id in _causes.keys():
		out.append(StringName(cause_id))
	out.sort()
	return out


## Test seam: drop the authored set entirely, so a suite installs exactly what it needs.
## Note this clears the DEFAULT causes too — a test that then uses `gifted_item` without
## installing it will correctly find nothing, which is why the social suite authors its
## own causes rather than leaning on the shipped ones.
func reset() -> void:
	_causes.clear()


## Test seam: restore the shipped default set, for a suite that only overrode one cause.
func install_defaults() -> void:
	_causes.clear()
	_install_defaults()


func install(defs: Array[SocialCauseDef]) -> void:
	for cause in defs:
		_causes[String(cause.id)] = cause
