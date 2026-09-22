
---@class BeamNGOrbitCameraSettings
local M = {}

local cspMajor, cspMinor = (ac.getPatchVersion() or ''):match('^(%d+)%.(%d+)')
local supportsCollisions = (tonumber(cspMajor) or 0) > 0 or (tonumber(cspMinor) or 0) >= 3

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

local COLLISION_HANDLING_SCHEMES = {
  [0] = 'Disabled',
  [1] = 'Collision with physics shapes',
  [2] = 'Collision with visuals',
}

---@class ParamDef
---@field kind 'slider'|'scheme'|'cbox'
---@field displayName string
---@field defaultValue number
---@field minValue number?
---@field maxValue number?
---@field format string?
---@field options table?

local cameraParams = {
  cameraDistance = { displayName = 'Distance', defaultValue = 5.0, minValue = 3.0, maxValue = 30.0, format = '%.1f m', kind = 'slider' },
  cameraFov = { displayName = 'Field of view', defaultValue = 65.0, minValue = 45.0, maxValue = 85.0, format = '%.0f°', kind = 'slider' },
  cameraPitch = { displayName = 'Pitch', defaultValue = 17.0, minValue = -85.0, maxValue = 85.0, format = '%.0f°', kind = 'slider' },
  cameraTargetHeightOffset = { displayName = 'Height', defaultValue = 0.0, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
  cameraRelaxation = { displayName = 'Follow vehicle direction', defaultValue = 6.0, minValue = 0.2, maxValue = 6.0, format = '%.2f', kind = 'slider' },
  dynamicFovAtSpeed = { displayName = 'Field of view', defaultValue = 40.0, minValue = 0.0, maxValue = 75.0, format = '%.0f°', kind = 'slider' },
  dynamicPitchAtSpeed = { displayName = 'Pitch', defaultValue = 7.0, minValue = 0.0, maxValue = 25.0, format = '%.1f°', kind = 'slider' },
  dynamicHeightAtSpeed = { displayName = 'Height', defaultValue = 0.4, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
}

local controlParams = {
  disableGlance = { displayName = 'Disable glance left/right/back', defaultValue = 0, kind = 'cbox' },
  gamepadControlScheme = { displayName = 'Control scheme', defaultValue = 2, options = GAMEPAD_CONTROL_SCHEMES, kind = 'scheme' },
  mouseControlScheme = { displayName = 'Control scheme', defaultValue = 1, options = MOUSE_CONTROL_SCHEMES, kind = 'scheme' },
  orbitStickDeadzone = { displayName = 'Orbit deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  orbitStickExponent = { displayName = 'Orbit exponent', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
  zoomStickDeadzone = { displayName = 'Zoom deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  zoomStickExponent = { displayName = 'Zoom exponent', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
}

local collisionParams = {
  collisionHandlingMethod = { displayName = 'Handling method', defaultValue = 1, options = COLLISION_HANDLING_SCHEMES, kind = 'scheme' },
  disableCollisionWhenRecentered = { displayName = 'Disable collision for recentered camera', defaultValue = 0, kind = 'cbox' },
}

---@return ParamDef
local function getParamDef(key)
  return cameraParams[key] or controlParams[key] or collisionParams[key]
end

local paramStorage = {}

local function registerParams(params)
  for key, param in pairs(params) do
    paramStorage[key] = ac.storage(key, param.defaultValue)
  end
end

---@param key string
---@return number
local function getParamVal(key)
  return paramStorage[key]:get()
end

---@param key string
---@param value number
local function setParamVal(key, value)
  paramStorage[key]:set(value)
end

---@param key string
local function resetParamVal(key)
  local paramDef = getParamDef(key)
  if paramDef == nil then return end
  setParamVal(key, paramDef.defaultValue)
end

local function resetCameraParams()
  for key, param in pairs(cameraParams) do
    setParamVal(key, param.defaultValue)
  end
end

---@param paramVal number?
---@param paramDef ParamDef
---@return number
local function clampParamValIfNeeded(paramVal, paramDef)

  if paramVal and paramDef.minValue ~= nil then
    paramVal = math.max(paramDef.minValue, paramVal)
  end

  if paramVal and paramDef.maxValue ~= nil then
    paramVal = math.min(paramDef.maxValue, paramVal)
  end

  return paramVal or paramDef.defaultValue
end

registerParams(cameraParams)
registerParams(controlParams)
registerParams(collisionParams)

---@param key string
---@return number
function M.get(key)
  local paramDef = getParamDef(key)
  local paramVal = getParamVal(key)

  return clampParamValIfNeeded(paramVal, paramDef)
end

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
  collisionHandlingMethod = ac.StructItem.uint32(),
  disableCollisionWhenRecentered = ac.StructItem.boolean(),
}, false, ac.SharedNamespace.Shared)

M.cameraConfig = {
  cameraDistance = cameraParams.cameraDistance.defaultValue,
  cameraFov = cameraParams.cameraFov.defaultValue,
  cameraTargetHeightOffset = cameraParams.cameraTargetHeightOffset.defaultValue,
  cameraPitch = cameraParams.cameraPitch.defaultValue,
  cameraRelaxation = cameraParams.cameraRelaxation.defaultValue,
  dynamicFovAtSpeed = cameraParams.dynamicFovAtSpeed.defaultValue,
  dynamicPitchAtSpeed = cameraParams.dynamicPitchAtSpeed.defaultValue,
  dynamicHeightAtSpeed = cameraParams.dynamicHeightAtSpeed.defaultValue,
  collisionHandlingMethod = collisionParams.collisionHandlingMethod.defaultValue,
  disableCollisionWhenRecentered = collisionParams.disableCollisionWhenRecentered.defaultValue == 1,
}

local UINT32_WRAP = 4294967296
local MODIFIED_PARAM_COLOR = rgbm.colors.yellow
local fullWidthSize = vec2()
local paramsPublished = false
local recenterRequested = false
local recenterKeepValuesRequested = false
local liveValuePosition = vec2()
local liveCameraValues = {
  active = false,
  cameraDistance = 0.0,
  cameraFov = 0.0,
  cameraPitch = 0.0,
  cameraTargetHeightOffset = 0.0,
  orbitDistance = 0.0,
  orbitPitch = 0.0,
}

local LIVE_CAMERA_VALUE_KEYS = {
  cameraDistance = 'cameraDistance',
  cameraFov = 'cameraFov',
  cameraPitch = 'cameraPitch',
  cameraTargetHeightOffset = 'cameraTargetHeightOffset',
}

---@param active boolean
---@param distance number
---@param fov number
---@param pitch number
---@param height number
---@param orbitDistance number
---@param orbitPitch number
function M.setLiveCameraValues(active, distance, fov, pitch, height, orbitDistance, orbitPitch)
  liveCameraValues.active = active
  liveCameraValues.cameraDistance = distance
  liveCameraValues.cameraFov = fov
  liveCameraValues.cameraPitch = pitch
  liveCameraValues.cameraTargetHeightOffset = height
  liveCameraValues.orbitDistance = orbitDistance
  liveCameraValues.orbitPitch = orbitPitch
end

local function setDistanceAndPitchFromOrbit()
  if not liveCameraValues.active then return end
  setParamVal('cameraDistance', clampParamValIfNeeded(
    liveCameraValues.orbitDistance,
    cameraParams.cameraDistance
  ))
  setParamVal('cameraPitch', clampParamValIfNeeded(
    liveCameraValues.orbitPitch,
    cameraParams.cameraPitch
  ))
end

---@param keepPitchAndDistance boolean
function M.requestRecenter(keepPitchAndDistance)
  recenterRequested = true
  recenterKeepValuesRequested = keepPitchAndDistance
end

---@return boolean requested
---@return boolean keepPitchAndDistance
function M.consumeRecenterRequest()
  local requested = recenterRequested
  local keepPitchAndDistance = recenterKeepValuesRequested
  recenterRequested = false
  recenterKeepValuesRequested = false
  return requested, keepPitchAndDistance
end

function M.update()
  local cameraConfig = M.cameraConfig
  local cameraDistance = M.get('cameraDistance')
  local cameraFov = M.get('cameraFov')
  local cameraTargetHeightOffset = M.get('cameraTargetHeightOffset')
  local cameraPitch = M.get('cameraPitch')
  local cameraRelaxation = M.get('cameraRelaxation')
  local dynamicFovAtSpeed = M.get('dynamicFovAtSpeed')
  local dynamicPitchAtSpeed = M.get('dynamicPitchAtSpeed')
  local dynamicHeightAtSpeed = M.get('dynamicHeightAtSpeed')
  local collisionHandlingMethod = M.get('collisionHandlingMethod')
  local disableCollisionWhenRecentered = M.get('disableCollisionWhenRecentered') == 1

  local changed = not paramsPublished
    or cameraDistance ~= cameraConfig.cameraDistance
    or cameraFov ~= cameraConfig.cameraFov
    or cameraTargetHeightOffset ~= cameraConfig.cameraTargetHeightOffset
    or cameraPitch ~= cameraConfig.cameraPitch
    or cameraRelaxation ~= cameraConfig.cameraRelaxation
    or dynamicFovAtSpeed ~= cameraConfig.dynamicFovAtSpeed
    or dynamicPitchAtSpeed ~= cameraConfig.dynamicPitchAtSpeed
    or dynamicHeightAtSpeed ~= cameraConfig.dynamicHeightAtSpeed
    or collisionHandlingMethod ~= cameraConfig.collisionHandlingMethod
    or disableCollisionWhenRecentered
      ~= cameraConfig.disableCollisionWhenRecentered

  cameraConfig.cameraDistance = cameraDistance
  cameraConfig.cameraFov = cameraFov
  cameraConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  cameraConfig.cameraPitch = cameraPitch
  cameraConfig.cameraRelaxation = cameraRelaxation
  cameraConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  cameraConfig.dynamicPitchAtSpeed = dynamicPitchAtSpeed
  cameraConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed
  cameraConfig.collisionHandlingMethod = collisionHandlingMethod
  cameraConfig.disableCollisionWhenRecentered = disableCollisionWhenRecentered

  if not changed then return end

  paramsBridge.ready = false
  paramsBridge.cameraDistance = cameraDistance
  paramsBridge.cameraFov = cameraFov
  paramsBridge.cameraTargetHeightOffset = cameraTargetHeightOffset
  paramsBridge.cameraPitch = cameraPitch
  paramsBridge.cameraRelaxation = cameraRelaxation
  paramsBridge.dynamicFovAtSpeed = dynamicFovAtSpeed
  paramsBridge.dynamicPitchAtSpeed = dynamicPitchAtSpeed
  paramsBridge.dynamicHeightAtSpeed = dynamicHeightAtSpeed
  paramsBridge.collisionHandlingMethod = collisionHandlingMethod
  paramsBridge.disableCollisionWhenRecentered = disableCollisionWhenRecentered
  paramsBridge.seqNum = (paramsBridge.seqNum + 1) % UINT32_WRAP
  paramsBridge.ready = true
  paramsPublished = true
end

---@param key string
---@param highlightIfModified boolean
local function drawParamLabel(key, highlightIfModified)
  local paramDef = getParamDef(key)
  if paramDef == nil then return end

  if highlightIfModified and getParamVal(key) ~= paramDef.defaultValue then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
    ui.text(paramDef.displayName)
    ui.popStyleColor()
  else
    ui.text(paramDef.displayName)
  end
end

---@param key string
---@param highlightIfModified boolean
function M.drawSlider(key, highlightIfModified)
  local paramDef = getParamDef(key)
  if paramDef == nil or paramDef.kind ~= 'slider' then return end

  local valueObj = paramStorage[key]
  local value = clampParamValIfNeeded(valueObj:get(), paramDef)
  local needHighlight = highlightIfModified and value ~= paramDef.defaultValue

  drawParamLabel(key, highlightIfModified)
  ui.sameLine(230)

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  ui.pushItemWidth(ui.availableSpaceX())
  local newValue, changed = ui.slider(
    '##' .. key,
    value,
    paramDef.minValue,
    paramDef.maxValue,
    paramDef.format
  )
  ui.popItemWidth()

  local liveValueKey = LIVE_CAMERA_VALUE_KEYS[key]
  if liveCameraValues.active and liveValueKey ~= nil then
    local liveValueText = string.format(paramDef.format, liveCameraValues[liveValueKey])
    local itemMax = ui.itemRectMax()
    local textSize = ui.measureText(liveValueText)
    liveValuePosition:set(itemMax.x - textSize.x - 4, itemMax.y - textSize.y - 1)
    ui.drawText(liveValueText, liveValuePosition, ui.styleColor(ui.StyleColor.TextDisabled))
  end

  if needHighlight then
    ui.popStyleColor()
  end

  if ui.itemHovered() and ui.mouseDown(ui.MouseButton.Right) then
    resetParamVal(key)
  end

  if changed then
    valueObj:set(newValue)
  end
end

---@param key string
---@param highlightIfModified boolean
function M.drawScheme(key, highlightIfModified)
  local paramDef = getParamDef(key)
  if paramDef == nil or paramDef.kind ~= 'scheme' then return end

  local valueObj = paramStorage[key]
  local value = clampParamValIfNeeded(valueObj:get(), paramDef)
  local needHighlight = highlightIfModified and value ~= paramDef.defaultValue

  drawParamLabel(key, highlightIfModified)
  ui.sameLine(230)
  ui.pushItemWidth(ui.availableSpaceX())

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  local comboOpen = ui.beginCombo('##' .. key, paramDef.options[value])

  if needHighlight then
    ui.popStyleColor()
  end

  if ui.itemHovered() and ui.mouseDown(ui.MouseButton.Right) then
    resetParamVal(key)
  end

  if comboOpen then
    for scheme, name in pairs(paramDef.options) do
      if ui.selectable(name .. '##' .. key .. scheme) then
        valueObj:set(scheme)
      end
    end
    ui.endCombo()
  end

  ui.popItemWidth()
end

---@param key string
---@param highlightIfModified boolean
function M.drawCheckbox(key, highlightIfModified)
  local paramDef = getParamDef(key)
  if paramDef == nil or paramDef.kind ~= 'cbox' then return end

  local valueObj = paramStorage[key]
  local value = clampParamValIfNeeded(valueObj:get(), paramDef)
  local checked = value ~= 0
  local needHighlight = highlightIfModified and value ~= paramDef.defaultValue

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  local changed = ui.checkbox(paramDef.displayName .. '##' .. key, checked)

  if needHighlight then
    ui.popStyleColor()
  end

  if ui.itemHovered() and ui.mouseDown(ui.MouseButton.Right) then
    resetParamVal(key)
  end

  if changed then
    valueObj:set(checked and 0 or 1)
  end
end

function M.drawCollisionSettings()
  if not supportsCollisions then return end

  ui.text('Collision')
  ui.separator()

  M.drawCheckbox('disableCollisionWhenRecentered', false)
  if ui.itemHovered() then
    ui.setTooltip('Disables camera collisions while recentered, which can slightly reduce CPU load. Collisions resume when you manually orbit or zoom the camera.')
  end
  M.drawScheme('collisionHandlingMethod', false)
end

function M.drawCameraTab()
  ui.text('Camera')
  if ui.itemHovered() then
    ui.setTooltip('Gray values show the camera\'s actual values, including offsets at speed and manual orbit adjustments.')
  end
  ui.separator()

  M.drawSlider('cameraDistance', true)
  M.drawSlider('cameraFov', true)
  M.drawSlider('cameraPitch', true)
  M.drawSlider('cameraTargetHeightOffset', true)
  M.drawSlider('cameraRelaxation', true)

  ui.newLine()
  ui.text('Offsets at speed')
  if ui.itemHovered() then
    ui.setTooltip('Resulting value = current value + value below × speed factor.')
  end
  ui.separator()

  M.drawSlider('dynamicFovAtSpeed', true)
  M.drawSlider('dynamicPitchAtSpeed', true)
  M.drawSlider('dynamicHeightAtSpeed', true)

  ui.newLine()
  fullWidthSize:set((ui.availableSpaceX() - 8) / 2, 0)
  if ui.button('Recenter', fullWidthSize) then
    M.requestRecenter(false)
  end
  if ui.itemHovered() then
    ui.setTooltip('Recenters the camera and restores its actual distance and pitch from the current settings.')
  end
  ui.sameLine(0, 8)
  if ui.button('Recenter, keep pitch/distance', fullWidthSize) then
    M.requestRecenter(true)
  end
  if ui.itemHovered() then
    ui.setTooltip('Recenters the camera while keeping its actual distance and pitch.')
  end
  fullWidthSize:set(ui.availableSpaceX(), 0)
  if ui.button('Capture current pitch/distance', fullWidthSize) then
    setDistanceAndPitchFromOrbit()
  end
  if ui.itemHovered() then
    ui.setTooltip('Copies the actual camera distance and pitch to the settings.')
  end
  fullWidthSize:set(ui.availableSpaceX(), 0)
  if ui.button('Reset all values to default', fullWidthSize) then
    resetCameraParams()
  end
end

return M
