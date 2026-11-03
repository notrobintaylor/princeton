-- level is the one scale every volume control shares: -75 to +10 dB laid out like a console fader,
-- 1 dB a tick below -20 dB and 0.5 dB above, with silence at the bottom. The taper lives in the
-- controlspec, so PARAMS, princeton's panes, lcx and a mapped MIDI knob all move alike.
local fmt = include("lib/fmt")

local level = {}

level.MIN, level.MAX = -75, 10
local MID = -20
local LO_TICKS = (MID - level.MIN) / 1
local HI_TICKS = (level.MAX - MID) / 0.5
local BEND = LO_TICKS / (LO_TICKS + HI_TICKS)

local FADER = {}
function FADER.map(_, x)
  if x <= BEND then return level.MIN + (MID - level.MIN) * x / BEND end
  return MID + (level.MAX - MID) * (x - BEND) / (1 - BEND)
end
function FADER.unmap(_, db)
  if db <= MID then return BEND * (db - level.MIN) / (MID - level.MIN) end
  return BEND + (1 - BEND) * (db - MID) / (level.MAX - MID)
end

function level.spec(default)
  local cs = controlspec.new(level.MIN, level.MAX, "lin", 0.5, default or 0, "dB", 1 / (LO_TICKS + HI_TICKS))
  cs.warp = FADER
  return cs
end

-- the bottom of the travel is off, not merely quiet
function level.amp(db)
  if db <= level.MIN then return 0 end
  return 10 ^ (db / 20)
end

function level.str(db)
  if db <= level.MIN then return "-inf dB" end
  return fmt.auto({ controlspec = { units = "dB", step = 0.5, minval = level.MIN }, get = function() return db end })
end

-- Adds a level control whose action receives the linear gain.
function level.add(id, name, default, send)
  params:add_control(id, name, level.spec(default))
  params:lookup_param(id).formatter = function(p) return level.str(p:get()) end
  params:set_action(id, function(v) send(level.amp(v)) end)
end

return level
