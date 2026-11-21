extends RefCounted
## Pure game rules of KugelArena: balls on a disc, items, falling off the edge.
## Two balls are a duel; three to eight are a free-for-all where the last ball on
## the disc wins.
##
## No nodes, no drawing, no input. The game window and the training both drive this
## same class with fixed 1/60 s steps, so the net is trained on exactly the rules the
## human plays. Units are abstract "arena units"; the window scales them to pixels.

# --- Field and movement -------------------------------------------------------
const ARENA_RADIUS := 10.0
const BALL_RADIUS := 0.6
const MAX_BALLS := 8
const TICKS_PER_SECOND := 60
const DT := 1.0 / 60.0
## Top speed without items. The disc is 20 units wide; at 2.0 a ball would cross
## it in 10 s. It was raised twice after watching rounds (x1.8, then x1.5).
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

# --- Collisions ---------------------------------------------------------------
const RESTITUTION := 0.9
## Every hit is amplified by this, so collisions throw balls around more than
## billiard physics would.
const KNOCKBACK := 2.3
## A ball that falls within this many ticks of being hit counts as a knockout
## for whoever hit it last.
const KNOCKOUT_TICKS := 120

# --- Items --------------------------------------------------------------------
const ITEM_POWER := 0   # your hits push twice as hard
const ITEM_SPEED := 1   # more thrust and top speed
const ITEM_ANCHOR := 2  # you are pushed far less
const ITEM_FREEZE := 3  # everyone else's thrust drops
const ITEM_SHOCK := 4   # instant blast that throws the others away from you
const ITEM_KINDS := 5
const ITEM_NAMES: Array[String] = ["Power", "Speed", "Anchor", "Freeze", "Shock"]
const ITEM_RADIUS := 0.45
const ITEM_FIRST_SPAWN := 2.0
const ITEM_SPAWN_INTERVAL := 3.5   # in a duel; more balls get items faster
const ITEM_SPAWN_RADIUS := 0.75    # fraction of the disc radius

# Timed effects on a ball. FX_FROZEN is put on the others by whoever picked FREEZE.
const FX_POWER := 0
const FX_SPEED := 1
const FX_ANCHOR := 2
const FX_FROZEN := 3
const FX_COUNT := 4
const FX_DURATION: Array[float] = [6.0, 6.0, 6.0, 4.0]
const POWER_FACTOR := 2.0
const SPEED_FACTOR := 1.6
const ANCHOR_FACTOR := 0.35
const FREEZE_FACTOR := 0.4
const SHOCK_IMPULSE := 5.0
const SHOCK_RANGE := 8.0

# --- Result -------------------------------------------------------------------
## `result` is the index of the winning ball, or one of these.
const RUNNING := -1
const DRAW := -2     # the last balls touched the edge in the same tick
const TIMEOUT := -3  # only when max_ticks > 0
const WIN_0 := 0
const WIN_1 := 1

## Number of inputs observe() writes.
const OBS_SIZE := 47

var n := 2                                # number of balls in this game
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var thrust := PackedVector2Array()
var alive := PackedByteArray()            # 1 while the ball is on the disc
var place := PackedInt32Array()           # 0 while alive, then 1 (winner) .. n
var knockouts := PackedInt32Array()       # rivals this ball pushed off
var fx := PackedFloat32Array()            # [who * FX_COUNT + effect] = seconds left
var item_kind := PackedInt32Array()       # -1 = empty slot
var item_pos := PackedVector2Array()
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
	# More balls, more items: 2 slots in a duel, up to 4, and they come faster.
	var slots := clampi(1 + n / 2, 2, 4)
	item_kind.resize(slots)
	item_kind.fill(-1)
	item_pos.resize(slots)
	_spawn_interval = maxf(1.2, ITEM_SPAWN_INTERVAL * 2.0 / n)
	tick = 0
	radius = ARENA_RADIUS
	max_ticks = int(round(time_limit_seconds * TICKS_PER_SECOND))
	result = RUNNING
	_spawn_timer = ITEM_FIRST_SPAWN
	events.clear()


func seconds() -> float:
	return tick * DT


## Thrust direction for one ball; longer than 1 is cut to 1.
func set_thrust(who: int, t: Vector2) -> void:
	var l := t.length()
	if l > 1.0:
		t /= l
	thrust[who] = t


func step() -> void:
	if result != RUNNING:
		return
	tick += 1
	for i in n:
		if alive[i] == 0:
			continue
		var power := THRUST
		if fx[i * FX_COUNT + FX_SPEED] > 0.0:
			power *= SPEED_FACTOR
		if fx[i * FX_COUNT + FX_FROZEN] > 0.0:
			power *= FREEZE_FACTOR
		var v := vel[i]
		v += (thrust[i] * power - v * DRAG) * DT
		vel[i] = v
		pos[i] += v * DT
	if tick > SHRINK_START * TICKS_PER_SECOND and radius > MIN_RADIUS:
		radius = maxf(MIN_RADIUS, radius - SHRINK_RATE * DT)
		for s in item_kind.size():
			if item_kind[s] >= 0 and item_pos[s].length() > radius - ITEM_RADIUS:
				item_kind[s] = -1  # the ground under the item is gone
	for a in n:
		if alive[a] == 0:
			continue
		for b in range(a + 1, n):
			if alive[b] == 1:
				_collide(a, b)
	_pick_items()
	for k in fx.size():
		if fx[k] > 0.0:
			fx[k] = maxf(0.0, fx[k] - DT)
	_spawn_items()
	_check_end()


func _push_factor(who: int) -> float:
	return POWER_FACTOR if fx[who * FX_COUNT + FX_POWER] > 0.0 else 1.0


func _receive_factor(who: int) -> float:
	return ANCHOR_FACTOR if fx[who * FX_COUNT + FX_ANCHOR] > 0.0 else 1.0


func _collide(a: int, b: int) -> void:
	var d := pos[b] - pos[a]
	var dist := d.length()
	var min_dist := BALL_RADIUS * 2.0
	if dist >= min_dist:
		return
	var normal := d / dist if dist > 0.0001 else Vector2.RIGHT
	# Separate the balls so they never overlap.
	var overlap := (min_dist - dist) * 0.5
	pos[a] -= normal * overlap
	pos[b] += normal * overlap
	var closing := (vel[a] - vel[b]).dot(normal)
	if closing <= 0.0:
		return
	var impulse := (1.0 + RESTITUTION) * 0.5 * closing * KNOCKBACK
	vel[a] -= normal * (impulse * _push_factor(b) * _receive_factor(a))
	vel[b] += normal * (impulse * _push_factor(a) * _receive_factor(b))
	_last_hit_by[a] = b
	_last_hit_by[b] = a
	_last_hit_tick[a] = tick
	_last_hit_tick[b] = tick
	if record_events:
		events.append({"type": "hit", "at": (pos[a] + pos[b]) * 0.5, "strength": impulse})


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
					var falloff := 1.0 - dist / SHOCK_RANGE
					vel[other] += d / dist * (SHOCK_IMPULSE * falloff * _receive_factor(other))
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
	# A few tries to find a spot that is not right under a ball.
	var p := Vector2.ZERO
	for attempt in 6:
		var angle := rng.randf() * TAU
		var spawn_r := sqrt(rng.randf()) * radius * ITEM_SPAWN_RADIUS
		p = Vector2(cos(angle), sin(angle)) * spawn_r
		var free := true
		for i in n:
			if alive[i] == 1 and p.distance_to(pos[i]) <= 2.0:
				free = false
				break
		if free:
			break
	item_pos[slot] = p
	item_kind[slot] = rng.randi_range(0, ITEM_KINDS - 1)
	if record_events:
		events.append({"type": "spawn", "kind": item_kind[slot], "at": p})


func _check_end() -> void:
	var limit := radius - BALL_RADIUS
	var fallen := 0
	for i in n:
		if alive[i] == 1 and pos[i].length() >= limit:
			fallen += 1
	if fallen > 0:
		# Balls that fall in the same tick share the better place.
		var their_place := alive_count - fallen + 1
		for i in n:
			if alive[i] == 1 and pos[i].length() >= limit:
				alive[i] = 0
				place[i] = their_place
				var by := -1
				if tick - _last_hit_tick[i] <= KNOCKOUT_TICKS and _last_hit_by[i] >= 0:
					by = _last_hit_by[i]
					knockouts[by] += 1
				if record_events:
					events.append({"type": "fall", "who": i, "by": by, "at": pos[i]})
		alive_count -= fallen
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


func _observe_item(slot: int, at: int, p: Vector2, ex: Vector2, ey: Vector2,
		out: PackedFloat32Array) -> void:
	if slot < 0:
		return
	var d := item_pos[slot] - p
	out[at] = 1.0
	out[at + 1] = d.dot(ex) / ARENA_RADIUS
	out[at + 2] = d.dot(ey) / ARENA_RADIUS
	out[at + 3 + item_kind[slot]] = 1.0
