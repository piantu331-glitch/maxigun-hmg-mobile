-- HD2-Addon: mods/dsh/maxigun_hmg_round
--
-- M-1000 Maxigun  ->  fires the E/MG-101 HMG Emplacement's projectile
--                  ->  AND can fire while moving
--
-- Build    : 25480438 / exe 1.8.46015.0
-- game.dll : 2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e
--
-- =========================================================================
-- TWO CHANGES, ONE MOD
-- =========================================================================
--
-- (1) PROJECTILE SWAP -- fires the emplacement round
--     The Maxigun's damage record is reached at *(game.dll + 58483896) and
--     reads DamageInfoType 127.
--     Every ProjectileSettings row carries at +84 the id of the damage record
--     it uses. Reading +84 for all rows in the family gave:
--         dmgid 126 -> 224      dmgid 128 -> 226
--         dmgid 127 -> 225      <== EXACTLY ONE ROW
--     ...so the Maxigun's projectile is row 225, identified by its damage link
--     rather than by its index or by its calibre/speed fingerprint.
--     Row 225 is rewritten to be byte-identical to the E/MG-101 row.
--
-- (2) FIRE WHILE MOVING
--     The Minigun's WeaponDataComponent holds a movement-lock flag as a single
--     byte at offset 387. The reference mod performs exactly this edit:
--         edits = {{ offset = 387, replacement = unhex("00") }}
--     The captured record has 0x01 there (locked); clearing it to 0x00 removes
--     the lock. The containing dword goes 0x01010001 -> 0x00010001.
--
-- =========================================================================
-- LOCATING THE WEAPON RECORD
-- =========================================================================
-- The weapon record is found by CONTENT, not by trust in an index:
--   * the reference mod published the full 1232-byte original_template_hex
--   * that template is embedded below
--   * the component table is reached via *(owner + (-13614272)), where
--     owner = *(game.dll + 54973760)
--   * the table is searched for a record equal to the template; a match both
--     locates the weapon AND proves the component is loaded
-- This retries for up to ~2 minutes because component tables populate late
-- (the reference mod itself sits at 'waiting_for_matching_component_table').
--
-- =========================================================================
-- SAFETY
-- =========================================================================
--   * verifies game.dll SHA-256 before ANY write
--   * both targets must match their captured bytes exactly before writing
--   * every individual write is read back and verified
--   * page protection restored in the same call
--   * refuses to write if a projectile damage-link match is ambiguous
--   * never trusts a fixed index for the weapon record

local M = {
    name = 'MaxigunHMGRound',
    version = '3.0.0',
    status = 'starting',
    disabled = false,
}
local NAME = M.name
local VERSION = M.version

local GAME_SHA = '2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e'
local OWNER_RVA = 54973760
local DAMAGEINFO_SLOT = 58483896
local WDC_SLOT = -13614272
local WDC_SIZE = 1232
local ROW_SIZE = 272
local TARGET_DMGID = 127          -- the Maxigun's DamageInfoType
local MOVE_LOCK_OFFSET = 387      -- single byte; 1 = cannot move while firing

local function unhex(s) return (s:gsub('..', function(x) return string.char(tonumber(x,16)) end)) end

-- ---------------------------------------------------------------------------
-- (2) the weapon component template (1232 bytes), published by the reference
--     mod and confirmed against a live read
-- ---------------------------------------------------------------------------
local WDC_TEMPLATE = unhex('0000a0410000a0410000b4420000b44200000000cdcccc3d0000803f000070410000f0410000b4420000b44200000000cdcccc3d0000803f0000003f0000' ..
  '803f0000803f0000803f0000803f0000803f0000803f0000204100002041000000000000803f0000803f0000803f9a99993f000000000000803f0000803f' ..
  '0000803f0000803f070000000000803f03000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000' ..
  '00000000000030eb953efde64a2d00000000bf0a525700000000000000000000000000000000000000000000000000000000000000000000000000000000' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' ..
  '0000000000009a99193f3333333f6666663f713d8abe6666e6be0000000000000000000000000000000000000000000080403333b33e000000000000c8c1' ..
  '0000a0400000000000000000010001013012fa457a84b0a10000000004000000000000000000000000000000000000000000000000000000000000000000' ..
  '000000000000000000000000000000000000739c7c525a68254d0000000001000000f8a98deba25efe285a68254dba830602e8f0bab10000000023b48a2c' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000' ..
  '0000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000' ..
  '0000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000' ..
  '0000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000' ..
  '0000000000000000000000000000000002000000000000000000803f0000803f0000803f000000000000803f0000803f0000803fd8cfeaf500000000556b' ..
  '63700000000000000000940a0000000000000000000000000000120000000000000012000000000000001200000000000000120000000000000012000000' ..
  '0000000012000000000000001200000000000000120000000000000000000000a0c7c3d5291e9a0855f346f280b6fbb20000000000000000000000000000' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000' ..
  '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f00000000')

-- ---------------------------------------------------------------------------
-- (1) the Maxigun's projectile row (index 225) and the fields that differ from
--     the E/MG-101 row
-- ---------------------------------------------------------------------------
local ORIGINAL_ROW = unhex('18953d39000000000000000000000000000000000000000032010000363d8e106c1a32766952cdf1f5c84b7d5898656a0000004101000000000066440000' ..
  '30419a99993e0000803f0100000000000000000000007f0000000000803e000000009c7b34f4ac78e462cbd59ebe71f73f3f0ad7233c0000000000000000' ..
  '0000000000000000000000000000000000000000000000000000000000000000000000000000a04201000000000000000000000000000000000000000000' ..
  '0000cdcccc3d0300000003000000010000000000a642000070420000403f000000400000404150af124d8790e63a0000000000000000000080bf00000000' ..
  '000000000000000001000000000000007d00000000000000')

local EDITS = {
    {offset=24,  bytes=unhex('53000000')},
    {offset=28,  bytes=unhex('f9c12819')},
    {offset=32,  bytes=unhex('a5b546c1')},
    {offset=48,  bytes=unhex('00004841')},
    {offset=56,  bytes=unhex('00005c44')},
    {offset=60,  bytes=unhex('00005042')},
    {offset=84,  bytes=unhex('cc000000')},
    {offset=96,  bytes=unhex('ee0ccc53')},
    {offset=100, bytes=unhex('36ff3405')},
    {offset=192, bytes=unhex('04000000')},
    {offset=196, bytes=unhex('04000000')},
    {offset=220, bytes=unhex('00002041')},
    {offset=224, bytes=unhex('79356d12')},
    {offset=256, bytes=unhex('02000000')},
}

local function build_patched_row()
    local b = ORIGINAL_ROW
    for _, e in ipairs(EDITS) do
        b = b:sub(1, e.offset) .. e.bytes .. b:sub(e.offset + #e.bytes + 1)
    end
    return b
end
local PATCHED_ROW = build_patched_row()

-- the weapon record with the movement lock cleared
local function build_patched_wdc()
    local b = WDC_TEMPLATE
    return b:sub(1, MOVE_LOCK_OFFSET) .. '\0' .. b:sub(MOVE_LOCK_OFFSET + 2)
end
local PATCHED_WDC = build_patched_wdc()

local S = { log={}, disabled=false, frames=0, tries=0, api=nil, owner=nil,
            phase='init', records={}, max_tries=1200, last_why=nil, ticks=0,
            proj_done=false, move_done=false }

local function base_dir() local l=os.getenv('LOCALAPPDATA') or '.' return l..'\\CowboyBingus\\Helldivers2\\Logs' end
local function write_file(n,c) local f=io.open(base_dir()..'\\'..n,'wb') if not f then return false end f:write(c) f:close() return true end
local function hexdump(s) if not s then return '' end return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function emit(m) S.log[#S.log+1]=os.date('!%Y-%m-%dT%H:%M:%SZ')..' '..m M.status=m M.disabled=S.disabled print('['..NAME..'] '..m) end
local function flush_log() if S.owner and S.owner.open_log then local f=S.owner.open_log(NAME..'.log') if f then f:write(table.concat(S.log,'\n')..'\n') f:close() end end end
local function write_status(v,d) write_file(NAME..'-STATUS.txt',table.concat({
  v,'','mod     : '..NAME..' v'..VERSION,'build   : 25480438 / exe 1.8.46015.0',
  'phase   : '..tostring(S.phase),'status  : '..tostring(S.status),
  'records : '..tostring(#S.records),'tries   : '..tostring(S.tries),
  'last why: '..tostring(S.last_why),
  'projectile swap : '..tostring(S.proj_done),
  'fire while move : '..tostring(S.move_done),
  'detail  : '..tostring(d or '')},'\n')..'\n') end

local function make_api()
  local ffi=require('ffi')
  if ffi.os~='Windows' or not ffi.abi('64bit') then return nil,'windows_x64_required' end
  ffi.cdef[[
    void *GetModuleHandleA(const char *);
    uint32_t GetModuleFileNameW(void *,uint16_t *,uint32_t);
    void *GetCurrentProcess(void);
    int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
    int WriteProcessMemory(void *,void *,const void *,size_t,size_t *);
    void *CreateFileW(const uint16_t *,uint32_t,uint32_t,void *,uint32_t,uint32_t,void *);
    int ReadFile(void *,void *,uint32_t,uint32_t *,void *);
    int CloseHandle(void *);
    int32_t BCryptOpenAlgorithmProvider(void **,const uint16_t *,const uint16_t *,uint32_t);
    int32_t BCryptCreateHash(void *,void **,void *,uint32_t,const void *,uint32_t,uint32_t);
    int32_t BCryptHashData(void *,const void *,uint32_t,uint32_t);
    int32_t BCryptFinishHash(void *,uint8_t *,uint32_t,uint32_t);
    int32_t BCryptDestroyHash(void *);
    int32_t BCryptCloseAlgorithmProvider(void *,uint32_t);
    typedef struct {
      void *BaseAddress; void *AllocationBase; uint32_t AllocationProtect;
      uint16_t PartitionId; uint16_t Padding; size_t RegionSize;
      uint32_t State; uint32_t Protect; uint32_t Type;
    } MHR_MBI;
    size_t VirtualQuery(const void *,void *,size_t);
    int VirtualProtect(void *,size_t,uint32_t,uint32_t *);
  ]]
  local k=ffi.load('kernel32'); local b=ffi.load('bcrypt'); local process=k.GetCurrentProcess()
  local api={}
  function api.module(n) local p=k.GetModuleHandleA(n) if p~=nil then return tonumber(ffi.cast('uintptr_t',p)) end end
  function api.read(a,sz)
    if type(a)~='number' or a<65536 or a+sz>=0x800000000000 or sz<=0 or sz>8192 then return nil end
    local out=ffi.new('uint8_t[?]',sz); local got=ffi.new('size_t[1]')
    if k.ReadProcessMemory(process,ffi.cast('const void *',a),out,sz,got)==0 or tonumber(got[0])~=sz then return nil end
    return ffi.string(out,sz)
  end
  function api.pointer(s) if not s or #s<8 then return nil end
    local v=0 for i=8,1,-1 do v=v*256+s:byte(i) end
    if v>=65536 and v<0x800000000000 then return v end return nil end
  function api.write(address,bytes)
    local n=#bytes
    if n<1 or n>16 then return false,'bad_size' end
    if type(address)~='number' or address<65536 then return false,'bad_addr' end
    local at=ffi.cast('void *',address)
    local mbi=ffi.new('MHR_MBI[1]'); local old=ffi.new('uint32_t[1]'); local unused=ffi.new('uint32_t[1]')
    if tonumber(k.VirtualQuery(at,mbi,ffi.sizeof(mbi[0])))~=ffi.sizeof(mbi[0]) then return false,'vq' end
    local protect=tonumber(mbi[0].Protect)
    if tonumber(mbi[0].State)~=0x1000 then return false,'not_commit' end
    if protect~=0x02 and protect~=0x04 and protect~=0x20 and protect~=0x40 then return false,'protect' end
    local before=api.read(address,n); if not before then return false,'pre_read' end
    local changed=false
    if protect==0x02 or protect==0x20 then
      if k.VirtualProtect(at,n,(protect==0x02) and 0x04 or 0x40,old)==0 then return false,'vp' end
      changed=true
    end
    local ok,wok,count,readback=pcall(function()
      if api.read(address,n)~=before then return false,0,false end
      local wrote=ffi.new('size_t[1]')
      local r=k.WriteProcessMemory(process,at,bytes,n,wrote)~=0
      return r,tonumber(wrote[0]),api.read(address,n)==bytes
    end)
    local restored=true
    if changed then restored=(k.VirtualProtect(at,n,old[0],unused)~=0) end
    if not ok or not wok or count~=n or not readback or not restored then return false,'write' end
    return true
  end
  function api.module_hash(addr)
    local path=ffi.new('uint16_t[32768]')
    local n=k.GetModuleFileNameW(ffi.cast('void *',addr),path,32768)
    if n==0 or n>=32768 then return nil end
    local f=k.CreateFileW(path,0x80000000,7,nil,3,0x08000000,nil)
    if f==ffi.cast('void *',-1) then return nil end
    local alg,hash=ffi.new('void *[1]'),ffi.new('void *[1]')
    local ok,res=pcall(function()
      local nm=ffi.new('uint16_t[7]',{83,72,65,50,53,54,0})
      assert(b.BCryptOpenAlgorithmProvider(alg,nm,nil,0)==0)
      assert(b.BCryptCreateHash(alg[0],hash,nil,0,nil,0,0)==0)
      local chunk=ffi.new('uint8_t[65536]'); local got=ffi.new('uint32_t[1]')
      while true do assert(k.ReadFile(f,chunk,65536,got,nil)~=0)
        if got[0]==0 then break end
        assert(b.BCryptHashData(hash[0],chunk,got[0],0)==0) end
      local d=ffi.new('uint8_t[32]'); assert(b.BCryptFinishHash(hash[0],d,32,0)==0)
      local p={} for i=0,31 do p[#p+1]=string.format('%02x',d[i]) end
      return table.concat(p) end)
    if hash[0]~=nil then b.BCryptDestroyHash(hash[0]) end
    if alg[0]~=nil then b.BCryptCloseAlgorithmProvider(alg[0],0) end
    k.CloseHandle(f)
    if not ok then return nil end return res
  end
  return api
end

local function u32(s,at)
  if type(s)~='string' or #s<at+4 then return nil end
  local a,b,c,d=s:byte(at+1,at+4) return a+b*256+c*65536+d*16777216
end
local function djb2(s) local h=5381 for i=1,#s do h=(h*33+s:byte(i))%4294967296 end return (h-5381)%4294967296 end
local function le32(v) return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256) end
local TYPE_SIG = 'LDLD'..le32(1)..le32(djb2('ProjectileSettings'))

-- ---------------------------------------------------------------- projectile
local function find_proj_table(anchor)
  local from=anchor-16*1024*1024
  local span=32*1024*1024
  local off,carry,cb=0,'',from
  while off<span do
    local n=math.min(8192,span-off)
    local raw=S.api.read(from+off,n)
    if raw then
      local hay=carry..raw; local cur=1
      while true do
        local at=hay:find(TYPE_SIG,cur,true)
        if not at then break end
        local addr=cb+(at-1); cur=at+1
        local hdr=S.api.read(addr,40)
        if hdr then
          local bs,cnt=u32(hdr,12),u32(hdr,32)
          if bs and cnt and cnt>0 and bs==cnt*ROW_SIZE+16 then return addr+16,cnt end
        end
      end
      carry=hay:sub(-11); cb=from+off+#raw-11
    else carry='' cb=from+off+n end
    off=off+n
  end
  return nil,nil
end

local function do_projectile()
  local api=S.api
  local game=api.module('game.dll')
  local anchor=api.pointer(api.read(game+DAMAGEINFO_SLOT,8))
  if not anchor then return false,'anchor_unreadable' end
  local array,count=find_proj_table(anchor)
  if not array then return false,'projectile_table_not_found' end

  local hit=nil
  local hits=0
  for i=0,count-1 do
    local addr=array+i*ROW_SIZE
    local row=api.read(addr,ROW_SIZE)
    if row and u32(row,84)==TARGET_DMGID then
      hits=hits+1
      if not hit then hit={addr=addr,idx=i} end
      if hits>1 then break end
    end
  end
  if hits==0 then return false,'damage_link_not_found' end
  if hits>1 then return false,'damage_link_ambiguous' end

  local rec=hit.addr
  if api.read(rec,ROW_SIZE) ~= ORIGINAL_ROW then
    emit('projectile: row no longer matches the captured template')
    return false,'row_mismatch'
  end
  for _,e in ipairs(EDITS) do
    local ok,err=api.write(rec+e.offset, e.bytes)
    if not ok then
      emit(string.format('projectile: write failed at +%d: %s', e.offset, tostring(err)))
      return false,'write_failed'
    end
  end
  if api.read(rec,ROW_SIZE) ~= PATCHED_ROW then
    emit('projectile: readback mismatch')
    return false,'readback_mismatch'
  end
  write_file(NAME..'-row-after.hex', hexdump(api.read(rec,ROW_SIZE)))
  S.records[#S.records+1]={addr=rec,patched=PATCHED_ROW}
  emit(string.format('projectile swapped: row=0x%x index=%d (damage link %d)',rec,hit.idx,TARGET_DMGID))
  S.proj_done=true
  return true
end

-- ------------------------------------------------------------------ movement
local function do_movement()
  local api=S.api
  local game=api.module('game.dll')
  local owner=api.pointer(api.read(game+OWNER_RVA,8))
  if not owner then return false,'owner_unreadable' end

  -- reach the component table, then find the weapon record by CONTENT
  local hm=api.pointer(api.read(owner+WDC_SLOT,8))
  if not hm then return false,'component_table_unavailable' end
  if hm < 0x10000000000 or hm > 0x7f0000000000 then return false,'component_table_implausible' end

  local from=hm-8*1024*1024
  local span=16*1024*1024
  local off,carry,cb=0,'',from
  local found=nil
  while off<span and not found do
    local n=math.min(8192,span-off)
    local raw=api.read(from+off,n)
    if raw then
      local hay=carry..raw; local cur=1
      while true do
        local at=hay:find(WDC_TEMPLATE,cur,true)
        if not at then break end
        found=cb+(at-1); cur=at+1; break
      end
      carry=hay:sub(-(#WDC_TEMPLATE-1)); cb=from+off+#raw-(#WDC_TEMPLATE-1)
    else carry='' cb=from+off+n end
    off=off+n
  end
  if not found then return false,'weapon_record_not_found' end

  -- clear the movement lock: one byte
  local before=api.read(found+MOVE_LOCK_OFFSET,1)
  if before=='\0' then
    emit('movement lock already clear')
    S.move_done=true
    return true
  end
  local ok,err=api.write(found+MOVE_LOCK_OFFSET, '\0')
  if not ok then
    emit('movement: write failed: '..tostring(err))
    return false,'write_failed'
  end
  if api.read(found, WDC_SIZE) ~= PATCHED_WDC then
    emit('movement: readback mismatch')
    return false,'readback_mismatch'
  end
  S.records[#S.records+1]={addr=found,patched=PATCHED_WDC}
  emit(string.format('fire-while-moving enabled: record=0x%x byte +%d cleared',found,MOVE_LOCK_OFFSET))
  S.move_done=true
  return true
end

local function recheck()
  local alive=0
  for _,r in ipairs(S.records) do
    local n=#r.patched
    if S.api.read(r.addr,n)==r.patched then alive=alive+1 end
  end
  return alive
end

local function startup()
  local loader=rawget(_G,'CowboyBingusModLoader')
  local apiv=type(loader)=='table' and tonumber(loader.api) or nil
  if not apiv or apiv<1 then
    S.phase='error'; S.status='loader_api_too_old'; S.disabled=true
    emit('need Bingus Shared Loader v15+/API 1'); write_status('FAILED - loader too old',''); return false
  end
  local api,err=make_api()
  if not api then
    S.phase='error'; S.status='ffi_unavailable'; S.disabled=true
    emit(S.status..': '..tostring(err)); write_status('FAILED - FFI',''); return false
  end
  S.api=api
  local game=api.module('game.dll')
  if not game then
    S.phase='error'; S.status='game_dll_missing'; S.disabled=true; emit(S.status); write_status('FAILED',''); return false
  end
  local h=api.module_hash(game)
  if h~=GAME_SHA then
    S.phase='error'; S.status='game_dll_hash_mismatch'; S.disabled=true
    emit('hash mismatch: '..tostring(h)); write_status('FAILED - wrong version', tostring(h)); return false
  end
  emit('game_dll_hash_verified')
  S.phase='working'; S.status='waiting'
  write_status('WORKING','')
  return true
end

local function tick()
  if S.disabled then return end
  S.frames=S.frames+1

  -- if both are done, only re-check periodically
  if S.proj_done and S.move_done then
    if S.frames%120~=0 then return end
    if recheck() < #S.records then
      emit('recheck: a patch was overwritten; re-applying')
      S.records={}
      S.proj_done=false
      S.move_done=false
    end
    return
  end

  if S.frames%30~=0 then return end
  S.ticks=S.ticks+1

  if not S.proj_done then
    local ok,why=do_projectile()
    S.last_why=why
    if not ok and S.ticks%60==0 then
      emit(string.format('projectile pending (%d): %s', S.ticks, tostring(why)))
    end
  end

  if S.proj_done and not S.move_done then
    local ok,why=do_movement()
    S.last_why=why
    if not ok and S.ticks%60==0 then
      emit(string.format('movement pending (%d): %s', S.ticks, tostring(why)))
    end
  end

  if S.proj_done and S.move_done then
    S.status='applied_gameplay_unverified'
    emit('both changes applied')
    write_status('OK - projectile swapped + fire while moving',
      'row 225 -> emplacement round; weapon byte +387 cleared')
    return
  end

  if S.ticks>=S.max_tries then
    S.disabled=true
    S.status='gave_up'
    emit('gave up')
    write_status('FAILED - one or both changes not applied', tostring(S.last_why))
  end
end

local loader=rawget(_G,'CowboyBingusModLoader')
if rawget(_G,'MaxigunHMGRound') then return rawget(_G,'MaxigunHMGRound') end
rawset(_G,'MaxigunHMGRound',M)
S.owner=loader
S.disabled=not startup()

if not S.disabled then
  local previous_update=rawget(_G,'update')
  local my_update
  my_update=function(dt,...)
    if not S.disabled then
      local ok,err=pcall(tick)
      if not ok then
        S.disabled=true; S.status='runtime_error: '..tostring(err)
        pcall(emit,S.status); pcall(write_status,'FAILED - runtime error',tostring(err))
      end
    end
    if type(previous_update)=='function' then return previous_update(dt,...) end
  end
  M.my_update=my_update
  M.previous_update=previous_update
  rawset(_G,'update',my_update)
  local previous_shutdown=rawget(_G,'shutdown')
  rawset(_G,'shutdown',function(...)
    if rawget(_G,'update')==my_update and type(previous_update)=='function' then
      rawset(_G,'update',previous_update)
    end
    pcall(flush_log)
    if type(previous_shutdown)=='function' then return previous_shutdown(...) end
  end)
end

pcall(flush_log)
return M
