extends Node2D
class_name FlameWall

# A sheet of witchfire that forms along one edge of the arena and then sweeps
# the whole room, burning the floor it crosses behind it.
#
# It is not a wall in the sense the arena's own border is a wall (FlameArena).
# That one is the edge of the world and shoves you back inside; this one is an
# attack, it is not solid, and crossing the fire is allowed — it just costs
# more than almost anything else in the fight.
#
# There is one hole in it, and that hole is the answer the move is built around.
# The sheet never crosses that strip, so nothing behind it is alight either: the
# gap is a clean lane running the whole depth of the burn, not merely a doorway
# in the front face. Three ways to answer the move, then — take the lane, stay
# ahead of the sheet until it runs out of room, or eat the fire and cross.
#
# The lane slides along the sheet as it advances (`gap_drift`). Straight, it
# would be a square of floor the Hunter could stand on for the whole sweep and
# ignore the move entirely; slanted, it has to be walked with, which is a thing
# to do rather than a place to be.
#
# What it leaves behind is the other half of the move. The floor it has crossed
# keeps burning for `trail_seconds`, so the ground the sweep has already taken
# stays taken for a while — but only for a while, or a Hunter who ran ahead of
# it would arrive at the far edge with nowhere left to stand and no way back.
# That decay is what makes "stay ahead of it" an answer rather than a stall.
#
# The whole hazard is therefore one moving band: the burning sheet at the front,
# and the ground behind it out to `speed * trail_seconds`, which is exactly how
# far back the fire has had time to go out. No trail objects are spawned and
# none have to be reaped — where the fire is, is a function of how far the sheet
# has travelled.
#
# Self-driving from the moment it is spawned, so it overlaps freely with a
# meteor shower or an eruption already in the air. The boss never waits on one.

const WARN := Color(0.62, 0.22, 0.88, 0.30)
const SHEET_EDGE := Color(0.44, 0.14, 0.66, 0.88)
const SHEET_CORE := Color(0.88, 0.52, 1.0, 0.94)
const TRAIL_COLOR := Color(0.55, 0.20, 0.80, 0.62)

# Same clock as the arena border — burning is a wound, not a grinder.
const BURN_INTERVAL := 0.45

# What the ground it has already crossed costs, against the sheet itself.
# Deliberately not much less: the trail is the reason crossing early is better
# than crossing late, not a consolation prize for being caught in it.
const TRAIL_DAMAGE_FRACTION := 0.7

# How many strips the trail is drawn in. Enough for the burn to visibly die down
# from front to back, few enough that it is one shape and not a ladder.
const TRAIL_STRIPS := 14

# The dimmest burning ground may ever be drawn, as a share of TRAIL_COLOR's own
# alpha. The fade used to run all the way to zero at the rear edge while the
# floor there still dealt seven tenths of the sheet's damage: the picture said
# "going out", the hitbox said "still on fire", and the player found the
# difference by walking into it. Damage here is flat across the whole trail, so
# the drawing is not allowed to imply otherwise — the ramp now only says which
# end of the burn is older, never whether it is still lit.
const TRAIL_MIN_HEAT := 0.55

# The rear edge as its own line. The ramp says the fire is dying; only an edge
# says where standing is free again, and that boundary is the one thing in the
# move with nothing to mark it — the front of the burn is the sheet itself and
# the sides are the walls.
const TRAIL_EDGE := Color(0.95, 0.66, 1.0, 0.85)
const TRAIL_EDGE_WIDTH := 4.0

# Flame tongues along the leading face, one per this many pixels.
const TONGUE_SPACING := 30.0

# How far the lane wanders across the sheet over a whole crossing, as a share of
# the sheet's own length. At 0 it is a straight safe corridor and the move can be
# stood out; far above this it outruns a Hunter who started on the wrong side.
const GAP_DRIFT_SHARE := 0.55

# Hard ceiling on the lane's slope, in local Y per pixel of travel — so the lane
# never slides sideways faster than this share of the sheet's own pace. The room
# is not square, and a share of the sheet length is not a share of the crossing:
# up the short axis the sheet is 660 long but the crossing only 600, which put
# the lane at 231px/s against a Hunter's 300 and made being on the wrong side of
# it unrecoverable. Keeping up with the lane must never be harder than staying
# ahead of the sheet.
const GAP_DRIFT_MAX_SLOPE := 0.45

# The most of its own run the trail may still be burning at once. The room is
# not square: at 210px/s a 2.8s trail is half of the 1200px crossing but nearly
# all of the 660px one, so a sweep up the short axis would leave the Hunter in a
# strip a few pixels wide with the sheet still coming. Capped as a share of the
# distance rather than tuned per direction, so one number in the resource stays
# honest whichever edge the sheet picks.
const TRAIL_MAX_SHARE := 0.55

# Local +X is the direction of travel and local Y runs along the sheet, so
# everything below is axis-aligned. The node sits at the centre of the edge it
# started from, rotated to face across the room.
# Half the sheet's length. Set from the arena so it always spans wall to wall.
var span_half: float = 350.0
var thickness: float = 54.0
var speed: float = 200.0
# Distance the leading face travels: the room, less the sheet's own thickness,
# so it finishes flush against the far edge instead of half inside it.
var total_distance: float = 1140.0
var trail_seconds: float = 3.0

# Half the width of the lane through the sheet, in local Y.
var gap_half_width: float = 95.0
# Where the lane sits at the edge it started from, and how far it slides along
# the sheet per pixel of travel. Both set by spawn_sweep.
var gap_offset: float = 0.0
var gap_drift: float = 0.0

var windup_seconds: float = 0.9
var damage: int = 26
var instigator: Node

var _age: float = 0.0
var _travelled: float = 0.0
var _burn_cooldown: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _physics_process(delta: float) -> void:
	_age += delta
	_burn_cooldown -= delta

	if WaveManager != null and WaveManager.is_preparing:
		return

	# The wind-up is the sheet forming along its edge without moving. It is the
	# only warning of which side the room is about to be swept from, so it does
	# not burn yet either.
	if _age < windup_seconds:
		return

	# Kept advancing past the far edge on purpose: the leading face stops there
	# (see swept()), but the back of the trail has to keep coming so the last of
	# the fire goes out instead of freezing on the floor.
	_travelled += speed * delta
	if trail_rear() >= total_distance:
		queue_free()
		return

	if _burn_cooldown > 0.0:
		return

	for node in get_tree().get_nodes_in_group("Player"):
		var body := node as Node2D
		if body == null:
			continue

		var hit := damage_at(body.global_position)
		if hit <= 0:
			continue

		var health: HealthComponent = body.get_node_or_null("HealthComponent")
		if health == null or health.is_dead:
			continue

		health.take_damage(hit, instigator)
		_burn_cooldown = BURN_INTERVAL
		break

# ------------------------------------------------------------------ geometry

# How far the leading face has got. Stops at the far edge; _travelled does not.
func swept() -> float:
	return minf(_travelled, total_distance)

func trail_rear() -> float:
	return maxf(0.0, _travelled - speed * trail_seconds)

# Centre of the lane at `along` pixels into the crossing. Clamped so the lane
# never slides off the end of the sheet — at the edge it runs along it instead.
func gap_center(along: float) -> float:
	var limit := maxf(0.0, span_half - gap_half_width)
	return clampf(gap_offset + gap_drift * along, -limit, limit)

# What standing at `point` costs this tick, or 0 for ground that is not alight.
func damage_at(point: Vector2) -> int:
	if _age < windup_seconds:
		return 0

	var local := to_local(point)
	if absf(local.y) > span_half:
		return 0

	# In the lane, and so on ground the sheet never touched. Tested against the
	# lane at the point's own depth into the room, which is what makes it a lane
	# through the whole burn rather than a hole in the front face.
	if absf(local.y - gap_center(local.x)) <= gap_half_width:
		return 0

	var front := swept()
	# The sheet itself, but only while it is still crossing the room — once it
	# has reached the far edge there is nothing there but burnt ground.
	if _travelled <= total_distance and local.x >= front and local.x <= front + thickness:
		return maxi(1, damage)

	if local.x >= trail_rear() and local.x < front:
		return maxi(1, roundi(damage * TRAIL_DAMAGE_FRACTION))

	return 0

# ---------------------------------------------------------------- appearance

func _draw() -> void:
	var front := swept()
	var rear := trail_rear()

	# The ground already crossed, drawn front to back so it visibly dies down
	# toward the edge it came from — which is the player's read on how long they
	# have before it is safe to go back. Every strip drawn here is a strip that
	# still burns: see TRAIL_MIN_HEAT.
	if front > rear:
		var burnt := WitchfireSheet.frame(WitchfireSheet.GROUND, _time)
		var step := (front - rear) / float(TRAIL_STRIPS)
		for i in range(TRAIL_STRIPS):
			var x0 := rear + step * i
			# 0 at the back where the fire is going out, 1 just behind the sheet.
			var heat := (float(i) + 0.5) / float(TRAIL_STRIPS)
			var flicker := 0.85 + 0.15 * sin(_time * 7.0 + x0 * 0.03)
			var glow := TRAIL_MIN_HEAT + (1.0 - TRAIL_MIN_HEAT) * heat * heat
			var tint := Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b,
				TRAIL_COLOR.a * glow * flicker)
			var strip := Rect2(Vector2(x0, -span_half), Vector2(step + 1.0, span_half * 2.0))
			for piece in _split_around_lane(strip, gap_center(x0 + step * 0.5)):
				# The wash first, and unconditionally. It is what makes the
				# whole damaging band one readable shape at a glance, which is
				# the thing the fade used to get wrong; the artwork on top says
				# what it is, but the wash is what says how far it goes.
				draw_rect(piece, tint)
				if burnt == null:
					continue

				WitchfireSheet.draw_tiled(self, burnt, piece,
					# Phased on the node rather than on the strip: the ground
					# does not move once it is alight, so the pattern must not
					# crawl forward with the sheet that lit it.
					Vector2.ZERO, 0.0,
					Color(1.0, 1.0, 1.0, glow * flicker), true)

		_draw_trail_edge(rear)

	if _travelled > total_distance:
		return

	var slab := Rect2(Vector2(front, -span_half), Vector2(thickness, span_half * 2.0))

	# The lane is drawn from the wind-up onward, so the way through is visible
	# before the sheet is worth avoiding.
	var pieces := _split_around_lane(slab, gap_center(front))

	if _age < windup_seconds:
		# Forming. Brightens toward the moment it starts moving rather than
		# pulsing, for the same reason BossAoeTelegraph grows its fill: a decal
		# that only flashes says where but never when.
		var t := clampf(_age / maxf(0.01, windup_seconds), 0.0, 1.0)
		for piece in pieces:
			draw_rect(piece, Color(WARN.r, WARN.g, WARN.b, WARN.a * (0.3 + 0.7 * t)))
			draw_rect(piece, Color(SHEET_CORE.r, SHEET_CORE.g, SHEET_CORE.b, 0.55 * t),
				false, 3.0)
		return

	var curtain := WitchfireSheet.frame(WitchfireSheet.CURTAIN, _time)
	if curtain != null:
		_draw_sheet_face(front, pieces, curtain)
		return

	var breathe := 0.78 + 0.14 * sin(_time * 10.0)
	for piece in pieces:
		draw_rect(piece, SHEET_EDGE)
		draw_rect(piece.grow(-7.0), Color(SHEET_CORE.r, SHEET_CORE.g, SHEET_CORE.b,
			SHEET_CORE.a * breathe))

	_draw_tongues(front + thickness, gap_center(front))

# The sheet itself, as a curtain of fire standing across the room and leaning
# the way it is going.
#
# Drawn in a frame rotated a quarter turn, because the artwork's "up" is this
# hazard's "forward": the flames then lick ahead of the slab in the direction of
# travel, which is the same tell the tongues used to give. It is also scaled, on
# purpose — the slab is as deep as the attack pattern says (`thickness`, 60 in
# the resource) and the artwork is FLAME_H deep, and what the player must be
# able to trust is that the fire they see is the fire that burns them.
func _draw_sheet_face(front: float, pieces: Array, curtain: Texture2D) -> void:
	var scale := thickness / WitchfireSheet.flame_height()
	var cell := WitchfireSheet.cell() * scale
	var floor_y := WitchfireSheet.floor_y() * scale

	# A quarter turn takes the artwork's up to this hazard's forward, which puts
	# the sheet's floor line on the back of the slab and its flame across the
	# whole depth the attack claims. The scorch below the line lands on ground
	# the sweep has already burnt, where it belongs.
	draw_set_transform(Vector2(front, 0.0), PI * 0.5, Vector2.ONE)
	for piece in pieces:
		WitchfireSheet.draw_tiled(self, curtain,
			Rect2(piece.position.y, -floor_y, piece.size.y, cell),
			# One grid for both sides of the lane, anchored on the sheet rather
			# than on the piece, so the fire does not step across the gap.
			Vector2(-span_half, -floor_y), cell)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The line the burn ends at: behind it the floor is floor again. Drawn at the
# same depth the lane is tested at, and split around the lane like everything
# else, so the way through stays a clean opening rather than being fenced off at
# the back by a bright line across it.
func _draw_trail_edge(rear: float) -> void:
	var pulse := 0.78 + 0.22 * sin(_time * 6.0)
	var band := Rect2(Vector2(rear, -span_half),
		Vector2(TRAIL_EDGE_WIDTH, span_half * 2.0))
	var tint := Color(TRAIL_EDGE.r, TRAIL_EDGE.g, TRAIL_EDGE.b, TRAIL_EDGE.a * pulse)
	for piece in _split_around_lane(band, gap_center(rear + TRAIL_EDGE_WIDTH * 0.5)):
		draw_rect(piece, tint)

# Fire licking off the leading face, so which way the sheet is going is legible
# from the shape of it and not only from watching it move.
func _draw_tongues(face_x: float, lane_center: float) -> void:
	var steps := maxi(2, int(span_half * 2.0 / TONGUE_SPACING))
	for i in range(steps):
		var y := -span_half + TONGUE_SPACING * (float(i) + 0.5)
		# Nothing licks across the way through: the lane has to read as open.
		if absf(y - lane_center) <= gap_half_width:
			continue

		var lick := 0.55 + 0.45 * sin(_time * 8.0 + y * 0.05)
		var reach := thickness * (0.3 + 0.5 * lick)
		draw_colored_polygon(PackedVector2Array([
			Vector2(face_x, y - TONGUE_SPACING * 0.34),
			Vector2(face_x, y + TONGUE_SPACING * 0.34),
			Vector2(face_x + reach, y),
		]), SHEET_EDGE)

# One full-width band minus the lane through it — the pieces either side.
# Returns one piece when the lane has slid up against an end of the sheet.
func _split_around_lane(band: Rect2, center: float) -> Array:
	var lo := center - gap_half_width
	var hi := center + gap_half_width
	var pieces: Array = []

	if lo > band.position.y:
		pieces.append(Rect2(band.position, Vector2(band.size.x, lo - band.position.y)))

	if hi < band.end.y:
		pieces.append(Rect2(Vector2(band.position.x, hi),
			Vector2(band.size.x, band.end.y - hi)))

	return pieces

# Forms along the edge whose outward normal is `side` and sweeps to the opposite
# one, so Vector2.RIGHT starts on the right-hand wall and travels left.
static func spawn_sweep(host: Node, arena: FlameArena, side: Vector2, thickness: float,
	speed: float, trail_seconds: float, gap_half_width: float, windup_seconds: float,
	damage: int, instigator: Node) -> FlameWall:
	var wall := FlameWall.new()
	var vertical := absf(side.x) > absf(side.y)

	# Spans the room across its direction of travel, and crosses the whole of it
	# the other way. Both read off the arena so a resized room stays sealed.
	wall.span_half = arena.half_extents.y if vertical else arena.half_extents.x
	var run := arena.half_extents.x * 2.0 if vertical else arena.half_extents.y * 2.0
	wall.thickness = thickness
	wall.total_distance = maxf(thickness, run - thickness)
	wall.speed = maxf(40.0, speed)
	# See TRAIL_MAX_SHARE: the authored seconds are what a long crossing gets,
	# and a short one gets whatever leaves the far end of the room clean.
	wall.trail_seconds = clampf(trail_seconds,
		0.2, wall.total_distance * TRAIL_MAX_SHARE / wall.speed)
	# Never wider than half the sheet: a lane bigger than that is not a way
	# through a wall, it is a wall with a wall-sized hole in it.
	wall.gap_half_width = clampf(gap_half_width, 30.0, wall.span_half * 0.5)
	var limit := wall.span_half - wall.gap_half_width
	wall.gap_offset = randf_range(-limit, limit)
	# Slides one way or the other over the crossing, never the same amount twice.
	var slope := minf(GAP_DRIFT_SHARE * (wall.span_half * 2.0) / wall.total_distance,
		GAP_DRIFT_MAX_SLOPE)
	wall.gap_drift = randf_range(-1.0, 1.0) * slope

	wall.windup_seconds = windup_seconds
	wall.damage = damage
	wall.instigator = instigator

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(wall)
	# At the centre of its starting edge, turned so local +X points across the
	# room. Everything the sheet does is then axis-aligned in its own frame.
	wall.global_position = arena.global_position + Vector2(
		side.x * arena.half_extents.x, side.y * arena.half_extents.y)
	wall.rotation = (-side).angle()
	return wall
