--------
-- Device input, control bindings, controls bridge and Controls tab.
--------

---@type BeamNGOrbitCameraSettings
local Settings = {}

---@class BeamNGOrbitCameraInput
local M = {}

local ORBIT_YAW_SPEED_RAD = math.rad(100)
local ORBIT_PITCH_SPEED_RAD = math.rad(50)
local MOUSE_ORBIT_SENSITIVITY_RAD = math.rad(0.12)
local MOUSE_ZOOM_WHEEL_STEP = 0.75
local UINT32_WRAP = 4294967296

-- Button actions are intentionally device-agnostic. A single ControlButton can
-- keep keyboard, gamepad and controller/wheel bindings at the same time.
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

-- Zoom modifier belongs specifically to the analogue gamepad schemes.
local zoomModifierButton = ac.ControlButton('beamng_orbit_camera.zoom_modifier_gamepad', { hold = false })

local commonControlFlags = ui.ControlButtonControlFlags.AlterRealConfig
  + ui.ControlButtonControlFlags.NoHoldSwitch

local gamepadControlFlags = commonControlFlags
  + ui.ControlButtonControlFlags.SingleEntry
  + ui.ControlButtonControlFlags.Gamepad

local controlsBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.controls_bridge'),
  seqNum = ac.StructItem.uint32(),

  yawTotalRad = ac.StructItem.double(),
  pitchTotalRad = ac.StructItem.double(),
  zoomTotal = ac.StructItem.double(),
  zoomDistanceTotal = ac.StructItem.double(),

  recenterSeqNum = ac.StructItem.uint32(),
  recenterKeepValuesSeqNum = ac.StructItem.uint32(),

  glanceLeft = ac.StructItem.boolean(),
  glanceRight = ac.StructItem.boolean(),
  glanceBack = ac.StructItem.boolean(),
}, false, ac.SharedNamespace.Shared)

local yawTotalRad = controlsBridge.yawTotalRad or 0
local pitchTotalRad = controlsBridge.pitchTotalRad or 0
local zoomTotal = controlsBridge.zoomTotal or 0
local zoomDistanceTotal = controlsBridge.zoomDistanceTotal or 0
local lastGlanceLeft = controlsBridge.glanceLeft == true
local lastGlanceRight = controlsBridge.glanceRight == true
local lastGlanceBack = controlsBridge.glanceBack == true

-- Direct per-App-update input is consumed by the independent OBS core instance.
-- The same input is also accumulated in controlsBridge for the chaser-camera,
-- so different update cadences cannot lose button/axis movement.
M.cameraInput = {
  yawStepRad = 0.0,
  pitchStepRad = 0.0,
  zoomStep = 0.0,
  zoomDistanceStep = 0.0,
  recenterPressed = false,
  recenterKeepValuesPressed = false,
  glanceLeft = false,
  glanceRight = false,
  glanceBack = false,
}

---@param settings BeamNGOrbitCameraSettings
function M.setSettings(settings)
  Settings = settings
end

local fullWidthSize = vec2()

---@param value number
---@param deadzone number
---@param exponent number
---@return number
local function shapeGamepadAxis(value, deadzone, exponent)
  local magnitude = math.abs(value or 0)
  if magnitude <= deadzone then return 0 end

  local normalized = math.min(1, (magnitude - deadzone) / (1 - deadzone))
  return math.sign(value) * normalized ^ exponent
end

---@param stickIndex integer 0 — Left, 1 — Right
---@return number x, number y
local function readGamepadStick(stickIndex)
  if type(ac.getGamepadAxisValue) ~= 'function' then return 0, 0 end

  local xAxis
  local yAxis
  if stickIndex == 0 then
    xAxis = ac.GamepadAxis and ac.GamepadAxis.LeftThumbX or 2
    yAxis = ac.GamepadAxis and ac.GamepadAxis.LeftThumbY or 3
  else
    xAxis = ac.GamepadAxis and ac.GamepadAxis.RightThumbX or 4
    yAxis = ac.GamepadAxis and ac.GamepadAxis.RightThumbY or 5
  end

  return ac.getGamepadAxisValue(0, xAxis) or 0, ac.getGamepadAxisValue(0, yAxis) or 0
end

---@param stickIndex integer 0 — Left, 1 — Right
---@return number
local function readZoomAxis(stickIndex)
  local _, y = readGamepadStick(stickIndex)
  return -shapeGamepadAxis(
    y,
    Settings.get('zoomStickDeadzone'),
    Settings.get('zoomStickExponent')
  )
end

---@return number yawInput, number pitchInput
local function readGamepadOrbit()
  if Settings.get('gamepadControlScheme') == 0 then return 0, 0 end

  local x, y = readGamepadStick(1)
  return -shapeGamepadAxis(
    x,
    Settings.get('orbitStickDeadzone'),
    Settings.get('orbitStickExponent')
  ), -shapeGamepadAxis(
    y,
    Settings.get('orbitStickDeadzone'),
    Settings.get('orbitStickExponent')
  )
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

---@param dt number
function M.update(dt)
  local cameraInput = M.cameraInput
  local gamepadYawInput, gamepadPitchInput = readGamepadOrbit()
  local buttonYawInput, buttonPitchInput = readButtonOrbit()

  local gamepadControlScheme = Settings.get('gamepadControlScheme')
  local gamepadZoomInput = 0

  if zoomModifierButton:down() then
    if gamepadControlScheme == 2 then
      -- Right Stick — Orbit; Zoom modifier + Left Stick Y — Zoom.
      gamepadZoomInput = readZoomAxis(0)
    elseif gamepadControlScheme == 3 then
      -- Right Stick — Orbit; Zoom modifier + Right Stick Y — Zoom.
      gamepadYawInput = 0
      gamepadPitchInput = 0
      gamepadZoomInput = readZoomAxis(1)
    elseif gamepadControlScheme == 4 then
      -- Right Stick — Orbit; Zoom modifier + Right Stick — Zoom + Yaw.
      gamepadPitchInput = 0
      gamepadZoomInput = readZoomAxis(1)
    end
  end

  local yawInput = math.clamp(gamepadYawInput + buttonYawInput, -1, 1)
  local pitchInput = math.clamp(gamepadPitchInput + buttonPitchInput, -1, 1)
  local zoomInput = math.clamp(gamepadZoomInput + readButtonZoom(), -1, 1)

  cameraInput.yawStepRad = yawInput * ORBIT_YAW_SPEED_RAD * dt
  cameraInput.pitchStepRad = pitchInput * ORBIT_PITCH_SPEED_RAD * dt
  cameraInput.zoomStep = zoomInput * dt
  cameraInput.zoomDistanceStep = 0

  if Settings.get('mouseControlScheme') == 1 and ui.mouseDown(ui.MouseButton.Right) then
    local mouseDelta = ac.accessMouseDelta('camera', true, false)
    local mouseWheelDelta = ui.mouseWheel()

    cameraInput.yawStepRad = cameraInput.yawStepRad
      - mouseDelta.x * MOUSE_ORBIT_SENSITIVITY_RAD
    cameraInput.pitchStepRad = cameraInput.pitchStepRad
      + mouseDelta.y * MOUSE_ORBIT_SENSITIVITY_RAD
    cameraInput.zoomDistanceStep = -mouseWheelDelta * MOUSE_ZOOM_WHEEL_STEP
  end

  cameraInput.recenterPressed = recenterButton:pressed()
  cameraInput.recenterKeepValuesPressed = recenterKeepValuesButton:pressed()
  cameraInput.glanceLeft = glanceLeftButton:down()
  cameraInput.glanceRight = glanceRightButton:down()
  cameraInput.glanceBack = glanceBackButton:down()

  yawTotalRad = yawTotalRad + cameraInput.yawStepRad
  pitchTotalRad = pitchTotalRad + cameraInput.pitchStepRad
  zoomTotal = zoomTotal + cameraInput.zoomStep
  zoomDistanceTotal = zoomDistanceTotal + cameraInput.zoomDistanceStep
end

function M.writeToBridge()
  local cameraInput = M.cameraInput

  controlsBridge.yawTotalRad = yawTotalRad
  controlsBridge.pitchTotalRad = pitchTotalRad
  controlsBridge.zoomTotal = zoomTotal
  controlsBridge.zoomDistanceTotal = zoomDistanceTotal

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
  ui.sameLine(230)
  fullWidthSize:set(ui.availableSpaceX(), 0)
  button:control(fullWidthSize, commonControlFlags)
  if ui.itemHovered() then ui.setTooltip(description) end
end

local function drawZoomModifierBinding()
  ui.text('Zoom modifier')
  ui.sameLine(230)
  fullWidthSize:set(ui.availableSpaceX(), 0)
  zoomModifierButton:control(fullWidthSize, gamepadControlFlags)
  if ui.itemHovered() then
    ui.setTooltip('Hold this button to activate zoom in control schemes that include it.')
  end
end

function M.drawControlsTab()
  ui.text('Bindings')
  ui.separator()

  drawBinding('Yaw left', 'Rotate camera left. Supports keyboard, gamepad and controllers.', orbitLeftButton)
  drawBinding('Yaw right', 'Rotate camera right. Supports keyboard, gamepad and controllers.', orbitRightButton)
  drawBinding('Pitch down', 'Rotate camera down. Supports keyboard, gamepad and controllers.', orbitDownButton)
  drawBinding('Pitch up', 'Rotate camera up. Supports keyboard, gamepad and controllers.', orbitUpButton)
  drawBinding('Zoom out', 'Increase camera distance. Supports keyboard, gamepad and controllers.', zoomOutButton)
  drawBinding('Zoom in', 'Decrease camera distance. Supports keyboard, gamepad and controllers.', zoomInButton)
  drawBinding('Recenter', 'Returns yaw, pitch and camera distance. Supports keyboard, gamepad and controllers.', recenterButton)
  drawBinding(
    'Recenter, keep pitch/distance',
    'Returns yaw while preserving the current pitch and camera distance. Supports keyboard, gamepad and controllers.',
    recenterKeepValuesButton
  )

  ui.newLine()
  ui.text('Gamepad')
  ui.separator()

  Settings.drawScheme('gamepadControlScheme', false)

  local controlScheme = Settings.get('gamepadControlScheme')
  if controlScheme >= 2 then
    drawZoomModifierBinding()
  end

  if controlScheme ~= 0 then
    ui.treeNode('Advanced', function()
      Settings.drawSlider('orbitStickDeadzone', true)
      Settings.drawSlider('orbitStickExponent', true)

      if controlScheme >= 2 then
        Settings.drawSlider('zoomStickDeadzone', true)
        Settings.drawSlider('zoomStickExponent', true)
      end
    end)
  end

  ui.newLine()
  ui.text('Mouse')
  ui.separator()

  Settings.drawScheme('mouseControlScheme', false)
end

return M
