extends CharacterBody2D

class_name Player

# 8-directional top-down player controller. Movement is pure input->velocity (no
# acceleration/friction yet — stage stub, tune once real art/animation exists).
# Bridges its HealthComponent to the global EventBus so UI/GameManager/AudioManager
# (which only know about EventBus, not this node) react to player damage/death.

@export var move_speed: float = 300.0

@export_group("Dash")
# A roll, not a blink. He travels at this multiple of his own speed — so a fast
# Hunter rolls further than a slow one — for exactly as long as the dash row on
# his sheet runs, and nothing can touch him for that window. Tying the i-frames
# to the animation rather than to a number here is the whole point: what the
# player sees is the rule.
# Shortens the roll by covering less ground rather than by ending sooner: the
# i-frames are the animation, so cutting the duration would quietly cut the
# invulnerability with it. At the default 300 speed this is ~135px of travel.
@export var dash_speed_multiplier: float = 1.8
# Measured from the moment the roll ends, not from the moment it starts, so this
# really is the gap between one dash and the next. Long enough that a dash is a
# decision about one attack rather than a second movement key.
@export var dash_cooldown: float = 5.0

# Used when the Hunter has no sheet at all (procedural skin) or a sheet without
# a dash row. Every authored Hunter sheet runs 4 frames at 16 fps, which is this.
const DASH_FALLBACK_SECONDS := 0.25

# Character
# Wired in the editor for quick standalone testing of Arena.tscn; in the normal flow
# this is left null and GameManager.selected_character (set by CharacterSelect) is used
# instead. If neither is set, Player keeps whatever defaults are already authored on the scene.
@export var character_data: CharacterData

# Wiring
@export var health_component_path: NodePath
@export var camera_path: NodePath
@export var player_stats_path: NodePath
@export var sprite_node_path: NodePath
@export var sprite_animator_path: NodePath
# Placeholder diamond shown for Hunters whose CharacterData has no sprite sheet
# (or when the sheet fails to load) so the player is never invisible.
@export var fallback_polygon_path: NodePath

# Debug
# Stage-2 verification hook: press the "debug_damage_test" action (T) to self-damage
# and confirm HealthComponent -> EventBus.OnPlayerDamaged/OnPlayerDied wiring works
# end-to-end without needing enemies yet. TODO: disable/remove once real combat lands.
@export var enable_debug_damage_key: bool = true
@export var debug_damage_amount: int = 10

var _health: HealthComponent
var _camera: Camera2D
var _stats: PlayerStats
var _animated_sprite: AnimatedSprite2D
var _sprite_animator: EnemySpriteAnimator
var _fallback_polygon: Node2D
var _procedural_sprite: Sprite2D
var _body_shape: CollisionShape2D

var _dash_remaining: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
# Last direction actually held. A dash pressed while standing still goes this
# way rather than nowhere, which is what makes it usable as a retreat.
var _facing_direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	# Lets Enemy.cs (and anything else) find the player via GetFirstNodeInGroup instead of
	# holding a direct scene reference, mirroring how Weapon/Projectile target the "Enemy" group.
	add_to_group("Player")

	_health = get_node_or_null(health_component_path)
	_camera = get_node_or_null(camera_path)
	_stats = get_node_or_null(player_stats_path)
	_animated_sprite = get_node_or_null(sprite_node_path)
	_sprite_animator = get_node_or_null(sprite_animator_path)
	_fallback_polygon = get_node_or_null(fallback_polygon_path)

	if _health != null:
		_health.damaged.connect(on_health_damaged)
		_health.died.connect(on_health_died)
		_health.health_changed.connect(on_health_changed)
	else:
		push_warning("[Player] HealthComponentPath not wired; player is invulnerable.")

	if _camera != null:
		_camera.make_current()

	_body_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if EventBus != null:
		EventBus.wave_start.connect(_on_wave_start)

	# Deferred: adding weapons/passives to this node from inside _ready is
	# rejected in Godot 4.7 ("parent is busy setting up children").
	apply_character_data.call_deferred()

# Configures stats/loadout/passive from the Hunter chosen at CharacterSelect (falls back to
# GameManager.selected_character, then to whatever CharacterData is wired in the
# editor). If neither is set, the Player keeps whatever defaults are already authored on the
# scene (MoveSpeed/HealthComponent.MaxHealth/starting Weapon child) — lets Arena.tscn still be
# run standalone for quick testing without going through CharacterSelect first.
func apply_character_data() -> void:
	var data: CharacterData = character_data if character_data != null else GameManager.selected_character
	if data == null:
		# Arena.tscn run standalone (see the note above): no Hunter was picked,
		# so the scene's own defaults stand. The difficulty still has to reach
		# them, or a hard run started from the admin panel is quietly a normal
		# one with a hard label on it.
		apply_run_difficulty(_health.max_health if _health != null else 100)
		return

	move_speed = data.move_speed
	apply_character_visual(data)

	if _health != null:
		_health.armor = data.starting_armor
		_health.dodge_chance = data.starting_dodge_chance

	apply_run_difficulty(data.max_health)

	if _stats != null:
		_stats.apply_extra_crit(data.starting_crit_chance, 0.0)
		_stats.set_magic_damage_multiplier(data.starting_magic_power)
		# Luck is a real stat now (shop rarity, and the Jester's whole wheel), so a
		# Hunter authored with a Luck baseline actually starts with it.
		_stats.apply_luck(data.starting_luck)

	# Replaces whatever Weapon.tscn child was hardcoded on Player.tscn (e.g. the default
	# RustyScythe) with this Hunter's own loadout instead of stacking on top of it.
	if WeaponInventory.instance != null:
		WeaponInventory.instance.clear_all_weapons()
		for weapon_data in data.starting_weapons:
			WeaponInventory.instance.try_add_weapon(weapon_data)

	if not data.passive_id.is_empty():
		var passive: PassiveAbility = PassiveAbilityFactory.create(data.passive_id)
		if passive != null:
			add_child(passive)
			passive.setup(self, _stats, _health, data)
			if _stats != null:
				_stats.active_passive = passive
		else:
			push_warning("[Player] Unknown PassiveId '%s' on CharacterData '%s'." % [data.passive_id, data.character_name])

# Publishes the Hunter's starting speed and applies the run difficulty's cut of
# their health and damage. Separate from apply_character_data because a
# standalone Arena run has no CharacterData but still has a difficulty.
func apply_run_difficulty(base_max_health: int) -> void:
	# Published before anything spawns: "Dark is the Night" pegs enemy speed to
	# the Hunter's, and enemies ask GameManager, not the Player node.
	GameManager.player_base_speed = move_speed

	var difficulty: int = GameManager.difficulty
	if _health != null:
		var max_hp: int = maxi(1, roundi(base_max_health * Difficulty.player_health_multiplier(difficulty)))
		_health.max_health = max_hp
		_health.revive(max_hp)

	if _stats != null:
		_stats.difficulty_damage_multiplier = Difficulty.player_damage_multiplier(difficulty)

# Swaps in this Hunter's sprite sheet (same Assets/sprites JSON+PNG pipeline the enemies use,
# hence the shared EnemySpriteAnimator). Hunters without a sheet — or a sheet that fails to
# load — keep the placeholder polygon instead of turning invisible.
func apply_character_visual(data: CharacterData) -> void:
	var sheet_path: String = data.sprite_sheet_path
	if sheet_path.is_empty() and data.sprite_sheet != null:
		sheet_path = data.sprite_sheet.resource_path

	var wants_sheet: bool = data.sprite_sheet != null or not sheet_path.is_empty()
	var sheet_ok: bool = false

	if wants_sheet and _sprite_animator != null:
		# Empty attack anim on purpose: Hunter sheets have no attack row and the
		# body never plays one. CharacterData.attack_anim_name is left in place
		# for tooling but is deliberately not passed through.
		sheet_ok = _sprite_animator.configure(
			sheet_path,
			data.sprite_json_path,
			"",
			data.sprite_scale if data.sprite_scale > 0.0 else 1.0,
			Color.WHITE,
			data.sprite_sheet)

	if _animated_sprite != null:
		_animated_sprite.visible = sheet_ok

	if _fallback_polygon != null:
		_fallback_polygon.visible = false

	if not sheet_ok:
		_show_procedural_skin(data.character_name)
	elif _procedural_sprite != null:
		_procedural_sprite.visible = false

	if wants_sheet and not sheet_ok:
		push_warning("[Player] Sheet failed for '%s' path='%s' — using procedural skin." % [data.character_name, sheet_path])

func _show_procedural_skin(character_name: String) -> void:
	if _procedural_sprite == null:
		_procedural_sprite = Sprite2D.new()
		_procedural_sprite.name = "ProceduralSkin"
		_procedural_sprite.centered = true
		# Matches EnemySpriteAnimator.SPRITE_Z so carried weapons and charms
		# layer the same whether the sheet loaded or the fallback is showing.
		_procedural_sprite.z_index = EnemySpriteAnimator.SPRITE_Z
		_procedural_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_procedural_sprite)

	var palette = ProceduralSprite.palette_for_name(character_name)
	_procedural_sprite.texture = ProceduralSprite.build(ProceduralSprite.Archetype.HUNTER, palette[0], palette[1], hash(character_name))
	_procedural_sprite.position.y = ProceduralSprite.anchor_y(ProceduralSprite.Archetype.HUNTER, 20.0)
	_procedural_sprite.visible = true

func _physics_process(delta: float) -> void:
	if _health != null and _health.is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)

	var effective_speed: float = move_speed * (_stats.move_speed_multiplier if _stats != null else 1.0)
	# Outside slows land after his own upgrades, so the dash carries them too:
	# a rolled escape from a warden should not be a way to ignore the warden.
	if _stats != null:
		effective_speed *= _stats.external_speed_multiplier
	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving: bool = input_direction.length_squared() > 0.01
	if moving:
		_facing_direction = input_direction.normalized()

	var was_dashing: bool = _dash_remaining > 0.0
	if was_dashing:
		# The roll commits: steering out of it mid-way would make the i-frames a
		# free 0.25s of walking anywhere rather than a read on one attack.
		_dash_remaining -= delta
		velocity = _dash_direction * effective_speed * dash_speed_multiplier
	else:
		velocity = input_direction * effective_speed

	move_and_slide()

	# Only on the frame the roll actually runs out. Closing the window every
	# frame instead would quietly cancel i-frames granted by anything else.
	var still_dashing: bool = _dash_remaining > 0.0
	if was_dashing and not still_dashing:
		end_dash()

	# The roll drives the look only while it is still running. Feeding it the
	# dash heading on the frame it ends made a standing Hunter flash one frame
	# of the run cycle before settling back to idle.
	if still_dashing:
		input_direction = _dash_direction
		moving = true

	if _sprite_animator != null:
		_sprite_animator.set_facing(input_direction.x)
		# No-op while the dash one-shot is playing, which is exactly the window
		# the roll occupies — the animator refuses to overwrite a one-shot.
		_sprite_animator.update_locomotion(moving)

	if NetSession != null and NetSession.is_active:
		var hp := _health.current_health if _health != null else 0
		NetSession.send_pose(self, hp, input_direction.x)

# Called by Weapon whenever it actually swings or fires.
#
# The Hunter has NO attack animation — the weapon plays the swing and the body
# does not. With six weapons firing at their own cooldowns the character was
# re-triggering an attack pose several times a second and spent the whole wave
# twitching; the arena reads far better when the only thing moving is the
# weapon that actually went off.
#
# All that is left is the turn: the Hunter faces what their weapons are
# hitting, which still happens while idle or running.
func on_weapon_attack(target: Node2D = null) -> void:
	if _sprite_animator == null or target == null:
		return

	_sprite_animator.set_facing(target.global_position.x - global_position.x)

func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input rather than polling: a focused Control eats the key first,
	# so Space still confirms a menu without also rolling the Hunter underneath
	# it. Menus that do not take focus pause the tree, which stops this node.
	if event.is_action_pressed("dash"):
		try_start_dash()

	if enable_debug_damage_key and event.is_action_pressed("debug_damage_test"):
		if _health != null:
			_health.take_damage(debug_damage_amount, self)

# Space. Refused while a roll is already running, while it is on cooldown, and
# while dead; nothing else blocks it.
func try_start_dash() -> void:
	if _dash_remaining > 0.0 or _dash_cooldown_remaining > 0.0:
		return

	if _health == null or _health.is_dead:
		return

	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_dash_direction = input_direction.normalized() if input_direction.length_squared() > 0.01 else _facing_direction
	_facing_direction = _dash_direction
	_dash_remaining = dash_duration()
	# Counted from the end of the roll, hence the roll's own length on top.
	_dash_cooldown_remaining = dash_cooldown + _dash_remaining
	_health.is_invulnerable = true

	if _sprite_animator != null:
		_sprite_animator.play_named("dash")

# The length of this Hunter's dash row. The i-frames are the animation, so this
# is the one number the whole feature is measured in.
func dash_duration() -> float:
	var length: float = _sprite_animator.get_animation_length("dash") if _sprite_animator != null else 0.0
	return length if length > 0.0 else DASH_FALLBACK_SECONDS

func end_dash() -> void:
	_dash_remaining = 0.0
	if _health != null:
		_health.is_invulnerable = false

# True while the roll is running. Read by UI and by anything that wants to know
# whether a hit was dodged rather than missed.
func get_is_dashing() -> bool:
	return _dash_remaining > 0.0

# 0 when the dash is ready, otherwise seconds until it is.
func get_dash_cooldown_remaining() -> float:
	return maxf(0.0, _dash_cooldown_remaining - _dash_remaining)

func on_health_damaged(amount: int, source: Node) -> void:
	if _sprite_animator != null:
		_sprite_animator.play_hurt()
	EventBus.player_damaged.emit(float(amount), float(_health.current_health))

func on_health_changed(current_health: int, max_health: int) -> void:
	# Forwards every HP change (damage, heal, or a max-HP level-up upgrade) to EventBus so
	# HUD can stay in sync without holding a direct reference to the player/HealthComponent.
	EventBus.player_health_changed.emit(current_health, max_health)

func restore_after_intermission() -> void:
	visible = true
	modulate = Color.WHITE
	if _camera != null:
		_camera.make_current()
	if _sprite_animator != null:
		_sprite_animator.reset_visual()
	elif _animated_sprite != null:
		_animated_sprite.visible = true
	if _procedural_sprite != null and _animated_sprite != null and not _animated_sprite.visible:
		_procedural_sprite.visible = true

func _on_wave_start(_wave_number: int) -> void:
	respawn_for_wave()

# Co-op: downed hunters sit out the rest of the round, then return at full HP.
func respawn_for_wave() -> void:
	# Always closed, never carried: an i-frame window left open across a wave
	# boundary would have nothing left running to shut it.
	end_dash()
	if _health != null and _health.is_dead:
		# Only a hunter who actually went down gets their dash handed back.
		# This runs for everyone on every wave_start, so clearing it here
		# unconditionally quietly refunded the cooldown between waves.
		_dash_cooldown_remaining = 0.0
		_health.revive(_health.max_health)
	collision_layer = 2
	if _body_shape != null:
		_body_shape.disabled = false
	restore_after_intermission()

func on_health_died(source: Node) -> void:
	end_dash()
	# Fire-and-forget: the death anim just needs to run out, nothing waits on it (physics is
	# already frozen above, and the game-over UI is driven by EventBus).
	collision_layer = 0
	if _body_shape != null:
		_body_shape.set_deferred("disabled", true)
	if _sprite_animator != null:
		_sprite_animator.play_death_async()
	EventBus.player_died.emit()
