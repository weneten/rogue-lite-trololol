using Godot;
using Nightbane.Resources;

namespace Nightbane.Bosses;

/// <summary>
/// The Gravekeeper Colossus — slow heavy melee, ground-smash shockwave zones, summons ghouls.
/// </summary>
public partial class GravekeeperColossus : Boss
{
    protected override void BeginTelegraph(BossAttackPatternData attack, Node2D player)
    {
        if (attack == null)
        {
            return;
        }

        string id = attack.AttackId ?? "";
        switch (id)
        {
            case "ground_smash":
                // Multiple shockwave rings at staggered offsets around player / self.
                Vector2 center = player?.GlobalPosition ?? GlobalPosition;
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, center, attack.Radius, attack.WindupSeconds,
                    Mathf.RoundToInt(attack.Damage), this, dealDamageOnComplete: false);

                // Extra warning zones (visual only; hit resolved in ExecuteAttack).
                int extra = Mathf.Max(0, attack.Count - 1);
                for (int i = 0; i < extra; i++)
                {
                    float a = Mathf.Tau * i / Mathf.Max(1, extra) + (float)GD.RandRange(0, 1);
                    Vector2 pos = center + new Vector2(attack.Range * 0.45f, 0).Rotated(a);
                    BossAoeTelegraph.Spawn(
                        this, pos, attack.Radius * 0.7f, attack.WindupSeconds,
                        0, this, dealDamageOnComplete: false);
                }
                break;

            case "summon_ghouls":
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, GlobalPosition, attack.Radius, attack.WindupSeconds, 0, this, dealDamageOnComplete: false);
                break;

            case "heavy_melee":
            default:
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, GlobalPosition, attack.Radius, attack.WindupSeconds,
                    Mathf.RoundToInt(attack.Damage), this, dealDamageOnComplete: false);
                break;
        }
    }

    protected override void ExecuteAttack(BossAttackPatternData attack, Node2D player)
    {
        if (attack == null)
        {
            return;
        }

        switch (attack.AttackId)
        {
            case "ground_smash":
                ExecuteGroundSmash(attack, player);
                break;
            case "summon_ghouls":
                ExecuteSummonGhouls(attack);
                break;
            case "heavy_melee":
            default:
                ApplyDamageInRadius(GlobalPosition, attack.Radius, Mathf.RoundToInt(attack.Damage));
                break;
        }

        RememberAttackCooldown(attack);
    }

    private void ExecuteGroundSmash(BossAttackPatternData attack, Node2D player)
    {
        Vector2 center = ActiveTelegraph != null && GodotObject.IsInstanceValid(ActiveTelegraph)
            ? ActiveTelegraph.GlobalPosition
            : player?.GlobalPosition ?? GlobalPosition;

        ApplyDamageInRadius(center, attack.Radius, Mathf.RoundToInt(attack.Damage));

        int extra = Mathf.Max(0, attack.Count - 1);
        for (int i = 0; i < extra; i++)
        {
            float a = Mathf.Tau * i / Mathf.Max(1, extra);
            Vector2 pos = center + new Vector2(attack.Range * 0.45f, 0).Rotated(a);
            ApplyDamageInRadius(pos, attack.Radius * 0.7f, Mathf.RoundToInt(attack.Damage * 0.75f));
        }
    }

    private void ExecuteSummonGhouls(BossAttackPatternData attack)
    {
        int count = Mathf.Max(1, attack.Count);
        for (int i = 0; i < count; i++)
        {
            float angle = Mathf.Tau * i / count;
            // "Graves" pop around the colossus.
            Vector2 gravePos = GlobalPosition + new Vector2(attack.Range, 0).Rotated(angle);
            BossAoeTelegraph.Spawn(this, gravePos, 28f, 0.2f, 0, this, dealDamageOnComplete: false);
            SpawnMinion(
                gravePos,
                "Ghoul",
                new Color(0.36f, 0.5f, 0.3f, 1f),
                maxHealth: 18,
                moveSpeed: 140f,
                attackDamage: 6f,
                attackCooldown: 0.85f);
        }
    }

    protected override void ProcessChase(double delta, Node2D player, bool hasLiveTarget)
    {
        // Deliberately slow: never sprints; base MoveSpeed already low.
        base.ProcessChase(delta, player, hasLiveTarget);
    }
}
