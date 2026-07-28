class_name CardLibrary
extends RefCounted

## Every card definition in the game.
##
## Card fields
##   name    : display name
##   type    : "attack" | "skill" | "power" | "status" | "curse"
##   rarity  : "basic" | "common" | "uncommon" | "rare" | "special" | "curse"
##   color   : "red" (Ironclad) | "green" (Silent) | "colorless" | "status" | "curse"
##   cost    : energy cost, -1 means X (spend all), -2 means unplayable
##   target  : "enemy" | "all" | "self" | "none" | "random"
##   params  : numeric parameters referenced by effects and by {placeholders} in text
##   up      : parameter overrides applied when the card is upgraded. May also carry
##             the special keys "cost", "flags_add", "text" and "effects".
##   text    : rules text; "{key}" is substituted with params[key]
##   flags   : "exhaust", "ethereal", "innate", "unplayable", "retain", "no_upgrade"
##   effects : ordered list of effect dictionaries resolved by Combat
##
## In an effect dictionary a numeric field may be an int, or a String naming a
## key of params (resolved at play time, after Strength / Dexterity scaling).

const STARTER_DECKS := {
	"ironclad": ["strike", "strike", "strike", "strike", "strike",
		"defend", "defend", "defend", "defend", "bash"],
	"silent": ["strike", "strike", "strike", "strike", "strike",
		"defend", "defend", "defend", "defend", "defend", "neutralize", "survivor"],
}

const CHARACTERS := {
	"ironclad": {
		"name": "The Ironclad", "color": "red", "max_hp": 80, "relic": "burning_blood",
		"blurb": "A hardened warrior. Trades HP for power and excels at exhausting cards.",
		"tint": Color(0.85, 0.32, 0.28),
	},
	"silent": {
		"name": "The Silent", "color": "green", "max_hp": 70, "relic": "ring_of_the_snake",
		"blurb": "A deadly assassin. Stacks poison, draws cards and dodges blows.",
		"tint": Color(0.35, 0.72, 0.42),
	},
}

static var CARDS := {

# ─────────────────────────────── Ironclad — basic ───────────────────────────────
"strike": {
	"name": "Strike", "type": "attack", "rarity": "basic", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 6}, "up": {"dmg": 9},
	"text": "Deal {dmg} damage.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"defend": {
	"name": "Defend", "type": "skill", "rarity": "basic", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 5}, "up": {"blk": 8},
	"text": "Gain {blk} Block.",
	"effects": [{"op": "block", "amount": "blk"}],
},
"bash": {
	"name": "Bash", "type": "attack", "rarity": "basic", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 8, "vuln": 2}, "up": {"dmg": 10, "vuln": 3},
	"text": "Deal {dmg} damage. Apply {vuln} Vulnerable.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "vulnerable", "stacks": "vuln", "target": "enemy"}],
},

# ────────────────────────────── Ironclad — common ──────────────────────────────
"anger": {
	"name": "Anger", "type": "attack", "rarity": "common", "color": "red", "cost": 0,
	"target": "enemy", "params": {"dmg": 6}, "up": {"dmg": 8},
	"text": "Deal {dmg} damage. Add a copy of this card to your discard pile.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "copy_self", "dest": "discard"}],
},
"armaments": {
	"name": "Armaments", "type": "skill", "rarity": "common", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 5}, "up": {"blk": 5, "count": 99},
	"text": "Gain {blk} Block. Upgrade a card in your hand for the rest of combat.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "choose_upgrade", "count": 1}],
},
"body_slam": {
	"name": "Body Slam", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 0}, "up": {"cost": 0},
	"text": "Deal damage equal to your current Block ({dmg}).",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"clash": {
	"name": "Clash", "type": "attack", "rarity": "common", "color": "red", "cost": 0,
	"target": "enemy", "params": {"dmg": 14}, "up": {"dmg": 18},
	"text": "Can only be played if every card in your hand is an Attack. Deal {dmg} damage.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"cleave": {
	"name": "Cleave", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "all", "params": {"dmg": 8}, "up": {"dmg": 11},
	"text": "Deal {dmg} damage to ALL enemies.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all"}],
},
"clothesline": {
	"name": "Clothesline", "type": "attack", "rarity": "common", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 12, "weak": 2}, "up": {"dmg": 14, "weak": 3},
	"text": "Deal {dmg} damage. Apply {weak} Weak.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "weak", "stacks": "weak", "target": "enemy"}],
},
"flex": {
	"name": "Flex", "type": "skill", "rarity": "common", "color": "red", "cost": 0,
	"target": "self", "params": {"str": 2}, "up": {"str": 4},
	"text": "Gain {str} Strength. At the end of this turn, lose {str} Strength.",
	"effects": [{"op": "status", "id": "strength", "stacks": "str", "target": "self"},
		{"op": "status", "id": "strength_down", "stacks": "str", "target": "self"}],
},
"havoc": {
	"name": "Havoc", "type": "skill", "rarity": "common", "color": "red", "cost": 1,
	"target": "none", "params": {}, "up": {"cost": 0},
	"text": "Play the top card of your draw pile and Exhaust it.",
	"effects": [{"op": "play_top_card", "exhaust": true}],
},
"headbutt": {
	"name": "Headbutt", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 9}, "up": {"dmg": 12},
	"text": "Deal {dmg} damage. Place a card from your discard pile on top of your draw pile.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "discard_to_draw", "count": 1}],
},
"heavy_blade": {
	"name": "Heavy Blade", "type": "attack", "rarity": "common", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 14, "mult": 3}, "up": {"dmg": 14, "mult": 5},
	"text": "Deal {dmg} damage. Strength affects this card {mult} times.",
	"effects": [{"op": "damage", "amount": "dmg", "str_mult": "mult"}],
},
"iron_wave": {
	"name": "Iron Wave", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 5, "blk": 5}, "up": {"dmg": 7, "blk": 7},
	"text": "Gain {blk} Block. Deal {dmg} damage.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "damage", "amount": "dmg"}],
},
"perfected_strike": {
	"name": "Perfected Strike", "type": "attack", "rarity": "common", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 6, "per": 2}, "up": {"per": 3},
	"text": "Deal {dmg} damage. Deals {per} additional damage for ALL of your cards containing \"Strike\".",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"pommel_strike": {
	"name": "Pommel Strike", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 9, "cards": 1}, "up": {"dmg": 10, "cards": 2},
	"text": "Deal {dmg} damage. Draw {cards} card(s).",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "draw", "amount": "cards"}],
},
"shrug_it_off": {
	"name": "Shrug It Off", "type": "skill", "rarity": "common", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 8}, "up": {"blk": 11},
	"text": "Gain {blk} Block. Draw 1 card.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "draw", "amount": 1}],
},
"sword_boomerang": {
	"name": "Sword Boomerang", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "random", "params": {"dmg": 3, "hits": 3}, "up": {"hits": 4},
	"text": "Deal {dmg} damage to a random enemy {hits} times.",
	"effects": [{"op": "damage_random", "amount": "dmg", "times": "hits"}],
},
"thunderclap": {
	"name": "Thunderclap", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "all", "params": {"dmg": 4, "vuln": 1}, "up": {"dmg": 7},
	"text": "Deal {dmg} damage and apply {vuln} Vulnerable to ALL enemies.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all"},
		{"op": "status", "id": "vulnerable", "stacks": "vuln", "target": "all"}],
},
"true_grit": {
	"name": "True Grit", "type": "skill", "rarity": "common", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 7}, "up": {"blk": 9, "choose": 1},
	"text": "Gain {blk} Block. Exhaust a random card from your hand.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "exhaust", "count": 1, "random": true}],
},
"twin_strike": {
	"name": "Twin Strike", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 5}, "up": {"dmg": 7},
	"text": "Deal {dmg} damage twice.",
	"effects": [{"op": "damage", "amount": "dmg", "times": 2}],
},
"warcry": {
	"name": "Warcry", "type": "skill", "rarity": "common", "color": "red", "cost": 0,
	"target": "none", "params": {"cards": 1}, "up": {"cards": 2},
	"text": "Draw {cards} card(s). Put a card from your hand on top of your draw pile. Exhaust.",
	"flags": ["exhaust"],
	"effects": [{"op": "draw", "amount": "cards"}, {"op": "hand_to_draw", "count": 1}],
},
"wild_strike": {
	"name": "Wild Strike", "type": "attack", "rarity": "common", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 12}, "up": {"dmg": 17},
	"text": "Deal {dmg} damage. Shuffle a Wound into your draw pile.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "add_card", "id": "wound", "dest": "draw_random", "count": 1}],
},

# ───────────────────────────── Ironclad — uncommon ─────────────────────────────
"battle_trance": {
	"name": "Battle Trance", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 0,
	"target": "self", "params": {"cards": 3}, "up": {"cards": 4},
	"text": "Draw {cards} cards. You cannot draw additional cards this turn.",
	"effects": [{"op": "draw", "amount": "cards"},
		{"op": "status", "id": "no_draw", "stacks": 1, "target": "self"}],
},
"blood_for_blood": {
	"name": "Blood for Blood", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 4,
	"target": "enemy", "params": {"dmg": 18}, "up": {"dmg": 22, "cost": 3},
	"text": "Costs 1 less energy for each time you lose HP this combat. Deal {dmg} damage.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"bloodletting": {
	"name": "Bloodletting", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 0,
	"target": "self", "params": {"nrg": 2}, "up": {"nrg": 3},
	"text": "Lose 3 HP. Gain {nrg} Energy.",
	"effects": [{"op": "lose_hp", "amount": 3}, {"op": "energy", "amount": "nrg"}],
},
"burning_pact": {
	"name": "Burning Pact", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"cards": 2}, "up": {"cards": 3},
	"text": "Exhaust 1 card. Draw {cards} cards.",
	"effects": [{"op": "exhaust", "count": 1}, {"op": "draw", "amount": "cards"}],
},
"carnage": {
	"name": "Carnage", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 20}, "up": {"dmg": 28},
	"text": "Ethereal. Deal {dmg} damage.", "flags": ["ethereal"],
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"combust": {
	"name": "Combust", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 5}, "up": {"n": 7},
	"text": "At the end of your turn, lose 1 HP and deal {n} damage to ALL enemies.",
	"effects": [{"op": "status", "id": "combust", "stacks": "n", "target": "self"}],
},
"dark_embrace": {
	"name": "Dark Embrace", "type": "power", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "self", "params": {"n": 1}, "up": {"cost": 1},
	"text": "Whenever a card is Exhausted, draw {n} card.",
	"effects": [{"op": "status", "id": "dark_embrace", "stacks": "n", "target": "self"}],
},
"disarm": {
	"name": "Disarm", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "enemy", "params": {"str": 2}, "up": {"str": 3},
	"text": "Enemy loses {str} Strength. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "strength", "stacks": -1, "scale": "str", "target": "enemy"}],
},
"dropkick": {
	"name": "Dropkick", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 5}, "up": {"dmg": 8},
	"text": "Deal {dmg} damage. If the target is Vulnerable, gain 1 Energy and draw 1 card.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "special", "id": "dropkick"}],
},
"dual_wield": {
	"name": "Dual Wield", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "none", "params": {"n": 1}, "up": {"n": 2},
	"text": "Create {n} copy(s) of an Attack or Power card in your hand.",
	"effects": [{"op": "duplicate_in_hand", "count": "n"}],
},
"entrench": {
	"name": "Entrench", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "self", "params": {}, "up": {"cost": 1},
	"text": "Double your current Block.",
	"effects": [{"op": "double_block"}],
},
"evolve": {
	"name": "Evolve", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 1}, "up": {"n": 2},
	"text": "Whenever you draw a Status card, draw {n} card(s).",
	"effects": [{"op": "status", "id": "evolve", "stacks": "n", "target": "self"}],
},
"feel_no_pain": {
	"name": "Feel No Pain", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 3}, "up": {"n": 4},
	"text": "Whenever a card is Exhausted, gain {n} Block.",
	"effects": [{"op": "status", "id": "feel_no_pain", "stacks": "n", "target": "self"}],
},
"fire_breathing": {
	"name": "Fire Breathing", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 6}, "up": {"n": 10},
	"text": "Whenever you draw a Status or Curse card, deal {n} damage to ALL enemies.",
	"effects": [{"op": "status", "id": "fire_breathing", "stacks": "n", "target": "self"}],
},
"flame_barrier": {
	"name": "Flame Barrier", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "self", "params": {"blk": 12, "thorns": 4}, "up": {"blk": 16, "thorns": 6},
	"text": "Gain {blk} Block. Whenever you are attacked this turn, deal {thorns} damage back.",
	"effects": [{"op": "block", "amount": "blk"},
		{"op": "status", "id": "thorns", "stacks": "thorns", "target": "self", "temp": true}],
},
"ghostly_armor": {
	"name": "Ghostly Armor", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 10}, "up": {"blk": 13},
	"text": "Ethereal. Gain {blk} Block.", "flags": ["ethereal"],
	"effects": [{"op": "block", "amount": "blk"}],
},
"hemokinesis": {
	"name": "Hemokinesis", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 15}, "up": {"dmg": 20},
	"text": "Lose 2 HP. Deal {dmg} damage.",
	"effects": [{"op": "lose_hp", "amount": 2}, {"op": "damage", "amount": "dmg"}],
},
"infernal_blade": {
	"name": "Infernal Blade", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "none", "params": {}, "up": {"cost": 0},
	"text": "Add a random Attack to your hand. It costs 0 this turn. Exhaust.",
	"flags": ["exhaust"],
	"effects": [{"op": "random_card_to_hand", "type": "attack", "free": true}],
},
"inflame": {
	"name": "Inflame", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"str": 2}, "up": {"str": 3},
	"text": "Gain {str} Strength.",
	"effects": [{"op": "status", "id": "strength", "stacks": "str", "target": "self"}],
},
"intimidate": {
	"name": "Intimidate", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 0,
	"target": "all", "params": {"weak": 1}, "up": {"weak": 2},
	"text": "Apply {weak} Weak to ALL enemies. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "weak", "stacks": "weak", "target": "all"}],
},
"metallicize": {
	"name": "Metallicize", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 3}, "up": {"n": 4},
	"text": "At the end of your turn, gain {n} Block.",
	"effects": [{"op": "status", "id": "metallicize", "stacks": "n", "target": "self"}],
},
"power_through": {
	"name": "Power Through", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 15}, "up": {"blk": 20},
	"text": "Add 2 Wounds to your hand. Gain {blk} Block.",
	"effects": [{"op": "add_card", "id": "wound", "dest": "hand", "count": 2},
		{"op": "block", "amount": "blk"}],
},
"pummel": {
	"name": "Pummel", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 2, "hits": 4}, "up": {"hits": 5},
	"text": "Deal {dmg} damage {hits} times. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "damage", "amount": "dmg", "times": "hits"}],
},
"rampage": {
	"name": "Rampage", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 8, "grow": 5}, "up": {"grow": 8},
	"text": "Deal {dmg} damage. Increase this card's damage by {grow} this combat.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "special", "id": "rampage"}],
},
"reckless_charge": {
	"name": "Reckless Charge", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 0,
	"target": "enemy", "params": {"dmg": 7}, "up": {"dmg": 10},
	"text": "Deal {dmg} damage. Shuffle a Dazed into your draw pile.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "add_card", "id": "dazed", "dest": "draw_random", "count": 1}],
},
"rupture": {
	"name": "Rupture", "type": "power", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 1}, "up": {"n": 2},
	"text": "Whenever you lose HP from a card, gain {n} Strength.",
	"effects": [{"op": "status", "id": "rupture", "stacks": "n", "target": "self"}],
},
"searing_blow": {
	"name": "Searing Blow", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 12}, "up": {"dmg": 16},
	"text": "Deal {dmg} damage. Can be upgraded any number of times.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"second_wind": {
	"name": "Second Wind", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 5}, "up": {"blk": 7},
	"text": "Exhaust all non-Attack cards in your hand and gain {blk} Block for each.",
	"effects": [{"op": "exhaust_all_nonattacks", "block_each": "blk"}],
},
"seeing_red": {
	"name": "Seeing Red", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {}, "up": {"cost": 0},
	"text": "Gain 2 Energy. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "energy", "amount": 2}],
},
"sentinel": {
	"name": "Sentinel", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "self", "params": {"blk": 5, "nrg": 2}, "up": {"blk": 8, "nrg": 3},
	"text": "Gain {blk} Block. If this card is Exhausted, gain {nrg} Energy.",
	"effects": [{"op": "block", "amount": "blk"}],
},
"sever_soul": {
	"name": "Sever Soul", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 16}, "up": {"dmg": 20},
	"text": "Exhaust all non-Attack cards in your hand. Deal {dmg} damage.",
	"effects": [{"op": "exhaust_all_nonattacks", "block_each": 0},
		{"op": "damage", "amount": "dmg"}],
},
"shockwave": {
	"name": "Shockwave", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "all", "params": {"n": 3}, "up": {"n": 5},
	"text": "Apply {n} Weak and {n} Vulnerable to ALL enemies. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "weak", "stacks": "n", "target": "all"},
		{"op": "status", "id": "vulnerable", "stacks": "n", "target": "all"}],
},
"spot_weakness": {
	"name": "Spot Weakness", "type": "skill", "rarity": "uncommon", "color": "red", "cost": 1,
	"target": "enemy", "params": {"str": 3}, "up": {"str": 4},
	"text": "If the enemy intends to attack, gain {str} Strength.",
	"effects": [{"op": "special", "id": "spot_weakness"}],
},
"uppercut": {
	"name": "Uppercut", "type": "attack", "rarity": "uncommon", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 13, "n": 1}, "up": {"n": 2},
	"text": "Deal {dmg} damage. Apply {n} Weak. Apply {n} Vulnerable.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "weak", "stacks": "n", "target": "enemy"},
		{"op": "status", "id": "vulnerable", "stacks": "n", "target": "enemy"}],
},
"whirlwind": {
	"name": "Whirlwind", "type": "attack", "rarity": "uncommon", "color": "red", "cost": -1,
	"target": "all", "params": {"dmg": 5}, "up": {"dmg": 8},
	"text": "Deal {dmg} damage to ALL enemies X times.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all", "times": "X"}],
},

# ─────────────────────────────── Ironclad — rare ───────────────────────────────
"barricade": {
	"name": "Barricade", "type": "power", "rarity": "rare", "color": "red", "cost": 3,
	"target": "self", "params": {}, "up": {"cost": 2},
	"text": "Block is no longer removed at the start of your turn.",
	"effects": [{"op": "status", "id": "barricade", "stacks": 1, "target": "self"}],
},
"berserk": {
	"name": "Berserk", "type": "power", "rarity": "rare", "color": "red", "cost": 0,
	"target": "self", "params": {"vuln": 2}, "up": {"vuln": 1},
	"text": "Gain {vuln} Vulnerable. At the start of your turn, gain 1 Energy.",
	"effects": [{"op": "status", "id": "vulnerable", "stacks": "vuln", "target": "self"},
		{"op": "status", "id": "berserk", "stacks": 1, "target": "self"}],
},
"bludgeon": {
	"name": "Bludgeon", "type": "attack", "rarity": "rare", "color": "red", "cost": 3,
	"target": "enemy", "params": {"dmg": 32}, "up": {"dmg": 42},
	"text": "Deal {dmg} damage.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"brutality": {
	"name": "Brutality", "type": "power", "rarity": "rare", "color": "red", "cost": 0,
	"target": "self", "params": {}, "up": {"innate": 1},
	"text": "At the start of your turn, lose 1 HP and draw 1 card.",
	"effects": [{"op": "status", "id": "brutality", "stacks": 1, "target": "self"}],
},
"corruption": {
	"name": "Corruption", "type": "power", "rarity": "rare", "color": "red", "cost": 3,
	"target": "self", "params": {}, "up": {"cost": 2},
	"text": "Skills cost 0. Whenever you play a Skill, Exhaust it.",
	"effects": [{"op": "status", "id": "corruption", "stacks": 1, "target": "self"}],
},
"demon_form": {
	"name": "Demon Form", "type": "power", "rarity": "rare", "color": "red", "cost": 3,
	"target": "self", "params": {"n": 2}, "up": {"n": 3},
	"text": "At the start of each turn, gain {n} Strength.",
	"effects": [{"op": "status", "id": "demon_form", "stacks": "n", "target": "self"}],
},
"double_tap": {
	"name": "Double Tap", "type": "skill", "rarity": "rare", "color": "red", "cost": 1,
	"target": "self", "params": {"n": 1}, "up": {"n": 2},
	"text": "This turn, your next {n} Attack(s) is played twice.",
	"effects": [{"op": "status", "id": "double_tap", "stacks": "n", "target": "self"}],
},
"exhume": {
	"name": "Exhume", "type": "skill", "rarity": "rare", "color": "red", "cost": 1,
	"target": "none", "params": {}, "up": {"cost": 0},
	"text": "Put a card from your Exhaust pile into your hand. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "exhaust_pile_to_hand", "count": 1}],
},
"feed": {
	"name": "Feed", "type": "attack", "rarity": "rare", "color": "red", "cost": 1,
	"target": "enemy", "params": {"dmg": 10, "hp": 3}, "up": {"dmg": 12, "hp": 4},
	"text": "Deal {dmg} damage. If this kills a non-minion enemy, gain {hp} permanent Max HP. Exhaust.",
	"flags": ["exhaust"],
	"effects": [{"op": "special", "id": "feed"}],
},
"fiend_fire": {
	"name": "Fiend Fire", "type": "attack", "rarity": "rare", "color": "red", "cost": 2,
	"target": "enemy", "params": {"dmg": 7}, "up": {"dmg": 10},
	"text": "Exhaust your hand. Deal {dmg} damage for each card Exhausted. Exhaust.",
	"flags": ["exhaust"],
	"effects": [{"op": "special", "id": "fiend_fire"}],
},
"immolate": {
	"name": "Immolate", "type": "attack", "rarity": "rare", "color": "red", "cost": 2,
	"target": "all", "params": {"dmg": 21}, "up": {"dmg": 28},
	"text": "Deal {dmg} damage to ALL enemies. Add a Burn to your discard pile.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all"},
		{"op": "add_card", "id": "burn", "dest": "discard", "count": 1}],
},
"impervious": {
	"name": "Impervious", "type": "skill", "rarity": "rare", "color": "red", "cost": 2,
	"target": "self", "params": {"blk": 30}, "up": {"blk": 40},
	"text": "Gain {blk} Block. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "block", "amount": "blk"}],
},
"juggernaut": {
	"name": "Juggernaut", "type": "power", "rarity": "rare", "color": "red", "cost": 2,
	"target": "self", "params": {"n": 5}, "up": {"n": 7},
	"text": "Whenever you gain Block, deal {n} damage to a random enemy.",
	"effects": [{"op": "status", "id": "juggernaut", "stacks": "n", "target": "self"}],
},
"limit_break": {
	"name": "Limit Break", "type": "skill", "rarity": "rare", "color": "red", "cost": 1,
	"target": "self", "params": {}, "up": {"no_exhaust": 1},
	"text": "Double your Strength. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "special", "id": "limit_break"}],
},
"offering": {
	"name": "Offering", "type": "skill", "rarity": "rare", "color": "red", "cost": 0,
	"target": "self", "params": {"cards": 3}, "up": {"cards": 5},
	"text": "Lose 6 HP. Gain 2 Energy. Draw {cards} cards. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "lose_hp", "amount": 6}, {"op": "energy", "amount": 2},
		{"op": "draw", "amount": "cards"}],
},
"reaper": {
	"name": "Reaper", "type": "attack", "rarity": "rare", "color": "red", "cost": 2,
	"target": "all", "params": {"dmg": 4}, "up": {"dmg": 5},
	"text": "Deal {dmg} damage to ALL enemies. Heal HP equal to unblocked damage. Exhaust.",
	"flags": ["exhaust"],
	"effects": [{"op": "special", "id": "reaper"}],
},

# ─────────────────────────────── Silent — basic ────────────────────────────────
"neutralize": {
	"name": "Neutralize", "type": "attack", "rarity": "basic", "color": "green", "cost": 0,
	"target": "enemy", "params": {"dmg": 3, "weak": 1}, "up": {"dmg": 4, "weak": 2},
	"text": "Deal {dmg} damage. Apply {weak} Weak.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "weak", "stacks": "weak", "target": "enemy"}],
},
"survivor": {
	"name": "Survivor", "type": "skill", "rarity": "basic", "color": "green", "cost": 1,
	"target": "self", "params": {"blk": 8}, "up": {"blk": 11},
	"text": "Gain {blk} Block. Discard 1 card.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "discard", "count": 1}],
},

# ─────────────────────────────── Silent — common ───────────────────────────────
"acrobatics": {
	"name": "Acrobatics", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "self", "params": {"cards": 3}, "up": {"cards": 4},
	"text": "Draw {cards} cards. Discard 1 card.",
	"effects": [{"op": "draw", "amount": "cards"}, {"op": "discard", "count": 1}],
},
"backflip": {
	"name": "Backflip", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "self", "params": {"blk": 5}, "up": {"blk": 8},
	"text": "Gain {blk} Block. Draw 2 cards.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "draw", "amount": 2}],
},
"bane": {
	"name": "Bane", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 7}, "up": {"dmg": 10},
	"text": "Deal {dmg} damage. If the target has Poison, deal {dmg} damage again.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "special", "id": "bane"}],
},
"blade_dance": {
	"name": "Blade Dance", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "self", "params": {"n": 3}, "up": {"n": 4},
	"text": "Add {n} Shivs to your hand.",
	"effects": [{"op": "add_card", "id": "shiv", "dest": "hand", "count": "n"}],
},
"cloak_and_dagger": {
	"name": "Cloak and Dagger", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "self", "params": {"blk": 6, "n": 1}, "up": {"n": 2},
	"text": "Gain {blk} Block. Add {n} Shiv(s) to your hand.",
	"effects": [{"op": "block", "amount": "blk"},
		{"op": "add_card", "id": "shiv", "dest": "hand", "count": "n"}],
},
"dagger_spray": {
	"name": "Dagger Spray", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "all", "params": {"dmg": 4}, "up": {"dmg": 6},
	"text": "Deal {dmg} damage to ALL enemies twice.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all", "times": 2}],
},
"dagger_throw": {
	"name": "Dagger Throw", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 9}, "up": {"dmg": 12},
	"text": "Deal {dmg} damage. Draw 1 card. Discard 1 card.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "draw", "amount": 1},
		{"op": "discard", "count": 1}],
},
"deadly_poison": {
	"name": "Deadly Poison", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"psn": 5}, "up": {"psn": 7},
	"text": "Apply {psn} Poison.",
	"effects": [{"op": "status", "id": "poison", "stacks": "psn", "target": "enemy"}],
},
"deflect": {
	"name": "Deflect", "type": "skill", "rarity": "common", "color": "green", "cost": 0,
	"target": "self", "params": {"blk": 4}, "up": {"blk": 7},
	"text": "Gain {blk} Block.",
	"effects": [{"op": "block", "amount": "blk"}],
},
"dodge_and_roll": {
	"name": "Dodge and Roll", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "self", "params": {"blk": 4}, "up": {"blk": 6},
	"text": "Gain {blk} Block. Next turn gain {blk} Block.",
	"effects": [{"op": "block", "amount": "blk"},
		{"op": "block_next_turn", "amount": "blk"}],
},
"flying_knee": {
	"name": "Flying Knee", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 8}, "up": {"dmg": 11},
	"text": "Deal {dmg} damage. Gain 1 Energy next turn.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "energy_next_turn", "amount": 1}],
},
"outmaneuver": {
	"name": "Outmaneuver", "type": "skill", "rarity": "common", "color": "green", "cost": 1,
	"target": "self", "params": {"nrg": 2}, "up": {"nrg": 3},
	"text": "Gain {nrg} Energy next turn.",
	"effects": [{"op": "energy_next_turn", "amount": "nrg"}],
},
"poisoned_stab": {
	"name": "Poisoned Stab", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 6, "psn": 3}, "up": {"dmg": 8, "psn": 4},
	"text": "Deal {dmg} damage. Apply {psn} Poison.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "poison", "stacks": "psn", "target": "enemy"}],
},
"prepared": {
	"name": "Prepared", "type": "skill", "rarity": "common", "color": "green", "cost": 0,
	"target": "self", "params": {"n": 1}, "up": {"n": 2},
	"text": "Draw {n} card(s). Discard {n} card(s).",
	"effects": [{"op": "draw", "amount": "n"}, {"op": "discard", "count": "n"}],
},
"quick_slash": {
	"name": "Quick Slash", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 8}, "up": {"dmg": 12},
	"text": "Deal {dmg} damage. Draw 1 card.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "draw", "amount": 1}],
},
"slice": {
	"name": "Slice", "type": "attack", "rarity": "common", "color": "green", "cost": 0,
	"target": "enemy", "params": {"dmg": 6}, "up": {"dmg": 9},
	"text": "Deal {dmg} damage.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"sneaky_strike": {
	"name": "Sneaky Strike", "type": "attack", "rarity": "common", "color": "green", "cost": 2,
	"target": "enemy", "params": {"dmg": 12}, "up": {"dmg": 16},
	"text": "Deal {dmg} damage. If you have discarded a card this turn, gain 2 Energy.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "special", "id": "sneaky_strike"}],
},
"sucker_punch": {
	"name": "Sucker Punch", "type": "attack", "rarity": "common", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 7, "weak": 1}, "up": {"dmg": 9, "weak": 2},
	"text": "Deal {dmg} damage. Apply {weak} Weak.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "weak", "stacks": "weak", "target": "enemy"}],
},

# ────────────────────────────── Silent — uncommon ──────────────────────────────
"accuracy": {
	"name": "Accuracy", "type": "power", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "self", "params": {"n": 4}, "up": {"n": 6},
	"text": "Shivs deal {n} additional damage.",
	"effects": [{"op": "status", "id": "accuracy", "stacks": "n", "target": "self"}],
},
"all_out_attack": {
	"name": "All-Out Attack", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "all", "params": {"dmg": 10}, "up": {"dmg": 14},
	"text": "Deal {dmg} damage to ALL enemies. Discard 1 random card.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all"},
		{"op": "discard", "count": 1, "random": true}],
},
"backstab": {
	"name": "Backstab", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 0,
	"target": "enemy", "params": {"dmg": 11}, "up": {"dmg": 15},
	"text": "Innate. Deal {dmg} damage. Exhaust.", "flags": ["innate", "exhaust"],
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"blur": {
	"name": "Blur", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "self", "params": {"blk": 5}, "up": {"blk": 8},
	"text": "Gain {blk} Block. Block is not removed at the start of your next turn.",
	"effects": [{"op": "block", "amount": "blk"},
		{"op": "status", "id": "blur", "stacks": 1, "target": "self"}],
},
"bouncing_flask": {
	"name": "Bouncing Flask", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "random", "params": {"psn": 3, "hits": 3}, "up": {"hits": 4},
	"text": "Apply {psn} Poison to a random enemy {hits} times.",
	"effects": [{"op": "poison_random", "stacks": "psn", "times": "hits"}],
},
"calculated_gamble": {
	"name": "Calculated Gamble", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 0,
	"target": "self", "params": {}, "up": {"no_exhaust": 1},
	"text": "Discard your hand, then draw that many cards. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "special", "id": "calculated_gamble"}],
},
"catalyst": {
	"name": "Catalyst", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "enemy", "params": {"mult": 2}, "up": {"mult": 3},
	"text": "Multiply the target's Poison by {mult}. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "special", "id": "catalyst"}],
},
"choke": {
	"name": "Choke", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "enemy", "params": {"dmg": 12, "psn": 3}, "up": {"psn": 5},
	"text": "Deal {dmg} damage. Apply {psn} Poison.",
	"effects": [{"op": "damage", "amount": "dmg"},
		{"op": "status", "id": "poison", "stacks": "psn", "target": "enemy"}],
},
"concentrate": {
	"name": "Concentrate", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 0,
	"target": "self", "params": {"n": 3}, "up": {"n": 2},
	"text": "Discard {n} cards. Gain 2 Energy.",
	"effects": [{"op": "discard", "count": "n"}, {"op": "energy", "amount": 2}],
},
"crippling_cloud": {
	"name": "Crippling Cloud", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "all", "params": {"psn": 4, "weak": 2}, "up": {"psn": 7},
	"text": "Apply {psn} Poison and {weak} Weak to ALL enemies. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "poison", "stacks": "psn", "target": "all"},
		{"op": "status", "id": "weak", "stacks": "weak", "target": "all"}],
},
"dash": {
	"name": "Dash", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "enemy", "params": {"dmg": 10, "blk": 10}, "up": {"dmg": 13, "blk": 13},
	"text": "Gain {blk} Block. Deal {dmg} damage.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "damage", "amount": "dmg"}],
},
"endless_agony": {
	"name": "Endless Agony", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 0,
	"target": "enemy", "params": {"dmg": 4}, "up": {"dmg": 6},
	"text": "Whenever you draw this card, add a copy of it to your hand. Deal {dmg} damage. Exhaust.",
	"flags": ["exhaust"],
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"envenom": {
	"name": "Envenom", "type": "power", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "self", "params": {"n": 1}, "up": {"cost": 1},
	"text": "Whenever an Attack deals unblocked damage, apply {n} Poison.",
	"effects": [{"op": "status", "id": "envenom", "stacks": "n", "target": "self"}],
},
"escape_plan": {
	"name": "Escape Plan", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 0,
	"target": "self", "params": {"blk": 3}, "up": {"blk": 5},
	"text": "Draw 1 card. If it is a Skill, gain {blk} Block.",
	"effects": [{"op": "special", "id": "escape_plan"}],
},
"eviscerate": {
	"name": "Eviscerate", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 3,
	"target": "enemy", "params": {"dmg": 7}, "up": {"dmg": 9},
	"text": "Costs 1 less energy for each card discarded this turn. Deal {dmg} damage 3 times.",
	"effects": [{"op": "damage", "amount": "dmg", "times": 3}],
},
"finisher": {
	"name": "Finisher", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 6}, "up": {"dmg": 8},
	"text": "Deal {dmg} damage for each Attack played this turn.",
	"effects": [{"op": "special", "id": "finisher"}],
},
"flechettes": {
	"name": "Flechettes", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 4}, "up": {"dmg": 6},
	"text": "Deal {dmg} damage for each Skill in your hand.",
	"effects": [{"op": "special", "id": "flechettes"}],
},
"footwork": {
	"name": "Footwork", "type": "power", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "self", "params": {"dex": 2}, "up": {"dex": 3},
	"text": "Gain {dex} Dexterity.",
	"effects": [{"op": "status", "id": "dexterity", "stacks": "dex", "target": "self"}],
},
"heel_hook": {
	"name": "Heel Hook", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 5}, "up": {"dmg": 8},
	"text": "Deal {dmg} damage. If the target is Weak, gain 1 Energy and draw 1 card.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "special", "id": "heel_hook"}],
},
"infinite_blades": {
	"name": "Infinite Blades", "type": "power", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "self", "params": {"n": 1}, "up": {"cost": 0},
	"text": "At the start of your turn, add {n} Shiv to your hand.",
	"effects": [{"op": "status", "id": "infinite_blades", "stacks": "n", "target": "self"}],
},
"leg_sweep": {
	"name": "Leg Sweep", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "enemy", "params": {"weak": 2, "blk": 11}, "up": {"weak": 3, "blk": 14},
	"text": "Apply {weak} Weak. Gain {blk} Block.",
	"effects": [{"op": "status", "id": "weak", "stacks": "weak", "target": "enemy"},
		{"op": "block", "amount": "blk"}],
},
"noxious_fumes": {
	"name": "Noxious Fumes", "type": "power", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "self", "params": {"n": 2}, "up": {"n": 3},
	"text": "At the start of your turn, apply {n} Poison to ALL enemies.",
	"effects": [{"op": "status", "id": "noxious_fumes", "stacks": "n", "target": "self"}],
},
"predator": {
	"name": "Predator", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "enemy", "params": {"dmg": 15}, "up": {"dmg": 20},
	"text": "Deal {dmg} damage. Draw 2 additional cards next turn.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "draw_next_turn", "amount": 2}],
},
"riddle_with_holes": {
	"name": "Riddle with Holes", "type": "attack", "rarity": "uncommon", "color": "green", "cost": 2,
	"target": "enemy", "params": {"dmg": 3, "hits": 5}, "up": {"dmg": 4},
	"text": "Deal {dmg} damage {hits} times.",
	"effects": [{"op": "damage", "amount": "dmg", "times": "hits"}],
},
"reflex": {
	"name": "Reflex", "type": "skill", "rarity": "uncommon", "color": "green", "cost": -2,
	"target": "none", "params": {"cards": 2}, "up": {"cards": 3},
	"text": "Unplayable. If this card is discarded, draw {cards} cards.",
	"flags": ["unplayable"], "effects": [],
},
"tactician": {
	"name": "Tactician", "type": "skill", "rarity": "uncommon", "color": "green", "cost": -2,
	"target": "none", "params": {"nrg": 1}, "up": {"nrg": 2},
	"text": "Unplayable. If this card is discarded, gain {nrg} Energy.",
	"flags": ["unplayable"], "effects": [],
},
"terror": {
	"name": "Terror", "type": "skill", "rarity": "uncommon", "color": "green", "cost": 1,
	"target": "enemy", "params": {}, "up": {"cost": 0},
	"text": "Apply 99 Vulnerable. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "vulnerable", "stacks": 99, "target": "enemy"}],
},

# ─────────────────────────────── Silent — rare ─────────────────────────────────
"adrenaline": {
	"name": "Adrenaline", "type": "skill", "rarity": "rare", "color": "green", "cost": 0,
	"target": "self", "params": {"nrg": 1}, "up": {"nrg": 2},
	"text": "Gain {nrg} Energy. Draw 2 cards. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "energy", "amount": "nrg"}, {"op": "draw", "amount": 2}],
},
"after_image": {
	"name": "After Image", "type": "power", "rarity": "rare", "color": "green", "cost": 1,
	"target": "self", "params": {"n": 1}, "up": {"innate": 1},
	"text": "Whenever you play a card, gain {n} Block.",
	"effects": [{"op": "status", "id": "after_image", "stacks": "n", "target": "self"}],
},
"a_thousand_cuts": {
	"name": "A Thousand Cuts", "type": "power", "rarity": "rare", "color": "green", "cost": 2,
	"target": "self", "params": {"n": 1}, "up": {"n": 2},
	"text": "Whenever you play a card, deal {n} damage to ALL enemies.",
	"effects": [{"op": "status", "id": "thousand_cuts", "stacks": "n", "target": "self"}],
},
"corpse_explosion": {
	"name": "Corpse Explosion", "type": "skill", "rarity": "rare", "color": "green", "cost": 2,
	"target": "enemy", "params": {"psn": 6}, "up": {"psn": 9},
	"text": "Apply {psn} Poison. When the target dies, deal its max HP damage to ALL enemies.",
	"effects": [{"op": "status", "id": "poison", "stacks": "psn", "target": "enemy"},
		{"op": "status", "id": "corpse_explosion", "stacks": 1, "target": "enemy"}],
},
"die_die_die": {
	"name": "Die Die Die", "type": "attack", "rarity": "rare", "color": "green", "cost": 1,
	"target": "all", "params": {"dmg": 13}, "up": {"dmg": 17},
	"text": "Deal {dmg} damage to ALL enemies. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "damage", "amount": "dmg", "target": "all"}],
},
"glass_knife": {
	"name": "Glass Knife", "type": "attack", "rarity": "rare", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 8}, "up": {"dmg": 12},
	"text": "Deal {dmg} damage twice. This card's damage is lowered by 2 this combat.",
	"effects": [{"op": "damage", "amount": "dmg", "times": 2}, {"op": "special", "id": "glass_knife"}],
},
"grand_finale": {
	"name": "Grand Finale", "type": "attack", "rarity": "rare", "color": "green", "cost": 0,
	"target": "all", "params": {"dmg": 50}, "up": {"dmg": 60},
	"text": "Can only be played if there are no cards in your draw pile. Deal {dmg} damage to ALL enemies.",
	"effects": [{"op": "damage", "amount": "dmg", "target": "all"}],
},
"malaise": {
	"name": "Malaise", "type": "skill", "rarity": "rare", "color": "green", "cost": -1,
	"target": "enemy", "params": {}, "up": {"plus": 1},
	"text": "The enemy loses X Strength and gains X Weak. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "special", "id": "malaise"}],
},
"phantasmal_killer": {
	"name": "Phantasmal Killer", "type": "skill", "rarity": "rare", "color": "green", "cost": 1,
	"target": "self", "params": {}, "up": {"cost": 0},
	"text": "Next turn, your Attacks deal double damage.",
	"effects": [{"op": "status", "id": "phantasmal", "stacks": 1, "target": "self"}],
},
"tools_of_the_trade": {
	"name": "Tools of the Trade", "type": "power", "rarity": "rare", "color": "green", "cost": 1,
	"target": "self", "params": {}, "up": {"cost": 0},
	"text": "At the start of your turn, draw 1 card and discard 1 card.",
	"effects": [{"op": "status", "id": "tools_of_the_trade", "stacks": 1, "target": "self"}],
},
"unload": {
	"name": "Unload", "type": "attack", "rarity": "rare", "color": "green", "cost": 1,
	"target": "enemy", "params": {"dmg": 14}, "up": {"dmg": 18},
	"text": "Deal {dmg} damage. Discard all non-Attack cards in your hand.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "special", "id": "unload"}],
},
"wraith_form": {
	"name": "Wraith Form", "type": "power", "rarity": "rare", "color": "green", "cost": 3,
	"target": "self", "params": {"n": 2}, "up": {"n": 3},
	"text": "Gain {n} Intangible-like Dexterity. At the end of your turn, lose 1 Dexterity.",
	"effects": [{"op": "status", "id": "dexterity", "stacks": "n", "target": "self"},
		{"op": "status", "id": "wraith_form", "stacks": 1, "target": "self"}],
},

# ────────────────────────────────── Colorless ─────────────────────────────────
"shiv": {
	"name": "Shiv", "type": "attack", "rarity": "special", "color": "colorless", "cost": 0,
	"target": "enemy", "params": {"dmg": 4}, "up": {"dmg": 6},
	"text": "Deal {dmg} damage. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"bandage_up": {
	"name": "Bandage Up", "type": "skill", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "self", "params": {"hp": 4}, "up": {"hp": 6},
	"text": "Heal {hp} HP. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "heal", "amount": "hp"}],
},
"blind": {
	"name": "Blind", "type": "skill", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "enemy", "params": {"weak": 2}, "up": {"target_all": 1},
	"text": "Apply {weak} Weak.",
	"effects": [{"op": "status", "id": "weak", "stacks": "weak", "target": "enemy"}],
},
"dark_shackles": {
	"name": "Dark Shackles", "type": "skill", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "enemy", "params": {"str": 9}, "up": {"str": 15},
	"text": "Enemy loses {str} Strength this turn. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "strength", "stacks": -1, "scale": "str", "target": "enemy"},
		{"op": "status", "id": "strength_up_end", "stacks": "str", "target": "enemy"}],
},
"finesse": {
	"name": "Finesse", "type": "skill", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "self", "params": {"blk": 2}, "up": {"blk": 4},
	"text": "Gain {blk} Block. Draw 1 card.",
	"effects": [{"op": "block", "amount": "blk"}, {"op": "draw", "amount": 1}],
},
"flash_of_steel": {
	"name": "Flash of Steel", "type": "attack", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "enemy", "params": {"dmg": 3}, "up": {"dmg": 6},
	"text": "Deal {dmg} damage. Draw 1 card.",
	"effects": [{"op": "damage", "amount": "dmg"}, {"op": "draw", "amount": 1}],
},
"swift_strike": {
	"name": "Swift Strike", "type": "attack", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "enemy", "params": {"dmg": 7}, "up": {"dmg": 10},
	"text": "Deal {dmg} damage.",
	"effects": [{"op": "damage", "amount": "dmg"}],
},
"trip": {
	"name": "Trip", "type": "skill", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "enemy", "params": {"vuln": 2}, "up": {"target_all": 1},
	"text": "Apply {vuln} Vulnerable.",
	"effects": [{"op": "status", "id": "vulnerable", "stacks": "vuln", "target": "enemy"}],
},
"apotheosis": {
	"name": "Apotheosis", "type": "skill", "rarity": "rare", "color": "colorless", "cost": 2,
	"target": "self", "params": {}, "up": {"cost": 1},
	"text": "Upgrade ALL of your cards for the rest of combat. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "upgrade_all_in_combat"}],
},
"hand_of_greed": {
	"name": "Hand of Greed", "type": "attack", "rarity": "rare", "color": "colorless", "cost": 2,
	"target": "enemy", "params": {"dmg": 20, "gold": 20}, "up": {"dmg": 25, "gold": 25},
	"text": "Deal {dmg} damage. If this kills a non-minion enemy, gain {gold} Gold.",
	"effects": [{"op": "special", "id": "hand_of_greed"}],
},
"master_of_strategy": {
	"name": "Master of Strategy", "type": "skill", "rarity": "rare", "color": "colorless", "cost": 0,
	"target": "self", "params": {"cards": 3}, "up": {"cards": 4},
	"text": "Draw {cards} cards. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "draw", "amount": "cards"}],
},
"panacea": {
	"name": "Panacea", "type": "skill", "rarity": "uncommon", "color": "colorless", "cost": 0,
	"target": "self", "params": {"n": 1}, "up": {"n": 2},
	"text": "Gain {n} Artifact. Exhaust.", "flags": ["exhaust"],
	"effects": [{"op": "status", "id": "artifact", "stacks": "n", "target": "self"}],
},
"mayhem": {
	"name": "Mayhem", "type": "power", "rarity": "rare", "color": "colorless", "cost": 2,
	"target": "self", "params": {}, "up": {"cost": 1},
	"text": "At the start of your turn, play the top card of your draw pile.",
	"effects": [{"op": "status", "id": "mayhem", "stacks": 1, "target": "self"}],
},

# ───────────────────────────── Status & curse cards ───────────────────────────
"wound": {
	"name": "Wound", "type": "status", "rarity": "special", "color": "status", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Unplayable.", "flags": ["unplayable", "no_upgrade"], "effects": [],
},
"dazed": {
	"name": "Dazed", "type": "status", "rarity": "special", "color": "status", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Ethereal. Unplayable.", "flags": ["unplayable", "ethereal", "no_upgrade"], "effects": [],
},
"burn": {
	"name": "Burn", "type": "status", "rarity": "special", "color": "status", "cost": -2,
	"target": "none", "params": {"dmg": 2}, "up": {"dmg": 4},
	"text": "Unplayable. At the end of your turn, take {dmg} damage.",
	"flags": ["unplayable", "no_upgrade"], "effects": [],
},
"slimed": {
	"name": "Slimed", "type": "status", "rarity": "special", "color": "status", "cost": 1,
	"target": "none", "params": {}, "up": {},
	"text": "Exhaust.", "flags": ["exhaust", "no_upgrade"], "effects": [],
},
"void": {
	"name": "Void", "type": "status", "rarity": "special", "color": "status", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Unplayable. When drawn, lose 1 Energy.",
	"flags": ["unplayable", "no_upgrade"], "effects": [],
},
"regret": {
	"name": "Regret", "type": "curse", "rarity": "curse", "color": "curse", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Unplayable. At the end of your turn, lose 1 HP for each card in your hand.",
	"flags": ["unplayable", "no_upgrade"], "effects": [],
},
"injury": {
	"name": "Injury", "type": "curse", "rarity": "curse", "color": "curse", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Unplayable.", "flags": ["unplayable", "no_upgrade"], "effects": [],
},
"clumsy": {
	"name": "Clumsy", "type": "curse", "rarity": "curse", "color": "curse", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Ethereal. Unplayable.", "flags": ["unplayable", "ethereal", "no_upgrade"], "effects": [],
},
"doubt": {
	"name": "Doubt", "type": "curse", "rarity": "curse", "color": "curse", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Unplayable. At the end of your turn, gain 1 Weak.",
	"flags": ["unplayable", "no_upgrade"], "effects": [],
},
"pain": {
	"name": "Pain", "type": "curse", "rarity": "curse", "color": "curse", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Unplayable. While in hand, lose 1 HP whenever you play a card.",
	"flags": ["unplayable", "no_upgrade"], "effects": [],
},
"ascenders_bane": {
	"name": "Ascender's Bane", "type": "curse", "rarity": "curse", "color": "curse", "cost": -2,
	"target": "none", "params": {}, "up": {},
	"text": "Ethereal. Unplayable. Cannot be removed from your deck.",
	"flags": ["unplayable", "ethereal", "no_upgrade"], "effects": [],
},
}


static func has(id: String) -> bool:
	if PokeMoves.is_move_card(id):
		return not PokeMoves.get_def(id).is_empty()
	return CARDS.has(id)


static func get_def(id: String) -> Dictionary:
	if PokeMoves.is_move_card(id):
		var d := PokeMoves.get_def(id)
		if not d.is_empty():
			return d
	return CARDS.get(id, CARDS["strike"])


## Character definition, covering both the Spire's two and every Pokemon.
static func character(id: String) -> Dictionary:
	if PokeCharacters.is_pokemon_character(id):
		return PokeCharacters.get_def(id)
	return CHARACTERS.get(id, CHARACTERS["ironclad"])


static func starter_deck(id: String) -> Array:
	if PokeCharacters.is_pokemon_character(id):
		return PokeCharacters.starter_deck(id)
	return (STARTER_DECKS.get(id, STARTER_DECKS["ironclad"]) as Array).duplicate()


## All cards obtainable as rewards for a given character colour.
##
## A Pokemon draws only from its own learnset, so the pool depends on who is
## running rather than on the colour alone.
static func pool_for(color: String, rarity: String = "") -> Array:
	if color == PokeCharacters.COLOR:
		return PokeCharacters.reward_pool(Run.character, rarity)
	var out: Array = []
	for id in CARDS:
		var c: Dictionary = CARDS[id]
		if c["color"] != color:
			continue
		if c["rarity"] in ["basic", "special", "curse"]:
			continue
		if rarity != "" and c["rarity"] != rarity:
			continue
		out.append(id)
	out.sort()
	return out


static func colorless_pool(rarity: String = "") -> Array:
	var out: Array = []
	for id in CARDS:
		var c: Dictionary = CARDS[id]
		if c["color"] != "colorless" or c["rarity"] == "special":
			continue
		if rarity != "" and c["rarity"] != rarity:
			continue
		out.append(id)
	out.sort()
	return out


static func curse_pool() -> Array:
	var out: Array = []
	for id in CARDS:
		if CARDS[id]["color"] == "curse" and id != "ascenders_bane":
			out.append(id)
	out.sort()
	return out


static func color_tint(color: String) -> Color:
	match color:
		"pokemon": return Color(0.20, 0.36, 0.52)
		"red": return Color(0.62, 0.19, 0.18)
		"green": return Color(0.16, 0.44, 0.24)
		"colorless": return Color(0.35, 0.38, 0.45)
		"status": return Color(0.28, 0.30, 0.36)
		"curse": return Color(0.16, 0.12, 0.20)
	return Color(0.3, 0.3, 0.3)


static func type_tint(type: String) -> Color:
	match type:
		"attack": return Color(0.85, 0.40, 0.32)
		"skill": return Color(0.42, 0.66, 0.88)
		"power": return Color(0.78, 0.62, 0.90)
		"status": return Color(0.60, 0.60, 0.65)
		"curse": return Color(0.55, 0.35, 0.65)
	return Color(0.7, 0.7, 0.7)
