class_name EnemyLibrary
extends RefCounted

## Enemy definitions, move sets and per-enemy AI.
##
## Enemy fields
##   name    : display name
##   hp      : [min, max] rolled at spawn
##   powers  : statuses granted at combat start
##   roll    : {key: [min, max]} values rolled once at spawn, referenced by "@key"
##   moves   : name -> {intent, effects}
##   boss / minion : flags
##
## Intent kinds drive the icon shown above the enemy:
##   attack, attack_defend, attack_debuff, attack_buff, defend, buff, debuff,
##   strong_debuff, sleep, stun, unknown, escape

static var ENEMIES := {

# ───────────────────────────────── Act 1 — normal ─────────────────────────────
"jaw_worm": {
	"name": "Jaw Worm", "hp": [40, 44],
	"moves": {
		"Chomp": {"intent": "attack", "effects": [{"op": "damage", "amount": 11}]},
		"Thrash": {"intent": "attack_defend", "effects": [
			{"op": "damage", "amount": 7}, {"op": "block", "amount": 5}]},
		"Bellow": {"intent": "attack_buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 3, "target": "self"},
			{"op": "block", "amount": 6}]},
	},
},
"cultist": {
	"name": "Cultist", "hp": [48, 54],
	"moves": {
		"Incantation": {"intent": "buff", "effects": [
			{"op": "status", "id": "ritual", "stacks": 3, "target": "self"}]},
		"Dark Strike": {"intent": "attack", "effects": [{"op": "damage", "amount": 6}]},
	},
},
"red_louse": {
	"name": "Red Louse", "hp": [10, 15], "powers": {"curl_up": 5},
	"roll": {"dmg": [5, 7]},
	"moves": {
		"Bite": {"intent": "attack", "effects": [{"op": "damage", "amount": "@dmg"}]},
		"Grow": {"intent": "buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 3, "target": "self"}]},
	},
},
"green_louse": {
	"name": "Green Louse", "hp": [11, 17], "powers": {"curl_up": 5},
	"roll": {"dmg": [5, 7]},
	"moves": {
		"Bite": {"intent": "attack", "effects": [{"op": "damage", "amount": "@dmg"}]},
		"Spit Web": {"intent": "debuff", "effects": [
			{"op": "status", "id": "weak", "stacks": 2, "target": "player"}]},
	},
},
"acid_slime_m": {
	"name": "Acid Slime (M)", "hp": [28, 32],
	"moves": {
		"Corrosive Spit": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 7},
			{"op": "add_card", "id": "slimed", "dest": "discard", "count": 1}]},
		"Tackle": {"intent": "attack", "effects": [{"op": "damage", "amount": 10}]},
		"Lick": {"intent": "debuff", "effects": [
			{"op": "status", "id": "weak", "stacks": 1, "target": "player"}]},
	},
},
"acid_slime_s": {
	"name": "Acid Slime (S)", "hp": [8, 12],
	"moves": {
		"Lick": {"intent": "debuff", "effects": [
			{"op": "status", "id": "weak", "stacks": 1, "target": "player"}]},
		"Tackle": {"intent": "attack", "effects": [{"op": "damage", "amount": 3}]},
	},
},
"spike_slime_m": {
	"name": "Spike Slime (M)", "hp": [28, 32],
	"moves": {
		"Flame Tackle": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 8},
			{"op": "add_card", "id": "slimed", "dest": "discard", "count": 1}]},
		"Lick": {"intent": "debuff", "effects": [
			{"op": "status", "id": "frail", "stacks": 1, "target": "player"}]},
	},
},
"spike_slime_s": {
	"name": "Spike Slime (S)", "hp": [10, 14],
	"moves": {
		"Tackle": {"intent": "attack", "effects": [{"op": "damage", "amount": 5}]},
	},
},
"fungi_beast": {
	"name": "Fungi Beast", "hp": [22, 28], "powers": {"spore_cloud": 2},
	"moves": {
		"Bite": {"intent": "attack", "effects": [{"op": "damage", "amount": 6}]},
		"Grow": {"intent": "buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 3, "target": "self"}]},
	},
},
"mad_gremlin": {
	"name": "Mad Gremlin", "hp": [20, 24], "powers": {"angry": 1},
	"moves": {
		"Scratch": {"intent": "attack", "effects": [{"op": "damage", "amount": 4}]},
	},
},
"sneaky_gremlin": {
	"name": "Sneaky Gremlin", "hp": [10, 14],
	"moves": {
		"Puncture": {"intent": "attack", "effects": [{"op": "damage", "amount": 9}]},
	},
},
"fat_gremlin": {
	"name": "Fat Gremlin", "hp": [13, 17],
	"moves": {
		"Smash": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 4},
			{"op": "status", "id": "weak", "stacks": 1, "target": "player"}]},
	},
},
"shield_gremlin": {
	"name": "Shield Gremlin", "hp": [12, 15],
	"moves": {
		"Protect": {"intent": "defend", "effects": [{"op": "block_ally", "amount": 7}]},
		"Shield Bash": {"intent": "attack", "effects": [{"op": "damage", "amount": 6}]},
	},
},
"gremlin_wizard": {
	"name": "Gremlin Wizard", "hp": [21, 25],
	"moves": {
		"Charging": {"intent": "unknown", "effects": []},
		"Ultimate Blast": {"intent": "attack", "effects": [{"op": "damage", "amount": 25}]},
	},
},
"looter": {
	"name": "Looter", "hp": [44, 48],
	"moves": {
		"Mug": {"intent": "attack", "effects": [{"op": "damage", "amount": 10}]},
		"Lunge": {"intent": "attack", "effects": [{"op": "damage", "amount": 12}]},
		"Smoke Bomb": {"intent": "defend", "effects": [{"op": "block", "amount": 6}]},
		"Escape": {"intent": "escape", "effects": [{"op": "flee"}]},
	},
},
"slaver_blue": {
	"name": "Blue Slaver", "hp": [46, 50],
	"moves": {
		"Stab": {"intent": "attack", "effects": [{"op": "damage", "amount": 12}]},
		"Rake": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 7},
			{"op": "status", "id": "weak", "stacks": 1, "target": "player"}]},
	},
},
"slaver_red": {
	"name": "Red Slaver", "hp": [46, 50],
	"moves": {
		"Stab": {"intent": "attack", "effects": [{"op": "damage", "amount": 13}]},
		"Scrape": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 8},
			{"op": "status", "id": "vulnerable", "stacks": 1, "target": "player"}]},
		"Entangle": {"intent": "debuff", "effects": [
			{"op": "status", "id": "frail", "stacks": 2, "target": "player"}]},
	},
},

# ───────────────────────────────── Act 1 — elites ─────────────────────────────
"gremlin_nob": {
	"name": "Gremlin Nob", "hp": [82, 86], "elite": true,
	"moves": {
		"Bellow": {"intent": "buff", "effects": [
			{"op": "status", "id": "enrage", "stacks": 2, "target": "self"}]},
		"Rush": {"intent": "attack", "effects": [{"op": "damage", "amount": 14}]},
		"Skull Bash": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 6},
			{"op": "status", "id": "vulnerable", "stacks": 2, "target": "player"}]},
	},
},
"lagavulin": {
	"name": "Lagavulin", "hp": [109, 111], "elite": true,
	"powers": {"metallicize": 8, "asleep": 1},
	"moves": {
		"Sleep": {"intent": "sleep", "effects": []},
		"Attack": {"intent": "attack", "effects": [{"op": "damage", "amount": 18}]},
		"Siphon Soul": {"intent": "strong_debuff", "effects": [
			{"op": "status", "id": "strength", "stacks": -1, "scale": 1, "target": "player"},
			{"op": "status", "id": "dexterity", "stacks": -1, "scale": 1, "target": "player"}]},
	},
},
"sentry": {
	"name": "Sentry", "hp": [38, 42], "elite": true, "powers": {"artifact": 1},
	"moves": {
		"Beam": {"intent": "attack", "effects": [{"op": "damage", "amount": 9}]},
		"Bolt": {"intent": "debuff", "effects": [
			{"op": "add_card", "id": "dazed", "dest": "discard", "count": 2}]},
	},
},

# ───────────────────────────────── Act 1 — bosses ─────────────────────────────
"slime_boss": {
	"name": "Slime Boss", "hp": [140, 140], "boss": true,
	"moves": {
		"Goop Spray": {"intent": "debuff", "effects": [
			{"op": "add_card", "id": "slimed", "dest": "discard", "count": 3}]},
		"Preparing": {"intent": "unknown", "effects": []},
		"Slam": {"intent": "attack", "effects": [{"op": "damage", "amount": 35}]},
		"Split": {"intent": "unknown", "effects": [
			{"op": "split", "into": ["acid_slime_m", "spike_slime_m"]}]},
	},
},
"the_guardian": {
	"name": "The Guardian", "hp": [240, 240], "boss": true, "powers": {"mode_shift": 30},
	"moves": {
		"Charging Up": {"intent": "defend", "effects": [{"op": "block", "amount": 9}]},
		"Fierce Bash": {"intent": "attack", "effects": [{"op": "damage", "amount": 32}]},
		"Vent Steam": {"intent": "strong_debuff", "effects": [
			{"op": "status", "id": "vulnerable", "stacks": 2, "target": "player"},
			{"op": "status", "id": "weak", "stacks": 2, "target": "player"}]},
		"Whirlwind": {"intent": "attack", "effects": [
			{"op": "damage", "amount": 5, "times": 4}]},
		"Defensive Mode": {"intent": "buff", "effects": [
			{"op": "status", "id": "thorns", "stacks": 3, "target": "self"}]},
		"Roll Attack": {"intent": "attack", "effects": [{"op": "damage", "amount": 9}]},
		"Twin Slam": {"intent": "attack", "effects": [
			{"op": "damage", "amount": 8, "times": 2}, {"op": "clear_thorns"}]},
	},
},
"hexaghost": {
	"name": "Hexaghost", "hp": [250, 250], "boss": true,
	"moves": {
		"Activate": {"intent": "unknown", "effects": []},
		"Divider": {"intent": "attack", "effects": [{"op": "divider"}]},
		"Sear": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 6},
			{"op": "add_card", "id": "burn", "dest": "discard", "count": 1}]},
		"Tackle": {"intent": "attack", "effects": [{"op": "damage", "amount": 5, "times": 2}]},
		"Inflame": {"intent": "attack_buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 2, "target": "self"},
			{"op": "block", "amount": 12}]},
		"Inferno": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 2, "times": 6},
			{"op": "add_card", "id": "burn", "dest": "discard", "count": 3}]},
	},
},

# ───────────────────────────────── Act 2 — normal ─────────────────────────────
"byrd": {
	"name": "Byrd", "hp": [25, 31], "powers": {"flight": 3},
	"moves": {
		"Peck": {"intent": "attack", "effects": [{"op": "damage", "amount": 1, "times": 5}]},
		"Swoop": {"intent": "attack", "effects": [{"op": "damage", "amount": 12}]},
		"Caw": {"intent": "buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 1, "target": "self"}]},
	},
},
"chosen": {
	"name": "Chosen", "hp": [95, 99],
	"moves": {
		"Zap": {"intent": "attack", "effects": [{"op": "damage", "amount": 21}]},
		"Debilitate": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 12},
			{"op": "status", "id": "vulnerable", "stacks": 2, "target": "player"}]},
		"Drain": {"intent": "strong_debuff", "effects": [
			{"op": "status", "id": "strength", "stacks": -1, "scale": 3, "target": "player"},
			{"op": "status", "id": "strength", "stacks": 3, "target": "self"}]},
		"Hex": {"intent": "debuff", "effects": [
			{"op": "add_card", "id": "dazed", "dest": "draw_random", "count": 2}]},
	},
},
"shelled_parasite": {
	"name": "Shelled Parasite", "hp": [68, 72], "powers": {"plated_armor": 14},
	"moves": {
		"Double Strike": {"intent": "attack", "effects": [{"op": "damage", "amount": 6, "times": 2}]},
		"Suck": {"intent": "attack", "effects": [{"op": "damage", "amount": 10, "drain": true}]},
		"Fell": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 18},
			{"op": "status", "id": "frail", "stacks": 2, "target": "player"}]},
		"Stunned": {"intent": "stun", "effects": []},
	},
},
"centurion": {
	"name": "Centurion", "hp": [76, 80],
	"moves": {
		"Slash": {"intent": "attack", "effects": [{"op": "damage", "amount": 12}]},
		"Fury": {"intent": "attack", "effects": [{"op": "damage", "amount": 6, "times": 3}]},
		"Defend": {"intent": "defend", "effects": [{"op": "block_ally", "amount": 15}]},
	},
},
"mystic": {
	"name": "Mystic", "hp": [48, 56],
	"moves": {
		"Heal": {"intent": "buff", "effects": [
			{"op": "heal_ally", "amount": 16}, {"op": "block_ally", "amount": 10}]},
		"Buff": {"intent": "buff", "effects": [
			{"op": "status_all_allies", "id": "strength", "stacks": 2}]},
		"Attack Debuff": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 8},
			{"op": "status", "id": "frail", "stacks": 2, "target": "player"}]},
	},
},
"snake_plant": {
	"name": "Snake Plant", "hp": [75, 79],
	"moves": {
		"Chomp": {"intent": "attack", "effects": [{"op": "damage", "amount": 7, "times": 3}]},
		"Enfeebling Spores": {"intent": "strong_debuff", "effects": [
			{"op": "status", "id": "weak", "stacks": 2, "target": "player"},
			{"op": "status", "id": "frail", "stacks": 2, "target": "player"}]},
	},
},
"spheric_guardian": {
	"name": "Spheric Guardian", "hp": [20, 20], "powers": {"artifact": 3, "start_block": 40},
	"moves": {
		"Slam": {"intent": "attack", "effects": [{"op": "damage", "amount": 10, "times": 2}]},
		"Activate": {"intent": "defend", "effects": [{"op": "block", "amount": 25}]},
		"Harden": {"intent": "attack_defend", "effects": [
			{"op": "damage", "amount": 10}, {"op": "block", "amount": 15}]},
	},
},

# ───────────────────────────────── Act 2 — elites ─────────────────────────────
"gremlin_leader": {
	"name": "Gremlin Leader", "hp": [140, 148], "elite": true,
	"moves": {
		"Rally": {"intent": "unknown", "effects": [
			{"op": "summon", "options": ["mad_gremlin", "sneaky_gremlin", "fat_gremlin",
				"shield_gremlin"], "count": 2}]},
		"Encourage": {"intent": "buff", "effects": [
			{"op": "status_all_allies", "id": "strength", "stacks": 3},
			{"op": "block_all_allies", "amount": 6}]},
		"Stab": {"intent": "attack", "effects": [{"op": "damage", "amount": 6, "times": 3}]},
	},
},
"book_of_stabbing": {
	"name": "Book of Stabbing", "hp": [160, 172], "elite": true, "powers": {"painful_stabs": 1},
	"moves": {
		"Multi-Stab": {"intent": "attack", "effects": [{"op": "multi_stab"}]},
		"Single Stab": {"intent": "attack", "effects": [{"op": "damage", "amount": 21}]},
	},
},
"taskmaster": {
	"name": "Taskmaster", "hp": [54, 60], "elite": true,
	"moves": {
		"Scouring Whip": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 7},
			{"op": "add_card", "id": "wound", "dest": "discard", "count": 1}]},
	},
},

# ───────────────────────────────── Act 2 — bosses ─────────────────────────────
"champ": {
	"name": "The Champ", "hp": [420, 420], "boss": true,
	"moves": {
		"Defensive Stance": {"intent": "defend", "effects": [
			{"op": "block", "amount": 15},
			{"op": "status", "id": "metallicize", "stacks": 5, "target": "self"}]},
		"Face Slap": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 12},
			{"op": "status", "id": "frail", "stacks": 2, "target": "player"},
			{"op": "status", "id": "vulnerable", "stacks": 2, "target": "player"}]},
		"Heavy Slash": {"intent": "attack", "effects": [{"op": "damage", "amount": 16}]},
		"Gloat": {"intent": "buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 3, "target": "self"}]},
		"Execute": {"intent": "attack", "effects": [{"op": "damage", "amount": 10, "times": 2}]},
		"Anger": {"intent": "buff", "effects": [
			{"op": "status", "id": "strength", "stacks": 6, "target": "self"},
			{"op": "clear_block_self"}]},
	},
},
"bronze_automaton": {
	"name": "Bronze Automaton", "hp": [300, 300], "boss": true, "powers": {"artifact": 3},
	"moves": {
		"Spawn Orbs": {"intent": "unknown", "effects": [
			{"op": "summon", "options": ["bronze_orb"], "count": 2}]},
		"Flail": {"intent": "attack", "effects": [{"op": "damage", "amount": 7, "times": 2}]},
		"Boost": {"intent": "defend", "effects": [
			{"op": "block", "amount": 9},
			{"op": "status", "id": "strength", "stacks": 3, "target": "self"}]},
		"Hyper Beam": {"intent": "attack", "effects": [{"op": "damage", "amount": 45}]},
		"Stunned": {"intent": "stun", "effects": []},
	},
},
"bronze_orb": {
	"name": "Bronze Orb", "hp": [52, 58], "minion": true,
	"moves": {
		"Beam": {"intent": "attack", "effects": [{"op": "damage", "amount": 8}]},
		"Support Beam": {"intent": "defend", "effects": [{"op": "block_ally", "amount": 12}]},
		"Stasis": {"intent": "debuff", "effects": [
			{"op": "add_card", "id": "dazed", "dest": "draw_random", "count": 1}]},
	},
},

# ───────────────────────────────── Act 3 — normal ─────────────────────────────
"darkling": {
	"name": "Darkling", "hp": [48, 56],
	"moves": {
		"Nip": {"intent": "attack", "effects": [{"op": "damage", "amount": 9}]},
		"Chomp": {"intent": "attack", "effects": [{"op": "damage", "amount": 8, "times": 2}]},
		"Harden": {"intent": "attack_defend", "effects": [
			{"op": "damage", "amount": 8}, {"op": "block", "amount": 12}]},
	},
},
"orb_walker": {
	"name": "Orb Walker", "hp": [90, 96],
	"moves": {
		"Laser": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 10},
			{"op": "add_card", "id": "burn", "dest": "discard", "count": 2}]},
		"Claw": {"intent": "attack", "effects": [{"op": "damage", "amount": 15}]},
	},
},
"spiker": {
	"name": "Spiker", "hp": [42, 56], "powers": {"thorns": 3, "artifact": 2},
	"moves": {
		"Cut": {"intent": "attack", "effects": [{"op": "damage", "amount": 7}]},
		"Spike": {"intent": "buff", "effects": [
			{"op": "status", "id": "thorns", "stacks": 2, "target": "self"}]},
	},
},
"repulsor": {
	"name": "Repulsor", "hp": [29, 35],
	"moves": {
		"Bash": {"intent": "attack", "effects": [{"op": "damage", "amount": 11}]},
		"Repulse": {"intent": "debuff", "effects": [
			{"op": "add_card", "id": "dazed", "dest": "draw_random", "count": 2}]},
	},
},
"transient": {
	"name": "Transient", "hp": [999, 999], "powers": {"fading": 5},
	"moves": {
		"Attack": {"intent": "attack", "effects": [{"op": "transient_attack"}]},
	},
},

# ───────────────────────────────── Act 3 — elites ─────────────────────────────
"nemesis": {
	"name": "Nemesis", "hp": [185, 185], "elite": true,
	"moves": {
		"Scythe": {"intent": "attack", "effects": [{"op": "damage", "amount": 45}]},
		"Debuff": {"intent": "debuff", "effects": [
			{"op": "add_card", "id": "burn", "dest": "discard", "count": 3}]},
		"Attack": {"intent": "attack", "effects": [{"op": "damage", "amount": 6, "times": 3}]},
	},
},
"giant_head": {
	"name": "Giant Head", "hp": [340, 340], "elite": true, "powers": {"slow_start": 1},
	"moves": {
		"Glare": {"intent": "debuff", "effects": [
			{"op": "status", "id": "weak", "stacks": 1, "target": "player"}]},
		"Count": {"intent": "attack", "effects": [{"op": "damage", "amount": 13}]},
		"It Is Time": {"intent": "attack", "effects": [{"op": "damage", "amount": 40}]},
	},
},

# ───────────────────────────────── Act 3 — bosses ─────────────────────────────
"awakened_one": {
	"name": "Awakened One", "hp": [300, 300], "boss": true,
	"powers": {"curiosity": 1, "unawakened": 1},
	"moves": {
		"Slash": {"intent": "attack", "effects": [{"op": "damage", "amount": 20}]},
		"Soul Strike": {"intent": "attack", "effects": [{"op": "damage", "amount": 6, "times": 4}]},
		"Rebirth": {"intent": "unknown", "effects": [{"op": "rebirth"}]},
		"Dark Echo": {"intent": "attack", "effects": [{"op": "damage", "amount": 40}]},
		"Sludge": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 18},
			{"op": "add_card", "id": "void", "dest": "discard", "count": 1}]},
		"Tackle": {"intent": "attack", "effects": [{"op": "damage", "amount": 10, "times": 2}]},
	},
},
"time_eater": {
	"name": "Time Eater", "hp": [456, 456], "boss": true,
	"moves": {
		"Reverberate": {"intent": "attack", "effects": [{"op": "damage", "amount": 7, "times": 3}]},
		"Head Slam": {"intent": "attack_debuff", "effects": [
			{"op": "damage", "amount": 26},
			{"op": "status", "id": "frail", "stacks": 2, "target": "player"},
			{"op": "add_card", "id": "slimed", "dest": "draw_random", "count": 1}]},
		"Ripple": {"intent": "strong_debuff", "effects": [
			{"op": "status", "id": "weak", "stacks": 1, "target": "player"},
			{"op": "status", "id": "vulnerable", "stacks": 1, "target": "player"},
			{"op": "status", "id": "frail", "stacks": 1, "target": "player"}]},
		"Haste": {"intent": "buff", "effects": [{"op": "haste"}]},
	},
},
}


static func has(id: String) -> bool:
	return ENEMIES.has(id)


static func get_def(id: String) -> Dictionary:
	return ENEMIES.get(id, ENEMIES["jaw_worm"])


static func spawn(id: String, rng: RandomNumberGenerator, ascension: int = 0) -> Actor:
	var d := get_def(id)
	var a := Actor.new()
	a.enemy_id = id
	a.name = d["name"]
	var hp_range: Array = d["hp"]
	a.max_hp = rng.randi_range(int(hp_range[0]), int(hp_range[1]))
	if ascension > 0:
		a.max_hp = int(round(a.max_hp * (1.0 + 0.05 * ascension)))
	a.hp = a.max_hp
	a.is_minion = bool(d.get("minion", false))
	a.is_boss = bool(d.get("boss", false))
	for k in d.get("powers", {}):
		if k == "start_block":
			a.block = int(d["powers"][k])
		else:
			a.set_status(k, int(d["powers"][k]))
	for k in d.get("roll", {}):
		var r: Array = d["roll"][k]
		a.rolled[k] = rng.randi_range(int(r[0]), int(r[1]))
	return a


static func moves_of(id: String) -> Dictionary:
	return get_def(id)["moves"]


static func _last(a: Actor, back: int = 1) -> String:
	var n := a.move_history.size()
	if n < back:
		return ""
	return a.move_history[n - back]


static func _repeated(a: Actor, move: String, times: int) -> bool:
	if a.move_history.size() < times:
		return false
	for i in range(1, times + 1):
		if _last(a, i) != move:
			return false
	return true


## Decide which move the enemy will use on its upcoming turn.
static func choose_move(a: Actor, combat) -> String:
	var rng: RandomNumberGenerator = combat.rng
	var t: int = a.turn_count
	match a.enemy_id:
		"jaw_worm":
			if t == 0:
				return "Chomp"
			var roll := rng.randf()
			if roll < 0.45 and not _repeated(a, "Bellow", 1):
				return "Bellow"
			elif roll < 0.75 and not _repeated(a, "Thrash", 2):
				return "Thrash"
			elif not _repeated(a, "Chomp", 1):
				return "Chomp"
			return "Thrash"
		"cultist":
			return "Incantation" if t == 0 else "Dark Strike"
		"red_louse", "green_louse":
			var bite_name := "Bite"
			var other := "Grow" if a.enemy_id == "red_louse" else "Spit Web"
			if rng.randf() < 0.75:
				if _repeated(a, bite_name, 2):
					return other
				return bite_name
			if _repeated(a, other, 1):
				return bite_name
			return other
		"acid_slime_m":
			var roll2 := rng.randf()
			if roll2 < 0.3:
				if _repeated(a, "Corrosive Spit", 2):
					return "Tackle"
				return "Corrosive Spit"
			elif roll2 < 0.7:
				if _repeated(a, "Tackle", 2):
					return "Corrosive Spit"
				return "Tackle"
			else:
				if _repeated(a, "Lick", 1):
					return "Tackle"
				return "Lick"
		"acid_slime_s":
			if t == 0:
				return "Lick" if rng.randf() < 0.5 else "Tackle"
			return "Tackle" if _last(a) == "Lick" else "Lick"
		"spike_slime_m":
			if rng.randf() < 0.7:
				if _repeated(a, "Flame Tackle", 2):
					return "Lick"
				return "Flame Tackle"
			if _repeated(a, "Lick", 1):
				return "Flame Tackle"
			return "Lick"
		"spike_slime_s":
			return "Tackle"
		"fungi_beast":
			if rng.randf() < 0.6:
				if _repeated(a, "Bite", 2):
					return "Grow"
				return "Bite"
			if _repeated(a, "Grow", 1):
				return "Bite"
			return "Grow"
		"mad_gremlin":
			return "Scratch"
		"sneaky_gremlin":
			return "Puncture"
		"fat_gremlin":
			return "Smash"
		"shield_gremlin":
			var allies: int = combat.living_enemies().size()
			if allies > 1:
				return "Protect"
			return "Shield Bash"
		"gremlin_wizard":
			# Charges for two turns, blasts on the third, then repeats.
			var cycle := t % 3
			return "Ultimate Blast" if cycle == 2 else "Charging"
		"looter":
			if t == 0 or t == 1:
				return "Mug"
			if t == 2:
				return "Lunge"
			if t == 3:
				return "Smoke Bomb"
			return "Escape"
		"slaver_blue":
			if not a.move_history.has("Rake") and t >= 1 and rng.randf() < 0.4:
				return "Rake"
			if _repeated(a, "Stab", 2):
				return "Rake"
			return "Stab"
		"slaver_red":
			if t == 0:
				return "Stab"
			if not a.move_history.has("Entangle") and rng.randf() < 0.4:
				return "Entangle"
			if _repeated(a, "Stab", 2):
				return "Scrape"
			if _repeated(a, "Scrape", 2):
				return "Stab"
			return "Stab" if rng.randf() < 0.5 else "Scrape"
		"gremlin_nob":
			if t == 0:
				return "Bellow"
			if rng.randf() < 0.33 and not _repeated(a, "Skull Bash", 1):
				return "Skull Bash"
			if _repeated(a, "Rush", 2):
				return "Skull Bash"
			return "Rush"
		"lagavulin":
			if a.has_status("asleep"):
				return "Sleep"
			if _repeated(a, "Attack", 2):
				return "Siphon Soul"
			if _last(a) == "Siphon Soul":
				return "Attack"
			return "Attack"
		"sentry":
			# Sentries alternate; odd slots open with Bolt.
			var offset: int = a.slot % 2
			return "Bolt" if (t + offset) % 2 == 0 else "Beam"
		"slime_boss":
			var cyc := t % 3
			if cyc == 0:
				return "Goop Spray"
			if cyc == 1:
				return "Preparing"
			return "Slam"
		"the_guardian":
			if a.has_status("defensive_mode"):
				# Defensive stance: roll, then a twin slam that drops the shell.
				if _last(a) == "Roll Attack":
					return "Twin Slam"
				return "Roll Attack"
			var off: int = 0
			for m in a.move_history:
				if String(m) in ["Charging Up", "Fierce Bash", "Vent Steam", "Whirlwind"]:
					off += 1
			match off % 4:
				0: return "Charging Up"
				1: return "Fierce Bash"
				2: return "Vent Steam"
				_: return "Whirlwind"
		"hexaghost":
			if t == 0:
				return "Activate"
			if t == 1:
				return "Divider"
			var step := (t - 2) % 7
			match step:
				0, 1: return "Sear"
				2, 4: return "Tackle"
				3: return "Inflame"
				5: return "Sear"
				_: return "Inferno"
		"byrd":
			if a.has_status("flight"):
				var r3 := rng.randf()
				if r3 < 0.5:
					if _repeated(a, "Peck", 2):
						return "Swoop"
					return "Peck"
				if r3 < 0.8:
					if _repeated(a, "Swoop", 1):
						return "Peck"
					return "Swoop"
				return "Caw"
			return "Peck"
		"chosen":
			if t == 0:
				return "Hex"
			if t == 1:
				return "Zap"
			if _repeated(a, "Debilitate", 1):
				return "Drain" if rng.randf() < 0.5 else "Zap"
			var r4 := rng.randf()
			if r4 < 0.4:
				return "Debilitate"
			if r4 < 0.7:
				return "Zap"
			return "Drain"
		"shelled_parasite":
			if t == 0:
				return "Double Strike"
			if _repeated(a, "Fell", 1):
				return "Double Strike"
			var r5 := rng.randf()
			if r5 < 0.2:
				return "Fell"
			if r5 < 0.6:
				return "Suck"
			return "Double Strike"
		"centurion":
			var ally_needs_help := false
			for e in combat.living_enemies():
				if e != a and e.hp_ratio() < 0.5:
					ally_needs_help = true
			if ally_needs_help and combat.living_enemies().size() > 1:
				return "Defend"
			if _repeated(a, "Slash", 1):
				return "Fury"
			return "Slash"
		"mystic":
			var hurt := false
			for e in combat.living_enemies():
				if e.hp_ratio() < 0.75:
					hurt = true
			if t == 0:
				return "Buff"
			if hurt and not _repeated(a, "Heal", 1):
				return "Heal"
			if _repeated(a, "Attack Debuff", 2):
				return "Buff"
			return "Attack Debuff"
		"snake_plant":
			if _repeated(a, "Chomp", 2):
				return "Enfeebling Spores"
			if _last(a) == "Enfeebling Spores":
				return "Chomp"
			return "Chomp" if rng.randf() < 0.65 else "Enfeebling Spores"
		"spheric_guardian":
			if t == 0:
				return "Activate"
			if t == 1:
				return "Slam"
			if _last(a) == "Slam":
				return "Harden"
			return "Slam"
		"gremlin_leader":
			var minions := 0
			for e in combat.living_enemies():
				if e != a:
					minions += 1
			if minions == 0:
				return "Rally"
			if minions < 2 and rng.randf() < 0.5:
				return "Rally"
			if rng.randf() < 0.4:
				return "Encourage"
			return "Stab"
		"book_of_stabbing":
			if _repeated(a, "Multi-Stab", 2):
				return "Single Stab"
			return "Multi-Stab" if rng.randf() < 0.85 else "Single Stab"
		"taskmaster":
			return "Scouring Whip"
		"champ":
			if a.hp_ratio() <= 0.5 and not a.has_status("angered"):
				a.set_status("angered", 1)
				return "Anger"
			if t > 0 and t % 4 == 3:
				return "Gloat"
			if a.has_status("angered"):
				if _repeated(a, "Execute", 1):
					return "Heavy Slash"
				return "Execute" if rng.randf() < 0.5 else "Heavy Slash"
			var r6 := rng.randf()
			if r6 < 0.3:
				return "Defensive Stance"
			if r6 < 0.55:
				return "Face Slap"
			return "Heavy Slash"
		"bronze_automaton":
			if a.has_status("stunned_next"):
				a.set_status("stunned_next", 0)
				return "Stunned"
			if t == 0:
				return "Spawn Orbs"
			var since: int = a.get_status("hyper_counter")
			if since >= 4:
				a.set_status("hyper_counter", 0)
				a.set_status("stunned_next", 1)
				return "Hyper Beam"
			a.set_status("hyper_counter", since + 1)
			return "Flail" if since % 2 == 1 else "Boost"
		"bronze_orb":
			if t == 0:
				return "Beam"
			if t == 1:
				return "Support Beam"
			return "Beam" if rng.randf() < 0.6 else "Stasis"
		"darkling":
			if t == 0:
				return "Chomp"
			var r7 := rng.randf()
			if r7 < 0.4 and not _repeated(a, "Nip", 2):
				return "Nip"
			if r7 < 0.7 and not _repeated(a, "Harden", 1):
				return "Harden"
			return "Chomp"
		"orb_walker":
			if _repeated(a, "Laser", 2):
				return "Claw"
			return "Laser" if rng.randf() < 0.6 else "Claw"
		"spiker":
			if t == 0:
				return "Spike"
			if _repeated(a, "Cut", 2):
				return "Spike"
			return "Cut"
		"repulsor":
			if _repeated(a, "Bash", 1):
				return "Repulse"
			return "Bash" if rng.randf() < 0.6 else "Repulse"
		"transient":
			return "Attack"
		"nemesis":
			if t == 0:
				return "Debuff"
			if _repeated(a, "Scythe", 1):
				return "Attack"
			if t % 3 == 0:
				return "Scythe"
			return "Attack"
		"giant_head":
			if t < 3:
				return "Glare" if t % 2 == 0 else "Count"
			if t >= 5:
				return "It Is Time"
			return "Count"
		"awakened_one":
			if a.has_status("unawakened"):
				if t == 0:
					return "Slash"
				if _repeated(a, "Slash", 2):
					return "Soul Strike"
				return "Slash" if rng.randf() < 0.6 else "Soul Strike"
			if _last(a) == "Rebirth":
				return "Dark Echo"
			var r8 := rng.randf()
			if r8 < 0.5:
				return "Sludge"
			if r8 < 0.8:
				return "Tackle"
			return "Slash"
		"time_eater":
			if a.hp_ratio() < 0.5 and not a.has_status("hasted"):
				a.set_status("hasted", 1)
				return "Haste"
			var r9 := rng.randf()
			if r9 < 0.45 and not _repeated(a, "Reverberate", 2):
				return "Reverberate"
			if r9 < 0.75 and not _repeated(a, "Head Slam", 1):
				return "Head Slam"
			return "Ripple"
	# Fallback: first move in the table.
	return moves_of(a.enemy_id).keys()[0]


static func intent_symbol(kind: String) -> String:
	match kind:
		"attack": return "⚔"
		"attack_defend": return "⚔🛡"
		"attack_debuff": return "⚔☠"
		"attack_buff": return "⚔▲"
		"defend": return "🛡"
		"buff": return "▲"
		"debuff": return "☠"
		"strong_debuff": return "☠☠"
		"sleep": return "z"
		"stun": return "✳"
		"escape": return "→"
	return "?"


static func intent_color(kind: String) -> Color:
	match kind:
		"attack", "attack_defend", "attack_debuff", "attack_buff":
			return Color(0.95, 0.42, 0.36)
		"defend":
			return Color(0.55, 0.75, 0.95)
		"buff":
			return Color(0.6, 0.9, 0.6)
		"debuff", "strong_debuff":
			return Color(0.85, 0.55, 0.95)
		"sleep", "stun":
			return Color(0.7, 0.7, 0.75)
	return Color(0.85, 0.85, 0.6)
