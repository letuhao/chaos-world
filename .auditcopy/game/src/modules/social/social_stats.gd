class_name SocialStats
extends RefCounted

## Module-owned stat ids for the `social` module. Namespaced by declaration, not by
## string prefix, so a typo is a compile error rather than a silently absent stat.

## How well this actor is regarded, as the mean of the standing it holds with everyone
## it has met, in [-1, 1]. A single legible number for a karmic gate.
const REPUTATION := &"social_reputation"

## How many bonds this actor holds at `friend` or better. The reach a recruitment or a
## party cap reads.
const REACH := &"social_reach"

## The mean trust this actor is trusted with, in [0, 1].
const TRUST := &"social_trust"
