# Installation Guide

This guide covers installation, in-game verification, the optional read-only probe, and common issues.

## Requirements

| Requirement | Details |
|---|---|
| Bingus Shared Loader | v15 or later, with addon support enabled |
| Game build | 25480438 / executable 1.8.46015.0 |
| Stratagem | M-1000 Maxigun backpack (Python Commandos Warbond) |

To check the loader, open `BingusSharedLoader.log`. Its first line should read `Bingus Shared Loader loader-v18; API 1`.

## Install

1. Exit the game completely; returning to the main menu is not enough.
2. Disable `starm/minigun_backpack_heavy_mobile` and other Maxigun mods. The reference mod also changes damage profile 127 and armor penetration.
3. Import `Maxigun-HMG-Mobile-v3.2.zip` into the loader.
4. Click **Deploy**, then launch the game. The changes apply automatically after startup.

## Verify in a mission

Bring the M-1000 Maxigun backpack. You should be able to walk while firing; damage and armor penetration should also increase (80 → 200, AP3 → AP4). The projectile is from a different family, so its heavier mass changes drop and hit feedback. This is expected.

If it feels unchanged, check whether you can move while firing and inspect the status file below.

## Check the logs

Logs are stored in `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`.

`MaxigunHMGRound-STATUS.txt` should contain:

```text
OK - projectile swapped + fire while moving
mod     : MaxigunHMGRound v3.2.0
build   : 25480438 / exe 1.8.46015.0
status  : applied
records : 2
projectile swap : true
fire while move : true
```

Both values must be `true`. The log should also report `game_dll_hash_verified`, the projectile row (index 225, damage link 127), and the movement flag cleared at byte `+387`.

Before/after row dumps are available as `MaxigunHMGRound-row-before.hex` and `MaxigunHMGRound-row-after.hex`. Key expected changes are caliber `8.0 → 12.5` at `+48`, velocity `920 → 880` at `+56`, mass `11 → 52` at `+60`, and damage link `127 → 204` at `+84`.

## Optional read-only probe

`Maxigun-ProbeRO.zip` observes changes to the projectile row and does not write memory.

1. Exit the game and disable the main mod.
2. Install only `Maxigun-ProbeRO.zip` and launch a mission.
3. Bring the Maxigun backpack and fire at least one full belt. Firing may be necessary to trigger changes.
4. Play for a few minutes, then exit the game to write the report. Repeat on another mission if useful.

The report files are `MaxigunProbeRO-STATUS.txt`, `MaxigunProbeRO-changes.txt`, and `MaxigunProbeRO-row.hex`. Changes outside the expected write span may indicate that the main mod's full-row check needs re-evaluation. A changed `+84` damage link or a moved address may mean the game data layout changed.

## Troubleshooting

- **`waiting` or `locate`:** The component table loads late. The mod retries with backoff (30, 120, then 300 frames); entering a mission usually allows it to initialize.
- **`game_dll_hash_mismatch`:** The game build changed and the mod refused to run. Wait for an updated build.
- **`row_mismatch`:** The projectile row differs from the captured template, possibly because the game changed or another mod edited it. Disable conflicting Maxigun mods and restart.
- **`damage_link_ambiguous`:** More than one row matched damage link 127. The mod refuses to write rather than guessing; the locator must be rechecked for the new game build.
- **No visible effect:** Confirm the two `true` values in the status file, disable conflicting mods, and make sure you brought the M-1000 Maxigun backpack (not the A/G-16 Gatling Sentry).

## Uninstall

Exit the game, remove the mod in the loader, and deploy again. The mod changes runtime memory only; the game restores its original data when it exits. Restarting the game reloads clean data if needed.

## Similar names

| Name | Meaning |
|---|---|
| M-1000 Maxigun | Backpack weapon modified by this mod |
| E/MG-101 HMG Emplacement | Source of the replacement projectile |
| A/G-16 Gatling Sentry | Separate sentry; not affected |
| MG-206 HMG | Separate handheld weapon; not affected |
