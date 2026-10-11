'use strict';
/**
 * Offline verification of the v3.5 tolerant locator.
 *
 * Mirrors the Lua logic exactly and runs it against synthetic memory images
 * that reproduce the real failure: another mod has changed some fields of the
 * weapon record, so an exact-match locator would fail.
 *
 * This proves the algorithm picks the right record and classifies it correctly.
 */
const fs = require('fs');

const src = fs.readFileSync('C:/Users/Piantu/Downloads/juediqianbing/src/maxigun_hmg_round_v3.lua', 'utf8');
const s0 = src.indexOf('local WDC_TEMPLATE = unhex(');
const s1 = src.indexOf('\n\n', s0);
const tplHex = [...src.slice(s0, s1).matchAll(/'([0-9a-fA-F]+)'/g)].map(m => m[1]).join('');
const TPL = Buffer.from(tplHex, 'hex');

const TLEN = 1232;
const MOVE_LOCK = 387;
const SIG = TPL.subarray(0, 32);
const SIG_WEAK = TPL.subarray(0, 8);

function u32(b, at) { return b.readUInt32LE(at); }

console.log('=== the identity field ===');
console.log('  dword at +384 :', '0x' + u32(TPL, 384).toString(16).padStart(8, '0'));
console.log('  byte  at +387 :', '0x' + TPL[387].toString(16));
console.log('  => locked shape is 0x01010001; clearing +387 gives 0x00010001');

// ---------- the algorithm, mirroring find_record ----------
function findRecord(mem, opts = {}) {
  const threshold = opts.threshold ?? 0.80;
  let best = null, bestRatio = 0, bestFlag = null, exact = null;

  function consider(addr) {
    if (addr + TLEN > mem.length) return;
    const blk = mem.subarray(addr, addr + TLEN);
    let same = 0;
    for (let i = 0; i < TLEN; i++) if (blk[i] === TPL[i]) same++;
    const ratio = same / TLEN;
    if (ratio >= 0.9999) { exact = addr; return; }
    const flag = u32(blk, 384);
    const locked = flag === 0x01010001;
    const clear = flag === 0x00010001;
    const strong = locked || clear;
    if (best === null
      || (strong && bestFlag === null)
      || (strong === (bestFlag !== null) && ratio > bestRatio)) {
      best = addr; bestRatio = ratio; bestFlag = strong ? flag : null;
    }
  }

  // scan for SIG (strong signature)
  let i = -1;
  const seen = new Set();
  while ((i = mem.indexOf(SIG, i + 1)) !== -1) {
    if (!seen.has(i)) { seen.add(i); consider(i); }
    if (exact !== null) break;
  }
  if (exact !== null) return { found: exact, already: null, ratio: 1, why: 'exact' };

  if (best === null) {
    let j = -1;
    while ((j = mem.indexOf(SIG_WEAK, j + 1)) !== -1) {
      if (!seen.has(j)) { seen.add(j); consider(j); }
      if (exact !== null) break;
    }
    if (exact !== null) return { found: exact, already: null, ratio: 1, why: 'exact_weak' };
  }

  if (best === null) return { found: null, already: null, ratio: 0, why: 'no_signature_hit' };
  if (bestFlag === 0x00010001) return { found: null, already: best, ratio: bestRatio, why: 'already_clear' };
  if (bestFlag === 0x01010001 && bestRatio >= threshold) return { found: best, already: null, ratio: bestRatio, why: 'locked_confirmed' };
  return { found: null, already: null, ratio: bestRatio, why: 'identity_unconfirmed' };
}

// ---------- scenarios ----------
function makeMem(sizeMB) { return Buffer.alloc(sizeMB * 1024 * 1024, 0xAA); }

function placeRecord(mem, at, mutator) {
  const rec = Buffer.from(TPL);
  if (mutator) mutator(rec);
  rec.copy(mem, at);
  return at;
}

let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { console.log(`  PASS  ${name}`); pass++; }
  else { console.log(`  FAIL  ${name}  ${detail || ''}`); fail++; }
}

console.log('');
console.log('=== scenario 1: pristine record (HUD+ off) ===');
{
  const mem = makeMem(4);
  const at = placeRecord(mem, 1234 * 1024, null);
  const r = findRecord(mem);
  check('finds exact record', r.found === at && r.why === 'exact', JSON.stringify(r));
}

console.log('');
console.log('=== scenario 2: HUD+ changed several fields, lock still set ===');
{
  const mem = makeMem(4);
  const at = placeRecord(mem, 1234 * 1024, rec => {
    rec.writeUInt32LE(0xDEADBEEF, 200);   // some modded field
    rec.writeUInt32LE(7, 260);
    rec.writeUInt8(0x2A, 1000);
    rec.writeUInt32LE(0x11223344, 1100);
  });
  const r = findRecord(mem);
  const ratioOK = r.ratio > 0.99;
  check('still locates the record', r.found === at, JSON.stringify(r));
  check('classified as locked', r.why === 'locked_confirmed', r.why);
  console.log(`        match ratio: ${(r.ratio * 100).toFixed(2)}%  (a few changed bytes barely dent it)`);
}

console.log('');
console.log('=== scenario 3: another mod already cleared +387 ===');
{
  const mem = makeMem(4);
  const at = placeRecord(mem, 1234 * 1024, rec => { rec.writeUInt8(0, MOVE_LOCK); });
  const r = findRecord(mem);
  check('recognised as already clear', r.already === at && r.why === 'already_clear', JSON.stringify(r));
}

console.log('');
console.log('=== scenario 4: a decoy shares the 32-byte signature ===');
{
  const mem = makeMem(4);
  // decoy first: same opening bytes, but a different tail and a wrong +384
  placeRecord(mem, 1000 * 1024, rec => {
    for (let i = 64; i < 400; i++) rec[i] = (rec[i] ^ 0x5A) & 0xFF;
    rec.writeUInt32LE(0x00000000, 384);
  });
  // the real one later
  const real = placeRecord(mem, 1234 * 1024, rec => {
    rec.writeUInt32LE(0xDEADBEEF, 200);
    rec.writeUInt32LE(5, 260);
  });
  const r = findRecord(mem);
  check('picks the real record, not the decoy', r.found === real, `got ${r.found} want ${real}`);
  check('ratio reflects the real match', r.ratio > 0.99, String(r.ratio));
}

console.log('');
console.log('=== scenario 5: signature hit but identity unconfirmed -> REFUSE ===');
{
  const mem = makeMem(4);
  placeRecord(mem, 1234 * 1024, rec => {
    rec.writeUInt32LE(0x00000000, 384);      // not a lock shape
    for (let i = 64; i < 1232; i++) rec[i] = (rec[i] ^ 0xFF) & 0xFF;
  });
  const r = findRecord(mem);
  check('refuses to write', r.found === null && r.already === null, JSON.stringify(r));
  check('reports why', r.why === 'identity_unconfirmed', r.why);
  console.log(`        (best ratio was only ${(r.ratio * 100).toFixed(2)}%)`);
}

console.log('');
console.log('=== scenario 6: heavy modification (half the record rewritten) ===');
{
  const mem = makeMem(4);
  placeRecord(mem, 1234 * 1024, rec => {
    for (let i = 400; i < 1000; i++) rec[i] = (rec[i] ^ 0x33) & 0xFF;
  });
  const r = findRecord(mem);
  console.log(`        match ratio: ${(r.ratio * 100).toFixed(2)}%`);
  // This is the intended trade-off, not a defect: past a point the tool cannot
  // tell "the record was edited" from "this is a different record", so it
  // declines to write. Safety beats coverage when the target is uncertain.
  check('declines to write when similarity is too low', r.found === null && r.already === null, JSON.stringify(r));
  check('says why', r.why === 'identity_unconfirmed', r.why);
}

console.log('');
console.log('=== scenario 7: nothing resembling the record ===');
{
  const mem = makeMem(2);   // all 0xAA
  const r = findRecord(mem);
  check('reports no hit', r.why === 'no_signature_hit', r.why);
}

console.log('');
console.log(`=== ${pass} passed, ${fail} failed ===`);
