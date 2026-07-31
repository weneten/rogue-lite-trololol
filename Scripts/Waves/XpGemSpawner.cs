using Godot;
using Nightbane.Autoloads;
using Nightbane.Core;
using Nightbane.Items;

namespace Nightbane.Waves;

/// <summary>
/// Scene-resident node (one per Arena, not an autoload — needs GetTree().CurrentScene as its
/// pool container) that pools and drops an XpGem wherever an enemy dies. Listens directly to
/// EventBus.OnEnemyKilled rather than routing through GameManager/WaveManager, keeping "who
/// drops pickups" decoupled from "who tracks currency/waves".
/// </summary>
public partial class XpGemSpawner : Node
{
    [Export] public PackedScene GemScene { get; set; }
    [Export] public int PoolPrewarm { get; set; } = 16;

    private ObjectPool<XpGem> _pool;

    public override void _Ready()
    {
        GemScene ??= GD.Load<PackedScene>("res://Scenes/Items/XpGem.tscn");
        _pool = new ObjectPool<XpGem>(GemScene, GetTree().CurrentScene ?? this, PoolPrewarm);

        EventBus.Instance.OnEnemyKilled += OnEnemyKilled;
    }

    private void OnEnemyKilled(Node enemy, int currencyReward, int experienceReward)
    {
        if (experienceReward <= 0 || enemy is not Node2D enemyPosition)
        {
            return;
        }

        XpGem gem = _pool.Get();
        gem.Launch(enemyPosition.GlobalPosition, experienceReward, _pool);
    }
}
