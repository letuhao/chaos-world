class_name L
extends RefCounted

## The one localization resolver (ADR 0916). Every player-facing string is a key:
##
##   label.text = L.t("LOC_UI_PANELS_AB12CD34")
##
## ## Where the English lives, and why it is not at the call site
##
## The English is the base catalog's `en` row (`game/locale/<owner>.tres`), not an argument
## on the call. That keeps a text change a DATA change — a mod, a translator, or a copy edit
## never has to touch `src/`, and two owners never collide on one shared file. The cost is
## that a key with no row resolves to the KEY itself, so a missing row would leak a slug to a
## player; `tools i18n check` is what refuses to ship one. `source` stays as an optional
## second argument for a caller that genuinely has the English in hand (a derived content
## key); core UI passes none.
##
## ## Roots, not one directory
##
## Catalogs are per OWNER (`ui_panels`, `ui_screens`, `items`, …), so a change to one area
## touches one file. The base pass loads `res://locale`; a mod registers its own root through
## the `locale_roots` seam and it is layered on top, later-wins, exactly like a content root
## overlay. See the ADR for the seam.

## First-party catalogs. One file per owner, discovered recursively.
const BASE_ROOT := "res://locale"

## Only `Translation` resources; `gaps.json` and any other sibling is ignored by suffix.
const CATALOG_SUFFIX := ".tres"

## Every catalog key starts with this — `LOC_<OWNER>_<NAME>`.
const SLUG_PREFIX := "LOC_"

## The longest a single key can be when scanning a composed string for embedded tokens. A key
## is `LOC_<OWNER>_<HASH10>` or `LOC_<OWNER>_<ID>_<FIELD>`, and the boundary is found by longest
## resolving prefix (see [method _longest_resolving]) because `_`/letters are legal in both.
const MAX_KEY_LENGTH := 96

## Control properties a scene may declare a key in. A `.tscn` literal has no call site, so a
## screen resolves its own subtree instead (see [method localize_tree]).
const SCENE_TEXT_PROPERTIES := ["text", "placeholder_text"]

## A node tree deeper than this is a scene bug, not a screen. Bounds the walk below.
const SCENE_MAX_DEPTH := 64

## Plural form COUNT per locale. A text `.tres` `Translation` carries no CLDR data, so the count
## lives here, in ONE place, and [method tn] picks the form. A locale absent from this table is
## refused LOUDLY rather than given an English-shaped plural — a wrong plural is worse than a
## missing one — and adding one is a one-line edit here plus that locale's own catalog rows.
const PLURAL_FORMS := {
	"en": 2,
	"en_us": 2,
	"en_gb": 2,
	"de": 2,
	"es": 2,
	"fr": 2,
	"it": 2,
	"pt": 2,
	"vi": 1,
	"zh": 1,
	"ja": 1,
	"ko": 1,
	"th": 1,
	"id": 1,
	# The Slavic three-form rule: 1 -> form 0, 2-4 (except 12-14) -> form 1, everything else 2.
	"ru": 3,
	"uk": 3,
	"pl": 3,
	"cs": 3,
	"sk": 3,
}

## System font families that cover a non-Latin script, best first. No font ships in this repo, so
## a CJK locale resolves an OS font instead of drawing boxes, and `allow_system_fallback` covers
## a machine whose named families all miss. A shipped font asset would supersede this, not
## replace the mechanism.
const SCRIPT_FONT_FAMILIES := [
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"Noto Sans SC",
	"Microsoft YaHei",
	"SimHei",
	"PingFang SC",
	"Hiragino Sans GB",
	"Yu Gothic",
	"Meiryo",
	"Malgun Gothic",
]

## The script prefixes that need [constant SCRIPT_FONT_FAMILIES] rather than the engine default.
const SCRIPT_FONT_PREFIXES := ["zh", "ja", "ko"]

static var _installed_base := false
static var _extra_roots: Array[String] = []


## The resolved text for `key`.
##
## The game's DATA holds keys, not English (`display_name = "LOC_ITEM_JADE_PENDANT_NAME"`), and
## one item is defined once for every language. This is the single point that turns a key into
## the current locale's text at display time. `source` is an optional fallback for a caller that
## genuinely has a default in hand; the catalogs are the real source.
##
## It also resolves keys EMBEDDED in a composed string, so a sentence built from several fields
## reads correctly without every composition site having to resolve its own parts. English that
## contains no key is returned untouched, so the call is safe on any display string.
static func t(key: String, source: String = "") -> String:
	install()
	var resolved := TranslationServer.translate(key)
	if resolved != key:
		return resolved
	if key.contains(SLUG_PREFIX):
		var woven := _resolve_tokens(key)
		if woven != key:
			return woven
	return source if not source.is_empty() else key


## The text for a COUNTED string. `key` is the row for form 0 (the singular in a two-form
## locale); a locale's other forms live at `key_1`, `key_2`, … A locale absent from
## [constant PLURAL_FORMS] is refused LOUDLY — a wrong plural is worse than a missing one, and a
## silent fallback is how a wrong one ships.
static func tn(key: String, count: int) -> String:
	install()
	var locale := TranslationServer.get_locale().to_lower()
	var forms := int(PLURAL_FORMS.get(locale, 0))
	if forms == 0:
		push_error("L.tn: no plural rule for locale '%s'; add one to PLURAL_FORMS" % locale)
		return t(key)
	var form := _plural_form(count, forms)
	return t(key) if form == 0 else t("%s_%d" % [key, form])


## Which form `count` takes, for a locale with `forms` of them. One rule per SHAPE of language
## rather than per language: no plural, a singular/other pair, and the Slavic three-form rule.
static func _plural_form(count: int, forms: int) -> int:
	if forms <= 1:
		return 0
	var size := absi(count)
	if forms == 2:
		return 0 if size == 1 else 1
	var last := size % 10
	var last_two := size % 100
	if last == 1 and last_two != 11:
		return 0
	if last >= 2 and last <= 4 and (last_two < 12 or last_two > 14):
		return 1
	return 2


## Switch the active locale. Returns false when no catalog is loaded for `code`, so a caller can
## refuse rather than half-switch; an unknown code leaves the current locale untouched. A locale
## whose script the engine font does not cover also installs a system font (see
## [method apply_script_font]).
static func set_locale(code: String) -> bool:
	install()
	if not TranslationServer.get_loaded_locales().has(code):
		return false
	TranslationServer.set_locale(code)
	apply_script_font()
	return true


## Install a system font for a script the engine default cannot draw, and return it (null when
## the active locale needs none). No font ships in this repo, so this is what makes a CJK locale
## READABLE rather than a wall of boxes; it touches nothing until such a locale is selected, so
## the English look is unchanged. Returns the installed font so a test can assert the choice.
static func apply_script_font() -> Font:
	var locale := TranslationServer.get_locale().to_lower()
	var script := locale.split("_")[0]
	if not SCRIPT_FONT_PREFIXES.has(script):
		return null
	var font := SystemFont.new()
	font.font_names = PackedStringArray(SCRIPT_FONT_FAMILIES)
	font.allow_system_fallback = true
	ThemeDB.fallback_font = font
	return font


## Every `LOC_…` token inside `text`, replaced by its row; a token with no row is left as-is so
## a missing translation is visible as a key rather than silently blanked.
##
## The boundary is found by LONGEST RESOLVING PREFIX, not by a regex character class: a key is
## `LOC_<OWNER>_<HASH10>` or a readable `LOC_<OWNER>_<ID>_<FIELD>`, and `_`/letters are all legal
## in both — so `LOC_A_9C7608368A` + `LOC_B_DFE3923CC6` glued together is ONE character run that
## a class-based pattern swallows whole and leaves unresolved.
static func _resolve_tokens(text: String) -> String:
	var out := ""
	var cursor := 0
	while true:
		var found := text.find(SLUG_PREFIX, cursor)
		if found < 0:
			break
		out += text.substr(cursor, found - cursor)
		var resolved := _longest_resolving(text, found)
		if resolved.is_empty():
			out += SLUG_PREFIX
			cursor = found + SLUG_PREFIX.length()
			continue
		out += TranslationServer.translate(resolved)
		cursor = found + resolved.length()
	return out + text.substr(cursor)


## The longest prefix of `text` from `start` that names a catalog row, or `""`.
static func _longest_resolving(text: String, start: int) -> String:
	var limit := mini(text.length(), start + MAX_KEY_LENGTH)
	var stop := start
	while stop < limit:
		var code := text.unicode_at(stop)
		var is_key_char := (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code == 95  # A-Z  # 0-9  # _
		if not is_key_char:
			break
		stop += 1
	var length := stop - start
	while length > SLUG_PREFIX.length():
		var key := text.substr(start, length)
		if TranslationServer.translate(key) != key:
			return key
		length -= 1
	return ""


## Resolve every key declared in a SCENE, under `root`. A `.tscn` literal has no call site, so
## the screen that owns it resolves its subtree once, from `_bind_nodes()`. Idempotent: a node
## already holding resolved text is left alone, so a repaint is free.
##
## Iterative with an explicit worklist, and depth-capped: a recursive walk is a `while` the arch
## rule cannot see, and a scene is not trusted to be a tree. Returns how many nodes it resolved.
static func localize_tree(root: Node) -> int:
	if root == null:
		return 0
	var changed := 0
	var pending: Array = [[root, 0]]
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		var node: Node = entry[0]
		var depth: int = entry[1]
		if depth > SCENE_MAX_DEPTH:
			push_error("L.localize_tree: depth cap %d exceeded" % SCENE_MAX_DEPTH)
			break
		if node is Control:
			for property in SCENE_TEXT_PROPERTIES:
				var value: Variant = node.get(property)
				if typeof(value) != TYPE_STRING or String(value).is_empty():
					continue
				var resolved := t(String(value))
				if resolved != String(value):
					node.set(property, resolved)
					changed += 1
		for child in node.get_children():
			pending.append([child, depth + 1])
	return changed


## Install the base catalogs once, lazily, on the first call. A `t()` anywhere — a panel, a
## headless test — is what installs them, so no boot step or test-harness hook is required.
static func install() -> void:
	if _installed_base:
		return
	_installed_base = true
	_load_root(BASE_ROOT)
	for root in _extra_roots:
		_load_root(root)


## Register a mod's catalog root, layering it over the base. Idempotent per root: a second
## boot pass re-registers nothing. Roots registered BEFORE the first `t()` are deferred and
## loaded by `install()`, so ordering does not matter.
static func install_roots(roots: Array) -> void:
	for entry in roots:
		var root := String(entry)
		if root.is_empty() or _extra_roots.has(root):
			continue
		_extra_roots.append(root)
		if _installed_base:
			_load_root(root)


## Every `.tres` under `root`, registered in load order. A missing directory is an ordinary
## "no catalogs here" rather than a fault: `ContentScan` opens nothing.
static func _load_root(root: String) -> void:
	for path in ContentScan.files_under(root, CATALOG_SUFFIX):
		var resource := ResourceLoader.load(path)
		if resource is Translation:
			TranslationServer.add_translation(resource)
