class_name Statuses
extends RefCounted

## Definitions for every buff / debuff (called "powers" in Slay the Spire).
##
## decay = "turn_end"  -> loses one stack at the end of the owner's turn
## decay = "none"      -> lasts for the whole combat
## decay = "tick"      -> loses one stack right after it triggers (Poison, Regen)

static var DEFS := {
	"strength": {
		"name": "Strength", "debuff": false, "decay": "none", "color": Color(0.95, 0.45, 0.35),
		"desc": "Increases attack damage by {n}.",
	},
	"dexterity": {
		"name": "Dexterity", "debuff": false, "decay": "none", "color": Color(0.45, 0.85, 0.55),
		"desc": "Increases Block gained from cards by {n}.",
	},
	"vulnerable": {
		"name": "Vulnerable", "debuff": true, "decay": "turn_end", "color": Color(0.95, 0.35, 0.45),
		"desc": "Takes 50% more damage from attacks for {n} turn(s).",
	},
	"weak": {
		"name": "Weak", "debuff": true, "decay": "turn_end", "color": Color(0.75, 0.55, 0.95),
		"desc": "Deals 25% less attack damage for {n} turn(s).",
	},
	"frail": {
		"name": "Frail", "debuff": true, "decay": "turn_end", "color": Color(0.8, 0.7, 0.4),
		"desc": "Gains 25% less Block from cards for {n} turn(s).",
	},
	"poison": {
		"name": "Poison", "debuff": true, "decay": "tick", "color": Color(0.45, 0.8, 0.35),
		"desc": "Loses {n} HP at the start of its turn, then Poison drops by 1.",
	},
	"regen": {
		"name": "Regen", "debuff": false, "decay": "tick", "color": Color(0.5, 0.9, 0.6),
		"desc": "Heals {n} HP at the end of its turn, then Regen drops by 1.",
	},
	"thorns": {
		"name": "Thorns", "debuff": false, "decay": "none", "color": Color(0.7, 0.8, 0.9),
		"desc": "Deals {n} damage back when hit by an attack.",
	},
	"metallicize": {
		"name": "Metallicize", "debuff": false, "decay": "none", "color": Color(0.75, 0.78, 0.8),
		"desc": "Gains {n} Block at the end of its turn.",
	},
	"plated_armor": {
		"name": "Plated Armor", "debuff": false, "decay": "none", "color": Color(0.7, 0.75, 0.85),
		"desc": "Gains {n} Block at the end of its turn. Loses 1 stack on unblocked attack damage.",
	},
	"artifact": {
		"name": "Artifact", "debuff": false, "decay": "none", "color": Color(0.95, 0.85, 0.5),
		"desc": "Negates the next {n} debuff(s).",
	},
	"ritual": {
		"name": "Ritual", "debuff": false, "decay": "none", "color": Color(0.9, 0.6, 0.2),
		"desc": "Gains {n} Strength at the end of its turn.",
	},
	"curl_up": {
		"name": "Curl Up", "debuff": false, "decay": "none", "color": Color(0.8, 0.8, 0.6),
		"desc": "The first time it is attacked, gains {n} Block.",
	},
	"angry": {
		"name": "Angry", "debuff": false, "decay": "none", "color": Color(0.95, 0.4, 0.3),
		"desc": "Gains {n} Strength whenever it takes attack damage.",
	},
	"spore_cloud": {
		"name": "Spore Cloud", "debuff": false, "decay": "none", "color": Color(0.6, 0.85, 0.5),
		"desc": "On death, applies {n} Vulnerable to the player.",
	},
	"strength_down": {
		"name": "Strength Down", "debuff": true, "decay": "none", "color": Color(0.85, 0.5, 0.4),
		"desc": "Loses {n} Strength at the end of its turn.",
	},
	"no_draw": {
		"name": "No Draw", "debuff": true, "decay": "turn_end", "color": Color(0.6, 0.6, 0.65),
		"desc": "Cannot draw any more cards this turn.",
	},
	"barricade": {
		"name": "Barricade", "debuff": false, "decay": "none", "color": Color(0.8, 0.8, 0.9),
		"desc": "Block is not removed at the start of your turn.",
	},
	"demon_form": {
		"name": "Demon Form", "debuff": false, "decay": "none", "color": Color(0.9, 0.3, 0.35),
		"desc": "At the start of each turn, gain {n} Strength.",
	},
	"double_tap": {
		"name": "Double Tap", "debuff": false, "decay": "none", "color": Color(0.95, 0.7, 0.4),
		"desc": "The next {n} Attack(s) played is played twice.",
	},
	"feel_no_pain": {
		"name": "Feel No Pain", "debuff": false, "decay": "none", "color": Color(0.8, 0.8, 0.75),
		"desc": "Whenever a card is Exhausted, gain {n} Block.",
	},
	"rupture": {
		"name": "Rupture", "debuff": false, "decay": "none", "color": Color(0.9, 0.4, 0.4),
		"desc": "Whenever you lose HP from a card, gain {n} Strength.",
	},
	"combust": {
		"name": "Combust", "debuff": false, "decay": "none", "color": Color(0.95, 0.55, 0.3),
		"desc": "At the end of your turn, lose 1 HP and deal {n} damage to ALL enemies.",
	},
	"evolve": {
		"name": "Evolve", "debuff": false, "decay": "none", "color": Color(0.6, 0.9, 0.8),
		"desc": "Whenever you draw a Status card, draw {n} card(s).",
	},
	"fire_breathing": {
		"name": "Fire Breathing", "debuff": false, "decay": "none", "color": Color(0.95, 0.5, 0.25),
		"desc": "Whenever you draw a Status or Curse card, deal {n} damage to ALL enemies.",
	},
	"juggernaut": {
		"name": "Juggernaut", "debuff": false, "decay": "none", "color": Color(0.75, 0.75, 0.85),
		"desc": "Whenever you gain Block, deal {n} damage to a random enemy.",
	},
	"dark_embrace": {
		"name": "Dark Embrace", "debuff": false, "decay": "none", "color": Color(0.55, 0.5, 0.75),
		"desc": "Whenever a card is Exhausted, draw {n} card(s).",
	},
	"envenom": {
		"name": "Envenom", "debuff": false, "decay": "none", "color": Color(0.5, 0.8, 0.4),
		"desc": "Whenever an attack deals unblocked damage, apply {n} Poison.",
	},
	"after_image": {
		"name": "After Image", "debuff": false, "decay": "none", "color": Color(0.7, 0.85, 0.95),
		"desc": "Whenever you play a card, gain {n} Block.",
	},
	"thousand_cuts": {
		"name": "Thousand Cuts", "debuff": false, "decay": "none", "color": Color(0.9, 0.75, 0.5),
		"desc": "Whenever you play a card, deal {n} damage to ALL enemies.",
	},
	"noxious_fumes": {
		"name": "Noxious Fumes", "debuff": false, "decay": "none", "color": Color(0.55, 0.85, 0.4),
		"desc": "At the start of your turn, apply {n} Poison to ALL enemies.",
	},
	"infinite_blades": {
		"name": "Infinite Blades", "debuff": false, "decay": "none", "color": Color(0.8, 0.85, 0.9),
		"desc": "At the start of your turn, add {n} Shiv(s) to your hand.",
	},
	"accuracy": {
		"name": "Accuracy", "debuff": false, "decay": "none", "color": Color(0.85, 0.85, 0.6),
		"desc": "Shivs deal {n} additional damage.",
	},
	"painful_stabs": {
		"name": "Painful Stabs", "debuff": false, "decay": "none", "color": Color(0.9, 0.5, 0.5),
		"desc": "Whenever it deals unblocked damage, adds a Wound to your discard pile.",
	},
	"minion": {
		"name": "Minion", "debuff": false, "decay": "none", "color": Color(0.7, 0.7, 0.7),
		"desc": "A summoned creature.",
	},
	"flight": {
		"name": "Flight", "debuff": false, "decay": "none", "color": Color(0.7, 0.9, 0.95),
		"desc": "Attack damage received is halved. Removed after {n} more hits.",
	},
	"enrage": {
		"name": "Enrage", "debuff": false, "decay": "none", "color": Color(0.95, 0.4, 0.3),
		"desc": "Whenever you play a Skill, gains {n} Strength.",
	},
	"asleep": {
		"name": "Asleep", "debuff": false, "decay": "none", "color": Color(0.6, 0.65, 0.8),
		"desc": "Dormant until it takes damage.",
	},
	"corpse_explosion": {
		"name": "Corpse Explosion", "debuff": true, "decay": "none", "color": Color(0.6, 0.85, 0.4),
		"desc": "On death, deals damage equal to its Max HP to ALL enemies.",
	},
	"berserk": {
		"name": "Berserk", "debuff": false, "decay": "none", "color": Color(0.9, 0.35, 0.3),
		"desc": "At the start of your turn, gain {n} Energy.",
	},
	"brutality": {
		"name": "Brutality", "debuff": false, "decay": "none", "color": Color(0.85, 0.35, 0.35),
		"desc": "At the start of your turn, lose {n} HP and draw {n} card(s).",
	},
	"corruption": {
		"name": "Corruption", "debuff": false, "decay": "none", "color": Color(0.55, 0.45, 0.6),
		"desc": "Skills cost 0 and Exhaust when played.",
	},
	"blur": {
		"name": "Blur", "debuff": false, "decay": "turn_end", "color": Color(0.6, 0.8, 0.95),
		"desc": "Block is not removed at the start of your next turn.",
	},
	"phantasmal": {
		"name": "Phantasmal", "debuff": false, "decay": "none", "color": Color(0.75, 0.6, 0.95),
		"desc": "Your Attacks deal double damage for {n} turn(s).",
	},
	"tools_of_the_trade": {
		"name": "Tools of the Trade", "debuff": false, "decay": "none", "color": Color(0.8, 0.8, 0.6),
		"desc": "At the start of your turn, draw {n} and discard {n}.",
	},
	"mayhem": {
		"name": "Mayhem", "debuff": false, "decay": "none", "color": Color(0.9, 0.6, 0.5),
		"desc": "At the start of your turn, play the top card of your draw pile.",
	},
	"wraith_form": {
		"name": "Wraith Form", "debuff": false, "decay": "none", "color": Color(0.65, 0.55, 0.85),
		"desc": "At the end of your turn, lose 1 Dexterity.",
	},
	"strength_up_end": {
		"name": "Regain Strength", "debuff": false, "decay": "none", "color": Color(0.8, 0.7, 0.6),
		"desc": "Regains {n} Strength at the end of the turn.",
	},
	"fading": {
		"name": "Fading", "debuff": false, "decay": "tick", "color": Color(0.7, 0.7, 0.8),
		"desc": "Dies in {n} turn(s).",
	},
	"curiosity": {
		"name": "Curiosity", "debuff": false, "decay": "none", "color": Color(0.85, 0.6, 0.9),
		"desc": "Whenever you play a Power, gains {n} Strength.",
	},
	"unawakened": {
		"name": "Unawakened", "debuff": false, "decay": "none", "color": Color(0.75, 0.6, 0.85),
		"desc": "It will rise again when defeated.",
	},
	"slow_start": {
		"name": "Slow", "debuff": false, "decay": "none", "color": Color(0.75, 0.75, 0.8),
		"desc": "Takes {n}% more damage for each card played this turn.",
	},
	"mode_shift": {
		"name": "Mode Shift", "debuff": false, "decay": "none", "color": Color(0.8, 0.8, 0.9),
		"desc": "Shifts to Defensive Mode after taking {n} more damage.",
	},
	# ───────────────────────── Pokemon ailments & stages ─────────────────────────
	# Ailments keep their series behaviour: burn chips HP and blunts physical
	# attacks, paralysis costs you tempo, sleep and freeze cost you the turn.
	"burn": {
		"name": "Burn", "debuff": true, "decay": "tick", "color": Color(0.95, 0.45, 0.2),
		"desc": "Loses HP each turn and deals 50% less physical damage. {n} turn(s) left.",
	},
	"paralysis": {
		"name": "Paralysis", "debuff": true, "decay": "tick", "color": Color(0.95, 0.85, 0.25),
		"desc": "Speed is quartered and it may lose its action. {n} turn(s) left.",
	},
	"sleep": {
		"name": "Sleep", "debuff": true, "decay": "tick", "color": Color(0.55, 0.55, 0.8),
		"desc": "Cannot act for {n} turn(s).",
	},
	"freeze": {
		"name": "Freeze", "debuff": true, "decay": "none", "color": Color(0.6, 0.87, 0.95),
		"desc": "Cannot act until it thaws (20% each turn).",
	},
	"confusion": {
		"name": "Confusion", "debuff": true, "decay": "tick", "color": Color(0.9, 0.55, 0.85),
		"desc": "33% chance to hurt itself instead of acting. {n} turn(s) left.",
	},
	"flinch": {
		"name": "Flinch", "debuff": true, "decay": "turn_end", "color": Color(0.8, 0.75, 0.5),
		"desc": "Loses its next action.",
	},
	"leech_seed": {
		"name": "Leech Seed", "debuff": true, "decay": "tick", "color": Color(0.45, 0.8, 0.35),
		"desc": "Drains HP to its attacker each turn. {n} turn(s) left.",
	},
	"trapped": {
		"name": "Trapped", "debuff": true, "decay": "tick", "color": Color(0.7, 0.6, 0.4),
		"desc": "Takes damage each turn and cannot flee. {n} turn(s) left.",
	},
	"infatuation": {
		"name": "Infatuation", "debuff": true, "decay": "tick", "color": Color(0.95, 0.6, 0.75),
		"desc": "50% chance to lose its action. {n} turn(s) left.",
	},
	"nightmare": {
		"name": "Nightmare", "debuff": true, "decay": "tick", "color": Color(0.45, 0.35, 0.6),
		"desc": "Loses HP each turn while it sleeps. {n} turn(s) left.",
	},
	"drowsy": {
		"name": "Drowsy", "debuff": true, "decay": "tick", "color": Color(0.65, 0.65, 0.85),
		"desc": "Falls asleep when this wears off. {n} turn(s) left.",
	},
	"heal_block": {
		"name": "Heal Block", "debuff": true, "decay": "tick", "color": Color(0.8, 0.4, 0.5),
		"desc": "Cannot be healed for {n} turn(s).",
	},
	"embargo": {
		"name": "Embargo", "debuff": true, "decay": "tick", "color": Color(0.7, 0.5, 0.4),
		"desc": "Cannot use potions for {n} turn(s).",
	},
	"disable": {
		"name": "Disable", "debuff": true, "decay": "tick", "color": Color(0.6, 0.55, 0.7),
		"desc": "Loses 1 Energy at the start of its turn. {n} turn(s) left.",
	},
	"identified": {
		"name": "Identified", "debuff": true, "decay": "tick", "color": Color(0.85, 0.8, 0.6),
		"desc": "Type immunities no longer protect it. {n} turn(s) left.",
	},
	# Stat stages. Signed like Strength, capped at +-6, and multiplicative
	# (+1 is x1.5, -1 is x0.66) exactly as in the games.
	"stage_atk": {
		"name": "Attack", "debuff": false, "decay": "none", "color": Color(0.95, 0.45, 0.35),
		"desc": "Attack stage {n}: physical damage dealt is scaled.", "stage": true,
	},
	"stage_df": {
		"name": "Defense", "debuff": false, "decay": "none", "color": Color(0.7, 0.75, 0.9),
		"desc": "Defense stage {n}: physical damage taken is scaled.", "stage": true,
	},
	"stage_spa": {
		"name": "Sp. Atk", "debuff": false, "decay": "none", "color": Color(0.95, 0.55, 0.75),
		"desc": "Sp. Atk stage {n}: special damage dealt is scaled.", "stage": true,
	},
	"stage_spd": {
		"name": "Sp. Def", "debuff": false, "decay": "none", "color": Color(0.6, 0.85, 0.75),
		"desc": "Sp. Def stage {n}: special damage taken is scaled.", "stage": true,
	},
	"stage_spe": {
		"name": "Speed", "debuff": false, "decay": "none", "color": Color(0.85, 0.85, 0.45),
		"desc": "Speed stage {n}: turn order and evasion are scaled.", "stage": true,
	},
	"stage_accuracy": {
		"name": "Accuracy", "debuff": false, "decay": "none", "color": Color(0.85, 0.85, 0.7),
		"desc": "Accuracy stage {n}: its moves are more or less likely to land.",
		"stage": true,
	},
	"stage_evasion": {
		"name": "Evasion", "debuff": false, "decay": "none", "color": Color(0.75, 0.85, 0.85),
		"desc": "Evasion stage {n}: incoming moves are more or less likely to miss.",
		"stage": true,
	},

	# Internal bookkeeping — never shown to the player.
	"defensive_mode": {"name": "Defensive Mode", "debuff": false, "decay": "none",
		"color": Color(0.8, 0.8, 0.9), "desc": "In defensive mode.", "hidden": true},
	"offensive_step": {"name": "Step", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
	"angered": {"name": "Angered", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
	"hyper_counter": {"name": "Charge", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
	"stunned_next": {"name": "Stunned", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
	"hasted": {"name": "Hasted", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
	"curl_used": {"name": "Curled", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
	"pen_nib_count": {"name": "Pen Nib", "debuff": false, "decay": "none",
		"color": Color.WHITE, "desc": "", "hidden": true},
}


static func is_hidden(id: String) -> bool:
	return bool(get_def(id).get("hidden", false))


## Compact labels for the status chips under each combatant.
static var SHORT := {
	"strength": "Str", "dexterity": "Dex", "vulnerable": "Vuln", "weak": "Weak",
	"frail": "Frail", "poison": "Psn", "regen": "Regen", "thorns": "Thorns",
	"metallicize": "Metal", "plated_armor": "Armor", "artifact": "Artifact",
	"ritual": "Ritual", "curl_up": "Curl", "angry": "Angry", "spore_cloud": "Spore",
	"strength_down": "Str Down", "no_draw": "No Draw", "barricade": "Barricade",
	"demon_form": "Demon", "double_tap": "2x Tap", "feel_no_pain": "No Pain",
	"rupture": "Rupture", "combust": "Combust", "evolve": "Evolve",
	"fire_breathing": "Fire", "juggernaut": "Jugger", "dark_embrace": "Embrace",
	"envenom": "Envenom", "after_image": "Image", "thousand_cuts": "Cuts",
	"noxious_fumes": "Fumes", "infinite_blades": "Blades", "accuracy": "Accuracy",
	"painful_stabs": "Stabs", "flight": "Flight", "enrage": "Enrage",
	"asleep": "Asleep", "corpse_explosion": "Corpse", "berserk": "Berserk",
	"brutality": "Brutality", "corruption": "Corrupt", "blur": "Blur",
	"phantasmal": "Phantasm", "tools_of_the_trade": "Tools", "mayhem": "Mayhem",
	"wraith_form": "Wraith", "strength_up_end": "Str Back", "fading": "Fading",
	"curiosity": "Curious", "unawakened": "Unawake", "slow_start": "Slow",
	"mode_shift": "Shift", "minion": "Minion",
	"burn": "Burn", "paralysis": "Para", "sleep": "Sleep", "freeze": "Frozen",
	"confusion": "Confused", "flinch": "Flinch", "leech_seed": "Seeded",
	"trapped": "Trapped", "infatuation": "Infatuated", "nightmare": "Nightmare",
	"drowsy": "Drowsy", "heal_block": "No Heal", "embargo": "Embargo",
	"disable": "Disabled", "identified": "Identified",
	"stage_atk": "Atk", "stage_df": "Def", "stage_spa": "SpA", "stage_spd": "SpD",
	"stage_spe": "Spe", "stage_accuracy": "Acc", "stage_evasion": "Eva",
}


## Stat stages read as "Atk +2" rather than as a stack count, and are the only
## statuses that are meaningful at a negative value.
static func is_stage(id: String) -> bool:
	return bool(get_def(id).get("stage", false))


## The ailments that stop an actor from acting outright.
static func is_incapacitating(id: String) -> bool:
	return id in ["sleep", "freeze", "flinch"]


static func short_name(id: String) -> String:
	if SHORT.has(id):
		return SHORT[id]
	return display_name(id)


static func get_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return {"name": id.capitalize(), "debuff": false, "decay": "none",
			"color": Color(0.8, 0.8, 0.8), "desc": "Amount: {n}."}


static func display_name(id: String) -> String:
	return String(get_def(id)["name"])


static func is_debuff(id: String) -> bool:
	return bool(get_def(id)["debuff"])


static func color_of(id: String) -> Color:
	return get_def(id)["color"]


static func describe(id: String, stacks: int) -> String:
	var d := get_def(id)
	return "%s %d — %s" % [d["name"], stacks, String(d["desc"]).replace("{n}", str(stacks))]
