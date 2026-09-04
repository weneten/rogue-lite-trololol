extends Node2D
class_name FlameEruption

# One ring of the arena floor going up. The Magus leaves the room, and the ring
# it has marked — the outer edge, the middle, or the square the Hunter is
# standing in the centre of — erupts a moment later.
#
# Rings rather than circles because the room is a rectangle and the safe ground
# has to read at a glance: "get off the outside" is a thing a player can act on
# in half a second, "get out of that ellipse" is not. The shape is defined by
# depth from the wall (FlameArena.edge_depth), so a ring hugs the corners the
# same way the room does.
#
# Purely self-driving: spawned and forgotten. The boss is not even in the room
# while these resolve, which is what lets an eruption still be going off while a
# meteor shower it queued earlier is coming down.

const WARN := Color(0.60, 0.24, 0.86, 0.24)
const WARN_EDGE := Color(0.85, 0.45, 1.0, 0.55)
const BURN := Color(0.80, 0.42, 1.0, 0.75)

# How long the fire hangs around after it lands. Long enough to see, short
# enough that four of them do not turn the room into a single lethal square.
const BURN_SECONDS := 0.55

var arena: FlameArena
var band_index: int = 0
var band_count: int = 3
var windup_seconds: float = 1.0
var damage: int = 24
var instigator: Node

var _age: float = 0.0
var _resolved: bool = false

func _ready() -> void:
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()

	if _resolved:
		if _age >= windup_seconds + BURN_SECONDS:
			queue_free()
		return

	if _age < windup_seconds:
		return

	_resolved = true
	_erupt()

func _erupt() -> void:
	if arena == null or not is_instance_valid(arena):
		return

	for node in get_tree().get_nodes_in_group("Player"):
		var body := node as Node2D
		if body == null:
			continue

		if arena.band_at(body.global_position, band_count) != band_index:
			continue

		var health: HealthComponent = body.get_node_or_null("HealthComponent")
		if health != null and not health.is_dead:
			health.take_damage(maxi(1, damage), instigator)

func _draw() -> void:
	if arena == null or not is_instance_valid(arena):
		return

	var span := arena.band_range(band_index, band_count)
	# The band is the gap between two rectangles inset from the wall. The inner
	# one collapses to nothing for the centre band, which is then a solid square
	# — the pink middle of the sketch.
	var outer := Rect2(-arena.half_extents, arena.half_extents * 2.0).grow(-span.x)
	var inner := Rect2(-arena.half_extents, arena.half_extents * 2.0).grow(-span.y)
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		inner = Rect2(outer.get_center(), Vector2.ZERO)

	var offset := arena.global_position - global_position
	outer.position += offset
	inner.position += offset

	if _resolved:
		# The hit itself: full brightness, fading out over BURN_SECONDS.
		var fade := 1.0 - clampf((_age - windup_seconds) / BURN_SECONDS, 0.0, 1.0)
		_draw_band(outer, inner, Color(BURN.r, BURN.g, BURN.b, BURN.a * fade))
		# Artwork over the wash, not instead of it: the wash is what makes the
		# ring one shape from across the room, and a ring is a thing the player
		# has to read the extent of in half a second.
		#
		# Only the eruption itself gets it. The wind-up below stays a flat decal
		# on purpose — a ring that is about to go up must not look like one that
		# already has, and the move is built on telling those apart.
		var burnt := WitchfireSheet.frame(WitchfireSheet.GROUND, _age)
		if burnt != null:
			_draw_band_tiled(outer, inner, burnt, Color(1.0, 1.0, 1.0, fade))

		return

	# Wind-up. The fill brightens toward the hit rather than pulsing, for the
	# same reason BossAoeTelegraph grows one: a decal that only flashes says
	# where but never when.
	var t := clampf(_age / maxf(0.01, windup_seconds), 0.0, 1.0)
	var heat := clampf((t - 0.82) / 0.18, 0.0, 1.0)
	_draw_band(outer, inner, Color(
		WARN.r + heat * 0.3, WARN.g, WARN.b, WARN.a + t * 0.28 + heat * 0.25))
	_draw_band_outline(outer, inner, Color(WARN_EDGE.r, WARN_EDGE.g, WARN_EDGE.b,
		WARN_EDGE.a * (0.6 + 0.4 * t)))

# The ring between two rectangles, drawn as the four rectangles left over. Godot
# has no hollow-rect primitive and a polygon with a hole would need triangulating
# for what is, on an axis-aligned band, four draw_rect calls.
func _draw_band(outer: Rect2, inner: Rect2, color: Color) -> void:
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		draw_rect(outer, color)
		return

	for rect in FlameArena.frame_rects(outer, inner):
		draw_rect(rect, color)

# The same ring, filled with burning ground. Every piece is phased on the arena
# rather than on its own rectangle, so the three rings of one eruption lie on a
# single grid and the fire does not visibly restart at each band boundary.
func _draw_band_tiled(outer: Rect2, inner: Rect2, texture: Texture2D, modulate: Color) -> void:
	var phase := arena.global_position - global_position
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		WitchfireSheet.draw_tiled(self, texture, outer, phase, 0.0, modulate, true)
		return

	for rect in FlameArena.frame_rects(outer, inner):
		WitchfireSheet.draw_tiled(self, texture, rect, phase, 0.0, modulate, true)

func _draw_band_outline(outer: Rect2, inner: Rect2, color: Color) -> void:
	draw_rect(outer, color, false, 3.0)
	if inner.size.x > 2.0 and inner.size.y > 2.0:
		draw_rect(inner, color, false, 3.0)

static func spawn(host: Node, arena: FlameArena, band_index: int, band_count: int,
	windup_seconds: float, damage: int, instigator: Node) -> FlameEruption:
	var eruption := FlameEruption.new()
	eruption.arena = arena
	eruption.band_index = band_index
	eruption.band_count = band_count
	eruption.windup_seconds = windup_seconds
	eruption.damage = damage
	eruption.instigator = instigator

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(eruption)
	eruption.global_position = arena.global_position
	return eruption
