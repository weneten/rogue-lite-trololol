extends Node

# WebSocket lobby + host-authoritative combat relay. Browsers cannot listen,
# so every peer connects to /signal and the host simulates enemies.

const SNAP_HZ := 15.0
const MAX_PEERS := 4

var is_active: bool = false
var is_host: bool = false
var local_pid: int = 0
var code: String = ""
var seed: int = 0
var roster: Array = []
var last_error: String = ""
var lobby_intent: String = ""

signal roster_changed(players)
signal lobby_ready(code)
signal match_starting(seed)
signal lobby_failed(message)

var _socket: WebSocketPeer
var _snap_acc: float = 0.0
var _next_enemy_id: int = 1
var _remotes: Dictionary = {}
var _proxies: Dictionary = {}
var _remote_hp: Dictionary = {}
var _arena_armed: bool = false
var _char_name: String = ""

func is_client() -> bool:
	return is_active and not is_host

func reset() -> void:
	is_active = false
	is_host = false
	local_pid = 0
	code = ""
	roster = []
	last_error = ""
	_arena_armed = false
	_next_enemy_id = 1
	_remotes.clear()
	_proxies.clear()
	_remote_hp.clear()
	if _socket != null:
		_socket.close()
		_socket = null

func host_lobby(character_name: String) -> void:
	_char_name = character_name
	_connect_and_send({"op": "host", "char": character_name})

func join_lobby(join_code: String, character_name: String) -> void:
	_char_name = character_name
	_connect_and_send({"op": "join", "code": join_code.strip_edges().to_upper(), "char": character_name})

func start_match() -> void:
	if not is_host:
		return
	seed = randi()
	_send({"op": "start", "seed": seed})

func send_hit(enemy_net_id: int, amount: int) -> void:
	if not is_active or amount <= 0:
		return
	if is_host:
		_apply_hit(enemy_net_id, amount)
	else:
		_send({"op": "hit", "eid": enemy_net_id, "dmg": amount})

func take_enemy_id() -> int:
	var id := _next_enemy_id
	_next_enemy_id += 1
	return id

func _process(delta: float) -> void:
	if _socket != null:
		_socket.poll()
		var state := _socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not _pending_hello.is_empty():
				var hello := _pending_hello
				_pending_hello = {}
				_send(hello)
			while _socket.get_available_packet_count() > 0:
				_on_packet(_socket.get_packet().get_string_from_utf8())
		elif state == WebSocketPeer.STATE_CLOSED:
			if is_active:
				last_error = "disconnected"
				lobby_failed.emit("Disconnected from lobby.")
			_socket = null
			is_active = false

	if not is_active:
		return

	var scene := get_tree().current_scene
	if scene != null and scene.name == "Arena" and not _arena_armed:
		_arm_arena(scene)

	if is_host and _arena_armed:
		_snap_acc += delta
		if _snap_acc >= 1.0 / SNAP_HZ:
			_snap_acc = 0.0
			_send_snapshot()

func _connect_and_send(hello: Dictionary) -> void:
	reset()
	_char_name = str(hello.get("char", _char_name))
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(_signal_url())
	if err != OK:
		last_error = "connect failed"
		lobby_failed.emit("Could not reach the lobby server.")
		_socket = null
		return
	# Wait until open then send. Polled below.
	_pending_hello = hello

var _pending_hello: Dictionary = {}

func _signal_url() -> String:
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		var origin := str(JavaScriptBridge.eval("window.location.origin || ''"))
		if origin.begins_with("https://"):
			return origin.replace("https://", "wss://") + "/signal"
		if origin.begins_with("http://"):
			return origin.replace("http://", "ws://") + "/signal"
	return "ws://127.0.0.1:8765"

func _send(payload: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(payload))

func _on_packet(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	var op := str(msg.get("op", ""))
	match op:
		"welcome":
			is_active = true
			is_host = bool(msg.get("host", false))
			local_pid = int(msg.get("pid", 0))
			code = str(msg.get("code", ""))
			lobby_ready.emit(code)
		"roster":
			roster = msg.get("players", [])
			roster_changed.emit(roster)
		"start":
			seed = int(msg.get("seed", randi()))
			if msg.has("players"):
				roster = msg.get("players", [])
			is_active = true
			match_starting.emit(seed)
		"err":
			last_error = str(msg.get("msg", "error"))
			lobby_failed.emit(last_error)
		"closed":
			lobby_failed.emit("Host left.")
			reset()
		"pose":
			_apply_pose(msg)
		"snap":
			if not is_host:
				_apply_snapshot(msg)
		"hit":
			if is_host:
				_apply_hit(int(msg.get("eid", 0)), int(msg.get("dmg", 0)))
		"hurt":
			_apply_hurt(msg)

func _arm_arena(scene: Node) -> void:
	_arena_armed = true
	_remotes.clear()
	_proxies.clear()
	var world: Node = scene.get_node_or_null("World")
	if world == null:
		world = scene
	var local := scene.get_tree().get_first_node_in_group("Player") as Player
	if local != null:
		local.set_meta("net_pid", local_pid)
	for entry in roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pid := int(entry.get("pid", 0))
		if pid == local_pid or pid == 0:
			continue
		var ghost := RemoteHunter.new()
		ghost.setup(pid, str(entry.get("char", "")))
		world.add_child(ghost)
		_remotes[pid] = ghost
		if is_host:
			ghost.damaged_net.connect(_on_remote_damaged)

func _on_remote_damaged(pid: int, hp: int) -> void:
	_send({"op": "hurt", "pid": pid, "hp": hp})

func send_pose(player: Node2D, hp: int, facing: float) -> void:
	if not is_active:
		return
	_send({
		"op": "pose",
		"pid": local_pid,
		"x": player.global_position.x,
		"y": player.global_position.y,
		"vx": (player as CharacterBody2D).velocity.x if player is CharacterBody2D else 0.0,
		"vy": (player as CharacterBody2D).velocity.y if player is CharacterBody2D else 0.0,
		"hp": hp,
		"f": facing,
	})

func _apply_pose(msg: Dictionary) -> void:
	var pid := int(msg.get("pid", 0))
	if pid == local_pid:
		return
	var ghost: RemoteHunter = _remotes.get(pid)
	if ghost == null:
		return
	ghost.apply_pose(
		Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0))),
		Vector2(float(msg.get("vx", 0.0)), float(msg.get("vy", 0.0))),
		int(msg.get("hp", 100)),
		float(msg.get("f", 0.0))
	)

func _send_snapshot() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var players: Array = []
	for node in tree.get_nodes_in_group("Player"):
		if not node is Node2D:
			continue
		var body := node as Node2D
		var pid := int(body.get_meta("net_pid", local_pid if body is Player else 0))
		if body is RemoteHunter:
			pid = (body as RemoteHunter).net_pid
		var health := body.get_node_or_null("HealthComponent") as HealthComponent
		var vel := (body as CharacterBody2D).velocity if body is CharacterBody2D else Vector2.ZERO
		players.append([
			pid,
			snapped(body.global_position.x, 0.1),
			snapped(body.global_position.y, 0.1),
			snapped(vel.x, 1.0),
			snapped(vel.y, 1.0),
			health.current_health if health != null else 0,
		])
	var enemies: Array = []
	for node in tree.get_nodes_in_group("Enemy"):
		if not node is Enemy:
			continue
		var enemy := node as Enemy
		if not enemy.is_physics_processing() and not enemy.visible:
			continue
		if enemy.net_id == 0:
			enemy.net_id = take_enemy_id()
		var hp := enemy.get_node_or_null("HealthComponent") as HealthComponent
		if hp != null and hp.is_dead:
			continue
		var sheet := ""
		if enemy.data != null:
			sheet = enemy.data.sprite_sheet_path
			if sheet.is_empty() and enemy.data.sprite_sheet != null:
				sheet = enemy.data.sprite_sheet.resource_path
		enemies.append([
			enemy.net_id,
			snapped(enemy.global_position.x, 0.1),
			snapped(enemy.global_position.y, 0.1),
			hp.current_health if hp != null else 0,
			sheet,
		])
	_send({"op": "snap", "pl": players, "en": enemies})

func _apply_snapshot(msg: Dictionary) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	for row in msg.get("pl", []):
		if typeof(row) != TYPE_ARRAY or row.size() < 6:
			continue
		var pid := int(row[0])
		if pid == local_pid:
			continue
		var ghost: RemoteHunter = _remotes.get(pid)
		if ghost != null:
			ghost.apply_pose(Vector2(float(row[1]), float(row[2])), Vector2(float(row[3]), float(row[4])), int(row[5]), 0.0)
	var seen: Dictionary = {}
	var world: Node = tree.current_scene.get_node_or_null("World")
	if world == null:
		world = tree.current_scene
	for row in msg.get("en", []):
		if typeof(row) != TYPE_ARRAY or row.size() < 5:
			continue
		var eid := int(row[0])
		seen[eid] = true
		var proxy: EnemyProxy = _proxies.get(eid)
		if proxy == null:
			proxy = EnemyProxy.new()
			proxy.net_id = eid
			world.add_child(proxy)
			_proxies[eid] = proxy
		proxy.apply_pose(Vector2(float(row[1]), float(row[2])), int(row[3]), str(row[4]))
	var drop: Array = []
	for eid in _proxies.keys():
		if not seen.has(eid):
			drop.append(eid)
	for eid in drop:
		var node: EnemyProxy = _proxies[eid]
		_proxies.erase(eid)
		if is_instance_valid(node):
			node.queue_free()

func _apply_hit(eid: int, amount: int) -> void:
	if amount <= 0:
		return
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("Enemy"):
		if node is Enemy and (node as Enemy).net_id == eid:
			var health := node.get_node_or_null("HealthComponent") as HealthComponent
			if health != null:
				health.take_damage(amount, null)
			return

func _apply_hurt(msg: Dictionary) -> void:
	if int(msg.get("pid", 0)) != local_pid:
		return
	var player := get_tree().get_first_node_in_group("Player") as Player
	if player == null:
		return
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return
	var hp := int(msg.get("hp", health.current_health))
	if hp < health.current_health:
		health.take_damage(health.current_health - hp, null)
