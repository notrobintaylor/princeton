-- fmt decides how a value reads in the PARAMS menu, so 0.0125 s shows as 12.5 ms and 1500 Hz as 1.5
-- kHz. Stepped controls also get an encoder tick that lands exactly on their grid.

local fmt = {}

-- Whatever already sits in PARAMS at load belongs to the system (LEVELS, REVERB, COMPRESSOR,
-- …), since norns builds it before the script. Those controls keep their own formatting.
local SYSTEM_COUNT = params.count

-- How many decimals a step needs (0.5 -> 1, 0.01 -> 2).
local function decimals(step)
  if not step or step <= 0 then return nil end
  for d = 0, 3 do
    local s = step * 10 ^ d
    if math.abs(s - math.floor(s + 0.5)) < 1e-6 then return d end
  end
  return 3
end

-- Trailing zeros drop: "1.50" -> "1.5", "2.00" -> "2".
local function trim(s)
  if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
  return s
end

-- a rounded zero carries no minus; signed puts a + before positive values
local function num(v, d, signed)
  local s = string.format("%." .. d .. "f", v)
  if tonumber(s) == 0 then s = string.format("%." .. d .. "f", 0) end
  if signed and tonumber(s) > 0 then s = "+" .. s end
  return s
end

-- Rounds to two significant digits. With fine, values with a leading 1 get a half step, so an
-- exponential encoder tick of about 5 % never lands on the same value twice.
function fmt.nice(v, fine)
  if v <= 0 then return v end
  local base = 10 ^ math.floor(math.log(v, 10) + 1e-9)
  local q = base * ((fine and v < 2 * base) and 0.05 or 0.1)
  return math.floor(v / q + 0.5) * q
end

-- Below one second in milliseconds, above in seconds.
function fmt.time(ms)
  if ms < 10 then return trim(string.format("%.2f", ms)) .. " ms" end
  if ms < 1000 then return string.format("%d ms", math.floor(ms + 0.5)) end
  return trim(string.format("%.2f", ms / 1000)) .. " s"
end

-- Below one kilohertz in hertz, above in kilohertz.
function fmt.hz(hz, d)
  if hz >= 1000 then return trim(string.format("%.2f", hz / 1000)) .. " kHz" end
  if d then return num(hz, d) .. " Hz" end
  if hz < 10 then return trim(string.format("%.2f", hz)) .. " Hz" end
  if hz < 100 then return trim(string.format("%.1f", hz)) .. " Hz" end
  return string.format("%d Hz", math.floor(hz + 0.5))
end

-- The formatter for every control: decimals follow the step, bipolar ranges carry a sign, times
-- and frequencies switch units.
function fmt.auto(p)
  local cs   = p.controlspec
  local v    = p:get()
  local unit = cs.units or ""
  -- a dB control at the bottom reads -inf; tonumber("-inf") is nil in Lua 5.3
  if v == math.huge or v == -math.huge then
    local s = v > 0 and "inf" or "-inf"
    return unit == "" and s or (s .. " " .. unit)
  end
  if unit == "ms" then return fmt.time(v) end
  if unit == "s" then return fmt.time(v * 1000) end
  if unit == "Hz" then return fmt.hz(v, decimals(cs.step)) end
  local s = num(v, decimals(cs.step) or 2, cs.minval < 0)
  if decimals(cs.step) == nil then s = trim(s) end
  return unit == "" and s or (s .. " " .. unit)
end

-- The encoder tick for a linear stepped control: one step per tick while the range spans at
-- most 200 steps, otherwise a whole number of steps (about a hundred ticks end to end). So a
-- tick never lands between two steps, nor twice on the same one.
local function grid_quantum(cs)
  local range = cs.maxval - cs.minval
  local steps = range / cs.step
  return cs.step * (steps <= 200 and 1 or math.floor(steps / 100 + 0.5)) / range
end

-- Gives every control without its own formatter fmt.auto, and every linear stepped control a
-- tick that follows its step. System controls stay untouched.
function fmt.apply_all()
  for i = SYSTEM_COUNT + 1, params.count do
    local p = params.params[i]
    local cs = p.controlspec
    if p.t == params.tCONTROL and cs then
      if p.formatter == nil then p.formatter = fmt.auto end
      -- linear means: the middle of the travel hits the middle of the range
      if cs.step and cs.step > 0 and cs.maxval > cs.minval
         and math.abs(cs:map(0.5) - (cs.minval + cs.maxval) / 2) <= cs.step then
        cs.quantum = grid_quantum(cs)
      end
    end
  end
end

return fmt
