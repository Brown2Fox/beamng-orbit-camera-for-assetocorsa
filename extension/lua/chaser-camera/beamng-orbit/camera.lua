--------
-- BeamNG-style Orbit Camera chaser adapter.
--
-- Runs the shared Orbit Camera core directly in the chaser-camera update
-- cadence, so the game camera is calculated from the same-frame vehicle state.
-- Settings and cumulative resolved input come from the companion Lua App.
--------

local OrbitCamera = require('modules/orbit-camera')

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

local cameraBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.camera_bridge'),
  cameraIndex = ac.StructItem.uint32(),
}, false, ac.SharedNamespace.Shared)

local cameraConfig = {
  cameraDistance = 5.0,
  cameraFov = 65.0,
  cameraTargetHeightOffset = 0.0,
  cameraPitch = 17.0,
  cameraRelaxation = 6.0,
  dynamicFovAtSpeed = 40.0,
  dynamicPitchAtSpeed = 7.0,
  dynamicHeightAtSpeed = 0.4,
}

local cameraInput = {
  yawStepRad = 0.0,
  pitchStepRad = 0.0,
  zoomStep = 0.0,
  zoomDistanceStep = 0.0,
  recenterPressed = false,
  recenterKeepValuesPressed = false,
}

local lastParamsBridgeSeqNum = 0
local paramsBridgeInitialized = false

local lastControlsBridgeSeqNum = 0
local controlsBridgeInitialized = false
local lastYawTotalRad = 0.0
local lastPitchTotalRad = 0.0
local lastZoomTotal = 0.0
local lastZoomDistanceTotal = 0.0
local lastRecenterSeqNum = 0
local lastRecenterKeepValuesSeqNum = 0

local function syncCameraParams()
  if not paramsBridge.ready then return end

  local seqNumBefore = paramsBridge.seqNum
  if paramsBridgeInitialized and seqNumBefore == lastParamsBridgeSeqNum then return end

  local cameraDistance = paramsBridge.cameraDistance
  local cameraFov = paramsBridge.cameraFov
  local cameraTargetHeightOffset = paramsBridge.cameraTargetHeightOffset
  local cameraPitch = paramsBridge.cameraPitch
  local cameraRelaxation = paramsBridge.cameraRelaxation
  local dynamicFovAtSpeed = paramsBridge.dynamicFovAtSpeed
  local dynamicPitchAtSpeed = paramsBridge.dynamicPitchAtSpeed
  local dynamicHeightAtSpeed = paramsBridge.dynamicHeightAtSpeed

  local seqNumAfter = paramsBridge.seqNum
  if seqNumBefore ~= seqNumAfter or not paramsBridge.ready then return end

  cameraConfig.cameraDistance = cameraDistance
  cameraConfig.cameraFov = cameraFov
  cameraConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  cameraConfig.cameraPitch = cameraPitch
  cameraConfig.cameraRelaxation = cameraRelaxation
  cameraConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  cameraConfig.dynamicPitchAtSpeed = dynamicPitchAtSpeed
  cameraConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed

  lastParamsBridgeSeqNum = seqNumAfter
  paramsBridgeInitialized = true
end

---@return table
local function readControlsInput()
  cameraInput.yawStepRad = 0
  cameraInput.pitchStepRad = 0
  cameraInput.zoomStep = 0
  cameraInput.zoomDistanceStep = 0
  cameraInput.recenterPressed = false
  cameraInput.recenterKeepValuesPressed = false

  local seqNumBefore = controlsBridge.seqNum
  if controlsBridgeInitialized and seqNumBefore == lastControlsBridgeSeqNum then
    return cameraInput
  end

  local yawTotalRad = controlsBridge.yawTotalRad
  local pitchTotalRad = controlsBridge.pitchTotalRad
  local zoomTotal = controlsBridge.zoomTotal
  local zoomDistanceTotal = controlsBridge.zoomDistanceTotal
  local recenterSeqNum = controlsBridge.recenterSeqNum
  local recenterKeepValuesSeqNum = controlsBridge.recenterKeepValuesSeqNum

  local seqNumAfter = controlsBridge.seqNum
  if seqNumBefore ~= seqNumAfter then
    return cameraInput
  end

  if not controlsBridgeInitialized then
    lastControlsBridgeSeqNum = seqNumAfter
    lastYawTotalRad = yawTotalRad
    lastPitchTotalRad = pitchTotalRad
    lastZoomTotal = zoomTotal
    lastZoomDistanceTotal = zoomDistanceTotal
    lastRecenterSeqNum = recenterSeqNum
    lastRecenterKeepValuesSeqNum = recenterKeepValuesSeqNum
    controlsBridgeInitialized = true
    return cameraInput
  end

  cameraInput.yawStepRad = yawTotalRad - lastYawTotalRad
  cameraInput.pitchStepRad = pitchTotalRad - lastPitchTotalRad
  cameraInput.zoomStep = zoomTotal - lastZoomTotal
  cameraInput.zoomDistanceStep = zoomDistanceTotal - lastZoomDistanceTotal
  cameraInput.recenterPressed = recenterSeqNum ~= lastRecenterSeqNum
  cameraInput.recenterKeepValuesPressed = recenterKeepValuesSeqNum
    ~= lastRecenterKeepValuesSeqNum

  lastControlsBridgeSeqNum = seqNumAfter
  lastYawTotalRad = yawTotalRad
  lastPitchTotalRad = pitchTotalRad
  lastZoomTotal = zoomTotal
  lastZoomDistanceTotal = zoomDistanceTotal
  lastRecenterSeqNum = recenterSeqNum
  lastRecenterKeepValuesSeqNum = recenterKeepValuesSeqNum

  -- If the App/shared bridge was recreated and cumulative totals restarted,
  -- discard the discontinuity instead of producing a camera jump.
  if math.abs(cameraInput.yawStepRad) > math.pi * 4
      or math.abs(cameraInput.pitchStepRad) > math.pi * 4
      or math.abs(cameraInput.zoomStep) > 10
      or math.abs(cameraInput.zoomDistanceStep) > 100 then
    cameraInput.yawStepRad = 0
    cameraInput.pitchStepRad = 0
    cameraInput.zoomStep = 0
    cameraInput.zoomDistanceStep = 0
  end

  return cameraInput
end

---@param dt number
---@param cameraIndex integer
---@diagnostic disable-next-line: lowercase-global
function update(dt, cameraIndex)
  syncCameraParams()

  if cameraBridge then
    cameraBridge.cameraIndex = cameraIndex;
  end

  local pose = OrbitCamera.update(
    dt,
    car,
    cameraConfig,
    readControlsInput()
  )

  if pose then
    ac.Camera.position = pose.position
    ac.Camera.direction = pose.direction
    ac.Camera.up = pose.up
    ac.Camera.fov = pose.fov
  end
end

function script.onCarChanged()
  OrbitCamera.reset()
end
