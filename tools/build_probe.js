const B=require(require('path').join(__dirname,'build_addon.js'));
const fs=require('fs');
const CORE = `-- core probe
rawset(_G,'PROBE_CORE_HITS',(rawget(_G,'PROBE_CORE_HITS') or 0)+1)
return 'core'
`;
const LEAF = `-- leaf probe
rawset(_G,'PROBE_LEAF_HITS',(rawget(_G,'PROBE_LEAF_HITS') or 0)+1)
return 'leaf'
`;
const archive = B.makeArchive({
  'mods/dsh/probecore':  B.envelope(B.entrySource('mods/dsh/probecore',  Buffer.from(CORE))),
  'mods/dsh/probeleafa': B.envelope(B.entrySource('mods/dsh/probeleafa', Buffer.from(LEAF))),
});
const zip = B.zipWrite({
  'manifest.json': Buffer.from(JSON.stringify({
      Name: 'Probe Multi-Name', GUID: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      Options: [{ Name: 'Pick', Description: 'probe', SubOptions: [
        { Name: 'A', Description: 'a', Include: ['Choices/a'] },
      ]}],
    }), 'utf8'),
  'Choices/a/9ba626afa44a3aa3.patch_0': archive,
});
fs.writeFileSync('./build/probe-multiname.zip', zip);
console.log('built:', zip.length, 'bytes');