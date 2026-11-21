extends RefCounted
## Turns a net into something a player can read: a name, a strength from one to
## five and a few plain sentences about how it plays.
##
## measure() lets the net play a handful of games and counts what it does; the
## numbers are stored in the net's file (info.profile). The wording is made from
## those numbers when the menu is shown, so it can change without re-measuring.

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")
const Bot = preload("res://sim/scripted_bot.gd")
const Recorder = preload("res://sim/game_recorder.gd")

## One first name per training run: the generations of a run are the same
## character growing up.
const FIRST_NAMES: Array[String] = ["Rico", "Mara", "Bolle", "Zora", "Knut", "Pixel", "Otto",
	"Luna", "Tilda", "Nox", "Fips", "Greta", "Jogi", "Kira", "Runa", "Tarek", "Wanda", "Yuki",
	"Zack", "Elmo", "Frida", "Bruno", "Ada", "Milo"]


## Plays 60 games (20 duels against the baseline bot, 20 against itself, 20
## four-ball free-for-alls against three bots) and returns what the net did:
##   win_vs_bot  share of the bot duels it won
##   ffa_win     share of the free-for-alls it won (chance would be 0.25)
##   chase       thrust towards the nearest rival, +1 always hunting .. -1 fleeing
##   centre      mean distance from the middle, share of the disc radius
##   items       items collected per game
##   escapes     times per game it was at the edge and got away
##   speed       mean speed, share of top speed
##   hits        collisions per duel
##   seconds     mean duel length
static func measure(weights: PackedFloat32Array) -> Dictionary:
	var net := Net.new()
	net.weights = weights
	var sim := Sim.new()
	sim.record_events = true
	var recorder := Recorder.new()
	var sums := {"chase": 0.0, "centre": 0.0, "items": 0.0, "escapes": 0.0, "speed": 0.0}
	var balls := 0.0
	var hits := 0.0
	var seconds := 0.0
	var bot_wins := 0
	var ffa_wins := 0
	for g in 60:
		var game_seed := 3000000 + g
		var kind := g / 20           # 0 bot duel, 1 mirror duel, 2 free-for-all
		var count := 4 if kind == 2 else 2
		var my_seat := g % count
		var bots := []
		for i in count:
			bots.append(Bot.standard(game_seed + i) if kind != 1 and i != my_seat else null)
		sim.reset(game_seed, 90.0, count)
		recorder.begin(game_seed, [])
		while sim.result == Sim.RUNNING:
			if sim.tick % Sim.DECISION_TICKS == 0:
				for i in count:
					if sim.alive[i] == 1:
						sim.set_thrust(i, net.act(sim, i) if bots[i] == null else bots[i].act(sim, i))
				recorder.capture(sim)
			sim.step()
			recorder.note_events(sim)
			sim.events.clear()
		if kind == 2:
			if sim.result == my_seat:
				ffa_wins += 1
			continue
		var st: Dictionary = recorder.finish(sim)["stats"]
		hits += float(st["hits"])
		seconds += sim.seconds()
		if kind == 0 and sim.result == my_seat:
			bot_wins += 1
		for i in count:
			if bots[i] != null:
				continue
			balls += 1.0
			sums["chase"] += float(st["chase"][i])
			sums["centre"] += float(st["centre_dist"][i])
			sums["items"] += float(st["pickups"][i])
			sums["escapes"] += float(st["escapes"][i])
			sums["speed"] += float(st["speed"][i])
	var profile := {"games": 60, "win_vs_bot": snappedf(bot_wins / 20.0, 0.001),
		"ffa_win": snappedf(ffa_wins / 20.0, 0.001),
		"hits": snappedf(hits / 40.0, 0.1), "seconds": snappedf(seconds / 40.0, 0.1)}
	for key: String in sums:
		profile[key] = snappedf(float(sums[key]) / maxf(1.0, balls), 0.001)
	return profile


static func falls_alone(p: Dictionary) -> bool:
	return float(p.get("seconds", 30.0)) < 8.0 and float(p.get("hits", 5.0)) < 1.0


## One (easy) to five (hard).
static func stars(p: Dictionary) -> int:
	var w := float(p.get("win_vs_bot", 0.0))
	if w < 0.15:
		return 1
	if w < 0.35:
		return 2
	if w < 0.55:
		return 3
	if w < 0.75:
		return 4
	return 5


static func difficulty(p: Dictionary) -> String:
	var s := stars(p)
	return "Easy" if s <= 2 else ("Medium" if s == 3 else "Hard")


## Collisions per second of play: above about 0.9 the net is in contact nearly
## all the time.
static func _hit_rate(p: Dictionary) -> float:
	return float(p.get("hits", 0.0)) / maxf(1.0, float(p.get("seconds", 1.0)))


## What kind of player it is, from its most striking habit.
static func epithet(p: Dictionary) -> String:
	if p.is_empty():
		return "the Unknown"
	if falls_alone(p):
		return "the Lemming"
	if float(p["chase"]) < 0.3:
		return "the Drifter"
	if float(p["win_vs_bot"]) >= 0.5 and float(p["seconds"]) <= 22.0:
		return "the Finisher"
	if _hit_rate(p) >= 0.9:
		return "the Brawler"
	if float(p["escapes"]) >= 0.45:
		return "the Acrobat"
	if float(p["items"]) >= 0.9:
		return "the Collector"
	if float(p["speed"]) >= 0.77:
		return "the Sprinter"
	return "the Hunter"


static func display_name(p: Dictionary, run_index: int) -> String:
	return "%s %s" % [FIRST_NAMES[posmod(run_index, FIRST_NAMES.size())], epithet(p)]


static func _habits(p: Dictionary) -> Array[String]:
	var list: Array[String] = []
	if p.is_empty():
		return list
	if falls_alone(p):
		list.append("rolls off the disc all by itself")
		return list
	var chase := float(p["chase"])
	if chase < 0.3:
		list.append("drifts around without a plan")
	elif _hit_rate(p) >= 0.9:
		list.append("keeps ramming you without a pause")
	elif chase >= 0.6:
		list.append("is on your heels the whole time")
	else:
		list.append("picks its moments to attack")
	if float(p["win_vs_bot"]) >= 0.5 and float(p["seconds"]) <= 22.0:
		list.append("ends rounds quickly")
	if float(p["escapes"]) >= 0.45:
		list.append("wriggles out when it is nearly off")
	var items := float(p["items"])
	if items >= 0.9:
		list.append("likes to grab the items")
	elif items < 0.4:
		list.append("leaves the items alone")
	if float(p["speed"]) >= 0.77:
		list.append("is nearly always at full speed")
	var centre := float(p["centre"])
	if centre < 0.31:
		list.append("guards the middle")
	elif centre > 0.5:
		list.append("lives close to the edge")
	return list


## Short line for a card.
static func tagline(p: Dictionary) -> String:
	var habits := _habits(p)
	if habits.is_empty():
		return "nobody has watched it play yet"
	var line := habits[0]
	if habits.size() > 1:
		line += ", " + habits[1]
	return line.capitalize().substr(0, 1) + line.substr(1)


## A few sentences for the detail view and the tooltip.
static func description(p: Dictionary) -> String:
	if p.is_empty():
		return "Nobody has watched this one play yet."
	var text := ""
	var habits := _habits(p)
	if not habits.is_empty():
		text = "It " + ", ".join(habits) + ".\n\n"
	text += "Beats the practice bot in about %d of 10 duels." % int(round(float(p["win_vs_bot"]) * 10.0))
	if p.has("ffa_win"):
		text += " In a four-ball free-for-all it is the last one standing about %d times in 10." % int(
			round(float(p["ffa_win"]) * 10.0))
	if not falls_alone(p):
		text += " A duel with it lasts around %d seconds, with a collision about every %s." % [
			int(round(float(p["seconds"]))),
			"second" if float(p["hits"]) >= float(p["seconds"]) * 0.7 else "couple of seconds"]
	return text


## The test results of a training run, read from its progress.md:
## {generation: {minutes, duel, ffa, score, kept}}. duel = share of the test duels
## won against the scripted bots, ffa = share of the four-ball free-for-alls won
## (0.25 would be chance), score = their mean, kept = it was the best so far.
static func read_tests(run_dir: String) -> Dictionary:
	var tests := {}
	var path := run_dir.path_join("progress.md")
	if not FileAccess.file_exists(path):
		return tests
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var cells := line.split("|")
		if cells.size() < 9 or not cells[1].strip_edges().is_valid_int():
			continue
		tests[int(cells[1])] = {"minutes": float(cells[2]), "duel": float(cells[3]) / 100.0,
			"ffa": float(cells[4]) / 100.0, "score": float(cells[5]) / 100.0,
			"kept": cells[8].contains("kept")}
	return tests


## Measures a net file and stores the result in it. False if the file is no net.
static func write_to_file(path: String) -> bool:
	var data := Net.load_file(path)
	if data.is_empty():
		return false
	var info: Dictionary = data.get("info", {})
	var weights := PackedFloat32Array(data["weights"])
	info["profile"] = measure(weights)
	return Net.save_weights(path, weights, info)
