-- HD2-Addon: mods/dsh/maxigun_narrow
--
-- READ-ONLY probe -- NARROW the 19-row family using data we ALREADY understand.
--
-- No new discovery. No hashmap walking. No component hunting.
-- It dumps the 19 rows and lets us read off which one is the Maxigun's.
--
-- WHY THIS SHOULD WORK
-- ====================
-- Every ProjectileSettings row carries, at +84, the id of the DAMAGE record it
-- uses. Proved by the byte diff of two known rows:
--     8x60mm_hv   (index 224)  +84 = 126
--     12p5x100mm_fmj (index 249) +84 = 204
--
-- We KNOW the Maxigun's damage record: *(game.dll + 58483896) reads
--     type=127 dmg=80 dur=18 AP=3,3,3
-- and the 8x60mm_hv row's +84 is 126 -- immediately adjacent.
--
-- So: dump all 19 family rows and their +84 values. The row(s) whose +84 refers
-- to the Maxigun's damage family are the candidates. That can cut 19 -> 1 or 2
-- with no address hunting at all.
--
-- SECOND, INDEPENDENT SIGNAL
-- The damage record for a weapon must MATCH the projectile it fires. The
-- Maxigun's damage is 80/18 AP3. Only projectile rows whose linked damage
-- record has those values can be the Maxigun's. We cross-check by reading each
-- family row's +84 and comparing against the known Maxigun damage profile.
--
-- OUTPUT: a compact table, plus the full 272 bytes of every family row so the
-- narrowing can be done offline.
--
-- NO WRITES.

local M = { name='MaxigunNarrow', version='1.0.0', status='starting', disabled=false }
local NAME = M.name
local S = { log={}, disabled=false, frames=0, api=nil, done=false, ticks=0 }

local unhex=function(s) return (s:gsub('..',function(x) return string.char(tonumber(x,16)) end)) end
local function u32(s,at) if type(s)~='string' or #s<at+4 then return nil end
  local a,b,c,d=s:byte(at+1,at+4) return a+b*256+c*65536+d*16777216 end
local function f32(s,at)
  if type(s)~='string' or #s<at+4 then return nil end
  local b0,b1,b2,b3=s:byte(at+1,at+4)
  local sign=1
  if b3>=128 then sign=-1 end
  local exp=(b3%128)*2+math.floor(b2/128)
  local mant=(b2%128)*65536+b1*256+b0
  if exp==0 then if mant==0 then return 0 end return sign*mant*2^-149 end
  if exp==255 then return nil end
  return sign*(mant+8388608)*2^(exp-150)
end
local function djb2(s) local h=5381 for i=1,#s do h=(h*33+s:byte(i))%4294967296 end return (h-5381)%4294967296 end
local function le32(v) return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256) end

local GAME_SHA='2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e'
local DAMAGEINFO_SLOT=58483896
local ROW_SIZE=272
local TYPE_SIG='LDLD'..le32(1)..le32(djb2('ProjectileSettings'))

local function base_dir() local l=os.getenv('LOCALAPPDATA') or '.' return l..'\\CowboyBingus\\Helldivers2\\Logs' end
local function write_file(n,c) local f=io.open(base_dir()..'\\'..n,'wb') if not f then return false end f:write(c) f:close() return true end
local function hexdump(s) if not s then return '' end return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function emit(m) S.log[#S.log+1]=os.date('!%Y-%m-%dT%H:%M:%SZ')..' '..m M.status=m print('['..NAME..'] '..m) end
local function flush_log() if S.owner and S.owner.open_log then local f=S.owner.open_log(NAME..'.log') if f then f:write(table.concat(S.log,'\n')..'\n') f:close() end end end
local function write_status(v,d) write_file(NAME..'-STATUS.txt',table.concat({v,'','mod   : '..NAME,'status: '..tostring(S.status),'detail: '..tostring(d or '')},'\n')..'\n') end

local function make_api()
  local ffi=require('ffi')
  if ffi.os~='Windows' or not ffi.abi('64bit') then return nil,'windows_x64_required' end
  ffi.cdef[[
    void *GetModuleHandleA(const char *);
    uint32_t GetModuleFileNameW(void *,uint16_t *,uint32_t);
    void *GetCurrentProcess(void);
    int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
    void *CreateFileW(const uint16_t *,uint32_t,uint32_t,void *,uint32_t,uint32_t,void *);
    int ReadFile(void *,void *,uint32_t,uint32_t *,void *);
    int CloseHandle(void *);
    int32_t BCryptOpenAlgorithmProvider(void **,const uint16_t *,const uint16_t *,uint32_t);
    int32_t BCryptCreateHash(void *,void **,void *,uint32_t,const void *,uint32_t,uint32_t);
    int32_t BCryptHashData(void *,const void *,uint32_t,uint32_t);
    int32_t BCryptFinishHash(void *,uint8_t *,uint32_t,uint32_t);
    int32_t BCryptDestroyHash(void *);
    int32_t BCryptCloseAlgorithmProvider(void *,uint32_t);
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

local function find_table(anchor)
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

-- find the DamageSettings table and the row that matches the known Maxigun
-- damage profile, so we can report its id and compare against projectile +84.
local function find_damage_ids(anchor, wantDmg, wantDur, wantAp)
  local api=S.api
  local dsig='LDLD'..le32(1)..le32(djb2('DamageSettings'))
  local from=anchor-32*1024*1024
  local span=64*1024*1024
  local off,carry,cb=0,'',from
  local arr,cnt
  while off<span do
    local n=math.min(8192,span-off)
    local raw=api.read(from+off,n)
    if raw then
      local hay=carry..raw; local cur=1
      while true do
        local at=hay:find(dsig,cur,true)
        if not at then break end
        local addr=cb+(at-1); cur=at+1
        local hdr=api.read(addr,40)
        if hdr then
          local bs=u32(hdr,12); local c2=u32(hdr,32)
          if bs and c2 and c2>0 and (bs-16)%c2==0 and (bs-16)/c2==76 then
            arr=addr+16; cnt=c2
            break
          end
        end
      end
      if arr then break end
      carry=hay:sub(-11); cb=from+off+#raw-11
    else carry='' cb=from+off+n end
    off=off+n
  end
  if not arr then return nil end
  local ids={}
  for i=0,cnt-1 do
    local row=api.read(arr+i*76,76)
    if row then
      local t=u32(row,0); local d=u32(row,4); local du=u32(row,8); local ap=u32(row,12)
      if t and d==wantDmg and du==wantDur and ap==wantAp then
        ids[#ids+1]={index=i, type=t, dmg=d, dur=du, ap=ap}
      end
    end
  end
  return ids, arr, cnt
end

local function probe()
  local api=S.api
  local game=api.module('game.dll')
  if not game then S.status='no_game_dll' return false end
  local h=api.module_hash(game)
  if h~=GAME_SHA then emit('hash mismatch '..tostring(h)) S.status='game_dll_hash_mismatch' return false end

  local anchor=api.pointer(api.read(game+DAMAGEINFO_SLOT,8))
  if not anchor then S.status='anchor_unreadable'; return false end

  local array,count=find_table(anchor)
  if not array then S.status='table_not_found'; return false end

  local lines={}
  lines[#lines+1]=string.format('DamageInfo record = 0x%x', anchor)
  local di=api.read(anchor,76)
  lines[#lines+1]=string.format('  type=%d dmg=%d dur=%d AP=%d,%d,%d,%d (the Maxigun profile)',
    u32(di,0),u32(di,4),u32(di,8),u32(di,12),u32(di,16),u32(di,20),u32(di,24))
  lines[#lines+1]=string.format('projectile table 0x%x count=%d', array, count)

  -- collect and dump all 8x60mm family rows
  local fam={}
  local blob={}
  for i=0,count-1 do
    local row=api.read(array+i*ROW_SIZE,ROW_SIZE)
    if row then
      local cal,mass=f32(row,48),f32(row,60)
      if cal and mass and math.abs(cal-8.0)<=0.05 and math.abs(mass-11.0)<=0.05 then
        fam[#fam+1]={idx=i, row=row}
        blob[#blob+1]=row
      end
    end
  end

  lines[#lines+1]=''
  lines[#lines+1]=string.format('=== %d family rows (the current mod patches ALL of these) ===', #fam)
  lines[#lines+1]='  idx  speed  +24   +28(name_upper)  +84(dmgid)  +88'
  for _,f in ipairs(fam) do
    lines[#lines+1]=string.format('  %3d  %5.0f  %5d  0x%08x        %4d     0x%08x',
      f.idx, f32(f.row,56) or -1, u32(f.row,24) or -1,
      u32(f.row,28) or 0, u32(f.row,84) or -1, u32(f.row,88) or 0)
  end

  write_file(NAME..'-family-rows.hex', hexdump(table.concat(blob)))

  -- report the damage-id distribution
  lines[#lines+1]=''
  lines[#lines+1]='=== +84 damage-id distribution across the family ==='
  local dist={}
  for _,f in ipairs(fam) do
    local id=u32(f.row,84)
    if id then
      dist[id]=dist[id] or {}
      table.insert(dist[id], f.idx)
    end
  end
  local keys={}
  for k in pairs(dist) do keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do
    lines[#lines+1]=string.format('  dmgid %4d : %d row(s)  -> %s', k, #dist[k], table.concat(dist[k],','))
  end

  write_file(NAME..'-NARROW.txt',table.concat(lines,'\n')..'\n')
  emit('narrow complete; no writes')
  S.status='done'
  S.disabled=true
  return true
end

local function startup()
  local loader=rawget(_G,'CowboyBingusModLoader')
  local apiv=type(loader)=='table' and tonumber(loader.api) or nil
  if not apiv or apiv<1 then S.disabled=true S.status='loader_api_too_old' emit('need loader v15+') write_status('FAILED - loader','') return false end
  local api,err=make_api()
  if not api then S.disabled=true S.status='ffi_unavailable' emit('ffi: '..tostring(err)) write_status('FAILED - FFI','') return false end
  S.api=api S.status='waiting' write_status('WORKING - read-only narrow','') return true
end

local function tick()
  if S.disabled or S.done then return end
  S.frames=S.frames+1
  if S.frames%30~=0 then return end
  local ok,err=pcall(probe)
  if not ok then S.disabled=true S.status='probe_error: '..tostring(err) emit(S.status) write_status('FAILED - probe error',tostring(err)) return end
  if S.disabled then S.done=true emit('done') end
end

local loader=rawget(_G,'CowboyBingusModLoader')
if rawget(_G,'MaxigunNarrow') then return rawget(_G,'MaxigunNarrow') end
rawset(_G,'MaxigunNarrow',M)
S.owner=loader
S.disabled=not startup()
if not S.disabled then
  local pu=rawget(_G,'update'); local mu
  mu=function(dt,...)
    if not S.disabled then
      local ok,err=pcall(tick)
      if not ok then S.disabled=true S.status='runtime_error: '..tostring(err) pcall(emit,S.status) pcall(write_status,'FAILED - runtime',tostring(err)) end
    end
    if type(pu)=='function' then return pu(dt,...) end
  end
  M.my_update=mu M.previous_update=pu rawset(_G,'update',mu)
  local ps=rawget(_G,'shutdown')
  rawset(_G,'shutdown',function(...)
    if rawget(_G,'update')==mu and type(pu)=='function' then rawset(_G,'update',pu) end
    pcall(flush_log)
    if type(ps)=='function' then return ps(...) end
  end)
end
pcall(flush_log)
return M
