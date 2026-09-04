extends Boss
class_name WitchfireMagus

# The Witchfire Magus — the wave 30 lich.
#
# Every other boss in the game is fought in the open, on a torus with no walls
# anywhere. This one is not: the first thing it does is throw a wall of purple
# fire around a rectangle of floor and stand in it with you. That changes what
# its attacks have to be. Nothing it does has to chase you down, because you can
# no longer leave — so all four of its moves are about taking the room away one
# piece at a time and seeing whether you are standing on the piece it took.
#
#   witchfire_bolt  a fan of homing skulls. The only thing it does that is
#                   about you rather than about the floor, and the only reason
#                   standing still between the big moves is not free.
#   pyre_eruption   it leaves the arena entirely. Four rings of the floor go up
#                   one after another, outer, middle or centre, in an order it
#                   does not tell you in advance.
#   meteor_shower   six to eight impacts, the last one twice the size of the
#                   rest. The big one is aimed at where you are standing when
#                   it is called, which is the whole reason to keep moving
#                   through the small ones.
#   flame_wall      a sheet of fire forms along one edge and sweeps the whole
#                   room, leaving the floor it crossed burning behind it. One
#                   lane through it stays clear the whole way, and slides along
#                   the sheet as it comes. Take the lane, outrun the sheet, or
#                   pay the fire and cross.
#
# It wears the dark mage artwork (Assets/sprites/enemies/dark_mage, cut from
# supplied art by tools/build_dark_mage.py) at 1.9.
#
# Its wardens used to wear the same sheet at 0.75, on the argument that the
# thing planting them is the thing the Hunter eventually stands in a room with.
# They do not any more: a painted boss shrunk to a third is a small boss, not a
# servant, and a wave of them made the wave-30 fight open with the player
# unsure which figure was the one with the health bar. They have their own rig
# now (see DarkMage.gd), on these colours, at the roster's size.
#
# The moves overlap on purpose, and that is why this boss does not use the base
# state machine the way the others do. Boss.process_chase picks one move, WINDUP
# holds still for it, RECOVER waits, and only then may the next one start — one
# attack at a time by construction. That is right for a boss whose moves are
# swings. This one's moves are rooms: a ring of floor going up, a slab closing
# off a side, a shower already falling. They are meant to be happening at once.
#
# So the Magus never leaves CHASE. It carries a cooldown per move (_cooldowns),
# all of them ticking at all times — including while it is out of the room for
# an eruption — and each fires the moment it comes up, whatever else is in the
# air. Dodging rings while a wall goes up behind you and the shower called a
# second ago lands on top of both is the fight.
#
# What the base machine's wind-up bought was a warning, and that is not lost:
# every hazard telegraphs on the floor on its own clock before it bites, which
# is the only kind of warning that still means anything when three of them are
# running at once.

# ---------------------------------------------------------------------------
# The room
# ---------------------------------------------------------------------------
# Sized against the 1280x720 viewport at zoom 1: the Hunter can see all four
# walls from the centre. An arena you have to pan around is one where a meteor
# lands on you from off-screen.
@export var arena_half_extents: Vector2 = Vector2(600.0, 330.0)
# What touching the wall costs. Deliberately the largest single number in the
# fight — the wall is not a fence, it is the reason the room is frightening.
@export var arena_border_damage: int = 34

# The most the difficulty may raise this boss above the speed its resource
# authored.
#
# Difficulty.enemy_speed is a floor, not a multiplier: on Dark is the Night it
# hands every enemy 94% of the Hunter's starting speed and throws the authored
# number away entirely. That is the right promise for the roster it was written
# for — whatever is behind you is barely slower than you — but the Magus is not
# a chaser. It fights in a room the Hunter cannot leave, and everything
# dangerous about it is on the floor rather than in its hands. A lich that also
# keeps pace is one standing on top of you while its own ring goes up.
#
# A ceiling rather than a share, so the resource stays the one place the speed
# is set: the harder difficulty still makes it faster, just not without limit.
@export var max_difficulty_speed_multiple: float = 3.0

# ---------------------------------------------------------------------------
# Eruption
# ---------------------------------------------------------------------------
# Three rings: outer, middle, centre. More than three and no ring is wide enough
# to stand in; fewer and the dodge is a coin flip.
const ERUPTION_BANDS := 3
# Gap between one ring landing and the next one being marked.
const ERUPTION_INTERVAL := 1.15
# The beat after the last ring before it walks back in, so the fight does not
# resume on the same frame the floor stops burning.
const ERUPTION_TAIL := 0.7
# The row it leaves and arrives on. The dark mage sheet's death is a collapse
# into witchfire, which is the picture this move wants in both directions:
# forwards it burns away out of the room, backwards it gathers back out of the
# flame somewhere else in it. Timed off the artwork by play_row rather than off
# a constant here, so re-exporting the sheet moves the manoeuvre with it.
const VANISH_ANIM := "death"

# ---------------------------------------------------------------------------
# Meteors
# ---------------------------------------------------------------------------
const METEOR_SPACING := 0.34
# How much bigger the last one is. It is the punchline of the move and has to
# look like it from across the room.
const FINALE_SCALE := 2.1

# ---------------------------------------------------------------------------
# Casting
# ---------------------------------------------------------------------------
# The shortest gap between two casts. Not a serialiser — anything held back by
# it keeps its expired cooldown and goes out a beat later. It exists so two
# moves that come up on the same frame arrive as two things the player can read
# rather than as one flash.
const CAST_GAP := 0.45

var arena: FlameArena

# attack_id -> seconds until it may be cast again. Ticked every frame whatever
# the boss is doing, which is the whole mechanism. Keyed by id, so a phase must
# never list the same move twice — two entries would share one clock and fire
# together for ever.
var _cooldowns: Dictionary = {}
var _cast_gap: float = 0.0

var _absent: bool = false
var _absent_remaining: float = 0.0
# The vanish and the return, in seconds. While either is running the Magus is on
# screen and already out of the fight — no collider, no contact damage, none of
# the moves that come out of its hands — and the only thing left to do is the
# animation. Hittable for that beat, deliberately: a boss you can see standing
# there and cannot shoot is the thing that reads as broken.
var _vanish_remaining: float = 0.0
var _return_remaining: float = 0.0
var _eruptions_left: int = 0
var _eruption_timer: float = 0.0
var _eruption_windup: float = 1.0
var _eruption_damage: int = 24
# Rings already used this cast, so four eruptions never call the same ring twice
# in a row and make the move readable as "wait it out in the corner".
var _last_band: int = -1

func initialize(data: BossData) -> void:
	super.initialize(data)
	_raise_arena()
	_seed_cooldowns(1.2)

# Centred on the Hunter rather than on the boss: BossManager drops the Magus a
# few hundred pixels away, and a room centred on it could open with the Hunter
# already outside his own arena and burning.
func _raise_arena() -> void:
	if arena != null and is_instance_valid(arena):
		arena.queue_free()

	var player := get_tree().get_first_node_in_group("Player") as Node2D
	var center := player.global_position if player != null else global_position
	arena = FlameArena.spawn(self, center, arena_half_extents, arena_border_damage, self)
	global_position = arena.clamp_point(global_position, 80.0)

func _physics_process(delta: float) -> void:
	_tick_eruption(delta)
	# Before the absence check, not after: rings going up do not stop the Magus
	# calling a shower down on top of them. Being out of the room takes away the
	# moves that come out of its hands and nothing else — see _can_cast.
	_tick_casting(delta)

	if _absent:
		# Out of the room. The base machine is frozen whole, so nothing chases
		# and contact damage cannot land; the hazards already marked do not care,
		# they run themselves.
		velocity = Vector2.ZERO
		move_and_slide()
		return

	super._physics_process(delta)

	# It is bound by its own wall like everything else. Without this a chase
	# across the room carries it into its own fire, where it would sit taking
	# no damage and looking like a bug.
	if arena != null and is_instance_valid(arena) and not arena.contains(global_position):
		global_position = arena.clamp_point(global_position, 60.0)

func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null:
		return

	match attack.attack_id:
		"witchfire_bolt":
			_execute_bolts(attack, player)
		"pyre_eruption":
			_execute_eruption(attack)
		"meteor_shower":
			_execute_meteors(attack, player)
		"flame_wall":
			_execute_flame_wall(attack)
		_:
			super.execute_attack(attack, player)

# ---------------------------------------------------------------------------
# Casting loop
# ---------------------------------------------------------------------------
# Movement only. The base version also ticks attack_cooldown_remaining and drops
# into WINDUP when it expires, which is exactly the one-at-a-time rule this boss
# exists to break. _tick_casting owns when anything is cast.
func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	if has_live_target and player != null:
		var speed := get_move_speed() * get_phase_move_multiplier()
		velocity = (player.global_position - global_position).normalized() * speed
	else:
		velocity = Vector2.ZERO

# Staggered rather than all armed at zero: the opening seconds should introduce
# the moves one at a time, and a phase change must not fire the whole kit on the
# frame it happens.
# See max_difficulty_speed_multiple. Capped here rather than by writing a
# smaller number into the resource, because on the harder difficulty the
# resource's number is not the one that gets read.
func get_move_speed() -> float:
	var settled := super.get_move_speed()
	if data == null or data.move_speed <= 0.0:
		return settled

	return minf(settled, data.move_speed * maxf(1.0, max_difficulty_speed_multiple))

func _seed_cooldowns(opening: float) -> void:
	_cooldowns.clear()
	_cast_gap = 0.0

	var phase := get_current_phase()
	if phase == null or phase.attacks == null:
		return

	var index := 0
	for attack: BossAttackPatternData in phase.attacks:
		if attack == null:
			continue

		_cooldowns[attack.attack_id] = opening + index * 1.1 + randf_range(0.0, 0.5)
		index += 1

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if previous_phase_index >= 0:
		# Short opening, because the second half has to arrive as an escalation
		# rather than as a lull while the new kit spins up.
		_seed_cooldowns(0.6)

func _tick_casting(delta: float) -> void:
	if health == null or health.is_dead or state == BossState.DEAD:
		return

	# The hold stops every other actor; a boss casting through it would be
	# swinging at a Hunter whose own weapons are down.
	if WaveManager != null and WaveManager.is_arena_held:
		return

	var phase := get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.is_empty():
		return

	_cast_gap -= delta

	var player := _live_player()
	if player == null:
		# Nobody left to cast at. Cooldowns stop with the fight rather than
		# banking up, so a revived Hunter does not walk back into the whole kit
		# arriving on one frame.
		return

	var ready: Array[BossAttackPatternData] = []

	for attack: BossAttackPatternData in phase.attacks:
		if attack == null:
			continue

		var remaining: float = float(_cooldowns.get(attack.attack_id, 0.0)) - delta
		_cooldowns[attack.attack_id] = remaining
		if remaining <= 0.0 and _can_cast(attack, player):
			ready.append(attack)

	if ready.is_empty() or _cast_gap > 0.0:
		return

	# Random among whatever is up. A move that loses the roll keeps its expired
	# cooldown and is offered again next frame, so nothing starves: what the roll
	# shuffles is the order, never the rate.
	_cast(ready[randi() % ready.size()], player)

# What being out of the room takes away, and nothing else.
func _can_cast(attack: BossAttackPatternData, player: Node2D) -> bool:
	if arena == null or not is_instance_valid(arena):
		return false

	match attack.attack_id:
		# Bolts come out of its hands, and there are no hands in the room.
		"witchfire_bolt":
			return not _absent and player != null
		# One eruption at a time: a second cast while it is already outside would
		# restart the ring count and strand it there.
		"pyre_eruption":
			return not _absent
		_:
			return true

func _cast(attack: BossAttackPatternData, player: Node2D) -> void:
	_cooldowns[attack.attack_id] = maxf(0.6,
		attack.cooldown_seconds * get_phase_cooldown_multiplier() * randf_range(0.9, 1.15))
	_cast_gap = CAST_GAP

	if not _absent and sprite_animator != null:
		sprite_animator.play_attack()

	execute_attack(attack, player)

# ---------------------------------------------------------------------------
# Witchfire bolts
# ---------------------------------------------------------------------------
func _execute_bolts(attack: BossAttackPatternData, player: Node2D) -> void:
	if player == null:
		return

	var count := maxi(1, attack.count)
	var spread := deg_to_rad(18.0)
	var aim := _direction_to(player.global_position)

	for i in range(count):
		# Fanned around the aim so a straight line back at the Magus is not a
		# safe lane. They home, so the fan closes again on its own.
		var offset := spread * (float(i) - (count - 1) * 0.5)
		BossHomingBolt.spawn(
			self, global_position, aim.rotated(offset),
			maxf(60.0, attack.speed),
			roundi(attack.damage * get_phase_damage_multiplier()),
			self,
			attack.duration if attack.duration > 0.0 else 4.0)

# ---------------------------------------------------------------------------
# Eruption
# ---------------------------------------------------------------------------
func _execute_eruption(attack: BossAttackPatternData) -> void:
	if arena == null or not is_instance_valid(arena):
		return

	_eruptions_left = maxi(1, attack.count)
	_eruption_windup = maxf(0.35, attack.duration if attack.duration > 0.0 else 1.0)
	_eruption_damage = roundi(attack.damage * get_phase_damage_multiplier())
	_eruption_timer = 0.0
	_last_band = -1

	# Gone from the room, the way the Belfry Tyrant is gone while aloft: hidden
	# means untargetable (Weapon.is_live_candidate skips a hidden node), and the
	# collider goes with it so the floor it left is genuinely empty. It is not
	# parked outside the wall where the Hunter could still shoot it — an
	# unreachable-but-shootable boss turns the one move he can only run from
	# into a free damage window.
	_absent = true
	_absent_remaining = _eruptions_left * ERUPTION_INTERVAL + _eruption_windup + ERUPTION_TAIL
	_begin_vanish()
	# Nothing has to hold the state machine open: it never left CHASE, and
	# _physics_process skips the base entirely while _absent. _tick_eruption is
	# the only clock the manoeuvre runs on.

func _tick_eruption(delta: float) -> void:
	if not _absent:
		return

	if _vanish_remaining > 0.0:
		# Still burning away. The rings do not wait for it — the first one is
		# marked on the frame the move was cast, so the floor starts working
		# while the Magus is still leaving it.
		_vanish_remaining -= delta
		if _vanish_remaining <= 0.0:
			_finish_vanish()

	if _return_remaining > 0.0:
		# Back in the room and gathering itself in. The rings are done; this is
		# the last beat before the fight is a fight again.
		_return_remaining -= delta
		if _return_remaining <= 0.0:
			_finish_return()

		return

	_absent_remaining -= delta
	_eruption_timer -= delta

	if _eruptions_left > 0 and _eruption_timer <= 0.0:
		_eruption_timer = ERUPTION_INTERVAL
		_eruptions_left -= 1
		_mark_ring()

	if _absent_remaining <= 0.0:
		_begin_return()

func _mark_ring() -> void:
	if arena == null or not is_instance_valid(arena):
		return

	var band := randi() % ERUPTION_BANDS
	if band == _last_band:
		# One re-roll, not a loop: it should rarely repeat, not never — a ring
		# that is guaranteed safe because it just fired is a free square.
		band = (band + 1 + (randi() % (ERUPTION_BANDS - 1))) % ERUPTION_BANDS

	_last_band = band
	FlameEruption.spawn(self, arena, band, ERUPTION_BANDS, _eruption_windup,
		_eruption_damage, self)

# Out of the fight on this frame — collider and contact hitbox off, hands empty
# — but not off the screen yet: it burns down the death row first, so the move
# opens with the Magus leaving rather than with the Magus blinking out.
func _begin_vanish() -> void:
	_return_remaining = 0.0
	_set_collidable(false)
	_vanish_remaining = _play_flourish(false, true)
	if _vanish_remaining <= 0.0:
		# A rig with no death row still has to go. Straight to hidden, which is
		# what this move did before it had an animation to do it with.
		_finish_vanish()

func _finish_vanish() -> void:
	_vanish_remaining = 0.0
	set_hidden_by_ability(true)

func _begin_return() -> void:
	_absent_remaining = 0.0
	_eruptions_left = 0

	if arena != null and is_instance_valid(arena):
		# Back in at a corner rather than on top of the Hunter: reappearing in
		# his face after a move he could only run from is a free hit.
		global_position = arena.random_point(140.0)

	# Visible again and running the death row backwards, but still no collider:
	# the arrival gets the same beat of grace the departure did, and the Hunter
	# gets a moment to see where in the room it came back before it matters.
	set_hidden_by_ability(false)
	_return_remaining = _play_flourish(true, false)
	if _return_remaining <= 0.0:
		_finish_return()

func _finish_return() -> void:
	_return_remaining = 0.0
	_absent = false
	_set_collidable(true)

	if sprite_animator != null:
		sprite_animator.resume_locomotion()

# Runs the vanish row in one direction or the other and reports its length, or
# 0.0 when this sheet has no such row and the manoeuvre has to be instant.
func _play_flourish(reverse: bool, hold_last: bool) -> float:
	if sprite_animator == null:
		return 0.0

	return sprite_animator.play_row(VANISH_ANIM, reverse, hold_last)

# ---------------------------------------------------------------------------
# Meteor shower
# ---------------------------------------------------------------------------
func _execute_meteors(attack: BossAttackPatternData, player: Node2D) -> void:
	if arena == null or not is_instance_valid(arena):
		return

	# 6-8 off a count of 7: the exact number is not something the player can use,
	# but a shower that is never the same length keeps them counting impacts
	# rather than counting to seven.
	var count := maxi(2, attack.count + (randi() % 3) - 1)
	var windup := maxf(0.35, attack.windup_seconds)
	var radius := maxf(40.0, attack.radius)
	# Not pre-scaled by the phase, unlike the bolts and the wall: the impact goes
	# through apply_damage_in_radius, which applies the multiplier itself, and
	# doing it here as well squared it.
	var damage := roundi(attack.damage)

	for i in range(count):
		var finale := i == count - 1
		var delay := i * METEOR_SPACING
		var target := arena.random_point(radius * 0.6 + 40.0)
		if finale and player != null:
			# The last one is aimed. Read at call time, not at impact: it is a
			# meteor, not a heat seeker, and the dodge has to be possible.
			target = arena.clamp_point(player.global_position, radius * 0.6 + 40.0)

		_schedule_meteor(delay, target,
			radius * (FINALE_SCALE if finale else 1.0),
			roundi(damage * (1.6 if finale else 1.0)),
			windup)

func _schedule_meteor(delay: float, target: Vector2, radius: float, damage: int,
	windup: float) -> void:
	var tree := get_tree()
	if tree == null:
		return

	if delay <= 0.0:
		_drop_meteor(target, radius, damage, windup)
		return

	# process_always off: a wave can end mid-fight on difficulties that do not
	# hold it open for the boss, and a meteor still landing while the Ossuary is
	# up would hit a Hunter who is looking at a shop.
	tree.create_timer(delay, false).timeout.connect(func():
		if not is_instance_valid(self) or state == BossState.DEAD:
			return

		_drop_meteor(target, radius, damage, windup))

func _drop_meteor(target: Vector2, radius: float, damage: int, windup: float) -> void:
	# The telegraph owns the timing and the picture; the impact is resolved here
	# so it goes through the boss's own phase multiplier rather than being baked
	# into the decal at spawn time.
	BossAoeTelegraph.spawn(self, target, radius, windup, damage, self, false, func():
		if not is_instance_valid(self):
			return

		BossGroundQuake.spawn(self, target, radius, radius * 0.45,
			7 if radius < 100.0 else 11, 1.8)
		# The quake is the ground being hit; the plume is what hit it. Both, or
		# a meteor from a lich reads as a rock.
		WitchfirePlume.spawn(self, target, radius)
		apply_damage_in_radius(target, radius, damage))

# ---------------------------------------------------------------------------
# Flame wall
# ---------------------------------------------------------------------------
func _execute_flame_wall(attack: BossAttackPatternData) -> void:
	if arena == null or not is_instance_valid(arena):
		return

	var sides := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var picked: Array = []
	for i in range(maxi(1, attack.count)):
		if sides.is_empty():
			break

		# Two sweeps never from the same edge, and never from opposite ones
		# either: sheets closing in from left and right leave the Hunter in a
		# shrinking strip with burnt ground behind both of them and no side to
		# run to. Perpendicular is a corner closing, which is hard; head-on is a
		# room with no answer in it. Adjacent edges only.
		var side: Vector2 = sides[randi() % sides.size()]
		sides.erase(side)
		sides.erase(-side)
		picked.append(side)

	for side in picked:
		FlameWall.spawn_sweep(
			self, arena, side,
			maxf(30.0, attack.radius),
			attack.speed,
			attack.duration if attack.duration > 0.0 else 2.8,
			maxf(45.0, attack.range),
			maxf(0.25, attack.windup_seconds),
			roundi(attack.damage * get_phase_damage_multiplier()),
			self)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
# The base flinches on damage, which is right everywhere except here: a hurt row
# cutting in would eat the vanish or the return, and the move would be back to
# the Magus popping out of existence. Hit it while it is burning away and it
# burns away anyway.
func _on_health_changed(current_health: int, max_health: int) -> void:
	if _vanish_remaining > 0.0 or _return_remaining > 0.0:
		return

	super._on_health_changed(current_health, max_health)

func _on_died(source: Node) -> void:
	# Dying while out of the room would otherwise leave an invisible corpse and
	# a wall of fire around an arena with nothing in it.
	if _absent:
		_absent = false
		_vanish_remaining = 0.0
		_return_remaining = 0.0
		_set_intangible(false)

	_drop_arena()
	super._on_died(source)

func _exit_tree() -> void:
	_drop_arena()
	super._exit_tree()

# The room belongs to the fight, not to the world: whichever way the encounter
# ends, the Hunter gets the arena back.
func _drop_arena() -> void:
	if arena != null and is_instance_valid(arena):
		arena.queue_free()

	arena = null

# Hidden means untargetable (Weapon.is_live_candidate), and the collider and
# contact hitbox go with it so the floor it left is genuinely empty. Split in
# two because the vanish and the return are exactly the moments where the second
# half is already true and the first is not yet.
func _set_intangible(on: bool) -> void:
	set_hidden_by_ability(on)
	_set_collidable(not on)

func _set_collidable(on: bool) -> void:
	if collision_shape != null:
		collision_shape.set_deferred("disabled", not on)

	if contact_hitbox != null:
		contact_hitbox.set_deferred("monitoring", on)

func _direction_to(point: Vector2) -> Vector2:
	var delta := point - global_position
	return delta.normalized() if delta.length_squared() > 0.0001 else Vector2.RIGHT

# A Hunter who is actually still standing. Boss._physics_process works this out
# for itself, but _tick_casting runs outside it — including while the Magus is
# out of the room, where the base never gets a turn at all.
func _live_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("Player"):
		var body := node as Node2D
		if body == null:
			continue

		var hp: HealthComponent = body.get_node_or_null("HealthComponent")
		if hp != null and hp.is_dead:
			continue

		return body

	return null
