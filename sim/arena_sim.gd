extends RefCounted
## Pure game rules of KugelArena: balls on a disc with obstacles and zones, items,
## a dodge, falling off the edge. Two balls are a duel; three to eight are a
## free-for-all where the last ball on the disc wins.
##
## No nodes, no drawing, no input. The game window and the training both drive this
## same class with fixed 1/60 s steps, so the net is trained on exactly the rules the
## human plays. Units are abstract "arena units"; the window scales them to pixels.

# --- Field and movement -------------------------------------------------------
## Three times the area of the first disc (radius 10).
const ARENA_RADIUS := 17.5
const BALL_RADIUS := 0.6
const MAX_BALLS := 8
const TICKS_PER_SECOND := 60
const DT := 1.0 / 60.0
## Top speed without items.
const MAX_SPEED := 5.4
## Linear drag. Thrust is chosen so that the terminal speed is MAX_SPEED.
## High drag = tight control: top speed is reached in about half a second.
const DRAG := 2.2
const THRUST := MAX_SPEED * DRAG
## After SHRINK_START seconds the disc shrinks steadily until nothing is left
## SHRINK_SECONDS later, so every round ends. Set SHRINK_RATE to 0 for a disc
## that never changes.
const SHRINK_START := 15.0
const SHRINK_SECONDS := 60.0
const SHRINK_RATE := ARENA_RADIUS / SHRINK_SECONDS   # units per second
const MIN_RADIUS := 0.0
## Controllers (net, scripted bots) choose a new thrust every DECISION_TICKS ticks.
const DECISION_TICKS := 6

# --- Dodge --------------------------------------------------------------------
## A dodge adds DASH_SPEED in the chosen direction at once and ends a skid; then
## it is unavailable for DASH_COOLDOWN seconds.
const DASH_SPEED := 7.5
const DASH_COOLDOWN := 3.0

# --- Collisions ---------------------------------------------------------------
## Collisions are real physics: momentum is conserved, and RESTITUTION is the
## share of the closing speed the balls separate with (1 = perfectly bouncy).
## Two equal balls swap their speeds along the line of the hit; a heavier ball
## pushes a lighter one away and is itself slowed less.
const RESTITUTION := 0.9
## A hard hit knocks a ball into a skid: for a moment it has little grip, so it
## slides on instead of stopping, and its own thrust does little. How long
## depends on how hard it was hit: SKID_SECONDS for a change of speed of
## MAX_SPEED or more, proportionally less for lighter hits.
const SKID_SECONDS := 1.2
const SKID_GRIP := 0.12
## A ball that falls within this many ticks of being hit counts as a knockout
## for whoever hit it last.
const KNOCKOUT_TICKS := 120

# --- Obstacles and zones ------------------------------------------------------
## Every round lays out a new set, rotationally symmetric so every ball starts
## with the same surroundings. They vanish when the shrinking disc reaches them.
const ZONE_PILLAR := 0  # solid, bouncy
const ZONE_BLOCK := 1   # big solid area nobody can enter, hardly bouncy
const ZONE_HOLE := 2    # trap: a ball whose centre gets in falls through and is out
const ZONE_ICE := 3     # patch with little grip: you slide
const ZONE_MUD := 4     # patch that slows you down
const ZONE_WIND := 5    # area with a steady wind in one direction
const ZONE_KINDS := 6
const ZONE_NAMES: Array[String] = ["Pillar", "Block", "Hole", "Ice", "Mud", "Wind"]
## How many of each kind a duel gets, roughly (more balls get proportionally more).
const ZONE_TARGET: Array[int] = [6, 2, 4, 2, 2, 2]
const ZONE_MIN_RADIUS: Array[float] = [0.8, 2.0, 1.2, 2.4, 2.4, 2.2]
const ZONE_MAX_RADIUS: Array[float] = [1.2, 2.8, 1.6, 3.2, 3.2, 3.0]
const PILLAR_BOUNCE := 0.8
const BLOCK_BOUNCE := 0.3
const ICE_GRIP := 0.25
const MUD_DRAG := 2.5
const WIND_ACCEL := 6.0

# --- Items --------------------------------------------------------------------
const ITEM_POWER := 0   # your ball gets heavy: it pushes harder and is pushed less
const ITEM_SPEED := 1   # more thrust and top speed
const ITEM_ANCHOR := 2  # grip: you slide far less after a hit, ice does not bother you
const ITEM_FREEZE := 3  # everyone else's thrust drops
const ITEM_SHOCK := 4   # instant blast that throws the others away from you
const ITEM_KINDS := 5
const ITEM_NAMES: Array[String] = ["Power", "Speed", "Anchor", "Freeze", "Shock"]
const ITEM_RADIUS := 0.6
const ITEM_FIRST_SPAWN := 2.0
const ITEM_SPAWN_INTERVAL := 2.3   # in a duel; more balls get items faster
const ITEM_SPAWN_RADIUS := 0.75    # fraction of the disc radius

# Timed effects on a ball. FX_FROZEN is put on the others by whoever picked FREEZE.
const FX_POWER := 0
const FX_SPEED := 1
const FX_ANCHOR := 2
const FX_FROZEN := 3
const FX_COUNT := 4
const FX_DURATION: Array[float] = [5.0, 5.0, 5.0, 3.0]
## Power makes the ball this many times as heavy. Its thrust grows with it, so
## it is as nimble as before.
const POWER_MASS := 1.7
const SPEED_FACTOR := 1.35
## Anchor multiplies the ball's grip on the disc (drag and thrust alike): same
## top speed, but it stops and turns this many times as fast. Skids are cut to
## ANCHOR_SKID of their length.
const ANCHOR_GRIP := 1.8
const ANCHOR_SKID := 0.4
const FREEZE_FACTOR := 0.6
const SHOCK_IMPULSE := 4.0
const SHOCK_RANGE := 6.0

# --- Result -------------------------------------------------------------------
## `result` is the index of the winning ball, or one of these.
const RUNNING := -1
const DRAW := -2     # the last balls fell in the same tick
const TIMEOUT := -3  # only when max_ticks > 0
const WIN_0 := 0
const WIN_1 := 1

## Number of inputs observe() writes.
const OBS_SIZE := 87
const OBS_ZONES := 3        # the net sees its three nearest zones
const OBS_PER_ZONE := 12

var n := 2                                # number of balls in this game
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var thrust := PackedVector2Array()
var alive := PackedByteArray()            # 1 while the ball is on the disc
var place := PackedInt32Array()           # 0 while alive, then 1 (winner) .. n
var knockouts := PackedInt32Array()       # rivals this ball pushed off
var fx := PackedFloat32Array()            # [who * FX_COUNT + effect] = seconds left
var skid := PackedFloat32Array()          # seconds of skidding left, per ball
var dash_cd := PackedFloat32Array()       # seconds until the dodge is ready again
var item_kind := PackedInt32Array()       # -1 = empty slot
var item_pos := PackedVector2Array()
var zone_kind := PackedInt32Array()       # -1 = gone (the disc shrank past it)
var zone_pos := PackedVector2Array()
var zone_radius := PackedFloat32Array()
var zone_dir := PackedVector2Array()      # wind direction; zero for other kinds
var radius := ARENA_RADIUS                # current radius of the disc
var tick := 0
var max_ticks := 0                        # 0 = no time limit
var result := RUNNING
var alive_count := 2
var rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0
var _spawn_interval := ITEM_SPAWN_INTERVAL
var _last_hit_by := PackedInt32Array()
var _last_hit_tick := PackedInt32Array()

## The window sets this to get a list of things that happened (for flashes and
## texts). Training leaves it off.
var record_events := false
var events: Array = []


## Starts a game with `balls` balls (2 = duel). They start evenly spread on a
## circle halfway out; in a duel ball 0 is on the left, ball 1 on the right.
func reset(game_seed: int, time_limit_seconds: float = 0.0, balls: int = 2) -> void:
	rng.seed = game_seed
	n = clampi(balls, 2, MAX_BALLS)
	pos.resize(n)
	vel.resize(n)
	thrust.resize(n)
	alive.resize(n)
	place.resize(n)
	knockouts.resize(n)
	_last_hit_by.resize(n)
	_last_hit_tick.resize(n)
	for i in n:
		pos[i] = Vector2.from_angle(PI + i * TAU / n) * (ARENA_RADIUS * 0.5)
		vel[i] = Vector2.ZERO
		thrust[i] = Vector2.ZERO
		alive[i] = 1
		place[i] = 0
		knockouts[i] = 0
		_last_hit_by[i] = -1
		_last_hit_tick[i] = -100000
	alive_count = n
	fx.resize(n * FX_COUNT)
	fx.fill(0.0)
	skid.resize(n)
	skid.fill(0.0)
	dash_cd.resize(n)
	dash_cd.fill(0.0)
	# More balls, more items: 3 slots in a duel, up to 6, and they come faster.
	var slots := clampi(2 + n / 2, 3, 6)
	item_kind.resize(slots)
	item_kind.fill(-1)
	item_pos.resize(slots)
	_spawn_interval = maxf(0.8, ITEM_SPAWN_INTERVAL * 2.0 / n)
	tick = 0
	radius = ARENA_RADIUS
	max_ticks = int(round(time_limit_seconds * TICKS_PER_SECOND))
	result = RUNNING
	_spawn_timer = ITEM_FIRST_SPAWN
	events.clear()
	_lay_out_zones()


## Places the obstacles and zones of this round. The layout repeats around the
## centre as often as needed for every ball to see the same surroundings.
func _lay_out_zones() -> void:
	zone_kind.clear()
	zone_pos.clear()
	zone_radius.clear()
	zone_dir.clear()
	var symmetry := n if n <= 4 or n % 2 == 1 else n / 2
	for kind in ZONE_KINDS:
		var copies := maxi(1, int(round(float(ZONE_TARGET[kind]) / symmetry)))
		for c in copies:
			for attempt in 80:
				var size := rng.randf_range(ZONE_MIN_RADIUS[kind], ZONE_MAX_RADIUS[kind])
				var at := Vector2.from_angle(rng.randf() * TAU) * \
					rng.randf_range(0.12, 0.85) * ARENA_RADIUS
				var wind := Vector2.from_angle(rng.randf() * TAU) if kind == ZONE_WIND else Vector2.ZERO
				if not _zone_fits(at, size, kind, symmetry):
					continue
				for k in symmetry:
					var turn := k * TAU / symmetry
					zone_kind.append(kind)
					zone_pos.append(at.rotated(turn))
					zone_radius.append(size)
					zone_dir.append(wind.rotated(turn))
				break


func _zone_fits(at: Vector2, size: float, kind: int, symmetry: int) -> bool:
	if at.length() + size > ARENA_RADIUS - 1.0:
		return false
	# Things that block or kill keep their distance from each other and from the
	# starting positions; patches and wind only must not overlap anything.
	var solid := kind <= ZONE_HOLE
	var gap := 1.5 if solid else 0.3
	var start_gap := 3.0 if solid else 0.8
	# Its own copies must not overlap each other.
	if symmetry > 1 and at.distance_to(at.rotated(TAU / symmetry)) < size * 2.0 + gap:
		return false
	for k in symmetry:
		var p := at.rotated(k * TAU / symmetry)
		for i in n:
			if p.distance_to(pos[i]) < size + start_gap:
				return false
		for z in zone_kind.size():
			# Two patches may overlap (wind over ice is fine), just not coincide.
			var needed := size + zone_radius[z] + gap
			if not solid and zone_kind[z] >= ZONE_ICE:
				needed = maxf(size, zone_radius[z])
			if p.distance_to(zone_pos[z]) < needed:
				return false
	return true


func seconds() -> float:
	return tick * DT


## Thrust direction for one ball; longer than 1 is cut to 1.
func set_thrust(who: int, t: Vector2) -> void:
	var l := t.length()
	if l > 1.0:
		t /= l
	thrust[who] = t


## Dodge: a burst of speed in `direction` (or, if that is zero, the way the ball
## is already moving). Returns false while the dodge is cooling down.
func dash(who: int, direction: Vector2) -> bool:
	if result != RUNNING or alive[who] == 0 or dash_cd[who] > 0.0:
		return false
	var d := direction
	if d.length() < 0.1:
		d = vel[who]
	if d.length() < 0.1:
		return false
	vel[who] += d.normalized() * DASH_SPEED
	dash_cd[who] = DASH_COOLDOWN
	skid[who] = 0.0
	if record_events:
		events.append({"type": "dash", "who": who, "at": pos[who]})
	return true


func step() -> void:
	if result != RUNNING:
		return
	tick += 1
	var zones := zone_kind.size()
	for i in n:
		if alive[i] == 0:
			continue
		# Accelerations, so a heavy (Power) ball steers like a light one.
		var power := THRUST
		var drag := DRAG
		var anchored := fx[i * FX_COUNT + FX_ANCHOR] > 0.0
		if anchored:
			power *= ANCHOR_GRIP
			drag *= ANCHOR_GRIP
		if skid[i] > 0.0:
			power *= SKID_GRIP
			drag *= SKID_GRIP
			skid[i] = maxf(0.0, skid[i] - DT)
		if fx[i * FX_COUNT + FX_SPEED] > 0.0:
			power *= SPEED_FACTOR
		if fx[i * FX_COUNT + FX_FROZEN] > 0.0:
			power *= FREEZE_FACTOR
		# What the ball is standing on.
		var wind := Vector2.ZERO
		var p := pos[i]
		for z in zones:
			var kind := zone_kind[z]
			if kind < ZONE_ICE:
				continue
			if p.distance_squared_to(zone_pos[z]) > zone_radius[z] * zone_radius[z]:
				continue
			if kind == ZONE_ICE:
				if not anchored:
					power *= ICE_GRIP
					drag *= ICE_GRIP
			elif kind == ZONE_MUD:
				drag *= MUD_DRAG
			else:
				wind += zone_dir[z] * WIND_ACCEL
		if dash_cd[i] > 0.0:
			dash_cd[i] = maxf(0.0, dash_cd[i] - DT)
		var v := vel[i]
		v += (thrust[i] * power + wind - v * drag) * DT
		vel[i] = v
		pos[i] = p + v * DT
	if tick > SHRINK_START * TICKS_PER_SECOND and radius > MIN_RADIUS:
		radius = maxf(MIN_RADIUS, radius - SHRINK_RATE * DT)
		for s in item_kind.size():
			if item_kind[s] >= 0 and item_pos[s].length() > radius - ITEM_RADIUS:
				item_kind[s] = -1  # the ground under the item is gone
		for z in zones:
			if zone_kind[z] >= 0 and zone_pos[z].length() > radius:
				zone_kind[z] = -1
	for a in n:
		if alive[a] == 0:
			continue
		for b in range(a + 1, n):
			if alive[b] == 1:
				_collide(a, b)
	for i in n:
		if alive[i] == 1:
			_hit_solids(i)
	_pick_items()
	for k in fx.size():
		if fx[k] > 0.0:
			fx[k] = maxf(0.0, fx[k] - DT)
	_spawn_items()
	_check_end()


func _mass(who: int) -> float:
	return POWER_MASS if fx[who * FX_COUNT + FX_POWER] > 0.0 else 1.0


func _collide(a: int, b: int) -> void:
	var d := pos[b] - pos[a]
	var dist := d.length()
	var min_dist := BALL_RADIUS * 2.0
	if dist >= min_dist:
		return
	var normal := d / dist if dist > 0.0001 else Vector2.RIGHT
	var inv_a := 1.0 / _mass(a)
	var inv_b := 1.0 / _mass(b)
	# Separate the balls so they never overlap; the lighter one gives way more.
	var overlap := (min_dist - dist) / (inv_a + inv_b)
	pos[a] -= normal * (overlap * inv_a)
	pos[b] += normal * (overlap * inv_b)
	var closing := (vel[a] - vel[b]).dot(normal)
	if closing <= 0.0:
		return
	# The same impulse acts on both balls, in opposite directions.
	var impulse := (1.0 + RESTITUTION) * closing / (inv_a + inv_b)
	vel[a] -= normal * (impulse * inv_a)
	vel[b] += normal * (impulse * inv_b)
	_knock(a, impulse * inv_a)
	_knock(b, impulse * inv_b)
	_last_hit_by[a] = b
	_last_hit_by[b] = a
	_last_hit_tick[a] = tick
	_last_hit_tick[b] = tick
	if record_events:
		events.append({"type": "hit", "at": (pos[a] + pos[b]) * 0.5, "strength": impulse})


## Keeps a ball out of pillars and blocks and bounces it off them.
func _hit_solids(who: int) -> void:
	for z in zone_kind.size():
		var kind := zone_kind[z]
		if kind != ZONE_PILLAR and kind != ZONE_BLOCK:
			continue
		var d := pos[who] - zone_pos[z]
		var min_dist := zone_radius[z] + BALL_RADIUS
		var dist := d.length()
		if dist >= min_dist:
			continue
		var normal := d / dist if dist > 0.0001 else Vector2.RIGHT
		pos[who] = zone_pos[z] + normal * min_dist
		var inward := vel[who].dot(normal)
		if inward < 0.0:
			var bounce := PILLAR_BOUNCE if kind == ZONE_PILLAR else BLOCK_BOUNCE
			vel[who] -= normal * ((1.0 + bounce) * inward)
			if record_events and inward < -1.5:
				events.append({"type": "hit", "at": pos[who] - normal * BALL_RADIUS,
					"strength": -inward})


## Starts or extends a skid after the ball's speed changed by `speed_change`.
func _knock(who: int, speed_change: float) -> void:
	var seconds_of_skid := SKID_SECONDS * minf(1.0, speed_change / MAX_SPEED)
	if fx[who * FX_COUNT + FX_ANCHOR] > 0.0:
		seconds_of_skid *= ANCHOR_SKID
	skid[who] = maxf(skid[who], seconds_of_skid)


func _pick_items() -> void:
	var reach := BALL_RADIUS + ITEM_RADIUS
	for s in item_kind.size():
		var kind := item_kind[s]
		if kind < 0:
			continue
		var who := -1
		var best := reach
		for i in n:
			if alive[i] == 0:
				continue
			var d := pos[i].distance_to(item_pos[s])
			if d <= best:
				best = d
				who = i
		if who < 0:
			continue
		item_kind[s] = -1
		_apply_item(who, kind)
		if record_events:
			events.append({"type": "pickup", "who": who, "kind": kind, "at": item_pos[s]})


func _apply_item(who: int, kind: int) -> void:
	match kind:
		ITEM_POWER:
			fx[who * FX_COUNT + FX_POWER] = FX_DURATION[FX_POWER]
		ITEM_SPEED:
			fx[who * FX_COUNT + FX_SPEED] = FX_DURATION[FX_SPEED]
		ITEM_ANCHOR:
			fx[who * FX_COUNT + FX_ANCHOR] = FX_DURATION[FX_ANCHOR]
		ITEM_FREEZE:
			for other in n:
				if other != who and alive[other] == 1:
					fx[other * FX_COUNT + FX_FROZEN] = FX_DURATION[FX_FROZEN]
		ITEM_SHOCK:
			for other in n:
				if other == who or alive[other] == 0:
					continue
				var d := pos[other] - pos[who]
				var dist := d.length()
				if dist < SHOCK_RANGE and dist > 0.0001:
					var push := SHOCK_IMPULSE * (1.0 - dist / SHOCK_RANGE) / _mass(other)
					vel[other] += d / dist * push
					_knock(other, push)
					_last_hit_by[other] = who
					_last_hit_tick[other] = tick


func _spawn_items() -> void:
	_spawn_timer -= DT
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _spawn_interval
	var slot := -1
	for s in item_kind.size():
		if item_kind[s] < 0:
			slot = s
			break
	if slot < 0:
		return
	# A few tries to find a spot that is not under a ball, in a wall or in a hole.
	var p := Vector2.ZERO
	var found := false
	for attempt in 10:
		var angle := rng.randf() * TAU
		var spawn_r := sqrt(rng.randf()) * radius * ITEM_SPAWN_RADIUS
		p = Vector2(cos(angle), sin(angle)) * spawn_r
		var free := true
		for i in n:
			if alive[i] == 1 and p.distance_to(pos[i]) <= 2.0:
				free = false
				break
		if free:
			for z in zone_kind.size():
				if zone_kind[z] >= 0 and zone_kind[z] <= ZONE_HOLE \
						and p.distance_to(zone_pos[z]) < zone_radius[z] + ITEM_RADIUS + 0.3:
					free = false
					break
		if free:
			found = true
			break
	if not found:
		return
	item_pos[slot] = p
	item_kind[slot] = rng.randi_range(0, ITEM_KINDS - 1)
	if record_events:
		events.append({"type": "spawn", "kind": item_kind[slot], "at": p})


func _is_out(who: int, limit: float) -> bool:
	if pos[who].length() >= limit:
		return true
	for z in zone_kind.size():
		if zone_kind[z] == ZONE_HOLE and pos[who].distance_to(zone_pos[z]) < zone_radius[z]:
			return true
	return false


func _check_end() -> void:
	var limit := radius - BALL_RADIUS
	var out := []
	for i in n:
		if alive[i] == 1 and _is_out(i, limit):
			out.append(i)
	if not out.is_empty():
		# Balls that fall in the same tick share the better place.
		var their_place := alive_count - out.size() + 1
		for i: int in out:
			alive[i] = 0
			place[i] = their_place
			var by := -1
			if tick - _last_hit_tick[i] <= KNOCKOUT_TICKS and _last_hit_by[i] >= 0:
				by = _last_hit_by[i]
				knockouts[by] += 1
			if record_events:
				events.append({"type": "fall", "who": i, "by": by, "at": pos[i]})
		alive_count -= out.size()
	if alive_count == 1:
		for i in n:
			if alive[i] == 1:
				place[i] = 1
				result = i
	elif alive_count == 0:
		result = DRAW
	elif max_ticks > 0 and tick >= max_ticks:
		result = TIMEOUT


## The nearest ball still on the disc other than `who`, or -1.
func nearest_rival(who: int) -> int:
	var best := -1
	var best_d := INF
	for i in n:
		if i == who or alive[i] == 0:
			continue
		var d := pos[who].distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## Unit vector from `who` to its nearest rival: the x axis of the frame the net sees.
func frame_x(who: int) -> Vector2:
	var rival := nearest_rival(who)
	if rival < 0:
		return Vector2.RIGHT
	var d := pos[rival] - pos[who]
	var l := d.length()
	return d / l if l > 0.0001 else Vector2.RIGHT


## Writes what one ball knows into `out` (size OBS_SIZE).
##
## Everything is expressed in a frame that is centred on the ball itself, with x
## pointing at the nearest rival and y a quarter turn to the left. The disc looks
## the same from every angle, so the net never has to learn the same thing once
## per direction. In a duel the inputs about further rivals are simply 0.
## The README lists the inputs.
func observe(who: int, out: PackedFloat32Array) -> void:
	out.fill(0.0)
	# The three nearest rivals, nearest first.
	var near := [-1, -1, -1]
	var near_d := [INF, INF, INF]
	var p := pos[who]
	for i in n:
		if i == who or alive[i] == 0:
			continue
		var d := p.distance_squared_to(pos[i])
		for slot in 3:
			if d < near_d[slot]:
				for back in range(2, slot, -1):
					near[back] = near[back - 1]
					near_d[back] = near_d[back - 1]
				near[slot] = i
				near_d[slot] = d
				break
	var other: int = near[0]
	if other < 0:
		return
	var q := pos[other]
	var ex := (q - p).normalized() if p.distance_squared_to(q) > 0.00000001 else Vector2.RIGHT
	var ey := Vector2(-ex.y, ex.x)
	var inv_r := 1.0 / ARENA_RADIUS
	var inv_v := 1.0 / MAX_SPEED
	var limit := radius - BALL_RADIUS
	out[0] = p.distance_to(q) * inv_r * 0.5
	# Where the centre of the disc is, seen from the ball.
	out[1] = -p.dot(ex) * inv_r
	out[2] = -p.dot(ey) * inv_r
	out[3] = vel[who].dot(ex) * inv_v
	out[4] = vel[who].dot(ey) * inv_v
	out[5] = vel[other].dot(ex) * inv_v
	out[6] = vel[other].dot(ey) * inv_v
	# Room left before the edge, for both balls.
	out[7] = (limit - p.length()) * inv_r
	out[8] = (limit - q.length()) * inv_r
	for k in FX_COUNT:
		out[9 + k] = fx[who * FX_COUNT + k] / FX_DURATION[k]
		out[13 + k] = fx[other * FX_COUNT + k] / FX_DURATION[k]
	# The two nearest items.
	var first := -1
	var second := -1
	var first_d := INF
	var second_d := INF
	for s in item_kind.size():
		if item_kind[s] < 0:
			continue
		var d := p.distance_squared_to(item_pos[s])
		if d < first_d:
			second = first
			second_d = first_d
			first = s
			first_d = d
		elif d < second_d:
			second = s
			second_d = d
	_observe_item(first, 17, p, ex, ey, out)
	_observe_item(second, 25, p, ex, ey, out)
	out[33] = radius * inv_r
	# Free-for-all: how many rivals are left, and the second and third nearest.
	out[34] = (alive_count - 1) / float(MAX_BALLS - 1)
	for slot in 2:
		var r: int = near[slot + 1]
		if r < 0:
			continue
		var at := 35 + slot * 6
		var d := pos[r] - p
		out[at] = 1.0
		out[at + 1] = d.dot(ex) * inv_r
		out[at + 2] = d.dot(ey) * inv_r
		out[at + 3] = vel[r].dot(ex) * inv_v
		out[at + 4] = vel[r].dot(ey) * inv_v
		out[at + 5] = (limit - pos[r].length()) * inv_r
	# Skidding: how long this ball and the nearest rival still have little grip.
	out[47] = skid[who] / SKID_SECONDS
	out[48] = skid[other] / SKID_SECONDS
	# Dodge: how long until it is ready again, own and the nearest rival's.
	out[49] = dash_cd[who] / DASH_COOLDOWN
	out[50] = dash_cd[other] / DASH_COOLDOWN
	# The three nearest obstacles or zones, by the distance to their rim.
	var zone := [-1, -1, -1]
	var zone_d := [INF, INF, INF]
	for z in zone_kind.size():
		if zone_kind[z] < 0:
			continue
		var d := p.distance_to(zone_pos[z]) - zone_radius[z]
		for slot in OBS_ZONES:
			if d < zone_d[slot]:
				for back in range(OBS_ZONES - 1, slot, -1):
					zone[back] = zone[back - 1]
					zone_d[back] = zone_d[back - 1]
				zone[slot] = z
				zone_d[slot] = d
				break
	for slot in OBS_ZONES:
		var z: int = zone[slot]
		if z < 0:
			continue
		var at := 51 + slot * OBS_PER_ZONE
		var d := zone_pos[z] - p
		out[at] = 1.0
		out[at + 1] = d.dot(ex) * inv_r
		out[at + 2] = d.dot(ey) * inv_r
		out[at + 3] = zone_radius[z] / 3.0
		out[at + 4 + zone_kind[z]] = 1.0
		out[at + 10] = zone_dir[z].dot(ex)
		out[at + 11] = zone_dir[z].dot(ey)


func _observe_item(slot: int, at: int, p: Vector2, ex: Vector2, ey: Vector2,
		out: PackedFloat32Array) -> void:
	if slot < 0:
		return
	var d := item_pos[slot] - p
	out[at] = 1.0
	out[at + 1] = d.dot(ex) / ARENA_RADIUS
	out[at + 2] = d.dot(ey) / ARENA_RADIUS
	out[at + 3 + item_kind[slot]] = 1.0
