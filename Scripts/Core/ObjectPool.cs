using System.Collections.Generic;
using Godot;

namespace Nightbane.Core;

/// <summary>
/// Generic reuse pool for pooled Node scenes (projectiles, hit-VFX, damage numbers, ...).
/// Instances are instantiated once, kept parented under a container node for their whole
/// life, and toggled via IPoolable.OnSpawn/OnDespawn instead of being freed/re-instantiated
/// — avoids the GC churn and Instantiate() cost of spawning a fresh scene every shot.
/// </summary>
public class ObjectPool<T> where T : Node
{
    private readonly PackedScene _scene;
    private readonly Node _container;
    private readonly Stack<T> _available = new();

    public int CountAlive { get; private set; }

    /// <param name="scene">Scene whose root must be (or inherit) T and implement IPoolable.</param>
    /// <param name="container">Node all pooled instances are parented under for their lifetime.</param>
    /// <param name="prewarmCount">Instances created up front to avoid a first-use hitch.</param>
    public ObjectPool(PackedScene scene, Node container, int prewarmCount = 0)
    {
        _scene = scene;
        _container = container;

        for (int i = 0; i < prewarmCount; i++)
        {
            _available.Push(CreateInstance());
        }
    }

    private T CreateInstance()
    {
        var instance = _scene.Instantiate<T>();
        _container.AddChild(instance);

        if (instance is IPoolable poolable)
        {
            poolable.OnDespawn();
        }

        return instance;
    }

    /// <summary>Pulls a ready instance (or creates one if the pool is empty) and arms it via OnSpawn().</summary>
    public T Get()
    {
        T instance = _available.Count > 0 ? _available.Pop() : CreateInstance();

        if (instance is IPoolable poolable)
        {
            poolable.OnSpawn();
        }

        CountAlive++;
        return instance;
    }

    /// <summary>Disarms an instance via OnDespawn() and returns it to the pool for reuse.</summary>
    public void Return(T instance)
    {
        if (instance is IPoolable poolable)
        {
            poolable.OnDespawn();
        }

        _available.Push(instance);
        CountAlive = Mathf.Max(0, CountAlive - 1);
    }
}
