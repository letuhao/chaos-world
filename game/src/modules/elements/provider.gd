class_name ElementProvider
extends StatProvider

## Contributes per-element derived stats: element_mastery_<e>, element_power_<e>,
## element_resistance_<e> for every element in the rules (ADR 0004).

var _rules: ElementRules


func _init(rules: ElementRules) -> void:
	_rules = rules


func contribute(context: StatContext) -> Dictionary:
	var will := context.value(Stat.WILL)
	var out := {}
	for element in _rules.ids():
		var affinity := context.affinity(element)
		var mastery := context.value(ElementStats.mastery_id(element))
		out[ElementStats.mastery_id(element)] = mastery
		out[ElementStats.power_id(element)] = maxf(0.0, affinity * (1.0 + mastery * 0.1))
		out[ElementStats.resistance_id(element)] = maxf(0.0, affinity * 0.5 + will * 0.2)
	return out
