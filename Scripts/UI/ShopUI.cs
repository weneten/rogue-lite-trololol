using System;
using System.Collections.Generic;
using Godot;
using Nightbane.Autoloads;
using Nightbane.Combat;
using Nightbane.PlayerCharacter;
using Nightbane.Resources;
using Nightbane.Shop;

namespace Nightbane.UI;

/// <summary>
/// Shop phase screen: opens on EventBus.OnWaveEnd (pausing the run, like LevelUpUI does for
/// level-ups), offers a rolled selection of weapons/passives to buy, lists currently equipped
/// weapons for sale, and lets the player reroll the offers before confirming "Next Wave" to
/// unpause and hand control back to WaveManager. All pricing/reroll-cost math is delegated to
/// the static ShopEconomy so none of it is a magic number here.
/// </summary>
public partial class ShopUI : CanvasLayer
{
    [Export] public ShopPoolData ShopPool { get; set; }
    [Export] public int WeaponOfferCount { get; set; } = 3;
    [Export] public int PassiveOfferCount { get; set; } = 2;

    [ExportGroup("Wiring")]
    [Export] public NodePath RootPanelPath { get; set; }
    [Export] public NodePath CurrencyLabelPath { get; set; }
    [Export] public NodePath RerollButtonPath { get; set; }
    [Export] public NodePath RerollCostLabelPath { get; set; }
    [Export] public NodePath NextWaveButtonPath { get; set; }

    [ExportGroup("Weapon Offers")]
    [Export] public NodePath[] WeaponButtonPaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] WeaponNamePaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] WeaponDescPaths { get; set; } = Array.Empty<NodePath>();

    [ExportGroup("Passive Offers")]
    [Export] public NodePath[] PassiveButtonPaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] PassiveNamePaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] PassiveDescPaths { get; set; } = Array.Empty<NodePath>();

    [ExportGroup("Equipped Weapons (Sell)")]
    [Export] public NodePath[] EquippedRowPaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] EquippedNamePaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] EquippedSellButtonPaths { get; set; } = Array.Empty<NodePath>();

    /// <summary>Selling the last weapon would leave the player unable to fight; block it.</summary>
    [Export] public int MinWeaponsKept { get; set; } = 1;

    private Control _rootPanel;
    private Label _currencyLabel;
    private Button _rerollButton;
    private Label _rerollCostLabel;
    private Button _nextWaveButton;

    private readonly List<Button> _weaponButtons = new();
    private readonly List<Label> _weaponNames = new();
    private readonly List<Label> _weaponDescs = new();
    private readonly List<WeaponData> _weaponOffers = new();

    private readonly List<Button> _passiveButtons = new();
    private readonly List<Label> _passiveNames = new();
    private readonly List<Label> _passiveDescs = new();
    private readonly List<PassiveItemData> _passiveOffers = new();

    private readonly List<Control> _equippedRows = new();
    private readonly List<Label> _equippedNames = new();
    private readonly List<Button> _equippedSellButtons = new();

    private int _rerollsThisVisit;

    public override void _Ready()
    {
        // Lets the shop's own buttons respond while GetTree().Paused is true, exactly like LevelUpUI.
        ProcessMode = ProcessModeEnum.Always;

        ShopPool ??= GD.Load<ShopPoolData>("res://Resources/ShopData/Data/StandardShopPool.tres");

        _rootPanel = GetNodeOrNull<Control>(RootPanelPath);
        _currencyLabel = GetNodeOrNull<Label>(CurrencyLabelPath);
        _rerollButton = GetNodeOrNull<Button>(RerollButtonPath);
        _rerollCostLabel = GetNodeOrNull<Label>(RerollCostLabelPath);
        _nextWaveButton = GetNodeOrNull<Button>(NextWaveButtonPath);

        ResolveOfferRow(WeaponButtonPaths, WeaponNamePaths, WeaponDescPaths, _weaponButtons, _weaponNames, _weaponDescs, BuyWeapon);
        ResolveOfferRow(PassiveButtonPaths, PassiveNamePaths, PassiveDescPaths, _passiveButtons, _passiveNames, _passiveDescs, BuyPassive);

        for (int i = 0; i < EquippedRowPaths.Length; i++)
        {
            _equippedRows.Add(GetNodeOrNull<Control>(EquippedRowPaths[i]));
            _equippedNames.Add(i < EquippedNamePaths.Length ? GetNodeOrNull<Label>(EquippedNamePaths[i]) : null);
            Button sellButton = i < EquippedSellButtonPaths.Length ? GetNodeOrNull<Button>(EquippedSellButtonPaths[i]) : null;
            _equippedSellButtons.Add(sellButton);

            int slotIndex = i; // capture by value for the closure below
            if (sellButton != null)
            {
                sellButton.Pressed += () => SellEquippedWeapon(slotIndex);
            }
        }

        if (_rerollButton != null)
        {
            _rerollButton.Pressed += OnRerollPressed;
        }
        if (_nextWaveButton != null)
        {
            _nextWaveButton.Pressed += OnNextWavePressed;
        }
        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        EventBus.Instance.OnWaveEnd += OnWaveEnd;
        EventBus.Instance.OnCurrencyChanged += OnCurrencyChanged;
    }

    /// <summary>Resolves a row of offer-slot NodePaths (button/name/desc) and wires each button's
    /// Pressed signal to onBuy(slotIndex). Used for both the weapon and passive offer rows.</summary>
    private void ResolveOfferRow(
        NodePath[] buttonPaths, NodePath[] namePaths, NodePath[] descPaths,
        List<Button> buttons, List<Label> names, List<Label> descs,
        Action<int> onBuy)
    {
        for (int i = 0; i < buttonPaths.Length; i++)
        {
            Button button = GetNodeOrNull<Button>(buttonPaths[i]);
            buttons.Add(button);
            names.Add(i < namePaths.Length ? GetNodeOrNull<Label>(namePaths[i]) : null);
            descs.Add(i < descPaths.Length ? GetNodeOrNull<Label>(descPaths[i]) : null);

            int offerIndex = i; // capture by value for the closure below
            if (button != null)
            {
                button.Pressed += () => onBuy(offerIndex);
            }
        }
    }

    private void OnWaveEnd(int waveNumber)
    {
        OpenShop();
    }

    private void OpenShop()
    {
        _rerollsThisVisit = 0;
        RollOffers();
        RefreshEquippedRow();
        RefreshRerollCost();
        UpdateAffordability();

        if (_rootPanel != null)
        {
            _rootPanel.Visible = true;
        }

        GetTree().Paused = true;
    }

    private void OnRerollPressed()
    {
        int cost = ShopEconomy.GetRerollCost(_rerollsThisVisit);
        if (!GameManager.Instance.TrySpendCurrency(cost))
        {
            return;
        }

        AudioManager.Instance?.PlaySfx("ui_click");
        _rerollsThisVisit++;
        RollOffers();
        RefreshRerollCost();
        UpdateAffordability();
    }

    private void OnNextWavePressed()
    {
        AudioManager.Instance?.PlaySfx("ui_click");
        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        GetTree().Paused = false;
        WaveManager.Instance?.StartNextWave();
    }

    /// <summary>Weighted, non-repeating draw of WeaponOfferCount/PassiveOfferCount items, mirroring
    /// LevelUpUI's roll — passives already owned this run are excluded so they never re-appear.</summary>
    private void RollOffers()
    {
        _weaponOffers.Clear();
        var weaponPool = new List<WeaponData>(ShopPool?.WeaponPool ?? Array.Empty<WeaponData>());
        int weaponDrawCount = Mathf.Min(WeaponOfferCount, weaponPool.Count);
        for (int i = 0; i < weaponDrawCount; i++)
        {
            WeaponData picked = weaponPool[(int)GD.RandRange(0, weaponPool.Count - 1)];
            _weaponOffers.Add(picked);
            weaponPool.Remove(picked);
        }

        _passiveOffers.Clear();
        var passivePool = new List<PassiveItemData>();
        foreach (PassiveItemData candidate in ShopPool?.PassivePool ?? Array.Empty<PassiveItemData>())
        {
            if (candidate != null && !GameManager.Instance.IsPassiveItemOwned(candidate.Id))
            {
                passivePool.Add(candidate);
            }
        }

        int passiveDrawCount = Mathf.Min(PassiveOfferCount, passivePool.Count);
        for (int i = 0; i < passiveDrawCount; i++)
        {
            PassiveItemData picked = passivePool[(int)GD.RandRange(0, passivePool.Count - 1)];
            _passiveOffers.Add(picked);
            passivePool.Remove(picked);
        }

        RefreshOfferRow(_weaponButtons, _weaponNames, _weaponDescs, _weaponOffers,
            w => w.Name, w => $"{w.Damage:F0} dmg | {ShopEconomy.GetWeaponPrice(w)}g");
        RefreshOfferRow(_passiveButtons, _passiveNames, _passiveDescs, _passiveOffers,
            p => p.DisplayName, p => $"{p.Description}\n{ShopEconomy.GetPassivePrice(p)}g");
    }

    private static void RefreshOfferRow<T>(
        List<Button> buttons, List<Label> names, List<Label> descs, List<T> offers,
        Func<T, string> nameFn, Func<T, string> descFn) where T : class
    {
        for (int i = 0; i < buttons.Count; i++)
        {
            bool hasOffer = i < offers.Count;
            if (buttons[i] != null)
            {
                buttons[i].Visible = hasOffer;
            }

            if (!hasOffer)
            {
                continue;
            }

            T offer = offers[i];
            if (names[i] != null) names[i].Text = nameFn(offer);
            if (descs[i] != null) descs[i].Text = descFn(offer);
        }
    }

    private void RefreshEquippedRow()
    {
        IReadOnlyList<Weapon> equipped = WeaponInventory.Instance?.EquippedWeapons ?? Array.Empty<Weapon>();

        for (int i = 0; i < _equippedRows.Count; i++)
        {
            bool hasWeapon = i < equipped.Count;
            if (_equippedRows[i] != null)
            {
                _equippedRows[i].Visible = hasWeapon;
            }

            if (!hasWeapon)
            {
                continue;
            }

            WeaponData data = equipped[i].Data;
            if (_equippedNames[i] != null)
            {
                _equippedNames[i].Text = $"{data?.Name} (sell {ShopEconomy.GetWeaponSellValue(data)}g)";
            }

            if (_equippedSellButtons[i] != null)
            {
                _equippedSellButtons[i].Disabled = equipped.Count <= MinWeaponsKept;
            }
        }
    }

    private void RefreshRerollCost()
    {
        if (_rerollCostLabel != null)
        {
            _rerollCostLabel.Text = $"Reroll ({ShopEconomy.GetRerollCost(_rerollsThisVisit)}g)";
        }
    }

    private void BuyWeapon(int offerIndex)
    {
        if (offerIndex >= _weaponOffers.Count || WeaponInventory.Instance == null)
        {
            return;
        }

        WeaponData data = _weaponOffers[offerIndex];
        int price = ShopEconomy.GetWeaponPrice(data);

        if (!WeaponInventory.Instance.HasFreeSlot || !GameManager.Instance.TrySpendCurrency(price))
        {
            return;
        }

        WeaponInventory.Instance.TryAddWeapon(data);
        AudioManager.Instance?.PlaySfx("ui_purchase");
        RefreshEquippedRow();
        UpdateAffordability();
    }

    private void BuyPassive(int offerIndex)
    {
        if (offerIndex >= _passiveOffers.Count)
        {
            return;
        }

        PassiveItemData data = _passiveOffers[offerIndex];
        int price = ShopEconomy.GetPassivePrice(data);

        if (!GameManager.Instance.TrySpendCurrency(price))
        {
            return;
        }

        AudioManager.Instance?.PlaySfx("ui_purchase");
        ApplyPassiveEffect(data);
        GameManager.Instance.RegisterPassiveItemOwned(data.Id);

        // Removing the bought offer shifts the remaining ones down; re-running RefreshOfferRow
        // reflows every slot's label/visibility off the shortened list (last slot ends up hidden).
        _passiveOffers.RemoveAt(offerIndex);
        RefreshOfferRow(_passiveButtons, _passiveNames, _passiveDescs, _passiveOffers,
            p => p.DisplayName, p => $"{p.Description}\n{ShopEconomy.GetPassivePrice(p)}g");
        UpdateAffordability();
    }

    private void SellEquippedWeapon(int slotIndex)
    {
        IReadOnlyList<Weapon> equipped = WeaponInventory.Instance?.EquippedWeapons;
        if (equipped == null || slotIndex >= equipped.Count || equipped.Count <= MinWeaponsKept)
        {
            return;
        }

        WeaponData data = equipped[slotIndex].Data;
        int sellValue = ShopEconomy.GetWeaponSellValue(data);

        if (WeaponInventory.Instance.RemoveWeaponAt(slotIndex))
        {
            AudioManager.Instance?.PlaySfx("ui_click");
            GameManager.Instance.AddCurrency(sellValue);
            RefreshEquippedRow();
            UpdateAffordability();
        }
    }

    private static void ApplyPassiveEffect(PassiveItemData item)
    {
        PlayerStats stats = PlayerStats.Instance;
        if (stats == null)
        {
            return;
        }

        switch (item.EffectType)
        {
            case PassiveEffectType.DamageBoost:
                stats.ApplyDamageUpgrade(item.Value);
                break;
            case PassiveEffectType.MoveSpeedBoost:
                stats.ApplyMoveSpeedUpgrade(item.Value);
                break;
            case PassiveEffectType.MaxHealthBoost:
                stats.ApplyMaxHealthUpgrade(Mathf.RoundToInt(item.Value));
                break;
        }
    }

    private void OnCurrencyChanged(int currentCurrency)
    {
        if (_currencyLabel != null)
        {
            _currencyLabel.Text = $"{currentCurrency}g";
        }

        UpdateAffordability();
    }

    /// <summary>Greys out any buy/reroll button the player can no longer afford (or, for weapons, if slots are full).</summary>
    private void UpdateAffordability()
    {
        if (GameManager.Instance == null)
        {
            return;
        }

        int currency = GameManager.Instance.Currency;
        bool weaponSlotsFull = WeaponInventory.Instance != null && !WeaponInventory.Instance.HasFreeSlot;

        for (int i = 0; i < _weaponButtons.Count; i++)
        {
            if (_weaponButtons[i] == null || i >= _weaponOffers.Count)
            {
                continue;
            }

            _weaponButtons[i].Disabled = weaponSlotsFull || currency < ShopEconomy.GetWeaponPrice(_weaponOffers[i]);
        }

        for (int i = 0; i < _passiveButtons.Count; i++)
        {
            if (_passiveButtons[i] == null || i >= _passiveOffers.Count)
            {
                continue;
            }

            _passiveButtons[i].Disabled = currency < ShopEconomy.GetPassivePrice(_passiveOffers[i]);
        }

        if (_rerollButton != null)
        {
            _rerollButton.Disabled = currency < ShopEconomy.GetRerollCost(_rerollsThisVisit);
        }
    }
}
