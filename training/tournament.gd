extends SceneTree
## Everyone against everyone: the best net of every training run plus the
## scripted practice bot play a round robin of duels, and then free-for-alls
## with everyone on the disc at once (at most eight per game, drawn at random
## when there are more). Writes training/tournament.md.
##
##   godot --headless --path . --script res://training/tournament.gd -- [options]
##     --games=200     games per pairing, sides alternate
##     --seed=9000000  first game seed (training never uses these)
##     --all           also enter every saved generation of every run, not only the best

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")
const Bot = preload("res://sim/scripted_bot.gd")
const Profile = preload("res://sim/net_profile.gd")


func _initialize() -> void:
	var opts := {"games": "200", "seed": "9000000", "all": "0"}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		opts[parts[0]] = parts[1] if parts.size() == 2 else "1"
	var games := int(opts["games"])

	# Entrants: {name, net (null = the bot)}.
	var entrants := [{"name": "Practice bot (scripted)", "net": null}]
	var base := ProjectSettings.globalize_path("res://training/runs")
	var names := Array(DirAccess.get_directories_at(base)) if DirAccess.dir_exists_absolute(base) else []
	names.sort()
	for index in names.size():
		var dir := base.path_join(names[index])
		var files: Array[String] = [dir.path_join("net_best.json")]
		if opts["all"] != "0" and DirAccess.dir_exists_absolute(dir.path_join("nets")):
			files.clear()
			for file in DirAccess.get_files_at(dir.path_join("nets")):
				files.append(dir.path_join("nets").path_join(file))
		for path in files:
			var data := Net.load_file(path)
			if data.is_empty():
				continue
			var info: Dictionary = data.get("info", {})
			var net := Net.new()
			net.weights = PackedFloat32Array(data["weights"])
			entrants.append({"net": net, "name": "%s, age %d (run %s)" % [
				Profile.display_name(info.get("profile", {}), index), int(info.get("generation", 0)),
				names[index]]})

	var n := entrants.size()
	var wins := []      # wins[a][b] = games a won against b
	for a in n:
		var row := []
		row.resize(n)
		row.fill(0)
		wins.append(row)
	var sim := Sim.new()
	var started := Time.get_ticks_msec()
	for a in n:
		for b in range(a + 1, n):
			for g in games:
				var game_seed := int(opts["seed"]) + g
				var a_side := g % 2
				var players := [null, null]
				players[a_side] = entrants[a]["net"] if entrants[a]["net"] != null else Bot.standard(game_seed)
				players[1 - a_side] = entrants[b]["net"] if entrants[b]["net"] != null else Bot.standard(game_seed + 1)
				sim.reset(game_seed, 90.0)
				while sim.result == Sim.RUNNING:
					if sim.tick % Sim.DECISION_TICKS == 0:
						sim.set_thrust(0, players[0].act(sim, 0))
						sim.set_thrust(1, players[1].act(sim, 1))
					sim.step()
				if sim.result == a_side:
					wins[a][b] += 1
				elif sim.result == 1 - a_side:
					wins[b][a] += 1

	# Rank by share of all games won.
	var order := range(n)
	var total := []
	for a in n:
		var sum := 0
		for b in n:
			sum += wins[a][b]
		total.append(sum)
	order.sort_custom(func(x: int, y: int) -> bool: return total[x] > total[y])
	var lines: Array[String] = ["# Tournament: everyone against everyone", "",
		"%d games per pairing, sides alternating, on games training never used. Played %s." % [
		games, Time.get_datetime_string_from_system(false, true)],
		"Each cell: share of the games the row player won against the column player.", ""]
	var header := "| rank | player | all games won % |"
	var rule := "|---:|---|---:|"
	for k in n:
		header += " vs %d |" % (k + 1)
		rule += "---:|"
	lines.append(header)
	lines.append(rule)
	for k in n:
		var a: int = order[k]
		var line := "| %d | %s | %.1f |" % [k + 1, entrants[a]["name"],
			100.0 * total[a] / maxf(1.0, games * (n - 1))]
		for j in n:
			var b: int = order[j]
			line += " - |" if a == b else " %d |" % int(round(100.0 * wins[a][b] / games))
		lines.append(line)
	# Free-for-all: everyone on one disc.
	if n >= 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(opts["seed"])
		var ffa_wins := []
		var ffa_place := []
		var ffa_games := []
		for a in n:
			ffa_wins.append(0)
			ffa_place.append(0.0)
			ffa_games.append(0)
		var balls := mini(n, Sim.MAX_BALLS)
		for g in games:
			var game_seed := int(opts["seed"]) + 100000 + g
			var seats := range(n)
			for k in range(n - 1, 0, -1):   # shuffle with our own rng
				var swap := rng.randi() % (k + 1)
				var tmp: int = seats[k]
				seats[k] = seats[swap]
				seats[swap] = tmp
			seats = seats.slice(0, balls)
			var players := []
			for seat in balls:
				var who: int = seats[seat]
				players.append(entrants[who]["net"] if entrants[who]["net"] != null
					else Bot.standard(game_seed + seat))
			sim.reset(game_seed, 90.0, balls)
			while sim.result == Sim.RUNNING:
				if sim.tick % Sim.DECISION_TICKS == 0:
					for seat in balls:
						if sim.alive[seat] == 1:
							sim.set_thrust(seat, players[seat].act(sim, seat))
				sim.step()
			for seat in balls:
				var who: int = seats[seat]
				ffa_games[who] += 1
				ffa_place[who] += maxi(sim.place[seat], 1)
				if sim.result == seat:
					ffa_wins[who] += 1
		var ffa_order := range(n)
		ffa_order.sort_custom(func(x: int, y: int) -> bool:
			return float(ffa_wins[x]) / maxf(1.0, ffa_games[x]) > float(ffa_wins[y]) / maxf(1.0, ffa_games[y]))
		lines.append("")
		lines.append("## Free-for-all")
		lines.append("")
		lines.append("%d games with %d balls each; by chance everyone would win %.1f %%." % [games, balls,
			100.0 / balls])
		lines.append("")
		lines.append("| rank | player | games | won % | mean place |")
		lines.append("|---:|---|---:|---:|---:|")
		for k in n:
			var a: int = ffa_order[k]
			lines.append("| %d | %s | %d | %.1f | %.2f |" % [k + 1, entrants[a]["name"], ffa_games[a],
				100.0 * ffa_wins[a] / maxf(1.0, ffa_games[a]), ffa_place[a] / maxf(1.0, ffa_games[a])])
	var f := FileAccess.open("res://training/tournament.md", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	for line in lines:
		print(line)
	print("(%.0f s)" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit(0)
