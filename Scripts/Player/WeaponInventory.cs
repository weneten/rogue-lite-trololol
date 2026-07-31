using System.Collections.Generic;
using Godot;
using Nightbane.Combat;
using Nightbane.Resources;

namespace Nightbane.PlayerCharacter;

/// <summary>
/// Extends the stage-3 single hardcoded Weapon child into a proper multi-slot loadout: tracks
/// every equipped Weapon node (starting with whatever Weapon.tscn instances are already wired
/// as children in Player.tscn), and lets ShopUI add/remove weapons at runtime as Grave Coin is
/// spent. Lives as a sibling of PlayerStats on the Player node and is exposed via a scene-lifetime
/// Instance singleton, mirroring PlayerStats, so ShopUI can reach it without a direct scene reference.
/// </summary>
public partial class WeaponInventory : Node
{
    public static WeaponInventory Instance { get; private set; }

    [Export] public int MaxWeaponSlots { get; set; } = 6;
    /// <summary>Scene instantiated for weapons purchased at runtime. Falls back to Weapon.tscn if unassigned.</summary>
    [Export] public PackedScene WeaponScene { get; set; }

    private Node2D _ownerBody;
    private readonly List<Weapon> _equippedWeapons = new();

    public IReadOnlyList<Weapon> EquippedWeapons => _equippedWeapons;
    public bool HasFreeSlot => _equippedWeapons.Count < MaxWeaponSlots;

    public override void _Ready()
    {
        Instance = this;
        WeaponScene ??= GD.Load<PackedScene>("res://Scenes/Weapons/Weapon.tscn");
        _ownerBody = GetParent<Node2D>();

        // Register whatever Weapon nodes are already wired as children in the scene (e.g. the
        // starting RustyScythe on Player.tscn) so they count against MaxWeaponSlots from the start.
        foreach (Node child in _ownerBody.GetChildren())
        {
            if (child is Weapon existingWeapon)
            {
                _equippedWeapons.Add(existingWeapon);
            }
        }
    }

    public override void _ExitTree()
    {
        if (Instance == this)
        {
            Instance = null;
        }
    }

    /// <summary>Instantiates a new Weapon.tscn mounted on the owner body. Fails (returns false) if no slot is free.</summary>
    public bool TryAddWeapon(WeaponData data)
    {
        if (data == null || !HasFreeSlot || _ownerBody == null)
        {
            return false;
        }

        Weapon weapon = WeaponScene.Instantiate<Weapon>();
        weapon.Data = data;
        // New weapons are parented directly onto the owner body, same as the Weapon child
        // authored in Player.tscn, so this NodePath ("..") resolves to the owner exactly like theirs.
        weapon.OwnerBodyPath = new NodePath("..");
        _ownerBody.AddChild(weapon);
        _equippedWeapons.Add(weapon);
        return true;
    }

    /// <summary>Removes and frees the first equipped weapon using this exact WeaponData resource.</summary>
    public bool RemoveWeapon(WeaponData data)
    {
        int index = _equippedWeapons.FindIndex(w => w.Data == data);
        return index >= 0 && RemoveWeaponAt(index);
    }

    public bool RemoveWeaponAt(int index)
    {
        if (index < 0 || index >= _equippedWeapons.Count)
        {
            return false;
        }

        Weapon weapon = _equippedWeapons[index];
        _equippedWeapons.RemoveAt(index);
        weapon.QueueFree();
        return true;
    }

    /// <summary>Frees every equipped weapon (including whatever was pre-wired in the scene). Used by
    /// Player.ApplyCharacterData so a freshly selected Hunter starts from their own StartingWeapons
    /// instead of stacking on top of Player.tscn's default RustyScythe.</summary>
    public void ClearAllWeapons()
    {
        for (int i = _equippedWeapons.Count - 1; i >= 0; i--)
        {
            RemoveWeaponAt(i);
        }
    }
}
