extends Area2D
class_name XpGem

# The drop every enemy leaves behind: a soul shard veined with gold.
#
# One pickup carries both halves of a kill's reward — experience and coin — so
# the player has a single thing to chase rather than two overlapping ones.
# Neither is banked until it is actually collected, which is what makes moving
# toward danger worth doing.
#
# Pooled; see MaterialDropSpawner.

const STRIP_PATH := "res://Assets/sprites/arena/pickup.png"
const FRAME_SIZE := 16
const FRAME_COUNT := 4

@export var attract_radius: float = 150.0
@export var attract_speed: float = 620.0
@export var collect_radius: float = 18.0
@export var frames_per_second: float = 8.0

var _xp_value: int
var _currency_value: int
var _pool
var _active: bool
var _anim_time: float = 0.0
var _sprite: Sprite2D
var _atlas: AtlasTexture

static var _strip: Texture2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_build_sprite()

# Swaps the placeholder polygon for the pixel shard the art pipeline emits.
func _build_sprite() -> void:
	var placeholder = get_node_or_null("Sprite")
	if placeholder != null and not (placeholder is Sprite2D):
		placeholder.queue_free()

	if _strip == null:
		_strip = _load_strip()

	if _strip == null:
		return

	_atlas = AtlasTexture.new()
	_atlas.atlas = _strip
	_atlas.region = Rect2(0, 0, FRAME_SIZE, FRAME_SIZE)
	_atlas.filter_clip = true

	_sprite = Sprite2D.new()
	_sprite.name = "Shard"
	_sprite.texture = _atlas
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * 2.0
	add_child(_sprite)

static func _load_strip() -> Texture2D:
	if ResourceLoader.exists(STRIP_PATH):
		var texture = ResourceLoader.load(STRIP_PATH, "Texture2D") as Texture2D
		if texture != null:
			return texture

	if not FileAccess.file_exists(STRIP_PATH):
		return null

	var image = Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(STRIP_PATH)) != OK:
		return null

	return ImageTexture.create_from_image(image)

# Arms this pooled instance with the reward the kill was worth.
func launch(position: Vector2, xp_value: int, currency_value: int, pool) -> void:
	global_position = position
	_xp_value = xp_value
	_currency_value = currency_value
	_pool = pool
	_active = true
	_anim_time = randf() * 1.0  # de-sync the bob across a pile of drops

func _physics_process(delta: float) -> void:
	if not _active:
		return

	_anim_time += delta
	if _atlas != null:
		var frame = int(_anim_time * frames_per_second) % FRAME_COUNT
		_atlas.region = Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	# Magnetise once the player is close, accelerating as it closes so the
	# last stretch snaps in rather than crawling.
	var distance = global_position.distance_to(player.global_position)

	# Collect on proximity rather than on body_entered alone. A pooled shard
	# re-armed while already overlapping the player never emits an enter
	# signal, so shards were piling up under their feet uncollected.
	if distance <= collect_radius:
		_collect()
		return

	if distance <= attract_radius:
		var pull = attract_speed * (1.0 + (1.0 - distance / attract_radius) * 1.5)
		global_position = global_position.move_toward(player.global_position, pull * delta)

func _on_body_entered(body: Node2D) -> void:
	if _active and body.is_in_group("Player"):
		_collect()

func _collect() -> void:
	if not _active:
		return

	_active = false  # guard: proximity and body_entered can both fire this frame

	if _xp_value > 0 and PlayerStats.instance != null:
		PlayerStats.instance.add_xp(_xp_value)

	if _currency_value > 0 and GameManager != null:
		GameManager.add_currency(_currency_value)

	AudioManager.play_sfx("pickup_material")
	_despawn()

func _despawn() -> void:
	_active = false
	if _pool:
		_pool.return_instance(self)

func on_spawn() -> void:
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)

func on_despawn() -> void:
	_active = false
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)
