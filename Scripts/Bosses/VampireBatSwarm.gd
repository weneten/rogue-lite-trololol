extends Node2D
class_name VampireBatSwarm

# The Voivode's called bats. They circle above the arena, stoop on the player
# five times in quick succession, then climb away and are gone — the swarm is
# an event with an end, not a set of minions the player has to clear.
#
# Each stoop is telegraphed on the ground before it lands, the same contract
# every other boss attack in the fight keeps: the bats are fast enough that
# without the marker they would simply be unavoidable damage.
#
# The bats are drawn here rather than loaded from a sheet. They exist for about
# a fifth of a second each pass, at speed, as a silhouette — an animated sprite
# would be work nobody could see.

const CIRCLE_RADIUS := 190.0
const CIRCLE_HEIGHT := 150.0
const APPROACH := 420.0

var dive_count: int = 5
var dive_interval: float = 0.55
var telegraph_seconds: float = 0.32
var strike_radius: float = 52.0
var damage: int = 12
var bat_count: int = 5
var owner_boss: Boss

var _bats: Array[Node2D] = []
var _dives_left: int
var _timer: float
var _leaving: bool
var _age: float

func _ready() -> void:
	z_index = 4
	_dives_left = dive_count
	_timer = 0.35
	for i in range(maxi(1, bat_count)):
		var bat := _make_bat()
		add_child(bat)
		_bats.append(bat)

func _process(delta: float) -> void:
	_age += delta
	_circle(delta)

	# The flock belongs to the vampire. Kill him mid-swarm and they scatter
	# rather than finishing his work — and rather than handing a freed Boss to
	# the next telegraph, which is a hard error, not a wrong-looking frame.
	if not _leaving and _living_boss() == null and owner_boss != null:
		_leaving = true
		_age = 0.0

	if _leaving:
		# Climb out and vanish; free once the whole flock is off the top.
		if _age > 1.4:
			queue_free()

		return

	_timer -= delta
	if _timer > 0.0:
		return

	if _dives_left <= 0:
		_leaving = true
		_age = 0.0
		return

	_dives_left -= 1
	_timer = dive_interval
	_begin_dive()

func _circle(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	var centre := player.global_position if player != null else global_position
	for i in range(_bats.size()):
		var bat := _bats[i]
		if bat == null or not is_instance_valid(bat) or bat.get_meta("diving", false):
			continue

		var angle := _age * 2.2 + TAU * i / maxi(1, _bats.size())
		var lift := CIRCLE_HEIGHT + (400.0 * _age if _leaving else 0.0)
		var target := centre + Vector2(cos(angle) * CIRCLE_RADIUS, sin(angle) * 34.0 - lift)
		bat.global_position = bat.global_position.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
		bat.modulate.a = clampf(1.0 - _age * 0.8, 0.0, 1.0) if _leaving else 1.0
		_flap(bat, delta)

func _begin_dive() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var target: Vector2 = player.global_position
	var boss := _living_boss()
	BossAoeTelegraph.spawn(self, target, strike_radius, telegraph_seconds, damage,
		boss if boss != null else self, false)

	var tree := get_tree()
	if tree == null:
		return

	tree.create_timer(telegraph_seconds).timeout.connect(func():
		if is_instance_valid(self):
			_strike(target))

func _strike(target: Vector2) -> void:
	var bat := _pick_free_bat()
	if bat == null:
		return

	bat.set_meta("diving", true)
	var entry := target + Vector2(-APPROACH, -APPROACH * 0.55)
	var exit_point := target + Vector2(APPROACH, -APPROACH * 0.55)
	bat.global_position = entry

	var tween := create_tween()
	tween.tween_property(bat, "global_position", target, 0.13)
	tween.tween_callback(func(): _resolve_hit(target))
	tween.tween_property(bat, "global_position", exit_point, 0.16)
	tween.tween_callback(func(): bat.set_meta("diving", false))

func _resolve_hit(target: Vector2) -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null or target.distance_to(player.global_position) > strike_radius:
		return

	var boss := _living_boss()
	if boss != null:
		boss.apply_damage_to_player(damage)
		return

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health != null and not health.is_dead:
		health.take_damage(damage, self)

# The owner, or null once it has been freed. Every use site needs this: the
# swarm outlives one fight's worth of bad luck by design.
func _living_boss() -> Boss:
	return owner_boss if owner_boss != null and is_instance_valid(owner_boss) else null

func _pick_free_bat() -> Node2D:
	for bat in _bats:
		if is_instance_valid(bat) and not bat.get_meta("diving", false):
			return bat

	return _bats[0] if _bats.size() > 0 and is_instance_valid(_bats[0]) else null

func _make_bat() -> Node2D:
	var bat := Node2D.new()
	bat.set_meta("diving", false)
	bat.set_meta("phase", randf() * TAU)

	var body := Polygon2D.new()
	body.color = Color(0.11, 0.06, 0.12, 1.0)
	body.polygon = PackedVector2Array([
		Vector2(0, -4), Vector2(4, 0), Vector2(0, 6), Vector2(-4, 0)])
	bat.add_child(body)

	for side in [-1.0, 1.0]:
		var wing := Polygon2D.new()
		wing.name = "Wing%d" % int(side)
		wing.color = Color(0.16, 0.07, 0.14, 1.0)
		wing.polygon = PackedVector2Array([
			Vector2(0, -2), Vector2(13 * side, -7), Vector2(17 * side, 1),
			Vector2(9 * side, 2), Vector2(0, 4)])
		bat.add_child(wing)

	return bat

func _flap(bat: Node2D, delta: float) -> void:
	var phase: float = bat.get_meta("phase", 0.0) + delta * 17.0
	bat.set_meta("phase", phase)
	var beat := 0.35 + 0.65 * absf(sin(phase))
	for child in bat.get_children():
		if child is Polygon2D and child.name.begins_with("Wing"):
			(child as Polygon2D).scale = Vector2(1.0, beat)

static func summon(host: Node, position: Vector2, dives: int, damage: int, radius: float,
	interval: float, boss: Boss) -> VampireBatSwarm:
	var swarm := VampireBatSwarm.new()
	swarm.dive_count = maxi(1, dives)
	swarm.damage = damage
	swarm.strike_radius = radius
	swarm.dive_interval = interval
	swarm.owner_boss = boss

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(swarm)
	swarm.global_position = position
	return swarm
