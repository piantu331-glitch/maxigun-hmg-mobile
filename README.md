# M-1000 Maxigun — Projectile Swap + Fire While Moving

A **Lua injection mod** for Helldivers 2, running through [Bingus Shared Loader](https://github.com/CowboyBingus/HD2-BingusSharedLoader).

**This mod replaces the M-1000 Maxigun backpack's projectile with the E/MG-101 HMG Emplacement projectile and enables firing while moving.**

> **Status: tested in game — v3.2.0**

One mod · one projectile replacement · one byte cleared to enable movement.

## Read before use

| Item | Details |
|---|---|
| Anti-cheat risk | Runtime game-memory modification may violate the game's Terms of Service. |
| Client-side only | Other players do not see the changes. |
| Suggested use | Solo or a private team that knows the mod is in use. |
| Disk writes | None; the game restores the original values when it exits. |
| Game updates | The mod checks the `game.dll` SHA-256 and refuses to run if it does not match. |
| Responsibility | Use at your own risk. |

**Do not use in public matchmaking.**

## What this mod does

Each row in Helldivers 2's projectile table describes a projectile: its caliber, mass, velocity, and damage data. The M-1000 Maxigun uses a projectile from the 8×60 mm family; the E/MG-101 HMG Emplacement uses one from the 12.5×100 mm family.

This mod replaces the Maxigun projectile row with the HMG Emplacement row, then clears one byte in the weapon component to enable firing while moving.

```text
Maxigun projectile row
  +48 caliber       8.0 → 12.5
  +56 velocity       920 → 880
  +60 mass            11 → 52
  +84 damage link    127 → 204
```

## Gameplay changes

| Property | M-1000 Maxigun | E/MG-101 HMG round |
|---|---:|---:|
| Damage / durable damage | 80 / 18 | **200 / 40** |
| Armor penetration | AP3 (medium) | **AP4 (heavy)** |
| Caliber | 8.0 mm | **12.5 mm** |
| Mass | 11 g | **52 g** |
| Muzzle velocity | 920 m/s | **880 m/s** |
| Demolition / stagger / force | 10 / 15 / 12 | 20 / 25 / 15 |
| Fire while moving | Locked | **Enabled** |

Because these projectiles come from different families, this is a cross-family replacement. Damage increases by 2.5×, armor penetration increases by one level, and projectile mass increases by 4.7×. **The heavier projectile changes its drop and hit feedback; this is expected behavior.**

## The clearest way to confirm it works

This mod changes an existing projectile rather than adding a new weapon, so the change may be hard to identify by sight alone. The most direct check is whether you can walk while firing. You can also check the two `true` values in the status log or compare the captured bytes with the included verification utility.

## In-game verification

After the mod was working in game, the captured bytes from before and after the write were checked field by field:

| Field | Before | After | E/MG-101 value |
|---|---:|---:|---:|
| Caliber (+48) | 8.0 | **12.5** | 12.5 |
| Velocity (+56) | 920 | **880** | 880 |
| Mass (+60) | 11 | **52** | 52 |
| Damage link (+84) | 127 | **204** | 204 |

All four key fields matched. The name hashes at `+28`, `+32`, and `+224` changed too, confirming the row took on the identity of another projectile instead of only receiving different stats.

The verification chain confirmed:

```text
1. The pre-write row matches the ORIGINAL_ROW template in the source: true
2. The calculated target matches the row written in game: true
3. All four key fields match the E/MG-101 values: all matched
4. All 31 changed bytes fall inside the write span: true
```

The second check matters most: it confirms the mod wrote to the row it intended to change. The first version wrote the right bytes to the wrong row (index 224, while the game used 225); its log reported success, but gameplay did not change. See the project iteration notes for more context.

## How it works

### Projectile lookup uses the damage link, not a guessed index

The Maxigun damage profile is 127, read from `*(game.dll + 58483896)`. Each projectile row stores the damage profile it uses at offset `+84`. Across the 350 projectile rows, damage link 127 identifies exactly one row: index 225.

Index or speed alone would be ambiguous: four rows have a velocity of 920 m/s (indices 224, 225, 233, and 234). The damage link uniquely identifies the Maxigun row.

### Weapon component lookup

The mod searches for the weapon component by its 1,232-byte contents, using the complete template published by the reference mod. It reaches the component table through `*(owner + (-13614272))`, where `owner = *(game.dll + 54973760)`. The table loads late, so the mod retries with backoff.

### Fire while moving

The mod clears one byte in `Minigun.WeaponDataComponent`:

```lua
Minigun.WeaponDataComponent
  edits = {{ offset = 387, replacement = unhex("00") }} -- 01 -> 00
```

The containing dword changes from `0x01010001` to `0x00010001`.

## Installation

### Requirements

- **Bingus Shared Loader v15 or later**, with addon support enabled
- The **M-1000 Maxigun** backpack (Python Commandos Warbond)

### Check for conflicts

Disable `starm/minigun_backpack_heavy_mobile` before installing this mod. It also changes damage profile 127 and armor penetration, so the two mods conflict. Disable other Maxigun mods as well.

### Steps

1. Exit the game completely; ending the process is required, not just returning to the main menu.
2. Import `dist/Maxigun-HMG-Mobile-v3.2.zip` into Bingus Shared Loader.
3. Click **Deploy**, then start the game.
4. Enter a mission and bring the Maxigun backpack.

The mod applies automatically after startup; no extra in-game action is needed.

## Confirm the mod is active

Logs are stored in:

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\
```

### Status file

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

Both values marked `true` are key.

### Log file

`MaxigunHMGRound.log` should include messages like:

```text
game_dll_hash_verified
projectile swapped: row=0x... index=225 (damage link 127) in one 236-byte span write
fire-while-moving enabled: record=0x... byte +387 cleared
both changes applied
```

### Verify the captured bytes

The mod writes full-row dumps to `MaxigunHMGRound-row-before.hex` and `MaxigunHMGRound-row-after.hex`. Run the included utility to compare the key fields:

```sh
node tools/verify_hmg_row.js
```

Expected output includes:

```text
after-capture calibre: 12.5 (HMG = 12.5)
after-capture speed  : 880  (HMG = 880)
after-capture mass   : 52   (HMG = 52)
after-capture dmg lnk: 204  (HMG = 204)

CONFIRMED: the row now carries the E/MG-101 HMG Emplacement values
```

## Safety checks

- The mod checks the `game.dll` SHA-256 and refuses to run on a mismatched version. The hash is cached, so it is calculated once.
- The target row must match the captured template byte for byte before it is changed.
- If the damage link matches multiple rows, the mod refuses to write rather than guessing.
- `MEM_IMAGE` regions are explicitly rejected; the mod does not modify code sections.
- The mod rereads and checks data before writing, then reads it back to verify the write.
- Original values are restored when the game exits.

### Single-span write

The 14 edits are combined into one 236-byte write spanning `+24..+259`. This reduces the write calls from 14 to 1 and avoids leaving the row partially changed between calls. Untouched bytes in the span retain their original values, so the result is byte-identical to the separate-write version.

## Known limitation

The current check requires the full 272-byte row to match its captured template. The mod changes 31 bytes and leaves 216 other bytes untouched; if the game changes any of those bytes at runtime, the mod may report `row_mismatch` and refuse to write.

The optional read-only probe is included to find out which bytes change. Until probe data shows the full-row check is too strict, the check remains in place; weakening it could make the mod write to the wrong data.

**Normal use does not require the probe.** Use it only to investigate `row_mismatch` or gather data about runtime changes.

## Optional read-only probe

`dist/Maxigun-ProbeRO.zip` is an observation tool. It does not write memory and contains no `WriteProcessMemory`, `VirtualProtect`, or `api.write` calls. It records which projectile-row bytes change, how often they change, and whether they fall inside the write span.

To use it, disable the main mod, install the probe by itself, launch a mission with the Maxigun backpack, fire at least one belt, then exit to write the report. See the installation guide for details.

## Version history

| Version | Changes |
|---|---|
| 3.0.0 | Projectile replacement and fire while moving |
| 3.1.0 | Engineering improvements: cached hash, single-span write, targeted recheck, and backoff retries |
| **3.2.0** | **In-game verified**; status changed from `applied_gameplay_unverified` to `applied` |

The four v3.1.0 optimizations were checked byte for byte to confirm behavior did not change:

```text
PASS — the one-shot span write is byte-identical to the 14-write version
```

## Repository layout

```text
dist/     Main mod and read-only probe packages
docs/     Installation guide, iteration notes, and release notes
src/      Main script, probe, and read-only locator
tools/    Packager and verification utilities
```

## Similar names

| Name | What it is | Relation to this mod |
|---|---|---|
| **M-1000 Maxigun** | Backpack minigun | **Target weapon** |
| **E/MG-101 HMG Emplacement** | Heavy machine-gun emplacement | **Source projectile** |
| A/G-16 Gatling Sentry | Gatling sentry | Unrelated |
| MG-206 HMG | Handheld heavy machine gun | Unrelated |

## Credits

- `starm/minigun_backpack_heavy_mobile` — reference for the `+387` fire-while-moving edit
- **Suzuka** — [helldivers-2-extra-slot](https://github.com/Suzuka2788/helldivers-2-extra-slot)
- **xypwn** — [Filediver](https://github.com/xypwn/filediver)
- **CowboyBingus** — shared loader

## License

MIT. Third-party attributions remain with their respective authors.
