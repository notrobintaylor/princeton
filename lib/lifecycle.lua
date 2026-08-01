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
