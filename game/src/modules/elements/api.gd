class_name ElementsApi
extends RefCounted

## Public facade for the `elements` module (ADR 0004).

static var _default_rules: ElementRules


static func default_rules() -> ElementRules:
	if _default_rules == null:
		_default_rules = ElementRules.new(ElementDefaults.all())
	return _default_rules


static func attach(actor: Actor, rules: ElementRules = null) -> void:
	var resolved := rules if rules != null else default_rules()
	actor.stats.add_provider(ElementProvider.new(resolved))


static func multiplier(rules: ElementRules, attacker: StringName, defender: StringName) -> float:
	return rules.multiplier(attacker, defender)
