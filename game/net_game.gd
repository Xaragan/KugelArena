extends Node
## Multiplayer link: one player hosts, friends join.
##
## The host runs the game (sim/arena_sim.gd) and is the only one who decides what
## happens. Everyone else sends their W A S D thrust and receives the state of the
## disc 30 times per second, plus the hits, pickups and falls as they happen.
##
## Two ways to connect, same messages on both:
##   Steam  a Steam lobby; friends are invited from the lobby screen or join a
##          friend they see hosting. Uses the GodotSteam extension (addons/godotsteam)
##          and Valve's public test app id 480 ("Spacewar").
##   LAN    direct connection by address (same network, or a forwarded port).
##
## This node must sit at the same path on every machine (it is Main/Net), because
## Godot's remote calls are addressed by node path.

signal lobby_changed                      # players or settings changed
signal entered_lobby                      # connected: show the lobby screen
signal round_started(info: Dictionary)    # client: the host started a round
signal state_received(data: PackedFloat32Array)
signal events_received(list: Array)
signal round_finished(info: Dictionary)
signal closed(reason: String)             # connection ended; reason is for the player
signal friends_changed

const STEAM_APP_ID := 480
const DEFAULT_PORT := 24800
const MAX_PLAYERS := 8

var active := false
var hosting := false
var via_steam := false
var players := {}                 # peer id -> name; the host is peer 1
var settings := {"balls": 2}      # chosen by the host
var inputs := {}                  # host only: peer id -> thrust (Vector2)
var my_name := "Player"
var status := ""                  # last thing worth telling the player

var steam: Object = null
var steam_ready := false
var lobby_id := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _close("Could not connect."))
	multiplayer.server_disconnected.connect(func() -> void: _close("The host closed the game."))


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


# ------------------------------------------------------------------------------
# Steam
# ------------------------------------------------------------------------------

## Connects to the running Steam client. Called when the player opens the
## multiplayer screen, not at start, so playing alone never touches Steam.
func init_steam() -> bool:
	if steam_ready:
		return true
	if not Engine.has_singleton("Steam"):
		status = "The Steam extension is missing (addons/godotsteam)."
		return false
	steam = Engine.get_singleton("Steam")
	var result: Dictionary = steam.steamInitEx(STEAM_APP_ID, true)
	if int(result.get("status", 1)) != 0:
		status = "Steam is not available: %s  Start Steam and log in, then try again." % str(
			result.get("verbal", "unknown error"))
		return false
	steam_ready = true
	my_name = str(steam.getPersonaName())
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(_on_join_requested)
	steam.persona_state_change.connect(func(_id: int, _flags: int) -> void: friends_changed.emit())
	status = "Steam: logged in as %s." % my_name
	return true


## Friends who are online: {id, name, lobby}. lobby is non-zero while that friend
## sits in a lobby of this app, i.e. is probably hosting or playing right now.
func friends() -> Array:
	var list := []
	if not steam_ready:
		return list
	var flag: int = steam.FRIEND_FLAG_IMMEDIATE
	for i in int(steam.getFriendCount(flag)):
		var id: int = steam.getFriendByIndex(i, flag)
		if int(steam.getFriendPersonaState(id)) == int(steam.PERSONA_STATE_OFFLINE):
			continue
		var game: Dictionary = steam.getFriendGamePlayed(id) if steam.has_method("getFriendGamePlayed") else {}
		var in_lobby := 0
		if int(game.get("id", 0)) == STEAM_APP_ID:
			in_lobby = int(game.get("lobby", 0))
		list.append({"id": id, "name": str(steam.getFriendPersonaName(id)), "lobby": in_lobby})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).nocasecmp_to(str(b["name"])) < 0)
	return list


func invite(friend_id: int) -> void:
	if steam_ready and lobby_id != 0:
		steam.inviteUserToLobby(lobby_id, friend_id)


func host_steam() -> void:
	if not init_steam():
		closed.emit(status)
		return
	leave()
	hosting = true
	via_steam = true
	status = "Opening a Steam lobby ..."
	steam.createLobby(steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)


func _on_lobby_created(connect_result: int, new_lobby: int) -> void:
	if connect_result != 1:
		_close("Steam could not open a lobby (code %d)." % connect_result)
		return
	lobby_id = new_lobby
	steam.setLobbyData(lobby_id, "game", "kugelarena")
	steam.setLobbyData(lobby_id, "name", "%s's KugelArena" % my_name)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var error: int = peer.host_with_lobby(lobby_id)
	if error != OK:
		_close("Could not start hosting over Steam (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer
	_begin_hosting("Your Steam lobby is open. Invite friends below.")


func join_steam(target_lobby: int) -> void:
	if not init_steam():
		closed.emit(status)
		return
	leave()
	via_steam = true
	status = "Joining ..."
	steam.joinLobby(target_lobby)


func _on_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if hosting:
		return  # Steam also reports our own lobby as joined
	if response != int(steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS):
		_close("Steam did not let you into that lobby (code %d)." % response)
		return
	lobby_id = joined_lobby
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var error: int = peer.connect_to_lobby(lobby_id)
	if error != OK:
		_close("Could not connect to the host over Steam (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer
	active = true
	status = "Connecting to the host ..."
	entered_lobby.emit()


## The player accepted an invite or clicked "Join game" on a friend in Steam.
func _on_join_requested(target_lobby: int, _friend_id: int) -> void:
	join_steam(target_lobby)


# ------------------------------------------------------------------------------
# Direct connection
# ------------------------------------------------------------------------------

func host_lan(port: int = DEFAULT_PORT) -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		closed.emit("Could not open port %d (error %d). Is another game already hosting?" % [port, error])
		return
	multiplayer.multiplayer_peer = peer
	hosting = true
	_begin_hosting("Hosting on port %d. Friends join with this PC's address." % port)


func join_lan(address: String, port: int = DEFAULT_PORT) -> void:
	leave()
	if address.contains(":"):
		port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		closed.emit("That address did not work (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer
	active = true
	status = "Connecting to %s ..." % address
	entered_lobby.emit()


# ------------------------------------------------------------------------------
# Lobby
# ------------------------------------------------------------------------------

func _begin_hosting(text: String) -> void:
	active = true
	players = {1: my_name}
	inputs.clear()
	status = text
	entered_lobby.emit()
	lobby_changed.emit()


func _on_connected() -> void:
	status = "Connected. Waiting for the host to start."
	_hello.rpc_id(1, my_name)
	lobby_changed.emit()


func _on_peer_connected(_id: int) -> void:
	pass  # the newcomer introduces itself with _hello


func _on_peer_disconnected(id: int) -> void:
	if hosting and players.has(id):
		players.erase(id)
		inputs.erase(id)
		_send_lobby()


## Host: change a setting (e.g. the number of balls) and tell everyone.
func set_setting(key: String, value: Variant) -> void:
	if hosting:
		settings[key] = value
		_send_lobby()


func _send_lobby() -> void:
	if hosting and active:
		_lobby.rpc({"players": players, "settings": settings})
	lobby_changed.emit()


## Ends the connection and returns everything to "not connected".
func leave() -> void:
	if steam_ready and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	hosting = false
	via_steam = false
	players.clear()
	inputs.clear()
	settings = {"balls": 2}


func _close(reason: String) -> void:
	leave()
	status = reason
	closed.emit(reason)


# ------------------------------------------------------------------------------
# Messages. Client -> host: _hello, _thrust. Host -> clients: the rest.
# ------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(player_name: String) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var clean := player_name.strip_edges().substr(0, 24)
	players[id] = clean if clean != "" else "Player %d" % players.size()
	_send_lobby()


@rpc("authority", "call_remote", "reliable")
func _lobby(state: Dictionary) -> void:
	players = state.get("players", {})
	settings = state.get("settings", {"balls": 2})
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _thrust(x: float, y: float) -> void:
	if hosting:
		inputs[multiplayer.get_remote_sender_id()] = Vector2(x, y).limit_length(1.0)


@rpc("authority", "call_remote", "reliable")
func _round_start(info: Dictionary) -> void:
	round_started.emit(info)


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(data: PackedFloat32Array) -> void:
	state_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _events(list: Array) -> void:
	events_received.emit(list)


@rpc("authority", "call_remote", "reliable")
func _round_over(info: Dictionary) -> void:
	round_finished.emit(info)


func send_input(thrust: Vector2) -> void:
	if active and not hosting and multiplayer.multiplayer_peer.get_connection_status() == \
			MultiplayerPeer.CONNECTION_CONNECTED:
		_thrust.rpc_id(1, thrust.x, thrust.y)


func send_round_start(info: Dictionary) -> void:
	if hosting and players.size() > 1:
		_round_start.rpc(info)


func send_state(data: PackedFloat32Array) -> void:
	if hosting and players.size() > 1:
		_state.rpc(data)


func send_events(list: Array) -> void:
	if hosting and players.size() > 1:
		_events.rpc(list)


func send_round_over(info: Dictionary) -> void:
	if hosting and players.size() > 1:
		_round_over.rpc(info)
