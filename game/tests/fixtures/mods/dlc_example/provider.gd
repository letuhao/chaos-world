class_name DlcExampleCultivationProvider
extends StatProvider

## Cultivation-path provider for the DLC example mod (ADR 0184).
## Proves the contract: calls RealmRate.factor for the realm factor,
## declares no RATE_STEP, and does not read RealmDefaults.ladder().


func contribute(context: StatContext) -> Dictionary:
	var factor := _realm_factor(context)
	return {
		Stat.SPIRIT: 1.0 * factor,
	}


func _realm_factor(context: StatContext) -> float:
	var state := context.path(&"dlc_example_cultivation")
	if state == null or state.rank_id == &"":
		return RealmRate.NEUTRAL
	return RealmRate.factor(state.rank_id)
