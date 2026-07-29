class_name PokeBalls
extends RefCounted

## The ball catalogue: what a shop stocks, what it costs, and how much each one
## actually helps.
##
## A ball is no longer a boss handout with a flat multiplier. There are four
## categories at four rarities, and most of them are *conditional* — a Net Ball
## is worth more than an Ultra Ball against a Water type and nothing at all
## against a Fire one. That is the point: stocking the bag is a decision about
## what you expect to meet, and the shop is where you make it.
##
## `multiplier()` is the only thing the capture maths asks of this file.
## Everything else — category, rarity, price, the handling numbers — is for the
## shop and for the throwing screen.

## Display order, and the headings the shop groups its stock under.
const CATEGORIES := ["standard", "specialist", "apricorn", "exotic"]

const CATEGORY_NAMES := {
	"standard": "Standard Balls",
	"specialist": "Specialist Balls",
	"apricorn": "Apricorn Balls",
	"exotic": "Exotic Balls",
}

const CATEGORY_BLURBS := {
	"standard": "Work on anything. Cost accordingly.",
	"specialist": "Cheap, and enormous against the right target.",
	"apricorn": "Hand-made. Each reads one number off the dex page.",
	"exotic": "Rare, strange, and occasionally decisive.",
}

const RARITIES := ["common", "uncommon", "rare", "legendary"]

const RARITY_COLORS := {
	# Bright enough that an affordable common ball does not read as a disabled one:
	# the theme's own disabled grey sits just below this.
	"common": Color(0.88, 0.88, 0.92),
	"uncommon": Color(0.55, 0.86, 0.72),
	"rare": Color(0.55, 0.72, 0.98),
	"legendary": Color(0.97, 0.78, 0.42),
}

## Every ball in the game.
##
##   mult   the unconditional catch multiplier
##   rule   which condition `multiplier()` tests; "" for none
##   bonus  the multiplier used *instead of* mult when the rule holds
##   sweet  how forgiving the ball's sweet spot is on the throwing screen
##   drag   how heavily it flies: >1 is sluggish, <1 is light and quick
##   curve  how much swerve it takes from a spun throw
##   join   levels the caught Pokemon arrives above the usual joining level
##   heal   whether it arrives at full health
const BALLS := {
	# ── Standard ─────────────────────────────────────────────────────────────
	"poke": {
		"name": "Poké Ball", "cat": "standard", "rarity": "common", "price": 40,
		"mult": 1.0, "rule": "", "bonus": 1.0,
		"desc": "The standard ball. Works on anything, excels at nothing.",
		"glyph": "◓", "color": Color(0.86, 0.28, 0.28),
	},
	"great": {
		"name": "Great Ball", "cat": "standard", "rarity": "common", "price": 95,
		"mult": 1.5, "rule": "", "bonus": 1.5,
		"desc": "Half again as likely to hold as a Poké Ball.",
		"glyph": "◓", "color": Color(0.30, 0.48, 0.86),
	},
	"ultra": {
		"name": "Ultra Ball", "cat": "standard", "rarity": "uncommon", "price": 190,
		"mult": 2.0, "rule": "", "bonus": 2.0,
		"desc": "Twice as likely to hold. The reliable answer to a hard catch.",
		"glyph": "◓", "color": Color(0.90, 0.78, 0.22), "sweet": 1.05,
	},
	"master": {
		"name": "Master Ball", "cat": "standard", "rarity": "legendary", "price": 1250,
		"mult": 255.0, "rule": "", "bonus": 255.0,
		"desc": "Never fails, however the throw lands.",
		"glyph": "◓", "color": Color(0.52, 0.34, 0.78), "sweet": 1.6, "drag": 0.85,
	},

	# ── Specialist ───────────────────────────────────────────────────────────
	"net": {
		"name": "Net Ball", "cat": "specialist", "rarity": "uncommon", "price": 120,
		"mult": 1.0, "rule": "type_water_bug", "bonus": 3.5,
		"desc": "3.5× against Water and Bug types. Ordinary against everything else.",
		"glyph": "◒", "color": Color(0.22, 0.62, 0.60),
	},
	"dive": {
		"name": "Dive Ball", "cat": "specialist", "rarity": "uncommon", "price": 115,
		"mult": 1.0, "rule": "type_water_ice", "bonus": 3.5,
		"desc": "3.5× against Water and Ice types.",
		"glyph": "◒", "color": Color(0.30, 0.66, 0.88), "drag": 1.15,
	},
	"dusk": {
		"name": "Dusk Ball", "cat": "specialist", "rarity": "uncommon", "price": 135,
		"mult": 1.0, "rule": "blinded", "bonus": 3.2,
		"desc": "3.2× on a target that cannot see it coming — asleep, frozen or blinded.",
		"glyph": "◓", "color": Color(0.24, 0.26, 0.34),
	},
	"quick": {
		"name": "Quick Ball", "cat": "specialist", "rarity": "rare", "price": 165,
		"mult": 0.9, "rule": "opening", "bonus": 5.0,
		"desc": "5× on the opening turn of a fight, and slightly worse after it.",
		"glyph": "◓", "color": Color(0.34, 0.72, 0.92), "drag": 0.75, "sweet": 0.95,
	},
	"timer": {
		"name": "Timer Ball", "cat": "specialist", "rarity": "uncommon", "price": 130,
		"mult": 1.0, "rule": "late", "bonus": 4.0,
		"desc": "Climbs by 0.3× a turn, to 4× in a long fight.",
		"glyph": "◓", "color": Color(0.78, 0.74, 0.66),
	},
	"nest": {
		"name": "Nest Ball", "cat": "specialist", "rarity": "common", "price": 75,
		"mult": 1.0, "rule": "low_level", "bonus": 4.0,
		"desc": "Up to 4× against something well below your own level.",
		"glyph": "◒", "color": Color(0.55, 0.76, 0.32),
	},
	"repeat": {
		"name": "Repeat Ball", "cat": "specialist", "rarity": "uncommon", "price": 125,
		"mult": 1.0, "rule": "known", "bonus": 3.5,
		"desc": "3.5× against a species already on your team.",
		"glyph": "◓", "color": Color(0.88, 0.60, 0.24),
	},
	"heal": {
		"name": "Heal Ball", "cat": "specialist", "rarity": "uncommon", "price": 130,
		"mult": 1.4, "rule": "", "bonus": 1.4,
		"desc": "1.4×, and whatever it holds arrives in perfect health.",
		"glyph": "◓", "color": Color(0.94, 0.55, 0.68), "heal": true,
	},
	"premier": {
		"name": "Premier Ball", "cat": "specialist", "rarity": "common", "price": 30,
		"mult": 1.0, "rule": "", "bonus": 1.0,
		"desc": "A Poké Ball in ceremonial white. Light, and it flies true.",
		"glyph": "◓", "color": Color(0.94, 0.94, 0.96), "sweet": 1.25, "drag": 0.8,
	},

	# ── Apricorn ─────────────────────────────────────────────────────────────
	"fast": {
		"name": "Fast Ball", "cat": "apricorn", "rarity": "rare", "price": 175,
		"mult": 1.0, "rule": "fast_species", "bonus": 4.0,
		"desc": "4× against a species with base Speed 100 or more.",
		"glyph": "◓", "color": Color(0.95, 0.80, 0.30), "drag": 0.7,
	},
	"level": {
		"name": "Level Ball", "cat": "apricorn", "rarity": "uncommon", "price": 140,
		"mult": 1.0, "rule": "out_levelled", "bonus": 4.0,
		"desc": "Up to 4× the further your own level is above the target's.",
		"glyph": "◒", "color": Color(0.86, 0.70, 0.36),
	},
	"lure": {
		"name": "Lure Ball", "cat": "apricorn", "rarity": "uncommon", "price": 120,
		"mult": 0.95, "rule": "provoked", "bonus": 3.0,
		"desc": "3× on something you have already drawn a blow out of.",
		"glyph": "◒", "color": Color(0.36, 0.62, 0.72),
	},
	"heavy": {
		"name": "Heavy Ball", "cat": "apricorn", "rarity": "uncommon", "price": 135,
		"mult": 1.0, "rule": "heavy_species", "bonus": 3.0,
		"desc": "Up to 3× on something enormous, and worse on something light.",
		"glyph": "◓", "color": Color(0.52, 0.54, 0.60), "drag": 1.35, "curve": 0.6,
	},
	"love": {
		"name": "Love Ball", "cat": "apricorn", "rarity": "rare", "price": 185,
		"mult": 1.0, "rule": "shares_type", "bonus": 4.0,
		"desc": "4× when someone on your team shares a type with the target.",
		"glyph": "◓", "color": Color(0.94, 0.52, 0.72),
	},
	"moon": {
		"name": "Moon Ball", "cat": "apricorn", "rarity": "rare", "price": 180,
		"mult": 1.0, "rule": "can_evolve", "bonus": 4.0,
		"desc": "4× against anything that still has an evolution ahead of it.",
		"glyph": "◓", "color": Color(0.42, 0.44, 0.72),
	},
	"friend": {
		"name": "Friend Ball", "cat": "apricorn", "rarity": "uncommon", "price": 150,
		"mult": 1.2, "rule": "", "bonus": 1.2,
		"desc": "1.2×, and what it holds joins a level higher for the bond.",
		"glyph": "◒", "color": Color(0.56, 0.82, 0.44), "join": 1,
	},

	# ── Exotic ───────────────────────────────────────────────────────────────
	"dream": {
		"name": "Dream Ball", "cat": "exotic", "rarity": "rare", "price": 260,
		"mult": 1.0, "rule": "asleep", "bonus": 5.0,
		"desc": "5× against a sleeping target, and nothing special against a waking one.",
		"glyph": "◓", "color": Color(0.86, 0.66, 0.94), "sweet": 1.15,
	},
	"sport": {
		"name": "Sport Ball", "cat": "exotic", "rarity": "uncommon", "price": 100,
		"mult": 1.0, "rule": "type_bug", "bonus": 4.0,
		"desc": "4× against Bug types. A contest ball, and it shows.",
		"glyph": "◒", "color": Color(0.82, 0.62, 0.30), "curve": 1.3,
	},
	"safari": {
		"name": "Safari Ball", "cat": "exotic", "rarity": "uncommon", "price": 105,
		"mult": 1.5, "rule": "", "bonus": 1.5,
		"desc": "1.5×, but the target is quicker to give up on you. Throw well.",
		"glyph": "◓", "color": Color(0.62, 0.66, 0.40), "patience": -1,
	},
	"beast": {
		"name": "Beast Ball", "cat": "exotic", "rarity": "legendary", "price": 900,
		"mult": 0.1, "rule": "legendary_target", "bonus": 5.0,
		"desc": "5× against a legendary or mythical. Almost useless against anything else.",
		"glyph": "◓", "color": Color(0.30, 0.78, 0.84), "sweet": 0.9,
	},
	"luxury": {
		"name": "Luxury Ball", "cat": "exotic", "rarity": "rare", "price": 300,
		"mult": 1.25, "rule": "", "bonus": 1.25,
		"desc": "1.25×, and what it holds arrives two levels up and in good health.",
		"glyph": "◓", "color": Color(0.24, 0.22, 0.28), "join": 2, "heal": true,
	},
	"cherish": {
		"name": "Cherish Ball", "cat": "exotic", "rarity": "legendary", "price": 750,
		"mult": 2.5, "rule": "", "bonus": 2.5,
		"desc": "2.5×, and what it holds joins at your own level, fully healed.",
		"glyph": "◓", "color": Color(0.90, 0.30, 0.36), "join": 3, "heal": true,
		"sweet": 1.2,
	},
}

## Which ball each boss hands over, as before. They get better as the run goes
## on, which is what keeps late captures viable against rising capture rates.
## Everything else in the bag is bought.
const BALL_BY_BOSS := ["poke", "great", "ultra", "master"]


static func has(id: String) -> bool:
	return BALLS.has(id)


static func get_def(id: String) -> Dictionary:
	return BALLS.get(id, BALLS["poke"])


static func display_name(id: String) -> String:
	return String(get_def(id)["name"])


static func ids() -> Array:
	var out: Array = BALLS.keys()
	out.sort()
	return out


## Catalogue order: by category, then by rarity, then by price. Anything that
## groups balls under headings wants this rather than `ids()`, or a category's
## heading turns up twice.
static func ids_ordered() -> Array:
	var out: Array = ids()
	out.sort_custom(func(a, b):
		var ca := CATEGORIES.find(category_of(String(a)))
		var cb := CATEGORIES.find(category_of(String(b)))
		if ca != cb:
			return ca < cb
		var ra := RARITIES.find(rarity_of(String(a)))
		var rb := RARITIES.find(rarity_of(String(b)))
		if ra != rb:
			return ra < rb
		return price_of(String(a)) < price_of(String(b)))
	return out


static func category_of(id: String) -> String:
	return String(get_def(id).get("cat", "standard"))


static func rarity_of(id: String) -> String:
	return String(get_def(id).get("rarity", "common"))


static func price_of(id: String) -> int:
	return int(get_def(id).get("price", 50))


static func color_of(id: String) -> Color:
	return get_def(id).get("color", Color(0.86, 0.28, 0.28))


static func rarity_color(id: String) -> Color:
	return RARITY_COLORS.get(rarity_of(id), Color.WHITE)


## Handling numbers, read by the throwing screen. Defaults are deliberately
## boring so a ball only feels different when its definition says so.
static func handling(id: String) -> Dictionary:
	var d := get_def(id)
	return {
		"sweet": float(d.get("sweet", 1.0)),
		"drag": float(d.get("drag", 1.0)),
		"curve": float(d.get("curve", 1.0)),
		"patience": int(d.get("patience", 0)),
	}


## Levels the caught Pokemon arrives above the usual joining level.
static func join_bonus(id: String) -> int:
	return int(get_def(id).get("join", 0))


static func heals_on_catch(id: String) -> bool:
	return bool(get_def(id).get("heal", false))


static func ball_for_boss(bosses_slain: int) -> String:
	var idx := clampi(bosses_slain, 0, BALL_BY_BOSS.size() - 1)
	return String(BALL_BY_BOSS[idx])


# ═══════════════════════════════ Conditions ══════════════════════════════════
## The catch multiplier this ball is worth against this target right now.
##
## `ctx` is whatever `context_for()` built. Anything missing falls back to a
## value that makes the rule fail, so a caller that only knows half the state
## still gets a sane, if pessimistic, number.
static func multiplier(id: String, ctx: Dictionary = {}) -> float:
	var d := get_def(id)
	var base := float(d.get("mult", 1.0))
	var rule := String(d.get("rule", ""))
	if rule == "":
		return base
	var bonus := float(d.get("bonus", base))
	var types: Array = ctx.get("types", [])
	var statuses: Dictionary = ctx.get("statuses", {})
	var mon: Dictionary = ctx.get("mon", {})

	match rule:
		"type_water_bug":
			return bonus if types.has("water") or types.has("bug") else base
		"type_water_ice":
			return bonus if types.has("water") or types.has("ice") else base
		"type_bug":
			return bonus if types.has("bug") else base
		"blinded":
			for sid in ["sleep", "freeze", "blind", "confusion"]:
				if statuses.has(sid):
					return bonus
			return base
		"asleep":
			return bonus if statuses.has("sleep") else base
		"opening":
			return bonus if int(ctx.get("turn", 99)) <= 1 else base
		"late":
			# Climbs a third of a multiplier a turn, to the ball's stated ceiling.
			var turn := int(ctx.get("turn", 1))
			return clampf(1.0 + 0.3 * float(turn - 1), base, bonus)
		"low_level":
			# Full value against something half your level, nothing at parity.
			var lvl := float(max(1, int(ctx.get("level", 1))))
			var mine := float(max(1, int(ctx.get("party_level", 1))))
			var gap := clampf((mine - lvl) / maxf(1.0, mine * 0.5), 0.0, 1.0)
			return lerpf(base, bonus, gap)
		"out_levelled":
			var lvl2 := float(max(1, int(ctx.get("level", 1))))
			var mine2 := float(max(1, int(ctx.get("party_level", 1))))
			var ratio := mine2 / lvl2
			if ratio >= 4.0:
				return bonus
			if ratio >= 2.0:
				return lerpf(base, bonus, 0.66)
			if ratio > 1.0:
				return lerpf(base, bonus, 0.33)
			return base
		"known":
			return bonus if bool(ctx.get("known", false)) else base
		"provoked":
			return bonus if bool(ctx.get("provoked", false)) else base
		"shares_type":
			return bonus if bool(ctx.get("shares_type", false)) else base
		"can_evolve":
			return bonus if bool(ctx.get("can_evolve", false)) else base
		"fast_species":
			var spe := int((mon.get("stats", {}) as Dictionary).get("spe", 0))
			return bonus if spe >= 100 else base
		"heavy_species":
			# Hectograms, as the dex stores them: 3000 is 300 kg.
			var w := int(mon.get("weight", 0))
			if w >= 3000:
				return bonus
			if w >= 1000:
				return lerpf(base, bonus, 0.6)
			if w <= 200:
				return base * 0.7
			return base
		"legendary_target":
			if bool(mon.get("legendary", false)) or bool(mon.get("mythical", false)):
				return bonus
			return base
	return base


## Everything the rules above can ask about one capture attempt, gathered in one
## place so the odds a screen *shows* and the odds a throw *rolls* cannot drift
## apart.
##
## `party` is an Array[PartyMember]; pass [] out of a run.
static func context_for(mon: Dictionary, hp: int, max_hp: int, statuses: Dictionary,
		level: int, party_level: int, turn: int, provoked: bool,
		party: Array = []) -> Dictionary:
	var types: Array = mon.get("types", [])
	var known := false
	var shares := false
	for m in party:
		var member = m
		if member == null:
			continue
		var species := String(member.species_name()) if member.has_method("species_name") \
				else ""
		if species == String(mon.get("name", "")):
			known = true
		var their := PokeData.mon(species)
		if not their.is_empty():
			for t in their.get("types", []):
				if types.has(t):
					shares = true
	return {
		"mon": mon,
		"types": types,
		"statuses": statuses,
		"hp": hp,
		"max_hp": max(1, max_hp),
		"hp_ratio": clampf(float(hp) / float(max(1, max_hp)), 0.0, 1.0),
		"level": level,
		"party_level": party_level,
		"turn": turn,
		"provoked": provoked,
		"known": known,
		"shares_type": shares,
		"can_evolve": not PokeData.evolutions_of(String(mon.get("name", ""))).is_empty(),
	}


## Wording for what a ball's condition is worth right now, for a shop row or the
## throwing screen. "" when the ball has no condition to report.
static func condition_note(id: String, ctx: Dictionary) -> String:
	var d := get_def(id)
	if String(d.get("rule", "")) == "":
		return ""
	var live := multiplier(id, ctx)
	var flat := float(d.get("mult", 1.0))
	if live > flat * 1.05:
		return "condition met — %.1f×" % live
	if live < flat * 0.95:
		return "working against you — %.2f×" % live
	return "condition unmet — %.1f×" % live


# ═════════════════════════════════ Shop stock ════════════════════════════════
## Balls a shop offers. Deeper in the run the shelf drifts toward the better
## categories, so an Act 4 merchant is where a Beast Ball turns up rather than a
## fifth rack of Poké Balls.
##
## `progress` is Run.progress(), 0 at the first floor and 1 at the last.
static func shop_stock(rng: RandomNumberGenerator, progress: float,
		count: int = 4) -> Array:
	var weights := {
		"common": lerpf(4.0, 1.0, progress),
		"uncommon": lerpf(3.0, 3.0, progress),
		"rare": lerpf(0.8, 2.6, progress),
		"legendary": lerpf(0.05, 0.7, progress),
	}
	var out: Array = []
	var taken: Array = []
	var guard := 0
	while out.size() < count and guard < 200:
		guard += 1
		var rarity := _weighted_rarity(rng, weights)
		var pool: Array = []
		for id in pool_for(rarity):
			if not taken.has(id):
				pool.append(id)
		if pool.is_empty():
			continue
		var pick := String(pool[rng.randi_range(0, pool.size() - 1)])
		taken.append(pick)
		# A ball is a consumable, so the shelf holds a few of the cheap ones and
		# exactly one of anything precious.
		var stack := 1
		match rarity_of(pick):
			"common": stack = rng.randi_range(2, 4)
			"uncommon": stack = rng.randi_range(1, 3)
			"rare": stack = 1
		var price := int(round(price_of(pick) * rng.randf_range(0.9, 1.12)))
		out.append({"id": pick, "price": price, "stock": stack, "sold": 0})
	# Grouped by category so the shelf reads as a shelf.
	out.sort_custom(func(a, b):
		var ca := CATEGORIES.find(category_of(String(a["id"])))
		var cb := CATEGORIES.find(category_of(String(b["id"])))
		if ca != cb:
			return ca < cb
		return price_of(String(a["id"])) < price_of(String(b["id"])))
	return out


static func pool_for(rarity: String) -> Array:
	var out: Array = []
	for id in BALLS:
		if rarity_of(String(id)) == rarity:
			out.append(String(id))
	out.sort()
	return out


static func _weighted_rarity(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for r in RARITIES:
		total += float(weights.get(r, 0.0))
	if total <= 0.0:
		return "common"
	var roll := rng.randf() * total
	for r in RARITIES:
		roll -= float(weights.get(r, 0.0))
		if roll <= 0.0:
			return String(r)
	return "common"
