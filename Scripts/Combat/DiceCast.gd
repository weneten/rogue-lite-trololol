extends Node2D
class_name DiceCast

# One throw of the Jester's Bone Dice: two dice arc out of his hand, tumble, land, show
# their numbers above the cubes, and vanish.
#
# The rolls are decided before the dice leave the hand (Weapon._throw_dice) — this node is
# the theatre, exactly like SlotMachineUI's reels. What it does own is the beat the damage
# lands on: `resolved` fires when the dice settle and the numbers come up, not when the
# throw starts, so a hit always looks like it came from the roll that caused it.
#
# One die is how many enemies are hit, the other is the damage each of them takes (the
# calculated hit, not the raw pip roll). Luck raises both: a little on every roll, and a
# whole step up the die ladder every LUCK_PER_DIE_STEP points, which is the Jester's
# entire scaling.

# Emitted once the dice have settled, carrying the two rolls. Weapon listens for this and
# applies the damage.
signal resolved(target_count: int, damage_pips: int)

const SHEET_PATH = "res://Assets/sprites/weapons/dice_cast.png"
const FONT_PATH = "res://Assets/Fonts/nightbane_3x.fnt"
const CELL = 16
const DIE_SCALE = 2.0
# Cube is 16 * DIE_SCALE; keep a sliver of air so the pair never stacks.
const MIN_DIE_SEPARATION = 44.0
# Label centre sits this many pixels above the die centre after the throw lands.
const NUMBER_ABOVE = 30.0
# Extra lift during the reveal pop, so the number reads as a callout, not a pip.
const NUMBER_RISE = 8.0
# Sheet: frames 0-5 are pip faces 1-6, 6 is the landing squash. The pips are
# theatre — they do not have to match the damage/count labels above the cubes.
const PIP_FRAMES = 6
const SQUASH_FRAME = 6

# The die ladder Luck climbs. A run starts on d6; every LUCK_PER_DIE_STEP points of Luck
# is one step right, and a Jester who has hoarded Luck all run is throwing d20s.
const SIDES_LADDER: Array[int] = [6, 8, 10, 12, 16, 20]
const LUCK_PER_DIE_STEP = 8.0
# On top of the bigger die, every point of Luck nudges the roll itself. Deliberately small:
# the die ladder is the interesting scaling, this just stops low rolls feeling dead.
const LUCK_PER_ROLL_BONUS = 22.0

const THROW_SECONDS = 0.36
const SQUASH_SECONDS = 0.07
const REVEAL_SECONDS = 0.30
const HOLD_SECONDS = 0.45
const FADE_SECONDS = 0.22

var _dice: Array[Sprite2D] = []
var _labels: Array[Label] = []

# ------------------------------------------------------------------------- scaling

# Faces on each die at this much Luck.
static func sides_for_luck(luck: float, base_sides: int = 6) -> int:
	var step: int = int(maxf(0.0, luck) / LUCK_PER_DIE_STEP)
	# The ladder is indexed from wherever the weapon's own base sits, so a future d10
	# weapon climbs from d10 rather than being dragged back down to d6.
	var start: int = SIDES_LADDER.find(base_sides)
	if start < 0:
		return base_sides + step * 2
	return SIDES_LADDER[mini(start + step, SIDES_LADDER.size() - 1)]

# Flat bonus added to every roll at this much Luck.
static func roll_bonus_for_luck(luck: float) -> int:
	return int(maxf(0.0, luck) / LUCK_PER_ROLL_BONUS)

# One die: 1..sides, plus Luck's nudge.
static func roll(sides: int, bonus: int) -> int:
	return randi_range(1, maxi(1, sides)) + maxi(0, bonus)

# --------------------------------------------------------------------------- throw

# Throws the pair. `from` is the hand, `toward` the direction the dice are cast in;
# they land short of the target rather than on it, because dice roll on the floor.
# `display_damage` is the hit painted on the crimson die; omit it to show raw pips.
func begin(from: Vector2, toward: Vector2, target_count: int, damage_pips: int,
		display_damage: int = -1) -> void:
	global_position = Vector2.ZERO
	z_index = 12

	var sheet := load(SHEET_PATH) as Texture2D
	if sheet == null:
		# No art: resolve immediately rather than swallowing the attack.
		push_warning("[DiceCast] Missing %s — run tools/build_art.py weapons." % SHEET_PATH)
		resolved.emit(target_count, damage_pips)
		queue_free()
		return

	var direction := (toward - from)
	direction = direction.normalized() if direction.length() > 1.0 else Vector2.RIGHT
	var landing := from + direction * 46.0

	var shown_damage: int = display_damage if display_damage > 0 else damage_pips
	# Gold count die (how many enemies), crimson damage die (the hit each of them
	# takes). Saturated so they hold up against the bone cube, especially gold.
	var faces: Array[String] = ["x%d" % target_count, str(shown_damage)]
	var tints := [Color(1.0, 0.94, 0.28), Color(1.0, 0.38, 0.32)]
	var landings := _spread_landings(landing, direction)

	for i in range(2):
		_spawn_die(sheet, from, landings[i], faces[i], tints[i], 0.05 * float(i))

	# The dice are thrown, tumble, squash on landing and then hold up their numbers. The
	# stagger above means the second die lands a beat after the first, so the pair reads
	# as two objects rather than one sprite drawn twice.
	var settle := THROW_SECONDS + 0.05 + SQUASH_SECONDS
	await get_tree().create_timer(settle).timeout
	# A wave can end (or the run can) while dice are in the air; the throw is then just
	# a throw, and nothing is owed to a tree this node has already left.
	if not is_inside_tree():
		return
	resolved.emit(target_count, damage_pips)

	await get_tree().create_timer(REVEAL_SECONDS + HOLD_SECONDS).timeout
	if is_inside_tree():
		_vanish()

func _spawn_die(sheet: Texture2D, from: Vector2, landing: Vector2, value: String,
		tint: Color, delay: float) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	var pip_cycle := _shuffled_pip_frames()
	atlas.region = Rect2(pip_cycle[0] * CELL, 0, CELL, CELL)

	var die := Sprite2D.new()
	die.texture = atlas
	die.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	die.global_position = from
	die.scale = Vector2.ONE * DIE_SCALE
	die.modulate = Color.WHITE.lerp(tint, 0.12)
	add_child(die)
	_dice.append(die)

	# Sibling of the die, not a child: the number must not inherit the cube's
	# gold tint (that was washing the yellow out) or the throw's spin.
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.02, 1.0))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	var label_size := Vector2(80, 36)
	label.size = label_size
	label.pivot_offset = label_size * 0.5
	label.position = landing - label_size * 0.5 + Vector2(0.0, -NUMBER_ABOVE)
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(label)
	_labels.append(label)

	var tween := die.create_tween()
	tween.tween_interval(delay)

	# Flight: a flat arc, done as position plus a height offset so the die can rise and
	# fall without a second tween fighting the first over `position`.
	tween.tween_method(
		func(t: float): _place_die(die, from, landing, t),
		0.0, 1.0, THROW_SECONDS
	)
	tween.parallel().tween_method(
		func(t: float): _tumble(atlas, t, pip_cycle), 0.0, 1.0, THROW_SECONDS
	)
	tween.parallel().tween_property(die, "rotation", randf_range(-TAU, TAU), THROW_SECONDS)

	# Landing: squash for a frame, drop the spin, then a random 1-6. The face
	# is flavour; the labels above carry the real hit.
	var rest_pip: int = randi_range(0, PIP_FRAMES - 1)
	tween.tween_callback(func():
		atlas.region = Rect2(SQUASH_FRAME * CELL, 0, CELL, CELL)
		die.rotation = 0.0)
	tween.tween_interval(SQUASH_SECONDS)
	tween.tween_callback(func(): atlas.region = Rect2(rest_pip * CELL, 0, CELL, CELL))

	# Number pops in above the die and rises a little so it isn't glued to the cube.
	var rest_y: float = label.position.y
	var reveal := label.create_tween()
	reveal.tween_interval(delay + THROW_SECONDS + SQUASH_SECONDS)
	reveal.set_parallel(true)
	reveal.tween_property(label, "modulate:a", 1.0, REVEAL_SECONDS * 0.45)
	reveal.tween_property(label, "scale", Vector2.ONE * 1.2, REVEAL_SECONDS * 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(label, "position:y", rest_y - NUMBER_RISE, REVEAL_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.chain().tween_property(label, "scale", Vector2.ONE, REVEAL_SECONDS * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

# Two spots beside the throw, then a last push if jitter still stacked them.
func _spread_landings(landing: Vector2, direction: Vector2) -> Array[Vector2]:
	var side := Vector2(-direction.y, direction.x)
	var half := MIN_DIE_SEPARATION * 0.5
	var spots: Array[Vector2] = [
		landing - side * half + direction * randf_range(-3.0, 3.0),
		landing + side * half + direction * randf_range(-3.0, 3.0),
	]
	var delta: Vector2 = spots[1] - spots[0]
	var dist := delta.length()
	if dist < MIN_DIE_SEPARATION:
		var axis := delta / dist if dist > 0.5 else side
		var extra := (MIN_DIE_SEPARATION - dist) * 0.5
		spots[0] -= axis * extra
		spots[1] += axis * extra
	return spots

func _place_die(die: Sprite2D, from: Vector2, landing: Vector2, t: float) -> void:
	if not is_instance_valid(die):
		return
	# 4 * t * (1 - t) peaks at 1.0 halfway through, so the hop is highest mid-flight and
	# exactly zero at both ends — the die leaves the hand and meets the floor cleanly.
	var hop := 4.0 * t * (1.0 - t) * 26.0
	die.global_position = from.lerp(landing, t) - Vector2(0.0, hop)

# A shuffled 1-6 so the pair doesn't flash the same faces in lockstep.
func _shuffled_pip_frames() -> Array[int]:
	var cycle: Array[int] = []
	for i in range(PIP_FRAMES):
		cycle.append(i)
	cycle.shuffle()
	return cycle

func _tumble(atlas: AtlasTexture, t: float, pip_cycle: Array[int]) -> void:
	# Fast at first, slower as it loses energy: the frame index is driven by a curve
	# rather than a constant rate, which is most of what sells a die losing momentum.
	if pip_cycle.is_empty():
		return
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var index: int = pip_cycle[int(eased * 11.0) % pip_cycle.size()]
	atlas.region = Rect2(index * CELL, 0, CELL, CELL)

func _vanish() -> void:
	var tween := create_tween()
	for die in _dice:
		if is_instance_valid(die):
			tween.parallel().tween_property(die, "modulate:a", 0.0, FADE_SECONDS)
	for label in _labels:
		if is_instance_valid(label):
			tween.parallel().tween_property(label, "modulate:a", 0.0, FADE_SECONDS)
	tween.chain().tween_callback(queue_free)
