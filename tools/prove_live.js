const fs=require('fs');
const t=fs.readFileSync(require('path').join(__dirname,'..','src','maxigun-hmg-round.lua'),'utf8');
// pull ORIGINAL_ROW and EDITS from the source
const s0=t.indexOf('local ORIGINAL_ROW = unhex(');
const s1=t.indexOf('\n\n', s0);
const rowLit=t.slice(s0,s1);
const origHex=[...rowLit.matchAll(/'([0-9a-fA-F]+)'/g)].map(m=>m[1]).join('');
const orig=Buffer.from(origHex,'hex');
const b0=t.indexOf('local EDITS = {');
const b1=t.indexOf('\n}', b0);
const edits=[...t.slice(b0,b1).matchAll(/offset=(\d+),\s*bytes=unhex\('([0-9a-fA-F]*)'\)/g)].map(m=>({o:+m[1],b:m[2]}));
// build the intended patched row
const want=Buffer.from(orig);
for(const e of edits) Buffer.from(e.b,'hex').copy(want,e.o);
// the live row the game reported after the write
const logs='C:/Users/Piantu/AppData/Local/CowboyBingus/Helldivers2/Logs/';
const live=Buffer.from(fs.readFileSync(logs+'MaxigunHMGRound-row-after.hex','utf8').trim(),'hex');
const before=Buffer.from(fs.readFileSync(logs+'MaxigunHMGRound-row-before.hex','utf8').trim(),'hex');
console.log('  intended patched row == live row :', want.equals(live));
console.log('  live row matched the template    :', before.equals(orig));
console.log('  row sizes                        :', orig.length, want.length, live.length, before.length);
if(!want.equals(live)){
  const d=[];for(let i=0;i<272;i++) if(want[i]!==live[i]) d.push(i);
  console.log('  differing positions:', d.join(', '));
}