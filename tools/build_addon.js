#!/usr/bin/env node
/**
 * Package a plaintext Lua addon into an Arsenal / HD2MM ZIP.
 * Node port of hd2-lua-mod-skill tools/build_addon.py + hd2_archive.py,
 * byte-for-byte compatible with BingusSharedLoader scripts/archive.py.
 *
 * usage:
 *   node build_addon.js --name mods/<author>/<mod> --entry <file.lua> \
 *        --guid <UUID> --display-name "My Mod" --output out/My-Mod.zip
 */
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

// ---- archive format constants ------------------------------------------
const MAGIC = 0xf0000011;
const TYPE = 0xa14e8dfa2cd117e2n;      // archive "lua" type marker
const ENVELOPE_VERSION = 2;
const FAMILY = '9ba626afa44a3aa3';
const ARCHIVE_NAME = FAMILY + '.patch_0';

const MASK = (1n << 64n) - 1n;
const MIX = 0xc6a4a7935bd1e995n;

/** Seed-zero MurmurHash64A over the UTF-8 resource path. */
function resourceHash(name) {
  const data = Buffer.from(name, 'utf8');
  const M = MASK;
  let value = (BigInt(data.length) * MIX) & M;
  const end = Math.floor(data.length / 8) * 8;
  for (let i = 0; i < end; i += 8) {
    let word = data.readBigUInt64LE(i);
    word = (word * MIX) & M;
    word ^= word >> 47n;
    value = ((value ^ ((word * MIX) & M)) * MIX) & M;
  }
  if (end < data.length) {
    let tail = 0n;
    for (let i = data.length - 1; i >= end; i--) tail = (tail << 8n) | BigInt(data[i]);
    value = ((value ^ tail) * MIX) & M;
  }
  value ^= value >> 47n;
  value = (value * MIX) & M;
  return (value ^ (value >> 47n)) & M;
}

function envelope(body) {
  const b = Buffer.alloc(8);
  b.writeUInt32LE(body.length, 0);
  b.writeUInt32LE(ENVELOPE_VERSION, 4);
  return Buffer.concat([b, body]);
}

/** pairs: iterable of [nameHashBigInt, envelopeBytes] already in final order. */
function makeArchiveRaw(pairs) {
  if (!pairs.length) throw new Error('an archive needs at least one resource');
  const count = pairs.length;
  let offset = (104 + 80 * count + 15) & ~15;
  const entryChunks = [];
  const bodyChunks = [Buffer.alloc(offset)];
  let bodyLen = offset;

  pairs.forEach(([nameHash, resource], index) => {
    const e = Buffer.alloc(80);
    e.writeBigUInt64LE(nameHash & MASK, 0);   // name_hash
    e.writeBigUInt64LE(TYPE, 8);              // type
    e.writeBigUInt64LE(BigInt(offset), 16);   // offset
    e.writeBigUInt64LE(0n, 24);
    e.writeBigUInt64LE(0n, 32);
    e.writeBigUInt64LE(0n, 40);
    e.writeBigUInt64LE(0n, 48);
    e.writeUInt32LE(resource.length, 56);     // length
    e.writeUInt32LE(0, 60);
    e.writeUInt32LE(0, 64);
    e.writeUInt32LE(16, 68);
    e.writeUInt32LE(16, 72);
    e.writeUInt32LE(index, 76);
    entryChunks.push(e);

    bodyChunks.push(resource);
    bodyLen += resource.length;
    // Real patches start each body at a 16-byte aligned offset, but the LAST
    // body is NOT padded -- the file ends exactly at the end of the data.
    const isLast = index === pairs.length - 1;
    if (!isLast) {
      const pad = (16 - (bodyLen % 16)) % 16;
      if (pad) { bodyChunks.push(Buffer.alloc(pad)); bodyLen += pad; }
    }
    offset = bodyLen;
  });

  const header = Buffer.alloc(72);
  header.writeUInt32LE(MAGIC, 0);
  header.writeUInt32LE(1, 4);
  header.writeUInt32LE(count, 8);
  // 20 bytes zero at 12..31
  header.writeBigUInt64LE(BigInt(bodyLen), 32);   // total archive size
  header.writeBigUInt64LE(0n, 40);
  // 24 bytes zero at 48..71

  const types = Buffer.alloc(32);
  types.writeUInt32LE(0, 0);
  types.writeUInt32LE(0, 4);
  types.writeBigUInt64LE(TYPE, 8);
  types.writeUInt32LE(count, 16);
  types.writeUInt32LE(0, 20);
  types.writeUInt32LE(16, 24);
  types.writeUInt32LE(16, 28);

  const entries = Buffer.concat(entryChunks);
  const bodies = Buffer.concat(bodyChunks);
  const all = Buffer.concat([header, types, entries, bodies.subarray(104 + entries.length)]);
  // the header+types+entries must overwrite the reserved front area
  header.copy(all, 0);
  types.copy(all, 72);
  entries.copy(all, 104);
  return all;
}

function makeArchive(resources) {
  const names = Object.keys(resources).sort();
  return makeArchiveRaw(names.map((n) => [resourceHash(n), resources[n]]));
}

// ---- packaging ----------------------------------------------------------
const NAME_RE = /^mods\/[A-Za-z0-9_]+\/[A-Za-z0-9_]+(?:\/[A-Za-z0-9_]+)*$/;
const ILLEGAL = new Set(['\\', '/', ':', '*', '?', '"', '<', '>', '|']);

function entrySource(name, source) {
  if (!NAME_RE.test(name)) {
    throw new Error('name must match mods/<author>/<mod>[/<sub>], letters/digits/underscore only');
  }
  if (name === 'mods/codex/loader') throw new Error('mods/codex/loader is reserved');
  if (source.length >= 3 && source[0] === 0xef && source[1] === 0xbb && source[2] === 0xbf) {
    throw new Error('entry must be plaintext UTF-8 Lua, no BOM');
  }
  if (source[0] === 0x1b) throw new Error('entry must not be bytecode');
  if (source.includes(0)) throw new Error('entry must not contain NUL bytes');
  source.toString('utf8');   // throws on invalid UTF-8
  const marker = Buffer.from('-- HD2-Addon: ' + name + '\n', 'utf8');
  if (marker.length > 256) throw new Error('declaration must fit in the first 256 bytes');
  if (source.subarray(0, 13).toString() === '-- HD2-Addon:') {
    const nl = source.indexOf(0x0a);
    if (nl < 0) throw new Error('existing declaration has no newline');
    const line = source.subarray(0, nl).toString().replace(/\r$/, '');
    if (line !== marker.subarray(0, marker.length - 1).toString()) {
      throw new Error('existing declaration does not match the resource name');
    }
    return Buffer.concat([marker, source.subarray(nl + 1)]);
  }
  return Buffer.concat([marker, source]);
}

function checkDisplayName(title) {
  const bad = [...title].filter((c) => ILLEGAL.has(c));
  if (bad.length) {
    throw new Error(`display name contains characters Windows forbids in file names ` +
      `[${bad.join(' ')}]: ${JSON.stringify(title)} -- mod managers use this string as a ` +
      `folder name, so the import fails`);
  }
  // eslint-disable-next-line no-control-regex
  if (!/^[\x00-\x7F]*$/.test(title)) {
    console.error(`WARNING: display name is not ASCII (${JSON.stringify(title)}); some mod managers mishandle it`);
  }
}

// ---- minimal ZIP writer (deflate, fixed 1980 timestamp) -----------------
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = (crc ^ buf[i]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function zipWrite(files) {
  const locals = [];
  const central = [];
  let offset = 0;
  const names = Object.keys(files).sort();

  for (const name of names) {
    const raw = files[name];
    const comp = zlib.deflateRawSync(raw, { level: 9 });
    const nameBuf = Buffer.from(name, 'utf8');
    const crc = crc32(raw);

    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(20, 4);          // version needed
    lh.writeUInt16LE(0, 6);           // flags
    lh.writeUInt16LE(8, 8);           // method deflate
    lh.writeUInt16LE(0, 10);          // time
    lh.writeUInt16LE(0x21, 12);       // date = 1980-01-01
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(comp.length, 18);
    lh.writeUInt32LE(raw.length, 22);
    lh.writeUInt16LE(nameBuf.length, 26);
    lh.writeUInt16LE(0, 28);
    locals.push(lh, nameBuf, comp);

    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE(0x031e, 4);      // version made by (unix)
    ch.writeUInt16LE(20, 6);
    ch.writeUInt16LE(0, 8);
    ch.writeUInt16LE(8, 10);
    ch.writeUInt16LE(0, 12);
    ch.writeUInt16LE(0x21, 14);
    ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(comp.length, 20);
    ch.writeUInt32LE(raw.length, 24);
    ch.writeUInt16LE(nameBuf.length, 28);
    ch.writeUInt16LE(0, 30);
    ch.writeUInt16LE(0, 32);
    ch.writeUInt16LE(0, 34);
    ch.writeUInt16LE(0, 36);
    ch.writeUInt32LE((0o100644 << 16) >>> 0, 38);   // external attrs
    ch.writeUInt32LE(offset, 42);
    central.push(ch, nameBuf);

    offset += lh.length + nameBuf.length + comp.length;
  }

  const localBuf = Buffer.concat(locals);
  const centralBuf = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(names.length, 8);
  eocd.writeUInt16LE(names.length, 10);
  eocd.writeUInt32LE(centralBuf.length, 12);
  eocd.writeUInt32LE(localBuf.length, 16);
  eocd.writeUInt16LE(0, 20);
  return Buffer.concat([localBuf, centralBuf, eocd]);
}

// ---- cli ----------------------------------------------------------------
function arg(flag, def) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

function main() {
  const name = arg('--name');
  const entryPath = arg('--entry');
  const guid = arg('--guid');
  const output = arg('--output');
  const displayName = arg('--display-name', name);
  const choicesPath = arg('--choices');
  if (!name || !guid || !output || (!entryPath && !choicesPath)) {
    console.error('usage: node build_addon.js --name mods/<a>/<m> (--entry x.lua | --choices choices.json) --guid <UUID> --display-name "N" --output out.zip');
    process.exit(2);
  }

  const title = displayName || name;
  checkDisplayName(title);
  const description =
    "Needs Bingus Shared Loader v15 or newer with addon support enabled. " +
    "Nothing else is required: 'API 1' is the loader's own Lua API level " +
    "(printed in BingusSharedLoader.log), not a separate mod.";

  let files, archiveLen = 0, manifest;

  if (choicesPath) {
    // ---- multi-choice / grid build (mod-manager Options + SubOptions) ----
    // Spec shapes accepted:
    //   flat   { Group, Description, Choices:[{Name,Description,Entry}] }
    //   grid   { Options:[{Name,Description,SubOptions:[{Name,Description,Entry}]}] }
    const spec = JSON.parse(fs.readFileSync(choicesPath, 'utf8'));

    // normalise to a list of groups, each with a list of leaves
    let groups;
    if (Array.isArray(spec.Options)) {
      groups = spec.Options.map(o => ({
        Name: o.Name,
        Description: o.Description || o.Name,
        Leaves: o.SubOptions || [],
      }));
    } else if (Array.isArray(spec.Choices)) {
      groups = [{
        Name: spec.Group || title,
        Description: spec.Description || description,
        Leaves: spec.Choices,
      }];
    } else {
      throw new Error('spec needs either "Options" or "Choices"');
    }
    const totalLeaves = groups.reduce((a, g) => a + g.Leaves.length, 0);
    if (totalLeaves === 0) throw new Error('spec has no leaves');

    files = {};
    let leafIndex = 0;
    const manifestOptions = groups.map(g => {
      const subOptions = g.Leaves.map(leaf => {
        // every leaf gets its own folder, named deterministically
        const dir = leaf.Include && leaf.Include[0]
          ? leaf.Include[0]
          : 'Choices/' + String(leafIndex).padStart(3, '0');
        leafIndex++;
        // a leaf may carry its own resource name (Name4). The loader appears to
        // load only ONE archive per resource name, so a grid where every leaf
        // shares one name collapses to a single load. Giving each leaf a unique
        // name avoids that.
        const leafName = leaf.Name4 || name;
        const body = entrySource(leafName, fs.readFileSync(leaf.Entry));
        // A leaf may also ship a SHARED engine under a STABLE name. Every
        // archive carries the same engine body under the same name, so the
        // loader's one-archive-per-resource-name rule collapses them into a
        // single load -- which is what we want. The leaf itself stays tiny and
        // contains no engine code.
        const resources = { [leafName]: envelope(body) };
        if (leaf.CoreName && leaf.CoreBody !== undefined) {
          resources[leaf.CoreName] = envelope(
            entrySource(leaf.CoreName, Buffer.from(leaf.CoreBody, 'utf8'))
          );
        }
        const ar = makeArchive(resources);
        archiveLen += ar.length;
        files[dir + '/' + ARCHIVE_NAME] = ar;
        files[dir + '/' + ARCHIVE_NAME + '.stream'] = Buffer.alloc(0);
        files[dir + '/' + ARCHIVE_NAME + '.gpu_resources'] = Buffer.alloc(0);
        return { Name: leaf.Name, Description: leaf.Description || leaf.Name, Include: [dir] };
      });
      return { Name: g.Name, Description: g.Description, SubOptions: subOptions };
    });

    manifest = {
      Version: 1,
      Guid: guid,
      Name: title,
      Description: description,
      Options: manifestOptions,
    };
  } else {
    // ---- single build ----
    const body = entrySource(name, fs.readFileSync(entryPath));
    const archive = makeArchive({ [name]: envelope(body) });
    archiveLen = archive.length;
    // A standalone mod still needs the Option -> SubOptions -> Include shape.
    // Every mod manager in this ecosystem (and every working addon) nests the
    // Include inside a SubOption; a bare Include on the Option is not
    // recognised, which is why the manager showed nothing for these builds.
    files = {
      ['Choices/00/' + ARCHIVE_NAME]: archive,
      ['Choices/00/' + ARCHIVE_NAME + '.stream']: Buffer.alloc(0),
      ['Choices/00/' + ARCHIVE_NAME + '.gpu_resources']: Buffer.alloc(0),
    };
    manifest = {
      Version: 1,
      Guid: guid,
      Name: title,
      Description: description,
      Options: [{
        Name: title,
        Description: description,
        SubOptions: [{ Name: title, Description: description, Include: ['Choices/00'] }],
      }],
    };
  }

  files['manifest.json'] = Buffer.from(JSON.stringify(manifest, null, 2) + '\n', 'utf8');

  const out = path.resolve(output);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, zipWrite(files));

  console.log('Built ' + out);
  console.log('  archive bytes: ' + archiveLen);
  console.log('  resource hash: 0x' + resourceHash(name).toString(16).toUpperCase().padStart(16, '0'));
  console.log('  manifest Name: ' + JSON.stringify(title));
  if (choicesPath) {
    const total = manifest.Options.reduce((a, o) => a + (o.SubOptions ? o.SubOptions.length : 0), 0);
    console.log('  option groups: ' + manifest.Options.length);
    console.log('  total sub-options: ' + total);
    if (manifest.Options.length <= 3) {
      for (const o of manifest.Options) {
        console.log('    [' + o.Name + ']');
        for (const s of (o.SubOptions || [])) console.log('       ' + s.Name + '  ->  ' + s.Include[0]);
      }
    } else {
      console.log('    first group: ' + manifest.Options[0].Name + '  (' + manifest.Options[0].SubOptions.length + ' choices)');
      console.log('    last  group: ' + manifest.Options[manifest.Options.length - 1].Name + '  (' + manifest.Options[manifest.Options.length - 1].SubOptions.length + ' choices)');
    }
  }
}

if (require.main === module) main();
module.exports = { resourceHash, makeArchive, makeArchiveRaw, envelope, entrySource, zipWrite, crc32, ARCHIVE_NAME, FAMILY, TYPE };
