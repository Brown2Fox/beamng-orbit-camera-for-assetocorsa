
---@type BeamNGOrbitCameraSettingsModule?
local Settings = nil

---@class BeamNGOrbitCameraInputModule
local M = {}

local cspMajor, cspMinor = (ac.getPatchVersion() or ''):match('^(%d+)%.(%d+)')
local supportsMouse = (tonumber(cspMajor) or 0) > 0 or (tonumber(cspMinor) or 0) >= 3

local ORBIT_YAW_SPEED_RAD = math.rad(100)
local ORBIT_PITCH_SPEED_RAD = math.rad(50)
local MOUSE_ORBIT_SENSITIVITY_RAD = math.rad(0.12)
local MOUSE_ZOOM_WHEEL_STEP = 0.75
local MOUSE_FOV_WHEEL_STEP = 0.08
local MOUSE_DOLLY_WHEEL_STEP = 0.1
local WHEEL_ACTION_FOV = 1
local WHEEL_ACTION_DOLLY = 2
local WHEEL_MODIFIER_KEYS = {
  [1] = ui.KeyIndex.Control,
  [2] = ui.KeyIndex.Menu,
  [3] = ui.KeyIndex.Shift,
}
local UINT32_WRAP = 4294967296

local orbitLeftButton = ac.ControlButton('beamng_orbit_camera.orbit_left', { keyboard = { key = ac.KeyIndex.NumPad4 }, hold = false })
local orbitRightButton = ac.ControlButton('beamng_orbit_camera.orbit_right', { keyboard = { key = ac.KeyIndex.NumPad6 }, hold = false })
local orbitDownButton = ac.ControlButton('beamng_orbit_camera.orbit_down', { keyboard = { key = ac.KeyIndex.NumPad2 }, hold = false })
local orbitUpButton = ac.ControlButton('beamng_orbit_camera.orbit_up', { keyboard = { key = ac.KeyIndex.NumPad8 }, hold = false })
local zoomOutButton = ac.ControlButton('beamng_orbit_camera.zoom_out', { keyboard = { key = ac.KeyIndex.NumPad3 }, hold = false })
local zoomInButton = ac.ControlButton('beamng_orbit_camera.zoom_in', { keyboard = { key = ac.KeyIndex.NumPad9 }, hold = false })
local recenterButton = ac.ControlButton('beamng_orbit_camera.recenter', { keyboard = { key = ac.KeyIndex.NumPad5 }, hold = false })
local recenterKeepValuesButton = ac.ControlButton('beamng_orbit_camera.recenter_keep_values', { keyboard = { key = ac.KeyIndex.NumPad5, ctrl = true }, hold = false })

local glanceLeftButton = ac.ControlButton('GLANCELEFT')
local glanceRightButton = ac.ControlButton('GLANCERIGHT')
local glanceBackButton = ac.ControlButton('GLANCEBACK')

local zoomModifierButton = ac.ControlButton('beamng_orbit_camera.zoom_modifier_gamepad', { hold = false })

---@type integer
local commonControlFlags = ui.ControlButtonControlFlags.AlterRealConfig
  + ui.ControlButtonControlFlags.NoHoldSwitch

---@type integer
local gamepadControlFlags = commonControlFlags
  + ui.ControlButtonControlFlags.SingleEntry
  + ui.ControlButtonControlFlags.Gamepad

---@class ControlsBridgeLayout
---@field seqNum integer
---@field yawTotalRad number
---@field pitchTotalRad number
---@field zoomTotal number
---@field zoomDistanceTotal number
---@field zoomFovTotal number
---@field zoomDollyTotal number
---@field recenterSeqNum integer
---@field recenterKeepValuesSeqNum integer
---@field glanceLeft boolean
---@field glanceRight boolean
---@field glanceBack boolean

---@type ControlsBridgeLayout
local controlsBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.controls_bridge_v2'),
  seqNum = ac.StructItem.uint32(),

  yawTotalRad = ac.StructItem.double(),
  pitchTotalRad = ac.StructItem.double(),
  zoomTotal = ac.StructItem.double(),
  zoomDistanceTotal = ac.StructItem.double(),
  zoomFovTotal = ac.StructItem.double(),
  zoomDollyTotal = ac.StructItem.double(),

  recenterSeqNum = ac.StructItem.uint32(),
  recenterKeepValuesSeqNum = ac.StructItem.uint32(),

  glanceLeft = ac.StructItem.boolean(),
  glanceRight = ac.StructItem.boolean(),
  glanceBack = ac.StructItem.boolean(),
}, false, ac.SharedNamespace.Shared)

local yawTotalRad = controlsBridge.yawTotalRad or 0.0 ---@type number
local pitchTotalRad = controlsBridge.pitchTotalRad or 0.0 ---@type number
local zoomTotal = controlsBridge.zoomTotal or 0.0 ---@type number
local zoomDistanceTotal = controlsBridge.zoomDistanceTotal or 0.0 ---@type number
local zoomFovTotal = controlsBridge.zoomFovTotal or 0.0 ---@type number
local zoomDollyTotal = controlsBridge.zoomDollyTotal or 0.0 ---@type number

---@type boolean
local rightDragWasDown = false
---@type boolean
local rightDragStartedFree = false

---@type BeamNGOrbitCameraInput
M.cameraInput = {
  yawStepRad = 0.0,
  pitchStepRad = 0.0,
  zoomStep = 0.0,
  zoomDistanceStep = 0.0,
  zoomFovStep = 0.0,
  zoomDollyStep = 0.0,
  recenterPressed = false,
  recenterKeepValuesPressed = false,
  glanceLeft = false,
  glanceRight = false,
  glanceBack = false,
}

---@param settings BeamNGOrbitCameraSettingsModule
function M.setSettings(settings)
  Settings = settings
end

local fullWidthSize = vec2()

local gamepadIndex = 0

local function reloadGamepadIndex()
  gamepadIndex = ac.INIConfig.controlsConfig():get('X360', 'JOYPAD_INDEX', 0)
end

reloadGamepadIndex()
ac.onControlSettingsChanged(reloadGamepadIndex)

---@param stickIndex integer # 0 — Left, 1 — Right
---@return number x, number y
local function readGamepadStick(stickIndex)
  if type(ac.getGamepadAxisValue) ~= 'function' then return 0, 0 end

  local xAxis = 0.0
  local yAxis = 0.0
  if stickIndex == 0 then
    xAxis = ac.GamepadAxis and ac.GamepadAxis.LeftThumbX or 2
    yAxis = ac.GamepadAxis and ac.GamepadAxis.LeftThumbY or 3
  else
    xAxis = ac.GamepadAxis and ac.GamepadAxis.RightThumbX or 4
    yAxis = ac.GamepadAxis and ac.GamepadAxis.RightThumbY or 5
  end

  return ac.getGamepadAxisValue(gamepadIndex, xAxis) or 0, ac.getGamepadAxisValue(gamepadIndex, yAxis) or 0
end

---@param stickIndex integer # 0 — Left, 1 — Right
---@return number
local function readZoomAxis(stickIndex)
  if Settings == nil then return 0 end

  local deadzone = Settings.get('zoomStickDeadzone')

  local _, yRaw = readGamepadStick(stickIndex)
  if math.abs(yRaw) <= deadzone then return 0 end

  local y = -yRaw
  return y
end

---@return number yawInput, number pitchInput
local function readGamepadOrbit()
  if Settings == nil then return 0, 0 end

  if Settings.get('gamepadControlScheme') == 0 then return 0, 0 end

  local deadzone = Settings.get('orbitStickDeadzone')

  local xRaw, yRaw = readGamepadStick(1)
  if xRaw*xRaw + yRaw*yRaw <= deadzone*deadzone then return 0, 0 end

  local x = -xRaw
  local y = -yRaw
  return x, y
end

---@return number yawInput, number pitchInput
local function readButtonOrbit()
  local yaw = 0
  local pitch = 0

  if orbitLeftButton:down() then yaw = yaw + 1 end
  if orbitRightButton:down() then yaw = yaw - 1 end
  if orbitUpButton:down() then pitch = pitch + 1 end
  if orbitDownButton:down() then pitch = pitch - 1 end

  return yaw, pitch
end

---@return number
local function readButtonZoom()
  local zoom = 0
  if zoomOutButton:down() then zoom = zoom + 1 end
  if zoomInButton:down() then zoom = zoom - 1 end
  return zoom
end

---@param a number
---@param b number
---@return number
local function maxAbs(a, b)
  return math.abs(a) > math.abs(b) and a or b
end

---@return integer
local function readWheelAction()
  if Settings == nil then return 0 end
  for i = 1, 2 do
    local key = WHEEL_MODIFIER_KEYS[Settings.get('wheelModifier' .. i .. 'Key')]
    if key ~= nil and ac.isKeyDown(key) then
      return Settings.get('wheelModifier' .. i .. 'Action')
    end
  end
  return Settings.get('wheelAction')
end

-- Wheel up makes the car bigger (closer or narrower); for the dolly zoom it moves closer and wider.
---@param wheelDelta number
local function applyMouseWheel(wheelDelta)
  if wheelDelta == 0 then return end
  wheelDelta = wheelDelta * Settings.get('zoomSens')

  local cameraInput = M.cameraInput
  local action = readWheelAction()
  if action == WHEEL_ACTION_FOV then
    cameraInput.zoomFovStep = -wheelDelta * MOUSE_FOV_WHEEL_STEP
  elseif action == WHEEL_ACTION_DOLLY then
    cameraInput.zoomDollyStep = -wheelDelta * MOUSE_DOLLY_WHEEL_STEP
  else
    cameraInput.zoomDistanceStep = -wheelDelta * MOUSE_ZOOM_WHEEL_STEP
  end
end

---@param dt number
function M.update(dt)
  if Settings == nil then return end

  local cameraInput = M.cameraInput
  local gamepadYawInput, gamepadPitchInput = readGamepadOrbit()
  local buttonYawInput, buttonPitchInput = readButtonOrbit()
  local buttonZoomInput = readButtonZoom()

  local orbitSens = Settings.get('orbitSens')
  local zoomSens = Settings.get('zoomSens')

  local gamepadControlScheme = Settings.get('gamepadControlScheme')
  local gamepadZoomInput = 0.0

  if zoomModifierButton:down() then
    if gamepadControlScheme == 2 then
      gamepadZoomInput = readZoomAxis(0)
    elseif gamepadControlScheme == 3 then
      gamepadYawInput = 0
      gamepadPitchInput = 0
      gamepadZoomInput = readZoomAxis(1)
    elseif gamepadControlScheme == 4 then
      gamepadPitchInput = 0
      gamepadZoomInput = readZoomAxis(1)
    end
  end

  local yawInput = maxAbs(gamepadYawInput, math.clamp(buttonYawInput, -1, 1)) * orbitSens
  local pitchInput = maxAbs(gamepadPitchInput, math.clamp(buttonPitchInput, -1, 1)) * orbitSens
  local zoomInput = maxAbs(gamepadZoomInput, math.clamp(buttonZoomInput, -1, 1)) * zoomSens

  cameraInput.yawStepRad = yawInput * ORBIT_YAW_SPEED_RAD * dt
  cameraInput.pitchStepRad = pitchInput * ORBIT_PITCH_SPEED_RAD * dt
  cameraInput.zoomStep = zoomInput * dt
  cameraInput.zoomDistanceStep = 0
  cameraInput.zoomFovStep = 0
  cameraInput.zoomDollyStep = 0

  local mouseControlScheme = supportsMouse and Settings.get('mouseControlScheme') or 0
  local rightMouseDown = mouseControlScheme ~= 0 and ui.mouseDown(ui.MouseButton.Right)
  if rightMouseDown and not rightDragWasDown then
    -- Latch whether this press started over the world, not over an app window.
    rightDragStartedFree = not ui.mouseBusy()
  end
  rightDragWasDown = rightMouseDown and true or false
  local rightDragOrbit = rightMouseDown and rightDragStartedFree
  if rightDragOrbit then
    local mouseDelta = ac.accessMouseDelta('camera', true, false) ---@type vec2

    cameraInput.yawStepRad = cameraInput.yawStepRad
      - mouseDelta.x * MOUSE_ORBIT_SENSITIVITY_RAD * orbitSens
    cameraInput.pitchStepRad = cameraInput.pitchStepRad
      + mouseDelta.y * MOUSE_ORBIT_SENSITIVITY_RAD * orbitSens
  end
  if rightDragOrbit or mouseControlScheme == 2 and not ui.mouseBusy() then
    applyMouseWheel(ui.mouseWheel())
  end

  cameraInput.recenterPressed = recenterButton:pressed()
  cameraInput.recenterKeepValuesPressed = recenterKeepValuesButton:pressed()
  local glanceEnabled = Settings.get('disableGlance') == 0
  cameraInput.glanceLeft = glanceEnabled and glanceLeftButton:down()
  cameraInput.glanceRight = glanceEnabled and glanceRightButton:down()
  cameraInput.glanceBack = glanceEnabled and glanceBackButton:down()

  yawTotalRad = yawTotalRad + cameraInput.yawStepRad
  pitchTotalRad = pitchTotalRad + cameraInput.pitchStepRad
  zoomTotal = zoomTotal + cameraInput.zoomStep
  zoomDistanceTotal = zoomDistanceTotal + cameraInput.zoomDistanceStep
  zoomFovTotal = zoomFovTotal + cameraInput.zoomFovStep
  zoomDollyTotal = zoomDollyTotal + cameraInput.zoomDollyStep
end

function M.writeToBridge()
  local cameraInput = M.cameraInput

  controlsBridge.yawTotalRad = yawTotalRad
  controlsBridge.pitchTotalRad = pitchTotalRad
  controlsBridge.zoomTotal = zoomTotal
  controlsBridge.zoomDistanceTotal = zoomDistanceTotal
  controlsBridge.zoomFovTotal = zoomFovTotal
  controlsBridge.zoomDollyTotal = zoomDollyTotal

  if cameraInput.recenterPressed then
    controlsBridge.recenterSeqNum = (controlsBridge.recenterSeqNum + 1) % UINT32_WRAP
  end
  if cameraInput.recenterKeepValuesPressed then
    controlsBridge.recenterKeepValuesSeqNum = (controlsBridge.recenterKeepValuesSeqNum + 1) % UINT32_WRAP
  end

  controlsBridge.glanceLeft = cameraInput.glanceLeft
  controlsBridge.glanceRight = cameraInput.glanceRight
  controlsBridge.glanceBack = cameraInput.glanceBack

  controlsBridge.seqNum = (controlsBridge.seqNum + 1) % UINT32_WRAP
end

function M.reset()
  local cameraInput = M.cameraInput

  cameraInput.yawStepRad = 0.0
  cameraInput.pitchStepRad = 0.0
  cameraInput.zoomStep = 0.0
  cameraInput.zoomDistanceStep = 0.0
  cameraInput.zoomFovStep = 0.0
  cameraInput.zoomDollyStep = 0.0
  cameraInput.recenterPressed = false
  cameraInput.recenterKeepValuesPressed = false
  cameraInput.glanceLeft = false
  cameraInput.glanceRight = false
  cameraInput.glanceBack = false
end

---@param label string
---@param description string
---@param button ac.ControlButton
local function drawBinding(label, description, button)
  ui.text(label)
  ui.sameLine(Settings.LABEL_COL)
  fullWidthSize:set(ui.availableSpaceX(), 0)
  ---@cast commonControlFlags ui.ControlButtonControlFlags
  button:control(fullWidthSize, commonControlFlags)
  if ui.itemHovered() then ui.setTooltip(description) end
end

local function drawZoomModifierBinding()
  ui.text('Zoom button')
  ui.sameLine(Settings.LABEL_COL)
  fullWidthSize:set(ui.availableSpaceX(), 0)
  ---@cast gamepadControlFlags ui.ControlButtonControlFlags
  zoomModifierButton:control(fullWidthSize, gamepadControlFlags)
  if ui.itemHovered() then
    ui.setTooltip('Hold while using the stick to zoom.')
  end
end

local function drawGamepad()
  local scheme = Settings.get('gamepadControlScheme')

  Settings.drawRowLabel('Orbit')
  local orbitPicked = Settings.drawSegmented({ 'Off', 'Right stick' }, scheme == 0 and 1 or 2)
  if orbitPicked ~= nil then Settings.set('gamepadControlScheme', orbitPicked == 1 and 0 or 1) end
  if scheme == 0 then return end

  Settings.drawRowLabel('Zoom with')
  local zoomPicked = Settings.drawSegmented({ 'None', 'Left stick', 'Right stick', 'Right + turn' }, scheme)
  if zoomPicked ~= nil then Settings.set('gamepadControlScheme', zoomPicked) end
  if ui.itemHovered() then
    ui.setTooltip('Hold the zoom button, then use the stick up/down. "Right + turn" also turns the camera.')
  end
  if scheme >= 2 then drawZoomModifierBinding() end

  Settings.drawSlider('orbitStickDeadzone', true)
  if scheme >= 2 then Settings.drawSlider('zoomStickDeadzone', true) end
end

local function drawWheel()
  Settings.drawScheme('wheelAction', false)
  for i = 1, 2 do
    Settings.drawScheme('wheelModifier' .. i .. 'Key', false)
    if Settings.get('wheelModifier' .. i .. 'Key') ~= 0 then
      Settings.drawScheme('wheelModifier' .. i .. 'Action', false)
    end
  end
end

local function drawMouseOptions()
  Settings.drawRowLabel('Orbit')
  local scheme = Settings.get('mouseControlScheme')
  local orbitPicked = Settings.drawSegmented({ 'Off', 'Right-drag' }, scheme == 0 and 1 or 2)
  if orbitPicked ~= nil then Settings.set('mouseControlScheme', orbitPicked == 1 and 0 or 1) end
  if scheme == 0 then return end

  Settings.drawRowLabel('Wheel zooms')
  local wheelPicked = Settings.drawSegmented({ 'Only while dragging', 'Always' }, scheme)
  if wheelPicked ~= nil then Settings.set('mouseControlScheme', wheelPicked) end
end

local function drawKeys()
  drawBinding('Orbit left', 'Keyboard, gamepad or wheel buttons.', orbitLeftButton)
  drawBinding('Orbit right', 'Keyboard, gamepad or wheel buttons.', orbitRightButton)
  drawBinding('Tilt down', 'Keyboard, gamepad or wheel buttons.', orbitDownButton)
  drawBinding('Tilt up', 'Keyboard, gamepad or wheel buttons.', orbitUpButton)
  drawBinding('Zoom out', 'Keyboard, gamepad or wheel buttons.', zoomOutButton)
  drawBinding('Zoom in', 'Keyboard, gamepad or wheel buttons.', zoomInButton)
  drawBinding('Straighten', 'Back behind the car, with the slider values.', recenterButton)
  drawBinding('Straighten, keep view', 'Back behind the car, keeping the current distance, lens and angle.', recenterKeepValuesButton)
end

---@return string
function M.controlsSummary()
  local parts = {}
  if supportsMouse and Settings.get('mouseControlScheme') ~= 0 then parts[#parts + 1] = 'Right-drag orbit · wheel zoom' end
  if Settings.get('gamepadControlScheme') ~= 0 then parts[#parts + 1] = 'gamepad' end
  return #parts > 0 and table.concat(parts, ' · ') or 'off'
end

function M.drawControlsTab()
  if Settings == nil then return end

  if supportsMouse and Settings.get('mouseControlScheme') ~= 0 then drawWheel() end
  Settings.drawSlider('orbitSens', true)
  Settings.drawSlider('zoomSens', true)

  local gamepad = Settings.get('gamepadControlScheme')
  if supportsMouse then ui.treeNode('Mouse options###mouse', drawMouseOptions) end
  ui.treeNode('Gamepad: ' .. (gamepad == 0 and 'off' or gamepad == 1 and 'orbit' or 'orbit + zoom') .. '###gamepad', drawGamepad)
  ui.treeNode('Keys and buttons###keys', drawKeys)

  Settings.drawCheckbox('disableGlance', false)
  Settings.drawCheckbox('keepViewOnCarSwitch', false)
  if ui.itemHovered() then
    ui.setTooltip('Off: each car starts from your default view. On: the same angle and zoom carry over.')
  end
end

return M
