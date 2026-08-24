extends StaticBody2D
class_name EnemyProxy

# Client-side stand-in for a host enemy. Weapons aim/hit this; damage is
# forwarded to the host. StaticBody2D so projectiles get a real physics body
# without needing a physics tick.

var net_id: int = 0
var _health: HealthComponent
var _sprite: AnimatedSprite2D
var _sheet: String = ""

func _init() -> void:
	collision_layer = 4
	collision_mask = 0

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	shape.shape = circle
	add_child(shape)

	_health = HealthComponent.new()
	_health.name = "HealthComponent"
	_health.max_health = 99999
	_health.current_health = 99999
	add_child(_health)
	_health.damaged.connect(_on_damaged)

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 2
	add_child(_sprite)

func _enter_tree() -> void:
	name = "EnemyProxy_%d" % net_id
	add_to_group("Enemy")
	visible = true
	collision_layer = 4

func apply_pose(pos: Vector2, hp: int, sheet_path: String, draw_scale: float = 2.0) -> void:
	global_position = pos
	if _health != null:
		_health.current_health = maxi(1, hp)
		_health.is_dead = false
	if _sprite != null and draw_scale > 0.0:
		_sprite.scale = Vector2.ONE * draw_scale
	if sheet_path != _sheet and not sheet_path.is_empty():
		_sheet = sheet_path
		_apply_sheet(sheet_path)

func _apply_sheet(path: String) -> void:
	if _sprite == null:
		return
	var frames := SpriteSheetCache.get_frames(path)
	if frames == null:
		return
	_sprite.sprite_frames = frames
	_sprite.offset = SpriteSheetCache.get_sprite_offset(path)
	if frames.has_animation("idle"):
		_sprite.play("idle")
	elif frames.get_animation_names().size() > 0:
		_sprite.play(frames.get_animation_names()[0])

func _on_damaged(amount: int, _source: Node) -> void:
	if NetSession != null:
		NetSession.send_hit(net_id, amount)
