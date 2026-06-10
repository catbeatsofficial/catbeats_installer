-- CATBEATS INSTALLER
-- fetch + install catbeats scripts
-- from catbeats.life
--
-- ENC2: scroll scripts
-- K3: install selected
-- K2: refresh list

local MANIFEST_URL = "https://catbeats.life/norns/manifest.json"
local DUST         = "/home/we/dust/"

-- state
local state        = "boot"  -- boot, fetching, ready, installing, error
local manifest     = nil
local scripts      = {}
local message      = ""
local selected     = 1
local status_msg   = ""
local install_progress = { current = 0, total = 0, name = "" }

-- animation
local anim_clock   = nil

-- ASCII cats bouncing around left half (x: 0-54, y: 0-64)
-- each cat: { x, y, dx, dy, frame }
-- frames cycle between two ASCII strings
local CAT_FRAMES = { "=^.^=", "=^-^=" }
local CAT_BUSY   = { ">^.^<", ">^-^<" }  -- excited during fetch/install
local NUM_CATS   = 2
local cats       = {}
local tick       = 0

local LEFT_MAX_X = 16  -- keep cats within left third (~42px); cat text is ~24px wide
local LEFT_MAX_Y = 60

local function init_cats()
  cats = {}
  for i = 1, NUM_CATS do
    table.insert(cats, {
      x  = math.random(0, LEFT_MAX_X),
      y  = math.random(8, LEFT_MAX_Y),
      dx = (math.random(0,1) == 0) and 1 or -1,
      dy = (math.random(0,1) == 0) and 1 or -1,
      frame = 1,
    })
  end
end

local function update_cats()
  tick = tick + 1
  for _, c in ipairs(cats) do
    c.x = c.x + c.dx
    c.y = c.y + c.dy
    -- bounce off left half walls
    if c.x <= 0 then c.x = 0; c.dx = 1 end
    if c.x >= LEFT_MAX_X then c.x = LEFT_MAX_X; c.dx = -1 end
    if c.y <= 7 then c.y = 7; c.dy = 1 end
    if c.y >= LEFT_MAX_Y then c.y = LEFT_MAX_Y; c.dy = -1 end
    -- alternate frame each tick
    c.frame = (tick % 2 == 0) and 1 or 2
  end
end

local function draw_cats()
  local frames = (state == "fetching" or state == "installing") and CAT_BUSY or CAT_FRAMES
  screen.font_size(8)
  screen.font_face(1)
  for _, c in ipairs(cats) do
    local lv = (state == "fetching" or state == "installing") and 12 or 8
    screen.level(lv)
    screen.move(c.x, c.y)
    screen.text(frames[c.frame])
  end
end

-- -------------------------
-- display
-- -------------------------

local function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_size(8)
  screen.font_face(1)

  -- bouncing ASCII cats on left half
  draw_cats()

  -- right side content (cats stay in left third)
  local rx = 46

  if state == "boot" then
    screen.level(6)
    screen.move(rx, 20)
    screen.text("catbeats")
    screen.level(3)
    screen.move(rx, 32)
    screen.text("installer")
    screen.level(2)
    screen.move(rx, 50)
    screen.text("K2: fetch")

  elseif state == "fetching" then
    screen.level(8)
    screen.move(rx, 32)
    screen.text("fetching...")

  elseif state == "ready" then
    -- header
    screen.level(6)
    screen.move(rx, 10)
    screen.text("AVAILABLE SCRIPTS:")

    -- script list: NAME (version)
    local list_y = 22
    local visible = 3
    local start = math.max(1, selected - visible + 1)
    for i = start, math.min(#scripts, start + visible - 1) do
      local s = scripts[i]
      local y = list_y + (i - start) * 9
      local label = s.name
      if s.version and s.version ~= "" then
        label = label .. " (" .. s.version .. ")"
      end
      if i == selected then
        screen.level(15)
        screen.move(rx, y)
        screen.text("> " .. label)
      else
        screen.level(5)
        screen.move(rx, y)
        screen.text("  " .. label)
      end
    end

    -- bottom hint
    screen.level(3)
    screen.move(rx, 63)
    screen.text("K3: INSTALL")

  elseif state == "installing" then
    screen.level(10)
    screen.move(rx, 20)
    screen.text("installing")
    screen.level(6)
    screen.move(rx, 31)
    local n = install_progress.name
    if #n > 10 then n = n:sub(1,9) .. "…" end
    screen.text(n)
    -- progress bar
    if install_progress.total > 0 then
      local pct = install_progress.current / install_progress.total
      local bar_w = 60
      screen.level(3)
      screen.rect(rx, 38, bar_w, 4)
      screen.fill()
      screen.level(12)
      screen.rect(rx, 38, math.floor(bar_w * pct), 4)
      screen.fill()
      screen.level(4)
      screen.move(rx, 52)
      screen.text(install_progress.current .. "/" .. install_progress.total)
    end

  elseif state == "error" then
    screen.level(8)
    screen.move(rx, 25)
    screen.text("error")
    screen.level(4)
    screen.move(rx, 37)
    -- word wrap at ~10 chars
    local s = status_msg or ""
    screen.text(s:sub(1, 10))
    if #s > 10 then
      screen.move(rx, 47)
      screen.text(s:sub(11, 20))
    end
    screen.level(2)
    screen.move(rx, 60)
    screen.text("K2: retry")

  elseif state == "done" then
    screen.level(10)
    screen.move(rx, 25)
    screen.text("installed!")
    screen.level(4)
    screen.move(rx, 37)
    screen.text("restart norns")
    screen.level(2)
    screen.move(rx, 50)
    screen.text("to load engine")
  end

  screen.update()
end

-- -------------------------
-- animation clock
-- -------------------------

local function start_anim()
  if anim_clock then clock.cancel(anim_clock) end
  anim_clock = clock.run(function()
    while true do
      update_cats()
      -- don't draw over the system menu (lets K1 work)
      if not norns.menu.status() then
        redraw()
      end
      local speed = (state == "fetching" or state == "installing") and 0.1 or 0.2
      clock.sleep(speed)
    end
  end)
end

-- -------------------------
-- manifest fetch
-- -------------------------

local function ensure_dir(path)
  os.execute("mkdir -p " .. path)
end

local function fetch_manifest()
  state = "fetching"
  redraw()
  clock.run(function()
    local tmp = "/tmp/catbeats_manifest.json"
    local cmd = 'curl -sL --max-time 8 "' .. MANIFEST_URL .. '" -o ' .. tmp
    local ok = os.execute(cmd)
    if ok ~= 0 and ok ~= true then
      state = "error"
      status_msg = "no network"
      redraw()
      return
    end
    -- read file
    local f = io.open(tmp, "r")
    if not f then
      state = "error"
      status_msg = "fetch failed"
      redraw()
      return
    end
    local raw = f:read("*all")
    f:close()
    if not raw or raw == "" then
      state = "error"
      status_msg = "empty response"
      redraw()
      return
    end
    print("catbeats installer: manifest " .. #raw .. " bytes")
    -- parse JSON line by line — we control the format so this is reliable
    message = raw:match('"message"%s*:%s*"([^"]*)"') or ""
    scripts = {}
    local current = nil
    local in_files = false
    for line in raw:gmatch("[^\n]+") do
      -- detect start of a script object (has "name" key)
      local name = line:match('"name"%s*:%s*"([^"]*)"')
      local desc = line:match('"desc"%s*:%s*"([^"]*)"')
      local ver  = line:match('"version"%s*:%s*"([^"]*)"')
      -- files array open/close
      if line:match('"files"') then
        in_files = true
      end
      -- new top-level script entry: has name but not src/dest (those are file entries)
      if name and not line:match('"src"') and not line:match('"dest"') then
        if current then table.insert(scripts, current) end
        current = { name = name, desc = "", version = "", files = {} }
        in_files = false
      end
      if current then
        if desc and not in_files then current.desc = desc end
        if ver  then current.version = ver end
        -- file entry: has both src and dest
        local src  = line:match('"src"%s*:%s*"([^"]*)"')
        local dest = line:match('"dest"%s*:%s*"([^"]*)"')
        if src and dest then
          table.insert(current.files, { src = src, dest = dest })
        end
      end
    end
    if current then table.insert(scripts, current) end
    print("catbeats installer: parsed " .. #scripts .. " script(s)")
    for _, sc in ipairs(scripts) do
      print("  " .. sc.name .. " (" .. #sc.files .. " files)")
    end
    if #scripts == 0 then
      state = "error"
      status_msg = "no scripts found"
      redraw()
      return
    end
    selected = 1
    state = "ready"
    redraw()
  end)
end

-- -------------------------
-- install
-- -------------------------

local function install_selected()
  if #scripts == 0 then return end
  local s = scripts[selected]
  local files = s.files or {}
  if #files == 0 then
    state = "error"; status_msg = "no files"; redraw(); return
  end
  state = "installing"
  install_progress = { current = 0, total = #files, name = s.name }
  redraw()

  clock.run(function()
    local base_url = "https://catbeats.life/norns/"
    local errors = 0

    for i, file in ipairs(files) do
      install_progress.current = i
      install_progress.name = file.src:match("[^/]+$") or file.src
      redraw()

      local dest_dir = DUST .. file.dest
      ensure_dir(dest_dir)

      local dest_path = dest_dir .. (file.src:match("[^/]+$") or "file")
      local url = base_url .. file.src
      local cmd = 'curl -sL --max-time 30 "' .. url .. '" -o "' .. dest_path .. '"'
      print("catbeats installer: " .. cmd)
      local ok = os.execute(cmd)
      if ok ~= 0 and ok ~= true then
        errors = errors + 1
        print("catbeats installer: failed to download " .. url)
      end
      clock.sleep(0.1)
    end

    if errors > 0 then
      state = "error"
      status_msg = errors .. " file(s) failed"
    else
      state = "done"
    end
    redraw()
  end)
end

-- -------------------------
-- norns hooks
-- -------------------------

function init()
  math.randomseed(os.time())
  init_cats()
  start_anim()
  -- auto-fetch on boot
  clock.run(function()
    clock.sleep(0.5)
    fetch_manifest()
  end)
end

function enc(n, d)
  if n == 2 and state == "ready" then
    selected = util.clamp(selected + d, 1, math.max(1, #scripts))
    redraw()
  end
end

function key(n, z)
  if z == 1 then
    if n == 2 then
      fetch_manifest()
    elseif n == 3 then
      if state == "ready" then
        install_selected()
      elseif state == "done" then
        state = "ready"
        redraw()
      end
    end
  end
end

function cleanup()
  if anim_clock then clock.cancel(anim_clock) end
end
