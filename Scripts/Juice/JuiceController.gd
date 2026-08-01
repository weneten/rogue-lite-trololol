extends Node
class_name JuiceController

# Central combat-juice hub. Listens to EventBus only — keeps Player/Enemy/Weapon/HealthComponent
# free of VFX side-effects so parallel stages can own those files. Owns ScreenShake, HitStop,
# pooled DamageNumber popups, and hit-flash modulation on damaged targets.

@export_group("Scenes")
@export var damage_number_scene: PackedScene
@export var damage_number_pool_prewarm: int = 24

@export_group("Player Hit")
@export var player_hit_trauma_per_damage: float = 0.03
@export var player_hit_trauma_min: float = 0.18
@export var player_hit_trauma_max: float = 0.65

@export_group("Outgoing Hits")
# Damage >= this uses stronger flash/number color (NOT hitstop by default).
@export var big_hit_threshold: int = 35
@export var big_hit_trauma: float = 0.12
# Hitstop only when damage reaches this AND cooldown elapsed. Keep high — per-hit freeze feels awful.
@export var hit_stop_damage_threshold: int = 80
@export var hit_stop_seconds: float = 0.03
@export var hit_stop_cooldown_seconds: float = 0.45
@export var enable_hit_stop: bool = false
@export var hit_flash_seconds: float = 0.06
@export var normal_damage_color: Color = Color(1.0, 0.92, 0.85, 1.0)
@export var big_damage_color: Color = Color(1.0, 0.78, 0.25, 1.0)
@export var flash_modulate: Color = Color(1.8, 1.8, 1.8, 1.0)

var _shake: ScreenShake
var _hit_stop: HitStop
var _damage_number_pool
var _player: Node2D
var _bound_camera: bool
var _hit_stop_cooldown_remaining: float

func _ready() -> void:
	# Recover if a previous session left TimeScale stuck low after hitstop spam.
	if Engine.time_scale < 0.99:
		Engine.time_scale = 1.0

	_shake = ScreenShake.new()
	_shake.name = "ScreenShake"
	add_child(_shake)

	_hit_stop = HitStop.new()
	_hit_stop.name = "HitStop"
	add_child(_hit_stop)

	# Draw culling lives as a sibling helper under this hub so Arena only needs one juice node.
	var culler = OffscreenCuller.new()
	culler.name = "OffscreenCuller"
	add_child(culler)

	damage_number_scene = damage_number_scene if damage_number_scene != null else load("res://Scenes/Combat/DamageNumber.tscn")

	if EventBus != null:
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.player_damage_dealt.connect(_on_player_damage_dealt)
	else:
		push_warning("[JuiceController] EventBus missing; combat juice disabled.")

func _exit_tree() -> void:
	if EventBus != null:
		EventBus.player_damaged.disconnect(_on_player_damaged)
		EventBus.player_damage_dealt.disconnect(_on_player_damage_dealt)

func _process(delta: float) -> void:
	if _hit_stop_cooldown_remaining > 0:
		_hit_stop_cooldown_remaining -= delta

	# Lazy camera bind: Player may spawn after this node in Arena.tscn.
	if not _bound_camera:
		_try_bind_camera()

func _try_bind_camera() -> void:
	_player = get_tree().get_first_node_in_group("Player") as Node2D
	if _player == null:
		return

	var cam = _player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return

	_shake.bind(cam)
	_bound_camera = true

func _on_player_damaged(damage_amount: float, current_health: float) -> void:
	if not _bound_camera:
		_try_bind_camera()

	var trauma = clampf(
		player_hit_trauma_min + damage_amount * player_hit_trauma_per_damage,
		player_hit_trauma_min,
		player_hit_trauma_max)
	_shake.add_trauma(trauma)

func _on_player_damage_dealt(target: Node, amount: int) -> void:
	if amount <= 0 or target == null or not is_instance_valid(target):
		return

	var big_hit = amount >= big_hit_threshold
	var pos = _resolve_world_position(target)

	_spawn_damage_number(pos, amount, big_damage_color if big_hit else normal_damage_color)
	_flash_target(target)

	if big_hit:
		if not _bound_camera:
			_try_bind_camera()

		# Light shake only — no TimeScale freeze on normal combat hits.
		_shake.add_trauma(big_hit_trauma * 0.55)

	# Hitstop OFF by default. When enabled, rare + cooldown so multi-cleave doesn't stutter.
	if enable_hit_stop \
		and amount >= hit_stop_damage_threshold \
		and _hit_stop_cooldown_remaining <= 0 \
		and hit_stop_seconds > 0.0:
		_hit_stop.freeze(hit_stop_seconds, 0.35)
		_hit_stop_cooldown_remaining = hit_stop_cooldown_seconds

func _spawn_damage_number(world_pos: Vector2, amount: int, color: Color) -> void:
	if damage_number_scene == null:
		return

	if _damage_number_pool == null:
		var container = get_tree().current_scene if get_tree().current_scene != null else self
		_damage_number_pool = ObjectPool.new(
			damage_number_scene,
			container,
			damage_number_pool_prewarm)

	var popup = _damage_number_pool.acquire()
	popup.show_at(world_pos, amount, color, _damage_number_pool)

func _flash_target(target: Node) -> void:
	var sprite = _find_flashable_sprite(target)
	if sprite == null:
		return

	var original = sprite.modulate
	sprite.modulate = flash_modulate

	var timer = get_tree().create_timer(hit_flash_seconds, true, true)
	await timer.timeout

	if is_instance_valid(sprite):
		sprite.modulate = original

static func _find_flashable_sprite(target: Node) -> CanvasItem:
	# Prefer an explicit "Sprite" child (AnimatedSprite2D / Polygon2D / Sprite2D).
	var sprite = target.get_node_or_null("Sprite") as CanvasItem
	if sprite != null:
		return sprite

	for child in target.get_children():
		if child is AnimatedSprite2D or child is Polygon2D or child is Sprite2D:
			return child as CanvasItem

	return target as CanvasItem

static func _resolve_world_position(target: Node) -> Vector2:
	if target is Node2D:
		return target.global_position

	# HealthComponent etc. live as children — climb to nearest Node2D ancestor.
	var current = target.get_parent()
	while current != null:
		if current is Node2D:
			return current.global_position

		current = current.get_parent()

	return Vector2.ZERO
