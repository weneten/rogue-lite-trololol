using Godot;
using Nightbane.Resources;

namespace Nightbane.Bosses;

/// <summary>
/// The Hollow Cardinal — homing curse bolts, ritual circles that punish standing still,
/// phase 2 cultist adds.
/// </summary>
public partial class HollowCardinal : Boss
{
    private bool _phase2Announced;

    protected override void OnPhaseEntered(int phaseIndex, int previousPhaseIndex = -1)
    {
        base.OnPhaseEntered(phaseIndex, previousPhaseIndex);
        if (phaseIndex >= 1 && !_phase2Announced)
        {
            _phase2Announced = true;
            GD.Print("[Boss] Hollow Cardinal begins the Dark Mass!");
        }
    }

    protected override void BeginTelegraph(BossAttackPatternData attack, Node2D player)
    {
        if (attack == null)
        {
            return;
        }

        string id = attack.AttackId ?? "";
        switch (id)
        {
            case "curse_bolt":
                // Self cast glow; bolts fire after wind-up.
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, GlobalPosition, 48f, attack.WindupSeconds, 0, this, dealDamageOnComplete: false);
                break;

            case "ritual_circle":
                // Circle under player feet.
                Vector2 pos = player?.GlobalPosition ?? GlobalPosition;
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, pos, attack.Radius, attack.WindupSeconds, 0, this, dealDamageOnComplete: false);
                break;

            case "summon_cultists":
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, GlobalPosition, attack.Radius, attack.WindupSeconds, 0, this, dealDamageOnComplete: false);
                break;

            default:
                base.BeginTelegraph(attack, player);
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
            case "curse_bolt":
                ExecuteCurseBolts(attack, player);
                break;
            case "ritual_circle":
                ExecuteRitualCircle(attack, player);
                break;
            case "summon_cultists":
                ExecuteSummonCultists(attack);
                break;
            default:
                base.ExecuteAttack(attack, player);
                break;
        }

        RememberAttackCooldown(attack);
    }

    private void ExecuteCurseBolts(BossAttackPatternData attack, Node2D player)
    {
        if (player == null)
        {
            return;
        }

        int count = Mathf.Max(1, attack.Count);
        Vector2 baseDir = (player.GlobalPosition - GlobalPosition).Normalized();
        if (baseDir == Vector2.Zero)
        {
            baseDir = Vector2.Right;
        }

        for (int i = 0; i < count; i++)
        {
            float spread = count == 1 ? 0f : Mathf.Lerp(-0.45f, 0.45f, i / (float)(count - 1));
            Vector2 dir = baseDir.Rotated(spread);
            BossHomingBolt.Spawn(
                this,
                GlobalPosition + dir * 24f,
                dir,
                attack.Speed,
                Mathf.RoundToInt(attack.Damage),
                this,
                lifetime: attack.Duration > 0f ? attack.Duration : 5f,
                turnRate: 3.2f + CurrentPhaseIndex * 0.6f);
        }
    }

    private void ExecuteRitualCircle(BossAttackPatternData attack, Node2D player)
    {
        Vector2 pos = ActiveTelegraph != null && GodotObject.IsInstanceValid(ActiveTelegraph)
            ? ActiveTelegraph.GlobalPosition
            : player?.GlobalPosition ?? GlobalPosition;

        // Phase 2: dual circles.
        int rings = CurrentPhaseIndex >= 1 ? Mathf.Max(2, attack.Count) : Mathf.Max(1, attack.Count);
        for (int i = 0; i < rings; i++)
        {
            Vector2 ringPos = pos;
            if (i > 0)
            {
                ringPos += new Vector2(attack.Range * 0.5f, 0).Rotated(Mathf.Tau * i / rings + (float)GD.Randf());
            }

            BossRitualCircle.Spawn(
                this,
                ringPos,
                attack.Radius,
                attack.Duration > 0f ? attack.Duration : 5f,
                Mathf.RoundToInt(attack.Damage),
                this);
        }
    }

    private void ExecuteSummonCultists(BossAttackPatternData attack)
    {
        int count = Mathf.Max(1, attack.Count);
        for (int i = 0; i < count; i++)
        {
            float angle = Mathf.Tau * i / count + (float)GD.RandRange(0, 0.5);
            Vector2 pos = GlobalPosition + new Vector2(attack.Range, 0).Rotated(angle);
            SpawnMinion(
                pos,
                "Cultist",
                new Color(0.45f, 0.2f, 0.55f, 1f),
                maxHealth: 22,
                moveSpeed: 100f,
                attackDamage: 7f,
                attackCooldown: 1.1f);
        }
    }

    protected override void ProcessChase(double delta, Node2D player, bool hasLiveTarget)
    {
        // Prefers mid-range kiting.
        if (hasLiveTarget && player != null)
        {
            float speed = Data.MoveSpeed * GetPhaseMoveMultiplier();
            float dist = GlobalPosition.DistanceTo(player.GlobalPosition);
            Vector2 dir = (player.GlobalPosition - GlobalPosition).Normalized();
            float preferred = 220f;

            if (dist < preferred - 40f)
            {
                Velocity = -dir * speed;
            }
            else if (dist > preferred + 40f)
            {
                Velocity = dir * speed * 0.85f;
            }
            else
            {
                Velocity = new Vector2(-dir.Y, dir.X) * speed * 0.5f;
            }

            AttackCooldownRemaining -= delta;
            if (AttackCooldownRemaining <= 0)
            {
                TryBeginAttack(player);
            }

            return;
        }

        base.ProcessChase(delta, player, hasLiveTarget);
    }
}
