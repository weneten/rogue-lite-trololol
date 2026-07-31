using Godot;

namespace Nightbane.Combat;

/// <summary>
/// Reusable HP tracker attachable to any actor (Player, Enemy, Boss). Owns no game-system
/// knowledge (currency rewards, EventBus, etc.) — the owning actor script listens to
/// Damaged/Died and decides what global signals to raise (e.g. Player raises
/// EventBus.OnPlayerDamaged/OnPlayerDied, an Enemy would raise EventBus.OnEnemyKilled).
/// </summary>
public partial class HealthComponent : Node
{
    [Export] public int MaxHealth { get; set; } = 100;

    /// <summary>Flat damage reduction applied after IncomingDamageMultiplier, before the hit lands
    /// (minimum 1 damage always gets through). Driven by CharacterData.StartingArmor / passives
    /// like Iron Widow's Taunt Armor. Defaults to 0 so enemies/bosses are unaffected.</summary>
    [Export] public int Armor { get; set; } = 0;
    /// <summary>Chance [0,1] to negate an incoming hit entirely before any reduction. Driven by
    /// CharacterData.StartingDodgeChance. Defaults to 0 so enemies/bosses are unaffected.</summary>
    [Export] public float DodgeChance { get; set; } = 0f;
    /// <summary>Multiplies incoming damage before Armor is subtracted; set by PlayerStats for
    /// passives like the Reaper's HP-for-damage tradeoff (deals more, takes more). Starts at 1
    /// (no change) so enemies/bosses are unaffected unless explicitly wired.</summary>
    public float IncomingDamageMultiplier { get; set; } = 1f;

    public int CurrentHealth { get; private set; }
    public bool IsDead { get; private set; }

    /// <summary>Fired on every HP change (damage or heal) with the resulting value.</summary>
    [Signal]
    public delegate void HealthChangedEventHandler(int currentHealth, int maxHealth);

    /// <summary>Fired only on damage, before HealthChanged, carrying the raw damage dealt.</summary>
    [Signal]
    public delegate void DamagedEventHandler(int amount, Node source);

    [Signal]
    public delegate void DiedEventHandler(Node source);

    public override void _Ready()
    {
        CurrentHealth = MaxHealth;
    }

    /// <summary>Applies damage (after DodgeChance/IncomingDamageMultiplier/Armor); clamps at 0 and
    /// triggers Die() exactly once. No-op once dead or fully dodged.</summary>
    public void TakeDamage(int amount, Node source = null)
    {
        if (IsDead || amount <= 0)
        {
            return;
        }

        if (DodgeChance > 0f && GD.Randf() < DodgeChance)
        {
            return;
        }

        // Armor is a flat post-multiplier reduction; a hit always does at least 1 damage so
        // stacking Armor can never make an actor fully unkillable.
        int scaledAmount = Mathf.Max(1, Mathf.RoundToInt(amount * IncomingDamageMultiplier) - Armor);

        CurrentHealth = Mathf.Max(0, CurrentHealth - scaledAmount);
        EmitSignal(SignalName.Damaged, scaledAmount, source);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);

        if (CurrentHealth <= 0)
        {
            Die(source);
        }
    }

    /// <summary>Restores HP up to MaxHealth. No-op once dead.</summary>
    public void Heal(int amount)
    {
        if (IsDead || amount <= 0)
        {
            return;
        }

        CurrentHealth = Mathf.Min(MaxHealth, CurrentHealth + amount);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
    }

    /// <summary>Raises MaxHealth by amount (e.g. a level-up upgrade) and grants the same amount of
    /// current HP immediately, so the boost is felt right away rather than only on next heal. No-op once dead.</summary>
    public void IncreaseMaxHealth(int amount)
    {
        if (IsDead || amount <= 0)
        {
            return;
        }

        MaxHealth += amount;
        CurrentHealth = Mathf.Min(MaxHealth, CurrentHealth + amount);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
    }

    /// <summary>Forces death regardless of remaining HP (e.g. instant-kill effects). Idempotent.</summary>
    public void Die(Node source = null)
    {
        if (IsDead)
        {
            return;
        }

        IsDead = true;
        CurrentHealth = 0;
        EmitSignal(SignalName.Died, source);
    }

    /// <summary>Resets IsDead and restores HP. Used by respawning actors (e.g. TargetDummy) — never called on Player/normal enemies which stay dead.</summary>
    public void Revive(int? toHealth = null)
    {
        IsDead = false;
        CurrentHealth = Mathf.Clamp(toHealth ?? MaxHealth, 0, MaxHealth);
        EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);
    }
}
