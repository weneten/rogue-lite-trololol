using Godot;
using Nightbane.Combat;
using Nightbane.Resources;

namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Grave Warden — raises spectral familiars from the earth: at run start, spawns
/// Mathf.RoundToInt(PassiveValueA) ghost-blade familiars orbiting the Player, evenly spaced in a
/// ring. Each familiar is just another Weapon.tscn instance (auto-targets/attacks nearest enemy
/// exactly like the player's own weapons) driven by FamiliarBolt.tres, mounted directly on the
/// Player body so it doesn't consume a WeaponInventory slot and isn't sellable in the shop.
/// </summary>
public partial class SummonFamiliarsPassive : PassiveAbility
{
    private const string WeaponScenePath = "res://Scenes/Weapons/Weapon.tscn";
    private const string FamiliarDataPath = "res://Resources/WeaponData/Data/FamiliarBolt.tres";
    private const float RingRadius = 40f;

    protected override void OnInitialize()
    {
        var weaponScene = GD.Load<PackedScene>(WeaponScenePath);
        var familiarData = GD.Load<WeaponData>(FamiliarDataPath);
        if (weaponScene == null || familiarData == null || Owner == null)
        {
            GD.PushWarning("[SummonFamiliarsPassive] Missing Weapon.tscn or FamiliarBolt.tres; no familiars spawned.");
            return;
        }

        int count = Mathf.Max(1, Mathf.RoundToInt(Data.PassiveValueA));
        for (int i = 0; i < count; i++)
        {
            float angle = Mathf.Tau * i / count;
            var familiar = weaponScene.Instantiate<Weapon>();
            familiar.Data = familiarData;
            familiar.OwnerBodyPath = new NodePath("..");
            familiar.Position = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * RingRadius;
            Owner.AddChild(familiar);
        }
    }
}
