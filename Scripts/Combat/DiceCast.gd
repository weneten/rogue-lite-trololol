extends Node2D
class_name DiceCast

# One throw of the Jester's Bone Dice: two dice arc out of his hand, tumble, land, show
# what they rolled, and vanish.
#
# The rolls are decided before the dice leave the hand (Weapon._throw_dice) — this node is
# the theatre, exactly like SlotMachineUI's reels. What it does own is the beat the damage
# lands on: `resolved` fires when the dice settle and the numbers come up, not when the
# throw starts, so a hit always looks like it came from the roll that caused it.
#
# One die is how many enemies are hit, the other is the damage each of them takes. Luck
# raises both: a little on every roll, and a whole step up the die ladder every
# LUCK_PER_DIE_STEP points, which is the Jester's entire scaling.

# Emitted once the dice have settled, carrying the two rolls. Weapon listens for this and
# applies the damage.
signal resolved(target_count: int, damage_pips: int)

const SHEET_PATH = "res://Assets/sprites/weapons/dice_cast.png"
const CELL = 16
# Frames 0-2 tumble, 3 is the landing squash, 4 is the resting face, 5 is the same face
# with a gold rim for the reveal.
const TUMBLE_FRAMES: Array[int] = [0, 1, 2]
const SQUASH_FRAME = 3
const REST_FRAME = 4
const REVEAL_FRAME = 5

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
func begin(from: Vector2, toward: Vector2, target_count: int, damage_pips: int) -> void:
	global_position = Vector2.ZERO
	z_index = 1

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

	var rolls := [target_count, damage_pips]
	# Gold for the count die, crimson for the damage die: which number did which is the
	# only thing the player needs to read off the floor.
	var tints := [Color(1.0, 0.84, 0.42), Color(1.0, 0.45, 0.45)]

	for i in range(2):
		var spread := Vector2(-9.0 + 18.0 * float(i), 5.0 - 10.0 * float(i))
		_spawn_die(sheet, from, landing + spread + Vector2(randf_range(-4, 4), randf_range(-3, 3)),
			rolls[i], tints[i], 0.05 * float(i))

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

func _spawn_die(sheet: Texture2D, from: Vector2, landing: Vector2, value: int,
		tint: Color, delay: float) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(TUMBLE_FRAMES[0] * CELL, 0, CELL, CELL)

	var die := Sprite2D.new()
	die.texture = atlas
	die.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	die.global_position = from
	die.scale = Vector2.ONE * 1.4
	add_child(die)
	_dice.append(die)

	var label := Label.new()
	label.text = str(value)
	label.theme_type_variation = &"StatLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(40, 20)
	label.position = landing - Vector2(20, 30)
	label.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	label.scale = Vector2.ONE * 0.6
	label.pivot_offset = Vector2(20, 10)
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
		func(t: float): _tumble(atlas, t), 0.0, 1.0, THROW_SECONDS
	)
	tween.parallel().tween_property(die, "rotation", randf_range(-TAU, TAU), THROW_SECONDS)

	# Landing: squash for a frame, drop the spin, then the face comes up.
	tween.tween_callback(func():
		atlas.region = Rect2(SQUASH_FRAME * CELL, 0, CELL, CELL)
		die.rotation = 0.0)
	tween.tween_interval(SQUASH_SECONDS)
	tween.tween_callback(func(): atlas.region = Rect2(REVEAL_FRAME * CELL, 0, CELL, CELL))

	# The number rises off the die and settles, then the die goes back to a plain face
	# so the gold rim reads as the moment of the reveal rather than as decoration.
	var reveal := label.create_tween()
	reveal.tween_interval(delay + THROW_SECONDS + SQUASH_SECONDS)
	reveal.set_parallel(true)
	reveal.tween_property(label, "modulate:a", 1.0, REVEAL_SECONDS * 0.5)
	reveal.tween_property(label, "scale", Vector2.ONE * 1.25, REVEAL_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(label, "position:y", label.position.y - 8.0, REVEAL_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.chain().tween_callback(func():
		if is_instance_valid(die):
			atlas.region = Rect2(REST_FRAME * CELL, 0, CELL, CELL))

func _place_die(die: Sprite2D, from: Vector2, landing: Vector2, t: float) -> void:
	if not is_instance_valid(die):
		return
	# 4 * t * (1 - t) peaks at 1.0 halfway through, so the hop is highest mid-flight and
	# exactly zero at both ends — the die leaves the hand and meets the floor cleanly.
	var hop := 4.0 * t * (1.0 - t) * 26.0
	die.global_position = from.lerp(landing, t) - Vector2(0.0, hop)

func _tumble(atlas: AtlasTexture, t: float) -> void:
	# Fast at first, slower as it loses energy: the frame index is driven by a curve
	# rather than a constant rate, which is most of what sells a die losing momentum.
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var index: int = TUMBLE_FRAMES[int(eased * 11.0) % TUMBLE_FRAMES.size()]
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
