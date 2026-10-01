'use strict';
/**
 * Prove the ONE-SHOT span write produces BYTE-IDENTICAL output to the old
 * 14-separate-writes approach.
 *
 * If the two differ, the refactor changed behaviour -- which it must not.
 */
const fs = require('fs');
const t = fs.readFileSync(require('path').join(__dirname,'..','src','maxigun-hmg-round.lua'), 'utf8');

// the edits, straight from the source
const block = t.slice(t.indexOf('local EDITS = {'), t.indexOf('\n}', t.indexOf('local EDITS = {')));
const edits = [...block.matchAll(/offset=(\d+),\s*bytes=unhex\('([0-9a-fA-F]*)'\)/g)]
  .map(m => ({ offset: Number(m[1]), bytes: m[2] }));

// the original row, from the unhex literal
// the literal spans multiple lines joined with '..', so read until the
// statement ends (the line that contains only ')' after the last fragment)
const rowStart = t.indexOf('local ORIGINAL_ROW = unhex(');
const rowEnd = t.indexOf('\n\n', rowStart);
const rowLit = t.slice(rowStart, rowEnd);
const hexParts = [...rowLit.matchAll(/'([0-9a-fA-F]+)'/g)].map(m => m[1]).join('');
const orig = Buffer.from(hexParts, 'hex');

console.log('=== inputs ===');
console.log('  edits        :', edits.length);
console.log('  ORIGINAL_ROW :', orig.length, 'bytes');
if (orig.length !== 272) { console.error('  !! expected 272 bytes, got ' + orig.length); process.exit(1); }

// --- method A: 14 separate writes (the old behaviour) ---
const a = Buffer.from(orig);
for (const e of edits) {
  const b = Buffer.from(e.bytes, 'hex');
  b.copy(a, e.offset);
}

// --- method B: one masked span write over +24..+259 (the new behaviour) ---
const S = 24, E = 259;
let span = Buffer.from(orig.subarray(S, E + 1));
for (const e of edits) {
  const rel = e.offset - S;
  const b = Buffer.from(e.bytes, 'hex');
  b.copy(span, rel);
}
const bOut = Buffer.from(orig);
span.copy(bOut, S);

console.log('');
console.log('=== comparison ===');
console.log('  identical:', a.equals(bOut));
const diffs = [];
for (let i = 0; i < 272; i++) if (a[i] !== bOut[i]) diffs.push(i);
console.log('  differing byte positions:', diffs.length ? diffs.join(', ') : 'none');

console.log('');
console.log('=== what actually changed vs the original ===');
const changed = [];
for (let i = 0; i < 272; i++) if (orig[i] !== a[i]) changed.push(i);
console.log('  bytes changed:', changed.length);
console.log('  positions    :', changed.join(', '));

console.log('');
console.log('=== span write covers all of them? ===');
const outside = changed.filter(i => i < S || i > E);
console.log('  span          : +' + S + '..+' + E, '(' + (E - S + 1) + ' bytes)');
console.log('  changed outside the span:', outside.length ? outside.join(', ') : 'none');

console.log('');
console.log(a.equals(bOut) && outside.length === 0
  ? 'PASS — the one-shot span write is byte-identical to the 14-write version'
  : 'FAIL — behaviour changed');
