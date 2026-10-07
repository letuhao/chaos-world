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

static var _installed_base := false
static var _extra_roots: Array[String] = []


## The resolved text for `key`.
##
## The game's DATA holds keys, not English (`display_name = "LOC_ITEM_JADE_PENDANT_NAME"`), and
## one item is defined once for every language. This is the single point that turns a key into
## the current locale's text at display time. `source` is an optional fallback for a caller that
## genuinely has a default in hand; the catalogs are the real source.
static func t(key: String, source: String = "") -> String:
	install()
	var resolved := TranslationServer.translate(key)
	if resolved != key:
		return resolved
	return source if not source.is_empty() else key


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
