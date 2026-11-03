-- control is princeton's control system: every knob is a Level, a Drive, an Amount, a Rate,
-- Frequency or Time, or a Step, and its values land on round numbers. The spec carries range and
-- tick, so PARAMS, princeton's panes, lcx and a mapped MIDI knob all move alike.
local control = {}

-- -75 dB is the quietest level that still sounds; the tick below it, LEVEL_OFF, is silence.
control.LEVEL_MIN, control.LEVEL_MAX, control.LEVEL_OFF = -75, 10, -76

-- A ladder starts at its first value and climbs in rungs of { up to, step }. Steps grow with the
-- value, so a tick is fine where the ear is fine and coarse where it isn't.
local LADDERS = {
  level = { -76, { -20, 1 }, { 10, 0.5 } },
  rate  = { 0.1, { 2, 0.1 }, { 10, 0.5 }, { 25, 1 } },
  hz    = { 20, { 100, 5 }, { 500, 25 }, { 1000, 50 }, { 5000, 250 }, { 10000, 500 }, { 20000, 1000 } },
  ms    = { 0.1, { 1, 0.1 }, { 10, 1 }, { 100, 5 }, { 500, 25 }, { 1000, 50 }, { 5000, 250 }, { 10000, 500 } },
  ms0   = { 0, { 100, 5 }, { 500, 25 }, { 1000, 50 }, { 5000, 250 }, { 10000, 500 } },
}
-- seconds walk the millisecond ladders
local SCALED = { s = { "ms", 1000 }, s0 = { "ms0", 1000 } }

local function snap(v) return math.floor(v * 1e6 + 0.5) / 1e6 end

-- Cuts a ladder to lo..hi, both of which must sit on its grid.
local function rungs(name, lo, hi)
  local L = LADDERS[name]
  local segs, from, n = {}, L[1], 0
  for i = 2, #L do
    local to, step = L[i][1], L[i][2]
    local a, b = math.max(from, lo), math.min(to, hi)
    if b > a + 1e-9 then
      local off, cnt = (a - from) / step, (b - a) / step
      assert(math.abs(off - math.floor(off + 0.5)) < 1e-6 and math.abs(cnt - math.floor(cnt + 0.5)) < 1e-6,
        "control: " .. lo .. ".." .. hi .. " is off the " .. name .. " grid")
      cnt = math.floor(cnt + 0.5)
      segs[#segs + 1] = { a = a, step = step, n = cnt, at = n }
      n = n + cnt
    end
    from = to
  end
  return segs, n
end

local function ladder_spec(name, lo, hi, default, units, scale)
  scale = scale or 1
  local segs, n = rungs(name, lo * scale, hi * scale)
  local warp = {}
  function warp.map(_, x)
    local i = math.floor(x * n + 0.5)
    for k = #segs, 1, -1 do
      local s = segs[k]
      if i >= s.at or k == 1 then return snap((s.a + (i - s.at) * s.step) / scale) end
    end
  end
  function warp.unmap(_, v)
    v = v * scale
    for k = #segs, 1, -1 do
      local s = segs[k]
      if v >= s.a - 1e-9 or k == 1 then return (s.at + math.max(0, math.min((v - s.a) / s.step, s.n))) / n end
    end
  end
  local cs = controlspec.new(lo, hi, "lin", 0, default, units, 1 / n)
  cs.warp = warp
  cs.fine = segs[1].step / scale
  return cs
end

local UNITS = { level = "dB", rate = "Hz", hz = "Hz", ms = "ms", ms0 = "ms", s = "s", s0 = "s" }

-- spec(kind, lo, hi, default[, step, units]) builds the controlspec of one kind. Levels default to
-- off..+10 dB, Drives to 0..10, Amounts to 0..100 %; Steps need their step.
function control.spec(kind, lo, hi, default, step, units)
  local cs
  if kind == "level" then
    cs = ladder_spec("level", lo or control.LEVEL_OFF, hi or control.LEVEL_MAX, default or 0, "dB")
  elseif kind == "drive" then
    cs = controlspec.new(0, 10, "lin", 0.1, default, "", 0.01)
    cs.fine = 0.1
  elseif kind == "amount" then
    lo, hi = lo or 0, hi or 100
    cs = controlspec.new(lo, hi, "lin", step or 1, default, "%", (step or 1) / (hi - lo))
    cs.fine = step or 1
  elseif kind == "steps" then
    cs = controlspec.new(lo, hi, "lin", step, default, units or "", step / (hi - lo))
    cs.fine = step
  elseif SCALED[kind] then
    cs = ladder_spec(SCALED[kind][1], lo, hi, default, UNITS[kind], SCALED[kind][2])
  else
    assert(LADDERS[kind], "control: unknown kind " .. tostring(kind))
    cs = ladder_spec(kind, lo, hi, default, units or UNITS[kind])
  end
  cs.kind = kind
  return cs
end

-- the bottom of a level's travel is off, not merely quiet
function control.amp(db)
  if db < control.LEVEL_MIN then return 0 end
  return 10 ^ (db / 20)
end

function control.level_str(db)
  if db < control.LEVEL_MIN then return "-inf dB" end
  local s = string.format("%.1f", db)
  if tonumber(s) == 0 then s = "0.0" elseif db > 0 then s = "+" .. s end
  return s .. " dB"
end

-- A level in dB for the engine, with off as far below hearing as dbamp needs.
function control.db(db)
  return db < control.LEVEL_MIN and -200 or db
end

-- Adds a control of one kind. Its action gets the value, or for a Level the linear gain.
function control.add(id, name, kind, default, send, lo, hi, step, units)
  params:add_control(id, name, control.spec(kind, lo, hi, default, step, units))
  if kind == "level" then
    params:lookup_param(id).formatter = function(p) return control.level_str(p:get()) end
    params:set_action(id, function(v) send(control.amp(v)) end)
  else
    params:set_action(id, send)
  end
end

function control.level(id, name, default, send, hi)
  control.add(id, name, "level", default, send, nil, hi)
end

return control
