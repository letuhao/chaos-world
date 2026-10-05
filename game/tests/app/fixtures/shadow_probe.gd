class_name TestShadowProbe
extends Actor

## THROWAWAY: does `Object.set`/`get` reach the SHADOWED Variant, or the base float?
## `stored` exists to show whether the value survived at all.

var age_years: Variant = null
var stored: Variant = null


func _init(actor_id: StringName) -> void:
	super(actor_id)
	stored = "unchanged"


func set_direct(value: Variant) -> void:
	age_years = value
	stored = value


func set_dynamic(value: Variant) -> void:
	self.set(&"age_years", value)
	stored = value


## Read back through BOTH seams, so the probe prints what each one actually sees.
func inspect() -> Dictionary:
	var out := {"base_field_get": self.get(&"age_years"), "side_channel": stored}
	out["shadow_readback"] = shadow_readback()
	return out


## Read the SHADOWED member from inside the class that declares it, where the name is not an
## unresolved external reference.
func shadow_readback() -> Variant:
	return age_years
