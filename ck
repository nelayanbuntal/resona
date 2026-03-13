#!/usr/bin/env lua
--[[
  claim_cookies.lua - Cookies Auto Claim
  =======================================
  Sekali run → otomatis claim 4 cookies → tulis cookie.txt → selesai.
  Tidak perlu argumen. Tidak perlu input apapun.

  Install & run:
    curl -L -o claim_cookies.lua https://raw.githubusercontent.com/nelayanbuntal/resona/refs/heads/main/claim_cookies && lua claim_cookies.lua
]]

-- ══════════════════════════════════════════════════════
--  KONFIGURASI — ubah SERVER_URL sesuai cs50.dev kamu
-- ══════════════════════════════════════════════════════

local SERVER_URL     = "https://bookish-computing-machine-g4v964w7xxg739v96-5000.app.github.dev"
local COOKIE_PATH    = "/storage/emulated/0/Download/cookie.txt"
local DEVICE_ID_FILE = "/data/data/com.termux/files/home/.device_id"
local STATE_FILE     = "/data/data/com.termux/files/home/.cookies_state"
local MAX_RETRIES    = 10
local RETRY_MIN_MS   = 500
local RETRY_MAX_MS   = 3000
local COOKIES_NEEDED = 4

-- ══════════════════════════════════════════════════════
--  UTILS
-- ══════════════════════════════════════════════════════

local function exec(cmd)
  local h = io.popen(cmd .. " 2>/dev/null")
  local r = h:read("*a"); h:close()
  return (r or ""):match("^%s*(.-)%s*$")  -- trim
end

local function sleep_ms(ms)
  os.execute(string.format("sleep %.3f", ms / 1000))
end

local function jitter(lo, hi)
  local pid  = tonumber(exec("sh -c 'echo $$'")) or 1
  local seed = (os.time() * 1000 + pid * 13 + math.floor((os.clock() * 1e5)) % 997)
  math.randomseed(seed % 2147483647)
  return math.random(lo, hi)
end

local function curl(url)
  return exec(string.format(
    'curl -s --max-time 20 --connect-timeout 10 --retry 1 "%s"', url))
end

-- JSON mini-parser
local function jstr(t, k)  return t:match('"'..k..'":%s*"([^"]*)"') end
local function jnum(t, k)  local v = t:match('"'..k..'":%s*(%d+)'); return v and tonumber(v) end
local function jbool(t, k)
  local v = t:match('"'..k..'":%s*(true)')
  if v then return true end
  v = t:match('"'..k..'":%s*(false)')
  if v then return false end
  v = t:match('"'..k..'":%s*([01])[^%d]')
  if v == "1" then return true end
  if v == "0" then return false end
  return nil
end

local function jarr(t, k)
  local arr = {}
  local pattern = '"'..k..'":%s*%[([^%]]+)%]'
  local content = t:match(pattern)
  if not content then return nil end
  for v in content:gmatch('"([^"]*)"') do
    table.insert(arr, v)
  end
  return #arr > 0 and arr or nil
end

local function is_ok(resp)
  if jbool(resp, "ok") == true then return true end
  return false
end

-- ══════════════════════════════════════════════════════
--  DEVICE ID
-- ══════════════════════════════════════════════════════

local function make_device_id()
  local function try(cmd)
    local v = exec(cmd)
    if v ~= "" and v ~= "unknown" and #v > 3 then return v end
  end

  local s = try("getprop ro.serialno")
  if s then return "dev_" .. s:gsub("[^%w]",""):sub(1,20) end

  local m = try("ip link show wlan0 | awk '/ether/{print $2}'")
  if m and m ~= "ff:ff:ff:ff:ff:ff" and m ~= "00:00:00:00:00:00" then
    return "dev_" .. m:gsub(":",""):sub(1,12)
  end

  local b = try("cat /proc/sys/kernel/random/boot_id")
  if b then
    local h = 0
    for i=1,#b do h=(h*31+b:byte(i))%0xFFFFFFFF end
    return ("dev_boot%08x"):format(h)
  end

  math.randomseed(os.time())
  return ("dev_rand%08x"):format(math.random(0,0xFFFFFFFF))
end

-- ══════════════════════════════════════════════════════
--  FOLDER & FILE HELPERS
-- ══════════════════════════════════════════════════════

local function ensure_folder_exists(path)
  local folder = path:match("^(.*)/[^/]+$")
  if folder then
    local ok = os.execute('mkdir -p "' .. folder .. '" 2>/dev/null')
    if ok ~= 0 and ok ~= true then
      return false
    end
  end
  return true
end

local function get_device_id()
  -- Pastikan folder ada
  ensure_folder_exists(DEVICE_ID_FILE)

  local f = io.open(DEVICE_ID_FILE, "r")
  if f then
    local id = f:read("*l"); f:close()
    if id and id:match("^dev_") then return id end
  end
  local id = make_device_id()
  local fw = io.open(DEVICE_ID_FILE, "w")
  if fw then fw:write(id.."\n"); fw:close() end
  return id
end

-- ══════════════════════════════════════════════════════
--  COOKIE FILE & STATE
-- ══════════════════════════════════════════════════════

local function write_cookies(cookies)
  -- Pastikan folder ada sebelum tulis
  if not ensure_folder_exists(COOKIE_PATH) then
    io.write("[!] Gagal buat folder untuk: "..COOKIE_PATH.."\n")
    io.write("    Jalankan: termux-setup-storage\n")
    return false
  end

  local f = io.open(COOKIE_PATH, "w")
  if not f then
    io.write("[!] Gagal buat file: "..COOKIE_PATH.."\n")
    io.write("    Jalankan: termux-setup-storage\n")
    return false
  end
  -- Format: satu cookies per baris (tanpa key)
  for _, cookie in ipairs(cookies) do
    f:write(cookie.."\n")
  end
  f:close()
  return true
end

-- ══════════════════════════════════════════════════════
--  STATE LOKAL
-- ══════════════════════════════════════════════════════

local function save_state(t)
  local f = io.open(STATE_FILE, "w")
  if not f then return end
  for k,v in pairs(t) do f:write(k.."="..tostring(v).."\n") end
  f:close()
end

local function load_state()
  local f = io.open(STATE_FILE, "r")
  if not f then return nil end
  local s = {}
  for line in f:lines() do
    local k,v = line:match("^([^=]+)=(.+)$")
    if k then s[k]=v end
  end
  f:close()
  return (s.cookies and s.cookies~="") and s or nil
end

-- ══════════════════════════════════════════════════════
--  MAIN
-- ══════════════════════════════════════════════════════

local DEVICE = get_device_id()

io.write("\n")
io.write("┌─────────────────────────────────────┐\n")
io.write("│       Cookies Auto Claim            │\n")
io.write("└─────────────────────────────────────┘\n")
io.write("  Device  : "..DEVICE.."\n")
io.write("  Server  : "..SERVER_URL.."\n")
io.write("  Output  : "..COOKIE_PATH.."\n")
io.write("  Needed  : "..COOKIES_NEEDED.." cookies\n\n")

-- Cek apakah device sudah punya cookies aktif (idempotent re-run)
local existing = load_state()
if existing then
  io.write("[~] Device sudah punya cookies:\n")
  io.write("    Count    : "..(existing.count or "-").."\n")
  io.write("    Claimed  : "..(existing.claimed_at or "-").."\n\n")
  io.write("[*] Re-write ke cookie.txt...\n")

  -- Load cookies dari server untuk ditulis ulang
  local url = SERVER_URL.."/claim_cookies?device="..DEVICE
  local resp = curl(url)

  if is_ok(resp) then
    local cookies = jarr(resp, "cookies")
    if cookies and write_cookies(cookies) then
      io.write("[+] cookie.txt ✓ OK (re-applied)\n")
    else
      io.write("[!] Gagal tulis cookie.txt\n")
    end
  end
  io.write("\n[+] SELESAI\n")
  os.exit(0)
end

-- Jitter awal
local jit = jitter(0, 10000)
if jit > 50 then
  io.write(string.format("[*] Jitter: %.1f detik...\n", jit/1000))
  sleep_ms(jit)
end

-- Claim loop
local url = SERVER_URL.."/claim_cookies?device="..DEVICE
local claimed = false

for attempt = 1, MAX_RETRIES do
  io.write(string.format("[*] Attempt %d/%d — claim...\n", attempt, MAX_RETRIES))

  local resp = curl(url)

  if resp == "" then
    io.write("[!] Tidak bisa konek ke server (timeout/down).\n")
    if attempt < MAX_RETRIES then
      local w = jitter(1000, 4000)
      io.write(string.format("[~] Retry dalam %.1f detik...\n", w/1000))
      sleep_ms(w)
    end

  elseif is_ok(resp) then
    -- Berhasil claim
    local status     = jstr(resp, "status")     or "claimed"
    local cookies    = jarr(resp, "cookies")    or {}
    local count      = jnum(resp, "count")       or 0
    local claimed_at = jstr(resp, "claimed_at")  or "-"
    local remaining  = jnum(resp, "remaining_valid")

    io.write("\n")
    io.write("  Status     : "..status.."\n")
    io.write("  Count      : "..count.." cookies\n")
    io.write("  Waktu      : "..claimed_at.."\n")
    if remaining then
      io.write("  Sisa valid : "..remaining.."\n")
    end

    -- Simpan state lokal
    save_state({
      device     = DEVICE,
      count      = tostring(count),
      claimed_at = claimed_at
    })

    -- Tulis ke cookie.txt
    if #cookies > 0 then
      if write_cookies(cookies) then
        io.write("\n[+] cookie.txt ✓ ditulis ("..#cookies.." cookies)\n")
      else
        io.write("\n[!] Gagal tulis cookie.txt\n")
      end
    else
      io.write("\n[!] Cookies kosong — tidak ditulis.\n")
    end

    claimed = true
    break

  else
    -- Gagal
    local err = jstr(resp, "error") or resp
    io.write("[ERROR] "..err.."\n")
    if attempt < MAX_RETRIES then
      local w = jitter(500, 2000)
      io.write(string.format("[~] Retry %d/%d dalam %.1f detik...\n",
               attempt, MAX_RETRIES, w/1000))
      sleep_ms(w)
    end
  end
end

io.write("\n")
if claimed then
  io.write("[+] SELESAI — Cookies siap digunakan.\n")
else
  io.write("[!] GAGAL koneksi ke server setelah "..MAX_RETRIES.."x percobaan.\n")
  io.write("    Pastikan server berjalan: "..SERVER_URL.."\n")
end
io.write("\n")
