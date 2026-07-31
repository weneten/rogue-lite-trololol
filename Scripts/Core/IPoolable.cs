namespace Nightbane.Core;

/// <summary>
/// Implemented by pooled nodes so ObjectPool&lt;T&gt; can reset/arm them on reuse instead of
/// (de)instantiating a fresh scene each time — the whole point of pooling.
/// </summary>
public interface IPoolable
{
    /// <summary>Called by ObjectPool when this instance is handed out via Get(). Re-enable processing/visibility/collision here.</summary>
    void OnSpawn();

    /// <summary>Called by ObjectPool when this instance is Return()-ed. Disable processing/visibility/collision here.</summary>
    void OnDespawn();
}
