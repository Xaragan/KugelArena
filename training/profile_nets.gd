extends SceneTree
## Watches every saved net play a few games and stores how it behaves in its file,
## so the game's menu can show a name, a strength and a description.
## Nets that already have a profile are skipped (use --all to redo them).
##
##   godot --headless --path . --script res://training/profile_nets.gd -- [--all]

const Net = preload("res://sim/net_policy.gd")
const Profile = preload("res://sim/net_profile.gd")


func _initialize() -> void:
	var redo := "--all" in OS.get_cmdline_user_args()
	var paths: Array[String] = [ProjectSettings.globalize_path("res://net/rival_net.json")]
	var base := ProjectSettings.globalize_path("res://training/runs")
	if DirAccess.dir_exists_absolute(base):
		for run_name in DirAccess.get_directories_at(base):
			var dir := base.path_join(run_name)
			paths.append(dir.path_join("net_best.json"))
			if DirAccess.dir_exists_absolute(dir.path_join("nets")):
				for file in DirAccess.get_files_at(dir.path_join("nets")):
					if file.ends_with(".json"):
						paths.append(dir.path_join("nets").path_join(file))
	var done := 0
	for path in paths:
		var data := Net.load_file(path)
		if data.is_empty():
			continue
		if not redo and (data.get("info", {}) as Dictionary).has("profile"):
			continue
		if Profile.write_to_file(path):
			done += 1
	print("Profiled %d nets (%d files looked at)." % [done, paths.size()])
	quit(0)
