-- Run from dogfiles: lua tests/test_hotcorners.lua
local module = arg[1] or (arg[0]:match("^(.*)/tests/") or ".") .. "/omarchy/config/hypr/hotcorners.lua"
local source = assert(io.open(module)):read("*a")
local callback, timer, cursor, monitor, dispatches
local function reset(overrides)
  cursor = { x = 100, y = 100 }
  monitor = { name = "eDP-1", x = 0, y = 0, width = 1920, height = 1080,
    scale = 1.5, transform = 0, dpms_status = true, is_mirror = false }
  dispatches = 0
  hl = {
    get_cursor_pos = function() return cursor end,
    get_monitor_at_cursor = function() return monitor end,
    dsp = { dpms = function(spec) assert(spec.action == "disable"); return spec end },
    dispatch = function() dispatches = dispatches + 1 end,
    timer = function(fn, opts)
      assert(opts.timeout == 250 and opts.type == "repeat")
      callback = fn
      timer = { enabled = true, set_enabled = function(self, value) self.enabled = value end }
      return timer
    end,
  }
  _dogfiles_hotcorners_timer = nil
  assert(load(overrides and overrides(source) or source))()
end
local function tick(n) for _ = 1, n or 1 do callback() end end
local function enter() cursor = { x = 1, y = 719 }; tick() end
local checks = 0
local function check(name, fn) fn(); checks = checks + 1; print("ok: " .. name) end
check("one-second dwell and one activation per visit", function()
  reset(); tick(); enter(); tick(3); assert(dispatches == 0)
  tick(); assert(dispatches == 1); tick(12); assert(dispatches == 1)
  cursor.x = 100; tick(); enter(); tick(4); assert(dispatches == 2)
end)
check("leaving the corner cancels the dwell", function()
  reset(); tick(); enter(); tick(2); cursor.x = 100; tick()
  enter(); tick(3); assert(dispatches == 0); tick(); assert(dispatches == 1)
end)
check("startup in a corner requires leaving first", function()
  reset(); enter(); tick(10); assert(dispatches == 0)
  cursor.x = 100; tick(); enter(); tick(4); assert(dispatches == 1)
end)
check("other corners are disabled", function()
  reset(); tick()
  for _, point in ipairs({{1,1}, {1279,1}, {1279,719}}) do
    cursor = {x=point[1], y=point[2]}; tick(8)
  end
  assert(dispatches == 0)
end)
check("dark displays cannot trigger; waking in corner cannot retrigger", function()
  reset(); tick(); monitor.dpms_status = false; enter(); tick(8)
  monitor.dpms_status = true; tick(8); assert(dispatches == 0)
  cursor.x = 100; tick(); enter(); tick(4); assert(dispatches == 1)
end)
check("scaled rotated monitor with negative origin", function()
  reset(); tick(); monitor.x = -1000; monitor.y = -300; monitor.transform = 1
  cursor = {x=-999, y=979}; tick(); tick(4); assert(dispatches == 1)
end)
check("all transforms and fractional scales", function()
  for transform = 0, 7 do
    reset(); tick(); monitor.transform = transform; monitor.scale = 1.25
    local height = transform % 2 == 1 and 1920 or 1080
    cursor = {x=1, y=math.floor(height/1.25+0.5)-1}; tick(); tick(4)
    assert(dispatches == 1, "transform " .. transform)
  end
end)
check("geometry changes restart the dwell", function()
  reset(); tick(); enter(); tick(3); monitor.x = -1; tick()
  assert(dispatches == 0); tick(3); assert(dispatches == 0); tick(); assert(dispatches == 1)
end)
check("missing and mirrored monitors do not fire", function()
  reset(); monitor.is_mirror = true; enter(); tick(8); assert(dispatches == 0)
  monitor = nil; tick(); cursor = nil; tick()
end)
check("reload disables the previous timer and resets arming", function()
  reset(); tick(); enter(); tick(3); local previous = timer
  assert(load(source))(); assert(not previous.enabled); tick(8); assert(dispatches == 0)
end)
check("disabled configuration creates no timer", function()
  reset(function(s) return s:gsub("enabled = true,", "enabled = false,", 1) end)
  assert(_dogfiles_hotcorners_timer == nil)
end)
print(checks .. " checks passed")
