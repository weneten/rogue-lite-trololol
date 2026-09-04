extends Node2D
class_name FlameArena

# The ring of witchfire the Magus throws up when the fight opens: a rectangle of
# floor with a wall of purple flame around every side of it.
#
# The world is a torus with no walls anywhere (see ArenaLoop), which is exactly
# why this is a spawned object rather than level geometry. There is nothing in
# the world to fight inside, so the boss brings its own room and takes it away
# with it. Crossing the flame is not a soft nudge back: it is the most damaging
# thing on the field, and the Hunter is pushed clear so a mistake costs a wound
# rather than becoming a death by grinding.
#
# Everything the fight needs to ask about the room goes through here — where a
# meteor may land, which ring is about to erupt, whether the boss has drifted
# out of its own arena — so the geometry is written down once.

# How thick the wall of fire is, drawn outward from the play rectangle.
const BORDER := 46.0

# One flame tongue roughly every this many pixels along an edge.
const TONGUE_SPACING := 34.0

# Standing in the fire hurts on this clock rather than per frame; a per-frame
# tick at any damage worth the name is instant death at 60fps.
const BURN_INTERVAL := 0.45

const FLAME_CORE := Color(0.72, 0.36, 0.95, 0.92)
const FLAME_EDGE := Color(0.33, 0.10, 0.52, 0.85)
const SCORCH := Color(0.06, 0.02, 0.09, 0.55)

const GROUP := &"FlameArena"

# Half width/height of the *playable* floor. The fire sits outside this.
var half_extents: Vector2 = Vector2(620.0, 350.0)

var border_damage: int = 34
var instigator: Node

var _burn_cooldown: float = 0.0
var _time: float = 0.0
# One phase offset per tongue so the wall flickers instead of pulsing as a unit.
var _tongue_seeds: Array[float] = []

func _ready() -> void:
	# Under the characters, over the floor — the layer boss telegraphs use.
	z_index = -1
	# The wall is pixel art now; filtering it would soften exactly the edges the
	# rest of the game keeps hard.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Findable by anything that places things on the floor. DarkMages is the one
	# that has to care: it keeps planting wardens through a boss fight by design.
	add_to_group(GROUP)
	_seed_tongues()

# The live arena, or null when the fight is in the open. Only ever one.
static func active(tree: SceneTree) -> FlameArena:
	if tree == null:
		return null

	return tree.get_first_node_in_group(GROUP) as FlameArena

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _physics_process(delta: float) -> void:
	_burn_cooldown -= delta

	# The count-in freezes the arena for everyone else; a wall that kept burning
	# through it would be the one thing on the field still taking swings.
	if WaveManager != null and WaveManager.is_preparing:
		return

	var player := _live_player()
	if player == null:
		return

	if contains(player.global_position):
		return

	# Out is out: pushed back to just inside the line before the burn lands, so
	# the punishment is one tick rather than one tick per half second until they
	# find their way home.
	player.global_position = clamp_point(player.global_position, 12.0)

	if _burn_cooldown > 0.0:
		return

	_burn_cooldown = BURN_INTERVAL
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health != null and not health.is_dead:
		health.take_damage(maxi(1, border_damage), instigator)

# ------------------------------------------------------------------ geometry

func contains(point: Vector2) -> bool:
	var d := point - global_position
	return absf(d.x) <= half_extents.x and absf(d.y) <= half_extents.y

# The nearest point at least `margin` inside the fire.
func clamp_point(point: Vector2, margin: float = 24.0) -> Vector2:
	var limit := Vector2(maxf(8.0, half_extents.x - margin), maxf(8.0, half_extents.y - margin))
	var d := point - global_position
	return global_position + Vector2(clampf(d.x, -limit.x, limit.x), clampf(d.y, -limit.y, limit.y))

# Somewhere on the floor, never right up against the fire — a meteor dropped on
# the line would be undodgeable in the only direction that is not lethal.
func random_point(margin: float = 90.0) -> Vector2:
	var limit := Vector2(maxf(8.0, half_extents.x - margin), maxf(8.0, half_extents.y - margin))
	return global_position + Vector2(randf_range(-limit.x, limit.x), randf_range(-limit.y, limit.y))

# How far a point is from the nearest wall, in pixels. Negative outside.
# This is what makes the eruption rings rectangular rather than circular: every
# point at the same depth is in the same ring, whichever wall it is nearest.
func edge_depth(point: Vector2) -> float:
	var d := point - global_position
	return minf(half_extents.x - absf(d.x), half_extents.y - absf(d.y))

# Which of `band_count` nested rings a point sits in, 0 being the outermost.
func band_at(point: Vector2, band_count: int) -> int:
	if band_count <= 1:
		return 0

	var step := minf(half_extents.x, half_extents.y) / float(band_count)
	return clampi(int(maxf(0.0, edge_depth(point)) / step), 0, band_count - 1)

# The inset depths (from, to) of one ring, for drawing it.
func band_range(index: int, band_count: int) -> Vector2:
	var step := minf(half_extents.x, half_extents.y) / float(maxi(1, band_count))
	return Vector2(index * step, (index + 1) * step)

# ---------------------------------------------------------------- appearance

func _seed_tongues() -> void:
	_tongue_seeds.clear()
	var total := int((half_extents.x + half_extents.y) * 4.0 / TONGUE_SPACING) + 8
	for i in range(total):
		_tongue_seeds.append(randf() * TAU)

func _draw() -> void:
	var inner := Rect2(-half_extents, half_extents * 2.0)
	var outer := inner.grow(BORDER)

	# Scorched ground under the fire, so the wall has a footprint on the floor
	# instead of looking like it is hovering.
	for band in frame_rects(outer, inner):
		draw_rect(band, SCORCH)

	if WitchfireSheet.ready():
		_draw_sheet_walls(inner)
		return

	_draw_polygon_walls(inner)

# One curtain per side, rotated so its flame leans out of the room. The sheet's
# floor line goes on the wall line itself: fire outward into the band the arena
# burns, scorch inward onto the floor the Hunter is standing on, which is what
# a wall of fire does to the ground it borders.
func _draw_sheet_walls(inner: Rect2) -> void:
	var texture := WitchfireSheet.frame(WitchfireSheet.CURTAIN, _time)
	if texture == null:
		_draw_polygon_walls(inner)
		return

	var cell := WitchfireSheet.cell()
	var floor_y := WitchfireSheet.floor_y()

	for edge in _edges(inner):
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var normal: Vector2 = edge[2]
		var span := from.distance_to(to)
		# The top and bottom walls are run out over the corners so the four
		# sides close into a ring. Without it each corner is a notch of unburnt
		# floor exactly where a Hunter fleeing a sweep ends up.
		var overhang := BORDER if absf(normal.y) > absf(normal.x) else 0.0

		# Local x runs along the wall, local -y is out of the room, so the
		# curtain is drawn upright in a frame where "up" means "outward".
		draw_set_transform((from + to) * 0.5, normal.angle() + PI * 0.5, Vector2.ONE)
		WitchfireSheet.draw_tiled(self, texture,
			Rect2(-span * 0.5 - overhang, -floor_y, span + overhang * 2.0, cell),
			# Phased off the wall's own middle so both halves of a side share
			# one grid and the pattern does not step at the centre.
			Vector2(-span * 0.5, -floor_y), cell)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# What the wall looked like before there was artwork, kept for when there is
# none: a hazard the player is being told to stand clear of must never be
# invisible because a file failed to load.
func _draw_polygon_walls(inner: Rect2) -> void:
	var seed_index := 0
	for edge in _edges(inner):
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var normal: Vector2 = edge[2]
		var span := from.distance_to(to)
		var steps := maxi(2, int(span / TONGUE_SPACING))
		var along := (to - from) / float(steps)
		var side := along.normalized()

		for i in range(steps):
			var base := from + along * (float(i) + 0.5)
			var phase: float = _tongue_seeds[seed_index % _tongue_seeds.size()]
			seed_index += 1
			# Two sines of different periods: a tongue that rises and falls on
			# one reads as a machine, not as fire.
			var lick := 0.55 + 0.3 * sin(_time * 6.5 + phase) + 0.15 * sin(_time * 11.0 + phase * 2.0)
			var height := BORDER * (0.55 + 0.75 * lick)
			var width := TONGUE_SPACING * 0.62

			draw_colored_polygon(PackedVector2Array([
				base - side * width * 0.5,
				base + side * width * 0.5,
				base + normal * height,
			]), FLAME_EDGE)
			draw_colored_polygon(PackedVector2Array([
				base - side * width * 0.26,
				base + side * width * 0.26,
				base + normal * height * 0.62,
			]), FLAME_CORE)

# The four sides of the play rectangle as (from, to, outward normal).
static func _edges(inner: Rect2) -> Array:
	var tl := inner.position
	var tr := Vector2(inner.end.x, inner.position.y)
	var br := inner.end
	var bl := Vector2(inner.position.x, inner.end.y)
	return [
		[tl, tr, Vector2.UP],
		[br, bl, Vector2.DOWN],
		[bl, tl, Vector2.LEFT],
		[tr, br, Vector2.RIGHT],
	]

# The four rectangles making up the frame between `outer` and `inner`. Public
# because FlameEruption draws its rings out of exactly the same four pieces.
static func frame_rects(outer: Rect2, inner: Rect2) -> Array:
	return [
		Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)),
		Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)),
		Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)),
		Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)),
	]

func _live_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("Player"):
		var body := node as Node2D
		if body == null or node is RemoteHunter:
			continue

		var health: HealthComponent = body.get_node_or_null("HealthComponent")
		if health != null and health.is_dead:
			continue

		return body

	return null

# Parented to the scene root rather than to the boss: LoopRebaser sweeps that
# branch, so the room stays put in the Hunter's frame when he crosses the world
# seam, and a boss freed mid-fight cannot take the only thing keeping him boxed
# in down with it without saying so.
static func spawn(host: Node, center: Vector2, half_extents: Vector2, border_damage: int,
	instigator: Node) -> FlameArena:
	var arena := FlameArena.new()
	arena.half_extents = half_extents
	arena.border_damage = border_damage
	arena.instigator = instigator

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(arena)
	arena.global_position = center
	return arena
