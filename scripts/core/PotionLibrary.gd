class_name PotionLibrary
extends RefCounted

## Potions. `effects` reuse the combat effect resolver, so most potions are pure data.
## `combat_only` potions cannot be drunk on the map.

static var POTIONS := {
"fire_potion": {"name": "Fire Potion", "rarity": "common", "color": Color(0.9, 0.4, 0.25),
	"target": "enemy", "combat_only": true, "desc": "Deal 20 damage to a single enemy.",
	"effects": [{"op": "damage", "amount": 20, "no_scale": true}]},
"explosive_potion": {"name": "Explosive Potion", "rarity": "common", "color": Color(0.95, 0.55, 0.2),
	"target": "all", "combat_only": true, "desc": "Deal 10 damage to ALL enemies.",
	"effects": [{"op": "damage", "amount": 10, "target": "all", "no_scale": true}]},
"block_potion": {"name": "Block Potion", "rarity": "common", "color": Color(0.4, 0.6, 0.9),
	"target": "self", "combat_only": true, "desc": "Gain 12 Block.",
	"effects": [{"op": "block", "amount": 12, "no_scale": true}]},
"strength_potion": {"name": "Strength Potion", "rarity": "common", "color": Color(0.9, 0.45, 0.35),
	"target": "self", "combat_only": true, "desc": "Gain 2 Strength.",
	"effects": [{"op": "status", "id": "strength", "stacks": 2, "target": "self"}]},
"swift_potion": {"name": "Swift Potion", "rarity": "common", "color": Color(0.5, 0.85, 0.6),
	"target": "self", "combat_only": true, "desc": "Draw 3 cards.",
	"effects": [{"op": "draw", "amount": 3}]},
"energy_potion": {"name": "Energy Potion", "rarity": "common", "color": Color(0.95, 0.85, 0.4),
	"target": "self", "combat_only": true, "desc": "Gain 2 Energy.",
	"effects": [{"op": "energy", "amount": 2}]},
"fear_potion": {"name": "Fear Potion", "rarity": "common", "color": Color(0.85, 0.4, 0.5),
	"target": "enemy", "combat_only": true, "desc": "Apply 3 Vulnerable.",
	"effects": [{"op": "status", "id": "vulnerable", "stacks": 3, "target": "enemy"}]},
"weak_potion": {"name": "Weak Potion", "rarity": "common", "color": Color(0.7, 0.5, 0.9),
	"target": "enemy", "combat_only": true, "desc": "Apply 3 Weak.",
	"effects": [{"op": "status", "id": "weak", "stacks": 3, "target": "enemy"}]},
"blood_potion": {"name": "Blood Potion", "rarity": "common", "color": Color(0.75, 0.2, 0.25),
	"target": "self", "combat_only": false, "desc": "Heal 20% of your Max HP.",
	"effects": [{"op": "heal_percent", "amount": 20}]},
"dexterity_potion": {"name": "Dexterity Potion", "rarity": "common", "color": Color(0.5, 0.8, 0.55),
	"target": "self", "combat_only": true, "desc": "Gain 2 Dexterity.",
	"effects": [{"op": "status", "id": "dexterity", "stacks": 2, "target": "self"}]},
"regen_potion": {"name": "Regen Potion", "rarity": "uncommon", "color": Color(0.55, 0.9, 0.6),
	"target": "self", "combat_only": true, "desc": "Gain 5 Regen.",
	"effects": [{"op": "status", "id": "regen", "stacks": 5, "target": "self"}]},
"ancient_potion": {"name": "Ancient Potion", "rarity": "uncommon", "color": Color(0.9, 0.8, 0.5),
	"target": "self", "combat_only": true, "desc": "Gain 2 Artifact.",
	"effects": [{"op": "status", "id": "artifact", "stacks": 2, "target": "self"}]},
"poison_potion": {"name": "Poison Potion", "rarity": "uncommon", "color": Color(0.5, 0.8, 0.35),
	"target": "enemy", "combat_only": true, "desc": "Apply 6 Poison.",
	"effects": [{"op": "status", "id": "poison", "stacks": 6, "target": "enemy"}]},
"attack_potion": {"name": "Attack Potion", "rarity": "uncommon", "color": Color(0.85, 0.5, 0.4),
	"target": "self", "combat_only": true,
	"desc": "Add a random Attack to your hand. It costs 0 this turn.",
	"effects": [{"op": "random_card_to_hand", "type": "attack", "free": true}]},
"skill_potion": {"name": "Skill Potion", "rarity": "uncommon", "color": Color(0.45, 0.65, 0.9),
	"target": "self", "combat_only": true,
	"desc": "Add a random Skill to your hand. It costs 0 this turn.",
	"effects": [{"op": "random_card_to_hand", "type": "skill", "free": true}]},
"liquid_bronze": {"name": "Liquid Bronze", "rarity": "uncommon", "color": Color(0.8, 0.6, 0.3),
	"target": "self", "combat_only": true, "desc": "Gain 3 Thorns.",
	"effects": [{"op": "status", "id": "thorns", "stacks": 3, "target": "self"}]},
"cultist_potion": {"name": "Cultist Potion", "rarity": "rare", "color": Color(0.9, 0.6, 0.25),
	"target": "self", "combat_only": true, "desc": "Gain 1 Ritual.",
	"effects": [{"op": "status", "id": "ritual", "stacks": 1, "target": "self"}]},
"fruit_juice": {"name": "Fruit Juice", "rarity": "rare", "color": Color(0.95, 0.75, 0.45),
	"target": "self", "combat_only": false, "desc": "Raise your Max HP by 5.",
	"effects": [{"op": "max_hp", "amount": 5}]},
"heart_of_iron": {"name": "Heart of Iron", "rarity": "rare", "color": Color(0.75, 0.75, 0.8),
	"target": "self", "combat_only": true, "desc": "Gain 6 Metallicize.",
	"effects": [{"op": "status", "id": "metallicize", "stacks": 6, "target": "self"}]},
"essence_of_steel": {"name": "Essence of Steel", "rarity": "rare", "color": Color(0.7, 0.75, 0.85),
	"target": "self", "combat_only": true, "desc": "Gain 4 Plated Armor.",
	"effects": [{"op": "status", "id": "plated_armor", "stacks": 4, "target": "self"}]},
}


static func has(id: String) -> bool:
	return POTIONS.has(id)


static func get_def(id: String) -> Dictionary:
	return POTIONS.get(id, POTIONS["block_potion"])


static func display_name(id: String) -> String:
	return String(get_def(id)["name"])


static func price(id: String) -> int:
	match String(get_def(id)["rarity"]):
		"common": return 50
		"uncommon": return 75
		"rare": return 100
	return 50


static func random_potion(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var want := "common"
	if roll > 0.90:
		want = "rare"
	elif roll > 0.65:
		want = "uncommon"
	var ids: Array = []
	for id in POTIONS:
		if POTIONS[id]["rarity"] == want:
			ids.append(id)
	ids.sort()
	return ids[rng.randi_range(0, ids.size() - 1)]
