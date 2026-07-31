export const meta = {
  name: 'nightbane-build',
  description: 'Build Nightbane gothic roguelite (Godot 4 C#) stage by stage per Brotato-style build plan',
  phases: [
    { title: 'Scaffold' },
    { title: 'Player+Arena+Health' },
    { title: 'Weapon system' },
    { title: 'Enemy+Wave system' },
    { title: 'XP/Level-up UI' },
    { title: 'Shop phase' },
    { title: 'Character roster' },
    { title: 'Weapon roster' },
    { title: 'Enemy roster' },
    { title: 'Bosses' },
    { title: 'Audio' },
    { title: 'Meta-progression UI' },
    { title: 'Balancing+Juice' },
  ],
}

const ROOT = 'C:\\Users\\SW-00-fiae19\\OneDrive - bbw Gruppe\\VS Code\\rogue-lite-trololol'

const PREFIX = `You are building "Nightbane", a Godot 4 (C#/.NET) top-down arena survival roguelite in Brotato style, reskinned dark gothic horror (Victorian hunters, vampires, undead, blood moons, cathedrals/graveyards). Repo root: ${ROOT}. This is a multi-stage build — before writing anything, inspect the current repo state (project.godot, Scenes/, Scripts/, Resources/, Autoloads/, Assets/ folders) to see what earlier stages already built, and extend it consistently rather than redoing it. Use data-driven Resource (.tres) design, EventBus autoload signal pattern, object pooling where relevant, strong typing, [Export] fields instead of magic numbers. Comment only non-obvious logic (state machines, scaling formulas). Do not write docs/markdown files. After finishing, verify the project still opens/compiles conceptually (check C# syntax, correct scene/script references) and return a short report: what you built, file paths, and any assumption you made due to ambiguous requirements.`

function stage(title, task) {
  return agent(`${PREFIX}\n\nSTAGE: ${title}\n\nTASK:\n${task}`, { phase: title, label: title })
}

phase('Scaffold')
log('Stage 1: project scaffold + autoloads + EventBus')
const s1 = await stage('Scaffold', `Create the Godot 4 C# project from scratch:
- project.godot configured for a 2D top-down game, .NET/C# (GodotSharp) enabled, autoloads registered.
- Folder structure: /Scenes (Player, Enemies, Bosses, Weapons, UI, Arena, MainMenu), /Scripts (Player, Combat, Waves, Shop, AI, Audio), /Resources (CharacterData, WeaponData, EnemyData, BossData C# Resource classes), /Assets (art, audio, fonts placeholders), /Autoloads (GameManager, WaveManager, AudioManager, EventBus).
- Implement EventBus.cs as an autoload C# singleton exposing C# events/signals: OnEnemyKilled, OnWaveStart, OnWaveEnd, OnPlayerLevelUp, OnItemPickedUp, OnPlayerDamaged, OnPlayerDied.
- Implement GameManager.cs (run state: currency, wave number, run seed) and stub WaveManager.cs / AudioManager.cs autoloads that reference EventBus.
- Create a minimal Nightbane.csproj/.sln consistent with Godot 4 C# project conventions.
- Create a placeholder MainMenu.tscn/.cs and empty Arena.tscn so the project has an entry scene.`)

phase('Player+Arena+Health')
log('Stage 2: player movement, camera, arena, health/damage')
const s2 = await stage('Player+Arena+Health', `Building on the scaffold from stage 1 (read existing Autoloads/EventBus first):
- Player.tscn + Player.cs: top-down 8-directional movement (CharacterBody2D), camera2D following player, basic sprite placeholder (ColorRect or Polygon2D is fine as placeholder art).
- HealthComponent.cs (reusable, attachable to Player/Enemy): max HP, current HP, TakeDamage(amount, source), Die(), fires EventBus signals on damage/death.
- Arena.tscn: bounded top-down arena with walls/collision bounds, simple gothic-graveyard placeholder tilemap or ColorRect ground, fog/vignette placeholder (a CanvasModulate or ColorRect overlay is fine, mark TODO for real shader).
- Wire Player health via HealthComponent, test that damage reduces HP and death fires EventBus.OnPlayerDied.`)

phase('Weapon system')
log('Stage 3: WeaponData resource + first working weapon')
const s3 = await stage('Weapon system', `Building on stages 1-2 (read existing Player/Arena/EventBus first):
- WeaponData.cs: a C# Resource with [Export] fields — Name, Damage, AttackSpeed, Range, CritChance, CritMultiplier, ProjectileCount, Spread, Knockback, RarityTier (enum), WeaponClass (Flags enum: Melee, Ranged, Firearm, Magic, Holy, Cursed, AoE, Summon).
- Weapon.cs base scene/script attachable to Player: auto-targets nearest enemy/dummy in range, fires per AttackSpeed using WeaponData stats, spawns a Projectile.tscn (pooled) for ranged weapons or does a hitbox check for melee.
- Create one concrete WeaponData .tres — "Rusty Scythe" (Melee) — and wire it onto Player so it auto-attacks.
- Create a TargetDummy.tscn (uses HealthComponent from stage 2) in Arena to verify the weapon fires and deals damage; confirm damage numbers/log show hits landing.
- Implement basic object pooling (ObjectPool.cs generic helper) used by the projectile spawner.`)

phase('Enemy+Wave system')
log('Stage 4: enemy base + 2 enemy types + spawner/wave system')
const s4 = await stage('Enemy+Wave system', `Building on stages 1-3 (read existing Weapon/HealthComponent/EventBus first):
- EnemyData.cs Resource: HP, MoveSpeed, Damage, AttackPattern enum, BehaviorType (Chase/Wander/Attack/Flee state machine tag).
- Enemy.tscn generic scene driven entirely by EnemyData (not one scene per enemy type) with a simple state-machine script (Chase/Attack states minimum), uses HealthComponent, fires EventBus.OnEnemyKilled with XP/loot info on death.
- Create 2 EnemyData .tres: "Ghoul" (fast melee chaser, low HP) and "Skeletal Archer" (ranged, keeps distance, shoots arrows via a simple projectile).
- WaveManager.cs (flesh out the stage-1 stub): timed waves (20-90s), spawns enemies from a wave definition (enemy pool + count scaling), fires EventBus.OnWaveStart/OnWaveEnd, uses object pooling for enemies.
- Verify: player fights spawned Ghouls/Archers with the Rusty Scythe weapon from stage 3 and they die correctly.`)

phase('XP/Level-up UI')
log('Stage 5: XP/leveling + level-up choice UI')
const s5 = await stage('XP/Level-up UI', `Building on stages 1-4 (read existing WaveManager/EventBus/EnemyData first):
- XP/Soul gem pickup: small pickup scene dropped on EventBus.OnEnemyKilled, player collects via Area2D overlap, grants XP.
- PlayerStats.cs / leveling logic: XP curve (isolated static method, easily tunable), level up fires EventBus.OnPlayerLevelUp, pauses wave time briefly.
- LevelUpUI.tscn/.cs: presents 3 random upgrade choices (stat boosts like +damage/+speed/+maxHP, or a passive relic placeholder) pulled from a simple upgrade pool data structure; selecting one applies the effect and resumes gameplay.
- Basic in-run HUD.tscn: HP bar, XP bar, wave timer, wave number, currency display (wire to GameManager/EventBus signals).`)

phase('Shop phase')
log('Stage 6: shop phase + currency + economy')
const s6 = await stage('Shop phase', `Building on stages 1-5 (read existing GameManager/WaveManager/WeaponData first):
- Currency: implement "Grave Coin" tracked in GameManager, earned from EventBus.OnEnemyKilled and end-of-wave bonus.
- ShopUI.tscn/.cs: appears between waves (WaveManager fires an OnWaveEnd -> shop phase transition), offers buy/sell/reroll of WeaponData items and simple passive items, using isolated static pricing/reroll-cost formulas (easily tunable, no magic numbers inline).
- Wire the shop to add purchased weapons onto the player (extend the stage-3 weapon-slot system to support multiple equipped weapons) and deduct/grant Grave Coin correctly.
- Verify a full loop: wave -> kill enemies -> collect coin -> shop -> buy weapon -> next wave.`)

phase('Character roster')
log('Stage 7: full character roster (10+ Hunters)')
const s7 = await stage('Character roster', `Building on stages 1-6 (read existing Player.cs, WeaponData, EventBus first):
- CharacterData.cs Resource: Name, lore blurb, base stats (HP, speed, armor, dodge, crit, magic), starting weapon(s) (WeaponData refs), a unique passive ability id/params, difficulty rating.
- Implement a passive-ability hook system on Player (e.g. IPassiveAbility interface or EventBus-driven passive effects) so distinct characters meaningfully change build strategy (lifesteal, bonus vs undead, crit bonus, HP-for-damage tradeoff, summon familiars, fire DoT, taunt/armor, dual-wield attack speed, potion throws/debuffs, curse-lifts-over-time scaling).
- Create CharacterData .tres resources for all 10 base Hunters: The Reaper, Silver Priest, Witch Hunter, Bloodletter, Iron Widow, Pyromancer, Grave Warden, Moonlit Duelist, Alchemist, Cursed Noble. Implement each one's passive distinctly, not just reskins.
- CharacterSelect.tscn/.cs: minimal character-select screen listing all CharacterData, selecting one configures Player stats/weapon/passive at run start.`)

phase('Weapon roster')
log('Stage 8: full weapon roster (20+) with rarity tiers')
const s8 = await stage('Weapon roster', `Building on stages 1-7 (read existing WeaponData.cs, Weapon.cs, ShopUI first):
- Extend WeaponData/Weapon.cs to support rarity tiers (Common/Uncommon/Rare/Legendary) and weapon evolution (a base weapon can reference an "UpgradesTo" WeaponData for tiered versions), plus behavior differences per WeaponClass (Magic scales with a Magic stat, Cursed scales with missing HP, Summon spawns an independent familiar/turret scene, AoE/Splash does an area hit).
- Create WeaponData .tres resources for the full 20+ list: Rusty Scythe (already exists, verify), Silver Kris Dagger, Hunting Crossbow, Bone Bow, Flintlock Pistol, Sawn-off Blunderbuss, Hexed Revolver, Cathedral Rifle, Spellblade of Ash, Wraith Staff, Grimoire of Bones (summons skeletons - implement a simple Summon.tscn familiar that auto-attacks), Holy Water Flask, Cursed Chain Whip, War Cleaver, Twin Stiletto Blades, Silver Stake Launcher, Vampiric Claws, Alchemist's Firebomb, Frost Lantern (slow effect on enemies), Iron Bear Trap (placed trap, root+damage), Spectral Hound Whistle, Bell of Judgement (damages all enemies on screen).
- Register all new weapons in the shop pool from stage 6 so they appear for purchase.`)

phase('Enemy roster')
log('Stage 9-13: enemy roster, bosses, audio, meta-progression UI, balancing+juice — ALL running in parallel')
const CONCURRENCY_NOTE = `NOTE: this stage is running IN PARALLEL with FOUR sibling stages (Enemy roster, Bosses, Audio, Meta-progression UI, Balancing+Juice — whichever ones this prompt is not) against the SAME working copy of the repo, none of which have finished yet. Do not assume any of their work exists yet. To avoid stepping on each other's edits: stick to the file-ownership boundaries below, prefer adding NEW files over editing shared ones, and if you must touch a shared file, keep the edit small and additive.`

const [s9, s10, s11, s12, s13] = await parallel([
  () => stage('Enemy roster', `Building on stages 1-8 (read existing Enemy.tscn/EnemyData/WaveManager first). ${CONCURRENCY_NOTE}
- Create EnemyData .tres for the full roster: Ghoul (exists, verify), Skeletal Archer (exists, verify), Bloated Corpse (slow tank, explodes AoE on death), Wraith (phases through obstacles, erratic movement), Plague Rat Swarm (spawns in large low-HP groups).
- Implement wave-scaling formulas as isolated static methods in a NEW file EnemyScaling.cs: HP/damage/speed multiplier as a function of wave number, applied when WaveManager spawns enemies (not per-enemy-type duplication).
- Implement "elite" visual variant: at higher waves, spawned enemies get a stat buff and a recolor/glow (e.g. red eye glow via a shader param or modulate tweak) to signal danger.
- Verify Bloated Corpse's on-death AoE explosion actually damages the player/other enemies via HealthComponent.
- File ownership: you own EnemyData resources, Enemy.tscn behavior, and EnemyScaling.cs. If WaveManager.cs needs a change, keep it to the enemy-spawn-scaling call site only — do not touch boss-triggering or audio-hook code there.`),

  () => stage('Bosses', `Building on stages 1-8 (read existing EnemyData/Enemy.tscn/WaveManager/HealthComponent first). ${CONCURRENCY_NOTE}
- BossData.cs Resource: phase HP thresholds, per-phase attack patterns/params.
- Boss.tscn base scene (state machine: phase transitions, telegraphed attacks with wind-up timer + a visual warning indicator e.g. a red AoE decal before the hit lands).
- Implement 3 bosses as BossData + boss-specific attack scripts:
  1. The Bat-Winged Count: teleports/blinks around arena, summons bat swarms, "blood frenzy" phase at 50% HP (faster attacks, life drain).
  2. The Gravekeeper Colossus: slow heavy melee, ground-smash shockwave AoE zones, summons ghouls from graves in the arena.
  3. The Hollow Cardinal: homing curse bolts, AoE ritual circles that punish standing still, phase 2 summons cultist adds.
- IMPORTANT for parallel safety: do NOT edit WaveManager.cs to wire in boss triggers. Instead create a new BossManager.cs (own node/autoload-style component) that self-subscribes to EventBus.OnWaveStart, checks the wave number itself (10/15/20, configurable), and pauses/resumes normal spawns via a flag or its own EventBus signal (e.g. OnBossEncounterStart/End).
- File ownership: you own BossData, Boss.tscn, boss attack scripts, and the new BossManager.cs.`),

  () => stage('Audio', `Building on stages 1-8 (read existing AudioManager stub/EventBus first). ${CONCURRENCY_NOTE}
- Flesh out AudioManager.cs autoload: calm "shop phase" track player, driving "combat wave" track using multiple synced AudioStreamPlayers crossfading/layering additional intensity (percussion layer volumes rise) as wave timer progresses or enemy density increases, and a boss-theme/intensity-spike trigger listening for a boss-encounter EventBus signal (subscribe defensively — the Bosses stage is adding that signal concurrently and may not exist yet when you write this).
- Since no final audio assets exist, use silence-safe placeholder AudioStream references (or empty/generated short tone streams) and leave clearly marked "// TODO: replace with final audio asset" comments at every hook point (weapon-class hit sounds, enemy death sounds per type, level-up chime, boss roar/telegraph cue, UI click).
- Wire hook CALL SITES into existing systems (Weapon.cs hit sound by WeaponClass, Enemy death sound, LevelUpUI chime, UI button clicks) as small additive one-line calls to AudioManager — avoid larger refactors of those shared files.
- File ownership: you own AudioManager.cs and the small additive hook call-sites listed above. Do not touch WaveManager.cs, EnemyData, or BossData.`),

  () => stage('Meta-progression UI', `Building on stages 1-8 (read existing MainMenu/CharacterSelect/GameManager first). ${CONCURRENCY_NOTE}
- Meta-currency persistence (simple JSON save file via Godot FileAccess) tracking unlocked characters/weapons and a meta-currency balance earned per run.
- MainMenu.tscn: character select (locked characters shown greyed out until unlocked), unlock-purchase UI spending meta-currency.
- Expand HUD: minimap or off-screen enemy direction indicator arrows.
- PauseMenu.tscn (resume/settings/quit) and SettingsMenu.tscn (volume sliders wired to AudioManager — reference AudioManager's existing bus/volume API defensively since the Audio stage is editing that file concurrently; key rebind stub).
- RunSummary/DeathScreen.tscn: shown on player death or run completion (wave 20), displaying run stats (waves survived, kills, damage dealt, gold earned) and granting meta-currency.
- File ownership: you own MainMenu.tscn, CharacterSelect additions, PauseMenu, SettingsMenu, RunSummary/DeathScreen, and the save-file persistence script. Do not touch WaveManager.cs, EnemyData, BossData, or AudioManager.cs internals (only call its public API).`),

  () => stage('Balancing+Juice', `Building on stages 1-8 (read the whole project structure first — Scripts/, Resources/, Scenes/). ${CONCURRENCY_NOTE}
- Review the XP curve (stage 5) and shop-pricing/reroll formulas (stage 6), which already exist, for reasonable early/mid/late-run balance; adjust exported tunable values if clearly broken (e.g. runaway exponential, zero-cost rerolls) — keep the static formula methods isolated and documented with brief comments explaining the curve. Do NOT touch EnemyScaling.cs (owned by the concurrent Enemy-roster stage) — if enemy-wave balance needs a note, leave it as a TODO comment instead of editing that file.
- Add "juice": screen shake on hit/boss-slam (a small Camera2D shake helper), hit-stop (brief Engine.TimeScale dip on big hits), damage-number popups (pooled, per stage-3 pooling pattern), simple hit particles/flash on enemy damage.
- Performance pass: confirm enemies, projectiles, and damage-number popups all go through the existing ObjectPool (no per-frame Instantiate for high-frequency spawns), add basic offscreen culling for far-away enemies if the project lacks it.
- File ownership: you own the juice helpers (ScreenShake, HitStop, DamageNumber popup) and XP-curve/shop-pricing tuning tweaks only. Avoid editing EnemyData/EnemyScaling/BossData/AudioManager/MainMenu/PauseMenu/SettingsMenu — those belong to sibling stages running concurrently.
- Final report: summarize the full Nightbane project state as you find/leave it — what's implemented, any known gaps/TODOs (especially final art/audio placeholders, and anything you couldn't verify because a sibling stage's files weren't done yet), and how to open+run the project in Godot 4 to test it.`),
])

return { stages: [s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13] }
