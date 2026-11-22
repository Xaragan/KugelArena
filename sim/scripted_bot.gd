extends RefCounted
## Hand-written players. They are NOT the rival in the game: they are sparring
## partners during training and the yardstick the net is measured against.
##
## standard() is the fixed baseline used for all reported numbers. varied() draws
## a random character (careful or reckless, item-hungry or not, strong or weak),
## so the net does not learn to beat one single behaviour.

const Sim = preload("res://sim/arena_sim.gd")

const KIND_CHASER := 0    # hunts the rival, fetches items, stays off the edge
const KIND_KEEPER := 1    # only holds the centre
const KIND_WANDERER := 2  # drifts around at random, stays off the edge

var kind := KIND_CHASER
## Turns back when it expects to be beyond this fraction of the safe radius.
var caution := 0.85
var lookahead := 0.6
## Fetches an item when its own distance is below the rival's distance times this.
## 0 = ignores items.
var item_bias := 1.2
## Seconds of rival movement it aims ahead by.
var lead := 0.4
## Standard deviation of its aiming error, in radians.
var noise := 0.12
## Thrust scale; below 1 is a deliberately weak player.
var strength := 1.0
## How strongly it steers around pillars, blocks and holes; 0 = blind to them.
var avoidance := 1.0
## Chance per decision to dodge into a rival that is close and in front of it.
var dash_rate := 0.25
var rng := RandomNumberGenerator.new()
var _wander := Vector2.ZERO
var _wander_left := 0


static func standard(bot_seed: int) -> RefCounted:
	var bot := new()
	bot.rng.seed = bot_seed
	return bot


static func varied(bot_seed: int) -> RefCounted:
	var bot := new()
	var r: RandomNumberGenerator = bot.rng
	r.seed = bot_seed
	var roll := r.randf()
	if roll < 0.08:
		bot.kind = KIND_KEEPER
	elif roll < 0.16:
		bot.kind = KIND_WANDERER
	bot.caution = r.randf_range(0.6, 0.95)
	bot.lookahead = r.randf_range(0.3, 1.0)
	bot.item_bias = 0.0 if r.randf() < 0.2 else r.randf_range(0.8, 2.5)
	bot.lead = r.randf_range(0.0, 0.8)
	bot.noise = r.randf_range(0.0, 0.5)
	bot.strength = 1.0 if r.randf() < 0.7 else r.randf_range(0.5, 1.0)
	bot.avoidance = r.randf_range(0.3, 1.5)
	bot.dash_rate = 0.0 if r.randf() < 0.25 else r.randf_range(0.05, 0.6)
	return bot


## In a free-for-all it always deals with the nearest rival. Dodges on its own:
## back towards the middle when it is sliding off, and into a rival now and then.
func act(sim: Sim, who: int) -> Vector2:
	var p := sim.pos[who]
	var v := sim.vel[who]
	var safe_radius := sim.radius - Sim.BALL_RADIUS
	var ahead := p + v * lookahead
	var target := Vector2.ZERO
	var hunting := false
	if ahead.length() > caution * safe_radius:
		# Heading for the edge: back to the centre, with a dodge if it is urgent.
		if p.length() > 0.8 * safe_radius and v.dot(p.normalized()) > 1.5:
			sim.dash(who, -p)
	elif kind == KIND_KEEPER:
		pass
	elif kind == KIND_WANDERER:
		_wander_left -= 1
		if _wander_left <= 0:
			_wander_left = rng.randi_range(3, 12)
			_wander = Vector2.from_angle(rng.randf() * TAU)
		return _wander * strength
	else:
		target = _chaser_target(sim, who)
		hunting = true
	var to_target := target - p
	if to_target.length() < 0.2 and v.length() < 0.2:
		return Vector2.ZERO
	# Steer so that the velocity turns towards the target at full speed.
	var steer := to_target.normalized() * Sim.MAX_SPEED - v
	if steer.length() < 0.05:
		return Vector2.ZERO
	var dir := steer.normalized().rotated(rng.randfn(0.0, noise))
	# Keep clear of pillars, blocks and above all holes, here and a moment ahead.
	if avoidance > 0.0:
		var away := Vector2.ZERO
		for z in sim.zone_kind.size():
			var zone := sim.zone_kind[z]
			if zone < 0 or zone > Sim.ZONE_HOLE:
				continue
			var reach := 2.2 if zone == Sim.ZONE_HOLE else 1.0
			var weight := 2.5 if zone == Sim.ZONE_HOLE else 1.0
			for spot: Vector2 in [p, ahead]:
				var off := spot - sim.zone_pos[z]
				var gap := off.length() - sim.zone_radius[z] - Sim.BALL_RADIUS
				if gap < reach:
					away += off.normalized() * (weight * (1.0 - maxf(gap, -0.5) / reach))
		if away != Vector2.ZERO:
			dir = (dir + away * avoidance).normalized()
	if hunting and dash_rate > 0.0 and sim.dash_cd[who] <= 0.0:
		var rival := sim.nearest_rival(who)
		if rival >= 0:
			var gap := p.distance_to(sim.pos[rival])
			var aimed := dir.dot((sim.pos[rival] - p).normalized()) > 0.9
			var stays_on := (p + dir * 3.0).length() < caution * safe_radius
			if aimed and stays_on and gap > 1.6 and gap < 4.5 and rng.randf() < dash_rate:
				sim.dash(who, dir)
	return dir * strength


func _chaser_target(sim: Sim, who: int) -> Vector2:
	var p := sim.pos[who]
	var rival := sim.nearest_rival(who)
	if rival < 0:
		return Vector2.ZERO
	var q := sim.pos[rival]
	if item_bias > 0.0:
		var best := -1
		var best_d := INF
		for s in sim.item_kind.size():
			if sim.item_kind[s] < 0:
				continue
			var d := p.distance_to(sim.item_pos[s])
			if d < best_d and d < q.distance_to(sim.item_pos[s]) * item_bias:
				best = s
				best_d = d
		if best >= 0:
			return sim.item_pos[best]
	# Push the rival outwards: ram when we are on its inner side, otherwise get
	# to the inner side first.
	var out_dir := q.normalized() if q.length() > 0.5 else (q - p).normalized()
	var aim := q + sim.vel[rival] * lead
	if (aim - p).normalized().dot(out_dir) > 0.2:
		return aim
	return q - out_dir * 2.0
