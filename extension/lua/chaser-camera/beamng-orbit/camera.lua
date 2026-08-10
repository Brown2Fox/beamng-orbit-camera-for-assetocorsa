--------
-- BeamNG-style Orbit Camera for Assetto Corsa
--
-- Porting policy for this version:
--   * movement-following heading uses BeamNG orbit.lua camLastPos2/relaxation logic;
--   * speed height uses BeamNG's formula;
--   * dynamic pitch keeps BeamNG's threshold/timer structure;
--   * optional BEAMNG_ORBIT_TARGET/BEAMNG_ORBIT_REAR scene nodes mirror BeamNG per-vehicle references;
--   * dynamic FOV and pitch geometry otherwise use CSP car AABB references;
--   * collision handling ports BeamNG collision.lua near-clip sweep using CSP track raycasts;
--   * camera parameters are supplied live by the companion Lua App through paramsBridge;
--   * all device input is resolved by the companion Lua App; controlsBridge carries only cumulative manual input;
--   * target/rendered rotation separation matches BeamNG camRot/camLastRot smoothing.
--------

-- Camera settings are owned by the companion Lua App so they can be edited
-- live while a session is running. App/bridge angles are user-facing degrees;
-- orientation angles are converted once on sync and stored here in radians.
-- These defaults are also used if the app is unavailable.
local runtimeConfig = {
  cameraDistance = 5.0,
  cameraFov = 65.0,
  cameraTargetHeightOffset = 0.0,
  cameraPitchRad = math.rad(17.0),
  cameraRelaxation = 6.0,
  dynamicFovAtSpeed = 40.0,
  dynamicPitchAtSpeedRad = math.rad(7.0),
  dynamicHeightAtSpeed = 0.4,
}

-- Defining constants and conversion helpers.

local VEC3_ZERO = vec3(0, 0, 0)
local WORLD_UP = vec3(0, 1, 0)
local INPUT_ANGLE_EPSILON_RAD = 0.0001
local EPSILON = 1e-30

local CAMERA_DISTANCE_MIN = 3.0
local CAMERA_DISTANCE_MAX = 30.0

local CAMERA_PITCH_MIN_RAD = math.rad(-85)
local CAMERA_PITCH_MAX_RAD = math.rad(85)

local DYNAMIC_FOV_SPEED = 130.0

local DYNAMIC_PITCH_LOWER_SPEED = 1.0
local DYNAMIC_PITCH_UPPER_SPEED = 10.0
local DYNAMIC_PITCH_MANUAL_DELAY = 1.0
local DYNAMIC_PITCH_LOW_SPEED_DELAY = 1.5
local DYNAMIC_PITCH_RISE_RATE = 0.30
local DYNAMIC_PITCH_FALL_RATE = 0.50

-- BeamNG collision.lua constants. BeamNG computes its longitudinal plane
-- offset as data.res.nearClip - 0.1. CSP chaser-camera does not expose that
-- value here, so keep the plane centered on the desired camera position rather
-- than introduce an unrelated configurable approximation.
local COLLISION_ASSUMED_NEAR_CLIP_DISTANCE = 0.0
local COLLISION_NEAR_CLIP_HALF_WIDTH = 0.2
local COLLISION_NEAR_CLIP_HALF_HEIGHT = 0.1
local COLLISION_MIN_HIT_DISTANCE = 0.5
local COLLISION_RELEASE_RATE = 7.0

local MANUAL_YAW_LOCK_THRESHOLD_RAD = math.rad(10)

-- The Lua App owns persistent configuration and ControlButton input. Camera
-- parameters and live controls use separate shared structures.
local paramsBridge = nil
local controlsBridge = nil

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

do
  local okParams, connectedParams = pcall(function()
    return ac.connect({
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
  end)
  if okParams then paramsBridge = connectedParams end

  local okControls, connectedControls = pcall(function()
    return ac.connect({
      ac.StructItem.key('beamng_orbit_camera.controls_bridge'),
      seqNum = ac.StructItem.uint32(),

      yawTotalRad = ac.StructItem.double(),
      pitchTotalRad = ac.StructItem.double(),
      zoomTotal = ac.StructItem.double(),
      zoomDistanceTotal = ac.StructItem.double(),

      recenterSeqNum = ac.StructItem.uint32(),
      recenterKeepValuesSeqNum = ac.StructItem.uint32(),
    }, false, ac.SharedNamespace.Shared)
  end)
  if okControls then controlsBridge = connectedControls end
end

-- BeamNG keeps a target rotation (camRot) and a separately smoothed
-- rendered rotation (camLastRot). orbitYawRad/orbitPitchRad are targets;
-- displayedYawRad/displayedPitchRad are the rendered equivalents.
local orbitYawRad = 0.0
local orbitPitchRad = 0.0
local displayedYawRad = 0.0
local displayedPitchRad = 0.0
local orbitDistance = 0.0
local displayedDistance = 0.0
local orbitInitialized = false

-- BeamNG lockCamera state. After enough manual horizontal rotation, a vehicle
-- direction reversal swaps the internal heading hemisphere while preserving
-- the same world-space camera view.
local lockCamera = false
local accumulatedManualYawRad = 0.0
local lastAppliedFov = runtimeConfig.cameraFov

-- BeamNG equivalents:
-- camAnchor = camLastPos2, camAnchorPerp = camLastPosPerp,
-- targetPosLast = camLastTargetPos.
local headingReference = vec3(0, 0, 1)
local lastValidCarHeading = vec3(0, 0, 1)
local camAnchor = vec3()
local camAnchorPerp = vec3()
local targetPosLast = vec3()
local headingInitialized = false
local resetHeadingReference = false

local recenterWorldForward = vec3()


-- BeamNG dynamic-pitch state.
local timeSinceManualRotation = 1000.0
local abovePitchSpeedThreshold = false
local belowPitchThresholdTimer = nil
local dynamicPitchBlend = 0.0
local dynamicPitchVelocity = 0.0

-- Reused vectors.
local tmpCrossA = vec3()
local tmpCrossB = vec3()
local tmpHorizontal = vec3()
local tmpMoveDirection = vec3()
local lockedCameraDirection = vec3()
local lockedCameraFlipOffset = vec3()
local camPointVector = vec3()
local camPointVectorPerp = vec3()
local orbitForward = vec3()
local baseCameraPosition = vec3()
local finalCameraPosition = vec3()
local baseDirection = vec3()
local finalDirection = vec3()
local cameraRight = vec3()
local aabbRearLocal = vec3()
local aabbRearBottomLocal = vec3()
local aabbRearPoint = vec3()
local rearReferencePoint = vec3()
local rearBottomPoint = vec3()
local targetReferencePosition = vec3()
local defaultCameraOffsetLocal = vec3()
local defaultCameraOffsetWorld = vec3()
local toRearReference = vec3()
local toTarget = vec3()
local toRearBottom = vec3()

-- Optional per-car scene references. BeamNG can use vehicle-specific nodes for
-- its orbit target and dynamic-FOV rear reference. AC cars do not define such
-- nodes by default, so these names are an opt-in convention for cars that need
-- custom camera geometry. If absent, target falls back to car.position and the
-- dynamic-FOV rear reference falls back to the AABB rear face.
local targetReferenceNode = nil
local dynamicFovRearReferenceNode = nil
local vehicleReferenceNodesInitialized = false

-- BeamNG collision.lua state and scratch vectors.
local collisionUseRaycast = true
local collisionLastDistance = nil
local collisionHasLastNearClipCenter = false
local collisionLastNearClipCenter = vec3()
local collisionDirection = vec3()
local collisionRayDirection = vec3()
local collisionCamDirection = vec3()
local collisionCamRight = vec3()
local collisionCamUp = vec3()
local collisionNearClipCenter = vec3()
local collisionRayStart = vec3()
local collisionEdgeDirection = vec3()
local collisionCorrectedPosition = vec3()
local collisionRayDestinations = { vec3(), vec3(), vec3(), vec3() }

local function resetCollisionState()
  collisionUseRaycast = true
  collisionLastDistance = nil
  collisionHasLastNearClipCenter = false
end

local function refreshVehicleReferenceNodes()
  targetReferenceNode = nil
  dynamicFovRearReferenceNode = nil
  vehicleReferenceNodesInitialized = false

  if car == nil then return end

  local carRoot = ac.findNodes('carRoot:' .. car.index)
  if carRoot == nil or #carRoot == 0 then return end

  local body = carRoot:findNodes('BODYTR')
  if body == nil or #body == 0 then return end

  local targetNode = body:findNodes('BEAMNG_ORBIT_TARGET')
  if targetNode ~= nil and #targetNode > 0 then
    targetReferenceNode = targetNode
  end

  local rearNode = body:findNodes('BEAMNG_ORBIT_REAR')
  if rearNode ~= nil and #rearNode > 0 then
    dynamicFovRearReferenceNode = rearNode
  end

  vehicleReferenceNodesInitialized = true
end

local function resetCameraState()
  orbitInitialized = false

  lockCamera = false
  accumulatedManualYawRad = 0.0
  lastAppliedFov = runtimeConfig.cameraFov

  headingReference:set(0, 0, 1)
  lastValidCarHeading:set(0, 0, 1)
  headingInitialized = false
  resetHeadingReference = false

  timeSinceManualRotation = 1000.0
  abovePitchSpeedThreshold = false
  belowPitchThresholdTimer = nil
  dynamicPitchBlend = 0.0
  dynamicPitchVelocity = 0.0

  resetCollisionState()
end

---@param fallbackPosition vec3
---@return vec3
local function resolveTargetReference(fallbackPosition)
  if targetReferenceNode ~= nil then
    local transform = targetReferenceNode:getWorldTransformationRaw()
    if transform ~= nil then
      targetReferencePosition:set(transform.position)
      return targetReferencePosition
    end
  end
  return fallbackPosition
end

local function updateRearReference()
  rearReferencePoint:set(aabbRearPoint)
  if dynamicFovRearReferenceNode == nil then return end

  local transform = dynamicFovRearReferenceNode:getWorldTransformationRaw()
  if transform ~= nil then
    rearReferencePoint:set(transform.position)
  end
end

---@param value number
---@return number
local function clampDistance(value)
  return math.clamp(value, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)
end

local function syncCameraParams()
  if paramsBridge == nil or paramsBridge.ready ~= true then return end

  local seqNumBefore = tonumber(paramsBridge.seqNum) or 0
  if paramsBridgeInitialized and seqNumBefore == lastParamsBridgeSeqNum then return end

  local cameraDistance = paramsBridge.cameraDistance
  local cameraFov = paramsBridge.cameraFov
  local cameraTargetHeightOffset = paramsBridge.cameraTargetHeightOffset
  local cameraPitchRad = math.rad(paramsBridge.cameraPitch)
  local cameraRelaxation = paramsBridge.cameraRelaxation
  local dynamicFovAtSpeed = paramsBridge.dynamicFovAtSpeed
  local dynamicPitchAtSpeedRad = math.rad(paramsBridge.dynamicPitchAtSpeed)
  local dynamicHeightAtSpeed = paramsBridge.dynamicHeightAtSpeed

  local seqNumAfter = tonumber(paramsBridge.seqNum) or 0
  if seqNumBefore ~= seqNumAfter or paramsBridge.ready ~= true then return end

  local distanceChanged = math.abs(cameraDistance - runtimeConfig.cameraDistance) > 0.000001
  local pitchChanged = math.abs(cameraPitchRad - runtimeConfig.cameraPitchRad) > 0.000001

  runtimeConfig.cameraDistance = cameraDistance
  runtimeConfig.cameraFov = cameraFov
  runtimeConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  runtimeConfig.cameraPitchRad = cameraPitchRad
  runtimeConfig.cameraRelaxation = cameraRelaxation
  runtimeConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  runtimeConfig.dynamicPitchAtSpeedRad = dynamicPitchAtSpeedRad
  runtimeConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed

  if orbitInitialized then
    if distanceChanged then orbitDistance = cameraDistance end
    if pitchChanged then orbitPitchRad = cameraPitchRad end
  end

  lastParamsBridgeSeqNum = seqNumAfter
  paramsBridgeInitialized = true
end

---@return number yawStepRad, number pitchStepRad, number zoomStep, number zoomDistanceStep, boolean recenterPressed, boolean recenterKeepValuesPressed
local function readControlsInput()
  if controlsBridge == nil then return 0, 0, 0, 0, false, false end

  local seqNumBefore = tonumber(controlsBridge.seqNum) or 0
  if controlsBridgeInitialized and seqNumBefore == lastControlsBridgeSeqNum then
    return 0, 0, 0, 0, false, false
  end

  local yawTotalRad = controlsBridge.yawTotalRad or 0
  local pitchTotalRad = controlsBridge.pitchTotalRad or 0
  local zoomTotal = controlsBridge.zoomTotal or 0
  local zoomDistanceTotal = controlsBridge.zoomDistanceTotal or 0
  local recenterSeqNum = tonumber(controlsBridge.recenterSeqNum) or 0
  local recenterKeepValuesSeqNum = tonumber(controlsBridge.recenterKeepValuesSeqNum) or 0

  local seqNumAfter = tonumber(controlsBridge.seqNum) or 0
  if seqNumBefore ~= seqNumAfter then
    return 0, 0, 0, 0, false, false
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
    return 0, 0, 0, 0, false, false
  end

  local yawStepRad = yawTotalRad - lastYawTotalRad
  local pitchStepRad = pitchTotalRad - lastPitchTotalRad
  local zoomStep = zoomTotal - lastZoomTotal
  local zoomDistanceStep = zoomDistanceTotal - lastZoomDistanceTotal
  local recenterPressed = recenterSeqNum ~= lastRecenterSeqNum
  local recenterKeepValuesPressed = recenterKeepValuesSeqNum ~= lastRecenterKeepValuesSeqNum

  lastControlsBridgeSeqNum = seqNumAfter
  lastYawTotalRad = yawTotalRad
  lastPitchTotalRad = pitchTotalRad
  lastZoomTotal = zoomTotal
  lastZoomDistanceTotal = zoomDistanceTotal
  lastRecenterSeqNum = recenterSeqNum
  lastRecenterKeepValuesSeqNum = recenterKeepValuesSeqNum

  -- If the app/shared bridge was recreated and cumulative totals restarted,
  -- discard the discontinuity instead of producing a camera jump.
  if math.abs(yawStepRad) > math.pi * 4
      or math.abs(pitchStepRad) > math.pi * 4
      or math.abs(zoomStep) > 10
      or math.abs(zoomDistanceStep) > 100 then
    return 0, 0, 0, 0, recenterPressed, recenterKeepValuesPressed
  end

  return yawStepRad, pitchStepRad, zoomStep, zoomDistanceStep, recenterPressed, recenterKeepValuesPressed
end

---@param source vec3
---@return vec3
local function planarHeading(source)
  local result = source - WORLD_UP * source:dot(WORLD_UP)
  local length = #result
  if length < 0.0001 then return VEC3_ZERO end
  return result / length
end

---@param angleRad number
---@return number
local function wrapAngle(angleRad)
  return (angleRad + math.pi) % (2 * math.pi) - math.pi
end

---@param currentAngleRad number
---@param targetAngleRad number
---@return number
local function shortestAngleDifference(currentAngleRad, targetAngleRad)
  return (targetAngleRad - currentAngleRad + math.pi) % (2 * math.pi) - math.pi
end

---@param from vec3
---@param to vec3
---@return number
local function signedHeadingError(from, to)
  from:cross(to, tmpCrossA)
  ---@diagnostic disable-next-line: redundant-parameter
  return math.atan(tmpCrossA:dot(WORLD_UP), math.clamp(from:dot(to), -1, 1))
end

---@param current number
---@param velocity number
---@param target number
---@param rate number
---@param accel number
---@param dt number
---@return number, number
local function rateAccelStep(current, velocity, target, rate, accel, dt)
  -- Approximation of BeamNG temporalSigmoidSmoothing: move a value with a
  -- limited rate and inertia, braking early enough to settle without overshoot.
  -- orbit.lua calls getWithRateAccel() with 0.3 for rise and 0.5 for fall;
  -- those numbers are rate/acceleration limits, not transition durations.
  rate = math.max(0.001, rate or 0)
  accel = math.max(0.001, accel or rate)
  dt = math.max(0, dt or 0)

  local delta = target - current
  if math.abs(delta) < 0.000001 and math.abs(velocity) < 0.000001 then
    return target, 0
  end

  local direction = math.sign(delta)
  local brakingLimitedRate = math.sqrt(math.max(0, 2 * accel * math.abs(delta)))
  local desiredVelocity = direction * math.min(rate, brakingLimitedRate)
  local maxVelocityChange = accel * dt
  velocity = velocity + math.clamp(
    desiredVelocity - velocity,
    -maxVelocityChange,
    maxVelocityChange
  )

  local nextValue = current + velocity * dt
  if delta * (target - nextValue) <= 0 then
    return target, 0
  end

  return math.clamp(nextValue, 0, 1), velocity
end


---@param targetPos vec3
---@param carHeading vec3
local function initializeHeading(targetPos, carHeading)
  headingReference:set(carHeading)
  camAnchor:set(targetPos - carHeading * runtimeConfig.cameraRelaxation)

  WORLD_UP:cross(carHeading, tmpCrossA)
  local rightLength = #tmpCrossA
  if rightLength > 0.0001 then
    camAnchorPerp:set(targetPos + tmpCrossA * (-runtimeConfig.cameraRelaxation * 0.8 / rightLength))
  else
    camAnchorPerp:set(targetPos)
  end

  targetPosLast:set(targetPos)
  headingInitialized = true
  resetHeadingReference = false
end

---@param targetPos vec3
local function handleLockedCameraHemisphere(targetPos)
  if not lockCamera or not headingInitialized then return end

  -- Direct port of BeamNG orbit.lua lockCamera reversal handling:
  -- camdir = camLastTargetPos - camLastPos2
  -- if movement is opposite camdir, add 180 degrees to camRot and move
  -- camLastPos2 to the opposite side. These two changes cancel in world
  -- space, so the rendered camera does not orbit around the vehicle.
  lockedCameraDirection:set(targetPosLast - camAnchor)
  if #lockedCameraDirection < 0.0001 then return end

  tmpMoveDirection:set(targetPos - targetPosLast)

  if tmpMoveDirection:dot(lockedCameraDirection) < 0 then
    -- BeamNG applies the hemisphere flip to both camRot and camLastRot.
    -- Updating both target and rendered yaw should preserve the current world view.
    orbitYawRad = wrapAngle(orbitYawRad + math.pi)
    displayedYawRad = wrapAngle(displayedYawRad + math.pi)

    -- CSP adaptation: orbitYawRad is a rotation around fixed WORLD_UP (Y). A 180°
    -- yaw negates X/Z but preserves Y. Simply moving the anchor by the full
    -- lockedCameraDirection would also negate its vertical component when
    -- updateMovementHeading() rebuilds targetPos - camAnchor, producing an
    -- instantaneous pitch-like jump on slopes. Reflect only the anchor offset's
    -- Y component here so the rebuilt heading becomes a true WORLD_UP half-turn:
    --   old heading:        ( x,  y,  z)
    --   heading after flip: (-x,  y, -z)
    --   +180° yaw:          ( x,  y,  z)
    -- Thus the world-space camera direction remains continuous in all 3 axes.
    lockedCameraFlipOffset:set(
      lockedCameraDirection.x,
      -lockedCameraDirection.y,
      lockedCameraDirection.z
    )
    camAnchor:set(targetPos + lockedCameraFlipOffset)

    WORLD_UP:cross(lockedCameraDirection, tmpCrossA)
    local rightLength = #tmpCrossA
    if rightLength > 0.0001 then
      camAnchorPerp:set(
        targetPos + tmpCrossA * (-runtimeConfig.cameraRelaxation * 0.8 / rightLength)
      )
    else
      camAnchorPerp:set(targetPos)
    end
  end
end

---@param targetPos vec3
---@param carHeading vec3
---@param dt number
local function updateMovementHeading(targetPos, carHeading, dt)
  if not headingInitialized
      or resetHeadingReference
      or dt > 0.2
      or #(targetPos - targetPosLast) > 25.0 then
    initializeHeading(targetPos, carHeading)
    return
  end

  -- BeamNG: lastCamPointVec = targetPos - camLastPos2
  camPointVector:set(targetPos - camAnchor)
  -- BeamNG: lastCamLastPerp = camLastPosPerp - targetPos
  camPointVectorPerp:set(camAnchorPerp - targetPos)

  local pointLength = #camPointVector
  local perpLength = #camPointVectorPerp

  if pointLength < runtimeConfig.cameraRelaxation and perpLength > runtimeConfig.cameraRelaxation * 0.8 then
    tmpMoveDirection:set(targetPos - targetPosLast)
    local moveLength = #tmpMoveDirection
    if moveLength > 0.0001 and pointLength > 0.0001 and perpLength > 0.0001 then
      tmpMoveDirection:set(tmpMoveDirection / moveLength)
      local pointAlongMove = math.abs((camPointVector / pointLength):dot(tmpMoveDirection))
      local perpAlongMove = math.abs((camPointVectorPerp / perpLength):dot(tmpMoveDirection))

      if pointAlongMove > perpAlongMove then
        camPointVector:cross(camPointVectorPerp, tmpCrossA)
        tmpCrossA:cross(camPointVectorPerp, tmpCrossB)
        local correctedLength = #tmpCrossB
        if correctedLength > 0.0001 then
          camAnchor:set(targetPos + tmpCrossB / correctedLength)
          camPointVector:set(targetPos - camAnchor)
          pointLength = #camPointVector
        end
      end
    end
  end

  if pointLength > 0.0001 then
    headingReference:set(camPointVector / pointLength)
  else
    headingReference:set(carHeading)
  end

  -- BeamNG flattens the rotation plane when the camera moves perpendicularly.
  -- Its world-up axis is Z; AC uses Y, hence x/z form the horizontal plane here.
  tmpHorizontal:set(headingReference.x, 0, headingReference.z)
  local horizontalLength = #tmpHorizontal
  if horizontalLength > 0.0001 then
    local coefficient = math.sqrt(math.max(0, 1 - horizontalLength))
    headingReference:set(
      headingReference * math.max(0, 1 - coefficient)
        + tmpHorizontal * (coefficient / (horizontalLength + EPSILON))
    )
    headingReference:normalize()
  end

  -- BeamNG keeps camLastPos2 exactly relaxation metres from targetPos.
  camPointVector:set(camAnchor - targetPos)
  local anchorLength = #camPointVector
  if anchorLength > 0.0001 then
    camAnchor:set(targetPos + camPointVector * (runtimeConfig.cameraRelaxation / anchorLength))
  else
    camAnchor:set(targetPos - headingReference * runtimeConfig.cameraRelaxation)
  end

  WORLD_UP:cross(headingReference, tmpCrossA)
  local rightLength = #tmpCrossA
  if rightLength > 0.0001 then
    camAnchorPerp:set(targetPos + tmpCrossA * (-runtimeConfig.cameraRelaxation * 0.8 / rightLength))
  else
    camAnchorPerp:set(targetPos)
  end

  targetPosLast:set(targetPos)
end

---@param keepPitchAndDistance boolean
---@param targetPos vec3
---@param carHeading vec3
local function requestRecenter(keepPitchAndDistance, targetPos, carHeading)
  -- BeamNG reset() immediately sets camRot to its target defaults while
  -- preserving the current rendered view in camLastRot/camLastDist. Recreate
  -- that separation here: displayedYawRad/displayedPitchRad stay at the current view,
  -- while orbitYawRad/orbitPitchRad become the new targets.
  headingReference:rotate(quat.fromAngleAxis(displayedYawRad, WORLD_UP), recenterWorldForward)
  if #recenterWorldForward > 0.0001 then
    recenterWorldForward:normalize()
  else
    recenterWorldForward:set(carHeading)
  end

  initializeHeading(targetPos, carHeading)
  displayedYawRad = signedHeadingError(carHeading, recenterWorldForward)
  orbitYawRad = 0.0

  if keepPitchAndDistance then
    orbitPitchRad = displayedPitchRad
  else
    orbitPitchRad = runtimeConfig.cameraPitchRad
    orbitDistance = runtimeConfig.cameraDistance
  end

  lockCamera = false
  accumulatedManualYawRad = 0.0
  resetCollisionState()
end

---@param targetPos vec3
---@param carHeading vec3
---@param recenterPressed boolean
---@param recenterKeepValuesPressed boolean
local function updateControlButtons(targetPos, carHeading, recenterPressed, recenterKeepValuesPressed)
  if recenterPressed then
    requestRecenter(false, targetPos, carHeading)
  end

  if recenterKeepValuesPressed then
    requestRecenter(true, targetPos, carHeading)
  end
end

---@param speed number
---@param manualRotationActive boolean
---@param dt number
local function updateDynamicPitchState(speed, manualRotationActive, dt)
  if runtimeConfig.dynamicPitchAtSpeedRad <= 0 then
    abovePitchSpeedThreshold = false
    belowPitchThresholdTimer = nil
    dynamicPitchBlend = 0.0
    dynamicPitchVelocity = 0.0
    return
  end

  if manualRotationActive then
    timeSinceManualRotation = 0.0
  else
    timeSinceManualRotation = timeSinceManualRotation + dt
  end

  -- BeamNG leaves the current sigmoid value unchanged for one second after
  -- manual rotation. It does not force it to zero during that delay.
  if timeSinceManualRotation <= DYNAMIC_PITCH_MANUAL_DELAY then
    return
  end

  local upperSpeed = DYNAMIC_PITCH_UPPER_SPEED
  local lowerSpeed = DYNAMIC_PITCH_LOWER_SPEED

  if abovePitchSpeedThreshold then
    if speed < lowerSpeed then
      if belowPitchThresholdTimer == nil then
        belowPitchThresholdTimer = dynamicPitchBlend >= 0.995
          and DYNAMIC_PITCH_LOW_SPEED_DELAY
          or 0
      end

      belowPitchThresholdTimer = belowPitchThresholdTimer - dt
      if belowPitchThresholdTimer <= 0 then
        abovePitchSpeedThreshold = false
        belowPitchThresholdTimer = nil
      end
    else
      belowPitchThresholdTimer = nil
    end
  else
    abovePitchSpeedThreshold = speed > upperSpeed
  end

  local target = abovePitchSpeedThreshold and 1 or 0
  local rate = target > dynamicPitchBlend
    and DYNAMIC_PITCH_RISE_RATE
    or DYNAMIC_PITCH_FALL_RATE

  -- BeamNG uses newTemporalSigmoidSmoothing(2, 2, 2, 2), then overrides
  -- rate/start-accel/stop-accel with the same per-direction value. Using a
  -- rate-and-acceleration motion profile reproduces the long, inertial rise
  -- and the noticeably quicker return instead of treating 0.3/0.5 as seconds.
  dynamicPitchBlend, dynamicPitchVelocity = rateAccelStep(
    dynamicPitchBlend,
    dynamicPitchVelocity,
    target,
    rate,
    rate,
    dt
  )
end

local function updateAabbReferences()
  -- car.aabbCenter/aabbSize are in car model space. Transforming the two
  -- reference points with bodyTransform turns the local AABB into the
  -- car-oriented world-space box used by the camera.
  local center = car.aabbCenter
  local size = car.aabbSize

  local halfLength = math.abs(size.z) * 0.5
  local halfHeight = math.abs(size.y) * 0.5

  -- BeamNG dynamic FOV fallback: center of the rear OOBB face.
  aabbRearLocal:set(center.x, center.y, center.z - halfLength)
  car.bodyTransform:transformPointTo(aabbRearPoint, aabbRearLocal)

  -- BeamNG dynamic pitch limit: rear-bottom point on the OOBB centerline.
  aabbRearBottomLocal:set(center.x, center.y - halfHeight, center.z - halfLength)
  car.bodyTransform:transformPointTo(rearBottomPoint, aabbRearBottomLocal)
end

---@param targetPos vec3
---@param baseFov number
---@return number
local function calculateDynamicPitchLimit(targetPos, baseFov)
  -- BeamNG calculates this limit from the *default* orbit pose rather than the
  -- current manually rotated/zoomed camera. Our positive pitch convention is
  -- the sign-inverted equivalent of BeamNG's defaultRotation.y.
  local defaultPitchRad = runtimeConfig.cameraPitchRad
  local defaultDistance = runtimeConfig.cameraDistance

  defaultCameraOffsetLocal:set(
    0,
    math.sin(defaultPitchRad) * defaultDistance,
    -math.cos(defaultPitchRad) * defaultDistance
  )
  car.bodyTransform:transformVectorTo(defaultCameraOffsetWorld, defaultCameraOffsetLocal)

  -- Same geometry as BeamNG:
  -- bottomRearDir = bottomRear - defaultCamPos
  -- targetDir = -defaultCamPos
  toRearBottom:set(rearBottomPoint - targetPos - defaultCameraOffsetWorld)
  toTarget:set(defaultCameraOffsetWorld * -1)

  local targetLength = #toTarget
  local rearLength = #toRearBottom
  if targetLength < 0.0001 or rearLength < 0.0001 then return 0 end

  toTarget:set(toTarget / targetLength)
  toRearBottom:set(toRearBottom / rearLength)
  local separationAngleRad = math.acos(math.clamp(toTarget:dot(toRearBottom), -1, 1))
  return math.max(math.rad(baseFov * 0.5) - separationAngleRad, 0)
end

---@param targetDistance number
---@param smoothedDistance number
---@param speed number
---@param targetPos vec3
---@return number dynamicFov, number dynamicDistance
local function calculateDynamicFovAndDistance(targetDistance, smoothedDistance, speed, targetPos)
  -- Unlike BeamNG, this port has no per-vehicle orbit-camera FOV config.
  -- runtimeConfig.cameraFov is therefore exposed directly as the zero-speed/base FOV,
  -- instead of exposing BeamNG's global modifier on top of a hidden base.
  local baseFov = runtimeConfig.cameraFov

  local dynamicFov = math.clamp(
    baseFov + runtimeConfig.dynamicFovAtSpeed * math.min(1, speed / DYNAMIC_FOV_SPEED),
    10, 160)

  -- BeamNG uses the full 3D distance from targetPos to its rear reference.
  toRearReference:set(rearReferencePoint - targetPos)
  local refToRear = #toRearReference
  local halfToRad = math.pi / 360
  local ratio = math.tan(baseFov * halfToRad) / math.tan(dynamicFov * halfToRad)

  -- BeamNG computes a distance delta from target camDist, then adds it to the
  -- separately smoothed displayed distance (camLastDist interpolation).
  local fovDistanceDifference = (targetDistance - refToRear) * (ratio - 1)
  local dynamicDistance = math.max(0.1, smoothedDistance + fovDistanceDifference)
  return dynamicFov, dynamicDistance
end

---@param speed number
---@return number
local function calculateDynamicHeight(speed)
  -- Direct copy of BeamNG orbit.lua height-offset curve. The variable called
  -- smoothedVelocity in BeamNG is only a remapped scalar; it is not a temporal
  -- filter and therefore no additional smoothing is applied here.
  local velocity = math.min(speed, 70)
  local smoothedVelocity = math.max(velocity * 0.05 - 0.2, 0.0)
  local lengthValue = math.min((1.4 * smoothedVelocity) / (smoothedVelocity + 4.1), 1)
  -- BeamNG allows a signed offset: positive raises the camera, negative lowers it.
  return lengthValue * runtimeConfig.dynamicHeightAtSpeed
end

---@param startPos vec3
---@param direction vec3
---@param rayLength number
---@return number
local function castCollisionRay(startPos, direction, rayLength)
  if rayLength <= 0.0001 then return rayLength end

  collisionRayDirection:set(direction)
  local directionLength = #collisionRayDirection
  if directionLength <= 0.0001 then return rayLength end
  collisionRayDirection:set(collisionRayDirection / directionLength)

  local hitDistance = render.createRay(
    startPos,
    collisionRayDirection,
    rayLength
  ):track()

  if hitDistance == nil or hitDistance < 0 then return rayLength end
  return math.min(hitDistance, rayLength)
end

---@return boolean
local function isObstacleInFrontOfCamera()
  -- BeamNG collision.lua first checks whether the near-clip rectangle has
  -- crossed completely through static collision geometry in a single frame.
  if collisionHasLastNearClipCenter then
    collisionEdgeDirection:set(
      collisionRayDestinations[1] - collisionLastNearClipCenter
    )
    local rayDistance = #collisionEdgeDirection
    if rayDistance > 0.0001
        and castCollisionRay(
          collisionLastNearClipCenter,
          collisionEdgeDirection,
          rayDistance
        ) < rayDistance then
      return true
    end
  end

  -- Then test all four edges of the current near-clip rectangle. This lets
  -- the cheaper idle mode notice geometry entering the camera plane and
  -- re-enable the four full target-to-camera raycasts.
  for i = 1, 4 do
    local cornerPos = collisionRayDestinations[i]
    local rayDest = collisionRayDestinations[i % 4 + 1]
    collisionEdgeDirection:set(rayDest - cornerPos)
    local rayDistance = #collisionEdgeDirection
    if rayDistance > 0.0001
        and castCollisionRay(cornerPos, collisionEdgeDirection, rayDistance) < rayDistance then
      return true
    end
  end

  return false
end

---@param targetPos vec3
---@param desiredCameraPosition vec3
---@param desiredCameraDirection vec3
---@param dt number
local function applyCameraCollision(
    targetPos,
    desiredCameraPosition,
    desiredCameraDirection,
    dt)
  collisionDirection:set(desiredCameraPosition - targetPos)
  local directionLength = #collisionDirection
  if directionLength <= 0.0001 then
    collisionLastDistance = nil
    collisionHasLastNearClipCenter = false
    collisionUseRaycast = true
    return
  end

  local assumedNearClipDistance = COLLISION_ASSUMED_NEAR_CLIP_DISTANCE

  collisionCamDirection:set(desiredCameraDirection)
  local camDirectionLength = #collisionCamDirection
  if camDirectionLength > 0.0001 then
    collisionCamDirection:set(collisionCamDirection / camDirectionLength)
  else
    collisionCamDirection:set(collisionDirection * (-1 / directionLength))
  end

  -- Build the same near-clip rectangle as BeamNG. AC exposes WORLD_UP as the
  -- requested camera up vector, so derive an orthonormal right/up basis from
  -- the final rendered look direction.
  WORLD_UP:cross(collisionCamDirection, collisionCamRight)
  local rightLength = #collisionCamRight
  if rightLength <= 0.0001 then
    collisionCamRight:set(1, 0, 0)
  else
    collisionCamRight:set(collisionCamRight / rightLength)
  end
  collisionCamDirection:cross(collisionCamRight, collisionCamUp)
  local upLength = #collisionCamUp
  if upLength <= 0.0001 then
    collisionCamUp:set(WORLD_UP)
  else
    collisionCamUp:set(collisionCamUp / upLength)
  end
  collisionCamRight:set(collisionCamRight * COLLISION_NEAR_CLIP_HALF_WIDTH)
  collisionCamUp:set(collisionCamUp * COLLISION_NEAR_CLIP_HALF_HEIGHT)

  collisionNearClipCenter:set(
    targetPos
      + collisionDirection
        * ((directionLength - assumedNearClipDistance) / directionLength)
  )

  collisionRayDestinations[1]:set(
    collisionNearClipCenter + collisionCamUp + collisionCamRight
  )
  collisionRayDestinations[2]:set(
    collisionNearClipCenter - collisionCamUp + collisionCamRight
  )
  collisionRayDestinations[3]:set(
    collisionNearClipCenter - collisionCamUp - collisionCamRight
  )
  collisionRayDestinations[4]:set(
    collisionNearClipCenter + collisionCamUp - collisionCamRight
  )

  if not collisionUseRaycast and isObstacleInFrontOfCamera() then
    collisionUseRaycast = true
  end

  local closestHit = directionLength
  local hitRegistered = false
  if collisionUseRaycast then
    -- Direct BeamNG layout: four parallel rays from the target side to the
    -- four corners of the near-clip plane, keeping the closest static hit.
    for i = 1, 4 do
      local cornerPos = collisionRayDestinations[i]
      collisionRayStart:set(cornerPos - collisionDirection)
      local hitDistance = castCollisionRay(
        collisionRayStart,
        collisionDirection,
        closestHit
      )
      if hitDistance < closestHit then
        closestHit = hitDistance
        hitRegistered = true
      end
    end
    closestHit = math.max(closestHit, COLLISION_MIN_HIT_DISTANCE)
  end

  if not hitRegistered then
    collisionUseRaycast = false
  end

  -- BeamNG uses newTemporalSmoothingNonLinear(1, 7, 0), but bypasses the
  -- smoother whenever the camera must move inward. Preserve that important
  -- asymmetry here: collision response is immediate, release is smoothed.
  local smoothedDistance = closestHit
  if collisionLastDistance ~= nil then
    local destinationDifference = closestHit - collisionLastDistance
    if destinationDifference >= 0 then
      local smoothingT = 1 - math.exp(-COLLISION_RELEASE_RATE * math.max(dt, 0))
      smoothedDistance = collisionLastDistance
        + (closestHit - collisionLastDistance) * smoothingT
    end
  end

  collisionLastDistance = smoothedDistance
  collisionLastNearClipCenter:set(collisionNearClipCenter)
  collisionHasLastNearClipCenter = true

  collisionCorrectedPosition:set(
    targetPos
      + collisionDirection
        * ((smoothedDistance + assumedNearClipDistance) / directionLength)
  )
  desiredCameraPosition:set(collisionCorrectedPosition)
end

---@param dt number
---@param cameraIndex integer
---@diagnostic disable-next-line: lowercase-global
function update(dt, cameraIndex)

  -- Pull the latest app-side values before any camera state is initialized so
  -- the current session immediately starts with the persisted app settings.
  syncCameraParams()

  if not vehicleReferenceNodesInitialized then
    refreshVehicleReferenceNodes()
  end

  if not orbitInitialized then
    orbitPitchRad = runtimeConfig.cameraPitchRad
    displayedPitchRad = orbitPitchRad
    orbitYawRad = 0
    displayedYawRad = 0
    orbitDistance = runtimeConfig.cameraDistance
    displayedDistance = orbitDistance
    orbitInitialized = true
  end

  local velocity = ac.getCarVelocity()
  local carSpeed = #velocity

  local carHeading = planarHeading(car.look)
  if carHeading == VEC3_ZERO then
    carHeading = headingInitialized and headingReference or lastValidCarHeading
  else
    lastValidCarHeading = carHeading
  end

  local carPosition = ac.getCarPosition()
  local targetReference = resolveTargetReference(carPosition)
  local targetPos = targetReference + WORLD_UP * runtimeConfig.cameraTargetHeightOffset
  updateAabbReferences()
  updateRearReference()
  handleLockedCameraHemisphere(targetPos)
  updateMovementHeading(targetPos, carHeading, dt)
  local manualYawStepRad, manualPitchStepRad, zoomStep, zoomDistanceStep,
      recenterPressed, recenterKeepValuesPressed = readControlsInput()

  updateControlButtons(
    targetPos,
    carHeading,
    recenterPressed,
    recenterKeepValuesPressed
  )

  local manualRotationActive = math.abs(manualYawStepRad) > INPUT_ANGLE_EPSILON_RAD
    or math.abs(manualPitchStepRad) > INPUT_ANGLE_EPSILON_RAD

  -- BeamNG applies manual input to target camRot directly. Device-specific
  -- interpretation has already happened in the Lua App.
  orbitYawRad = wrapAngle(orbitYawRad + manualYawStepRad)
  orbitPitchRad = math.clamp(
    orbitPitchRad + manualPitchStepRad,
    CAMERA_PITCH_MIN_RAD,
    CAMERA_PITCH_MAX_RAD
  )

  -- BeamNG enables lockCamera only after more than 10 degrees of accumulated
  -- manual horizontal rotation. Pitch and zoom do not affect this state.
  if math.abs(manualYawStepRad) > INPUT_ANGLE_EPSILON_RAD then
    accumulatedManualYawRad = accumulatedManualYawRad + manualYawStepRad
  end
  if math.abs(accumulatedManualYawRad) > MANUAL_YAW_LOCK_THRESHOLD_RAD then
    lockCamera = true
  end

  -- BeamNG rotation smoothing:
  --   ratio = 1 / (dt * 8)
  --   t = 1 / (ratio + 1) = dt * 8 / (1 + dt * 8)
  -- During active manual input maxRot is raised to 1000 rad/s, leaving the
  -- dt*8 interpolation as the visible smoothing. With no input, yaw catch-up
  -- is capped at 4.5 rad/s exactly like orbit.lua.
  local rotationSmoothingT = (dt * 8) / (1 + dt * 8)
  local maxRenderedYawSpeedRadPerSec = manualRotationActive and 1000 or 4.5
  local yawErrorRad = shortestAngleDifference(displayedYawRad, orbitYawRad)
  local renderedYawStepRad = math.clamp(
    yawErrorRad * rotationSmoothingT,
    -maxRenderedYawSpeedRadPerSec * dt,
    maxRenderedYawSpeedRadPerSec * dt
  )

  displayedYawRad = wrapAngle(displayedYawRad + renderedYawStepRad)
  displayedPitchRad = math.clamp(
    displayedPitchRad + (orbitPitchRad - displayedPitchRad) * rotationSmoothingT,
    CAMERA_PITCH_MIN_RAD,
    CAMERA_PITCH_MAX_RAD
  )

  -- BeamNG changes camDist directly. Its expression is:
  -- zoomChange * (dt * 1000) * data.speed * 0.0001 * currentFov.
  -- CSP does not expose BeamNG's generic camera data.speed, so its neutral
  -- value of 1 is used here.
  -- Lua App already combines all zoom devices. zoomStep is integrated analogue/
  -- button intent; current FOV scaling remains here because FOV is camera state.
  -- zoomDistanceStep is a direct distance delta (currently mouse wheel).
  orbitDistance = clampDistance(
    orbitDistance
      + zoomStep * 0.1 * lastAppliedFov
      + zoomDistanceStep
  )

  -- BeamNG smooths rendered distance every frame with the same ratio used for
  -- orbit rotation: ratio = 1 / (dt * 8). orbitDistance remains the target
  -- camDist in metres, while displayedDistance corresponds to camLastDist.
  local distanceSmoothingT = (dt * 8) / (1 + dt * 8)
  displayedDistance = displayedDistance
    + (orbitDistance - displayedDistance) * distanceSmoothingT

  updateDynamicPitchState(carSpeed, manualRotationActive, dt)

  headingReference:rotate(quat.fromAngleAxis(displayedYawRad, WORLD_UP), orbitForward)
  orbitForward:normalize()

  local dynamicFov, dynamicDistance = calculateDynamicFovAndDistance(
    orbitDistance,
    displayedDistance,
    carSpeed,
    targetPos
  )
  local horizontalDistance = math.cos(displayedPitchRad) * dynamicDistance
  local verticalDistance = math.sin(displayedPitchRad) * dynamicDistance

  baseCameraPosition:set(
    targetPos
      - orbitForward * horizontalDistance
      + WORLD_UP * verticalDistance
  )

  local heightOffset = calculateDynamicHeight(carSpeed)
  finalCameraPosition:set(baseCameraPosition + WORLD_UP * heightOffset)

  -- Match BeamNG ordering: direction is calculated from the unshifted orbit
  -- position, then dynamic height is added only to the final position.
  baseDirection:set(targetPos - baseCameraPosition)
  if #baseDirection > 0.0001 then
    baseDirection:normalize()
  else
    baseDirection:set(orbitForward)
  end

  local dynamicPitchAngleRad = 0
  if dynamicPitchBlend > 0.0001 and runtimeConfig.dynamicPitchAtSpeedRad > 0 then
    local pitchLimitRad = calculateDynamicPitchLimit(targetPos, runtimeConfig.cameraFov)
    -- BeamNG applies dynamic pitch with a negative angle. With AC's Y-up
    -- coordinate system and cameraRight axis this pitches the view upward,
    -- moving the vehicle lower on screen just like orbit.lua.
    dynamicPitchAngleRad = -math.min(runtimeConfig.dynamicPitchAtSpeedRad, pitchLimitRad) * dynamicPitchBlend
  end

  WORLD_UP:cross(baseDirection, cameraRight)
  if #cameraRight > 0.0001 and math.abs(dynamicPitchAngleRad) > 0.000001 then
    cameraRight:normalize()
    baseDirection:rotate(quat.fromAngleAxis(dynamicPitchAngleRad, cameraRight), finalDirection)
    finalDirection:normalize()
  else
    finalDirection:set(baseDirection)
  end

  -- BeamNG applies collision as the final camera-position filter, after orbit,
  -- dynamic FOV/height and dynamic pitch have already produced the view.
  applyCameraCollision(targetPos, finalCameraPosition, finalDirection, dt)

  ac.Camera.position = finalCameraPosition
  ac.Camera.direction = finalDirection
  ac.Camera.up = WORLD_UP
  ac.Camera.fov = dynamicFov
  lastAppliedFov = dynamicFov
end

function script.onCarChanged()
  -- CSP updates global `car` before this callback. Refresh any optional
  -- vehicle-specific camera nodes and restart all camera state for the new car.
  refreshVehicleReferenceNodes()
  resetCameraState()
end
