class_name MetaSave

# Persistent meta-progression: meta-currency + unlocked characters/weapons.
# JSON at user://nightbane_meta.json via Godot FileAccess.

const SAVE_PATH = "user://nightbane_meta.json"

# Default free starter hunters (by CharacterName). All base roster playable at first launch.
static var _default_unlocked_characters: Array[String] = [
	"Witch Hunter",
	"The Reaper",
	"Silver Priest",
	"Bloodletter",
	"Bloodstained Crusader",
	"Pyromancer",
	"Grave Warden",
	"Moonlit Duelist",
	"Alchemist",
	"Cursed Noble",
]

static var meta_currency: int = 0

static var _unlocked_characters: Array[String] = []
static var _unlocked_weapons: Array[String] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


static func load_data() -> void:
	_unlocked_characters.clear()
	_unlocked_weapons.clear()
	meta_currency = 0

	if not FileAccess.file_exists(SAVE_PATH):
		_apply_defaults()
		save()
		_loaded = true
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("[MetaSave] Failed to open '%s' for read." % SAVE_PATH)
		_apply_defaults()
		_loaded = true
		return

	var json_str = file.get_as_text()
	if json_str.is_empty():
		json_str = "{}"

	var json = JSON.new()
	var error = json.parse(json_str)
	if error != OK:
		push_warning("[MetaSave] Corrupt save, resetting. %s" % json.get_error_message())
		_unlocked_characters.clear()
		_unlocked_weapons.clear()
		meta_currency = 0
	else:
		var data = json.data
		if data is Dictionary:
			meta_currency = maxi(0, int(data.get("meta_currency", 0)))
			var chars = data.get("unlocked_characters")
			if chars is Array:
				for name in chars:
					if name is String and not name.is_empty():
						_unlocked_characters.append(name)
			var weapons = data.get("unlocked_weapons")
			if weapons is Array:
				for name in weapons:
					if name is String and not name.is_empty():
						_unlocked_weapons.append(name)

	_apply_defaults()
	_loaded = true


static func save() -> void:
	var data = {
		"meta_currency": meta_currency,
		"unlocked_characters": Array(_unlocked_characters),
		"unlocked_weapons": Array(_unlocked_weapons)
	}

	var json_str = JSON.stringify(data)
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[MetaSave] Failed to open '%s' for write: %s" % [SAVE_PATH, FileAccess.get_open_error()])
		return

	file.store_string(json_str)


static func get_meta_currency() -> int:
	ensure_loaded()
	return meta_currency


static func add_meta_currency(amount: int) -> void:
	ensure_loaded()
	if amount <= 0:
		return

	meta_currency += amount
	save()


static func try_spend_meta_currency(amount: int) -> bool:
	ensure_loaded()
	if amount < 0 or meta_currency < amount:
		return false

	meta_currency -= amount
	save()
	return true


static func is_character_unlocked(character_name: String) -> bool:
	ensure_loaded()
	if character_name.is_empty():
		return false

	return _unlocked_characters.has(character_name)


static func is_weapon_unlocked(weapon_name: String) -> bool:
	ensure_loaded()
	if weapon_name.is_empty():
		return false

	return _unlocked_weapons.has(weapon_name)


# Unlock cost from DifficultyRating (1-5). Diff 1 free-tier; others scale.
static func get_character_unlock_cost(difficulty_rating: int) -> int:
	var d = clampi(difficulty_rating, 1, 5)
	if d <= 1:
		return 0

	# Diff2=50, Diff3=150, Diff4=300, Diff5=500
	return d * (d - 1) * 25


static func try_unlock_character(character_name: String, cost: int) -> bool:
	ensure_loaded()
	if character_name.is_empty() or _unlocked_characters.has(character_name):
		return false

	if cost > 0 and not try_spend_meta_currency(cost):
		return false

	_unlocked_characters.append(character_name)
	save()
	return true


static func try_unlock_weapon(weapon_name: String, cost: int) -> bool:
	ensure_loaded()
	if weapon_name.is_empty() or _unlocked_weapons.has(weapon_name):
		return false

	if cost > 0 and not try_spend_meta_currency(cost):
		return false

	_unlocked_weapons.append(weapon_name)
	save()
	return true


static func get_unlocked_characters() -> Array[String]:
	ensure_loaded()
	return _unlocked_characters


static func get_unlocked_weapons() -> Array[String]:
	ensure_loaded()
	return _unlocked_weapons


static func _apply_defaults() -> void:
	for name in _default_unlocked_characters:
		_unlocked_characters.append(name)
