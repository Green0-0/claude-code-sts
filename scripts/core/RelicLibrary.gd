class_name RelicLibrary
extends RefCounted

## Relic definitions. Behaviour lives in `trigger()`, which every relevant game
## system calls at the appropriate moment.

static var RELICS := {
"burning_blood": {"name": "Burning Blood", "rarity": "starter", "sigil": "🩸",
	"desc": "At the end of combat, heal 6 HP."},
"ring_of_the_snake": {"name": "Ring of the Snake", "rarity": "starter", "sigil": "🐍",
	"desc": "At the start of each combat, draw 2 additional cards."},
"bag_of_preparation": {"name": "Bag of Preparation", "rarity": "common", "sigil": "🎒",
	"desc": "At the start of each combat, draw 2 additional cards."},
"anchor": {"name": "Anchor", "rarity": "common", "sigil": "⚓",
	"desc": "At the start of each combat, gain 10 Block."},
"vajra": {"name": "Vajra", "rarity": "common", "sigil": "⚡",
	"desc": "At the start of each combat, gain 1 Strength."},
"oddly_smooth_stone": {"name": "Oddly Smooth Stone", "rarity": "common", "sigil": "🪨",
	"desc": "At the start of each combat, gain 1 Dexterity."},
"blood_vial": {"name": "Blood Vial", "rarity": "common", "sigil": "🧪",
	"desc": "At the start of each combat, heal 2 HP."},
"bronze_scales": {"name": "Bronze Scales", "rarity": "common", "sigil": "🛡",
	"desc": "At the start of each combat, gain 3 Thorns."},
"lantern": {"name": "Lantern", "rarity": "common", "sigil": "🏮",
	"desc": "Gain 1 Energy on the first turn of each combat."},
"orichalcum": {"name": "Orichalcum", "rarity": "common", "sigil": "🟡",
	"desc": "If you end your turn without Block, gain 6 Block."},
"pen_nib": {"name": "Pen Nib", "rarity": "common", "sigil": "🖊",
	"desc": "Every 10th Attack you play deals double damage."},
"strawberry": {"name": "Strawberry", "rarity": "common", "sigil": "🍓",
	"desc": "Raise your Max HP by 7.", "on_pickup": "max_hp:7"},
"pear": {"name": "Pear", "rarity": "common", "sigil": "🍐",
	"desc": "Raise your Max HP by 10.", "on_pickup": "max_hp:10"},
"meat_on_the_bone": {"name": "Meat on the Bone", "rarity": "common", "sigil": "🍖",
	"desc": "If you end combat below 50% HP, heal 12 HP."},
"happy_flower": {"name": "Happy Flower", "rarity": "common", "sigil": "🌻",
	"desc": "Every 3rd turn, gain 1 Energy."},
"art_of_war": {"name": "Art of War", "rarity": "common", "sigil": "📖",
	"desc": "If you play no Attacks during a turn, gain 1 extra Energy next turn."},
"centennial_puzzle": {"name": "Centennial Puzzle", "rarity": "common", "sigil": "🧩",
	"desc": "The first time you lose HP each combat, draw 3 cards."},
"kunai": {"name": "Kunai", "rarity": "uncommon", "sigil": "🗡",
	"desc": "Every 3rd Attack played in a turn grants 1 Dexterity."},
"shuriken": {"name": "Shuriken", "rarity": "uncommon", "sigil": "✴",
	"desc": "Every 3rd Attack played in a turn grants 1 Strength."},
"horn_cleat": {"name": "Horn Cleat", "rarity": "uncommon", "sigil": "🔩",
	"desc": "At the start of your 2nd turn, gain 14 Block."},
"gremlin_horn": {"name": "Gremlin Horn", "rarity": "uncommon", "sigil": "📯",
	"desc": "Whenever an enemy dies, gain 1 Energy and draw 1 card."},
"ornamental_fan": {"name": "Ornamental Fan", "rarity": "uncommon", "sigil": "🪭",
	"desc": "Every 3rd Attack played in a turn grants 4 Block."},
"toolbox": {"name": "Toolbox", "rarity": "uncommon", "sigil": "🧰",
	"desc": "At the start of each combat, add a random Colorless card to your hand."},
"blue_candle": {"name": "Blue Candle", "rarity": "uncommon", "sigil": "🕯",
	"desc": "Curses can be played, losing 1 HP and Exhausting the card."},
"bird_faced_urn": {"name": "Bird-Faced Urn", "rarity": "rare", "sigil": "🏺",
	"desc": "Whenever you play a Power, heal 2 HP."},
"ice_cream": {"name": "Ice Cream", "rarity": "rare", "sigil": "🍦",
	"desc": "Energy is conserved between turns."},
"sundial": {"name": "Sundial", "rarity": "uncommon", "sigil": "⏳",
	"desc": "Every 3rd time you shuffle your draw pile, gain 2 Energy."},
"mercury_hourglass": {"name": "Mercury Hourglass", "rarity": "rare", "sigil": "⌛",
	"desc": "At the start of your turn, deal 3 damage to ALL enemies."},
"philosophers_stone": {"name": "Philosopher's Stone", "rarity": "boss", "sigil": "💎",
	"desc": "Gain 1 Energy at the start of each turn. ALL enemies start with 1 Strength."},
"runic_pyramid": {"name": "Runic Pyramid", "rarity": "boss", "sigil": "🔺",
	"desc": "You no longer discard your hand at the end of your turn."},
"velvet_choker": {"name": "Velvet Choker", "rarity": "boss", "sigil": "🎀",
	"desc": "Gain 1 Energy at the start of each turn. You cannot play more than 6 cards per turn."},
"mark_of_pain": {"name": "Mark of Pain", "rarity": "boss", "sigil": "💀",
	"desc": "Gain 1 Energy at the start of each turn. At the start of combat, shuffle 2 Wounds into your draw pile."},
"black_blood": {"name": "Black Blood", "rarity": "boss", "sigil": "🖤",
	"desc": "At the end of combat, heal 12 HP. Replaces Burning Blood.",
	"replaces": "burning_blood"},
"snecko_eye": {"name": "Snecko Eye", "rarity": "boss", "sigil": "👁",
	"desc": "Draw 2 additional cards each turn. Start each combat Confused (random card costs)."},
"tiny_house": {"name": "Tiny House", "rarity": "shop", "sigil": "🏠",
	"desc": "Gain 50 Gold, 5 Max HP, 1 potion, 1 card and upgrade a random card.",
	"on_pickup": "tiny_house"},
}


static func has(id: String) -> bool:
	return RELICS.has(id)


static func get_def(id: String) -> Dictionary:
	return RELICS.get(id, {"name": id, "rarity": "common", "sigil": "?", "desc": ""})


static func display_name(id: String) -> String:
	return String(get_def(id)["name"])


static func pool(rarity: String) -> Array:
	var out: Array = []
	for id in RELICS:
		if RELICS[id]["rarity"] == rarity:
			out.append(id)
	out.sort()
	return out


## Every relic reachable through normal rewards.
static func common_pool() -> Array:
	return pool("common")


static func uncommon_pool() -> Array:
	return pool("uncommon")


static func rare_pool() -> Array:
	return pool("rare")


static func boss_pool() -> Array:
	return pool("boss")


static func shop_pool() -> Array:
	return pool("shop")
