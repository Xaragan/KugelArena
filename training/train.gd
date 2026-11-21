extends SceneTree
## Trains the rival's net by letting it play headless games.
##
##   godot --headless --path . --script res://training/train.gd -- [options]
##     --minutes=30       stop after this many minutes (0 = no limit)
##     --generations=0    stop after this many generations (0 = no limit)
##     --run=main         name of the run, kept in training/runs/<name>/
##     --fresh            throw the run's checkpoint away and start from a random net
##     --workers=N        parallel game processes (default: cores - 2)
##     --net-share=0.5    share of training games played against nets (the current
##                        one and earlier versions); the rest are scripted bots
##     --selection=panel      champion = a net is kept when it beats the kept net
##                        directly; panel = when it scores best against scripted bots
##     --export=1         0 = do not replace the game's net (for experiments)
##
## Stop it any time: create a file called STOP in the run folder (or press Ctrl+C,
## which loses at most the generation in progress). Start it again with the same
## --run and it continues from the checkpoint.
##
## Method: evolution strategies. Every generation the current net is copied
## POPULATION times with small random changes to its weights, half of them the
## mirror image of the other half. All copies play the same GAMES_PER_CANDIDATE
## games, against a mix of scripted bots of varying character, earlier versions
## of the net and the current net itself. The weights then move towards the
## changes that scored better. No game ever counts for more than its result:
## win, loss, or "ran out of time", which is scored like a loss.
##
## The games of one generation are spread over worker processes (this same
## script with --worker). Each worker writes its own result file.

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")
const Match = preload("res://training/match.gd")
const Bot = preload("res://sim/scripted_bot.gd")
const Recorder = preload("res://sim/game_recorder.gd")
const Profile = preload("res://sim/net_profile.gd")

const POPULATION := 112            # must be even
const GAMES_PER_CANDIDATE := 10
const SIGMA := 0.07                # size of the random weight changes
const LEARNING_RATE := 0.015
const WEIGHT_DECAY := 0.005
const SNAPSHOT_EVERY := 10         # generations between league snapshots
const LEAGUE_SIZE := 12
const EVAL_EVERY := 10             # generations between tests
const EVAL_GAMES := 600            # test games against the panel of scripted bots
const EVAL_FFA_GAMES := 400        # test games in a four-ball free-for-all against the bots
const EVAL_SEED := 1000000
const FFA_SHARE := 0.5             # share of training games that are free-for-alls
const FFA_MAX_BALLS := 6
const DUEL_GAMES := 400             # games against the kept net when selection is "champion"
const DUEL_WIN_SHARE := 0.55
const RECORDED_GAMES := 12         # sample games saved as data at each test
const WORKER_TIMEOUT_MS := 180000
const GAME_NET := "res://net/rival_net.json"

var _opts := {}
var _run_dir := ""
var _state := {}
var _last_profile := {}   # how the current net behaves, see sim/net_profile.gd


func _initialize() -> void:
	_opts = {"minutes": "30", "generations": "0", "run": "main", "fresh": "0",
		"workers": str(maxi(1, OS.get_processor_count() - 2)), "worker": "-1", "job": "",
		"net_share": "0.5", "selection": "panel", "export": "1"}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_opts[parts[0].replace("-", "_")] = parts[1] if parts.size() == 2 else "1"
	if int(_opts["worker"]) >= 0:
		_worker_main(int(_opts["worker"]), _opts["job"])
		quit(0)
		return
	quit(_master_main())


# ------------------------------------------------------------------------------
# Worker: plays its share of one job and writes its own result file.
# ------------------------------------------------------------------------------

func _worker_main(index: int, job_path: String) -> void:
	var job: Variant = _read_var(job_path)
	if typeof(job) != TYPE_DICTIONARY:
		return
	var n_workers: int = job["n_workers"]
	var nets: Array = job["nets"]
	var scenarios: Array = job["scenarios"]
	for sc: Dictionary in scenarios:
		for spec: Dictionary in sc["seats"]:
			if spec["opp"] == "net":
				spec["net"] = nets[spec["net_index"]]
	var theta: PackedFloat32Array = job["theta"]
	var runner := Match.new()
	var result := {}
	if job["mode"] == "train":
		var seeds: PackedInt64Array = job["noise_seeds"]
		var sigma: float = job["sigma"]
		var candidates := []
		var ids := []
		for m in range(index, seeds.size() * 2, n_workers):
			candidates.append(perturbed(theta, seeds[m >> 1], sigma * (1.0 - 2.0 * (m & 1))))
			ids.append(m)
		var res := runner.play_all(candidates, scenarios, 1)
		for k in ids.size():
			result[ids[k]] = res[k]
	else:
		var mine := []
		for i in range(index, scenarios.size(), n_workers):
			mine.append(scenarios[i])
		var res: Array = runner.play_all([theta], mine, 1)[0]
		res[0] = float(res[0]) * mine.size()  # sum of rewards, the master averages
		result[0] = res
	_write_var(job_path.get_base_dir().path_join("result_%d.bin" % index), result)


## The weights plus scale * (a noise vector that is fully determined by its seed).
static func perturbed(theta: PackedFloat32Array, noise_seed: int, scale: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var w := theta.duplicate()
	for i in w.size():
		w[i] += scale * rng.randfn()
	return w


# ------------------------------------------------------------------------------
# Master
# ------------------------------------------------------------------------------

func _master_main() -> int:
	_run_dir = ProjectSettings.globalize_path("res://training/runs").path_join(_opts["run"])
	DirAccess.make_dir_recursive_absolute(_run_dir.path_join("work"))
	var stop_file := _run_dir.path_join("STOP")
	if FileAccess.file_exists(stop_file):
		DirAccess.remove_absolute(stop_file)
	if _opts["fresh"] != "0":
		for f in ["checkpoint.bin", "checkpoint.bak", "progress.md", "log.txt", "net_best.json",
				"behaviour.md", "highlights.jsonl"]:
			if FileAccess.file_exists(_run_dir.path_join(f)):
				DirAccess.remove_absolute(_run_dir.path_join(f))
		for sub in ["games", "nets"]:
			var d := _run_dir.path_join(sub)
			if DirAccess.dir_exists_absolute(d):
				for name in DirAccess.get_files_at(d):
					DirAccess.remove_absolute(d.path_join(name))
	if not _load_checkpoint():
		_new_state()
		_progress_header()
		_test_and_report()
		_save_checkpoint()
	else:
		_log("Continuing run '%s' at generation %d (%.1f minutes trained so far)." % [
			_opts["run"], _state["generation"], _state["seconds"] / 60.0])

	var session_start := Time.get_ticks_msec()
	var minutes := float(_opts["minutes"])
	var max_generations := int(_opts["generations"])
	var done := 0
	var failures := 0
	var why := "generation limit reached"
	while max_generations == 0 or done < max_generations:
		if FileAccess.file_exists(stop_file):
			DirAccess.remove_absolute(stop_file)
			why = "STOP file found"
			break
		if minutes > 0.0 and (Time.get_ticks_msec() - session_start) / 60000.0 >= minutes:
			why = "time limit of %s minutes reached" % _opts["minutes"]
			break
		var started := Time.get_ticks_msec()
		if not _one_generation():
			failures += 1
			if failures >= 3:
				_log("Three generations in a row failed; giving up. See the work folder.")
				return 1
			continue
		failures = 0
		done += 1
		_state["seconds"] += (Time.get_ticks_msec() - started) / 1000.0
		var gen: int = _state["generation"]
		if gen % SNAPSHOT_EVERY == 0:
			var league: Array = _state["league"]
			if league.size() >= LEAGUE_SIZE:
				league.remove_at(randi() % league.size())
			league.append((_state["theta"] as PackedFloat32Array).duplicate())
		if gen % EVAL_EVERY == 0:
			started = Time.get_ticks_msec()
			_test_and_report()
			_state["seconds"] += (Time.get_ticks_msec() - started) / 1000.0
		_save_checkpoint()
	_log("Stopped: %s. Generation %d, %.1f minutes trained in total. Best test: %.1f %% wins (generation %d)." % [
		why, _state["generation"], _state["seconds"] / 60.0, _state["best_score"] * 100.0,
		_state["best_generation"]])
	return 0


func _new_state() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var theta := PackedFloat32Array()
	theta.resize(Net.param_count())
	# Small random weights, scaled by the number of inputs of each layer; biases 0.
	var at := 0
	for layer: Array in [[Net.N_IN, Net.N_H1], [Net.N_H1, Net.N_H2], [Net.N_H2, Net.N_OUT]]:
		var scale := 1.0 / sqrt(layer[0])
		for i in layer[0] * layer[1]:
			theta[at + i] = rng.randfn() * scale
		at += layer[0] * layer[1] + layer[1]
	var zeros := PackedFloat64Array()
	zeros.resize(theta.size())
	_state = {
		"run_seed": rng.randi() >> 2,
		"generation": 0,
		"seconds": 0.0,
		"theta": theta,
		"adam_m": zeros,
		"adam_v": zeros.duplicate(),
		"league": [],
		"best_score": -1.0,
		"best_generation": 0,
		# Fixed for the life of the run, so continuing never changes the method.
		"net_share": float(_opts["net_share"]),
		"selection": _opts["selection"],
		"champion": PackedFloat32Array(),
	}
	_log("New run '%s': net with %d weights, %s workers." % [_opts["run"], theta.size(),
		_opts["workers"]])


## The games of one generation. Half are duels, half free-for-alls with three to
## FFA_MAX_BALLS balls. Every other ball is, by net_share, a net (the current one
## or an earlier version) or a scripted bot with a random character.
func _training_scenarios(rng: RandomNumberGenerator) -> Array:
	var league: Array = _state["league"]
	var list := []
	for i in GAMES_PER_CANDIDATE:
		var balls := 2
		if rng.randf() < FFA_SHARE:
			balls = rng.randi_range(3, FFA_MAX_BALLS)
		var seat := rng.randi() % balls
		var seats := []
		for s in balls:
			if s == seat:
				seats.append({"opp": "me"})
			elif rng.randf() < float(_state["net_share"]):
				# Index league.size() is the current net itself (see _run_job).
				var itself := league.is_empty() or rng.randf() < 0.33
				seats.append({"opp": "net",
					"net_index": league.size() if itself else rng.randi() % league.size()})
			else:
				seats.append({"opp": "std" if rng.randf() < 0.25 else "var",
					"bot_seed": rng.randi() >> 1})
		list.append({"seed": rng.randi() >> 1, "seat": seat, "seats": seats})
	return list


func _one_generation() -> bool:
	var gen: int = _state["generation"] + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state["run_seed"], gen])
	var theta: PackedFloat32Array = _state["theta"]
	var seeds := PackedInt64Array()
	for j in POPULATION / 2:
		seeds.append(rng.randi() >> 1)
	var started := Time.get_ticks_msec()
	var results := _run_job({"mode": "train", "sigma": SIGMA, "noise_seeds": seeds,
		"scenarios": _training_scenarios(rng)})

	# Keep only pairs where both mirror images reported back.
	var pairs := []
	var rewards := []
	var tally := [0.0, 0, 0, 0, 0, 0.0]
	for j in seeds.size():
		if results.has(2 * j) and results.has(2 * j + 1):
			pairs.append(j)
			for m in [2 * j, 2 * j + 1]:
				var r: Array = results[m]
				rewards.append(float(r[0]))
				for k in 6:
					tally[k] += r[k]
	if pairs.size() < seeds.size() / 2:
		_log("Generation %d: only %d of %d pairs came back, repeating it." % [gen, pairs.size(),
			seeds.size()])
		return false

	# Rank the rewards (best = +0.5, worst = -0.5); only the order matters, so a
	# single lucky game cannot dominate the step.
	var order := range(rewards.size())
	order.sort_custom(func(a: int, b: int) -> bool: return rewards[a] < rewards[b])
	var rank := PackedFloat64Array()
	rank.resize(rewards.size())
	for pos in order.size():
		rank[order[pos]] = float(pos) / maxf(1.0, rewards.size() - 1.0) - 0.5

	var n := theta.size()
	var grad := PackedFloat64Array()
	grad.resize(n)
	var noise_rng := RandomNumberGenerator.new()
	for p in pairs.size():
		var weight := rank[2 * p] - rank[2 * p + 1]
		noise_rng.seed = seeds[pairs[p]]
		for i in n:
			grad[i] += weight * noise_rng.randfn()
	var norm := 1.0 / (rewards.size() * SIGMA)

	# Adam step uphill.
	var m: PackedFloat64Array = _state["adam_m"]
	var v: PackedFloat64Array = _state["adam_v"]
	var bias1 := 1.0 - pow(0.9, gen)
	var bias2 := 1.0 - pow(0.999, gen)
	for i in n:
		var g := grad[i] * norm - WEIGHT_DECAY * theta[i]
		m[i] = 0.9 * m[i] + 0.1 * g
		v[i] = 0.999 * v[i] + 0.001 * g * g
		theta[i] += LEARNING_RATE * (m[i] / bias1) / (sqrt(v[i] / bias2) + 1e-8)
	_state["generation"] = gen

	var games: float = maxf(1.0, tally[1] + tally[2] + tally[3] + tally[4])
	_log("gen %4d  reward %+.3f  win %4.1f%%  loss %4.1f%%  draw %4.1f%%  timeout %4.1f%%  game %4.1fs  took %.1fs" % [
		gen, float(tally[0]) / rewards.size(), 100.0 * tally[1] / games, 100.0 * tally[2] / games,
		100.0 * tally[3] / games, 100.0 * tally[4] / games, float(tally[5]) / games,
		(Time.get_ticks_msec() - started) / 1000.0])
	return true


## Tests the current net, writes a line to progress.md and decides whether it
## becomes the kept net. Two tests against the scripted bots, always the same
## games: duels against the four characters, and four-ball free-for-alls against
## three of them (where winning by chance would be 25 %). The score is the mean
## of the two win rates.
##   selection "panel":    kept when its score is the best so far.
##   selection "champion": kept when it beats the currently kept net directly in
##                         duels, with at least 55 % of the decided games.
func _test_and_report() -> void:
	var theta: PackedFloat32Array = _state["theta"]
	var total := _sum_results(_run_job({"mode": "eval",
		"scenarios": Match.test_scenarios(EVAL_GAMES, EVAL_SEED, "panel")}))
	var ffa := _sum_results(_run_job({"mode": "eval",
		"scenarios": Match.test_scenarios(EVAL_FFA_GAMES, EVAL_SEED + 100000, "ffa")}))
	var games: float = total[1] + total[2] + total[3] + total[4]
	var ffa_games: float = ffa[1] + ffa[2] + ffa[3] + ffa[4]
	if games < EVAL_GAMES * 0.5 or ffa_games < EVAL_FFA_GAMES * 0.5:
		_log("Test at generation %d failed (%d + %d games came back); skipped." % [
			_state["generation"], int(games), int(ffa_games)])
		return
	var duel_rate: float = total[1] / games
	var ffa_rate: float = ffa[1] / ffa_games
	var score := 0.5 * (duel_rate + ffa_rate)
	var gen: int = _state["generation"]
	_record_samples()
	var is_best := false
	var duel := "-"
	if _state["selection"] == "champion":
		var champion: PackedFloat32Array = _state["champion"]
		if champion.is_empty():
			is_best = true
		else:
			var scenarios := []
			for i in DUEL_GAMES:
				var seats := [{"opp": "me"}, {"opp": "net",
					"net_index": (_state["league"] as Array).size() + 1}]
				if i % 2 == 1:
					seats.reverse()
				scenarios.append({"seed": EVAL_SEED + 500000 + i, "seat": i % 2, "seats": seats})
			var d := _sum_results(_run_job({"mode": "eval", "scenarios": scenarios}))
			var decided: float = d[1] + d[2]
			if decided >= DUEL_GAMES * 0.3:
				var share: float = d[1] / decided
				duel = "%.1f" % (100.0 * share)
				is_best = share >= DUEL_WIN_SHARE
		if is_best:
			_state["champion"] = theta.duplicate()
	else:
		is_best = score > _state["best_score"]
	var note := ""
	if is_best:
		_state["best_score"] = score
		_state["best_generation"] = gen
		var info := {"run": _opts["run"], "generation": gen, "panel_win_rate": duel_rate,
			"ffa_win_rate": ffa_rate, "test_games": int(games + ffa_games),
			"trained_minutes": snappedf(_state["seconds"] / 60.0, 0.1),
			"profile": _last_profile}
		Net.save_weights(_run_dir.path_join("net_best.json"), theta, info)
		note = "kept as best"
		if _opts["export"] != "0":
			Net.save_weights(GAME_NET, theta, info)
			note = "kept as best, now the game's net"
	var f := FileAccess.open(_run_dir.path_join("progress.md"), FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		f.store_line("| %d | %.1f | %.1f | %.1f | %.1f | %.1f | %s | %s |" % [gen,
			_state["seconds"] / 60.0, 100.0 * duel_rate, 100.0 * ffa_rate, 100.0 * score,
			float(total[5]) / games, duel, note])
		f.close()
	_log("TEST gen %d: duels %.1f%% wins (%d games), free-for-all %.1f%% wins (%d games), against the kept net: %s%%  %s" % [
		gen, 100.0 * duel_rate, int(games), 100.0 * ffa_rate, int(ffa_games), duel, note])


func _sum_results(results: Dictionary) -> Array:
	var total := [0.0, 0, 0, 0, 0, 0.0]
	for key: int in results:
		for k in 6:
			total[k] += results[key][k]
	return total


## At every test: saves the current net (so it can be picked as an opponent in
## the game), records a few of its games as data (half against itself, half
## against the baseline bot), keeps the run's three most interesting games in
## highlights.jsonl and adds a row to behaviour.md.
func _record_samples() -> void:
	var gen: int = _state["generation"]
	var theta: PackedFloat32Array = _state["theta"]
	_last_profile = Profile.measure(theta)
	var path := _run_dir.path_join("games").path_join("gen_%04d.jsonl" % gen)
	if FileAccess.file_exists(path):
		return
	DirAccess.make_dir_recursive_absolute(_run_dir.path_join("nets"))
	Net.save_weights(_run_dir.path_join("nets").path_join("gen_%04d.json" % gen), theta,
		{"run": _opts["run"], "generation": gen, "profile": _last_profile})
	var net := Net.new()
	net.weights = theta
	var sim := Sim.new()
	sim.record_events = true
	var recorder := Recorder.new()
	var games := []
	for g in RECORDED_GAMES:
		var game_seed := 2000000 + gen * 100 + g
		# A third each: net against itself, net against the baseline bot, and a
		# four-ball free-for-all of two nets and two bots.
		var is_bot: Array[bool] = [false, false]
		if g % 3 == 1:
			is_bot[(g / 3) % 2] = true
		elif g % 3 == 2:
			is_bot = [false, true, false, true]
		var names := []
		var bots := []
		for i in is_bot.size():
			names.append("baseline_bot" if is_bot[i] else "net_gen%d" % gen)
			bots.append(Bot.standard(game_seed + i) if is_bot[i] else null)
		sim.reset(game_seed, Match.TIME_LIMIT, is_bot.size())
		recorder.begin(game_seed, names)
		while sim.result == Sim.RUNNING:
			if sim.tick % Sim.DECISION_TICKS == 0:
				for i in sim.n:
					if sim.alive[i] == 1:
						sim.set_thrust(i, bots[i].act(sim, i) if is_bot[i] else net.act(sim, i))
				recorder.capture(sim)
			sim.step()
			recorder.note_events(sim)
			sim.events.clear()
		var game := recorder.finish(sim)
		game["run"] = _opts["run"]
		game["generation"] = gen
		Recorder.append(path, game)
		games.append(game)
	_update_highlights(games)
	_behaviour_row(games, gen)


## highlights.jsonl holds the run's most interesting recorded games, one of
## each kind (see Recorder.pick_highlights).
func _update_highlights(new_games: Array) -> void:
	var path := _run_dir.path_join("highlights.jsonl")
	Recorder.write_all(path, Recorder.pick_highlights(Recorder.read_all(path) + new_games))


## One row per test describing how the net behaves, measured on the sample games.
func _behaviour_row(games: Array, gen: int) -> void:
	var path := _run_dir.path_join("behaviour.md")
	if not FileAccess.file_exists(path):
		var h := FileAccess.open(path, FileAccess.WRITE)
		h.store_line("# How the net's behaviour develops, run '%s'" % _opts["run"])
		h.store_line("")
		h.store_line("Measured at every test on %d recorded games (a third each: net against itself," % RECORDED_GAMES)
		h.store_line("net against the baseline bot, four-ball free-for-all); few games, so read")
		h.store_line("trends, not single rows.")
		h.store_line("")
		h.store_line("- game s: mean game length. hits: collisions per game.")
		h.store_line("- items: items the net collects per game. escapes: times per game it was at the")
		h.store_line("  edge and got away again.")
		h.store_line("- from centre: its mean distance from the middle, in % of the disc radius.")
		h.store_line("- speed: its mean speed in % of top speed.")
		h.store_line("- chase: how much of its thrust points at the rival, +100 = always hunting,")
		h.store_line("  -100 = always running away.")
		h.store_line("- beats bot: wins in the sample duels against the baseline bot.")
		h.store_line("")
		h.store_line("| generation | game s | hits | items | escapes | from centre % | speed % | chase | beats bot | in words |")
		h.store_line("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
		h.close()
	var seconds := 0.0
	var hits := 0.0
	var items := 0.0
	var escapes := 0.0
	var dist := 0.0
	var speed := 0.0
	var chase := 0.0
	var balls := 0.0
	var bot_games := 0
	var bot_wins := 0
	for game: Dictionary in games:
		var st: Dictionary = game["stats"]
		seconds += float(game["seconds"])
		hits += float(st["hits"])
		var net_balls := 0
		for i in (game["players"] as Array).size():
			if not str(game["players"][i]).begins_with("net_"):
				continue
			net_balls += 1
			balls += 1.0
			dist += float(st["centre_dist"][i])
			speed += float(st["speed"][i])
			chase += float(st["chase"][i])
			items += float(st["pickups"][i]) / 1.0
			escapes += float(st["escapes"][i])
		if net_balls == 1 and (game["players"] as Array).size() == 2:
			bot_games += 1
			var net_side := 0 if str(game["players"][0]).begins_with("net_") else 1
			if game["result"] == "win_%d" % net_side:
				bot_wins += 1
	var n := maxf(1.0, games.size())
	balls = maxf(1.0, balls)
	seconds /= n
	hits /= n
	items /= balls
	escapes /= balls
	dist /= balls
	speed /= balls
	chase /= balls
	var words: Array[String] = []
	if seconds < 8.0 and hits < 1.0:
		words.append("falls off on its own")
	if chase > 0.45:
		words.append("hunts the rival")
	elif chase < 0.1 and seconds >= 8.0:
		words.append("does not seek the fight")
	if items >= 1.5:
		words.append("collects items")
	if dist < 0.35:
		words.append("holds the middle")
	elif dist > 0.6:
		words.append("lives near the edge")
	if escapes >= 0.5:
		words.append("saves itself at the edge")
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("| %d | %.1f | %.1f | %.1f | %.1f | %.0f | %.0f | %+.0f | %d of %d | %s |" % [gen, seconds,
		hits, items, escapes, 100.0 * dist, 100.0 * speed, 100.0 * chase, bot_wins, bot_games,
		", ".join(words)])
	f.close()


func _progress_header() -> void:
	var f := FileAccess.open(_run_dir.path_join("progress.md"), FileAccess.WRITE)
	f.store_line("# Training progress, run '%s'" % _opts["run"])
	f.store_line("")
	f.store_line("Every %d generations the net plays the same test games against scripted bots:" % EVAL_EVERY)
	f.store_line("%d duels against four characters, and %d four-ball free-for-alls against three" % [
		EVAL_GAMES, EVAL_FFA_GAMES])
	f.store_line("of them, where winning by chance would be 25 %. The score is the mean of the two")
	f.store_line("win rates. One generation = %d training games, half duels, half free-for-alls" % [
		POPULATION * GAMES_PER_CANDIDATE])
	f.store_line("with 3 to %d balls. Generation 0 is the untrained random net." % FFA_MAX_BALLS)
	f.store_line("")
	f.store_line("Method of this run: %d %% of the training games are against nets, selection '%s'." % [
		int(round(100.0 * float(_state["net_share"]))), _state["selection"]])
	f.store_line("The last number column is the share of decided games won against the kept net.")
	f.store_line("")
	f.store_line("| generation | minutes trained | duel wins % | free-for-all wins % | score | duel length s | vs kept net % | note |")
	f.store_line("|---:|---:|---:|---:|---:|---:|---:|---|")
	f.close()


# ------------------------------------------------------------------------------
# Worker processes and files
# ------------------------------------------------------------------------------

## Hands a job to the workers and collects {candidate index: result}. Results of
## workers that died or wrote a broken file are simply missing.
func _run_job(job: Dictionary) -> Dictionary:
	var n_workers := int(_opts["workers"])
	var work := _run_dir.path_join("work")
	var nets: Array = (_state["league"] as Array).duplicate()
	nets.append(_state["theta"])
	if not (_state["champion"] as PackedFloat32Array).is_empty():
		nets.append(_state["champion"])  # index league.size() + 1
	job["nets"] = nets
	job["theta"] = _state["theta"]
	job["n_workers"] = n_workers
	var job_path := work.path_join("job.bin")
	_write_var(job_path, job)
	var pids := []
	for w in n_workers:
		var result_path := work.path_join("result_%d.bin" % w)
		if FileAccess.file_exists(result_path):
			DirAccess.remove_absolute(result_path)
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", "res://training/train.gd",
			"--", "--worker=%d" % w, "--job=" + job_path]))
	var deadline := Time.get_ticks_msec() + WORKER_TIMEOUT_MS
	var running := true
	while running:
		OS.delay_msec(10)
		running = false
		for pid: int in pids:
			if pid > 0 and OS.is_process_running(pid):
				running = true
				break
		if running and Time.get_ticks_msec() > deadline:
			for pid: int in pids:
				if pid > 0 and OS.is_process_running(pid):
					OS.kill(pid)
			break
	var merged := {}
	for w in n_workers:
		var part: Variant = _read_var(work.path_join("result_%d.bin" % w))
		if typeof(part) != TYPE_DICTIONARY:
			continue
		for key: Variant in part:
			var value: Variant = part[key]
			if typeof(value) == TYPE_ARRAY and (value as Array).size() == 6:
				# In a test job every worker reports under key 0; keep them apart.
				merged[int(key) if job["mode"] == "train" else w] = value
	return merged


func _write_var(path: String, value: Variant) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(value)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


## Null when the file is missing, empty or cut off.
func _read_var(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 8:
		return null
	# The first four bytes are the length store_var wrote; a cut-off file fails here.
	var size := f.get_32()
	if size <= 0 or size > f.get_length() - 4:
		return null
	f.seek(0)
	return f.get_var()


func _save_checkpoint() -> void:
	var path := _run_dir.path_join("checkpoint.bin")
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, _run_dir.path_join("checkpoint.bak"))
	_write_var(path, _state)


func _load_checkpoint() -> bool:
	for name in ["checkpoint.bin", "checkpoint.bak"]:
		var data: Variant = _read_var(_run_dir.path_join(name))
		if typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("theta") \
				and (data["theta"] as PackedFloat32Array).size() == Net.param_count():
			_state = data
			return true
	return false


func _log(text: String) -> void:
	print(text)
	var path := _run_dir.path_join("log.txt")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%s  %s" % [Time.get_datetime_string_from_system(false, true), text])
		f.close()
