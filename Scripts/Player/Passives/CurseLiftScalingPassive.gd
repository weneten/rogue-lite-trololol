extends PassiveAbility
class_name CurseLiftScalingPassive

# Cursed Noble — an old curse loosens its grip the longer he survives: damage multiplier ramps
# linearly from +0 towards +PassiveValueB over time, growing by PassiveValueA per minute survived,
# capped at PassiveValueB. Ticks every frame in _Process (which — like everything else on this
# Node — is naturally suspended whenever the tree pauses for level-up/shop screens).

var _elapsed_seconds: float = 0.0

func _process(delta: float) -> void:
	_elapsed_seconds += delta

	var cap: float = data.passive_value_b if data.passive_value_b > 0 else 1.0
	var bonus: float = minf(cap, data.passive_value_a * (_elapsed_seconds / 60.0))
	stats.set_curse_damage_bonus(bonus)
