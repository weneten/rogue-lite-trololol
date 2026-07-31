using Godot;

namespace Nightbane.AI;

/// <summary>
/// Drives an AnimatedSprite2D from Nightbane sprite sheets. Owns facing, locomotion
/// (idle/run), one-shot hurt/attack/death, and scale/modulate from EnemyData.
/// </summary>
public partial class EnemySpriteAnimator : Node
{
    [Export] public NodePath SpritePath { get; set; }

    private AnimatedSprite2D _sprite;
    private string _sheetPath;
    private string _attackAnim = "attack_slash";
    private string _currentLocomotion = "idle";
    private bool _oneShotPlaying;
    private bool _dead;
    private float _baseScale = 1f;

    public bool IsDeathPlaying => _dead && _oneShotPlaying;
    public AnimatedSprite2D Sprite => _sprite;

    public override void _Ready()
    {
        _sprite = GetNodeOrNull<AnimatedSprite2D>(SpritePath);
        if (_sprite == null && GetParent() != null)
        {
            _sprite = GetParent().GetNodeOrNull<AnimatedSprite2D>("Sprite");
        }

        if (_sprite != null)
        {
            _sprite.TextureFilter = CanvasItem.TextureFilterEnum.Nearest;
            _sprite.Centered = true;
            _sprite.AnimationFinished += OnAnimationFinished;
        }
    }

    public override void _ExitTree()
    {
        if (_sprite != null)
        {
            _sprite.AnimationFinished -= OnAnimationFinished;
        }
    }

    /// <summary>Swap sheet / attack anim / scale / tint for a pooled enemy re-arm.</summary>
    public void Configure(string sheetPath, string attackAnimName, float scale, Color modulate)
    {
        _dead = false;
        _oneShotPlaying = false;
        _baseScale = scale <= 0f ? 1f : scale;
        _attackAnim = string.IsNullOrEmpty(attackAnimName) ? "attack_slash" : attackAnimName;
        _sheetPath = sheetPath;

        if (_sprite == null)
        {
            return;
        }

        if (!string.IsNullOrEmpty(sheetPath))
        {
            SpriteFrames frames = SpriteSheetCache.GetFrames(sheetPath);
            if (frames != null)
            {
                _sprite.SpriteFrames = frames;
                _sprite.Offset = SpriteSheetCache.GetSpriteOffset(sheetPath);
            }
        }

        _sprite.Modulate = modulate.A <= 0.001f ? Colors.White : modulate;
        _sprite.Scale = Vector2.One * _baseScale;
        _sprite.FlipH = false;
        _sprite.Visible = true;

        // Resolve attack alias if this sheet uses a different name (hunter/witch/guardian).
        _attackAnim = ResolveAttackAnim(_attackAnim);

        PlayLocomotion("idle", force: true);
    }

    public void ResetVisual()
    {
        _dead = false;
        _oneShotPlaying = false;
        if (_sprite != null)
        {
            _sprite.Visible = true;
            _sprite.Modulate = Colors.White;
            _sprite.Scale = Vector2.One * _baseScale;
            _sprite.FlipH = false;
        }

        PlayLocomotion("idle", force: true);
    }

    /// <summary>Face movement / target. Positive dirX → face right (sheet default).</summary>
    public void SetFacing(float dirX)
    {
        if (_sprite == null || Mathf.Abs(dirX) < 0.05f)
        {
            return;
        }

        // Sheets face right; FlipH when moving/aiming left.
        _sprite.FlipH = dirX < 0f;
    }

    public void UpdateLocomotion(bool moving)
    {
        if (_dead || _oneShotPlaying)
        {
            return;
        }

        PlayLocomotion(moving ? "run" : "idle");
    }

    public void PlayHurt()
    {
        if (_dead || _sprite == null)
        {
            return;
        }

        PlayOneShot("hurt");
    }

    public void PlayAttack()
    {
        if (_dead || _sprite == null)
        {
            return;
        }

        PlayOneShot(_attackAnim);
    }

    /// <summary>Plays death and returns when finished (or immediately if no sprite/anim).</summary>
    public async System.Threading.Tasks.Task PlayDeathAsync()
    {
        _dead = true;
        if (_sprite == null || _sprite.SpriteFrames == null || !_sprite.SpriteFrames.HasAnimation("death"))
        {
            return;
        }

        _oneShotPlaying = true;
        _sprite.Play("death");

        // Wait for AnimationFinished or a hard timeout so pool never soft-locks.
        float timeout = 1.2f;
        if (_sprite.SpriteFrames.HasAnimation("death"))
        {
            int count = _sprite.SpriteFrames.GetFrameCount("death");
            float speed = (float)_sprite.SpriteFrames.GetAnimationSpeed("death");
            if (speed > 0.01f)
            {
                timeout = Mathf.Max(0.35f, count / speed + 0.15f);
            }
        }

        SceneTreeTimer timer = GetTree().CreateTimer(timeout);
        await ToSignal(timer, SceneTreeTimer.SignalName.Timeout);
        _oneShotPlaying = false;
    }

    private void PlayLocomotion(string name, bool force = false)
    {
        if (_sprite == null || _sprite.SpriteFrames == null)
        {
            return;
        }

        if (!force && _currentLocomotion == name && _sprite.IsPlaying())
        {
            return;
        }

        if (!_sprite.SpriteFrames.HasAnimation(name))
        {
            name = "idle";
        }

        _currentLocomotion = name;
        if (!_oneShotPlaying && !_dead)
        {
            _sprite.Play(name);
        }
    }

    private void PlayOneShot(string name)
    {
        if (_sprite.SpriteFrames == null)
        {
            return;
        }

        if (!_sprite.SpriteFrames.HasAnimation(name) || _sprite.SpriteFrames.GetFrameCount(name) == 0)
        {
            // Try common aliases.
            name = ResolveAttackAnim(name);
            if (!_sprite.SpriteFrames.HasAnimation(name))
            {
                return;
            }
        }

        _oneShotPlaying = true;
        _sprite.Play(name);
    }

    private void OnAnimationFinished()
    {
        if (_dead)
        {
            _oneShotPlaying = false;
            return;
        }

        if (_oneShotPlaying)
        {
            _oneShotPlaying = false;
            // Resume locomotion after hurt/attack.
            if (_sprite != null && _sprite.SpriteFrames != null &&
                _sprite.SpriteFrames.HasAnimation(_currentLocomotion))
            {
                _sprite.Play(_currentLocomotion);
            }
        }
    }

    private string ResolveAttackAnim(string preferred)
    {
        if (_sprite?.SpriteFrames == null)
        {
            return preferred;
        }

        if (_sprite.SpriteFrames.HasAnimation(preferred) &&
            _sprite.SpriteFrames.GetFrameCount(preferred) > 0)
        {
            return preferred;
        }

        // Sheet-specific attack names across hunter / wolf / witch / guardian kits.
        string[] fallbacks =
        {
            preferred,
            "attack_slash",
            "attack_whip",
            "attack_orbs",
            "shield_bash",
            "chain_swing",
            "attack_spin",
            "attack_nova",
            "attack_cross",
            "hurt"
        };

        foreach (string name in fallbacks)
        {
            if (!string.IsNullOrEmpty(name) &&
                _sprite.SpriteFrames.HasAnimation(name) &&
                _sprite.SpriteFrames.GetFrameCount(name) > 0)
            {
                return name;
            }
        }

        return "idle";
    }
}
