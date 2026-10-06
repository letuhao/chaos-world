class_name RelationshipsStats
extends RefCounted

## Stat ids owned by the relationships module (ADR 0892).
##
## **Module-owned ids only.** The provider never emits a core id, because a provider's
## contribution replaces the baseline of the stat it names (ADR 0026).

const EMOTIONAL_ENERGY := &"relationship_emotional_energy"
const ACTIVE_RELATIONSHIPS := &"relationship_active_count"
const DC_PARTNER_COUNT := &"relationship_dc_partner_count"
const HIGHEST_TIER := &"relationship_highest_tier"
