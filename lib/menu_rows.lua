-- Two-line entries in the PARAMS menu
-- norns draws each parameter on one line, so a long value runs into its name. While princeton runs,
-- this module draws the EDIT list itself and wraps such values, restoring the original on exit.

local M = {}

local GAP = 4      -- at least this much space between name and value
local EDIT = 1     -- mEDIT in core/menu/params.lua

local menu = require 'core/menu/params'
local orig

-- the page (list of visible params) is local in the original: read it through the upvalue
local function page_of(f)
  for i = 1, 64 do
    local n, v = debug.getupvalue(f, i)
    if not n then return nil end
    if n == "page" then return v end
  end
end

local function plain(t)
  return t ~= params.tSEPARATOR and t ~= params.tGROUP and t ~= params.tTRIGGER and t ~= params.tBINARY
end

local function height(p)
  if not plain(params:t(p)) then return 1 end
  local w = screen.text_extents(params:get_name(p)) + GAP + screen.text_extents(params:string(p))
  return w > 128 and 2 or 1
end

-- one entry starting at row (1..6), drawn as in the original
local function draw(p, row, h)
  local y = 10 * row
  local t = params:t(p)
  if t == params.tSEPARATOR then
    screen.move(0, y + 2.5)
    screen.line_rel(127, 0)
    screen.stroke()
    screen.move(63, y)
    screen.text_center(params:get_name(p))
  elseif t == params.tGROUP then
    screen.move(0, y)
    screen.text(params:get_name(p) .. " >")
  else
    screen.move(0, y)
    screen.text(params:get_name(p))
    if t == params.tTRIGGER then
      local tr = _menu.binarystates.triggered[p]
      if tr and tr > 0 then screen.rect(124, y - 4, 3, 3); screen.fill() end
    elseif t == params.tBINARY then
      local fill = _menu.binarystates.on[p] or _menu.binarystates.triggered[p]
      if fill and fill > 0 then screen.rect(124, y - 4, 3, 3); screen.fill() end
    elseif row + h - 1 <= 6 then
      screen.move(127, 10 * (row + h - 1))
      screen.text_right(params:string(p))
    end
  end
end

local function redraw()
  local page = page_of(orig)
  if menu.mode ~= EDIT or not page then return orig() end
  screen.clear()
  _menu.draw_panel()
  if menu.pos == 0 then
    local n = "PARAMETERS"
    if menu.group then n = n .. " / " .. menu.groupname end
    screen.level(4)
    screen.move(0, 10)
    screen.text(n)
  end
  -- the selected entry sits in row 3 as in the original; the others follow on
  local sel = menu.pos + 1
  local row = 3
  for k = sel, #page do
    if row > 6 then break end
    local h = height(page[k])
    screen.level(k == sel and 15 or 4)
    draw(page[k], row, h)
    row = row + h
  end
  row = 3
  for k = sel - 1, 1, -1 do
    local h = height(page[k])
    row = row - h
    -- no room above the header; a half-visible entry is skipped
    if row < (menu.pos == 0 and 2 or 1) then break end
    screen.level(4)
    draw(page[k], row, h)
  end
  screen.update()
end

-- This module reaches into norns menu internals, which may change with a norns update. Before
-- hooking in it checks two assumptions (the menu has a local page, and EDIT mode is still 1)
-- and leaves the original menu alone if either fails, rather than drawing wrongly.
local function upvalue(f, name)
  for i = 1, 64 do
    local n, v = debug.getupvalue(f, i)
    if not n then return nil, false end
    if n == name then return v, true end
  end
  return nil, false
end

local function compatible(f)
  -- page is nil while the menu is closed (it builds its page on open): what counts is that the
  -- upvalue exists, not what it holds
  local _, has_page = upvalue(f, "page")
  if not has_page then return false end
  for _, g in ipairs({ menu.key, menu.enc }) do
    if type(g) == "function" then
      local v, found = upvalue(g, "mEDIT")
      if found then return v == EDIT end
    end
  end
  return true
end

function M.install()
  if orig then return end
  if not compatible(menu._princeton_redraw or menu.redraw) then
    print("princeton: menu_rows does not fit this norns menu, two-line entries stay off")
    return
  end
  -- stash the original on the menu: a crashed script may not have cleaned up
  orig = menu._princeton_redraw or menu.redraw
  menu._princeton_redraw = orig
  menu.redraw = redraw
  if _menu.page == "PARAMS" then _menu.redraw = redraw end
end

function M.remove()
  if not orig then return end
  menu.redraw = orig
  if _menu.page == "PARAMS" then _menu.redraw = orig end
  menu._princeton_redraw = nil
  orig = nil
end

return M
