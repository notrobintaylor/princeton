-- nam plays NAM profiles, the learned imprint of a real amp, through princeton's own NamAmp UGen.
-- sclang loads plugins only at startup, so after install() copies it into Extensions the script
-- reports "restart" until norns reboots.
local nam = {
  status = "missing",
  dir    = _path.data .. "princeton/nam/",
  files  = {},
  gear   = {},
}

local SRC = _path.code .. "princeton/lib/nam/NamAmp.so"
local DST = "/home/we/.local/share/SuperCollider/Extensions/princeton/NamAmp.so"

local function mtime(path)
  return tonumber(util.os_capture("stat -c %Y " .. path .. " 2>/dev/null")) or 0
end

-- when sclang started: a plugin copied after that is still unknown to it
local function sclang_start()
  local age = tonumber(util.os_capture("ps -o etimes= -C sclang | head -1")) or 0
  return os.time() - age
end

function nam.install()
  if not util.file_exists(SRC) then
    nam.status = "missing"
    return nam.status
  end
  if not util.file_exists(DST) or os.execute("cmp -s " .. SRC .. " " .. DST) ~= true then
    os.execute("mkdir -p " .. DST:match("(.*/)") .. " && cp " .. SRC .. " " .. DST)
    nam.status = "restart"
  elseif mtime(DST) >= sclang_start() then
    nam.status = "restart"
  else
    nam.status = "ok"
  end
  return nam.status
end

function nam.scan()
  util.make_dir(nam.dir)
  nam.files = {}
  for _, f in ipairs(util.scandir(nam.dir) or {}) do
    if f:match("%.nam$") then nam.files[#nam.files + 1] = f end
  end
  table.sort(nam.files)
  return nam.files
end

function nam.available()
  return nam.status == "ok" and #nam.files > 0
end

-- names without the prefix all profiles share (often the amp's name), so the strip shows what
-- sets them apart
function nam.options()
  local opts = {}
  for _, f in ipairs(nam.files) do opts[#opts + 1] = f:gsub("%.nam$", "") end
  if #opts == 0 then opts[1] = "-" end
  if #opts > 1 then
    local pre = opts[1]
    for _, o in ipairs(opts) do
      while pre ~= "" and o:sub(1, #pre) ~= pre do pre = pre:sub(1, -2) end
    end
    pre = pre:match("^(.*[%s%-_])") or ""
    if #pre > 0 then
      for i, o in ipairs(opts) do opts[i] = o:sub(#pre + 1):gsub("^[%s%-_]+", "") end
    end
  end
  return opts
end

-- Does a profile already include the cabinet (gear_type "full" or "cab")? Then Cab & Mic can
-- step aside; the flag sits in the metadata at the file's start or end, only those chunks are
-- read, and the answer is cached per file.
function nam.full_rig(i)
  local f = nam.files[i]
  if not f then return false end
  if nam.gear[f] == nil then
    local h = io.open(nam.dir .. f, "r")
    local head = h and h:read(4096) or ""
    local tail = ""
    if h then
      local size = h:seek("end")
      h:seek("set", math.max(0, size - 8192))
      tail = h:read("a") or ""
      h:close()
    end
    nam.gear[f] = (head .. tail):match('"gear_type"%s*:%s*"([^"]*)"') or ""
  end
  local g = nam.gear[f]:lower()
  return g:match("full") ~= nil or g:match("cab") ~= nil
end

function nam.select(on, i)
  if not on or not nam.available() or not nam.files[i] then
    engine.nam_on(0)
    return
  end
  engine.nam_load(nam.dir .. nam.files[i])
  engine.nam_on(1)
end

return nam
