--------
-- Persisted settings, camera configuration bridge and parameter UI.
--------

---@class BeamNGOrbitCameraSettings
local M = {}

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

---@class ParamDef
---@field kind 'slider'|'scheme'
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
  cameraTargetHeightOffset = { displayName = 'Target height offset', defaultValue = 0.0, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
  cameraRelaxation = { displayName = 'Follow vehicle direction', defaultValue = 6.0, minValue = 0.2, maxValue = 6.0, format = '%.2f', kind = 'slider' },
  dynamicFovAtSpeed = { displayName = 'Field of view', defaultValue = 40.0, minValue = 0.0, maxValue = 75.0, format = '%.0f°', kind = 'slider' },
  dynamicPitchAtSpeed = { displayName = 'Pitch', defaultValue = 7.0, minValue = 0.0, maxValue = 25.0, format = '%.1f°', kind = 'slider' },
  dynamicHeightAtSpeed = { displayName = 'Height', defaultValue = 0.4, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
}

local controlParams = {
  gamepadControlScheme = { displayName = 'Control scheme', defaultValue = 2, options = GAMEPAD_CONTROL_SCHEMES, kind = 'scheme' },
  mouseControlScheme = { displayName = 'Control scheme', defaultValue = 1, options = MOUSE_CONTROL_SCHEMES, kind = 'scheme' },
  orbitStickDeadzone = { displayName = 'Orbit deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  orbitStickExponent = { displayName = 'Orbit exponent', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
  zoomStickDeadzone = { displayName = 'Zoom deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  zoomStickExponent = { displayName = 'Zoom exponent', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
}

---@return ParamDef
local function getParamDef(key)
  return cameraParams[key] or controlParams[key]
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
}, false, ac.SharedNamespace.Shared)

M.cameraConfig = {
  cameraDistance = 5.0,
  cameraFov = 65.0,
  cameraTargetHeightOffset = 0.0,
  cameraPitch = 17.0,
  cameraRelaxation = 6.0,
  dynamicFovAtSpeed = 40.0,
  dynamicPitchAtSpeed = 7.0,
  dynamicHeightAtSpeed = 0.4,
}

local UINT32_WRAP = 4294967296
local MODIFIED_PARAM_COLOR = rgbm.colors.yellow
local fullWidthSize = vec2()
local paramsPublished = false

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

  local changed = not paramsPublished
    or cameraDistance ~= cameraConfig.cameraDistance
    or cameraFov ~= cameraConfig.cameraFov
    or cameraTargetHeightOffset ~= cameraConfig.cameraTargetHeightOffset
    or cameraPitch ~= cameraConfig.cameraPitch
    or cameraRelaxation ~= cameraConfig.cameraRelaxation
    or dynamicFovAtSpeed ~= cameraConfig.dynamicFovAtSpeed
    or dynamicPitchAtSpeed ~= cameraConfig.dynamicPitchAtSpeed
    or dynamicHeightAtSpeed ~= cameraConfig.dynamicHeightAtSpeed

  cameraConfig.cameraDistance = cameraDistance
  cameraConfig.cameraFov = cameraFov
  cameraConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  cameraConfig.cameraPitch = cameraPitch
  cameraConfig.cameraRelaxation = cameraRelaxation
  cameraConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  cameraConfig.dynamicPitchAtSpeed = dynamicPitchAtSpeed
  cameraConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed

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

  local newValue, changed = ui.slider(
    '##' .. key,
    value,
    paramDef.minValue,
    paramDef.maxValue,
    paramDef.format
  )

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

function M.drawCameraTab()
  ui.text('Camera')
  ui.separator()

  M.drawSlider('cameraDistance', true)
  M.drawSlider('cameraFov', true)
  M.drawSlider('cameraPitch', true)
  M.drawSlider('cameraTargetHeightOffset', true)
  M.drawSlider('cameraRelaxation', true)

  ui.newLine()
  ui.text('Offsets at speed (current value + value below * speed factor)')
  ui.separator()

  M.drawSlider('dynamicFovAtSpeed', true)
  M.drawSlider('dynamicPitchAtSpeed', true)
  M.drawSlider('dynamicHeightAtSpeed', true)

  ui.newLine()
  fullWidthSize:set(ui.availableSpaceX(), 0)
  if ui.button('Reset all to defaults', fullWidthSize) then
    resetCameraParams()
  end
end

return M
