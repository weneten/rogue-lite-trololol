extends CharacterBody2D
class_name RemoteHunter

signal damaged_net(pid: int, hp: int)

var net_pid: int = 0
var _health: HealthComponent
var _sprite: AnimatedSprite2D
var _animator: EnemySpriteAnimator
var _shape: CollisionShape2D

func setup(pid: int, character_name: String) -> void:
	net_pid = pid
	name = "RemoteHunter_%d" % pid
	collision_layer = 2
	collision_mask = 1
	add_to_group("Player")
	set_meta("net_pid", pid)

	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	_shape.shape = circle
	add_child(_shape)

	if EventBus != null:
		EventBus.wave_start.connect(_on_wave_start)

	_health = HealthComponent.new()
	_health.name = "HealthComponent"
	_health.max_health = 100
	add_child(_health)
	_health.damaged.connect(_on_damaged)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	add_child(_sprite)

	_animator = EnemySpriteAnimator.new()
	_animator.name = "SpriteAnimator"
	_animator.sprite_path = NodePath("../Sprite")
	add_child(_animator)

	_apply_character(character_name)

func _apply_character(character_name: String) -> void:
	var data := _load_character(character_name)
	if data == null:
		return
	_health.max_health = data.max_health
	_health.revive(data.max_health)
	if _animator != null:
		_animator.configure(
			data.sprite_sheet_path,
			data.sprite_json_path,
			"",
			data.sprite_scale if data.sprite_scale > 0.0 else 1.0,
			Color.WHITE,
			data.sprite_sheet
		)

func apply_pose(pos: Vector2, vel: Vector2, hp: int, _facing: float) -> void:
	global_position = pos
	velocity = vel
	if _animator != null:
		_animator.set_facing(vel.x)
		_animator.update_locomotion(vel.length_squared() > 40.0)
	if _health != null and hp >= 0:
		_health.current_health = hp
		_health.is_dead = hp <= 0
		collision_layer = 0 if _health.is_dead else 2
		if _shape != null:
			_shape.disabled = _health.is_dead

func _on_wave_start(_wave_number: int) -> void:
	if _health != null:
		_health.revive(_health.max_health)
	collision_layer = 2
	if _shape != null:
		_shape.disabled = false
	if _animator != null:
		_animator.reset_visual()

func _on_damaged(_amount: int, _source: Node) -> void:
	if _health != null:
		damaged_net.emit(net_pid, _health.current_health)

static func _load_character(character_name: String) -> CharacterData:
	const PATHS: Array[String] = [
		"res://Resources/CharacterData/Data/WitchHunter.tres",
		"res://Resources/CharacterData/Data/TheReaper.tres",
		"res://Resources/CharacterData/Data/SilverPriest.tres",
		"res://Resources/CharacterData/Data/Bloodletter.tres",
		"res://Resources/CharacterData/Data/BloodstainedCrusader.tres",
		"res://Resources/CharacterData/Data/Pyromancer.tres",
		"res://Resources/CharacterData/Data/GraveWarden.tres",
		"res://Resources/CharacterData/Data/MoonlitDuelist.tres",
		"res://Resources/CharacterData/Data/Alchemist.tres",
		"res://Resources/CharacterData/Data/CursedNoble.tres",
	]
	for path in PATHS:
		if not ResourceLoader.exists(path):
			continue
		var data := load(path) as CharacterData
		if data != null and data.character_name == character_name:
			return data
	return null
