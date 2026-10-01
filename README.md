# M-1000 Maxigun ← E/MG-101 HMG Emplacement — Projectile Swap + Fire While Moving

A Lua injection mod for Helldivers 2, running on [Bingus Shared Loader](https://github.com/CowboyBingus/HD2-BingusSharedLoader).

**Replaces the M-1000 Maxigun backpack minigun's rounds with E/MG-101 HMG Emplacement rounds and enables firing while moving.**

---

## ⚠️ Read This First

### 1. In-game testing

**Tested in-game: both features work as intended.**

- The M-1000 Maxigun backpack minigun uses E/MG-101 HMG Emplacement projectiles.
- Firing while moving is enabled.

To check the mod's load status, see:

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\MaxigunHMGRound-STATUS.txt
```

### 2. Anti-cheat risk

- This mod modifies game memory at runtime and **may violate the game's Terms of Service**.
- It is **client-side only**; teammates will not see the changes.
- Use it in solo play or with a premade group that knows about the mod.
- All changes are restored when the game exits; nothing is written to disk.
- The mod refuses to run on an unsupported game version (it checks the `game.dll` SHA-256).

---

## 1. Weapons

| Common name | Official name | Internal projectile name |
|---|---|---|
| Backpack minigun | **M-1000 Maxigun** | `M-1000 P` (entity/component name: `Minigun`) |
| HMG emplacement | **E/MG-101 HMG Emplacement** | `Rifle 12.5x100mm Full Metal Jacket` |

Do not confuse the target with these unrelated weapons:

- **M-1000 Maxigun** — the backpack minigun targeted by this mod
- **A/G-16 Gatling Sentry** — the Gatling sentry stratagem
- **MG-206 HMG** — the handheld heavy machine gun

---

## 2. What Changes

| Stat | Before (Maxigun) | After (E/MG-101) |
|---|---:|---:|
| **Damage / durable damage** | 80 / 18 | **200 / 40** |
| **Armor penetration** | AP3 (medium) | **AP4 (heavy)** |
| **Mass** | 11 g | **52 g** |
| **Muzzle velocity** | 920 m/s | **880 m/s** |
| Demolition / stagger / force | 10 / 15 / 12 | 20 / 25 / 15 |
| **Fire while moving** | ❌ Locked | **✅ Enabled** |

These are entirely different projectile families (8×60 mm vs. 12.5×100 mm), so this is a cross-family copy:

- Damage is **2.5×** higher.
- Armor penetration increases by one level.
- **Mass increases by 4.7×**, so drop and impact feedback will be noticeably different.

---

## 3. Change One: Projectile Swap

### Identification by damage-profile link, not by index

```
Maxigun damage profile = 127 (read from *(game.dll + 58483896))
Projectile row +84 stores its damage-profile ID.
There are 350 rows in the table:

    dmgid 127 -> exactly one row: index 225
```

**Why not identify the row by index or stats?** Four rows have the same 920 m/s velocity (indices 224/225/233/234), so their stats alone are ambiguous. The damage-profile link uniquely identifies the correct row.

### What changed

Row 225 is replaced with the E/MG-101 emplacement row, byte for byte (14 fields):

| Offset | Field | Maxigun → emplacement |
|---|---|---|
| +48 | Caliber | 8.0 → **12.5** |
| +56 | Velocity | 920 → **880** |
| +60 | Mass | 11 → **52** |
| +84 | Damage-profile link | 127 → **204** |
| 10 other fields | Armor, identifiers, hashes | — |

### Damage changes automatically with the projectile

Projectile row `+84` specifies which damage profile it uses:

```
Maxigun row     +84 = 127
E/MG-101 row    +84 = 204
```

In v3, the entire 272-byte row is copied, changing `+84` from 127 to 204. The projectile therefore uses the HMG damage profile (200/40/AP4) automatically.

**A separate damage-only version is unnecessary:** the damage change is included in the projectile swap.

### Locating the weapon component

The weapon component is found by searching for its complete 1,232-byte content, using the full template published by the reference mod. The component table is reached through `*(owner + (-13614272))`, where `owner = *(game.dll + 54973760)`.

> ⚠️ The component table loads late. The mod retries for up to about two minutes.

### Fallback behavior

If the damage link cannot be found, the mod falls back to an exact match of the full 272-byte row. If neither check succeeds, it refuses to write.

---

## 4. Change Two: Fire While Moving

This follows the reference mod and changes a single byte:

```lua
Minigun.WeaponDataComponent
  edits = {{ offset = 387, replacement = unhex("00") }}   -- 01 -> 00
```

The containing 4-byte dword is:

```
+384 original = 0x01010001
+384 modified = 0x00010001
```

**Only byte 387 changes**, verified byte by byte.

---

## 5. Investigation Notes

| Attempt | Result |
|---|---|
| Modify index 224 | ❌ Correct bytes, but the game reads index 225 |
| Scan bytes for the record | ❌ The record is reached through a pointer dereference, so scanning misses it |
| Identify by fingerprint | ❌ Fingerprint was too broad and matched multiple rows |
| **Identify by damage link** | ✅ **Works** — `+84 == 127` is unique in the table |
| Guess the projectile type field | ❌ `ProjectileWeaponComponent.ProjType` was never found |

**Key breakthrough:** instead of guessing which projectile the minigun references, reverse-map from its damage profile.

---

## 6. Confirmed Data

| Item | Value |
|---|---|
| Projectile table | `ProjectileSettings`, **272-byte** rows, 350 rows |
| Damage table | `DamageSettings`, **76-byte** rows, 649 rows |
| Weapon component table | `WeaponDataComponent`, **1,232-byte** rows |
| LDLD header | **16 bytes**, `block_size == count*row_size + 16` |
| Maxigun damage profile | `*(game.dll + 58483896)` → `type=127 dmg=80 AP=3,3,3 demo=10 force=15/12` |
| E/MG-101 projectile row | Index 249, caliber 12.5, velocity 880, mass 52, `+84 = 204` |
| Fire while moving | Weapon component **`+387`**, `01 → 00` |
| Game build | 25480438 / exe **1.8.46015.0** |
| `game.dll` SHA-256 | `2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e` |

**Projectile row field layout:**

| Offset | Field |
|---|---|
| +0 | Family tag `0x393D9518` (shared) |
| +24 | Tag |
| +28 / +32 | `name_upper` / `name_cased` |
| +48 | Caliber (f32) |
| +56 | Velocity (f32) |
| +60 | Mass (f32) |
| +64 | Drag (f32) |
| **+84** | **Damage-profile link** |
| +192 / +196 / +220 / +224 / +256 | Other fields |

---

## 7. Safety Checks

- Checks the `game.dll` **SHA-256** and refuses to run on an unsupported version.
- Writes only when the target bytes exactly match the captured bytes.
- Reads back and verifies every write immediately.
- Restores page protection immediately after temporarily changing it.
- Refuses to write if the damage link matches multiple rows.
- Finds the weapon record by content, not a fixed index.

---

## 8. Installation

1. Fully exit the game.
2. Import `dist/Maxigun-HMG-Mobile-v3.zip`.
3. Click **Deploy**.
4. Start the game.

Use this instead of other Maxigun mods; they occupy the same slot.

> If `starm/minigun_backpack_heavy_mobile` is installed, disable it first. It also modifies damage profile 127 and armor penetration, which can conflict with this mod.

---

## 9. Files

```
dist/
  Maxigun-HMG-Mobile-v3.zip    Release build
src/
  maxigun_hmg_round_v3.lua     Main script
  maxigun_narrow.lua           Read-only projectile-row probe
docs/
  confirmed-data.md            Byte-level confirmed data (219 lines)
  design-decisions.md          Design decisions
```

---

## 10. Pitfalls

| Pitfall | Lesson |
|---|---|
| Modifying index **224** | The game reads **225**; four rows share the same velocity |
| Scanning bytes for the record | The record is reached through a pointer dereference |
| **Fingerprint matching** | Too broad; multiple rows matched, creating ambiguity |
| **Guessing enum values** | Enums change between game builds; community JSON was an old snapshot |
| `ProjectileWeaponComponent.ProjType` | Could not be located; the implementation uses a different route |
| Hand-writing hex literals | Bytes were repeatedly dropped; generate them with a script |

---

## 11. Credits

- Reference mod: `starm/minigun_backpack_heavy_mobile` (source of the `+387` fire-while-moving change)
- **Suzuka** — [helldivers-2-extra-slot](https://github.com/Suzuka2788/helldivers-2-extra-slot)
- **xypwn** — [Filediver](https://github.com/xypwn/filediver)
- **CowboyBingus** — Shared Loader
