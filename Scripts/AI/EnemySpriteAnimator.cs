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
    public bool HasFrames => _sprite != null && _sprite.SpriteFrames != null &&
                             _sprite.SpriteFrames.GetAnimationNames().Length > 0;
    public AnimatedSprite2D Sprite => _sprite;

    public override void _Ready()
    {
        ResolveSprite();
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

    /// <summary>
    /// Swap sheet / attack anim / scale / tint for a pooled enemy re-arm.
    /// Returns true when frames were applied successfully.
    /// </summary>
    public bool Configure(string sheetPath, string jsonPath, string attackAnimName, float scale, Color modulate,
        Texture2D preloadedTexture = null)
    {
        ResolveSprite();

        _dead = false;
        _oneShotPlaying = false;
        _baseScale = scale <= 0f ? 1f : scale;
        _attackAnim = string.IsNullOrEmpty(attackAnimName) ? "attack_slash" : attackAnimName;
        _sheetPath = sheetPath;

        if (_sprite == null)
        {
            GD.PushError("[EnemySpriteAnimator] No AnimatedSprite2D found (Sprite child missing).");
            return false;
        }

        _sprite.TextureFilter = CanvasItem.TextureFilterEnum.Nearest;
        _sprite.Centered = true;
        _sprite.ZIndex = 2;

        bool loaded = false;
        if (!string.IsNullOrEmpty(sheetPath) || preloadedTexture != null)
        {
            SpriteFrames frames = SpriteSheetCache.GetFrames(sheetPath, jsonPath, preloadedTexture);
            if (frames != null)
            {
                _sprite.SpriteFrames = frames;
                _sprite.Offset = SpriteSheetCache.GetSpriteOffset(sheetPath);
                loaded = true;
            }
        }

        // Avoid harsh full-tint washes that can hide pixel art; keep mild color keys.
        Color tint = modulate.A <= 0.001f ? Colors.White : modulate;
        // Soften extreme multiplies so sprites stay readable under CanvasModulate.
        tint = new Color(
            Mathf.Clamp(tint.R, 0.55f, 1.35f),
            Mathf.Clamp(tint.G, 0.55f, 1.35f),
            Mathf.Clamp(tint.B, 0.55f, 1.35f),
            Mathf.Clamp(tint.A, 0.7f, 1f));
        _sprite.Modulate = tint;
        _sprite.Scale = Vector2.One * _baseScale;
        _sprite.FlipH = false;
        _sprite.Visible = loaded;

        if (loaded)
        {
            _attackAnim = ResolveAttackAnim(_attackAnim);
            PlayLocomotion("idle", force: true);
        }

        return loaded;
    }

    public void ResetVisual()
    {
        _dead = false;
        _oneShotPlaying = false;
        if (_sprite != null)
        {
            _sprite.Visible = HasFrames;
            _sprite.Modulate = Colors.White;
            _sprite.Scale = Vector2.One * _baseScale;
            _sprite.FlipH = false;
        }

        if (HasFrames)
        {
            PlayLocomotion("idle", force: true);
        }
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

    private void ResolveSprite()
    {
        if (_sprite != null && GodotObject.IsInstanceValid(_sprite))
        {
            return;
        }

        if (SpritePath != null && !SpritePath.IsEmpty)
        {
            _sprite = GetNodeOrNull<AnimatedSprite2D>(SpritePath);
        }

        // Sibling under Enemy root — most reliable.
        if (_sprite == null && GetParent() != null)
        {
            _sprite = GetParent().GetNodeOrNull<AnimatedSprite2D>("Sprite");
        }

        if (_sprite == null)
        {
            _sprite = GetParent()?.FindChild("Sprite", recursive: true, owned: false) as AnimatedSprite2D;
        }
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

        if (!_sprite.SpriteFrames.HasAnimation(name))
        {
            return;
        }

        _currentLocomotion = name;
        if (!_oneShotPlaying && !_dead)
        {
            _sprite.Play(name);
        }
    }

    private void PlayOneShot(string name)
    {
        if (_sprite?.SpriteFrames == null)
        {
            return;
        }

        if (!_sprite.SpriteFrames.HasAnimation(name) || _sprite.SpriteFrames.GetFrameCount(name) == 0)
        {
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
