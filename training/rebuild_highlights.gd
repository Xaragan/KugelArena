extends SceneTree
## Rebuilds highlights.jsonl of every training run from its recorded sample games.
##   godot --headless --path . --script res://training/rebuild_highlights.gd

const Recorder = preload("res://sim/game_recorder.gd")


func _initialize() -> void:
	var base := ProjectSettings.globalize_path("res://training/runs")
	for run_name in DirAccess.get_directories_at(base):
		var dir := base.path_join(run_name).path_join("games")
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var games := []
		for file in DirAccess.get_files_at(dir):
			games.append_array(Recorder.read_all(dir.path_join(file)))
		var picked := Recorder.pick_highlights(games)
		Recorder.write_all(base.path_join(run_name).path_join("highlights.jsonl"), picked)
		print("%s: %d games looked at, %d highlights kept" % [run_name, games.size(), picked.size()])
	quit(0)
