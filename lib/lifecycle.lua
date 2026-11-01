-- lifecycle builds devices only when needed, because some engine devices cost CPU even when silent.
-- It tracks what's standing, so nothing is built twice or torn down that never stood.
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
