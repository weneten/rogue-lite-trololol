extends Node2D
class_name HunterCosmetics

# Makes the run's loadout visible on the Hunter.
#
# Every relic bought this run becomes a charm orbiting the character, and the
# mix of relics tints a ground aura underneath them — so a defensive build
# glows cold and a greed build glows gold without anyone reading a stat sheet.
#
# Deliberately anchored to the body rather than to the rig's skeleton: the
# sprite sheets bob and swing through six animations, so anything pinned to a
# shoulder slides off it within two frames. Orbiting charms and a ground disc
# track the character on all ten Hunters with no per-character offsets.
#
# Purely cosmetic. Nothing here touches stats.

const AURA_PATH := "res://Assets/sprites/cosmetics/aura.png"
const BACKING_PATH := "res://Assets/sprites/cosmetics/charm_backing.png"

# Past this the charms stop reading as jewellery and start reading as a swarm.
const MAX_CHARMS := 8

const ORBIT_RADIUS_X := 30.0
const ORBIT_RADIUS_Y := 11.0
# Charms ride at chest height, matching the carried weapons. The rig stands its
# characters on the body origin, so anything at y=0 orbits their ankles.
const ORBIT_HEIGHT := -26.0
const ORBIT_SPEED := 0.55
const CHARM_SCALE := 0.75

# Where the aura sits relative to the body origin (the Hunter's feet).
const AURA_OFFSET := Vector2(0.0, -2.0)

# Which relic families pull the aura towards which colour. An unlisted effect
# simply does not vote, which is why the default stays neutral.
const CATEGORY_COLOR := {
	PassiveItemData.PassiveEffectType.DAMAGE_BOOST: Color(0.78, 0.16, 0.20),
	PassiveItemData.PassiveEffectType.ATTACK_SPEED_BOOST: Color(0.90, 0.42, 0.20),
	PassiveItemData.PassiveEffectType.CRIT_CHANCE_BOOST: Color(0.90, 0.42, 0.20),
	PassiveItemData.PassiveEffectType.CRIT_DAMAGE_BOOST: Color(0.90, 0.42, 0.20),
	PassiveItemData.PassiveEffectType.LIFESTEAL_BOOST: Color(0.70, 0.10, 0.28),
	PassiveItemData.PassiveEffectType.MAX_HEALTH_BOOST: Color(0.70, 0.10, 0.28),
	PassiveItemData.PassiveEffectType.HEALTH_REGEN_BOOST: Color(0.36, 0.72, 0.44),
	PassiveItemData.PassiveEffectType.ARMOR_BOOST: Color(0.45, 0.55, 0.68),
	PassiveItemData.PassiveEffectType.DODGE_BOOST: Color(0.37, 0.83, 0.78),
	PassiveItemData.PassiveEffectType.MOVE_SPEED_BOOST: Color(0.37, 0.83, 0.78),
	PassiveItemData.PassiveEffectType.MAGIC_DAMAGE_BOOST: Color(0.54, 0.35, 0.83),
	PassiveItemData.PassiveEffectType.UNDEAD_DAMAGE_BOOST: Color(0.54, 0.35, 0.83),
	PassiveItemData.PassiveEffectType.XP_GAIN_BOOST: Color(0.54, 0.35, 0.83),
	PassiveItemData.PassiveEffectType.CURRENCY_GAIN_BOOST: Color(0.94, 0.75, 0.29),
	PassiveItemData.PassiveEffectType.PICKUP_RANGE_BOOST: Color(0.94, 0.75, 0.29),
}

var _aura: Sprite2D
var _charm_root: Node2D
var _charms: Array[Node2D] = []
var _time: float = 0.0

func _ready() -> void:
	# The Hunter's own art draws at z 0; the aura belongs on the floor and the
	# charms just above it, so neither ever covers the character.
	_aura = Sprite2D.new()
	_aura.name = "Aura"
	_aura.texture = _load(AURA_PATH)
	_aura.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_aura.position = AURA_OFFSET
	_aura.z_index = -3
	_aura.visible = false
	add_child(_aura)

	_charm_root = Node2D.new()
	_charm_root.name = "Charms"
	_charm_root.z_index = -1
	add_child(_charm_root)

	EventBus.item_picked_up.connect(_on_item_picked_up)
	refresh()

func _on_item_picked_up(_item_id: String) -> void:
	refresh()

# Rebuilds from GameManager's owned list. Cheap enough to run on every
# purchase, and rebuilding beats trying to diff two small arrays.
func refresh() -> void:
	var owned: Array[PassiveItemData] = GameManager.owned_passive_items if GameManager != null else []

	for charm in _charms:
		charm.queue_free()
	_charms.clear()

	if owned.is_empty():
		_aura.visible = false
		return

	var backing := _load(BACKING_PATH)
	for i in range(mini(owned.size(), MAX_CHARMS)):
		var item: PassiveItemData = owned[i]
		if item == null:
			continue
		_charms.append(_build_charm(item, backing))

	_aura.visible = true
	_aura.modulate = _aura_color(owned)
	# A bigger collection glows brighter, up to a ceiling — an aura that keeps
	# growing eventually hides the floor the player needs to read.
	_aura.modulate.a = minf(0.34 + 0.05 * owned.size(), 0.7)
	_aura.scale = Vector2.ONE * minf(1.0 + 0.04 * owned.size(), 1.45)

func _build_charm(item: PassiveItemData, backing: Texture2D) -> Node2D:
	var holder := Node2D.new()
	holder.name = "Charm_" + item.id

	if backing != null:
		var disc := Sprite2D.new()
		disc.texture = backing
		disc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(disc)

	if item.icon != null:
		var icon := Sprite2D.new()
		icon.texture = item.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Relic icons are authored at 32; the charm disc is 16.
		icon.scale = Vector2.ONE * 0.5
		holder.add_child(icon)

	holder.scale = Vector2.ONE * CHARM_SCALE
	_charm_root.add_child(holder)
	return holder

# Average of every owned relic's category colour. Averaging rather than picking
# a winner means a mixed build reads as mixed instead of flickering between two
# identities every time you buy something.
static func _aura_color(owned: Array[PassiveItemData]) -> Color:
	var total := Color(0, 0, 0, 1)
	var votes := 0

	for item in owned:
		if item == null or not CATEGORY_COLOR.has(item.effect_type):
			continue
		var c: Color = CATEGORY_COLOR[item.effect_type]
		total.r += c.r
		total.g += c.g
		total.b += c.b
		votes += 1

	if votes == 0:
		return Color(0.6, 0.6, 0.7, 1.0)

	return Color(total.r / votes, total.g / votes, total.b / votes, 1.0)

func _process(delta: float) -> void:
	if _charms.is_empty():
		return

	_time += delta
	var count := _charms.size()
	for i in range(count):
		var phase: float = _time * ORBIT_SPEED * TAU + TAU * float(i) / float(count)
		var charm := _charms[i]
		charm.position = Vector2(cos(phase) * ORBIT_RADIUS_X, sin(phase) * ORBIT_RADIUS_Y + ORBIT_HEIGHT)
		# Charms on the far side of the orbit sit behind the Hunter and dim, so
		# the ring reads as going around them rather than across them.
		var front: float = (sin(phase) + 1.0) * 0.5
		charm.z_index = 1 if front > 0.5 else -1
		charm.modulate.a = 0.55 + 0.45 * front
		charm.scale = Vector2.ONE * CHARM_SCALE * (0.85 + 0.15 * front)

static func _load(path: String) -> Texture2D:
	return ResourceLoader.load(path, "Texture2D") as Texture2D if ResourceLoader.exists(path) else null
