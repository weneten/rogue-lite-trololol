extends Node

class_name WeaponInventory

static var instance: WeaponInventory

# Extends the stage-3 single hardcoded Weapon child into a proper multi-slot loadout: tracks
# every equipped Weapon node (starting with whatever Weapon.tscn instances are already wired
# as children in Player.tscn), and lets ShopUI add/remove weapons at runtime as Grave Coin is
# spent. Lives as a sibling of PlayerStats on the Player node and is exposed via a scene-lifetime
# Instance singleton, mirroring PlayerStats, so ShopUI can reach it without a direct scene reference.

@export var max_weapon_slots: int = 6
# Scene instantiated for weapons purchased at runtime. Falls back to Weapon.tscn if unassigned.
@export var weapon_scene: PackedScene

# Hard ceiling the exported dial is clamped to. Six weapons is what the ring
# around the Hunter can hold and still be read at a glance, and it is what the
# shop tray draws — a designer raising the export past this would quietly break
# both, so the cap is enforced in code rather than trusted to the .tscn.
const SLOT_CEILING := 6

var _owner_body: Node2D
var _equipped_weapons: Array[Weapon] = []
# Shared per-frame aim so six weapons don't each scan the enemy group.
var aim_target: Node2D = null

var equipped_weapons: Array[Weapon]:
	get:
		return _equipped_weapons

var has_free_slot: bool:
	get:
		return _equipped_weapons.size() < max_weapon_slots

func _ready() -> void:
	instance = self
	max_weapon_slots = clampi(max_weapon_slots, 1, SLOT_CEILING)
	weapon_scene = weapon_scene if weapon_scene != null else load("res://Scenes/Weapons/Weapon.tscn")
	_owner_body = get_parent() as Node2D

	# Register whatever Weapon nodes are already wired as children in the scene (e.g. the
	# starting RustyScythe on Player.tscn) so they count against MaxWeaponSlots from the start.
	# Anything past the cap is freed rather than left fighting off-book: the shop
	# and the carry ring both size themselves off max_weapon_slots.
	for child in _owner_body.get_children():
		if child is Weapon:
			if _equipped_weapons.size() < max_weapon_slots:
				_equipped_weapons.append(child)
			else:
				push_warning("[WeaponInventory] Scene wires more than %d weapons; dropping the extras." % max_weapon_slots)
				child.queue_free()

	_reslot_weapons()

func _process(_delta: float) -> void:
	if _owner_body == null or not is_instance_valid(_owner_body):
		aim_target = null
		return

	aim_target = Weapon.find_nearest(_owner_body, "Enemy", -1.0, true)

func _exit_tree() -> void:
	if instance == self:
		instance = null

# Instantiates a new Weapon.tscn mounted on the owner body. Fails (returns false) if no slot is free.
func try_add_weapon(data: WeaponData) -> bool:
	if data == null or not has_free_slot or _owner_body == null:
		return false

	var weapon: Weapon = weapon_scene.instantiate() as Weapon
	weapon.data = data
	# New weapons are parented directly onto the owner body, same as the Weapon child
	# authored in Player.tscn, so this NodePath ("..") resolves to the owner exactly like theirs.
	weapon.owner_body_path = NodePath("..")
	if _owner_body.is_node_ready():
		_owner_body.add_child(weapon)
	else:
		_owner_body.add_child.call_deferred(weapon)
	_equipped_weapons.append(weapon)
	_reslot_weapons()
	return true

# Removes and frees the first equipped weapon using this exact WeaponData resource.
func remove_weapon(data: WeaponData) -> bool:
	for i in range(_equipped_weapons.size()):
		if _equipped_weapons[i].data == data:
			return remove_weapon_at(i)
	return false

func remove_weapon_at(index: int) -> bool:
	if index < 0 or index >= _equipped_weapons.size():
		return false

	var weapon: Weapon = _equipped_weapons[index]
	_equipped_weapons.remove_at(index)
	weapon.queue_free()
	_reslot_weapons()
	return true

# Frees every equipped weapon (including whatever was pre-wired in the scene). Used by
# Player.ApplyCharacterData so a freshly selected Hunter starts from their own StartingWeapons
# instead of stacking on top of Player.tscn's default RustyScythe.
func clear_all_weapons() -> void:
	for i in range(_equipped_weapons.size() - 1, -1, -1):
		remove_weapon_at(i)

# Radians between neighbouring weapons in the cluster, so a full loadout fans
# out enough to read as distinct weapons without the fan swallowing more than
# a quarter of the ring.
const SLOT_SPACING := 0.32

# Gives every carried weapon a small fixed offset from the shared aim
# direction, so a full loadout clusters on whichever side the nearest enemy
# is on instead of ringing the Hunter — while staying spread out enough that
# six weapons don't stack into one sprite.
func _reslot_weapons() -> void:
	var count: int = _equipped_weapons.size()
	if count == 0:
		return

	for i in range(count):
		_equipped_weapons[i].slot_offset = (float(i) - float(count - 1) * 0.5) * SLOT_SPACING
