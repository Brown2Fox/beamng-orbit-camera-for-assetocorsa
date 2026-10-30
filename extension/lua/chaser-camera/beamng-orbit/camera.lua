
local OrbitCamera = require('modules/orbit-camera')

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

---@type CameraBridgeLayout
local cameraBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.camera_bridge_v4'),
  cameraIndex = ac.StructItem.uint32(),
  currentPitch = ac.StructItem.double(),
  currentDistance = ac.StructItem.double(),
  currentFov = ac.StructItem.double(),
  currentHeight = ac.StructItem.double(),
  orbitPitch = ac.StructItem.double(),
  orbitDistance = ac.StructItem.double(),
  orbitFov = ac.StructItem.double(),
}, false, ac.SharedNamespace.Shared)

---@type BeamNGOrbitCameraConfig
local cameraConfig = {
  cameraDistance = 5.0,
  cameraFov = 65.0,
  cameraTargetHeightOffset = 0.0,
  cameraPitch = 17.0,
  cameraRelaxation = 6.0,
  cameraSlopeFollow = 1.0,
  dynamicFovAtSpeed = 40.0,
  dynamicPitchAtSpeed = 7.0,
  dynamicHeightAtSpeed = 0.4,
  collisionHandlingMethod = 4,
  disableCollisionWhenRecentered = false,
  keepViewOnCarSwitch = false,
  collisionKeepSubjectSize = true,
  collisionGroundClearance = 0.3,
  collisionMaxFov = 90.0,
  collisionMinDistance = 2.5,
  collisionMaxHitHeight = 4.0,
}

---@type BeamNGOrbitCameraInput
local cameraInput = {
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

local lastParamsBridgeSeqNum = 0
local paramsBridgeInitialized = false

local lastControlsBridgeSeqNum = 0
local controlsBridgeInitialized = false
local lastYawTotalRad = 0.0
local lastPitchTotalRad = 0.0
local lastZoomTotal = 0.0
local lastZoomDistanceTotal = 0.0
local lastZoomFovTotal = 0.0
local lastZoomDollyTotal = 0.0
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
  local cameraSlopeFollow = paramsBridge.cameraSlopeFollow
  local dynamicFovAtSpeed = paramsBridge.dynamicFovAtSpeed
  local dynamicPitchAtSpeed = paramsBridge.dynamicPitchAtSpeed
  local dynamicHeightAtSpeed = paramsBridge.dynamicHeightAtSpeed
  local collisionHandlingMethod = paramsBridge.collisionHandlingMethod
  local disableCollisionWhenRecentered =
    paramsBridge.disableCollisionWhenRecentered
  local keepViewOnCarSwitch = paramsBridge.keepViewOnCarSwitch
  local collisionKeepSubjectSize = paramsBridge.collisionKeepSubjectSize
  local collisionGroundClearance = paramsBridge.collisionGroundClearance
  local collisionMaxFov = paramsBridge.collisionMaxFov
  local collisionMinDistance = paramsBridge.collisionMinDistance
  local collisionMaxHitHeight = paramsBridge.collisionMaxHitHeight

  local seqNumAfter = paramsBridge.seqNum
  if seqNumBefore ~= seqNumAfter or not paramsBridge.ready then return end

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
  cameraConfig.disableCollisionWhenRecentered =
    disableCollisionWhenRecentered
  cameraConfig.keepViewOnCarSwitch = keepViewOnCarSwitch
  cameraConfig.collisionKeepSubjectSize = collisionKeepSubjectSize
  cameraConfig.collisionGroundClearance = collisionGroundClearance
  cameraConfig.collisionMaxFov = collisionMaxFov
  cameraConfig.collisionMinDistance = collisionMinDistance
  cameraConfig.collisionMaxHitHeight = collisionMaxHitHeight

  lastParamsBridgeSeqNum = seqNumAfter
  paramsBridgeInitialized = true
end

---@return BeamNGOrbitCameraInput
local function readControlsInput()
  cameraInput.yawStepRad = 0
  cameraInput.pitchStepRad = 0
  cameraInput.zoomStep = 0
  cameraInput.zoomDistanceStep = 0
  cameraInput.zoomFovStep = 0
  cameraInput.zoomDollyStep = 0
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
  local zoomFovTotal = controlsBridge.zoomFovTotal
  local zoomDollyTotal = controlsBridge.zoomDollyTotal
  local recenterSeqNum = controlsBridge.recenterSeqNum
  local recenterKeepValuesSeqNum = controlsBridge.recenterKeepValuesSeqNum
  local glanceLeft = controlsBridge.glanceLeft
  local glanceRight = controlsBridge.glanceRight
  local glanceBack = controlsBridge.glanceBack

  local seqNumAfter = controlsBridge.seqNum
  if seqNumBefore ~= seqNumAfter then
    return cameraInput
  end

  cameraInput.glanceLeft = glanceLeft
  cameraInput.glanceRight = glanceRight
  cameraInput.glanceBack = glanceBack

  if not controlsBridgeInitialized then
    lastControlsBridgeSeqNum = seqNumAfter
    lastYawTotalRad = yawTotalRad
    lastPitchTotalRad = pitchTotalRad
    lastZoomTotal = zoomTotal
    lastZoomDistanceTotal = zoomDistanceTotal
    lastZoomFovTotal = zoomFovTotal
    lastZoomDollyTotal = zoomDollyTotal
    lastRecenterSeqNum = recenterSeqNum
    lastRecenterKeepValuesSeqNum = recenterKeepValuesSeqNum
    controlsBridgeInitialized = true
    return cameraInput
  end

  cameraInput.yawStepRad = yawTotalRad - lastYawTotalRad
  cameraInput.pitchStepRad = pitchTotalRad - lastPitchTotalRad
  cameraInput.zoomStep = zoomTotal - lastZoomTotal
  cameraInput.zoomDistanceStep = zoomDistanceTotal - lastZoomDistanceTotal
  cameraInput.zoomFovStep = zoomFovTotal - lastZoomFovTotal
  cameraInput.zoomDollyStep = zoomDollyTotal - lastZoomDollyTotal
  cameraInput.recenterPressed = recenterSeqNum ~= lastRecenterSeqNum
  cameraInput.recenterKeepValuesPressed = recenterKeepValuesSeqNum
    ~= lastRecenterKeepValuesSeqNum

  lastControlsBridgeSeqNum = seqNumAfter
  lastYawTotalRad = yawTotalRad
  lastPitchTotalRad = pitchTotalRad
  lastZoomTotal = zoomTotal
  lastZoomDistanceTotal = zoomDistanceTotal
  lastZoomFovTotal = zoomFovTotal
  lastZoomDollyTotal = zoomDollyTotal
  lastRecenterSeqNum = recenterSeqNum
  lastRecenterKeepValuesSeqNum = recenterKeepValuesSeqNum

  if math.abs(cameraInput.yawStepRad) > math.pi * 4
      or math.abs(cameraInput.pitchStepRad) > math.pi * 4
      or math.abs(cameraInput.zoomStep) > 10
      or math.abs(cameraInput.zoomDistanceStep) > 100
      or math.abs(cameraInput.zoomFovStep) > 10
      or math.abs(cameraInput.zoomDollyStep) > 10 then
    cameraInput.yawStepRad = 0
    cameraInput.pitchStepRad = 0
    cameraInput.zoomStep = 0
    cameraInput.zoomDistanceStep = 0
    cameraInput.zoomFovStep = 0
    cameraInput.zoomDollyStep = 0
  end

  return cameraInput
end

---@param dt number
---@param cameraIndex integer
function update(dt, cameraIndex)
  syncCameraParams()

  if cameraBridge then
    cameraBridge.cameraIndex = cameraIndex;
  end

  local input = readControlsInput()

  local pose = OrbitCamera.update(
    dt,
    car,
    cameraConfig,
    input
  )

  if pose then
    cameraBridge.currentPitch = pose.currentPitch
    cameraBridge.currentDistance = pose.currentDistance
    cameraBridge.currentFov = pose.currentFov
    cameraBridge.currentHeight = pose.currentHeight
    cameraBridge.orbitPitch = pose.orbitPitch
    cameraBridge.orbitDistance = pose.orbitDistance
    cameraBridge.orbitFov = pose.orbitFov

    ac.Camera.position = pose.position
    ac.Camera.direction = pose.direction
    ac.Camera.up = pose.up
    ac.Camera.fov = pose.fov
  end
end

function script.onCarChanged()
  OrbitCamera.reset()
end
