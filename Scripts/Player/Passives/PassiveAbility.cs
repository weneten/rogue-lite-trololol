using Godot;
using Nightbane.Combat;
using Nightbane.Resources;

namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Base hook for a Hunter's unique passive ability. One concrete subclass per CharacterData
/// (selected via PassiveAbilityFactory off CharacterData.PassiveId) attached as a child Node of
/// Player at run start (see Player.ApplyCharacterData). Subclasses override whichever hooks their
/// effect needs; the rest default to no-ops. Continuous effects (DoTs, ramping bonuses, familiar
/// upkeep) use Godot's own _Process on the subclass itself rather than a bespoke tick list, so
/// pausing the tree (level-up/shop) automatically pauses them too, same as everything else.
/// </summary>
public abstract partial class PassiveAbility : Node
{
    protected Player Owner { get; private set; }
    protected PlayerStats Stats { get; private set; }
    protected HealthComponent Health { get; private set; }
    protected CharacterData Data { get; private set; }

    /// <summary>Wires the shared references and runs one-time setup. Called by Player right after AddChild.</summary>
    public void Setup(Player owner, PlayerStats stats, HealthComponent health, CharacterData data)
    {
        Owner = owner;
        Stats = stats;
        Health = health;
        Data = data;
        OnInitialize();
    }

    /// <summary>One-shot setup: apply flat stat bonuses, spawn familiars, etc. Runs once, right after Setup.</summary>
    protected virtual void OnInitialize() { }

    /// <summary>Called by PlayerStats.NotifyDamageDealt after every weapon hit the player lands.</summary>
    public virtual void OnDamageDealt(int amount, Node target) { }

    /// <summary>Called whenever the player's HealthComponent takes damage (post-armor/dodge).</summary>
    public virtual void OnDamageTaken(int amount, Node source) { }

    /// <summary>Called whenever any enemy dies (single-player game, so always a player kill).</summary>
    public virtual void OnEnemyKilled(Node enemy) { }
}
