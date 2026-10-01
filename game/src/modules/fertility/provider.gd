class_name FertilityProvider
extends StatProvider

## Contributes the module's actor-scoped fertility stats from base attributes
## (ADR 0002). Species parameters are baked into base attributes at attach time.


func contribute(context: StatContext) -> Dictionary:
	var fertility := context.value(DualCultivationApi.FERTILITY)
	var physique := context.value(Stat.PHYSIQUE)
	var spirit := context.value(Stat.SPIRIT)
	var aptitude := context.value(Stat.APTITUDE)
	var comprehension := context.value(Stat.COMPREHENSION)
	var will := context.value(Stat.WILL)
	var fortune := context.value(Stat.FORTUNE)

	return {
		FertilityStats.CONCEPTION_CHANCE: clampf(0.05 + fertility * 0.02, 0.0, 0.95),
		FertilityStats.GESTATION_SPEED: 1.0 + (physique + spirit + aptitude) * 0.01,
		FertilityStats.PARTURITION_SAFETY: clampf(0.7 + physique * 0.01, 0.0, 0.99),
		FertilityStats.OFFSPRING_QUALITY: 1.0 + (comprehension + fortune) * 0.01,
		FertilityStats.MULTIPLE_BIRTH_CHANCE: clampf(0.02 + fortune * 0.005, 0.0, 0.5),
		FertilityStats.MATERNAL_RESILIENCE: clampf((physique + will) * 0.01, 0.0, 0.8),
		FertilityStats.RECOVERY_RATE: 1.0 + (physique + will) * 0.01,
	}
