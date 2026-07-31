using Godot;
using Nightbane.Combat;

namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Iron Widow — an unmovable wall who punishes whoever dares strike her: PassiveValueA is flat
/// bonus Armor applied once at run start; PassiveValueB is the fraction of every hit she takes
/// reflected straight back at its source's HealthComponent (her "iron thorns"), standing in for a
/// taunt since every enemy in this single-player arena already always targets the Player.
/// </summary>
public partial class TauntArmorPassive : PassiveAbility
{
    protected override void OnInitialize()
    {
        if (Health != null)
        {
            Health.Armor += Mathf.RoundToInt(Data.PassiveValueA);
        }
    }

    public override void OnDamageTaken(int amount, Node source)
    {
        if (source == null || Data.PassiveValueB <= 0f)
        {
            return;
        }

        HealthComponent sourceHealth = source.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (sourceHealth != null && !sourceHealth.IsDead)
        {
            sourceHealth.TakeDamage(Mathf.RoundToInt(amount * Data.PassiveValueB), Owner);
        }
    }
}
