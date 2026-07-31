using Godot;

namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Cursed Noble — an old curse loosens its grip the longer he survives: damage multiplier ramps
/// linearly from +0 towards +PassiveValueB over time, growing by PassiveValueA per minute survived,
/// capped at PassiveValueB. Ticks every frame in _Process (which — like everything else on this
/// Node — is naturally suspended whenever the tree pauses for level-up/shop screens).
/// </summary>
public partial class CurseLiftScalingPassive : PassiveAbility
{
    private double _elapsedSeconds;

    public override void _Process(double delta)
    {
        _elapsedSeconds += delta;

        float cap = Data.PassiveValueB > 0 ? Data.PassiveValueB : 1f;
        float bonus = Mathf.Min(cap, Data.PassiveValueA * (float)(_elapsedSeconds / 60.0));
        Stats.SetCurseDamageBonus(bonus);
    }
}
