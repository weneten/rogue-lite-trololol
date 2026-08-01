extends PassiveAbility
class_name SummonFamiliarsPassive

# Grave Warden — raises spectral familiars from the earth: at run start, spawns
# Mathf.RoundToInt(PassiveValueA) ghost-blade familiars orbiting the Player, evenly spaced in a
# ring. Each familiar is just another Weapon.tscn instance (auto-targets/attacks nearest enemy
# exactly like the player's own weapons) driven by FamiliarBolt.tres, mounted directly on the
# Player body so it doesn't consume a WeaponInventory slot and isn't sellable in the shop.

const WEAPON_SCENE_PATH = "res://Scenes/Weapons/Weapon.tscn"
const FAMILIAR_DATA_PATH = "res://Resources/WeaponData/Data/FamiliarBolt.tres"
const RING_RADIUS = 40.0

func on_initialize() -> void:
	var weapon_scene = load(WEAPON_SCENE_PATH)
	var familiar_data = load(FAMILIAR_DATA_PATH)
	if weapon_scene == null or familiar_data == null or owner_player == null:
		push_warning("[SummonFamiliarsPassive] Missing Weapon.tscn or FamiliarBolt.tres; no familiars spawned.")
		return

	var count = maxi(1, roundi(data.passive_value_a))
	for i in range(count):
		var angle = TAU * i / count
		var familiar = weapon_scene.instantiate()
		familiar.data = familiar_data
		familiar.owner_body_path = NodePath("..")
		familiar.position = Vector2(cos(angle), sin(angle)) * RING_RADIUS
		owner_player.add_child(familiar)
