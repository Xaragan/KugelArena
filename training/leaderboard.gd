extends SceneTree
## Lists every saved net of every training run with its test results and how it
## plays. Writes training/leaderboard.md (to read) and training/leaderboard.json
## (for other tools).
##
##   godot --headless --path . --script res://training/leaderboard.gd

const Net = preload("res://sim/net_policy.gd")
const Profile = preload("res://sim/net_profile.gd")


func _initialize() -> void:
	var base := ProjectSettings.globalize_path("res://training/runs")
	var names := Array(DirAccess.get_directories_at(base)) if DirAccess.dir_exists_absolute(base) else []
	names.sort()
	var rows := []
	var runs := []
	for index in names.size():
		var run_name: String = names[index]
		var dir := base.path_join(run_name)
		var tests := Profile.read_tests(dir)
		var curve := []
		var generations := tests.keys()
		generations.sort()
		for g: int in generations:
			var t: Dictionary = tests[g]
			curve.append({"generation": g, "minutes": t["minutes"], "duel": t["duel"], "ffa": t["ffa"],
				"score": t["score"], "kept": t["kept"]})
		runs.append({"run": run_name, "first_name": Profile.FIRST_NAMES[index % Profile.FIRST_NAMES.size()],
			"tests": curve})
		if not DirAccess.dir_exists_absolute(dir.path_join("nets")):
			continue
		for file in DirAccess.get_files_at(dir.path_join("nets")):
			var data := Net.load_file(dir.path_join("nets").path_join(file))
			if data.is_empty():
				continue
			var info: Dictionary = data.get("info", {})
			var profile: Dictionary = info.get("profile", {})
			var generation := int(info.get("generation", 0))
			var test: Dictionary = tests.get(generation, {})
			rows.append({"name": Profile.display_name(profile, index), "run": run_name,
				"generation": generation, "minutes": test.get("minutes", -1.0),
				"duel": test.get("duel", -1.0), "ffa": test.get("ffa", -1.0),
				"score": test.get("score", -1.0), "kept": test.get("kept", false),
				"stars": Profile.stars(profile), "plays": Profile.tagline(profile),
				"profile": profile})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	var out := {"written": Time.get_datetime_string_from_system(false, true), "nets": rows, "runs": runs}
	var f := FileAccess.open("res://training/leaderboard.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	var lines: Array[String] = ["# Leaderboard", "",
		"Every saved net, best first. Written %s." % out["written"], "",
		"Duel and free-for-all are win rates in the training tests against scripted bots (600 duels,",
		"400 four-ball free-for-alls where chance would be 25 %); the score is their mean.", "",
		"| rank | net | age | run | minutes trained | duel wins % | free-for-all wins % | score | how it plays |",
		"|---:|---|---:|---|---:|---:|---:|---:|---|"]
	for k in rows.size():
		var r: Dictionary = rows[k]
		lines.append("| %d | %s | %d | %s | %.1f | %.1f | %.1f | %.1f | %s |" % [k + 1, r["name"],
			r["generation"], r["run"], r["minutes"], 100.0 * float(r["duel"]), 100.0 * float(r["ffa"]),
			100.0 * float(r["score"]), r["plays"]])
	f = FileAccess.open("res://training/leaderboard.md", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("Leaderboard: %d nets from %d runs." % [rows.size(), runs.size()])
	quit(0)
