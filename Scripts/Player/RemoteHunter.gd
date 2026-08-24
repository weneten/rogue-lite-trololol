extends CharacterBody2D
class_name RemoteHunter

signal damaged_net(pid: int, hp: int)

var net_pid: int = 0
var _health: HealthComponent
var _sprite: AnimatedSprite2D
var _animator: EnemySpriteAnimator
var _shape: CollisionShape2D
var _visuals: Array[WeaponVisual] = []
var _loadout_key: String = ""

const SLOT_SPACING := 0.32
const WEAPON_DIR := "res://Resources/WeaponData/Data/"
static var _weapon_by_name: Dictionary = {}

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
	var starters: Array = []
	for weapon_data in data.starting_weapons:
		if weapon_data != null:
			_weapon_by_name[weapon_data.name] = weapon_data
			starters.append(weapon_data.name)
	sync_loadout(starters)

func apply_body(pos: Vector2, vel: Vector2, hp: int) -> void:
	global_position = pos
	velocity = vel
	if _health != null and hp >= 0:
		_health.current_health = hp
		_health.is_dead = hp <= 0
		collision_layer = 0 if _health.is_dead else 2
		if _shape != null:
			_shape.disabled = _health.is_dead

func apply_pose(pos: Vector2, vel: Vector2, hp: int, facing: float, aim: float = 0.0, has_target: bool = false, swinging: bool = false) -> void:
	apply_body(pos, vel, hp)
	if _animator != null:
		_animator.set_facing(facing if absf(facing) > 0.05 else vel.x)
		_animator.update_locomotion(vel.length_squared() > 40.0)
	for visual in _visuals:
		if visual != null:
			visual.set_aim(aim, has_target)
			if swinging:
				visual.play_swing(0)

func _on_wave_start(_wave_number: int) -> void:
	if _health != null:
		_health.revive(_health.max_health)
	collision_layer = 2
	if _shape != null:
		_shape.disabled = false
	if _animator != null:
		_animator.reset_visual()

func sync_loadout(weapon_names: Array) -> void:
	var key := ",".join(PackedStringArray(weapon_names))
	if key == _loadout_key:
		return
	_loadout_key = key
	for visual in _visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	_visuals.clear()
	var total: int = 0
	for raw in weapon_names:
		var data := _weapon_named(str(raw))
		if data != null and (data.weapon_class & WeaponData.WeaponClass.SUMMON) == 0:
			total += 1
	var index := 0
	for raw in weapon_names:
		var data := _weapon_named(str(raw))
		if data == null or (data.weapon_class & WeaponData.WeaponClass.SUMMON) != 0:
			continue
		var visual := WeaponVisual.new()
		visual.name = "WeaponVisual_%s" % data.name
		visual.slot_offset = (float(index) - float(total - 1) * 0.5) * SLOT_SPACING
		visual.setup(data)
		add_child(visual)
		_visuals.append(visual)
		index += 1

static func _weapon_named(weapon_name: String) -> WeaponData:
	_ensure_weapon_catalog()
	return _weapon_by_name.get(weapon_name) as WeaponData

static func _ensure_weapon_catalog() -> void:
	if not _weapon_by_name.is_empty():
		return
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres") or file.ends_with(".res"):
			var data := load(WEAPON_DIR + file) as WeaponData
			if data != null and not data.name.is_empty():
				_weapon_by_name[data.name] = data
		file = dir.get_next()
	dir.list_dir_end()

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
