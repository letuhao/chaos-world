class_name DualCultivationProvider
extends StatProvider

## Contributes the module's actor-scoped derived stats from base attributes,
## resources, and the succubus path rank. Pair-specific values (e.g. real harmony
## between two actors) belong to the dual-cultivation action layer, not here.
##
## The per-realm factor is the ONE shared rate, `RealmRate.factor`, read exactly
## as the other three paths read it (ADR 0116). It was a private
## `1.0 + ladder_ordinal * 0.05`: a fourth rate curve, authored in a module, with
## no ADR and no bound. Its span reached 2.45x at R30 — past the under-2x ceiling a
## rate is held to — while answering a question the shared curve already answers.


func contribute(context: StatContext) -> Dictionary:
	var charm := context.value(DualCultivationStats.CHARM)
	var spirit := context.value(Stat.SPIRIT)
	var aptitude := context.value(Stat.APTITUDE)
	var will := context.value(Stat.WILL)

	var corruption := _pool_ratio(context, DualCultivationStats.CORRUPTION)
	var purity := 1.0 - corruption
	var balance := _yin_yang_balance(context)
	var deviation := clampf(absf(balance) * 0.5 + corruption * 0.3, 0.0, 1.0)
	var realm_rate := _realm_factor(context)

	return {
		DualCultivationStats.ALLURE: (charm * 2.0 + corruption * 10.0) * realm_rate,
		DualCultivationStats.SEDUCTION_RESIST: will * 1.5 + purity * 10.0,
		DualCultivationStats.ESSENCE_DRAIN: (charm * 0.5 + corruption * 8.0) * realm_rate,
		DualCultivationStats.ESSENCE_CAPACITY: 20.0 + spirit * 4.0 + charm * 3.0,
		DualCultivationStats.ESSENCE_REGEN: aptitude * 0.2 + charm * 0.1,
		DualCultivationStats.PURITY: purity,
		DualCultivationStats.YIN_YANG_BALANCE: balance,
		DualCultivationStats.DEVIATION_RISK: deviation,
		DualCultivationStats.DUAL_CULTIVATION_RATE:
		(1.0 + aptitude * 0.02) * (1.0 - deviation * 0.5),
		DualCultivationStats.QI_TRANSFER_RATE: (spirit * 0.3 + charm * 0.2) * (1.0 - absf(balance)),
		DualCultivationStats.HARMONY: charm * 0.5 + will * 0.5,
		DualCultivationStats.SUCCUBUS_DOMINION: realm_rate,
	}


## The realm rate for the succubus rank, or neutral when the path is unstarted.
## R1 is the neutral realm because it is the first ordinal, so its factor is
## `RATE_STEP^0` and an unstarted path and a first-realm path agree at 1.0.
##
## `SUCCUBUS_DOMINION` publishes this rate, not a bare ladder index. The ordinal is
## already `PathState.rank_id`'s to be had, and publishing it as a derived stat put
## an array position in the stat namespace where a caller would read it as a value.
func _realm_factor(context: StatContext) -> float:
	var state := context.path(SuccubusPath.PATH_ID)
	if state == null:
		return RealmRate.NEUTRAL
	return RealmRate.factor(state.rank_id)


func _pool_ratio(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return clampf(pool.current / pool.maximum, 0.0, 1.0)


func _yin_yang_balance(context: StatContext) -> float:
	var yin := _pool_current(context, DualCultivationStats.YIN)
	var yang := _pool_current(context, DualCultivationStats.YANG)
	var total := yin + yang
	if total <= 0.0:
		return 0.0
	return clampf((yang - yin) / total, -1.0, 1.0)


func _pool_current(context: StatContext, id: StringName) -> float:
	var pool := context.resource(id)
	return 0.0 if pool == null else pool.current
