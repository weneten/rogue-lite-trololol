extends Node

# Global signal hub. Every gameplay system communicates through here instead of
# holding direct references to each other, keeping Player/Enemies/UI/Waves decoupled.
# Registered as an autoload singleton (see project.godot [autoload]).

signal enemy_killed(enemy, currency_reward, experience_reward)
# Raised by WaveManager the moment the wave loop arms itself in the arena —
# once per run, whether the player came through CharacterSelect or booted
# Arena.tscn directly. Anything holding per-run state clears it here.
signal run_started()

signal wave_start(wave_number)
signal wave_end(wave_number)
signal player_level_up(new_level)
# After every queued moon-boon for this intermission has been picked. ShopUI
# waits on this so the Ossuary never covers the boon screen.
signal intermission_boons_done()
signal item_picked_up(item_id)
signal player_damaged(damage_amount, current_health)

# Raised on every player HP change (damage/heal/max-HP upgrade), forwarded by Player.gd
# from its HealthComponent so HUD never needs a direct scene reference.
signal player_health_changed(current_health, max_health)

# Raised whenever the player's banked XP or level changes (gem pickup or level-up). HUD's XP bar listens here.
signal xp_changed(current_xp, xp_to_next_level, level)

# Raised whenever GameManager's currency total changes. HUD's currency display listens here.
signal currency_changed(current_currency)

signal player_died()

# Raised whenever a player weapon lands a hit, carrying the final damage dealt and the
# target hit. Feeds character passives (lifesteal, on-hit DoT, etc.) via PlayerStats.notify_damage_dealt;
# broadcast on EventBus too so future systems (damage numbers, combat log) can listen without
# touching PlayerStats directly.
signal player_damage_dealt(target, amount)

# Raised by BossManager when a boss is spawned. Carries display name and trigger wave.
signal boss_encounter_start(boss_name, wave_number)

# Raised when a boss fight ends (boss death or run fail). defeated=true if boss was killed.
signal boss_encounter_end(boss_name, defeated)
