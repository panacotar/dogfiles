-- Personal hot corners. Times are milliseconds; size is in logical pixels.
local settings = {
  enabled = true,
  interval_ms = 250,
  dwell_ms = 1000,
  size = 5,
  corners = {
    top_left = false,
    top_right = false,
    bottom_left = "display_off",
    bottom_right = false,
  },
}

-- A normal config reload tears down Lua timers. Also handle loading this file
-- twice within one Lua state without leaving a second timer behind.
if _dogfiles_hotcorners_timer then
  _dogfiles_hotcorners_timer:set_enabled(false)
  _dogfiles_hotcorners_timer = nil
end
if not settings.enabled then return end

local actions = {
  display_off = function()
    hl.dispatch(hl.dsp.dpms({ action = "disable" }))
  end,
}

local interval = math.max(50, settings.interval_ms)
local dwell = math.max(interval, settings.dwell_ms)
local size = math.max(1, settings.size)
for _, action in pairs(settings.corners) do
  assert(not action or actions[action], "Unknown hot-corner action: " .. tostring(action))
end

local armed = false -- On load, first leave the corner before it can fire.
local candidate, elapsed = nil, 0

local function current_corner()
  local cursor = hl.get_cursor_pos()
  local monitor = hl.get_monitor_at_cursor()
  if not cursor or not monitor or monitor.is_mirror or not monitor.dpms_status then
    return nil, nil, false
  end

  -- The Lua API exposes untransformed physical dimensions. Match Hyprland's
  -- logical bounds: rotate, divide by scale, then round to the nearest pixel.
  local width, height = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then width, height = height, width end
  width = math.floor(width / monitor.scale + 0.5)
  height = math.floor(height / monitor.scale + 0.5)
  local x, y = cursor.x - monitor.x, cursor.y - monitor.y
  if x < 0 or y < 0 or x >= width or y >= height then return nil, nil, false end

  local side = x < size and "left" or (x >= width - size and "right" or nil)
  local edge = y < size and "top" or (y >= height - size and "bottom" or nil)
  local corner = side and edge and edge .. "_" .. side
  local action = corner and settings.corners[corner]
  if not action then return nil, nil, true end
  -- Changing monitor geometry restarts the dwell instead of inheriting it.
  local key = table.concat({ monitor.name, monitor.x, monitor.y, width, height, corner }, ":")
  return key, action, true
end

_dogfiles_hotcorners_timer = hl.timer(function()
  local key, action, awake = current_corner()
  if not awake then
    armed, candidate, elapsed = false, nil, 0
  elseif not key then
    armed, candidate, elapsed = true, nil, 0
  elseif armed then
    if candidate ~= key then
      candidate, elapsed = key, 0
    else
      elapsed = elapsed + interval
      if elapsed >= dwell then
        armed, candidate, elapsed = false, nil, 0
        actions[action]()
      end
    end
  end
end, { timeout = interval, type = "repeat" })
