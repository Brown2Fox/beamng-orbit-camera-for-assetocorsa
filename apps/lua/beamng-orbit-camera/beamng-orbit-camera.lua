--------
-- Camera-parameter and control bridges for BeamNG-style Orbit Camera.
--
-- Camera settings live here so they can be changed while a session is running.
-- All device input is interpreted here. The camera receives only cumulative
-- manual yaw/pitch/zoom results and recenter event counters.
--------

local GAMEPAD_CONTROL_SCHEMES = {
  [0] = 'Disabled',
  [1] = 'Right Stick — Orbit',
  [2] = 'Right Stick — Orbit; Zoom modifier + Left Stick Y — Zoom',
  [3] = 'Right Stick — Orbit; Zoom modifier + Right Stick Y — Zoom',
  [4] = 'Right Stick — Orbit; Zoom modifier + Right Stick — Zoom + Yaw',
}

local MOUSE_CONTROL_SCHEMES = {
  [0] = 'Disabled',
  [1] = 'RMB (Hold) + Move — Orbit; RMB (Hold) + Wheel — Zoom',
}

local ORBIT_YAW_SPEED_RAD = math.rad(100)
local ORBIT_PITCH_SPEED_RAD = math.rad(50)
local MOUSE_ORBIT_SENSITIVITY_RAD = math.rad(0.12)
local MOUSE_ZOOM_WHEEL_STEP = 0.75

local cameraParams = {
  cameraDistance = { displayName = 'Distance', defaultValue = 5.0, minValue = 3.0, maxValue = 30.0, format = '%.1f m', kind = 'slider' },
  cameraFov = { displayName = 'Field of view', defaultValue = 65.0, minValue = 45.0, maxValue = 85.0, format = '%.0f°', kind = 'slider' },
  cameraPitch = { displayName = 'Pitch', defaultValue = 17.0, minValue = -85.0, maxValue = 85.0, format = '%.0f°', kind = 'slider' },
  cameraTargetHeightOffset = { displayName = 'Target height offset', defaultValue = 0.0, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
  cameraRelaxation = { displayName = 'Follow vehicle direction', defaultValue = 6.0, minValue = 0.5, maxValue = 6.0, format = '%.2f', kind = 'slider' },
  dynamicFovAtSpeed = { displayName = 'Dynamic FOV', defaultValue = 40.0, minValue = 0.0, maxValue = 75.0, format = '%.0f°', kind = 'slider' },
  dynamicPitchAtSpeed = { displayName = 'Dynamic pitch', defaultValue = 7.0, minValue = 0.0, maxValue = 25.0, format = '%.1f°', kind = 'slider' },
  dynamicHeightAtSpeed = { displayName = 'Dynamic height', defaultValue = 0.4, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
}

local controlParams = {
  gamepadControlScheme = { displayName = 'Control scheme', defaultValue = 2, options = GAMEPAD_CONTROL_SCHEMES, kind = 'scheme' },
  mouseControlScheme = { displayName = 'Control scheme', defaultValue = 1, options = MOUSE_CONTROL_SCHEMES, kind = 'scheme' },
  orbitStickDeadzone = { displayName = 'Orbit deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  orbitStickExponent = { displayName = 'Orbit exponent', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
  zoomStickDeadzone = { displayName = 'Zoom deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  zoomStickExponent = { displayName = 'Zoom exponent', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
}

local function getParam(key)
  return cameraParams[key] or controlParams[key]
end

local paramStorage = {}

local function registerParams(params)
  for key, param in pairs(params) do
    paramStorage[key] = ac.storage(key, param.defaultValue)
  end
end

registerParams(cameraParams)
registerParams(controlParams)

---@param key string
---@return number
local function getParamValue(key)
  local param = getParam(key)
  local valueNum = tonumber(paramStorage[key]:get())

  if param.kind == 'scheme' then
    return valueNum ~= nil and param.options[valueNum] ~= nil and valueNum or param.defaultValue
  end

  return math.clamp(valueNum or param.defaultValue, param.minValue, param.maxValue)
end

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

-- Zoom modifier belongs specifically to the analogue gamepad schemes.
local zoomModifierButton = ac.ControlButton('beamng_orbit_camera.zoom_modifier_gamepad', { hold = false })

local commonControlFlags = ui.ControlButtonControlFlags.AlterRealConfig
  + ui.ControlButtonControlFlags.NoHoldSwitch

local gamepadControlFlags = commonControlFlags
  + ui.ControlButtonControlFlags.SingleEntry
  + ui.ControlButtonControlFlags.Gamepad

local paramsBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.params_bridge'),
  seqNum = ac.StructItem.uint32(),
  ready = ac.StructItem.boolean(),
  cameraDistance = ac.StructItem.double(),
  cameraFov = ac.StructItem.double(),
  cameraTargetHeightOffset = ac.StructItem.double(),
  cameraPitch = ac.StructItem.double(),
  cameraRelaxation = ac.StructItem.double(),
  dynamicFovAtSpeed = ac.StructItem.double(),
  dynamicPitchAtSpeed = ac.StructItem.double(),
  dynamicHeightAtSpeed = ac.StructItem.double(),
}, false, ac.SharedNamespace.Shared)

local controlsBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.controls_bridge'),
  seqNum = ac.StructItem.uint32(),

  yawTotalRad = ac.StructItem.double(),
  pitchTotalRad = ac.StructItem.double(),
  zoomTotal = ac.StructItem.double(),
  zoomDistanceTotal = ac.StructItem.double(),

  recenterSeqNum = ac.StructItem.uint32(),
  recenterKeepValuesSeqNum = ac.StructItem.uint32(),
}, false, ac.SharedNamespace.Shared)

local yawTotalRad = controlsBridge.yawTotalRad or 0
local pitchTotalRad = controlsBridge.pitchTotalRad or 0
local zoomTotal = controlsBridge.zoomTotal or 0
local zoomDistanceTotal = controlsBridge.zoomDistanceTotal or 0

local MODIFIED_PARAM_COLOR = rgbm.colors.yellow

local function publishParams()
  paramsBridge.ready = false
  paramsBridge.cameraDistance = getParamValue('cameraDistance')
  paramsBridge.cameraFov = getParamValue('cameraFov')
  paramsBridge.cameraTargetHeightOffset = getParamValue('cameraTargetHeightOffset')
  paramsBridge.cameraPitch = getParamValue('cameraPitch')
  paramsBridge.cameraRelaxation = getParamValue('cameraRelaxation')
  paramsBridge.dynamicFovAtSpeed = getParamValue('dynamicFovAtSpeed')
  paramsBridge.dynamicPitchAtSpeed = getParamValue('dynamicPitchAtSpeed')
  paramsBridge.dynamicHeightAtSpeed = getParamValue('dynamicHeightAtSpeed')
  paramsBridge.ready = true
  paramsBridge.seqNum = (tonumber(paramsBridge.seqNum) + 1) % 4294967296
end

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
    getParamValue('zoomStickDeadzone'),
    getParamValue('zoomStickExponent')
  )
end

---@return number yawInput, number pitchInput
local function readGamepadOrbit()
  if getParamValue('gamepadControlScheme') == 0 then return 0, 0 end

  local x, y = readGamepadStick(1)
  return -shapeGamepadAxis(
    x,
    getParamValue('orbitStickDeadzone'),
    getParamValue('orbitStickExponent')
  ), -shapeGamepadAxis(
    y,
    getParamValue('orbitStickDeadzone'),
    getParamValue('orbitStickExponent')
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
local function publishControls(dt)
  local gamepadYawInput, gamepadPitchInput = readGamepadOrbit()
  local buttonYawInput, buttonPitchInput = readButtonOrbit()

  local gamepadControlScheme = getParamValue('gamepadControlScheme')
  local gamepadZoomInput = 0

  if zoomModifierButton:down() then
    if gamepadControlScheme == 2 then
      -- Right Stick — Orbit; Zoom modifier + Left Stick Y — Zoom.
      gamepadZoomInput = readZoomAxis(0)
    elseif gamepadControlScheme == 3 then
      -- Right Stick — Orbit; Zoom modifier + Right Stick Y — Zoom
      gamepadYawInput = 0
      gamepadPitchInput = 0
      gamepadZoomInput = readZoomAxis(1)
    elseif gamepadControlScheme == 4 then
      -- Right Stick — Orbit; Zoom modifier + Right Stick — Zoom + Yaw
      gamepadPitchInput = 0
      gamepadZoomInput = readZoomAxis(1)
    end
  end

  local yawInput = math.clamp(gamepadYawInput + buttonYawInput, -1, 1)
  local pitchInput = math.clamp(gamepadPitchInput + buttonPitchInput, -1, 1)
  local zoomInput = math.clamp(gamepadZoomInput + readButtonZoom(), -1, 1)

  local yawStepRad = yawInput * ORBIT_YAW_SPEED_RAD * dt
  local pitchStepRad = pitchInput * ORBIT_PITCH_SPEED_RAD * dt
  local zoomStep = zoomInput * dt
  local zoomDistanceStep = 0

  local mouseControlScheme = getParamValue('mouseControlScheme')
  if mouseControlScheme == 1 then
     if ui.mouseDown(ui.MouseButton.Right) then
      -- “camera” follows CSP raw-input preference. restorePosition=true returns
      -- the cursor to its original location when RMB is released. force=false
      -- avoids stealing the mouse while another UI element is being operated.
      local mouseDelta = ac.accessMouseDelta('camera', true, false)
      local mouseWheelDelta = ui.mouseWheel() or 0

      yawStepRad = yawStepRad - (mouseDelta.x or 0) * MOUSE_ORBIT_SENSITIVITY_RAD
      pitchStepRad = pitchStepRad + (mouseDelta.y or 0) * MOUSE_ORBIT_SENSITIVITY_RAD
      zoomDistanceStep = -mouseWheelDelta * MOUSE_ZOOM_WHEEL_STEP
    end
  end

  yawTotalRad = yawTotalRad + yawStepRad
  pitchTotalRad = pitchTotalRad + pitchStepRad
  zoomTotal = zoomTotal + zoomStep
  zoomDistanceTotal = zoomDistanceTotal + zoomDistanceStep

  controlsBridge.yawTotalRad = yawTotalRad
  controlsBridge.pitchTotalRad = pitchTotalRad
  controlsBridge.zoomTotal = zoomTotal
  controlsBridge.zoomDistanceTotal = zoomDistanceTotal

  if recenterButton:pressed() then
    controlsBridge.recenterSeqNum = (tonumber(controlsBridge.recenterSeqNum) + 1) % 4294967296
  end
  if recenterKeepValuesButton:pressed() then
    controlsBridge.recenterKeepValuesSeqNum = (tonumber(controlsBridge.recenterKeepValuesSeqNum) + 1) % 4294967296
  end

  -- Commit the entire resolved input snapshot last. Cumulative totals avoid
  -- losing input if Lua App and chaser-camera update cadences differ.
  controlsBridge.seqNum = (tonumber(controlsBridge.seqNum) + 1) % 4294967296
end

---@param key string
---@return boolean
local function isParamModified(key)
  local param = getParam(key)
  if param == nil then return false end

  local value = getParamValue(key)
  if param.kind == 'scheme' then
    return value ~= param.defaultValue
  end

  return math.abs(value - param.defaultValue) > 0.000001
end

---@param key string
local function resetParam(key)
  local param = getParam(key)
  if param == nil then return end
  paramStorage[key]:set(param.defaultValue)
end

local function resetCameraParams()
  for key, param in pairs(cameraParams) do
    paramStorage[key]:set(param.defaultValue)
  end
end

---@param key string
---@param highlightIfModified boolean
local function drawParamLabel(key, highlightIfModified)
  local param = getParam(key)
  if param == nil then return end

  if highlightIfModified and isParamModified(key) then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
    ui.text(param.displayName)
    ui.popStyleColor()
  else
    ui.text(param.displayName)
  end
end

---@param label string
---@param description string
---@param button ac.ControlButton
local function drawBinding(label, description, button)
  ui.text(label)
  ui.sameLine(230)
  button:control(vec2(ui.availableSpaceX(), 0), commonControlFlags)
  if ui.itemHovered() then ui.setTooltip(description) end
end

---@param key string
---@param highlightIfModified boolean
local function drawParamAsSlider(key, highlightIfModified)
  local param = getParam(key)
  if param == nil or param.kind ~= 'slider' then return end

  local valueObj = paramStorage[key]
  local valueNum = tonumber(valueObj:get()) or param.defaultValue
  local needHighlight = highlightIfModified and isParamModified(key)

  drawParamLabel(key, highlightIfModified)
  ui.sameLine(230)

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  local newValue, changed = ui.slider(
    '##' .. key,
    valueNum,
    param.minValue,
    param.maxValue,
    param.format
  )

  if needHighlight then
    ui.popStyleColor()
  end

  if ui.itemHovered() and ui.mouseDown(ui.MouseButton.Right) then
    resetParam(key)
  end

  if changed then
    valueObj:set(newValue)
  end
end

---@param key string
---@param highlightIfModified boolean
local function drawParamAsScheme(key, highlightIfModified)
  local param = getParam(key)
  if param == nil or param.kind ~= 'scheme' then return end

  local valueObj = paramStorage[key]
  local value = getParamValue(key)
  local needHighlight = highlightIfModified and isParamModified(key)

  drawParamLabel(key, highlightIfModified)
  ui.sameLine(230)
  ui.pushItemWidth(ui.availableSpaceX())

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  local comboOpen = ui.beginCombo('##' .. key, param.options[value])

  if needHighlight then
    ui.popStyleColor()
  end

  if ui.itemHovered() and ui.mouseDown(ui.MouseButton.Right) then
    resetParam(key)
  end

  if comboOpen then
    for scheme, name in pairs(param.options) do
      if ui.selectable(name .. '##' .. key .. scheme) then
        valueObj:set(scheme)
      end
    end
    ui.endCombo()
  end

  ui.popItemWidth()
end

local function drawZoomModifierBinding()
  ui.text('Zoom modifier')
  ui.sameLine(230)
  zoomModifierButton:control(vec2(ui.availableSpaceX(), 0), gamepadControlFlags)
  if ui.itemHovered() then
    ui.setTooltip('Hold this button to activate zoom in control schemes that include it.')
  end
end

local function drawCameraTab()
  ui.text('Camera')
  ui.separator()

  drawParamAsSlider('cameraDistance', true)
  drawParamAsSlider('cameraFov', true)
  drawParamAsSlider('cameraPitch', true)
  drawParamAsSlider('cameraTargetHeightOffset', true)
  drawParamAsSlider('cameraRelaxation', true)

  ui.newLine()
  ui.text('At speed')
  ui.separator()

  drawParamAsSlider('dynamicFovAtSpeed', true)
  drawParamAsSlider('dynamicPitchAtSpeed', true)
  drawParamAsSlider('dynamicHeightAtSpeed', true)

  ui.newLine()
  if ui.button('Reset all to defaults', vec2(ui.availableSpaceX(), 0)) then
    resetCameraParams()
  end
end

local function drawControlsTab()
  ui.text('Bindings')
  ui.separator()

  drawBinding(
    'Yaw left',
    'Rotate camera left. Supports keyboard, gamepad and controllers.',
    orbitLeftButton
  )

  drawBinding(
    'Yaw right',
    'Rotate camera right. Supports keyboard, gamepad and controllers.',
    orbitRightButton
  )

  drawBinding(
    'Pitch down',
    'Rotate camera down. Supports keyboard, gamepad and controllers.',
    orbitDownButton
  )

  drawBinding(
    'Pitch up',
    'Rotate camera up. Supports keyboard, gamepad and controllers.',
    orbitUpButton
  )

  drawBinding(
    'Zoom out',
    'Increase camera distance. Supports keyboard, gamepad and controllers.',
    zoomOutButton
  )

  drawBinding(
    'Zoom in',
    'Decrease camera distance. Supports keyboard, gamepad and controllers.',
    zoomInButton
  )

  drawBinding(
    'Recenter',
    'Returns yaw, pitch and camera distance. Supports keyboard, gamepad and controllers.',
    recenterButton
  )

  drawBinding(
    'Recenter, keep pitch/distance',
    'Returns yaw while preserving the current pitch and camera distance. Supports keyboard, gamepad and controllers.',
    recenterKeepValuesButton
  )

  ui.newLine()

  ui.text('Gamepad')
  ui.separator()

  drawParamAsScheme('gamepadControlScheme', false)

  local controlScheme = getParamValue('gamepadControlScheme')
  if controlScheme >= 2 then
    drawZoomModifierBinding()
  end

  if controlScheme ~= 0 then
    ui.treeNode('Advanced', function()
      drawParamAsSlider('orbitStickDeadzone', true)
      drawParamAsSlider('orbitStickExponent', true)

      if controlScheme >= 2 then
        drawParamAsSlider('zoomStickDeadzone', true)
        drawParamAsSlider('zoomStickExponent', true)
      end
    end)
  end

  ui.newLine()

  ui.text('Mouse')
  ui.separator()

  drawParamAsScheme('mouseControlScheme', false)
end

---@param dt number
---@diagnostic disable-next-line: duplicate-set-field
function script.update(dt)
  -- Keep parameters and resolved input available even while the app window is closed.
  publishParams()
  publishControls(dt)
end

---@param dt number
function script.windowMain(dt)
  ui.tabBar('beamngOrbitCameraTabs', function()
    ui.tabItem('Camera', drawCameraTab)
    ui.tabItem('Controls', drawControlsTab)
  end)
end
