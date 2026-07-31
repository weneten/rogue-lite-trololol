using Godot;

namespace Nightbane.Juice;

/// <summary>
/// Draw-only culling for far enemies: toggles CanvasItem.Visible based on distance from the
/// player. Does NOT stop physics/AI (would desync chase). Lives as its own node so Enemy.cs
/// (Enemy roster stage) stays untouched.
/// </summary>
public partial class OffscreenCuller : Node
{
    /// <summary>Hide when farther than this from the player.</summary>
    [Export] public float CullDistance { get; set; } = 920f;
    /// <summary>Re-show when closer than CullDistance - Hysteresis (avoids edge flicker).</summary>
    [Export] public float Hysteresis { get; set; } = 80f;
    /// <summary>Only re-evaluate every N process frames (cheap at high enemy counts).</summary>
    [Export] public int UpdateEveryNFrames { get; set; } = 4;

    private int _frameCounter;

    public override void _Process(double delta)
    {
        _frameCounter++;
        if (_frameCounter < Mathf.Max(1, UpdateEveryNFrames))
        {
            return;
        }

        _frameCounter = 0;

        Node2D player = GetTree()?.GetFirstNodeInGroup("Player") as Node2D;
        if (player == null)
        {
            return;
        }

        float cullSq = CullDistance * CullDistance;
        float showSq = Mathf.Max(0f, CullDistance - Hysteresis);
        showSq *= showSq;
        Vector2 playerPos = player.GlobalPosition;

        foreach (Node node in GetTree().GetNodesInGroup("Enemy"))
        {
            if (node is not Node2D enemy || !GodotObject.IsInstanceValid(enemy))
            {
                continue;
            }

            // Skip fully inactive pooled instances (already invisible + not processing).
            if (!enemy.IsPhysicsProcessing() && !enemy.Visible)
            {
                continue;
            }

            float distSq = playerPos.DistanceSquaredTo(enemy.GlobalPosition);
            if (enemy.Visible)
            {
                if (distSq > cullSq)
                {
                    enemy.Visible = false;
                }
            }
            else if (distSq < showSq)
            {
                enemy.Visible = true;
            }
        }
    }
}
