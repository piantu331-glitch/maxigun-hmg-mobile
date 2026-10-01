-- HD2-Addon: mods/dsh/maxigun_probe_ro
--
-- =========================================================================
-- READ-ONLY probe for the Maxigun projectile row
-- =========================================================================
-- GOAL
--   The projectile mod matches the whole 272-byte row against a captured
--   template and refuses to write unless it is byte-identical. If the game
--   mutates ANY of the 216 bytes we do not touch, that guard fails forever.
--
--   Before changing the guard I need to KNOW which bytes actually change at
--   runtime. This probe answers that, and it WRITES NOTHING.
--
-- WHAT IT DOES
--   1. locates the projectile table the same way the mod does
--   2. finds the Maxigun row by its damage link (+84 == 127)
--   3. records the row once, then RE-READS it on a slow timer
--   4. reports every byte position that ever differed, with the before/after
--      values and how many times each position changed
--   5. also reports whether the damage link (+84) stays at 127, and whether
--      the row ADDRESS itself moves (the table may be rebuilt)
--
-- SAFETY
--   * NOTHING is written -- no WriteProcessMemory anywhere in this file
--   * reads are confined to the already-located row (272 bytes)
--   * game.dll SHA-256 verified once, then cached
--
-- OUTPUT
--   MaxigunProbeRO-STATUS.txt    summary
--   MaxigunProbeRO-changes.txt   every differing byte, with counts
--   MaxigunProbeRO-row.hex       the first capture
-- =========================================================================

local M = { name = 'MaxigunProbeRO', version = '1.0.0', status = 'starting', disabled = false }
local NAME = M.name

local GAME_SHA = '2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e'
local OWNER_RVA = 54973760
local DAMAGEINFO_SLOT = 58483896
local ROW_SIZE = 272
local TARGET_DMGID = 127

local S = { log = {}, disabled = false, frames = 0, ticks = 0, api = nil, owner = nil,
            phase = 'locate', max_tries = 600, last_why = nil,
            baseline = nil, base_addr = nil, changes = {}, samples = 0 }

local function u32(s, at)
    if type(s) ~= 'string' or #s < at + 4 then return nil end
    local a, b, c, d = s:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function hexdump(s) if not s then return '' end return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
local function base_dir() local l = os.getenv('LOCALAPPDATA') or '.' return l .. '\\CowboyBingus\\Helldivers2\\Logs' end
local function write_file(n, c) local f = io.open(base_dir() .. '\\' .. n, 'wb') if not f then return false end f:write(c) f:close() return true end
local function emit(m) S.log[#S.log + 1] = os.date('!%Y-%m-%dT%H:%M:%SZ') .. ' ' .. m M.status = m print('[' .. NAME .. '] ' .. m) end
local function flush_log() if S.owner and S.owner.open_log then local f = S.owner.open_log(NAME .. '.log') if f then f:write(table.concat(S.log, '\n') .. '\n') f:close() end end end
local function write_status(v, d)
    write_file(NAME .. '-STATUS.txt', table.concat({
        v, '', 'mod      : ' .. NAME .. ' v' .. M.version,
        'phase    : ' .. tostring(S.phase), 'status   : ' .. tostring(S.status),
        'samples  : ' .. S.samples .. ' re-read(s) of the projectile row',
        'changed  : ' .. (function() local n = 0 for _ in pairs(S.changes) do n = n + 1 end return n end)() .. ' byte position(s) ever differed',
        'last why : ' .. tostring(S.last_why),
        'detail   : ' .. tostring(d or ''),
        '', 'NOTHING WAS WRITTEN -- this probe is read-only.',
    }, '\n') .. '\n')
end
local function write_changes()
    local rows = {}
    for pos, rec in pairs(S.changes) do rows[#rows + 1] = { pos = pos, rec = rec } end
    table.sort(rows, function(a, b) return a.pos < b.pos end)
    local out = {}
    out[#out + 1] = 'byte position(s) that differed from the first capture'
    out[#out + 1] = 'samples: ' .. S.samples
    out[#out + 1] = ''
    out[#out + 1] = string.format('%-6s %-8s %-8s %-6s %s', 'offset', 'first', 'last', 'count', 'note')
    for _, r in ipairs(rows) do
        local note = ''
        if r.pos == 84 or r.pos == 85 or r.pos == 86 or r.pos == 87 then note = '<-- DAMAGE LINK (we edit this)' end
        if r.pos >= 24 and r.pos <= 35 then note = note .. ' edited span +24..+35' end
        if r.pos >= 48 and r.pos <= 63 then note = note .. ' edited span +48..+63' end
        if r.pos >= 192 and r.pos <= 199 then note = note .. ' edited span +192..+199' end
        if r.pos >= 220 and r.pos <= 227 then note = note .. ' edited span +220..+227' end
        if r.pos >= 256 and r.pos <= 259 then note = note .. ' edited span +256..+259' end
        if r.pos >= 96 and r.pos <= 103 then note = note .. ' edited span +96..+103' end
        out[#out + 1] = string.format('+%-5d %-8s %-8s %-6d %s', r.pos, r.rec.first, r.rec.last, r.rec.count, note)
    end
    if #rows == 0 then out[#out + 1] = '(none -- the row never changed during the sampling window)' end
    out[#out + 1] = ''
    out[#out + 1] = 'INTERPRETATION'
    out[#out + 1] = '  positions listed here are what a full-row compare would trip on.'
    out[#out + 1] = '  if they are all inside our edited spans, the strict compare is fine.'
    out[#out + 1] = '  if any are OUTSIDE them, the guard should compare only the edited'
    out[#out + 1] = '  bytes plus a few identity bytes.'
    write_file(NAME .. '-changes.txt', table.concat(out, '\n') .. '\n')
end

-- ------------------------------------------------------------------ API
local function make_api()
    local ffi = require('ffi')
    if ffi.os ~= 'Windows' or not ffi.abi('64bit') then return nil, 'windows_x64_required' end
    ffi.cdef[[
        void *GetModuleHandleA(const char *);
        uint32_t GetModuleFileNameW(void *,uint16_t *,uint32_t);
        void *GetCurrentProcess(void);
        int ReadProcessMemory(void *,const void *,void *,size_t,size_t *);
        size_t VirtualQuery(const void *,void *,size_t);
        uint32_t GetLastError(void);
        void *CreateFileW(const uint16_t *,uint32_t,uint32_t,void *,uint32_t,uint32_t,void *);
        int ReadFile(void *,void *,uint32_t,uint32_t *,void *);
        int CloseHandle(void *);
        int32_t BCryptOpenAlgorithmProvider(void **,const uint16_t *,const uint16_t *,uint32_t);
        int32_t BCryptCreateHash(void *,void **,void *,uint32_t,const uint8_t *,uint32_t,uint32_t);
        int32_t BCryptHashData(void *,const void *,uint32_t,uint32_t);
        int32_t BCryptFinishHash(void *,uint8_t *,uint32_t,uint32_t);
        int32_t BCryptDestroyHash(void *);
        int32_t BCryptCloseAlgorithmProvider(void *,uint32_t);
        typedef struct { void *base; void *allocation; uint32_t protection0;
            uint16_t partition; uint16_t reserved; size_t size;
            uint32_t state; uint32_t protection; uint32_t kind; } RO_REGION;
    ]]
    local k = ffi.load('kernel32')
    local b = ffi.load('bcrypt')
    local process = k.GetCurrentProcess()
    local api = {}
    local buf = ffi.new('uint8_t[262144]')
    local cnt = ffi.new('size_t[1]')
    local bufaddr = tonumber(ffi.cast('uintptr_t', buf))
    local function excluded(a, sz) return a < bufaddr + 262144 and a + sz > bufaddr end

    function api.module(n)
        local p = k.GetModuleHandleA(n)
        if p == nil then return nil end
        local v = tonumber(ffi.cast('uintptr_t', p))
        if v and v ~= 0 then return v end
    end
    function api.query(address)
        if address >= 0x800000000000 then return nil end
        local info = ffi.new('RO_REGION[1]')
        if tonumber(k.VirtualQuery(ffi.cast('void *', address), info, ffi.sizeof(info[0]))) ~= ffi.sizeof(info[0]) then return nil end
        local r = info[0]
        return { base = tonumber(ffi.cast('uintptr_t', r.base)), size = tonumber(r.size),
                 state = tonumber(r.state), protection = tonumber(r.protection), kind = tonumber(r.kind) }
    end
    local function readable(r)
        if not r or r.state ~= 0x1000 then return false end
        local p = r.protection % 256
        return (p == 2 or p == 4 or p == 8 or p == 32 or p == 64 or p == 128) and r.protection < 256
    end
    -- generic read, allowed on private AND image regions
    function api.read(address, size)
        if type(size) ~= 'number' or size <= 0 or size > 262144 or excluded(address, size) then return nil end
        local r = api.query(address)
        if not readable(r) then return nil end
        if address < r.base or address + size > r.base + r.size then return nil end
        if k.ReadProcessMemory(process, ffi.cast('const void *', address), buf, size, cnt) == 0
            or tonumber(cnt[0]) ~= size then return nil end
        return ffi.string(buf, size)
    end
    function api.pointer(bytes)
        if not bytes or #bytes ~= 8 then return nil end
        local p = ffi.new('uint64_t[1]')
        ffi.copy(p, bytes, 8)
        local v = tonumber(p[0])
        if v < 65536 or v >= 0x800000000000 then return nil end
        return v
    end
    function api.module_hash(addr)
        local cache = rawget(_G, 'ROPROBE_SHA_CACHE')
        if type(cache) == 'table' and cache.addr == addr and type(cache.sha) == 'string' then return cache.sha end
        local path = ffi.new('uint16_t[32768]')
        local n = k.GetModuleFileNameW(ffi.cast('void *', addr), path, 32768)
        if n == 0 or n >= 32768 then return nil end
        local f = k.CreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
        if f == ffi.cast('void *', -1) then return nil end
        local alg, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
        local ok, res = pcall(function()
            local nm = ffi.new('uint16_t[7]', { 83, 72, 65, 50, 53, 54, 0 })
            assert(b.BCryptOpenAlgorithmProvider(alg, nm, nil, 0) == 0)
            assert(b.BCryptCreateHash(alg[0], hash, nil, 0, nil, 0, 0) == 0)
            local chunk = ffi.new('uint8_t[65536]')
            local got = ffi.new('uint32_t[1]')
            while true do
                assert(k.ReadFile(f, chunk, 65536, got, nil) ~= 0)
                if got[0] == 0 then break end
                assert(b.BCryptHashData(hash[0], chunk, got[0], 0) == 0)
            end
            local d = ffi.new('uint8_t[32]')
            assert(b.BCryptFinishHash(hash[0], d, 32, 0) == 0)
            local parts = {}
            for i = 0, 31 do parts[#parts + 1] = string.format('%02x', d[i]) end
            return table.concat(parts)
        end)
        if hash[0] ~= nil then b.BCryptDestroyHash(hash[0]) end
        if alg[0] ~= nil then b.BCryptCloseAlgorithmProvider(alg[0], 0) end
        k.CloseHandle(f)
        if not ok then return nil end
        rawset(_G, 'ROPROBE_SHA_CACHE', { addr = addr, sha = res })
        return res
    end
    return api
end

-- ------------------------------------------------------------------ locate
local function djb2(s) local h = 5381 for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end return (h - 5381) % 4294967296 end
local function le32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
local TYPE_SIG = 'LDLD' .. le32(1) .. le32(djb2('ProjectileSettings'))

local function find_proj_table(anchor)
    local api = S.api
    for off = 0, 4096, 8 do
        local pb = api.read(anchor + off, 8)
        if pb then
            local cand = api.pointer(pb)
            if cand then
                local head = api.read(cand, 24)
                if head and head:sub(1, 16) == TYPE_SIG then
                    local count = u32(head, 16)
                    if count and count > 50 and count < 5000 then
                        local first = api.read(cand + 16, 4)
                        if first then
                            local ok = true
                            for _, i in ipairs({ 0, math.floor(count / 2), count - 1 }) do
                                local row = api.read(cand + 16 + i * ROW_SIZE, 8)
                                if not row then ok = false break end
                            end
                            if ok then return cand, count end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function locate_row()
    local api = S.api
    local game = api.module('game.dll')
    if not game then return nil, 'no_game_dll' end
    if api.module_hash(game) ~= GAME_SHA then return nil, 'game_dll_hash_mismatch' end
    local anchor = api.pointer(api.read(game + DAMAGEINFO_SLOT, 8))
    if not anchor then return nil, 'anchor_unreadable' end
    local array, count = find_proj_table(anchor)
    if not array then return nil, 'projectile_table_not_found' end
    S.count = count

    local hit, hits = nil, 0
    for i = 0, count - 1 do
        local addr = array + 16 + i * ROW_SIZE
        local row = api.read(addr, ROW_SIZE)
        if row and u32(row, 84) == TARGET_DMGID then
            hits = hits + 1
            if not hit then hit = { addr = addr, idx = i } end
            if hits > 1 then break end
        end
    end
    if hits == 0 then return nil, 'damage_link_not_found' end
    if hits > 1 then return nil, 'damage_link_ambiguous' end
    return hit
end

-- ------------------------------------------------------------------ compare
local function compare(row)
    if not S.baseline or not row then return end
    for i = 0, ROW_SIZE - 1 do
        local a = S.baseline:byte(i + 1)
        local b = row:byte(i + 1)
        if a ~= b then
            local rec = S.changes[i]
            if not rec then
                rec = { first = string.format('%02x', a), last = string.format('%02x', b), count = 1 }
                S.changes[i] = rec
                emit(string.format('CHANGED +%d: %02x -> %02x', i, a, b))
            else
                rec.last = string.format('%02x', b)
                rec.count = rec.count + 1
            end
        end
    end
end

-- ------------------------------------------------------------------ lifecycle
local function startup()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local apiv = type(loader) == 'table' and tonumber(loader.api) or nil
    if not apiv or apiv < 1 then
        S.phase = 'error' S.status = 'loader_api_too_old' S.disabled = true
        emit('need Bingus Shared Loader v15+/API 1') write_status('FAILED - loader', '') return false
    end
    local api, err = make_api()
    if not api then
        S.phase = 'error' S.status = 'ffi_unavailable' S.disabled = true
        emit(S.status .. ': ' .. tostring(err)) write_status('FAILED - FFI', '') return false
    end
    S.api = api
    S.phase = 'locate'
    S.status = 'waiting_for_projectile_table'
    write_status('WORKING - waiting for the projectile table', '')
    return true
end

local function tick()
    if S.disabled then return end
    S.frames = S.frames + 1
    if S.phase == 'done' then return end
    if S.frames % 30 ~= 0 then return end
    S.ticks = S.ticks + 1

    -- phase 1: find the row and take the baseline
    if S.phase == 'locate' then
        local hit, why = locate_row()
        if not hit then
            S.last_why = why
            if S.ticks % 60 == 0 then emit('locate attempt ' .. S.ticks .. ': ' .. tostring(why)) end
            if S.ticks >= S.max_tries then
                S.phase = 'error' S.disabled = true S.status = 'gave_up'
                emit('gave up: ' .. tostring(why))
                write_status('FAILED - projectile row never located', tostring(why))
            end
            return
        end
        local row = S.api.read(hit.addr, ROW_SIZE)
        if not row then S.last_why = 'row_unreadable' return end
        S.baseline = row
        S.base_addr = hit.addr
        S.row_index = hit.idx
        write_file(NAME .. '-row.hex', hexdump(row))
        S.phase = 'sample'
        S.samples = 1
        emit(string.format('baseline captured: row=0x%x index=%d of %d', hit.addr, hit.idx, S.count))
        write_status('SAMPLING - baseline captured, now watching for changes',
            string.format('row=0x%x index=%d', hit.addr, hit.idx))
        return
    end

    -- phase 2: re-read on a slow timer and diff
    if S.phase == 'sample' then
        if S.frames % 300 ~= 0 then return end   -- once every ~5 seconds
        local game = S.api.module('game.dll')
        if not game then return end
        local anchor = S.api.pointer(S.api.read(game + DAMAGEINFO_SLOT, 8))
        if not anchor then return end
        local array = find_proj_table(anchor)
        if not array then
            emit('projectile table disappeared (rebuilt?)')
            S.last_why = 'table_moved'
            return
        end
        local addr = array + 16 + S.row_index * ROW_SIZE
        if addr ~= S.base_addr then
            emit(string.format('ROW ADDRESS MOVED: 0x%x -> 0x%x (table index %d)',
                S.base_addr, addr, S.row_index))
            S.base_addr = addr
            S.addr_moved = true
        end
        local row = S.api.read(addr, ROW_SIZE)
        if not row then S.last_why = 'row_unreadable' return end
        S.samples = S.samples + 1
        compare(row)
        write_changes()
        write_status('SAMPLING - watching for changes',
            string.format('%d sample(s), %d byte position(s) ever differed',
                S.samples, (function() local n = 0 for _ in pairs(S.changes) do n = n + 1 end return n end)()))
    end
end

local loader = rawget(_G, 'CowboyBingusModLoader')
if rawget(_G, 'MaxigunProbeRO') then return rawget(_G, 'MaxigunProbeRO') end
rawset(_G, 'MaxigunProbeRO', M)
S.owner = loader
S.disabled = not startup()

if not S.disabled then
    local previous_update = rawget(_G, 'update')
    local my_update
    my_update = function(dt, ...)
        if not S.disabled then
            local ok, err = pcall(tick)
            if not ok then
                S.disabled = true
                S.status = 'runtime_error: ' .. tostring(err)
                pcall(emit, S.status)
                pcall(write_status, 'FAILED - runtime', tostring(err))
            end
        end
        if type(previous_update) == 'function' then return previous_update(dt, ...) end
    end
    rawset(_G, 'update', my_update)

    local previous_shutdown = rawget(_G, 'shutdown')
    rawset(_G, 'shutdown', function(...)
        pcall(write_changes)
        pcall(write_status, 'DONE - read-only probe finished',
            string.format('%d sample(s)', S.samples))
        if rawget(_G, 'update') == my_update and type(previous_update) == 'function' then
            rawset(_G, 'update', previous_update)
        end
        pcall(flush_log)
        if type(previous_shutdown) == 'function' then return previous_shutdown(...) end
    end)
end

pcall(flush_log)
return M
