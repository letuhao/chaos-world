class_name InstitutionSubclassFixtureDef
extends InstitutionDef

## A def authored on a SUBCLASS of `InstitutionDef`, for one case only:
## `test_a_subclass_def_is_not_merged` in `test_institution_def_catalog.gd`.
##
## ## Why it exists
##
## `CatalogOverlay.merge` selects a `.tres` by a TEXT scan for
## `script_class="InstitutionDef"`. A def authored here declares
## `script_class="InstitutionSubclassFixtureDef"` instead, so the scan does not match it
## and the family does not discover it. That limit is DELIBERATE — ADR 0278's decision is
## that `core` ships ONE authored type for every kind, so a mod authors a `kind` rather
## than a new def class — but a limit nobody can observe is a silent skip waiting to
## happen, so it is pinned by a real subclass rather than described in prose.
##
## ## Why the body is EMPTY
##
## Everything it needs is inherited. The point is the `script_class` the resource
## declares, which comes from the script this file is, not from any field.
##
## ## Why it lives under `res://tests/`
##
## The same reason `institution_registry_fixture_def.gd` does: `core/` may not name
## `modules/`, and a fixture under `res://tests/` creates no boundary edge in either
## direction.


## Whether a caller handed this def directly can still use it. `InstitutionBoot.register_def`
## accepts any `InstitutionDef`, and the case asserts a subclass is REGISTERABLE when
## handed one — so the documented limit is "not discovered by the scan", never "invalid".
func registered_def_type() -> String:
	return String(get_script().get_global_name())
