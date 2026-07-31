using Godot;
using Nightbane.Resources;

namespace Nightbane.Bosses;

/// <summary>
/// The Bat-Winged Count — blinks, summons bat swarms, blood frenzy at ~50% HP
/// (faster attacks via phase cooldown multiplier + life drain on hits).
/// </summary>
public partial class BatWingedCount : Boss
{
    private bool _frenzyAnnounced;

    protected override void OnPhaseEntered(int phaseIndex, int previousPhaseIndex = -1)
    {
        base.OnPhaseEntered(phaseIndex, previousPhaseIndex);
        if (phaseIndex >= 1 && !_frenzyAnnounced)
        {
            _frenzyAnnounced = true;
            GD.Print("[Boss] Bat-Winged Count enters Blood Frenzy!");
            // Brief self telegraph as visual flare.
            BossAoeTelegraph.Spawn(this, GlobalPosition, 70f, 0.35f, 0, this, dealDamageOnComplete: false);
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
            case "blink":
                // Destination flash near player.
                if (player != null)
                {
                    Vector2 dest = player.GlobalPosition
                        + new Vector2(attack.Range, 0).Rotated((float)GD.RandRange(0.0, Mathf.Tau));
                    ActiveTelegraph = BossAoeTelegraph.Spawn(
                        this, dest, 36f, attack.WindupSeconds, 0, this, dealDamageOnComplete: false);
                }
                break;

            case "bat_swarm":
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, GlobalPosition, attack.Radius, attack.WindupSeconds, 0, this, dealDamageOnComplete: false);
                break;

            case "blood_slash":
            default:
                // Slash arc centered on boss toward player.
                ActiveTelegraph = BossAoeTelegraph.Spawn(
                    this, GlobalPosition, attack.Radius, attack.WindupSeconds,
                    Mathf.RoundToInt(attack.Damage), this, dealDamageOnComplete: false);
                break;
        }
    }

    protected override void ExecuteAttack(BossAttackPatternData attack, Node2D player)
    {
        if (attack == null || player == null)
        {
            return;
        }

        float heal = attack.HealFraction;
        // Blood frenzy phase also forces life drain even if pattern heal is 0.
        if (CurrentPhaseIndex >= 1 && heal <= 0f)
        {
            heal = 0.35f;
        }

        switch (attack.AttackId)
        {
            case "blink":
                ExecuteBlink(attack, player, heal);
                break;
            case "bat_swarm":
                ExecuteBatSwarm(attack);
                break;
            case "blood_slash":
            default:
                ApplyDamageInRadius(GlobalPosition, attack.Radius, Mathf.RoundToInt(attack.Damage), heal);
                break;
        }

        RememberAttackCooldown(attack);
    }

    private void ExecuteBlink(BossAttackPatternData attack, Node2D player, float heal)
    {
        Vector2 dest;
        if (ActiveTelegraph != null && GodotObject.IsInstanceValid(ActiveTelegraph))
        {
            dest = ActiveTelegraph.GlobalPosition;
        }
        else
        {
            dest = player.GlobalPosition
                + new Vector2(attack.Range, 0).Rotated((float)GD.RandRange(0.0, Mathf.Tau));
        }

        GlobalPosition = dest;
        // Arrival slash.
        ApplyDamageInRadius(GlobalPosition, attack.Radius * 0.75f, Mathf.RoundToInt(attack.Damage), heal);
    }

    private void ExecuteBatSwarm(BossAttackPatternData attack)
    {
        int count = Mathf.Max(1, attack.Count);
        for (int i = 0; i < count; i++)
        {
            float angle = Mathf.Tau * i / count + (float)GD.RandRange(-0.2, 0.2);
            Vector2 offset = new Vector2(attack.Radius, 0).Rotated(angle);
            SpawnMinion(
                GlobalPosition + offset,
                "Bat",
                new Color(0.25f, 0.12f, 0.3f, 1f),
                maxHealth: 8,
                moveSpeed: 170f,
                attackDamage: Mathf.Max(2f, attack.Damage * 0.25f),
                attackCooldown: 0.7f);
        }
    }

    protected override void ProcessChase(double delta, Node2D player, bool hasLiveTarget)
    {
        // Frenzy: slightly more aggressive close-range orbit.
        if (CurrentPhaseIndex >= 1 && hasLiveTarget && player != null)
        {
            float speed = Data.MoveSpeed * GetPhaseMoveMultiplier();
            Vector2 toPlayer = player.GlobalPosition - GlobalPosition;
            float dist = toPlayer.Length();
            Vector2 dir = dist > 0.001f ? toPlayer / dist : Vector2.Right;
            // Prefer ~120px hover range.
            if (dist < 100f)
            {
                Velocity = -dir * speed;
            }
            else if (dist > 160f)
            {
                Velocity = dir * speed;
            }
            else
            {
                Velocity = new Vector2(-dir.Y, dir.X) * speed * 0.7f;
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
