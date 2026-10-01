# M-1000 Maxigun — HMG Projectile Swap + Fire While Moving

A Lua injection mod for Helldivers 2, running through the [Bingus Shared Loader](https://github.com/CowboyBingus/HD2-BingusSharedLoader).

**Replaces the backpack Maxigun projectile with the E/MG-101 HMG Emplacement projectile and enables firing while moving.**

> **Status: tested in game — v3.2.0**

## Read before use

| Item | Details |
|---|---|
| Anti-cheat risk | Runtime memory modification may violate the game's Terms of Service. |
| Client-side only | Other players do not see the changes. |
| Suggested use | Solo or a private team that knows the mod is in use. |
| Disk writes | None; values are restored when the game exits. |
| Game updates | The mod checks the `game.dll` SHA-256 and refuses to run if it differs. |
| Responsibility | Use at your own risk. |

**Do not use in public matchmaking.**

## Changes

| Property | M-1000 Maxigun | E/MG-101 HMG round |
|---|---:|---:|
| Damage / durable damage | 80 / 18 | **200 / 40** |
| Armor penetration | AP3 (medium) | **AP4 (heavy)** |
| Caliber | 8.0 mm | **12.5 mm** |
| Mass | 11 g | **52 g** |
| Muzzle velocity | 920 m/s | **880 m/s** |
| Demolition / stagger / force | 10 / 15 / 12 | 20 / 25 / 15 |
| Fire while moving | Locked | **Enabled** |

These are different projectile families (8×60 mm and 12.5×100 mm). The swap increases damage by 2.5× and mass by 4.7×, so drop and hit feedback will feel different.

## In-game verification

The before/after bytes captured in game were checked field by field:

| Field | Before | After | E/MG-101 value |
|---|---:|---:|---:|
| Caliber (+48) | 8.0 | **12.5** | 12.5 |
| Velocity (+56) | 920 | **880** | 880 |
| Mass (+60) | 11 | **52** | 52 |
| Damage link (+84) | 127 | **204** | 204 |

All four fields matched. The name hashes at `+28`, `+32`, and `+224` changed as well, confirming the projectile identity was replaced rather than only its stats.

The verification chain confirmed that the original row matched the source template, the calculated target matched the row written in game, and all 31 changed bytes fell within the write span.

## How it works

The mod finds the Maxigun damage profile (127), then searches the projectile table for the row whose `+84` damage link is 127. That link uniquely identifies row 225; speed alone is ambiguous because four rows use 920 m/s. The mod copies the HMG projectile row to the target row after validating the complete original row.

The movement lock is cleared at byte offset 387 in `Minigun.WeaponDataComponent` (`01` → `00`).

## Installation

1. Exit the game completely.
2. Import `Maxigun-HMG-Mobile-v3.2.zip` into Bingus Shared Loader v15 or later, with addon support enabled.
3. Click **Deploy**, then start the game.
4. Do not run another Maxigun mod at the same time.

If `starm/minigun_backpack_heavy_mobile` is installed, disable it first. It also changes damage profile 127 and armor penetration, which conflicts with this mod.

## Confirm it is active

Check `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\MaxigunHMGRound-STATUS.txt`. A successful run should report:

```text
OK - projectile swapped + fire while moving
mod     : MaxigunHMGRound v3.2.0
status  : applied
records : 2
projectile swap : true
fire while move : true
```

The log also records `game_dll_hash_verified`, the projectile row and damage link, and the cleared movement-lock byte. Before/after row dumps are written as `MaxigunHMGRound-row-before.hex` and `MaxigunHMGRound-row-after.hex`.

See the [installation and troubleshooting guide](docs/installation-guide.md).

## Read-only probe

`Maxigun-ProbeRO.zip` is an optional observation tool. It does not write memory; it records which bytes in the projectile row change while playing. Install it by itself with the main mod disabled, enter a mission with the backpack Maxigun, fire at least one belt, then exit to write the report. See the guide for details.

## Repository layout

- `dist/` — Main mod and read-only probe packages
- `docs/` — Installation guide and iteration notes
- `src/` — Mod and probe scripts
- `tools/` — Packaging and verification utilities

## Credits

- `starm/minigun_backpack_heavy_mobile` — reference for the movement unlock
- [Suzuka](https://github.com/Suzuka2788/helldivers-2-extra-slot)
- [xypwn / Filediver](https://github.com/xypwn/filediver)
- CowboyBingus — shared loader

## License

MIT. Third-party attributions remain with their respective authors.
