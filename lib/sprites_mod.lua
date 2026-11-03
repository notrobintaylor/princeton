-- sprites_mod gives each modulation source exactly one picture, the same in the chooser and the
-- editor. In the chooser it runs on invented values, in the editor it shows what the source really
-- does.

local scope = include("lib/scope")

local sprites_mod = {}

local FULL, DIM = 15, 3
local TAU = 2 * math.pi

sprites_mod.SENSE_WIN = 3.2   -- seconds of history the Sense picture spans
sprites_mod.TRIG_SLOTS = 8    -- chances the Trigger picture shows

local function dim_of(lv) return lv > 2 and DIM or 1 end

-- ── Modulate ───────────────────────────────────────────────────
local function demo_lfo(x, y, w, h, now, lv)
  local win, ys = 2.5, {}
  for i = 0, w - 1 do
    local v = 0.5 + 0.5 * math.sin(TAU * (now - win * (w - 1 - i) / (w - 1)) / 1.25)
    ys[i] = y + (1 - v) * (h - 1)
  end
  scope.line(x, ys, w, lv)
end

-- ── Sense ──────────────────────────────────────────────────────
-- env[i]: the envelope in column i (0 to 1, nil = nothing yet), mirrored above and below the
-- centre line the way it hugs an audio signal's peaks. The signal itself stays hidden; the
-- shape is enough to see it.
function sprites_mod.sense(x, y, w, h, env, lv)
  local mid = y + math.floor((h - 1) / 2)
  local hh  = math.floor((h - 1) / 2)
  local top, bot = {}, {}
  for i = 0, w - 1 do
    local e = env[i]
    if e then
      e = math.max(0, math.min(1, e)) * hh
      -- under a pixel the two halves would blur the centre line into a double one
      if e < 1 then e = 0 end
      top[i], bot[i] = mid - e, mid + e
    end
  end
  scope.line(x, top, w, lv)
  scope.line(x, bot, w, lv)
end

-- short attack, long decay, alternating loud and soft
local function pluck(tau)
  local per = 1.6
  local p = tau % per
  local loud = math.floor(tau / per) % 2 == 0 and 1 or 0.6
  if p < 0.08 then return loud * p / 0.08 end
  return loud * math.exp(-(p - 0.08) * 2.4)
end

local function demo_sense(x, y, w, h, now, lv)
  local win, env = sprites_mod.SENSE_WIN, {}
  for i = 0, w - 1 do env[i] = pluck(now - win * (w - 1 - i) / (w - 1)) end
  sprites_mod.sense(x, y, w, h, env, lv)
end

-- ── Walk ───────────────────────────────────────────────────────
-- steps holds all step values (-1..1), n how many play, cur the playing step and sel the one being
-- edited. Disabled slots stay as faint ghosts at the lowest brightness, so you can see what returns
-- when you raise the count.
local GHOST = 1

function sprites_mod.walk(x, y, w, h, steps, n, cur, sel, lv)
  local total = #steps
  local cw  = math.min(10, math.floor((w + 1) / total))
  local x0  = x + math.floor((w - (total * cw - 1)) / 2)
  local hh  = math.floor((h - 7) / 2)
  local mid = y + hh
  local dim = dim_of(lv)
  for k = 1, total do
    local bx = x0 + (k - 1) * cw
    local v  = math.max(1, math.floor(math.abs(steps[k]) * hh + 0.5))
    local by = steps[k] >= 0 and mid - v or mid + 1
    if k <= n then
      screen.level(k == cur and lv or dim)
      screen.rect(bx, by, cw - 1, v)
      -- the chase light
      screen.rect(bx, y + h - 2, cw - 1, 2)
    else
      screen.level(GHOST)
      screen.rect(bx, by, cw - 1, v)
    end
    screen.fill()
    if sel == k then
      screen.level(FULL); screen.rect(bx + math.floor((cw - 1) / 2), y + h + 1, 1, 1); screen.fill()
    end
  end
end

local WALK = { 0.6, -0.3, 0.9, 0.2, -0.8, 0.4, -0.5, 1.0,
               -0.1, 0.7, -0.6, 0.3, -1.0, 0.8, 0.1, -0.4 }

local function demo_walk(x, y, w, h, now, lv)
  local n = 12
  sprites_mod.walk(x, y, w, h, WALK, n, math.floor(now * 4) % n + 1, nil, lv)
end

-- ── Trigger ────────────────────────────────────────────────────
-- slots: the latest chances, oldest first and newest on the right, { v = 1 (fired) | 0, t =
-- time }; a hit flashes bright, then stays as a block until it scrolls out left. No centre
-- line: a trigger has no value, only moments.
local FLASH = 0.12

function sprites_mod.trig(x, y, w, h, slots, now, lv)
  local n   = sprites_mod.TRIG_SLOTS
  local cw  = w / n
  local bw  = 4
  local off = n - #slots
  for i, s in ipairs(slots) do
    local bx = x + math.floor((off + i - 0.5) * cw) - bw / 2
    if s.v > 0 then
      screen.level((i == #slots and now - s.t < FLASH) and FULL or math.min(lv, 6))
      screen.rect(bx, y, bw, h); screen.fill()
    else
      screen.level(dim_of(lv)); screen.rect(bx + 0.5, y + 0.5, bw - 1, h - 1); screen.stroke()
    end
  end
end

local PULSE = { 1, 1, 0, 1, 0, 1, 1, 0 }

local function demo_trig(x, y, w, h, now, lv)
  local per = 0.35
  local k_now = math.floor(now / per)
  local slots = {}
  for k = k_now - sprites_mod.TRIG_SLOTS + 1, k_now do
    slots[#slots + 1] = { v = PULSE[k % #PULSE + 1], t = k * per }
  end
  sprites_mod.trig(x, y, w, h, slots, now, lv)
end

local DEMO = { lfo = demo_lfo, env = demo_sense, seq = demo_walk, trig = demo_trig }

-- Chooser: a source's picture on invented values; lv dims it when no slot is free
function sprites_mod.draw(kind, x, y, w, h, lv)
  DEMO[kind](x, y, w, h, util.time(), lv or FULL)
end

return sprites_mod
