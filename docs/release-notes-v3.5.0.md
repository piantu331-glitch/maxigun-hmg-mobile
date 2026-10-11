# M-1000 Maxigun HMG Mobile v3.5.0

## Highlights

- Updates weapon-record lookup to tolerate fields changed by other mods, including HD2 HUD+.
- Retains a strict identity check and rejects candidates below 80% similarity.
- Writes and verifies only the single movement-lock byte, leaving other weapon-record fields untouched.
- Adds bounded scanning and longer retry intervals after repeated attempts.
- Includes the updated main mod, read-only probe, and an offline locator simulation utility.

## How the new locator works

1. Uses the first 32 bytes of the captured record as a candidate signature.
2. Scores candidates against the full template and chooses the closest match.
3. Confirms identity using the independent dword at `+384` (`0x01010001` locked or `0x00010001` already unlocked).
4. Requires at least 80% similarity, then changes and rereads only byte `+387`.

Scanning covers the containing allocation plus `hm ±8 MB`, up to 32 MB. After 300 retries, the interval increases to 900 frames to limit repeated broad scans.

## Verification status

- Offline locator simulation: **11 passed, 0 failed**.
- In-game testing: **passed**. The modified weapon record was located with a 99.9% match and `locked_confirmed`; both mod changes applied.
- Simultaneous use with HD2 HUD+: **confirmed in game**; both mods were active and working.
- Records modified by 50% or more: designed to reject writing; this case has not been tested in game.

## Compatibility and installation

- Requires Bingus Shared Loader v15 or later with addon support enabled.
- Game build targeted by the package: 25480438 / executable 1.8.46015.0.
- The mod checks the `game.dll` SHA-256 and refuses to run if the binary differs.
- v3.5.0's tolerant lookup was designed for mods that edit the same weapon record. Coexistence with HD2 HUD+ was confirmed in game; other weapon-data mods have not all been tested individually.
- Import `Maxigun-HMG-Mobile-v3.5.zip`, click **Deploy**, then start the game.

See the [README](../README.md) and [installation guide](installation-guide.md) for details.

## Risk notice

This mod modifies game memory at runtime. It may violate the game's Terms of Service and carries anti-cheat risk. Use at your own risk; public matchmaking is not recommended.
