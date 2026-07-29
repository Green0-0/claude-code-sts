class_name PokeMotion
extends RefCounted

## How a Pokemon moves while you are trying to hit it with a ball.
##
## Every type has its own movement algorithm, expressed as weights over a small
## set of primitives — sway, bob, leap, jolt, aerial swerve, orbit, teleport,
## burrow, jitter — plus a dodge choreography. A Bug type jolts and leaps; a
## Flying type swerves aerially; a Rock type holds still and then shifts its
## whole weight. A dual type is the *blend* of two profiles, weighted toward the
## primary, so a Bug/Flying really does jolt and leap and then swerve.
##
## Resistance (see PokeCapture) is the other half of it. It does not merely slow
## the motion down: amplitudes shrink, leaps stop clearing the ground, dodges
## stop being attempted, and the whole phase begins to stutter and sag as the
## thing tires. Wearing a target down is therefore legible in how it moves, which
## is the point — the capture screen should reward the fight that came before it.
##
## Sampling is a pure function of (profile, time, seed, resistance): there is no
## state and no RNG, so a paused screen resumes mid-stride and a replay of the
## same fight looks the same.

## The primitive weights a profile is made of. Anything absent is 0, except the
## handful of baselines below.
const DEFAULTS := {
	"speed": 1.0,
	"amp": Vector2(78.0, 40.0),
	"sway": 1.0,
	"bob": 0.6,
	"swerve": 0.0,
	"spiral": 0.0,
	"hop": 0.0,
	"hop_every": 1.6,
	"jolt": 0.0,
	"jolt_every": 1.1,
	"sink": 0.0,
	"sink_every": 3.2,
	"blink": 0.0,
	"blink_every": 2.6,
	"jitter": 0.0,
	"pulse": 0.05,
	"tilt": 0.05,
	"heavy": 0.35,
	"dodge": 0.3,
	"style": "sidestep",
	"note": "keeps an easy rhythm",
}

## One profile per type. Only the weights that matter are listed; the rest come
## from DEFAULTS.
const PROFILES := {
	"normal": {
		"speed": 0.95, "sway": 1.0, "bob": 0.7, "hop": 0.35, "hop_every": 2.2,
		"dodge": 0.30, "style": "sidestep",
		"note": "keeps an easy, watchful rhythm",
	},
	"fighting": {
		"speed": 1.25, "amp": Vector2(84.0, 30.0), "sway": 0.6, "bob": 1.1,
		"jolt": 0.75, "jolt_every": 0.8, "hop": 0.3, "hop_every": 1.5,
		"pulse": 0.09, "tilt": 0.08, "heavy": 0.25,
		"dodge": 0.55, "style": "sidestep",
		"note": "bobs on its feet and lunges",
	},
	"flying": {
		"speed": 1.15, "amp": Vector2(120.0, 74.0), "sway": 0.35, "bob": 0.3,
		"swerve": 1.0, "hop": 0.0, "heavy": 0.12, "tilt": 0.16, "pulse": 0.06,
		"dodge": 0.6, "style": "soar",
		"note": "swerves aerially",
	},
	"poison": {
		"speed": 0.8, "amp": Vector2(70.0, 32.0), "sway": 1.0, "bob": 0.5,
		"jitter": 0.5, "jolt": 0.3, "jolt_every": 1.6, "pulse": 0.11,
		"heavy": 0.45,
		"dodge": 0.3, "style": "sidestep",
		"note": "oozes sideways in fits",
	},
	"ground": {
		"speed": 0.75, "amp": Vector2(72.0, 26.0), "sway": 0.85, "bob": 0.35,
		"sink": 0.9, "sink_every": 2.8, "heavy": 0.7, "tilt": 0.03,
		"dodge": 0.45, "style": "burrow",
		"note": "hunkers low and dips away underfoot",
	},
	"rock": {
		"speed": 0.55, "amp": Vector2(66.0, 20.0), "sway": 0.3, "bob": 0.2,
		"jolt": 0.95, "jolt_every": 1.9, "heavy": 0.85, "pulse": 0.03,
		"tilt": 0.02,
		"dodge": 0.2, "style": "brace",
		"note": "holds still, then shifts its whole weight",
	},
	"bug": {
		"speed": 1.5, "amp": Vector2(92.0, 46.0), "sway": 0.4, "bob": 0.3,
		"jolt": 0.9, "jolt_every": 0.55, "hop": 0.85, "hop_every": 0.9,
		"jitter": 0.35, "heavy": 0.2, "tilt": 0.12,
		"dodge": 0.5, "style": "hop",
		"note": "jolts and leaps",
	},
	"ghost": {
		"speed": 0.85, "amp": Vector2(104.0, 56.0), "sway": 0.7, "bob": 0.8,
		"blink": 0.85, "blink_every": 1.9, "heavy": 0.05, "pulse": 0.13,
		"dodge": 0.65, "style": "fade",
		"note": "fades out and reappears elsewhere",
	},
	"steel": {
		"speed": 0.7, "amp": Vector2(62.0, 22.0), "sway": 0.75, "bob": 0.25,
		"jolt": 0.45, "jolt_every": 1.4, "heavy": 0.75, "pulse": 0.02,
		"tilt": 0.02,
		"dodge": 0.25, "style": "brace",
		"note": "moves in stiff, measured steps",
	},
	"fire": {
		"speed": 1.45, "amp": Vector2(86.0, 52.0), "sway": 0.55, "bob": 0.9,
		"jitter": 0.8, "hop": 0.45, "hop_every": 1.0, "pulse": 0.14,
		"heavy": 0.15,
		"dodge": 0.45, "style": "hop",
		"note": "flickers upward in quick bursts",
	},
	"water": {
		"speed": 0.95, "amp": Vector2(110.0, 48.0), "sway": 1.15, "bob": 0.75,
		"swerve": 0.45, "heavy": 0.3, "pulse": 0.07, "tilt": 0.09,
		"dodge": 0.4, "style": "slide",
		"note": "swims in long smooth waves",
	},
	"grass": {
		"speed": 0.7, "amp": Vector2(68.0, 34.0), "sway": 1.1, "bob": 0.6,
		"hop": 0.55, "hop_every": 2.6, "heavy": 0.4, "pulse": 0.08,
		"tilt": 0.11,
		"dodge": 0.3, "style": "sidestep",
		"note": "sways like something rooted, then springs",
	},
	"electric": {
		"speed": 1.9, "amp": Vector2(112.0, 44.0), "sway": 0.3, "bob": 0.3,
		"jolt": 1.05, "jolt_every": 0.34, "jitter": 0.6, "heavy": 0.1,
		"tilt": 0.14, "pulse": 0.06,
		"dodge": 0.7, "style": "blink",
		"note": "zigzags almost too fast to follow",
	},
	"psychic": {
		"speed": 0.75, "amp": Vector2(96.0, 58.0), "sway": 0.6, "bob": 0.7,
		"spiral": 0.6, "blink": 0.5, "blink_every": 2.9, "heavy": 0.08,
		"pulse": 0.12, "tilt": 0.07,
		"dodge": 0.6, "style": "blink",
		"note": "drifts, then blinks a body-length away",
	},
	"ice": {
		"speed": 0.9, "amp": Vector2(104.0, 26.0), "sway": 1.2, "bob": 0.2,
		"jolt": 0.35, "jolt_every": 2.1, "heavy": 0.5, "pulse": 0.04,
		"tilt": 0.05,
		"dodge": 0.45, "style": "slide",
		"note": "glides and stops dead",
	},
	"dragon": {
		"speed": 0.95, "amp": Vector2(126.0, 62.0), "sway": 0.8, "bob": 0.5,
		"swerve": 0.75, "spiral": 0.35, "heavy": 0.35, "pulse": 0.09,
		"tilt": 0.15,
		"dodge": 0.55, "style": "soar",
		"note": "carves wide, powerful arcs",
	},
	"dark": {
		"speed": 1.05, "amp": Vector2(114.0, 40.0), "sway": 1.0, "bob": 0.4,
		"blink": 0.4, "blink_every": 2.2, "sink": 0.35, "sink_every": 3.6,
		"heavy": 0.25, "pulse": 0.07,
		"dodge": 0.6, "style": "fade",
		"note": "lurks at the edges and slips into shadow",
	},
	"fairy": {
		"speed": 1.2, "amp": Vector2(82.0, 50.0), "sway": 0.5, "bob": 0.6,
		"spiral": 0.85, "hop": 0.5, "hop_every": 1.2, "heavy": 0.12,
		"pulse": 0.11, "tilt": 0.1,
		"dodge": 0.5, "style": "hop",
		"note": "bounces through little orbits",
	},
}

## How heavily the primary type dominates a dual-type blend.
const PRIMARY_WEIGHT := 0.62


static func profile_for_type(t: String) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	for k in PROFILES.get(t, {}):
		out[k] = PROFILES[t][k]
	return out


## The movement algorithm for a typing. One type is its own profile; two are
## blended, weighted toward the primary, so both readings survive in the motion.
static func for_types(types: Array) -> Dictionary:
	if types.is_empty():
		return profile_for_type("normal")
	var primary := profile_for_type(String(types[0]))
	if types.size() == 1:
		return primary
	var secondary := profile_for_type(String(types[1]))
	return blend(primary, secondary, PRIMARY_WEIGHT)


## Weighted average of two profiles. `w` is how much of `a` survives.
static func blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for k in a:
		var va = a[k]
		var vb = b.get(k, va)
		match typeof(va):
			TYPE_FLOAT, TYPE_INT:
				out[k] = lerpf(float(vb), float(va), w)
			TYPE_VECTOR2:
				out[k] = (vb as Vector2).lerp(va as Vector2, w)
			_:
				# Choreography and flavour cannot be averaged, so the louder half
				# of the blend supplies them.
				out[k] = va if w >= 0.5 else vb
	# The dodge style is the primary's, but the secondary's is kept so the screen
	# can alternate between the two — which is what makes a blend read as a blend.
	out["style"] = String(a.get("style", "sidestep")) if w >= 0.5 \
			else String(b.get("style", "sidestep"))
	out["style_alt"] = String(b.get("style", "sidestep")) if w >= 0.5 \
			else String(a.get("style", "sidestep"))
	var na := String(a.get("note", ""))
	var nb := String(b.get("note", ""))
	if na != "" and nb != "" and na != nb:
		out["note"] = "%s, then %s" % [na, nb] if w >= 0.5 else "%s, then %s" % [nb, na]
	return out


# ═════════════════════════════════ Sampling ══════════════════════════════════
## Where the target is at time `t`, and what shape it is in.
##
## Returns {offset: Vector2, scale: float, rotation: float, alpha: float}. The
## offset is relative to the arena's centre, in pixels.
##
## `resistance` is 0..1 from PokeCapture.resistance(): 1 is a fresh, healthy,
## hard-to-catch target and 0 is one that can barely keep itself off the floor.
static func sample(profile: Dictionary, t: float, seed_value: int,
		resistance: float) -> Dictionary:
	var r := clampf(resistance, 0.0, 1.0)
	var enc := 1.0 - r                     # how spent it is
	var amp: Vector2 = profile.get("amp", DEFAULTS["amp"])
	amp *= 0.28 + 0.72 * r
	var speed := float(profile.get("speed", 1.0)) * (0.40 + 0.60 * r)

	# Phase offsets, so two of the same species on screen are not in lockstep.
	var s := float(seed_value % 997) * 0.0631
	# An encumbered thing does not simply move slower: its phase creeps and
	# stalls, so the motion falters rather than being played back at half rate.
	var tw := t * speed + enc * 0.35 * sin(t * 0.6 + s)

	var off := Vector2.ZERO
	var alpha := 1.0
	var extra_tilt := 0.0

	# ── The baseline: everything sways and breathes. ─────────────────────────
	off.x += sin(tw + s) * amp.x * float(profile.get("sway", 1.0))
	off.y += sin(tw * 1.7 + s * 1.7) * amp.y * float(profile.get("bob", 0.6))

	# ── Aerial swerve: a figure eight, wide and unhurried. ───────────────────
	var swerve := float(profile.get("swerve", 0.0))
	if swerve > 0.0:
		off.x += sin(tw * 0.8 + s * 0.4) * amp.x * swerve * 1.15
		off.y += sin(tw * 1.6 + s * 0.8) * amp.y * swerve * 1.35
		extra_tilt += cos(tw * 0.8 + s * 0.4) * swerve * 0.22

	# ── Orbit: a circle that breathes wider and tighter. ────────────────────
	var spiral := float(profile.get("spiral", 0.0))
	if spiral > 0.0:
		var radius := 0.6 + 0.4 * sin(tw * 0.31 + s)
		off.x += cos(tw * 1.25 + s) * amp.x * spiral * radius
		off.y += sin(tw * 1.25 + s) * amp.y * spiral * radius

	# ── Leaps: parabolic hops that travel while airborne. ───────────────────
	var hop := float(profile.get("hop", 0.0))
	if hop > 0.0:
		var every: float = maxf(0.2, float(profile.get("hop_every", 1.6)))
		var raw := tw / every
		var idx := floorf(raw)
		var ph := raw - idx
		var dir := _hash(idx, 7) * 2.0 - 1.0
		var arc := 4.0 * ph * (1.0 - ph)
		# A tiring thing still tries to jump; it just stops leaving the ground.
		off.y -= arc * amp.y * hop * 2.4 * (0.25 + 0.75 * r)
		off.x += dir * (ph - 0.5) * amp.x * hop * 1.1
		extra_tilt += dir * arc * hop * 0.2

	# ── Jolts: snap to a new station, hold it, snap again. ──────────────────
	var jolt := float(profile.get("jolt", 0.0))
	if jolt > 0.0:
		var jevery: float = maxf(0.1, float(profile.get("jolt_every", 1.1)))
		var jraw := tw / jevery
		var jidx := floorf(jraw)
		var jph := jraw - jidx
		# Cubic ease so it arrives suddenly and then sits still.
		var settle := 1.0 - pow(1.0 - clampf(jph * 5.0, 0.0, 1.0), 3.0)
		var to := Vector2(_hash(jidx, 11) * 2.0 - 1.0, _hash(jidx, 13) * 2.0 - 1.0)
		var from := Vector2(_hash(jidx - 1.0, 11) * 2.0 - 1.0,
				_hash(jidx - 1.0, 13) * 2.0 - 1.0)
		var j := from.lerp(to, settle)
		off += Vector2(j.x * amp.x, j.y * amp.y * 0.55) * jolt
		extra_tilt += j.x * jolt * 0.18

	# ── Burrow: drops out of sight and comes back up somewhere else. ────────
	var sink := float(profile.get("sink", 0.0))
	if sink > 0.0:
		var severy: float = maxf(0.5, float(profile.get("sink_every", 3.2)))
		var sraw := tw / severy
		var sidx := floorf(sraw)
		var sph := sraw - sidx
		# Down for the first third of the cycle, up for the rest.
		var dip: float = clampf(sin(sph * PI * 3.0), 0.0, 1.0) if sph < 0.34 else 0.0
		if dip > 0.0:
			off.y += dip * amp.y * sink * 2.6
			off.x += (_hash(sidx, 17) * 2.0 - 1.0) * amp.x * sink * dip
			alpha *= 1.0 - dip * 0.55 * sink

	# ── Teleport: gone, then a body-length away. ────────────────────────────
	var blink := float(profile.get("blink", 0.0))
	if blink > 0.0:
		var bevery: float = maxf(0.4, float(profile.get("blink_every", 2.6)))
		var braw := tw / bevery
		var bidx := floorf(braw)
		var bph := braw - bidx
		off.x += (_hash(bidx, 19) * 2.0 - 1.0) * amp.x * blink * 1.2
		off.y += (_hash(bidx, 23) * 2.0 - 1.0) * amp.y * blink * 1.1
		# Fades through the seam between one station and the next.
		var edge: float = minf(bph, 1.0 - bph)
		alpha *= clampf(0.18 + edge * 8.0, 0.18, 1.0)

	# ── Jitter: a fast, steppy tremor. ─────────────────────────────────────
	var jitter := float(profile.get("jitter", 0.0))
	if jitter > 0.0:
		var step := floorf(tw * 9.0)
		off.x += (_hash(step, 29) * 2.0 - 1.0) * amp.x * jitter * 0.32
		off.y += (_hash(step, 31) * 2.0 - 1.0) * amp.y * jitter * 0.32

	# ── Encumbrance: a spent thing sags, and sags further if it is heavy. ──
	var heavy := float(profile.get("heavy", 0.35))
	off.y += enc * enc * 34.0 * (0.4 + heavy)
	off *= 1.0 - enc * 0.18 * heavy

	var pulse := float(profile.get("pulse", 0.05))
	# Breathing gets shallower as it tires, then heaves as it labours.
	var breath := sin(tw * 2.1 + s * 2.3) * pulse * (0.35 + 0.65 * r)
	breath += sin(t * 1.1 + s) * enc * 0.045
	var tilt := float(profile.get("tilt", 0.05))
	var rot := sin(tw * 1.3 + s * 0.7) * tilt * (0.3 + 0.7 * r) + extra_tilt * tilt * 4.0
	rot += enc * 0.12 * sin(t * 0.5 + s)     # a weary list to one side

	return {
		"offset": off,
		"scale": 1.0 + breath,
		"rotation": rot,
		"alpha": clampf(alpha, 0.0, 1.0),
	}


# ═══════════════════════════════ Getting out of the way ══════════════════════
## How likely this thing is to dodge a ball it has seen coming. A target on its
## last legs barely tries.
static func dodge_chance(profile: Dictionary, resistance: float) -> float:
	var base := float(profile.get("dodge", 0.3))
	return clampf(base * (0.12 + 0.88 * clampf(resistance, 0.0, 1.0)), 0.0, 0.85)


## The choreography of one dodge: where it goes, how long it takes, and how it
## looks doing it. Blended typings alternate between their two styles, which is
## what stops a Bug/Flying from only ever hopping.
static func dodge_plan(profile: Dictionary, rng: RandomNumberGenerator,
		resistance: float, attempt: int = 0) -> Dictionary:
	var r := clampf(resistance, 0.0, 1.0)
	var amp: Vector2 = profile.get("amp", DEFAULTS["amp"])
	var style := String(profile.get("style", "sidestep"))
	var alt := String(profile.get("style_alt", ""))
	if alt != "" and attempt % 2 == 1:
		style = alt
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var reach := 0.35 + 0.65 * r
	var plan := {"style": style, "offset": Vector2.ZERO, "time": 0.22,
			"alpha": 1.0, "scale": 1.0, "note": "dodges"}

	match style:
		"sidestep":
			plan["offset"] = Vector2(side * amp.x * 1.15 * reach, 0.0)
			plan["time"] = 0.18
			plan["note"] = "sidesteps"
		"hop":
			plan["offset"] = Vector2(side * amp.x * 0.7 * reach, -amp.y * 1.8 * reach)
			plan["time"] = 0.22
			plan["note"] = "springs clear"
		"soar":
			plan["offset"] = Vector2(side * amp.x * 1.3 * reach, -amp.y * 1.5 * reach)
			plan["time"] = 0.3
			plan["note"] = "banks away"
		"fade":
			plan["offset"] = Vector2(side * amp.x * 0.9 * reach, amp.y * 0.3 * reach)
			plan["alpha"] = 0.05
			plan["time"] = 0.16
			plan["note"] = "melts out of the way"
		"blink":
			plan["offset"] = Vector2(side * amp.x * 1.5 * reach,
					(rng.randf() * 2.0 - 1.0) * amp.y * reach)
			plan["alpha"] = 0.0
			plan["time"] = 0.08
			plan["note"] = "is simply somewhere else"
		"burrow":
			plan["offset"] = Vector2(side * amp.x * 0.6 * reach, amp.y * 2.4 * reach)
			plan["alpha"] = 0.15
			plan["time"] = 0.2
			plan["note"] = "drops underground"
		"slide":
			plan["offset"] = Vector2(side * amp.x * 1.6 * reach, 0.0)
			plan["time"] = 0.34
			plan["note"] = "glides aside"
		"brace":
			# It does not move much; it just gets harder to knock over.
			plan["offset"] = Vector2(side * amp.x * 0.3 * reach, 0.0)
			plan["scale"] = 1.12
			plan["time"] = 0.14
			plan["note"] = "braces and takes it side-on"
	return plan


## One line describing how this thing is behaving, for the capture screen's
## caption. Reads off the blended note and the state it is in.
static func describe(types: Array, resistance: float) -> String:
	var profile := for_types(types)
	var note := String(profile.get("note", "moves"))
	var out := note.substr(0, 1).to_upper() + note.substr(1)
	var r := clampf(resistance, 0.0, 1.0)
	if r >= 0.85:
		return out + " — and it is fresh."
	if r >= 0.6:
		return out + "."
	if r >= 0.35:
		return out + " — slower than it was."
	if r >= 0.15:
		return out + " — and it is flagging badly."
	return out + " — barely."


# ═══════════════════════════════════ Noise ═══════════════════════════════════
## Deterministic 0..1 hash. Used instead of an RNG so the motion is a pure
## function of time and can be sampled out of order.
static func _hash(i: float, salt: int) -> float:
	var x := i * 127.1 + float(salt) * 311.7
	return float(fposmod(sin(x) * 43758.5453, 1.0))
