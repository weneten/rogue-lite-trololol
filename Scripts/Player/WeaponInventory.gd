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

var _owner_body: Node2D
var _equipped_weapons: Array[Weapon] = []

var equipped_weapons: Array[Weapon]:
	get:
		return _equipped_weapons

var has_free_slot: bool:
	get:
		return _equipped_weapons.size() < max_weapon_slots

func _ready() -> void:
	instance = self
	weapon_scene = weapon_scene if weapon_scene != null else load("res://Scenes/Weapons/Weapon.tscn")
	_owner_body = get_parent() as Node2D

	# Register whatever Weapon nodes are already wired as children in the scene (e.g. the
	# starting RustyScythe on Player.tscn) so they count against MaxWeaponSlots from the start.
	for child in _owner_body.get_children():
		if child is Weapon:
			_equipped_weapons.append(child)

	_reslot_weapons()

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
	_owner_body.add_child(weapon)
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

# Spaces the carried weapons evenly around the orbit they fly, so a full loadout
# reads as six distinct things rather than one smear. This is position only —
# the moment a target is in range each weapon aims at it independently.
func _reslot_weapons() -> void:
	var count: int = _equipped_weapons.size()
	if count == 0:
		return

	# Phases start at "in front of the Hunter" so a single weapon is never
	# parked behind them where it cannot be seen.
	for i in range(count):
		_equipped_weapons[i].orbit_phase = PI * 0.5 + TAU * float(i) / float(count)
