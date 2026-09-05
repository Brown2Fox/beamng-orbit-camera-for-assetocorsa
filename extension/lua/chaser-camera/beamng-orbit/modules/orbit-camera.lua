
---@class BeamNGOrbitCameraConfig
---@field cameraDistance number
---@field cameraFov number
---@field cameraTargetHeightOffset number
---@field cameraPitch number
---@field cameraRelaxation number
---@field dynamicFovAtSpeed number
---@field dynamicPitchAtSpeed number
---@field dynamicHeightAtSpeed number

---@class BeamNGOrbitCameraInput
---@field yawStepRad number
---@field pitchStepRad number
---@field zoomStep number
---@field zoomDistanceStep number
---@field recenterPressed boolean
---@field recenterKeepValuesPressed boolean
---@field glanceLeft boolean
---@field glanceRight boolean
---@field glanceBack boolean

---@class BeamNGOrbitCameraPose
---@field position vec3
---@field direction vec3
---@field up vec3
---@field fov number

---@class BeamNGOrbitCameraModule
local M = {}
---@type ac.StateCar
local car = nil
local currentCarIndex = -1

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

local lastCameraPitchDeg = 17.0
local lastDynamicPitchAtSpeedDeg = 7.0

---@type BeamNGOrbitCameraPose
local outputPose = {
  position = vec3(),
  direction = vec3(0, 0, 1),
  up = vec3(0, 1, 0),
  fov = 65.0,
}


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

local RELAXATION_SAFE_MIN = 0.5
local RELAXATION_BLEND_START_SPEED = 70*10.0/36.0
local RELAXATION_BLEND_END_SPEED = 140*10.0/36.0

local COLLISION_ASSUMED_NEAR_CLIP_DISTANCE = 0.0
local COLLISION_NEAR_CLIP_HALF_WIDTH = 0.2
local COLLISION_NEAR_CLIP_HALF_HEIGHT = 0.1
local COLLISION_MIN_HIT_DISTANCE = 0.5
local COLLISION_RELEASE_RATE = 7.0

local MANUAL_YAW_LOCK_THRESHOLD_RAD = math.rad(10)
local GLANCE_MOVEMENT_HEADING_START_SPEED = 2.0
local GLANCE_MOVEMENT_HEADING_FULL_SPEED = 8.0
local GLANCE_TRANSITION_DURATION = 0.15

local orbitYawRad = 0.0
local orbitPitchRad = 0.0
local displayedYawRad = 0.0
local displayedPitchRad = 0.0
local orbitDistance = 0.0
local displayedDistance = 0.0
local orbitInitialized = false

local effectiveRelaxation = RELAXATION_SAFE_MIN

local lockCamera = false
local accumulatedManualYawRad = 0.0
local lastAppliedFov = runtimeConfig.cameraFov

local headingReference = vec3(0, 0, 1)
local lastValidCarHeading = vec3(0, 0, 1)
local camAnchor = vec3()
local camAnchorPerp = vec3()
local targetPosLast = vec3()
local headingInitialized = false
local resetHeadingReference = false
local glanceTransitionActive = false
local glanceTransitionElapsed = 0.0
local glanceMode = 0

local recenterWorldForward = vec3()


local timeSinceManualRotation = 1000.0
local abovePitchSpeedThreshold = false
local belowPitchThresholdTimer = nil
local dynamicPitchBlend = 0.0
local dynamicPitchVelocity = 0.0

local tmpCrossA = vec3()
local tmpCrossB = vec3()
local tmpHorizontal = vec3()
local tmpMoveDirection = vec3()
local lockedCameraDirection = vec3()
local lockedCameraFlipOffset = vec3()
local camPointVector = vec3()
local camPointVectorPerp = vec3()
local normalOrbitForward = vec3()
local movementHeading = vec3()
local glanceBaseHeading = vec3()
local glanceTargetForward = vec3()
local glanceRenderedForward = vec3(0, 0, 1)
local glanceTransitionStartForward = vec3(0, 0, 1)
local glanceStartHorizontal = vec3()
local glanceTargetHorizontal = vec3()
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
local carPositionLocal = vec3()

local targetReferenceNode = nil
local dynamicFovRearReferenceNode = nil
local vehicleReferenceNodesInitialized = false

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
  glanceTransitionActive = false
  glanceTransitionElapsed = 0.0
  glanceMode = 0
  glanceRenderedForward:set(0, 0, 1)
  glanceTransitionStartForward:set(0, 0, 1)

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

---@param config table
local function applyRuntimeConfig(config)
  if config == nil then return end

  local cameraDistance = tonumber(config.cameraDistance) or runtimeConfig.cameraDistance
  local cameraFov = tonumber(config.cameraFov) or runtimeConfig.cameraFov
  local cameraTargetHeightOffset = tonumber(config.cameraTargetHeightOffset) or runtimeConfig.cameraTargetHeightOffset
  local cameraPitchDeg = tonumber(config.cameraPitch) or lastCameraPitchDeg
  local cameraRelaxation = tonumber(config.cameraRelaxation) or runtimeConfig.cameraRelaxation
  local dynamicFovAtSpeed = tonumber(config.dynamicFovAtSpeed) or runtimeConfig.dynamicFovAtSpeed
  local dynamicPitchAtSpeedDeg = tonumber(config.dynamicPitchAtSpeed) or lastDynamicPitchAtSpeedDeg
  local dynamicHeightAtSpeed = tonumber(config.dynamicHeightAtSpeed) or runtimeConfig.dynamicHeightAtSpeed

  local distanceChanged = math.abs(cameraDistance - runtimeConfig.cameraDistance) > 0.000001
  local pitchChanged = math.abs(cameraPitchDeg - lastCameraPitchDeg) > 0.000001

  runtimeConfig.cameraDistance = cameraDistance
  runtimeConfig.cameraFov = cameraFov
  runtimeConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  runtimeConfig.cameraRelaxation = cameraRelaxation
  runtimeConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  runtimeConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed

  if pitchChanged then
    runtimeConfig.cameraPitchRad = math.clamp(
      math.rad(cameraPitchDeg),
      CAMERA_PITCH_MIN_RAD,
      CAMERA_PITCH_MAX_RAD
    )
    lastCameraPitchDeg = cameraPitchDeg
  end

  if math.abs(dynamicPitchAtSpeedDeg - lastDynamicPitchAtSpeedDeg) > 0.000001 then
    runtimeConfig.dynamicPitchAtSpeedRad = math.max(0, math.rad(dynamicPitchAtSpeedDeg))
    lastDynamicPitchAtSpeedDeg = dynamicPitchAtSpeedDeg
  end

  if orbitInitialized then
    if distanceChanged then orbitDistance = clampDistance(cameraDistance) end
    if pitchChanged then orbitPitchRad = runtimeConfig.cameraPitchRad end
  end
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
  return math.atan2(tmpCrossA:dot(WORLD_UP), math.clamp(from:dot(to), -1, 1))
end

---@param from vec3
---@param to vec3
---@param t number
---@param out vec3
local function interpolateForward(from, to, t, out)
  local fromLength = #from
  local toLength = #to
  if fromLength <= 0.0001 or toLength <= 0.0001 then
    out:set(to)
    return
  end

  glanceStartHorizontal:set(from.x, 0, from.z)
  glanceTargetHorizontal:set(to.x, 0, to.z)
  local startHorizontalLength = #glanceStartHorizontal
  local targetHorizontalLength = #glanceTargetHorizontal
  if startHorizontalLength <= 0.0001 or targetHorizontalLength <= 0.0001 then
    out:set(from * (1 - t) + to * t)
    if #out > 0.0001 then out:normalize() end
    return
  end

  glanceStartHorizontal:set(glanceStartHorizontal / startHorizontalLength)
  glanceTargetHorizontal:set(glanceTargetHorizontal / targetHorizontalLength)
  local yawDelta = signedHeadingError(glanceStartHorizontal, glanceTargetHorizontal)
  glanceStartHorizontal:rotate(
    quat.fromAngleAxis(yawDelta * t, WORLD_UP),
    out
  )

  local fromPitch = math.asin(math.clamp(from.y / fromLength, -1, 1))
  local toPitch = math.asin(math.clamp(to.y / toLength, -1, 1))
  local pitch = fromPitch + (toPitch - fromPitch) * t
  local horizontalScale = math.cos(pitch)
  out:set(out.x * horizontalScale, math.sin(pitch), out.z * horizontalScale)
  out:normalize()
end

---@param dt number
---@param input BeamNGOrbitCameraInput
---@param carHeading vec3
---@param velocity vec3
---@param normalForward vec3
---@param out vec3
local function updateGlanceForward(dt, input, carHeading, velocity, normalForward, out)
  local glanceLeft = input.glanceLeft == true
  local glanceRight = input.glanceRight == true
  local glanceBack = input.glanceBack == true
  local nextGlanceMode = glanceBack and 3
    or glanceLeft ~= glanceRight and (glanceLeft and 1 or 2)
    or 0

  if nextGlanceMode ~= 0 then
    movementHeading:set(velocity.x, 0, velocity.z)
    local movementSpeed = #movementHeading
    if movementSpeed > 0.0001 then
      movementHeading:set(movementHeading / movementSpeed)
      local movementBlend = math.clamp(
        (movementSpeed - GLANCE_MOVEMENT_HEADING_START_SPEED)
          / (GLANCE_MOVEMENT_HEADING_FULL_SPEED - GLANCE_MOVEMENT_HEADING_START_SPEED),
        0,
        1
      )
      carHeading:rotate(
        quat.fromAngleAxis(
          signedHeadingError(carHeading, movementHeading) * movementBlend,
          WORLD_UP
        ),
        glanceBaseHeading
      )
    else
      glanceBaseHeading:set(carHeading)
    end

    if nextGlanceMode == 3 then
      glanceTargetForward:set(glanceBaseHeading * -1)
    else
      glanceBaseHeading:rotate(
        quat.fromAngleAxis(nextGlanceMode == 1 and math.pi * 0.5 or -math.pi * 0.5, WORLD_UP),
        glanceTargetForward
      )
    end
  else
    glanceTargetForward:set(normalForward)
  end
  glanceTargetForward:normalize()

  if nextGlanceMode ~= glanceMode then
    if glanceMode == 0 and not glanceTransitionActive then
      glanceRenderedForward:set(normalForward)
    end
    glanceTransitionStartForward:set(glanceRenderedForward)
    glanceTransitionElapsed = 0.0
    glanceTransitionActive = true
    glanceMode = nextGlanceMode
  end

  if glanceTransitionActive then
    glanceTransitionElapsed = glanceTransitionElapsed + math.max(dt, 0)
    local glanceT = math.clamp(glanceTransitionElapsed / GLANCE_TRANSITION_DURATION, 0, 1)
    glanceT = glanceT * glanceT * (3 - 2 * glanceT)
    interpolateForward(
      glanceTransitionStartForward,
      glanceTargetForward,
      glanceT,
      out
    )
    glanceRenderedForward:set(out)

    if glanceTransitionElapsed >= GLANCE_TRANSITION_DURATION then
      glanceTransitionActive = false
      glanceRenderedForward:set(glanceTargetForward)
      out:set(glanceTargetForward)
    end
  else
    out:set(glanceTargetForward)
    glanceRenderedForward:set(out)
  end
end

---@param state number
---@param previousVelocity number
---@param sample number
---@param dt number
---@param rateLimit number
---@param startAcceleration number
---@param stopAcceleration number
---@return number, number
local function temporalSigmoidGetWithRateAccel(
    state,
    previousVelocity,
    sample,
    dt,
    rateLimit,
    startAcceleration,
    stopAcceleration
)
  if dt <= 0 then
    return state, previousVelocity
  end

  local difference = sample - state
  local previousVelocityInTargetDirection = previousVelocity
    * math.max(math.sign(previousVelocity * difference), 0)
  local velocitySquared = previousVelocityInTargetDirection
    * previousVelocityInTargetDirection
  local absoluteDifference = math.abs(difference)
  local differenceSign = math.sign(difference)

  local accelerationDelta
  local doubleAbsoluteDifference = absoluteDifference * 2
  if velocitySquared > doubleAbsoluteDifference * stopAcceleration
      and doubleAbsoluteDifference > 0 then
    accelerationDelta = -differenceSign * math.min(
      (velocitySquared / doubleAbsoluteDifference) * dt,
      math.abs(previousVelocityInTargetDirection)
    )
  else
    accelerationDelta = differenceSign * startAcceleration * dt
  end

  state = state + differenceSign * math.min(
    math.min(
      math.abs(previousVelocityInTargetDirection + 0.5 * accelerationDelta),
      rateLimit
    ) * dt,
    absoluteDifference
  )

  previousVelocity = differenceSign * math.min(
    math.abs(previousVelocityInTargetDirection + accelerationDelta),
    rateLimit
  )

  return state, previousVelocity
end

---@param speed number
---@return number
local function getEffectiveRelaxation(speed)
  local configuredRelaxation = runtimeConfig.cameraRelaxation

  if configuredRelaxation >= RELAXATION_SAFE_MIN then
    return configuredRelaxation
  end

  local t = math.clamp(
    (speed - RELAXATION_BLEND_START_SPEED)
      / (RELAXATION_BLEND_END_SPEED - RELAXATION_BLEND_START_SPEED),
    0,
    1
  )

  t = t * t * (3 - 2 * t)

  return RELAXATION_SAFE_MIN
    + (configuredRelaxation - RELAXATION_SAFE_MIN) * t
end

---@param targetPos vec3
---@param carHeading vec3
local function initializeHeading(targetPos, carHeading)
  headingReference:set(carHeading)
  camAnchor:set(targetPos - carHeading * effectiveRelaxation)

  WORLD_UP:cross(carHeading, tmpCrossA)
  local rightLength = #tmpCrossA
  if rightLength > 0.0001 then
    camAnchorPerp:set(targetPos + tmpCrossA * (-effectiveRelaxation * 0.8 / rightLength))
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

  lockedCameraDirection:set(targetPosLast - camAnchor)
  if #lockedCameraDirection < 0.0001 then return end

  tmpMoveDirection:set(targetPos - targetPosLast)

  if tmpMoveDirection:dot(lockedCameraDirection) < 0 then
    orbitYawRad = wrapAngle(orbitYawRad + math.pi)
    displayedYawRad = wrapAngle(displayedYawRad + math.pi)

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
        targetPos + tmpCrossA * (-effectiveRelaxation * 0.8 / rightLength)
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

  camPointVector:set(targetPos - camAnchor)
  camPointVectorPerp:set(camAnchorPerp - targetPos)

  local pointLength = #camPointVector
  local perpLength = #camPointVectorPerp

  if pointLength < effectiveRelaxation and perpLength > effectiveRelaxation * 0.8 then
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

  camPointVector:set(camAnchor - targetPos)
  local anchorLength = #camPointVector
  if anchorLength > 0.0001 then
    camAnchor:set(targetPos + camPointVector * (effectiveRelaxation / anchorLength))
  else
    camAnchor:set(targetPos - headingReference * effectiveRelaxation)
  end

  WORLD_UP:cross(headingReference, tmpCrossA)
  local rightLength = #tmpCrossA
  if rightLength > 0.0001 then
    camAnchorPerp:set(targetPos + tmpCrossA * (-effectiveRelaxation * 0.8 / rightLength))
  else
    camAnchorPerp:set(targetPos)
  end

  targetPosLast:set(targetPos)
end

---@param keepPitchAndDistance boolean
---@param targetPos vec3
---@param carHeading vec3
local function requestRecenter(keepPitchAndDistance, targetPos, carHeading)
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

  dynamicPitchBlend, dynamicPitchVelocity = temporalSigmoidGetWithRateAccel(
    dynamicPitchBlend,
    dynamicPitchVelocity,
    target,
    dt,
    rate,
    rate,
    rate
  )
end

local function updateAabbReferences()
  local center = car.aabbCenter
  local size = car.aabbSize

  local halfLength = math.abs(size.z) * 0.5

  aabbRearLocal:set(center.x, center.y, center.z - halfLength)
  car.bodyTransform:transformPointTo(aabbRearPoint, aabbRearLocal)

  car.worldToLocal:transformPointTo(carPositionLocal, car.position)
  aabbRearBottomLocal:set(center.x, carPositionLocal.y, center.z - halfLength)
  car.bodyTransform:transformPointTo(rearBottomPoint, aabbRearBottomLocal)
end

---@param targetPos vec3
---@param baseFov number
---@return number
local function calculateDynamicPitchLimit(targetPos, baseFov)
  local defaultPitchRad = runtimeConfig.cameraPitchRad
  local defaultDistance = runtimeConfig.cameraDistance

  defaultCameraOffsetLocal:set(
    0,
    math.sin(defaultPitchRad) * defaultDistance,
    -math.cos(defaultPitchRad) * defaultDistance
  )
  car.bodyTransform:transformVectorTo(defaultCameraOffsetWorld, defaultCameraOffsetLocal)

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
  local baseFov = runtimeConfig.cameraFov

  local dynamicFov = math.clamp(
    baseFov + runtimeConfig.dynamicFovAtSpeed * math.min(1, speed / DYNAMIC_FOV_SPEED),
    10, 160)

  toRearReference:set(rearReferencePoint - targetPos)
  local refToRear = #toRearReference
  local halfToRad = math.pi / 360
  local ratio = math.tan(baseFov * halfToRad) / math.tan(dynamicFov * halfToRad)

  local fovDistanceDifference = (targetDistance - refToRear) * (ratio - 1)
  local dynamicDistance = math.max(0.1, smoothedDistance + fovDistanceDifference)
  return dynamicFov, dynamicDistance
end

---@param speed number
---@return number
local function calculateDynamicHeight(speed)
  local velocity = math.min(speed, 70)
  local smoothedVelocity = math.max(velocity * 0.05 - 0.2, 0.0)
  local lengthValue = math.min((1.4 * smoothedVelocity) / (smoothedVelocity + 4.1), 1)
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

  local outPosition, outNormal
  local hitDistance = render.createRay(
    startPos,
    collisionRayDirection,
    rayLength
  ):physics(outPosition, outNormal)

  if hitDistance == nil or hitDistance < 0 then return rayLength end
  return math.min(hitDistance, rayLength)
end

---@return boolean
local function isObstacleInFrontOfCamera()
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
local function applyCameraCollision(targetPos, desiredCameraPosition, desiredCameraDirection, dt)

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
---@param targetCar ac.StateCar
---@param config BeamNGOrbitCameraConfig
---@param input BeamNGOrbitCameraInput
---@return BeamNGOrbitCameraPose|nil
function M.update(dt, targetCar, config, input)
  if targetCar == nil then return nil end

  applyRuntimeConfig(config)

  if car == nil or currentCarIndex ~= targetCar.index then
    car = targetCar
    currentCarIndex = targetCar.index
    refreshVehicleReferenceNodes()
    resetCameraState()
  else
    car = targetCar
  end

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

  local carSpeed = math.abs(car.speedMs)

  effectiveRelaxation = getEffectiveRelaxation(carSpeed)
  ac.debug('effectiveRelaxation', effectiveRelaxation)

  local carHeading = planarHeading(car.look)
  if carHeading == VEC3_ZERO then
    carHeading = headingInitialized and headingReference or lastValidCarHeading
  else
    lastValidCarHeading = carHeading
  end

  local carPosition = car.transform.position
  local targetReference = resolveTargetReference(carPosition)
  local targetPos = targetReference + WORLD_UP * runtimeConfig.cameraTargetHeightOffset
  updateAabbReferences()
  updateRearReference()
  handleLockedCameraHemisphere(targetPos)
  updateMovementHeading(targetPos, carHeading, dt)

  input = input or {}
  local manualYawStepRad = tonumber(input.yawStepRad) or 0
  local manualPitchStepRad = tonumber(input.pitchStepRad) or 0
  local zoomStep = tonumber(input.zoomStep) or 0
  local zoomDistanceStep = tonumber(input.zoomDistanceStep) or 0
  local recenterPressed = input.recenterPressed == true
  local recenterKeepValuesPressed = input.recenterKeepValuesPressed == true

  updateControlButtons(
    targetPos,
    carHeading,
    recenterPressed,
    recenterKeepValuesPressed
  )

  local manualRotationActive = math.abs(manualYawStepRad) > INPUT_ANGLE_EPSILON_RAD
    or math.abs(manualPitchStepRad) > INPUT_ANGLE_EPSILON_RAD

  orbitYawRad = wrapAngle(orbitYawRad + manualYawStepRad)
  orbitPitchRad = math.clamp(
    orbitPitchRad + manualPitchStepRad,
    CAMERA_PITCH_MIN_RAD,
    CAMERA_PITCH_MAX_RAD
  )

  if math.abs(manualYawStepRad) > INPUT_ANGLE_EPSILON_RAD then
    accumulatedManualYawRad = accumulatedManualYawRad + manualYawStepRad
  end
  if math.abs(accumulatedManualYawRad) > MANUAL_YAW_LOCK_THRESHOLD_RAD then
    lockCamera = true
  end

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

  orbitDistance = clampDistance(
    orbitDistance
      + zoomStep * 0.1 * lastAppliedFov
      + zoomDistanceStep
  )

  local distanceSmoothingT = (dt * 8) / (1 + dt * 8)
  displayedDistance = displayedDistance
    + (orbitDistance - displayedDistance) * distanceSmoothingT

  updateDynamicPitchState(carSpeed, manualRotationActive, dt)

  headingReference:rotate(quat.fromAngleAxis(displayedYawRad, WORLD_UP), normalOrbitForward)
  normalOrbitForward:normalize()

  updateGlanceForward(
    dt,
    input,
    carHeading,
    car.velocity,
    normalOrbitForward,
    orbitForward
  )

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

  baseDirection:set(targetPos - baseCameraPosition)
  if #baseDirection > 0.0001 then
    baseDirection:normalize()
  else
    baseDirection:set(orbitForward)
  end

  local dynamicPitchAngleRad = 0
  if dynamicPitchBlend > 0.0001 and runtimeConfig.dynamicPitchAtSpeedRad > 0 then
    local pitchLimitRad = calculateDynamicPitchLimit(targetPos, runtimeConfig.cameraFov)
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

  applyCameraCollision(targetPos, finalCameraPosition, finalDirection, dt)

  outputPose.position:set(finalCameraPosition)
  outputPose.direction:set(finalDirection)
  outputPose.up:set(WORLD_UP)
  outputPose.fov = dynamicFov
  lastAppliedFov = dynamicFov
  return outputPose
end

function M.reset()
  refreshVehicleReferenceNodes()
  resetCameraState()
end

return M
