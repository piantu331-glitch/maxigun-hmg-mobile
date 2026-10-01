'use strict';
/**
 * CONFIRM the swapped row really is the E/MG-101 HMG Emplacement round.
 *
 * The mod logs "row 225 -> emplacement round" but that is the mod ASSERTING it.
 * Let me verify against the actual bytes:
 *
 *   1. MaxigunHMGRound-row-after.hex   = what the row looks like NOW
 *   2. the E/MG-101 values are known from the confirmed data
 *
 * If the after-bytes carry the E/MG-101 calibre / speed / mass / damage link,
 * the substitution is real and not just a claimed one.
 */
const fs = require('fs');

const logs = 'C:/Users/Piantu/AppData/Local/CowboyBingus/Helldivers2/Logs/';
const after = fs.readFileSync(logs + 'MaxigunHMGRound-row-after.hex', 'utf8').trim();
const before = fs.readFileSync(logs + 'MaxigunHMGRound-row-before.hex', 'utf8').trim();

const row = Buffer.from(after, 'hex');
const old = Buffer.from(before, 'hex');

console.log('=== row sizes ===');
console.log('  before:', old.length, ' after:', row.length);
if (row.length !== 272) { console.error('  !! expected 272'); process.exit(1); }

const f32 = (b, at) => b.readFloatLE(at);
const u32 = (b, at) => b.readUInt32LE(at);

console.log('');
console.log('=== the fields that identify a projectile ===');
const fields = [
  ['calibre (+48)', 48, f32],
  ['speed   (+56)', 56, f32],
  ['mass    (+60)', 60, f32],
  ['dmg link(+84)', 84, u32],
];

console.log('  field            before        after');
for (const [name, off, dec] of fields) {
  console.log(`  ${name}   ${String(dec(old, off)).padEnd(12)}  ${dec(row, off)}`);
}

console.log('');
console.log('=== known values (from the confirmed specs) ===');
console.log('  M-1000 Maxigun  : calibre 8.0  speed 920  mass 11  damage link 127');
console.log('  E/MG-101 HMG    : calibre 12.5 speed 880  mass 52  damage link 204');

console.log('');
console.log('=== verdict ===');
const cal = f32(row, 48), spd = f32(row, 56), mass = f32(row, 60), link = u32(row, 84);
const isHMG = Math.abs(cal - 12.5) < 0.01 && Math.abs(spd - 880) < 1 && Math.abs(mass - 52) < 0.5 && link === 204;
console.log('  after-capture calibre:', cal, '(HMG = 12.5)');
console.log('  after-capture speed  :', spd, '(HMG = 880)');
console.log('  after-capture mass   :', mass, '(HMG = 52)');
console.log('  after-capture dmg lnk:', link, '(HMG = 204)');
console.log('');
console.log(isHMG
  ? '  CONFIRMED: the row now carries the E/MG-101 HMG Emplacement values'
  : '  NOT a full HMG match -- see the per-field comparison above');

console.log('');
console.log('=== full byte diff (before -> after) ===');
const diffs = [];
for (let i = 0; i < 272; i++) if (old[i] !== row[i]) diffs.push(i);
console.log('  bytes changed:', diffs.length);
console.log('  positions    :', diffs.join(', '));
