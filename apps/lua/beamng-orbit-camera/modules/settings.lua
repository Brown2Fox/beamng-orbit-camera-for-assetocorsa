
---@class BeamNGOrbitCameraSettingsModule
local M = {}

local cspMajor, cspMinor = (ac.getPatchVersion() or ''):match('^(%d+)%.(%d+)')
local supportsCollisions = (tonumber(cspMajor) or 0) > 0 or (tonumber(cspMinor) or 0) >= 3

---@type table<integer, string>
local GAMEPAD_CONTROL_SCHEMES = {
  [0] = 'Disabled',
  [1] = 'Right stick orbits',
  [2] = 'Right stick orbits; hold zoom button + left stick up/down zooms',
  [3] = 'Right stick orbits; hold zoom button + right stick up/down zooms',
  [4] = 'Right stick orbits; hold zoom button + right stick zooms and turns',
}

---@type table<integer, string>
local MOUSE_CONTROL_SCHEMES = {
  [0] = 'Disabled',
  [1] = 'Right-drag orbits; wheel zooms only while right button is held',
  [2] = 'Right-drag orbits; wheel always zooms',
}

local WHEEL_ACTIONS = {
  [0] = 'Moves camera',
  [1] = 'Changes lens',
  [2] = 'Does both',
}

local WHEEL_MODIFIER_KEYS = {
  [0] = 'None',
  [1] = 'Ctrl',
  [2] = 'Alt',
  [3] = 'Shift',
}

---@type table<integer, string>
local COLLISION_HANDLING_SCHEMES = {
  [0] = 'Disabled',
  [1] = 'Collision with physics shapes',
  [2] = 'Collision with visuals',
  [3] = 'Smart: physics shapes — rise over ground, pull in at walls',
  [4] = 'Smart: visuals — rise over ground, pull in at walls and trees',
}

---@alias ParamKind 'slider'|'scheme'|'cbox'

---@class ParamDef
---@field kind ParamKind
---@field displayName string
---@field defaultValue number
---@field minValue number?
---@field maxValue number?
---@field format string?
---@field ends string[]?
---@field hint string?
---@field options table<integer, string>?

---@type table<string, ParamDef>
local cameraParams = {
  cameraDistance = { displayName = 'Distance', ends = { 'Close', 'Far' }, defaultValue = 5.0, minValue = 3.0, maxValue = 75.0, format = '%.1f m', kind = 'slider' },
  cameraFov = { displayName = 'Lens', ends = { 'Zoomed in', 'Wide' }, defaultValue = 65.0, minValue = 10.0, maxValue = 120.0, format = '%.0f°', kind = 'slider' },
  cameraPitch = { displayName = 'Angle', ends = { 'Low', 'High' }, defaultValue = 17.0, minValue = -85.0, maxValue = 85.0, format = '%.0f°', kind = 'slider' },
  cameraTargetHeightOffset = { displayName = 'Aim point', ends = { 'Lower on car', 'Higher' }, defaultValue = 0.0, minValue = -1.0, maxValue = 1.0, format = '%.2f m', kind = 'slider' },
  cameraRelaxation = { displayName = 'Turns with car', ends = { 'Lazy', 'Tight' }, hint = 'How tightly the camera swings round behind the car.', defaultValue = 6.0, minValue = 0.2, maxValue = 30.0, format = '%.1f', kind = 'slider' },
  cameraSlopeFollow = { displayName = 'Tilts with hills', ends = { 'Never', 'Fully' }, hint = 'Low values calm the camera over crests and dips.', defaultValue = 1.0, minValue = 0.0, maxValue = 1.0, format = '%.2f', kind = 'slider' },
  dynamicFovAtSpeed = { displayName = 'Wider lens', defaultValue = 40.0, minValue = 0.0, maxValue = 75.0, format = '+%.0f°', kind = 'slider' },
  dynamicPitchAtSpeed = { displayName = 'Higher angle', defaultValue = 7.0, minValue = 0.0, maxValue = 25.0, format = '+%.1f°', kind = 'slider' },
  dynamicHeightAtSpeed = { displayName = 'Higher aim', defaultValue = 0.4, minValue = -1.0, maxValue = 1.0, format = '+%.2f m', kind = 'slider' },
}

---@type table<string, ParamDef>
local controlParams = {
  disableGlance = { displayName = 'Ignore glance left/right/back', defaultValue = 0, kind = 'cbox' },
  keepViewOnCarSwitch = { displayName = 'Keep view when switching cars', defaultValue = 0, kind = 'cbox' },
  gamepadControlScheme = { displayName = 'Gamepad', defaultValue = 2, options = GAMEPAD_CONTROL_SCHEMES, kind = 'scheme' },
  mouseControlScheme = { displayName = 'Mouse', defaultValue = 1, options = MOUSE_CONTROL_SCHEMES, kind = 'scheme' },
  wheelAction = { displayName = 'Wheel', defaultValue = 2, options = WHEEL_ACTIONS, kind = 'scheme' },
  wheelModifier1Key = { displayName = 'Extra key 1', defaultValue = 1, options = WHEEL_MODIFIER_KEYS, kind = 'scheme' },
  wheelModifier1Action = { displayName = 'Extra key 1 + wheel', defaultValue = 0, options = WHEEL_ACTIONS, kind = 'scheme' },
  wheelModifier2Key = { displayName = 'Extra key 2', defaultValue = 2, options = WHEEL_MODIFIER_KEYS, kind = 'scheme' },
  wheelModifier2Action = { displayName = 'Extra key 2 + wheel', defaultValue = 1, options = WHEEL_ACTIONS, kind = 'scheme' },
  orbitStickDeadzone = { displayName = 'Orbit stick deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  orbitSens = { displayName = 'Orbit speed', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
  zoomStickDeadzone = { displayName = 'Zoom stick deadzone', defaultValue = 0.03, minValue = 0.0, maxValue = 0.95, format = '%.2f', kind = 'slider' },
  zoomSens = { displayName = 'Zoom speed', defaultValue = 1.0, minValue = 0.2, maxValue = 5.0, format = '%.2f', kind = 'slider' },
}

---@type table<string, ParamDef>
local collisionParams = {
  collisionHandlingMethod = { displayName = 'Handling method', defaultValue = 4, minValue = 0, maxValue = 4, options = COLLISION_HANDLING_SCHEMES, kind = 'scheme' },
  disableCollisionWhenRecentered = { displayName = 'No obstacle checks while straightened', defaultValue = 0, kind = 'cbox' },
  collisionKeepSubjectSize = { displayName = 'Keep car the same size when pulled in', defaultValue = 1, kind = 'cbox' },
  collisionGroundClearance = { displayName = 'Clearance over ground', defaultValue = 0.3, minValue = 0.1, maxValue = 3.0, format = '%.2f m', kind = 'slider' },
  collisionMaxFov = { displayName = 'Widest lens when pulled in', defaultValue = 90.0, minValue = 60.0, maxValue = 140.0, format = '%.0f°', kind = 'slider' },
  collisionMaxHitHeight = { displayName = 'Ignore above', ends = { 'Low walls only', 'Anything' }, hint = 'Track only: hits higher than this above the car (trunks, banks) are ignored.', defaultValue = 4.0, minValue = 0.5, maxValue = 50.0, format = '%.1f m', kind = 'slider' },
  collisionMinDistance = { displayName = 'Closest to car', defaultValue = 2.5, minValue = 0.5, maxValue = 10.0, format = '%.1f m', kind = 'slider' },
}

-- Helicopter mode is a second, separately stored set of the camera values: a far, long-lens,
-- lazily following shot. The camera tab's sliders, capture and reset act on the active set.
---@type table<string, number>
local HELICOPTER_DEFAULTS = {
  cameraDistance = 50.0,
  cameraFov = 14.0,
  cameraPitch = 8.0,
  cameraTargetHeightOffset = 0.0,
  cameraRelaxation = 30.0,
  cameraSlopeFollow = 0.5,
  dynamicFovAtSpeed = 0.0,
  dynamicPitchAtSpeed = 2.0,
  dynamicHeightAtSpeed = 0.4,
}

local helicopterMode = ac.storage('helicopterMode', 0) --[[@as ac.StoredValue]]

---@return boolean
local function isHelicopterMode()
  return helicopterMode:get() == 1
end

---@param key string
---@return ParamDef
local function getParamDef(key)
  return cameraParams[key] or controlParams[key] or collisionParams[key]
end

---@type table<string, ac.StoredValue>
local paramStorage = {}
---@type table<string, ac.StoredValue>
local helicopterStorage = {}

---@param params table<string, ParamDef>
local function registerParams(params)
  for key, param in pairs(params) do
    paramStorage[key] = ac.storage(key, param.defaultValue)
  end
end

for key, value in pairs(HELICOPTER_DEFAULTS) do
  helicopterStorage[key] = ac.storage('helicopter_' .. key, value)
end

---@param key string
---@return ac.StoredValue
local function getParamStorage(key)
  return isHelicopterMode() and helicopterStorage[key] or paramStorage[key]
end

---@param key string
---@return number
local function getDefaultVal(key)
  return isHelicopterMode() and HELICOPTER_DEFAULTS[key] or getParamDef(key).defaultValue
end

---@param key string
---@return number
local function getParamVal(key)
  return tonumber(getParamStorage(key):get()) or 0.0
end

---@param key string
---@param value number
local function setParamVal(key, value)
  getParamStorage(key):set(value)
end

---@param key string
local function resetParamVal(key)
  local paramDef = getParamDef(key)
  if paramDef == nil then return end
  setParamVal(key, getDefaultVal(key))
end

local function resetCameraParams()
  for key in pairs(cameraParams) do
    setParamVal(key, getDefaultVal(key))
  end
end

---@param paramVal number?
---@param paramDef ParamDef
---@param defaultVal number?
---@return number
local function clampParamValIfNeeded(paramVal, paramDef, defaultVal)

  if paramVal and paramDef.minValue ~= nil then
    paramVal = math.max(paramDef.minValue, paramVal)
  end

  if paramVal and paramDef.maxValue ~= nil then
    paramVal = math.min(paramDef.maxValue, paramVal)
  end

  return paramVal or defaultVal or paramDef.defaultValue
end

registerParams(cameraParams)
registerParams(controlParams)
registerParams(collisionParams)

---@param key string
---@param value number
function M.set(key, value)
  getParamStorage(key):set(value)
end

---@param key string
---@return number
function M.get(key)
  local paramDef = getParamDef(key)
  local paramVal = getParamVal(key)

  return clampParamValIfNeeded(paramVal, paramDef, getDefaultVal(key))
end

---@class ParamsBridgeLayout
---@field seqNum integer
---@field ready boolean
---@field cameraDistance number
---@field cameraFov number
---@field cameraTargetHeightOffset number
---@field cameraPitch number
---@field cameraRelaxation number
---@field cameraSlopeFollow number
---@field dynamicFovAtSpeed number
---@field dynamicPitchAtSpeed number
---@field dynamicHeightAtSpeed number
---@field collisionHandlingMethod integer
---@field disableCollisionWhenRecentered boolean
---@field keepViewOnCarSwitch boolean
---@field collisionKeepSubjectSize boolean
---@field collisionGroundClearance number
---@field collisionMaxFov number
---@field collisionMinDistance number
---@field collisionMaxHitHeight number

---@type ParamsBridgeLayout
local paramsBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.params_bridge_v6'),
  seqNum = ac.StructItem.uint32(),
  ready = ac.StructItem.boolean(),
  cameraDistance = ac.StructItem.double(),
  cameraFov = ac.StructItem.double(),
  cameraTargetHeightOffset = ac.StructItem.double(),
  cameraPitch = ac.StructItem.double(),
  cameraRelaxation = ac.StructItem.double(),
  cameraSlopeFollow = ac.StructItem.double(),
  dynamicFovAtSpeed = ac.StructItem.double(),
  dynamicPitchAtSpeed = ac.StructItem.double(),
  dynamicHeightAtSpeed = ac.StructItem.double(),
  collisionHandlingMethod = ac.StructItem.uint32(),
  disableCollisionWhenRecentered = ac.StructItem.boolean(),
  keepViewOnCarSwitch = ac.StructItem.boolean(),
  collisionKeepSubjectSize = ac.StructItem.boolean(),
  collisionGroundClearance = ac.StructItem.double(),
  collisionMaxFov = ac.StructItem.double(),
  collisionMinDistance = ac.StructItem.double(),
  collisionMaxHitHeight = ac.StructItem.double(),
}, false, ac.SharedNamespace.Shared)

M.cameraConfig = {
  cameraDistance = cameraParams.cameraDistance.defaultValue,
  cameraFov = cameraParams.cameraFov.defaultValue,
  cameraTargetHeightOffset = cameraParams.cameraTargetHeightOffset.defaultValue,
  cameraPitch = cameraParams.cameraPitch.defaultValue,
  cameraRelaxation = cameraParams.cameraRelaxation.defaultValue,
  cameraSlopeFollow = cameraParams.cameraSlopeFollow.defaultValue,
  dynamicFovAtSpeed = cameraParams.dynamicFovAtSpeed.defaultValue,
  dynamicPitchAtSpeed = cameraParams.dynamicPitchAtSpeed.defaultValue,
  dynamicHeightAtSpeed = cameraParams.dynamicHeightAtSpeed.defaultValue,
  collisionHandlingMethod = collisionParams.collisionHandlingMethod.defaultValue,
  disableCollisionWhenRecentered = collisionParams.disableCollisionWhenRecentered.defaultValue == 1,
  keepViewOnCarSwitch = controlParams.keepViewOnCarSwitch.defaultValue == 1,
  collisionKeepSubjectSize = collisionParams.collisionKeepSubjectSize.defaultValue == 1,
  collisionGroundClearance = collisionParams.collisionGroundClearance.defaultValue,
  collisionMaxFov = collisionParams.collisionMaxFov.defaultValue,
  collisionMinDistance = collisionParams.collisionMinDistance.defaultValue,
  collisionMaxHitHeight = collisionParams.collisionMaxHitHeight.defaultValue,
}

M.LABEL_COL = 170
local LABEL_COL = M.LABEL_COL
local UINT32_WRAP = 4294967296
local MODIFIED_PARAM_COLOR = rgbm.colors.yellow
local paramsPublished = false
local recenterRequested = false
local recenterKeepValuesRequested = false
local liveValuePosition = vec2()
---@class LiveCameraValues
---@field active boolean
---@field cameraDistance number
---@field cameraFov number
---@field cameraPitch number
---@field cameraTargetHeightOffset number
---@field orbitDistance number
---@field orbitPitch number
---@field orbitFov number

---@type LiveCameraValues
local liveCameraValues = {
  active = false,
  cameraDistance = 0.0,
  cameraFov = 0.0,
  cameraPitch = 0.0,
  cameraTargetHeightOffset = 0.0,
  orbitDistance = 0.0,
  orbitPitch = 0.0,
  orbitFov = 0.0,
}

---@type table<string, string>
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
---@param orbitFov number
function M.setLiveCameraValues(active, distance, fov, pitch, height, orbitDistance, orbitPitch, orbitFov)
  liveCameraValues.active = active
  liveCameraValues.cameraDistance = distance
  liveCameraValues.cameraFov = fov
  liveCameraValues.cameraPitch = pitch
  liveCameraValues.cameraTargetHeightOffset = height
  liveCameraValues.orbitDistance = orbitDistance
  liveCameraValues.orbitPitch = orbitPitch
  liveCameraValues.orbitFov = orbitFov
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
  setParamVal('cameraFov', clampParamValIfNeeded(
    liveCameraValues.orbitFov,
    cameraParams.cameraFov
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
  local cameraSlopeFollow = M.get('cameraSlopeFollow')
  local dynamicFovAtSpeed = M.get('dynamicFovAtSpeed')
  local dynamicPitchAtSpeed = M.get('dynamicPitchAtSpeed')
  local dynamicHeightAtSpeed = M.get('dynamicHeightAtSpeed')
  local collisionHandlingMethod = M.get('collisionHandlingMethod') ---@cast collisionHandlingMethod integer
  local disableCollisionWhenRecentered = M.get('disableCollisionWhenRecentered') == 1
  local keepViewOnCarSwitch = M.get('keepViewOnCarSwitch') == 1
  local collisionKeepSubjectSize = M.get('collisionKeepSubjectSize') == 1
  local collisionGroundClearance = M.get('collisionGroundClearance')
  local collisionMaxFov = M.get('collisionMaxFov')
  local collisionMinDistance = M.get('collisionMinDistance')
  local collisionMaxHitHeight = M.get('collisionMaxHitHeight')

  local changed = not paramsPublished
    or cameraDistance ~= cameraConfig.cameraDistance
    or cameraFov ~= cameraConfig.cameraFov
    or cameraTargetHeightOffset ~= cameraConfig.cameraTargetHeightOffset
    or cameraPitch ~= cameraConfig.cameraPitch
    or cameraRelaxation ~= cameraConfig.cameraRelaxation
    or cameraSlopeFollow ~= cameraConfig.cameraSlopeFollow
    or dynamicFovAtSpeed ~= cameraConfig.dynamicFovAtSpeed
    or dynamicPitchAtSpeed ~= cameraConfig.dynamicPitchAtSpeed
    or dynamicHeightAtSpeed ~= cameraConfig.dynamicHeightAtSpeed
    or collisionHandlingMethod ~= cameraConfig.collisionHandlingMethod
    or disableCollisionWhenRecentered
      ~= cameraConfig.disableCollisionWhenRecentered
    or keepViewOnCarSwitch ~= cameraConfig.keepViewOnCarSwitch
    or collisionKeepSubjectSize ~= cameraConfig.collisionKeepSubjectSize
    or collisionGroundClearance ~= cameraConfig.collisionGroundClearance
    or collisionMaxFov ~= cameraConfig.collisionMaxFov
    or collisionMinDistance ~= cameraConfig.collisionMinDistance
    or collisionMaxHitHeight ~= cameraConfig.collisionMaxHitHeight

  cameraConfig.cameraDistance = cameraDistance
  cameraConfig.cameraFov = cameraFov
  cameraConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  cameraConfig.cameraPitch = cameraPitch
  cameraConfig.cameraRelaxation = cameraRelaxation
  cameraConfig.cameraSlopeFollow = cameraSlopeFollow
  cameraConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  cameraConfig.dynamicPitchAtSpeed = dynamicPitchAtSpeed
  cameraConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed
  cameraConfig.collisionHandlingMethod = collisionHandlingMethod
  cameraConfig.disableCollisionWhenRecentered = disableCollisionWhenRecentered
  cameraConfig.keepViewOnCarSwitch = keepViewOnCarSwitch
  cameraConfig.collisionKeepSubjectSize = collisionKeepSubjectSize
  cameraConfig.collisionGroundClearance = collisionGroundClearance
  cameraConfig.collisionMaxFov = collisionMaxFov
  cameraConfig.collisionMinDistance = collisionMinDistance
  cameraConfig.collisionMaxHitHeight = collisionMaxHitHeight

  if not changed then return end

  paramsBridge.ready = false
  paramsBridge.cameraDistance = cameraDistance
  paramsBridge.cameraFov = cameraFov
  paramsBridge.cameraTargetHeightOffset = cameraTargetHeightOffset
  paramsBridge.cameraPitch = cameraPitch
  paramsBridge.cameraRelaxation = cameraRelaxation
  paramsBridge.cameraSlopeFollow = cameraSlopeFollow
  paramsBridge.dynamicFovAtSpeed = dynamicFovAtSpeed
  paramsBridge.dynamicPitchAtSpeed = dynamicPitchAtSpeed
  paramsBridge.dynamicHeightAtSpeed = dynamicHeightAtSpeed
  paramsBridge.collisionHandlingMethod = collisionHandlingMethod
  paramsBridge.disableCollisionWhenRecentered = disableCollisionWhenRecentered
  paramsBridge.keepViewOnCarSwitch = keepViewOnCarSwitch
  paramsBridge.collisionKeepSubjectSize = collisionKeepSubjectSize
  paramsBridge.collisionGroundClearance = collisionGroundClearance
  paramsBridge.collisionMaxFov = collisionMaxFov
  paramsBridge.collisionMinDistance = collisionMinDistance
  paramsBridge.collisionMaxHitHeight = collisionMaxHitHeight
  paramsBridge.seqNum = (paramsBridge.seqNum + 1) % UINT32_WRAP
  paramsBridge.ready = true
  paramsPublished = true
end

---@param key string
---@param highlightIfModified boolean
local function drawParamLabel(key, highlightIfModified)
  local paramDef = getParamDef(key)
  if paramDef == nil then return end

  if highlightIfModified and getParamVal(key) ~= getDefaultVal(key) then
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
  if paramDef.format == nil then return end

  local valueObj = getParamStorage(key)
  local value = clampParamValIfNeeded(tonumber(valueObj:get()), paramDef, getDefaultVal(key))
  local needHighlight = highlightIfModified and value ~= getDefaultVal(key)

  drawParamLabel(key, highlightIfModified)
  ui.sameLine(LABEL_COL)

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  local sliderWidth = ui.availableSpaceX()
  ui.pushItemWidth(sliderWidth)
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
  if paramDef.hint ~= nil and ui.itemHovered() then
    ui.setTooltip(paramDef.hint)
  end

  if changed then
    valueObj:set(newValue)
  end

  if paramDef.ends ~= nil then
    local captionColor = ui.styleColor(ui.StyleColor.TextDisabled)
    ui.setCursorX(LABEL_COL)
    ui.textColored(paramDef.ends[1], captionColor)
    ui.sameLine(LABEL_COL + sliderWidth - ui.measureText(paramDef.ends[2]).x)
    ui.textColored(paramDef.ends[2], captionColor)
  end
end

---@param key string
---@param highlightIfModified boolean
function M.drawScheme(key, highlightIfModified)
  local paramDef = getParamDef(key)
  if paramDef == nil or paramDef.kind ~= 'scheme' then return end
  if paramDef.options == nil then return end

  local valueObj = getParamStorage(key)
  local optInd = clampParamValIfNeeded(tonumber(valueObj:get()), paramDef, getDefaultVal(key)) ---@cast optInd integer
  local defaultInd = getDefaultVal(key) ---@cast defaultInd integer
  local needHighlight = highlightIfModified and optInd ~= defaultInd

  drawParamLabel(key, highlightIfModified)
  ui.sameLine(LABEL_COL)
  ui.pushItemWidth(ui.availableSpaceX())

  if needHighlight then
    ui.pushStyleColor(ui.StyleColor.Text, MODIFIED_PARAM_COLOR)
  end

  local comboOpen = ui.beginCombo('##' .. key, paramDef.options[optInd] --[[@as string]])

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

  local valueObj = getParamStorage(key)
  local value = clampParamValIfNeeded(tonumber(valueObj:get()), paramDef, getDefaultVal(key))
  local checked = value ~= 0
  local needHighlight = highlightIfModified and value ~= getDefaultVal(key)

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

local segmentSize = vec2()

---Equal-width buttons in a row; the current one is lit. Returns the index clicked, if any.
---@param labels string[]
---@param current integer
---@param gap number?
---@return integer?
function M.drawSegmented(labels, current, gap)
  gap = gap or 4
  segmentSize:set((ui.availableSpaceX() - gap * (#labels - 1)) / #labels, 0)
  local picked
  for i, label in ipairs(labels) do
    if i > 1 then ui.sameLine(0, gap) end
    local active = i == current
    if active then ui.pushStyleColor(ui.StyleColor.Button, ui.styleColor(ui.StyleColor.ButtonActive)) end
    if ui.button(label, segmentSize) then picked = i end
    if active then ui.popStyleColor() end
  end
  return picked
end

---@param label string
function M.drawRowLabel(label)
  ui.text(label)
  ui.sameLine(LABEL_COL)
end

-- collisionHandlingMethod is stored as one number; the window shows it as two choices.
-- 0 nothing blocks the camera, 1/2 pull in at walls (physics/visuals), 3/4 also rise over ground.
local rise = true

function M.drawCollisionSettings()
  local method = M.get('collisionHandlingMethod') ---@cast method integer
  if method ~= 0 then rise = method >= 3 end
  local sees = method == 0 and 1 or (method % 2 == 0 and 3 or 2)

  M.drawRowLabel('Blocked by')
  local pickedSees = M.drawSegmented({ 'Nothing', 'Track', 'Track + trees' }, sees)
  if pickedSees ~= nil then
    method = pickedSees == 1 and 0 or (rise and 3 or 1) + (pickedSees == 3 and 1 or 0)
    getParamStorage('collisionHandlingMethod'):set(method)
  end
  if method == 0 then return end

  M.drawRowLabel('When blocked')
  local pickedAction = M.drawSegmented({ 'Pull in', 'Pull in + rise' }, rise and 2 or 1)
  if pickedAction ~= nil then
    rise = pickedAction == 2
    method = (rise and 3 or 1) + (method % 2 == 0 and 1 or 0)
    getParamStorage('collisionHandlingMethod'):set(method)
  end
  if ui.itemHovered() then
    ui.setTooltip('Pull in: closer to the car at walls. Rise: also lifts over ground and tunnel ceilings.')
  end

  if method >= 3 then M.drawSlider('collisionGroundClearance', true) end
  if method == 1 or method == 3 then M.drawSlider('collisionMaxHitHeight', true) end
  M.drawSlider('collisionMinDistance', true)
  M.drawCheckbox('collisionKeepSubjectSize', false)
  if M.get('collisionKeepSubjectSize') == 1 then
    M.drawSlider('collisionMaxFov', true)
  end
  M.drawCheckbox('disableCollisionWhenRecentered', false)
  if ui.itemHovered() then
    ui.setTooltip('Saves a little CPU. Checks resume when you orbit or zoom.')
  end
end

---@return boolean
function M.collisionsSupported()
  return supportsCollisions
end

---@return string
function M.collisionSummary()
  return ({ [0] = 'ignored', 'Pull in', 'Pull in', 'Pull in + rise', 'Pull in + rise' })[M.get('collisionHandlingMethod')]
end

---@param helicopter boolean
local function setHelicopterMode(helicopter)
  helicopterMode:set(helicopter and 1 or 0)
end

local CAPTION_COLOR = rgbm(0.55, 0.55, 0.6, 1)
local captionedButtonPos = vec2()

---A button with a small grey line under its label.
---@param title string
---@param caption string
---@param size vec2
---@return boolean
local function drawCaptionedButton(title, caption, size)
  local maxWidth = size.x - 12
  local titleFont, captionFont = 15, 12
  local titleHeight = ui.measureDWriteText(title, titleFont).y
  local captionHeight = ui.measureDWriteText(caption, captionFont).y
  local titleSize = ui.measureDWriteText(title, titleFont)
  local captionSize = ui.measureDWriteText(caption, captionFont)
  if captionSize.x > maxWidth then
    captionFont = math.floor(captionFont * maxWidth / captionSize.x)
    captionSize = ui.measureDWriteText(caption, captionFont)
  end
  if titleSize.x > maxWidth then
    titleFont = math.floor(titleFont * maxWidth / titleSize.x)
    titleSize = ui.measureDWriteText(title, titleFont)
  end
  size.y = titleHeight + captionHeight + 16
  local clicked = ui.button('##' .. title .. caption, size)
  local min = ui.itemRectMin()
  captionedButtonPos:set(min.x + (size.x - titleSize.x) / 2, min.y + 7)
  ui.dwriteDrawText(title, titleFont, captionedButtonPos, rgbm.colors.white)
  captionedButtonPos:set(min.x + (size.x - captionSize.x) / 2, min.y + 7 + titleHeight)
  ui.dwriteDrawText(caption, captionFont, captionedButtonPos, CAPTION_COLOR)
  return clicked
end

---@param title string
---@param hint string?
local function drawSection(title, hint)
  ui.newLine()
  ui.text(title)
  if hint ~= nil and ui.itemHovered() then ui.setTooltip(hint) end
  ui.separator()
end

function M.drawCameraTab()
  local helicopter = isHelicopterMode()
  local pickedMode = M.drawSegmented({ 'Chase', 'Helicopter' }, helicopter and 2 or 1)
  if pickedMode ~= nil then
    setHelicopterMode(pickedMode == 2)
    M.requestRecenter(false)
  end
  if ui.itemHovered() then
    ui.setTooltip('Each mode keeps its own settings. Helicopter is far away with a long lens.')
  end

  drawSection('Where the camera sits', 'Grey numbers are the live values, including speed extras and your manual orbit.')
  M.drawSlider('cameraDistance', true)
  M.drawSlider('cameraFov', true)
  M.drawSlider('cameraPitch', true)
  M.drawSlider('cameraTargetHeightOffset', true)

  drawSection('How it follows')
  M.drawSlider('cameraRelaxation', true)
  M.drawSlider('cameraSlopeFollow', true)

  drawSection('Extra at full speed', 'Added on top of the values above, growing with speed.')
  M.drawSlider('dynamicFovAtSpeed', true)
  M.drawSlider('dynamicPitchAtSpeed', true)
  M.drawSlider('dynamicHeightAtSpeed', true)

  ui.newLine()
  local buttonSize = vec2((ui.availableSpaceX() - 12) / 4, 0)
  if drawCaptionedButton('Straighten', 'behind the car', buttonSize) then
    M.requestRecenter(false)
  end
  ui.sameLine(0, 4)
  if drawCaptionedButton('Straighten', 'keep zoom & angle', buttonSize) then
    M.requestRecenter(true)
  end
  ui.sameLine(0, 4)
  if drawCaptionedButton('Save view', 'as default', buttonSize) then
    setDistanceAndPitchFromOrbit()
  end
  ui.sameLine(0, 4)
  if drawCaptionedButton('Reset', 'all sliders', buttonSize) then
    resetCameraParams()
  end
  if ui.itemHovered() then
    ui.setTooltip('Right-click a single slider to reset just that one.')
  end
end

return M
