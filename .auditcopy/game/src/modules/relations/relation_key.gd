class_name RelationKey
extends RefCounted

## The node vocabulary of the relation graph, and the closed stance set that
## decides whether an edge is hostile.
##
## ## The node key is `"{kind}:{id}"`, and the ids inside stay PLAIN
##
## ADR 0065's rule is that an id is `oath_of_the_empty_hand` and never
## `fate.oath_of_the_empty_hand`: the KIND is carried by the catalog that holds the
## id, never welded onto the id itself. So `qi_dao` stays `qi_dao` in
## `res://data/world/factions/qi_dao.tres`, and the kind only appears where two
## namespaces have to share one key space — which is exactly what this graph is.
## A node key is therefore a **graph-local address**, never an authored id, and no
## caller may hold one and expect a catalog to answer it.
##
## The separator is a character no authored id carries, so the join is unambiguous
## and the pair can always be split back apart.
const NODE_SEPARATOR := ":"
## The separator joining two node keys into one canonical edge key.
const PAIR_SEPARATOR := "|"

## The three namespaces this graph reads. Authored as constants rather than
## interpolated at call sites so a typo is a missing key rather than a node called
## `sectt:whatever`.
const KIND_DAO := "dao"
const KIND_SECT := "sect"
const KIND_NATION := "nation"
const KINDS: Array[StringName] = [KIND_DAO, KIND_SECT, KIND_NATION]

## The normalized stances, weakest first. A disagreement between two rows about the
## same pair resolves by rank, and the winner's provenance is what the edge carries,
## so the graph never has to pick arbitrarily.
const NEUTRAL := "neutral"
const ALLIED := "allied"
const HOSTILE := "hostile"
const STANCES: Array[StringName] = [NEUTRAL, ALLIED, HOSTILE]


## The canonical node key for one institution in one namespace.
##
## `""` in either half yields `""` rather than a dangling key: "no institution" is
## ADR 0083's FIRST state and it has to be representable, because a member sworn to
## nothing is the ordinary starting state rather than a failure.
static func node_key(kind: String, id: String) -> String:
	var text := String(id)
	if text == "" or kind == "":
		return ""
	return "%s%s%s" % [kind, NODE_SEPARATOR, text]


static func is_node_key(value: String) -> bool:
	return value.count(NODE_SEPARATOR) == 1 and not value.ends_with(NODE_SEPARATOR)


## The namespace half of a node key, or `""` for anything unreadable. Read by
## splitting rather than by stripping a prefix, so a key whose id happens to contain
## the separator cannot be mis-resolved.
static func kind_of(node_key: String) -> String:
	var at := node_key.find(NODE_SEPARATOR)
	return "" if at <= 0 else node_key.substr(0, at)


## The plain id half of a node key — the authored id, with no namespace on it. That
## separation is the point: `sect:iron_vine` answers `iron_vine` here, and a
## catalog lookup uses the answer, never the key.
static func id_of(node_key: String) -> String:
	var at := node_key.find(NODE_SEPARATOR)
	if at <= 0 or at + NODE_SEPARATOR.length() >= node_key.length():
		return ""
	return node_key.substr(at + NODE_SEPARATOR.length())


## The ONE canonical key for an unordered pair of nodes: the two node keys ordered
## lexicographically and joined.
##
## ADR 0047 makes faction stance symmetric and ADR 0085 extends that to every tier.
## Making it STRUCTURAL — the reversed key is inexpressible, so there is no second
## writer to police — is the same move `NationState.pair_key` makes, kept here for
## the same reason: a rule that merely forbids a reversed write has one writer to
## check, and one writer is one missed writer.
static func pair_key(a_node: String, b_node: String) -> String:
	if a_node == "" or b_node == "" or a_node == b_node:
		return ""
	return (
		a_node + PAIR_SEPARATOR + b_node if a_node <= b_node else b_node + PAIR_SEPARATOR + a_node
	)


## Both node keys of a canonical pair key, in the order the key stores them.
static func split_pair(pair: String) -> Array[String]:
	var parts := pair.split(PAIR_SEPARATOR, false, 1)
	if parts.size() != 2:
		return []
	return [String(parts[0]), String(parts[1])]


## The normalized stance an owner's verbatim verb means, or `""` when this graph
## cannot read the verb at all.
##
## **Unknown is `""`, never `neutral`.** The closed sets belong to their owners
## (`NationState.VERBS`, ADR 0047's `allied/neutral/hostile`, `SectSchism.VERB`),
## and defaulting a verb this build has never heard of to "neutral" would make a
## broken `.tres` read as a peaceful relationship — the silence ADR 0085 refuses
## everywhere else. A caller that gets `""` knows the answer is unknown.
static func stance_of(verb: String) -> String:
	match String(verb):
		"hostile", "war", "embargo", "rival", "schism":
			return HOSTILE
		"allied", "truce":
			return ALLIED
		"neutral", "":
			return NEUTRAL
		_:
			return ""


## The rank a normalized stance resolves a disagreement by. Neutral is 0, so an
## unreadable verb — which has no stance at all — never outranks a read one.
static func rank(stance: String) -> int:
	var at := STANCES.find(String(stance))
	return at if at >= 0 else -1


static func is_hostile(stance: String) -> bool:
	return String(stance) == HOSTILE
