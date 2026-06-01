-- princeton lifecycle
--
-- Sub-synth spawn/free helper for click/pop-free bypass (the prc_t101 standard).
-- A managed sub-synth named <name> is backed by two engine commands the SC engine
-- provides: <name>_on (Synth spawn, gate = 1) and <name>_off (gate = 0, then the
-- sub-synth frees itself via its EnvGen doneAction after the fade). Lua never holds
-- the SC node; the engine owns it. This module only tracks on/off state so that
-- spawn/free are idempotent.

local lifecycle = {}

lifecycle.active = {}

function lifecycle.spawn(name)
  if lifecycle.active[name] then return end
  engine[name .. "_on"]()
  lifecycle.active[name] = true
end

function lifecycle.free(name)
  if not lifecycle.active[name] then return end
  engine[name .. "_off"]()
  lifecycle.active[name] = false
end

function lifecycle.set(name, on)
  if on then lifecycle.spawn(name) else lifecycle.free(name) end
end

return lifecycle
