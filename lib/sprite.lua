-- sprite turns pictures made of text into points, one character per pixel, with "." empty and
-- base-36 glyphs as levels. rects merges neighbouring points into horizontal runs, so each run
-- draws as one rectangle.
local sprite = {}

local runs_cache = setmetatable({}, { __mode = "k" })

function sprite.decode(art)
  local levels, y = {}, 0
  for line in art:gmatch("([^\n]*)\n") do
    for x = 1, #line do
      local c = line:sub(x, x)
      if c ~= "." then
        local lv = tonumber(c, 36)
        local t = levels[lv]
        if not t then t = {}; levels[lv] = t end
        t[#t + 1] = { x - 1, y }
      end
    end
    y = y + 1
  end
  return levels
end

local function runs(pts)
  local r = runs_cache[pts]
  if r then return r end
  local rows = {}
  for _, p in ipairs(pts) do
    local t = rows[p[2]]
    if not t then t = {}; rows[p[2]] = t end
    t[#t + 1] = p[1]
  end
  r = {}
  for y, xs in pairs(rows) do
    table.sort(xs)
    local s, w = xs[1], 1
    for i = 2, #xs do
      local x = xs[i]
      if x == s + w then w = w + 1
      elseif x ~= s + w - 1 then r[#r + 1] = { s, y, w }; s, w = x, 1 end
    end
    r[#r + 1] = { s, y, w }
  end
  runs_cache[pts] = r
  return r
end

function sprite.rects(pts, ox, oy)
  for _, q in ipairs(runs(pts)) do screen.rect(ox + q[1], oy + q[2], q[3], 1) end
end

return sprite
