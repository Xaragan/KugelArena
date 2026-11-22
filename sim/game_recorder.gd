extends RefCounted
## Records one game as data: one row every decision step (10 per second) with
## everything on the field, the hits, pickups and falls, who played and how it
## ended, plus a few numbers describing how each ball behaved.
##
## Games are appended to .jsonl files, one JSON object per line. Every process
## writes its own file, so two writers never share one.
##
## A row holds, for a game with n balls and m item slots:
##   per ball (n times):  x, y, vx, vy, thrust_x, thrust_y, on_disc (1/0)
##   disc_radius
##   per item slot (m times):  kind (-1 = none), x, y
##   per ball (n times):  power, speed, anchor, frozen (seconds left)

const Sim = preload("res://sim/arena_sim.gd")

const FORMAT := "kugelarena-game-4"
const PER_BALL := 7

var _rows: Array = []
var _events: Array = []
var _seed := 0
var _players: Array = []
var _zones: Array = []   # the round's obstacles and zones: [kind, x, y, radius, wind x, wind y]


static func col_radius(n: int) -> int:
	return n * PER_BALL


static func col_items(n: int) -> int:
	return n * PER_BALL + 1


static func col_fx(n: int, item_slots: int) -> int:
	return n * PER_BALL + 1 + item_slots * 3


## `players` names the balls in order.
func begin(game_seed: int, players: Array) -> void:
	_rows = []
	_events = []
	_seed = game_seed
	_players = players.duplicate()
	_zones = []


## Call once after sim.reset(): stores the round's obstacles and zones.
func note_layout(sim: Sim) -> void:
	_zones = []
	for z in sim.zone_kind.size():
		_zones.append([sim.zone_kind[z], snappedf(sim.zone_pos[z].x, 0.001),
			snappedf(sim.zone_pos[z].y, 0.001), snappedf(sim.zone_radius[z], 0.001),
			snappedf(sim.zone_dir[z].x, 0.001), snappedf(sim.zone_dir[z].y, 0.001)])


## Call once per decision step, after the thrusts are set.
func capture(sim: Sim) -> void:
	var row := []
	for i in sim.n:
		for v: Vector2 in [sim.pos[i], sim.vel[i], sim.thrust[i]]:
			row.append(snappedf(v.x, 0.001))
			row.append(snappedf(v.y, 0.001))
		row.append(int(sim.alive[i]))
	row.append(snappedf(sim.radius, 0.001))
	for s in sim.item_kind.size():
		row.append(sim.item_kind[s])  # -1 = no item; kinds as in ArenaSim.ITEM_NAMES
		row.append(snappedf(sim.item_pos[s].x, 0.001) if sim.item_kind[s] >= 0 else 0.0)
		row.append(snappedf(sim.item_pos[s].y, 0.001) if sim.item_kind[s] >= 0 else 0.0)
	for k in sim.fx.size():
		row.append(snappedf(sim.fx[k], 0.01))
	_rows.append(row)


## Call after every sim.step() while sim.record_events is on, before the caller
## clears sim.events. Keeps [seconds, "hit", x, y, strength],
## [seconds, "pickup", who, item kind] and [seconds, "fall", who, pushed by or -1].
func note_events(sim: Sim) -> void:
	for e: Dictionary in sim.events:
		var t := snappedf(sim.seconds(), 0.01)
		match e["type"]:
			"hit":
				var at: Vector2 = e["at"]
				_events.append([t, "hit", snappedf(at.x, 0.01), snappedf(at.y, 0.01),
					snappedf(e["strength"], 0.01)])
			"pickup":
				_events.append([t, "pickup", e["who"], e["kind"]])
			"fall":
				_events.append([t, "fall", e["who"], e["by"]])
			"dash":
				_events.append([t, "dash", e["who"]])


func finish(sim: Sim) -> Dictionary:
	var result := "unfinished"
	if sim.result >= 0:
		result = "win_%d" % sim.result
	elif sim.result == Sim.DRAW:
		result = "draw"
	elif sim.result == Sim.TIMEOUT:
		result = "timeout"
	var stats := _stats(sim)
	return {
		"format": FORMAT,
		"recorded": Time.get_datetime_string_from_system(false, true),
		"seed": _seed,
		"n": sim.n,
		"item_slots": sim.item_kind.size(),
		"zones": _zones,
		"players": _players,
		"result": result,
		"places": Array(sim.place),
		"seconds": snappedf(sim.seconds(), 0.01),
		"rows_per_second": Sim.TICKS_PER_SECOND / Sim.DECISION_TICKS,
		"stats": stats,
		"interest": _interest(stats, sim.seconds()),
		"item_names": Sim.ITEM_NAMES,
		"events": _events,
		"rows": _rows,
	}


## Numbers describing the game. Per-ball entries are lists, one value per ball,
## measured while the ball was on the disc.
##   hits          collisions in the game
##   pickups       items collected
##   dashes        dodges used
##   knockouts     rivals pushed off
##   lead_changes  how often the ball with the most room to the edge changed
##   escapes       times a ball was within 0.8 of the edge and got 2.0 away again
##   centre_dist   mean distance from the centre, as a share of the disc radius
##   speed         mean speed as a share of the top speed
##   chase         mean of thrust towards the nearest rival: +1 hunts, -1 runs away
func _stats(sim: Sim) -> Dictionary:
	var n := sim.n
	var hits := 0
	var pickups := []
	var escapes := []
	var danger := []
	var dist := []
	var speed := []
	var chase := []
	var rows_alive := []
	var dashes := []
	for i in n:
		dashes.append(0)
		pickups.append(0)
		escapes.append(0)
		danger.append(false)
		dist.append(0.0)
		speed.append(0.0)
		chase.append(0.0)
		rows_alive.append(0)
	for e: Array in _events:
		if e[1] == "hit":
			hits += 1
		elif e[1] == "pickup":
			pickups[int(e[2])] += 1
		elif e[1] == "dash":
			dashes[int(e[2])] += 1
	var lead_changes := 0
	var leader := -1
	var c_radius := col_radius(n)
	for row: Array in _rows:
		var limit: float = float(row[c_radius]) - Sim.BALL_RADIUS
		var p := []
		var room := []
		for i in n:
			p.append(Vector2(row[i * PER_BALL], row[i * PER_BALL + 1]))
			room.append(limit - (p[i] as Vector2).length())
		# The leader changes when another ball has clearly more room (by 1.0).
		var best := -1
		for i in n:
			if int(row[i * PER_BALL + 6]) == 1 and (best < 0 or room[i] > room[best]):
				best = i
		if best >= 0 and best != leader:
			var leader_gone := leader < 0 or int(row[leader * PER_BALL + 6]) == 0
			if leader_gone or room[best] - room[leader] > 1.0:
				if leader >= 0:
					lead_changes += 1
				leader = best
		for i in n:
			if int(row[i * PER_BALL + 6]) == 0:
				continue
			rows_alive[i] += 1
			if room[i] < 0.8:
				danger[i] = true
			elif danger[i] and room[i] > 2.0:
				danger[i] = false
				escapes[i] += 1
			dist[i] += (p[i] as Vector2).length() / maxf(float(row[c_radius]), 0.5)
			speed[i] += Vector2(row[i * PER_BALL + 2], row[i * PER_BALL + 3]).length() / Sim.MAX_SPEED
			var nearest := -1
			for j in n:
				if j != i and int(row[j * PER_BALL + 6]) == 1 and (nearest < 0 or
						(p[i] as Vector2).distance_squared_to(p[j]) <
						(p[i] as Vector2).distance_squared_to(p[nearest])):
					nearest = j
			if nearest >= 0:
				var to_rival: Vector2 = ((p[nearest] as Vector2) - (p[i] as Vector2)).normalized()
				chase[i] += Vector2(row[i * PER_BALL + 4], row[i * PER_BALL + 5]).dot(to_rival)
	for i in n:
		var count := maxf(1.0, rows_alive[i])
		dist[i] = snappedf(dist[i] / count, 0.001)
		speed[i] = snappedf(speed[i] / count, 0.001)
		chase[i] = snappedf(chase[i] / count, 0.001)
	return {"hits": hits, "pickups": pickups, "dashes": dashes, "knockouts": Array(sim.knockouts),
		"lead_changes": lead_changes, "escapes": escapes, "centre_dist": dist, "speed": speed,
		"chase": chase, "final_radius": snappedf(sim.radius, 0.01)}


## How much there is to see in a game: a fight with hits, changes of who is
## winning and escapes from the edge, decided by a push rather than by the disc
## shrinking away. Used to pick the highlights of a training run.
func _interest(stats: Dictionary, seconds: float) -> float:
	var score := minf(float(stats["hits"]), 30.0)
	score += 4.0 * minf(float(stats["lead_changes"]), 8.0)
	for i in (stats["escapes"] as Array).size():
		score += 6.0 * float(stats["escapes"][i])
		score += 1.5 * float(stats["pickups"][i])
		score += 3.0 * float(stats["knockouts"][i])
	if float(stats["final_radius"]) > 4.0:
		score += 8.0
	if seconds >= 12.0 and seconds <= 50.0:
		score += 5.0
	return snappedf(score, 0.1)


## The highlights of a run: the most interesting free-for-all, the most
## interesting net-against-net duel and the most interesting duel against the bot.
static func pick_highlights(games: Array) -> Array:
	var best := {}
	for game: Dictionary in games:
		var players: Array = game["players"]
		var kind := "ffa"
		if players.size() == 2:
			kind = "mirror" if players[0] == players[1] else "bot"
		if not best.has(kind) or float(game["interest"]) > float(best[kind]["interest"]):
			best[kind] = game
	var picked := []
	for kind: String in ["mirror", "bot", "ffa"]:
		if best.has(kind):
			picked.append(best[kind])
	return picked


## Writes games as a .jsonl file, replacing what was there.
static func write_all(path: String, games: Array) -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	for game: Dictionary in games:
		f.store_line(JSON.stringify(game))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"),
		ProjectSettings.globalize_path(path))


## Adds one game as one line. `path` may be res:// or absolute.
static func append(path: String, game: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path,
		FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return false
	f.seek_end()
	f.store_line(JSON.stringify(game))
	f.close()
	return true


## Reads every game of a .jsonl file; lines that do not parse or are in an older
## format are skipped.
static func read_all(path: String) -> Array:
	var games := []
	if not FileAccess.file_exists(path):
		return games
	var f := FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).get("format", "") == FORMAT:
			games.append(parsed)
	return games
