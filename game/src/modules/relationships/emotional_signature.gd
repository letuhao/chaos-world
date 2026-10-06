class_name EmotionalSignature
extends RefCounted

## A 7-axis emotion vector for one relationship (ADR 0123).
##
## Each axis is an intensity in [0.0, 1.0]. The signature decays toward its baseline
## at 0.5% per day — output-bounded, so it can never push below baseline, only toward it.
##
## **This is NOT a second bond.** It has no standing, no trust, no class. It is a pure
## emotion vector that the social module's bond axes do not capture.

const BASELINE_JOY := 0.3
const BASELINE_TRUST := 0.2
const BASELINE_FEAR := 0.1
const BASELINE_SURPRISE := 0.2
const BASELINE_SADNESS := 0.1
const BASELINE_DISGUST := 0.0
const BASELINE_ANGER := 0.1

const DECAY_RATE := 0.005  # 0.5% per day

var joy: float = BASELINE_JOY
var trust: float = BASELINE_TRUST
var fear: float = BASELINE_FEAR
var surprise: float = BASELINE_SURPRISE
var sadness: float = BASELINE_SADNESS
var disgust: float = BASELINE_DISGUST
var anger: float = BASELINE_ANGER


func _init(values: Dictionary = {}) -> void:
	if values.is_empty():
		return
	joy = clampf(float(values.get("joy", BASELINE_JOY)), 0.0, 1.0)
	trust = clampf(float(values.get("trust", BASELINE_TRUST)), 0.0, 1.0)
	fear = clampf(float(values.get("fear", BASELINE_FEAR)), 0.0, 1.0)
	surprise = clampf(float(values.get("surprise", BASELINE_SURPRISE)), 0.0, 1.0)
	sadness = clampf(float(values.get("sadness", BASELINE_SADNESS)), 0.0, 1.0)
	disgust = clampf(float(values.get("disgust", BASELINE_DISGUST)), 0.0, 1.0)
	anger = clampf(float(values.get("anger", BASELINE_ANGER)), 0.0, 1.0)


## Decay all axes toward their baselines. `days` is the number of days elapsed.
## Output-bounded: an axis can never drop below its baseline.
func decay(days: float) -> void:
	var factor := 1.0 - DECAY_RATE * days
	joy = _decay_toward(joy, BASELINE_JOY, factor)
	trust = _decay_toward(trust, BASELINE_TRUST, factor)
	fear = _decay_toward(fear, BASELINE_FEAR, factor)
	surprise = _decay_toward(surprise, BASELINE_SURPRISE, factor)
	sadness = _decay_toward(sadness, BASELINE_SADNESS, factor)
	disgust = _decay_toward(disgust, BASELINE_DISGUST, factor)
	anger = _decay_toward(anger, BASELINE_ANGER, factor)


func _decay_toward(value: float, baseline: float, factor: float) -> float:
	if value > baseline:
		return maxf(baseline, value * factor)
	return minf(baseline, value * factor)


## Add a delta to an axis. Clamped to [0.0, 1.0].
func add(axis: StringName, delta: float) -> void:
	match axis:
		&"joy":
			joy = clampf(joy + delta, 0.0, 1.0)
		&"trust":
			trust = clampf(trust + delta, 0.0, 1.0)
		&"fear":
			fear = clampf(fear + delta, 0.0, 1.0)
		&"surprise":
			surprise = clampf(surprise + delta, 0.0, 1.0)
		&"sadness":
			sadness = clampf(sadness + delta, 0.0, 1.0)
		&"disgust":
			disgust = clampf(disgust + delta, 0.0, 1.0)
		&"anger":
			anger = clampf(anger + delta, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"joy": joy,
		"trust": trust,
		"fear": fear,
		"surprise": surprise,
		"sadness": sadness,
		"disgust": disgust,
		"anger": anger,
	}


static func from_dict(values: Dictionary) -> EmotionalSignature:
	return EmotionalSignature.new(values)
