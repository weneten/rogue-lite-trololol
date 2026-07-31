using Godot;
using Nightbane.AI;
using Nightbane.Autoloads;
using Nightbane.Combat;
using Nightbane.PlayerCharacter.Passives;
using Nightbane.Resources;

namespace Nightbane.PlayerCharacter;

/// <summary>
/// 8-directional top-down player controller. Movement is pure input->velocity (no
/// acceleration/friction yet — stage stub, tune once real art/animation exists).
/// Bridges its HealthComponent to the global EventBus so UI/GameManager/AudioManager
/// (which only know about EventBus, not this node) react to player damage/death.
/// </summary>
public partial class Player : CharacterBody2D
{
    [Export] public float MoveSpeed { get; set; } = 300f;

    [ExportGroup("Character")]
    /// <summary>Wired in the editor for quick standalone testing of Arena.tscn; in the normal flow
    /// this is left null and GameManager.Instance.SelectedCharacter (set by CharacterSelect) is used
    /// instead. If neither is set, Player keeps whatever defaults are already authored on the scene.</summary>
    [Export] public CharacterData CharacterData { get; set; }

    [ExportGroup("Wiring")]
    [Export] public NodePath HealthComponentPath { get; set; }
    [Export] public NodePath CameraPath { get; set; }
    [Export] public NodePath PlayerStatsPath { get; set; }
    [Export] public NodePath SpriteNodePath { get; set; }
    [Export] public NodePath SpriteAnimatorPath { get; set; }
    /// <summary>Placeholder diamond shown for Hunters whose CharacterData has no sprite sheet
    /// (or when the sheet fails to load) so the player is never invisible.</summary>
    [Export] public NodePath FallbackPolygonPath { get; set; }

    [ExportGroup("Debug")]
    // Stage-2 verification hook: press the "debug_damage_test" action (T) to self-damage
    // and confirm HealthComponent -> EventBus.OnPlayerDamaged/OnPlayerDied wiring works
    // end-to-end without needing enemies yet. TODO: disable/remove once real combat lands.
    [Export] public bool EnableDebugDamageKey { get; set; } = true;
    [Export] public int DebugDamageAmount { get; set; } = 10;

    private HealthComponent _health;
    private Camera2D _camera;
    private PlayerStats _stats;
    private AnimatedSprite2D _animatedSprite;
    private EnemySpriteAnimator _spriteAnimator;
    private Node2D _fallbackPolygon;

    public override void _Ready()
    {
        // Lets Enemy.cs (and anything else) find the player via GetFirstNodeInGroup instead of
        // holding a direct scene reference, mirroring how Weapon/Projectile target the "Enemy" group.
        AddToGroup("Player");

        _health = GetNodeOrNull<HealthComponent>(HealthComponentPath);
        _camera = GetNodeOrNull<Camera2D>(CameraPath);
        _stats = GetNodeOrNull<PlayerStats>(PlayerStatsPath);
        _animatedSprite = GetNodeOrNull<AnimatedSprite2D>(SpriteNodePath);
        _spriteAnimator = GetNodeOrNull<EnemySpriteAnimator>(SpriteAnimatorPath);
        _fallbackPolygon = GetNodeOrNull<Node2D>(FallbackPolygonPath);

        if (_health != null)
        {
            _health.Damaged += OnHealthDamaged;
            _health.Died += OnHealthDied;
            _health.HealthChanged += OnHealthChanged;
        }
        else
        {
            GD.PushWarning("[Player] HealthComponentPath not wired; player is invulnerable.");
        }

        if (_camera != null)
        {
            _camera.MakeCurrent();
        }

        ApplyCharacterData();
    }

    /// <summary>
    /// Configures stats/loadout/passive from the Hunter chosen at CharacterSelect (falls back to
    /// GameManager.Instance.SelectedCharacter, then to whatever CharacterData is wired in the
    /// editor). If neither is set, the Player keeps whatever defaults are already authored on the
    /// scene (MoveSpeed/HealthComponent.MaxHealth/starting Weapon child) — lets Arena.tscn still be
    /// run standalone for quick testing without going through CharacterSelect first.
    /// </summary>
    private void ApplyCharacterData()
    {
        CharacterData data = CharacterData ?? GameManager.Instance?.SelectedCharacter;
        if (data == null)
        {
            return;
        }

        MoveSpeed = data.MoveSpeed;
        ApplyCharacterVisual(data);

        if (_health != null)
        {
            _health.MaxHealth = data.MaxHealth;
            _health.Armor = data.StartingArmor;
            _health.DodgeChance = data.StartingDodgeChance;
            _health.Revive(data.MaxHealth);
        }

        if (_stats != null)
        {
            _stats.ApplyExtraCrit(data.StartingCritChance, 0f);
            _stats.SetMagicDamageMultiplier(data.StartingMagicPower);
        }

        if (WeaponInventory.Instance != null)
        {
            // Replaces whatever Weapon.tscn child was hardcoded on Player.tscn (e.g. the default
            // RustyScythe) with this Hunter's own loadout instead of stacking on top of it.
            WeaponInventory.Instance.ClearAllWeapons();
            foreach (WeaponData weaponData in data.StartingWeapons)
            {
                WeaponInventory.Instance.TryAddWeapon(weaponData);
            }
        }

        if (!string.IsNullOrEmpty(data.PassiveId))
        {
            PassiveAbility passive = PassiveAbilityFactory.Create(data.PassiveId);
            if (passive != null)
            {
                AddChild(passive);
                passive.Setup(this, _stats, _health, data);
                if (_stats != null)
                {
                    _stats.ActivePassive = passive;
                }
            }
            else
            {
                GD.PushWarning($"[Player] Unknown PassiveId '{data.PassiveId}' on CharacterData '{data.CharacterName}'.");
            }
        }
    }

    /// <summary>
    /// Swaps in this Hunter's sprite sheet (same Assets/sprites JSON+PNG pipeline the enemies use,
    /// hence the shared EnemySpriteAnimator). Hunters without a sheet — or a sheet that fails to
    /// load — keep the placeholder polygon instead of turning invisible.
    /// </summary>
    private void ApplyCharacterVisual(CharacterData data)
    {
        string sheetPath = data.SpriteSheetPath;
        if (string.IsNullOrEmpty(sheetPath) && data.SpriteSheet != null)
        {
            sheetPath = data.SpriteSheet.ResourcePath;
        }

        bool wantsSheet = data.SpriteSheet != null || !string.IsNullOrEmpty(sheetPath);
        bool sheetOk = false;

        if (wantsSheet && _spriteAnimator != null)
        {
            sheetOk = _spriteAnimator.Configure(
                sheetPath,
                data.SpriteJsonPath,
                data.AttackAnimName,
                data.SpriteScale <= 0f ? 1f : data.SpriteScale,
                Colors.White,
                data.SpriteSheet);
        }

        if (_animatedSprite != null)
        {
            _animatedSprite.Visible = sheetOk;
        }

        if (_fallbackPolygon != null)
        {
            _fallbackPolygon.Visible = !sheetOk;
        }

        if (wantsSheet && !sheetOk)
        {
            GD.PushWarning($"[Player] Sheet failed for '{data.CharacterName}' path='{sheetPath}' — using fallback polygon.");
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_health != null && _health.IsDead)
        {
            Velocity = Vector2.Zero;
            MoveAndSlide();
            return;
        }

        float effectiveSpeed = MoveSpeed * (_stats?.MoveSpeedMultiplier ?? 1f);
        Vector2 inputDirection = Input.GetVector("move_left", "move_right", "move_up", "move_down");
        Velocity = inputDirection * effectiveSpeed;
        MoveAndSlide();

        if (_spriteAnimator != null)
        {
            _spriteAnimator.SetFacing(inputDirection.X);
            _spriteAnimator.UpdateLocomotion(inputDirection.LengthSquared() > 0.01f);
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (EnableDebugDamageKey && @event.IsActionPressed("debug_damage_test"))
        {
            _health?.TakeDamage(DebugDamageAmount, this);
        }
    }

    private void OnHealthDamaged(int amount, Node source)
    {
        _spriteAnimator?.PlayHurt();
        EventBus.Instance?.EmitSignal(
            EventBus.SignalName.OnPlayerDamaged,
            (float)amount,
            (float)_health.CurrentHealth);
    }

    private void OnHealthChanged(int currentHealth, int maxHealth)
    {
        // Forwards every HP change (damage, heal, or a max-HP level-up upgrade) to EventBus so
        // HUD can stay in sync without holding a direct reference to the player/HealthComponent.
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnPlayerHealthChanged, currentHealth, maxHealth);
    }

    private void OnHealthDied(Node source)
    {
        // Fire-and-forget: the death anim just needs to run out, nothing waits on it (physics is
        // already frozen above, and the game-over UI is driven by EventBus).
        _ = _spriteAnimator?.PlayDeathAsync();
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnPlayerDied);
    }
}
