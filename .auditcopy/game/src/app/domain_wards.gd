class_name DomainWards
extends RefCounted

## The two FACTS a domain run needs from outside its own module: the weather a
## template authors, and what the hero's wardrobe, codex and bag say they can ward.
##
## ## Why this is a SIBLING and not more of `DomainBoot`
##
## Extracted from `domain_boot.gd` because that file passed the thousand-line ceiling.
## The cut is the one this file's own banner already drew — the section that opens
## "the two facts a domain run needs from outside its own module" — because both of
## its halves are the same kind of thing: a CONTACT with a module `domain` may not
## depend on. `domain` declares `core` + `contracts` only (`tools/arch/registry.json`),
## so it cannot name `items`, `techniques` or read an authored `.tres` without
## breaking that edge, and `app/` is the composition root and may depend on anything.
##
## ## INHERITANCE, and that is the whole reason it works
##
## `DomainBoot` extends this class, so every name below is reached by its
## UNCHANGED spelling: `DomainBoot.publish_ward_tags`, `DomainBoot._template_weather`
## and `DomainBoot._map_accepts` all still resolve, and `tests/modules/domain/
## test_domain_weather.gd` calls two of them without knowing this file exists. GDScript
## cannot alias a static from one script onto another and cannot extend two classes, so
## the base is the only shape that keeps both spellings compiling. That is the same
## arrangement `ItemWorkbenchApp` -> `ItemWorkbenchBody` uses, and unlike a delegation
## it leaves the entry point where every caller already found it.
##
## **No public method was renamed, no signature changed and no body was re-derived**:
## every function below moved with its docblock, character for character. The element and
## consumable vocabularies moved with them and are declared ONCE, HERE — the sibling-mirror
## they were paired with was only needed while the two files were siblings, and once this
## class became `DomainBoot`'s BASE a second declaration was a hard parse error
## ("already exists in parent class DomainWards") that stopped `DomainBoot` resolving for
## everything naming it, `ItemWorkbenchApp` included. `DomainBoot.ELEMENT_TAGS` still
## answers; it is this member.
##
## ## The loops below stay BOUNDED
##
## `_template_files` and `_inhabitant_catalogue` walk a closed content directory with
## `while file_name != ""`, which is the `DirAccess` terminator itself: `get_next()`
## returns `""` at the end of the directory, exactly the idiom `DomainApi.templates`
## uses. No loop here grows the container its own condition tests.

## The element vocabulary the environment layer speaks. CLOSED, and it is exactly the
## set `EnvironmentField.HOSTILE_ELEMENTS` keys on, because a tag outside that set
## cannot answer any zone and publishing it would inflate the list for nothing. Declared
## here once and inherited, so `DomainBoot.ELEMENT_TAGS` is this member rather than a
## second list that could disagree with it.
const ELEMENT_TAGS: Array[StringName] = [
	&"fire",
	&"ice",
	&"water",
	&"lightning",
	&"metal",
	&"wood",
	&"dark",
	&"light",
	&"earth",
	&"wind",
]

## The consumable subtypes a mitigation can be carried as. Authored vocabulary
## (`ItemSubtype`), named here rather than rebuilt, so a new consumable subtype is one
## edit in the items module rather than a second list to drift.
const CONSUMABLE_SUBTYPES: Array[StringName] = [
	ItemSubtype.PILL,
	ItemSubtype.ELIXIR,
	ItemSubtype.TALISMAN,
	ItemSubtype.FOOD,
]


## The weather `template_id` authors, or [constant DomainMap.WEATHER_NONE].
##
## ## Why this is a TEXT read and not a field on `DomainTemplateDef`
##
## `weather` is authored on the template `.tres` as a plain `weather = &"ashfall"` line,
## and read back with [method RegEx]. That is deliberate rather than a shortcut:
## `DomainTemplateDef` is a `Resource` whose exported set is another file's to change,
## so a field there would mean editing a module file this change does not own. Reading
## the authored line is also the same discipline `tools/` applies to this corpus — a
## value that is not a field of the resource is still content, and content is read, not
## inferred. The `[method _scalar]` helper normalizes Godot's `&"x"` / `"x"` spelling
## away, which is the same normalization `tools/acquisition/chain.py` performs.
##
## Refused by `DomainMap.accepts_weather` before it is returned, so a template naming a
## weather outside the closed catalogue contributes NO weather rather than a string
## every zone would silently ignore. `WEATHER_NONE` (no `weather` line at all) is a
## legitimate authored state, not a failure.
static func _template_weather(template_id: StringName) -> StringName:
	for path in _template_files():
		var text := _read_text(path)
		if _scalar(text, "template_id") != String(template_id):
			continue
		var authored := _scalar(text, "weather")
		if authored.is_empty():
			return DomainMap.WEATHER_NONE
		var id := StringName(authored)
		return id if _map_accepts(id) else DomainMap.WEATHER_NONE
	return DomainMap.WEATHER_NONE


## Every `templates/*.tres` path, sorted. Bounded `for`/enumeration over a closed
## content directory; the `while` terminates because `get_next()` returns `""` at the
## end of the directory, which is the same idiom `DomainApi.templates` itself uses.
static func _template_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DomainApi.TEMPLATE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			out.append("%s/%s" % [DomainApi.TEMPLATE_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## The authored value of `name` in a `.tres`, unquoted, or `""` when the file does not
## declare it. One helper so every authored scalar this file reads is parsed the same
## way; `RegEx` rather than `String.split` because the value is a `&"..."` literal and
## its quoting has to come off before the string is compared to an id.
static func _scalar(text: String, name: String) -> String:
	var pattern := RegEx.new()
	if pattern.compile("(?m)^%s\\s*=\\s*(.+?)\\s*$" % name) != OK:
		return ""
	var found := pattern.search(text)
	if found == null:
		return ""
	var value := found.get_string(1).strip_edges()
	# `StringName` literals in a `.tres` are written `&"name"`, so the `&` sits OUTSIDE
	# the quotes. Stripping only the quotes left `&ashfall`, which never compared equal
	# to `ashfall` — which is why an authored weather read back as "no weather" and every
	# zone in the domain silently ran at its authored band.
	if value.begins_with("&"):
		value = value.substr(1).strip_edges()
	for quote in ['"', "'"]:
		if value.length() > 1 and value.begins_with(quote) and value.ends_with(quote):
			return value.substr(1, value.length() - 2)
	return value


static func _map_accepts(id: StringName) -> bool:
	var probe := DomainMap.new()
	return probe.accepts_weather(id)


## Publish what this actor CARRIES into the three `module_data` slots
## `EnvironmentField` reads, so `GEAR_CAP`, `TECHNIQUE_CAP` and `PILL_CAP` gate a real
## list instead of a permanently empty one.
##
## ## Why this is here and not in `environment_field.gd`
##
## `EnvironmentField` reads three tag keys and nothing writes them, which is why a
## cultivator wearing a fire ward used to get ZERO mitigation while the screen still
## printed "answered by: gear, pill, affinity". The three caps were live caps over
## lists that were always empty — a cap that gates nothing.
##
## `domain` cannot fix that itself: the tags live in `items` (equipped instances and
## inventory) and `techniques` (the codex and the loadout), and `domain` is allowed to
## depend on neither. So this reads them THROUGH THEIR FACADES — `ItemsApi` and
## `TechniquesApi` — and writes only the tag strings into the three keys this module
## already owns. No sibling payload shape is depended on: `EnvironmentField` still reads
## a flat `{"tags": [...]}` list and nothing here walks anybody's internals.
##
## ## What the tags MEAN, and why they are element names
##
## The three lists carry ELEMENTS (`&"fire"`, `&"ice"`, …), not invented ids. That is
## the honest join key: `EnvironmentZoneDef.tags` is already the "elements this zone is
## hostile to" list, so a wardrobe of fire-and-ice gear answers the same question the
## zone already asks of a spirit root. A consumable named "fire" is a cooling draught;
## an orb tagged `fire` is a fire ward. Neither needs a registry this module cannot
## own, and neither can be a silent no-op: if nothing in the corpus carries the
## element, the list is empty and the lever does not fire, which is correct.
##
## Idempotent: every key is overwritten from the actor's CURRENT state rather than
## appended to, so re-entering a room cannot accumulate stale tags.
static func publish_ward_tags(player: Actor) -> Dictionary:
	if player == null:
		return {"gear": 0, "technique": 0, "pill": 0}
	# GEAR: what is WORN, not what is owned. A bag full of robes is not a ward, so this
	# reads `Equipment.all()` — the slots actually occupied.
	player.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": _equipped_elements(player)})
	player.set_module_data(EnvironmentField.TECHNIQUE_TAGS_KEY, {"tags": _learned_elements(player)})
	player.set_module_data(EnvironmentField.PILL_TAGS_KEY, {"tags": _carried_elements(player)})
	return {
		"gear": _size(player, EnvironmentField.GEAR_TAGS_KEY),
		"technique": _size(player, EnvironmentField.TECHNIQUE_TAGS_KEY),
		"pill": _size(player, EnvironmentField.PILL_TAGS_KEY),
	}


static func _size(player: Actor, key: StringName) -> int:
	var tags: Array = player.get_module_data(key).get("tags", [])
	return tags.size()


## Every element carried by what the actor is WEARING, canonical and de-duplicated.
## Bounded `for` over the five equipment slots and each def's own authored tag list.
static func _equipped_elements(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var equipment := ItemsApi.equipment(player)
	if equipment == null:
		return out
	# Bounded `for` over `Equipment.SLOTS`, which is the closed five-slot set. Iterating
	# the slots rather than `all().keys()` keeps the order canonical, so the published
	# list is a pure function of what is worn rather than of dictionary order.
	for slot in Equipment.SLOTS:
		var def := equipment.definition(slot)
		if def == null:
			continue
		_add_elements(out, def.tags)
	return out


## Every element carried by what the actor has LEARNED, through the techniques facade.
## Read from the codex the facade attaches on demand, so an actor who has never opened
## the technique screen still answers. Empty when no technique is attached, which is the
## honest "this actor knows nothing that helps" rather than a fabricated default.
static func _learned_elements(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var codex := TechniquesApi.codex(player)
	if codex == null:
		return out
	# Bounded `for` over the codex's own entries — authored content, small, and the only
	# list the techniques module publishes as ids rather than as a read model.
	for technique_id in _codex_ids(codex):
		var def := TechniqueCatalog.instance().definition(StringName(technique_id))
		if def == null:
			continue
		_add_elements(out, def.tags)
	return out


static func _codex_ids(codex: TechniqueCodex) -> Array[String]:
	var out: Array[String] = []
	# Bounded `for` over the codex's own technique ids — authored content, small, and the
	# only list the techniques module publishes as ids rather than as a read model.
	for technique_id in codex.technique_ids():
		out.append(String(technique_id))
	return out


## Every element carried by what the actor has IN THE BAG as a consumable.
##
## INVENTORY, not equipment: a pill is spent, not worn, so it cannot come from
## `Equipment`. Read through `Inventory.stacks()` and `.instances()` — the two lists
## that between them hold every carried item — and narrowed to the authored CONSUMABLE
## subtypes, because an herb in the bag is not a mitigation the player chose to carry.
static func _carried_elements(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var inventory := ItemsApi.inventory(player)
	if inventory == null:
		return out
	for batch in inventory.stacks():
		if batch.def_ref == null or not _is_consumable(batch.def_ref):
			continue
		_add_elements(out, batch.def_ref.tags)
	for instance in inventory.instances():
		var def := Crafting.resolve(instance.def_id)
		if def == null or not _is_consumable(def):
			continue
		_add_elements(out, def.tags)
	return out


## Whether `def` is something a body CONSUMES rather than wears or learns. The
## authored subtype list, not a name test: a subtype nobody declared is not a pill.
static func _is_consumable(def: ItemDef) -> bool:
	return CONSUMABLE_SUBTYPES.has(def.subcategory)


## Add every element-shaped tag in `tags` to `out`, de-duplicated and canonically
## ordered at the end. A bounded `for` over authored content; no `while`.
static func _add_elements(out: Array[StringName], tags: Array[StringName]) -> void:
	for tag in tags:
		var element := StringName(str(tag))
		if ELEMENT_TAGS.has(element) and not out.has(element):
			out.append(element)


## Every authored inhabitant, as `inhabitant_id -> InhabitantDef`, read from the same tree
## the module's own `templates()` reads (`DomainApi.INHABITANT_DIR`). Content is read here
## rather than restated, so a newly authored `.tres` is a file and never a code edit
## (ADR 0074) — the same rule `NpcBoot.install`'s `load_authored` follows.
static func _inhabitant_catalogue() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(DomainApi.INHABITANT_DIR)
	if dir == null:
		return out
	var names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		var def := load("%s/%s" % [DomainApi.INHABITANT_DIR, name]) as InhabitantDef
		if def != null:
			out[String(def.inhabitant_id)] = def
	return out
