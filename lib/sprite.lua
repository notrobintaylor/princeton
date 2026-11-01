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

-- A dashed line of 5 px dashes and 4 px gaps, centred so both ends keep the same margin. With an
-- odd leftover one dash fewer is drawn, since an even one splits evenly.
sprite.DASH, sprite.GAP = 5, 4

function sprite.dashes(x, y, len, vertical)
  local d, g = sprite.DASH, sprite.GAP
  local n = math.floor((len + g) / (d + g))
  if (len - (n * d + (n - 1) * g)) % 2 == 1 then n = n - 1 end
  local o = (len - (n * d + (n - 1) * g)) / 2
  for k = 0, n - 1 do
    local p = o + k * (d + g)
    if vertical then screen.rect(x, y + p, 1, d) else screen.rect(x + p, y, d, 1) end
  end
end

return sprite
