extends TestCase

## SCRATCH — measurement only, deleted before the task closes.

func test_dump() -> void:
	var ladder := RealmDefaults.ladder().realms()
	var lines: Array[String] = []
	for realm in ladder:
		var ordinal := RealmDefaults.ladder().index_of(realm.id)
		lines.append(
			"RATE %d %s %s %s %s %s %s" % [
				ordinal,
				realm.id,
				var_to_str(RealmRate.factor(realm.id)),
				var_to_str(BodyRealmProfile.factor(realm.id)),
				var_to_str(QiRealmProfile.factor(realm.id)),
				var_to_str(MindRealmProfile.factor(realm.id)),
				var_to_str(pow(1.02, float(ordinal))),
			]
		)
	lines.append(
		"RATE steps %s %s %s %s" % [
			var_to_str(RealmRate.RATE_STEP),
			var_to_str(BodyRealmProfile.RATE_STEP),
			var_to_str(QiRealmProfile.RATE_STEP),
			var_to_str(MindRealmProfile.RATE_STEP),
		]
	)
	for realm in ladder:
		var ordinal := RealmDefaults.ladder().index_of(realm.id)
		var body := load("res://data/body_cultivation/realms/%s.tres" % realm.id)
		var qi := load("res://data/qi_cultivation/realms/%s.tres" % realm.id)
		var mind := load("res://data/mind_cultivation/realms/%s.tres" % realm.id)
		lines.append(
			"PRICE %d %s %s %s %s" % [
				ordinal,
				realm.id,
				var_to_str(float(body.get("progress_required")) / RealmRate.factor(realm.id)),
				var_to_str(float(qi.get("progress_required")) / RealmRate.factor(realm.id)),
				var_to_str(float(mind.get("progress_required")) / RealmRate.factor(realm.id)),
			]
		)
	print("\n".join(lines))
