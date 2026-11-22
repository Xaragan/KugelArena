extends RefCounted
## The rival's brain: a small fully connected net, evaluated in plain GDScript.
##
## 87 inputs (see ArenaSim.observe) -> 32 tanh -> 16 tanh -> 3 tanh.
## The first two outputs are a thrust vector in the ball's own frame (x = towards
## the nearest rival, y = a quarter turn to the left); act() turns it back into
## arena space. The third output asks for a dodge when it is above 0.5.
## All weights live in one flat array: per layer the weight matrix row by row
## (one row per output neuron), then the biases.

const Sim = preload("res://sim/arena_sim.gd")

const N_IN := 87
const N_H1 := 32
const N_H2 := 16
const N_OUT := 3
const FORMAT := "kugelarena-net-3"

var weights := PackedFloat32Array()
var _obs := PackedFloat32Array()
var _h1 := PackedFloat32Array()
var _h2 := PackedFloat32Array()
var _out := PackedFloat32Array()


static func param_count() -> int:
	return N_IN * N_H1 + N_H1 + N_H1 * N_H2 + N_H2 + N_H2 * N_OUT + N_OUT


func _init() -> void:
	_obs.resize(N_IN)
	_h1.resize(N_H1)
	_h2.resize(N_H2)
	_out.resize(N_OUT)
	weights.resize(param_count())


func _layer(src: PackedFloat32Array, dst: PackedFloat32Array, offset: int,
		n_in: int, n_out: int) -> int:
	var w := weights
	var bias_at := offset + n_in * n_out
	for o in n_out:
		var s: float = w[bias_at + o]
		var row := offset + o * n_in
		for i in n_in:
			s += w[row + i] * src[i]
		dst[o] = tanh(s)
	return bias_at + n_out


## Thrust for ball `who` in arena space, length at most 1. Also triggers the
## ball's dodge in that direction when the net asks for it.
func act(sim: Sim, who: int) -> Vector2:
	sim.observe(who, _obs)
	var at := _layer(_obs, _h1, 0, N_IN, N_H1)
	at = _layer(_h1, _h2, at, N_H1, N_H2)
	_layer(_h2, _out, at, N_H2, N_OUT)
	var ex := sim.frame_x(who)
	var ey := Vector2(-ex.y, ex.x)
	var t := ex * _out[0] + ey * _out[1]
	var l := t.length()
	if l > 1.0:
		t /= l
	if _out[2] > 0.5 and sim.dash_cd[who] <= 0.0:
		sim.dash(who, t)
	return t


static func save_weights(path: String, w: PackedFloat32Array, info: Dictionary) -> bool:
	var data := {
		"format": FORMAT,
		"layers": [N_IN, N_H1, N_H2, N_OUT],
		"info": info,
		"weights": Array(w),
	}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	# Write-then-rename, so a crash never leaves half a file behind.
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)
	return DirAccess.rename_absolute(abs_tmp, abs_path) == OK


## Returns {} when the file is missing or does not fit this net.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if data.get("format", "") != FORMAT:
		return {}
	var raw: Variant = data.get("weights", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != param_count():
		return {}
	return data


## Loads weights into this net. False when the file is unusable.
func load_weights(path: String) -> bool:
	var data := load_file(path)
	if data.is_empty():
		return false
	weights = PackedFloat32Array(data["weights"])
	return true
