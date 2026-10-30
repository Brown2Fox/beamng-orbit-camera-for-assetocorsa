
---@class BeamNGOrbitCameraConfig
---@field cameraDistance number
---@field cameraFov number
---@field cameraTargetHeightOffset number
---@field cameraPitch number
---@field cameraRelaxation number
---@field cameraSlopeFollow number
---@field dynamicFovAtSpeed number
---@field dynamicPitchAtSpeed number
---@field dynamicHeightAtSpeed number
---@field collisionHandlingMethod number
---@field disableCollisionWhenRecentered boolean
---@field keepViewOnCarSwitch boolean
---@field collisionKeepSubjectSize boolean
---@field collisionGroundClearance number
---@field collisionMaxFov number
---@field collisionMinDistance number
---@field collisionMaxHitHeight number

---@class BeamNGOrbitCameraInput
---@field yawStepRad number
---@field pitchStepRad number
---@field zoomStep number
---@field zoomDistanceStep number
---@field zoomFovStep number @Log of the tan(fov/2) scale.
---@field zoomDollyStep number @Log of the distance scale; FOV follows so the subject keeps its size.
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
---@field currentPitch number
---@field currentDistance number
---@field currentFov number
---@field currentHeight number
---@field orbitPitch number
---@field orbitDistance number
---@field orbitFov number

---@class BeamNGOrbitCameraModule
local M = {}

local cspMajor, cspMinor = (ac.getPatchVersion() or ''):match('^(%d+)%.(%d+)')
local supportsCollisions = (tonumber(cspMajor) or 0) > 0 or (tonumber(cspMinor) or 0) >= 3

local car = nil ---@type ac.StateCar?
local currentCarIndex = -1

---@class (exact) BeamNGOrbitCameraRuntimeConfig
---@field cameraDistance number
---@field cameraFov number
---@field cameraTargetHeightOffset number
---@field cameraPitchRad number
---@field cameraRelaxation number
---@field cameraSlopeFollow number
---@field dynamicFovAtSpeed number
---@field dynamicPitchAtSpeedRad number
---@field dynamicHeightAtSpeed number
---@field collisionHandlingMethod number
---@field disableCollisionWhenRecentered boolean
---@field keepViewOnCarSwitch boolean
---@field collisionKeepSubjectSize boolean
---@field collisionGroundClearance number
---@field collisionMaxFov number
---@field collisionMinDistance number
---@field collisionMaxHitHeight number

---@type BeamNGOrbitCameraRuntimeConfig
local runtimeConfig = {
  cameraDistance = 5.0,
  cameraFov = 65.0,
  cameraTargetHeightOffset = 0.0,
  cameraPitchRad = math.rad(17.0),
  cameraRelaxation = 6.0,
  cameraSlopeFollow = 1.0,
  dynamicFovAtSpeed = 40.0,
  dynamicPitchAtSpeedRad = math.rad(7.0),
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

local lastCameraPitchDeg = 17.0
local lastDynamicPitchAtSpeedDeg = 7.0

---@type BeamNGOrbitCameraPose
local outputPose = {
  position = vec3(),
  direction = vec3(0, 0, 1),
  up = vec3(0, 1, 0),
  fov = 65.0,
  currentPitch = 17.0,
  currentDistance = 5.0,
  currentFov = 65.0,
  currentHeight = 0.0,
  orbitPitch = 17.0,
  orbitDistance = 5.0,
  orbitFov = 65.0,
}

local VEC3_ZERO = vec3(0, 0, 0)
local WORLD_UP = vec3(0, 1, 0)
local INPUT_ANGLE_EPSILON_RAD = 0.0001
local EPSILON = 1e-30

local CAMERA_DISTANCE_MIN = 3.0
local CAMERA_DISTANCE_MAX = 75.0

local CAMERA_PITCH_MIN_RAD = math.rad(-85)
local CAMERA_PITCH_MAX_RAD = math.rad(85)

-- Subject size on screen goes as 1 / (distance * tan(fov / 2)), so FOV is kept as tan(fov / 2).
local MANUAL_TAN_HALF_FOV_MIN = math.tan(math.rad(10) / 2)
local MANUAL_TAN_HALF_FOV_MAX = math.tan(math.rad(120) / 2)
-- Collision tuning (one table: the file is near Lua's 200-local limit).
local COLLISION = {}

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

COLLISION.ASSUMED_NEAR_CLIP_DISTANCE = 0.0
COLLISION.NEAR_CLIP_HALF_WIDTH = 0.2
COLLISION.NEAR_CLIP_HALF_HEIGHT = 0.1
-- Pull-in by walls: a critically damped spring towards the pulled-in distance, the same in both
-- directions, with its speed (m/s) and acceleration (m/s^2) capped so it eases into a wall.
-- A brief, shallow clip at the start of a wall is the price.
COLLISION.PULL_FREQUENCY = 8.0
COLLISION.PULL_MAX_SPEED = 10.0
COLLISION.PULL_MAX_ACCELERATION = 40.0
-- Far cameras get proportionally higher caps (this fraction of the distance per second), or a big
-- pull-in at 50 m would take seconds to recover.
COLLISION.PULL_MAX_SPEED_PER_METRE = 0.5
-- Each wall hit is checked against what was expected: the look-ahead cast the frame before, or
-- the pull-in already in place. Within WALL_MATCH (m, or that fraction of the distance) of it:
-- inside a wall, fixed at once when the gap is small (WALL_SNAP, the same), otherwise by a spring
-- this many times quicker. Much nearer than expected: a surprise, probably a post or a tree going
-- past, waited out for up to WALL_WAIT seconds before it counts.
COLLISION.PULL_FAST_FACTOR = 8.0
COLLISION.WALL_WAIT = 0.15
COLLISION.WALL_MATCH_MIN = 2.0
COLLISION.WALL_MATCH_FRACTION = 0.1
COLLISION.WALL_SNAP_MIN = 0.5
COLLISION.WALL_SNAP_FRACTION = 0.03
-- Hard cap on collision rays per frame. The lift spends what is left after the wall pass's share
-- and carries an unfinished search over to the next frame.
COLLISION.RAY_BUDGET = 15
COLLISION.WALL_RAY_RESERVE = 6
-- A hit within this distance of the previous frame's hit reuses its surface reading.
COLLISION.SURFACE_CACHE_DISTANCE = 1.0
-- Car and requested camera position both within this distance of last frame: reuse its answer.
COLLISION.STATIC_DISTANCE = 0.02
COLLISION.HANDLING_DISABLED = 0
COLLISION.HANDLING_PHYSICS_SHAPES = 1
COLLISION.HANDLING_VISUALS = 2
COLLISION.HANDLING_SMART_PHYSICS_SHAPES = 3
COLLISION.HANDLING_SMART_VISUALS = 4

-- Smart handling: ground (or a tunnel ceiling) between the car and the camera makes the camera
-- orbit over (or under) it instead of pulling in. Surfaces steeper than 30 degrees are walls.
COLLISION.GROUND_MIN_NORMAL_Y = math.cos(math.rad(30))
COLLISION.NORMAL_PROBE_BACK = 0.3
COLLISION.NORMAL_PROBE_SPREAD = 0.1
-- Visuals modes first try the physics shape at the hit: a ray aimed at it from this far (m) off the
-- line, on the open side, so even a line skimming the ground gets a solid hit. Its reading counts
-- only if it lands within the match distance (m) of the visual hit (trees have no physics shape).
COLLISION.NORMAL_PHYSICS_LIFT = 0.2
COLLISION.NORMAL_PHYSICS_MATCH = 0.25
-- The target rise starts from last frame's, lowered a little (that is how the shot returns to the
-- user's framing), and jumps straight over each contact point until the view is clear.
COLLISION.LIFT_MAX_JUMPS = 8
-- A rise or pull-in that is no longer needed is held this long (s) before it lets go, so grazing
-- posts, fences and crests don't flick the camera in and out.
COLLISION.RELEASE_HOLD = 0.2
-- Look-ahead: where the car and the camera will be this long (s) from now, each assumed to stay on
-- the arc it is on (same speed, rate of turn and climb). One ray along that future line of sight,
-- from the rays a frame has left over; a hit raises the lift or pull-in early, never lowers it.
COLLISION.LOOKAHEAD_TIME = 0.25
-- Under a ceiling the look-ahead reaches further: a bridge ends, and the camera should head back
-- up before the car is out from under it.
COLLISION.CEILING_LOOKAHEAD_TIME = 0.6
-- Look-ahead hits this close (m) to the predicted car are the prediction running into a kerb or
-- a wall on a turn, not something on the way to the camera: ignored.
COLLISION.LOOKAHEAD_MIN_HIT = 3.0
-- A predicted wall counts only if the predicted car is within this far (m) of the real one: further
-- out the arc guesses wrong (the road bends, the verge is not in the way) and the real rays are in
-- time anyway. Ground and ceilings are not limited: lifting early is harmless.
COLLISION.LOOKAHEAD_WALL_MAX_TRAVEL = 8.0
-- A ceiling counts only when the car is under cover too: a ray straight up from it must hit
-- something within this far (m) above the ceiling's height.
COLLISION.COVER_MARGIN = 5.0
-- How quickly (1/s) the tracked speed and rate of turn follow the measured ones.
COLLISION.ARC_SMOOTHING = 10.0
COLLISION.LIFT_MIN_DESCENT_SPEED_RAD = math.rad(3)
-- The target rise eases back down at this rate (1/s); the camera follows the target on a
-- critically damped spring at one fixed frequency (rad/s), so it never overshoots.
COLLISION.LIFT_TARGET_RELEASE_RATE = 1.5
COLLISION.LIFT_FOLLOW_FREQUENCY = 8.0
-- A camera caught below the clearance line climbs back to it at least this fast (1/s).
COLLISION.LIFT_CATCH_FREQUENCY = 25.0
-- A camera this close (rad) under the clearance line goes straight to it, like a wall pull-in.
COLLISION.LIFT_SNAP_RAD = math.rad(2)

-- Metres per frame the car may move beyond what its speed accounts for before it counts as scrubbing.
local REPLAY_SCRUB_TOLERANCE = 0.05

local MANUAL_YAW_LOCK_THRESHOLD_RAD = math.rad(10)
local GLANCE_MOVEMENT_HEADING_START_SPEED = 2.0
local GLANCE_MOVEMENT_HEADING_FULL_SPEED = 8.0
local GLANCE_TRANSITION_DURATION = 0.15

local orbitYawRad = 0.0
local orbitPitchRad = 0.0
local displayedYawRad = 0.0
local displayedPitchRad = 0.0
-- Car speed for the speed-driven FOV, distance, height and tilt. A replay reports it only every 2-3
-- frames, and those steps showed as the view stuttering.
local smoothedSpeed = nil
local SPEED_SMOOTHING = 8.0
local orbitDistance = 0.0
local displayedDistance = 0.0
local orbitTanHalfFov = 0.0
local displayedTanHalfFov = 0.0
local orbitInitialized = false
local cameraOrbitActive = false

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
local belowPitchThresholdTimer = nil ---@type number?
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
local defaultCameraOffsetLocal = vec3()
local defaultCameraOffsetWorld = vec3()
local toRearReference = vec3()
local toTarget = vec3()
local toRearBottom = vec3()
local carPositionLocal = vec3()

local collisionUseRaycast = true
local collisionWallProbe = vec3()
local collisionPullIn = 0.0
local collisionLastDesiredDistance = 0.0
-- Last frame's collision answer, reused while nothing moves. `liftFinal` is false while the lift
-- is still easing down (or its search was cut short): those frames have to keep solving.
local collisionReuse = {
  liftFinal = false,
  hasPose = false,
  target = vec3(),
  desired = vec3(),
  closestHit = 0.0,
  hitRegistered = false,
}
local collisionPullVelocity = 0.0
-- Release holds: time left before a falling lift target / pull-in is accepted, and the pull-in held.
-- `final` is last frame's camera elevation (rad), nil after a reset; `goal` the elevation the lift
-- target asked for, so pitching under a lift doesn't drag the remembered target down with it.
local collisionHold = { liftTimer = 0.0, pullTimer = 0.0, pullIn = 0.0, final = nil, goal = 0.0, goalClear = 0.0,
  wallTime = 0.0 }
local collisionRaysLeft = COLLISION.RAY_BUDGET
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
local collisionProbeDirection = vec3()
local collisionProbeStart = vec3()
local collisionLiftOffset = vec3()
local collisionLiftHorizontal = vec3()
local collisionLiftSide = vec3()
local collisionLiftProbe = vec3()
local collisionLiftDirection = vec3()
local collisionLiftHit = vec3()
local collisionHitNormal = vec3()
-- The car's up: on banking the track tilts with it, so ground is judged against this too.
local collisionCarUp = vec3(0, 1, 0)
local collisionNormalSideA = vec3()
local collisionNormalSideB = vec3()
local collisionNormalHitA = vec3()
local collisionNormalHitB = vec3()
local collisionNormalAim = vec3()
local collisionLiftAngleRad = 0.0
local collisionLiftVelocity = 0.0
local collisionLiftTarget = 0.0
local collisionLiftAtLimit = false
local collisionLiftComplete = true

---@return {valid: boolean, position: vec3, surface: integer|nil}
local function newSurfaceCache()
  return { valid = false, position = vec3(), surface = nil }
end
local liftSurfaceCache = newSurfaceCache()
local cornerSurfaceCaches = { newSurfaceCache(), newSurfaceCache(), newSurfaceCache(), newSurfaceCache() }
local collisionWallHitPoint = vec3()

---@alias CollisionArc {valid: boolean, position: vec3, velocity: vec3, turnRate: number}
---@return CollisionArc
local function newArc()
  return { valid = false, position = vec3(), velocity = vec3(), turnRate = 0.0 }
end
-- Arcs of the car and the camera, the predicted line of sight, and what it asks for (used the
-- frame after it is cast).
local lookahead = {
  targetArc = newArc(),
  cameraArc = newArc(),
  step = vec3(),
  target = vec3(),
  camera = vec3(),
  direction = vec3(),
  hit = vec3(),
  surfaceCache = newSurfaceCache(),
  -- Elevation (rad) the predicted line of sight must stay above (side 1) or below (side -1).
  lift = 0.0,
  liftSide = 0,
  -- The predicted line of sight was cast and hit nothing.
  clear = false,
  pullIn = 0.0,
}

local replayReversed = false
local lastReplayFrame = nil
-- Camera heading relative to the car, kept up to date on every followed frame. A hold uses the
-- value from before it started: on a scrub the first held frame already has the car somewhere
-- else, so measuring the angle then would compare the old camera with the new car.
local replayHoldYawRad = 0.0

local function resetCollisionState()
  collisionUseRaycast = true
  collisionPullIn = 0.0
  collisionPullVelocity = 0.0
  collisionLastDesiredDistance = 0.0
  collisionReuse.liftFinal = false
  collisionReuse.hasPose = false
  collisionLiftComplete = true
  liftSurfaceCache.valid = false
  for i = 1, 4 do cornerSurfaceCaches[i].valid = false end
  collisionHasLastNearClipCenter = false
  collisionLiftAngleRad = 0.0
  collisionLiftVelocity = 0.0
  collisionLiftTarget = 0.0
  collisionLiftAtLimit = false
  collisionHold.liftTimer = 0.0
  collisionHold.pullTimer = 0.0
  collisionHold.pullIn = 0.0
  collisionHold.final = nil
  collisionHold.goalClear = 0.0
  collisionHold.wallTime = 0.0
  lookahead.targetArc.valid = false
  lookahead.cameraArc.valid = false
  lookahead.surfaceCache.valid = false
  lookahead.liftSide = 0
  lookahead.clear = false
  lookahead.pullIn = 0.0
end

---@param fovDeg number
---@return number
local function fovToTanHalf(fovDeg)
  return math.tan(math.rad(fovDeg) * 0.5)
end

---@param tanHalfFov number
---@return number
local function tanHalfToFov(tanHalfFov)
  return math.deg(math.atan(tanHalfFov) * 2)
end

---@param keepView boolean? keep the orbit view (yaw, pitch, distance, lens and manual-orbit state)
local function resetCameraState(keepView)
  if not keepView then
    orbitInitialized = false
    cameraOrbitActive = false

    lockCamera = false
    accumulatedManualYawRad = 0.0
    lastAppliedFov = runtimeConfig.cameraFov
  end

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

  replayReversed = false
  lastReplayFrame = nil
  replayHoldYawRad = 0.0
  smoothedSpeed = nil

  resetCollisionState()
end

local function updateRearReference()
  rearReferencePoint:set(aabbRearPoint)
end

---@param value number
---@return number
local function clampDistance(value)
  return math.clamp(value, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)
end

---@param config BeamNGOrbitCameraConfig
local function applyRuntimeConfig(config)
  if config == nil then return end

  local cameraDistance = config.cameraDistance or runtimeConfig.cameraDistance
  local cameraFov = config.cameraFov or runtimeConfig.cameraFov
  local cameraTargetHeightOffset = config.cameraTargetHeightOffset or runtimeConfig.cameraTargetHeightOffset
  local cameraPitchDeg = config.cameraPitch or lastCameraPitchDeg
  local cameraRelaxation = config.cameraRelaxation or runtimeConfig.cameraRelaxation
  local dynamicFovAtSpeed = config.dynamicFovAtSpeed or runtimeConfig.dynamicFovAtSpeed
  local dynamicPitchAtSpeedDeg = config.dynamicPitchAtSpeed or lastDynamicPitchAtSpeedDeg
  local dynamicHeightAtSpeed = config.dynamicHeightAtSpeed or runtimeConfig.dynamicHeightAtSpeed
  local collisionHandlingMethod = math.clamp(
    math.floor(
      tonumber(config.collisionHandlingMethod)
        or runtimeConfig.collisionHandlingMethod
    ),
    COLLISION.HANDLING_DISABLED,
    COLLISION.HANDLING_SMART_VISUALS
  )
  local disableCollisionWhenRecentered =
    config.disableCollisionWhenRecentered == true
  local collisionKeepSubjectSize = config.collisionKeepSubjectSize ~= false
  runtimeConfig.keepViewOnCarSwitch = config.keepViewOnCarSwitch == true

  local distanceChanged = math.abs(cameraDistance - runtimeConfig.cameraDistance) > 0.000001
  local fovChanged = math.abs(cameraFov - runtimeConfig.cameraFov) > 0.000001
  local pitchChanged = math.abs(cameraPitchDeg - lastCameraPitchDeg) > 0.000001
  local collisionConfigChanged =
    collisionHandlingMethod ~= runtimeConfig.collisionHandlingMethod
    or disableCollisionWhenRecentered
      ~= runtimeConfig.disableCollisionWhenRecentered

  runtimeConfig.cameraDistance = cameraDistance
  runtimeConfig.cameraFov = cameraFov
  runtimeConfig.cameraTargetHeightOffset = cameraTargetHeightOffset
  runtimeConfig.cameraRelaxation = cameraRelaxation
  runtimeConfig.cameraSlopeFollow = math.clamp(
    tonumber(config.cameraSlopeFollow) or runtimeConfig.cameraSlopeFollow, 0, 1
  )
  runtimeConfig.dynamicFovAtSpeed = dynamicFovAtSpeed
  runtimeConfig.dynamicHeightAtSpeed = dynamicHeightAtSpeed
  runtimeConfig.collisionHandlingMethod = collisionHandlingMethod
  runtimeConfig.disableCollisionWhenRecentered =
    disableCollisionWhenRecentered
  runtimeConfig.collisionKeepSubjectSize = collisionKeepSubjectSize
  runtimeConfig.collisionMaxFov = math.clamp(
    tonumber(config.collisionMaxFov) or runtimeConfig.collisionMaxFov,
    30.0,
    170.0
  )
  runtimeConfig.collisionMinDistance = math.clamp(
    tonumber(config.collisionMinDistance) or runtimeConfig.collisionMinDistance,
    0.1,
    CAMERA_DISTANCE_MAX
  )
  runtimeConfig.collisionMaxHitHeight = math.clamp(
    tonumber(config.collisionMaxHitHeight) or runtimeConfig.collisionMaxHitHeight,
    0.5,
    50.0
  )
  runtimeConfig.collisionGroundClearance = math.clamp(
    tonumber(config.collisionGroundClearance) or runtimeConfig.collisionGroundClearance,
    0.05,
    5.0
  )

  if collisionConfigChanged then resetCollisionState() end

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
    if fovChanged then orbitTanHalfFov = fovToTanHalf(cameraFov) end
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
  local nextGlanceMode = glanceBack and (glanceLeft ~= glanceRight and (glanceLeft and 4 or 5) or 3)
    or glanceLeft ~= glanceRight and (glanceLeft and 1 or 2)
    or 0 ---@type integer

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
      local glanceAngle = (nextGlanceMode == 4 or nextGlanceMode == 5) and math.pi * 0.75 or math.pi * 0.5
      if nextGlanceMode == 2 or nextGlanceMode == 5 then glanceAngle = -glanceAngle end
      glanceBaseHeading:rotate(
        quat.fromAngleAxis(glanceAngle, WORLD_UP),
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

  local accelerationDelta = 0.0
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

  -- The rope's vertical angle comes from where the car was a rope length ago, so a long rope over
  -- crests and dips tilts the camera a lot. Scale it down; the anchor itself still follows fully.
  local slopeFollow = runtimeConfig.cameraSlopeFollow
  if slopeFollow < 1 then
    headingReference.y = headingReference.y * slopeFollow
    if #headingReference > 0.0001 then
      headingReference:normalize()
    else
      headingReference:set(carHeading)
    end
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

-- The rope heading above trails the direction of travel, so in a replay anything other than
-- plain forward playback drags the camera around: rewinding pulls it to the front, scrubbing
-- yanks it along every jump. In those cases hold the camera's angle to the car instead.
-- Scrubbing shows up as the car moving by a different amount than its own speed says (a paused,
-- scrubbed replay reports zero speed while the car jumps). The car moving tail-first catches a
-- rewind on its first frame, before the frame counter does.
---@param sim ac.StateSim
---@param targetPos vec3
---@param carHeading vec3
---@param carSpeed number
---@param dt number
---@return boolean
local function shouldHoldReplayCamera(sim, targetPos, carHeading, carSpeed, dt)
  tmpMoveDirection:set(targetPos - targetPosLast)
  local moved = #tmpMoveDirection

  if not sim.isReplayActive then
    replayReversed = false
    lastReplayFrame = nil
    return false
  end

  local frame = sim.replayCurrentFrame
  if (sim.replayPlaybackRate or 0) < 0 then
    replayReversed = true
  elseif lastReplayFrame ~= nil and frame ~= lastReplayFrame then
    replayReversed = frame < lastReplayFrame
  end
  lastReplayFrame = frame

  local movingTailFirst = headingInitialized
    and tmpMoveDirection:dot(carHeading) < -0.001

  local playbackRate = sim.replayPlaybackRate or 1
  local expectedMove = carSpeed * math.max(dt, 0) * (playbackRate > 0 and playbackRate or 1)
  local scrubbing = headingInitialized
    and math.abs(moved - expectedMove) > REPLAY_SCRUB_TOLERANCE + expectedMove * 0.5

  return replayReversed or movingTailFirst or scrubbing
end

---@param targetPos vec3
---@param carHeading vec3
local function holdCameraToCar(targetPos, carHeading)
  if not headingInitialized then initializeHeading(targetPos, carHeading) end

  carHeading:rotate(quat.fromAngleAxis(replayHoldYawRad, WORLD_UP), headingReference)
  headingReference:normalize()

  camAnchor:set(targetPos - headingReference * effectiveRelaxation)
  WORLD_UP:cross(headingReference, tmpCrossA)
  local rightLength = #tmpCrossA
  if rightLength > 0.0001 then
    camAnchorPerp:set(targetPos + tmpCrossA * (-effectiveRelaxation * 0.8 / rightLength))
  else
    camAnchorPerp:set(targetPos)
  end

  targetPosLast:set(targetPos)
end

---@param step number
local function applyFovZoom(step)
  orbitTanHalfFov = math.clamp(
    orbitTanHalfFov * math.exp(step),
    MANUAL_TAN_HALF_FOV_MIN,
    MANUAL_TAN_HALF_FOV_MAX
  )
end

-- Moves the camera and changes FOV together so distance * tan(fov / 2) stays constant:
-- the subject keeps its size and only perspective compression changes.
---@param step number
local function applyDollyZoom(step)
  local subjectSize = orbitDistance * orbitTanHalfFov
  local minDistance = math.max(CAMERA_DISTANCE_MIN, subjectSize / MANUAL_TAN_HALF_FOV_MAX)
  local maxDistance = math.min(CAMERA_DISTANCE_MAX, subjectSize / MANUAL_TAN_HALF_FOV_MIN)
  if minDistance > maxDistance then return end

  orbitDistance = math.clamp(orbitDistance * math.exp(step), minDistance, maxDistance)
  orbitTanHalfFov = subjectSize / orbitDistance
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
    displayedPitchRad = math.clamp(
      displayedPitchRad + collisionLiftAngleRad,
      CAMERA_PITCH_MIN_RAD,
      CAMERA_PITCH_MAX_RAD
    )
    orbitPitchRad = displayedPitchRad
  else
    orbitPitchRad = runtimeConfig.cameraPitchRad
    orbitDistance = runtimeConfig.cameraDistance
    orbitTanHalfFov = fovToTanHalf(runtimeConfig.cameraFov)
  end

  lockCamera = false
  cameraOrbitActive = false
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
  if car == nil then return end

  local center = car.aabbCenter
  local size = car.aabbSize

  local halfLength = math.abs(size.z) * 0.5

  aabbRearLocal:set(center.x, center.y, center.z - halfLength)
  car.bodyTransform:transformPointTo(aabbRearPoint, aabbRearLocal)

  car.worldToLocal:transformPointTo(carPositionLocal, car.position)
  aabbRearBottomLocal:set(center.x, carPositionLocal.y, center.z - halfLength)
  car.bodyTransform:transformPointTo(rearBottomPoint, aabbRearBottomLocal)
end

-- How far the view may tilt down before the car's rear leaves the frame, from the camera's current
-- pitch and distance (not the defaults: zoomed, the car fills a different part of the frame).
---@param targetPos vec3
---@param baseFov number
---@param pitchRad number
---@param distance number
---@return number
local function calculateDynamicPitchLimit(targetPos, baseFov, pitchRad, distance)
  if car == nil then return 0 end

  defaultCameraOffsetLocal:set(
    0,
    math.sin(pitchRad) * distance,
    -math.cos(pitchRad) * distance
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
  local baseFov = tanHalfToFov(displayedTanHalfFov)

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
  if rayLength <= 0.0001 or collisionRaysLeft <= 0 then return rayLength end
  collisionRaysLeft = collisionRaysLeft - 1

  collisionRayDirection:set(direction)
  local directionLength = #collisionRayDirection
  if directionLength <= 0.0001 then return rayLength end
  collisionRayDirection:set(collisionRayDirection / directionLength)

  local method = runtimeConfig.collisionHandlingMethod
  local hitDistance ---@type number
  if method == COLLISION.HANDLING_VISUALS
      or method == COLLISION.HANDLING_SMART_VISUALS then
    hitDistance = render.createRay(
      startPos,
      collisionRayDirection,
      rayLength
    ):track()
  elseif method == COLLISION.HANDLING_PHYSICS_SHAPES
      or method == COLLISION.HANDLING_SMART_PHYSICS_SHAPES then
    hitDistance = render.createRay(
      startPos,
      collisionRayDirection,
      rayLength
    ):physics()
  else
    return rayLength
  end

  if hitDistance == nil or hitDistance < 0 then return rayLength end
  return math.min(hitDistance, rayLength)
end

---@return boolean
local function isPhysicsShapeCollision()
  return runtimeConfig.collisionHandlingMethod == COLLISION.HANDLING_PHYSICS_SHAPES
    or runtimeConfig.collisionHandlingMethod == COLLISION.HANDLING_SMART_PHYSICS_SHAPES
end

---@return boolean
local function isSmartCollision()
  return runtimeConfig.collisionHandlingMethod == COLLISION.HANDLING_SMART_PHYSICS_SHAPES
    or runtimeConfig.collisionHandlingMethod == COLLISION.HANDLING_SMART_VISUALS
end

-- Casts from collisionProbeStart towards hitPos + offset; writes the contact to out.
---@param hitPos vec3
---@param offset vec3
---@param out vec3
---@return boolean
local function probeNearHit(hitPos, offset, out)
  collisionNormalAim:set(hitPos + offset * COLLISION.NORMAL_PROBE_SPREAD - collisionProbeStart)
  local aimLength = #collisionNormalAim
  if aimLength < 0.0001 then return false end
  collisionNormalAim:set(collisionNormalAim / aimLength)
  local probeLength = aimLength * 3
  local distance = castCollisionRay(collisionProbeStart, collisionNormalAim, probeLength)
  if distance >= probeLength then return false end
  out:set(collisionProbeStart + collisionNormalAim * distance)
  return true
end

-- Normal of the surface a ray hit, facing back along the ray; zero when it can't be found.
-- Physics shapes report it. For visuals the physics shape at the hit is tried first; failing that
-- the normal comes from two more rays fired from just short of the hit at nearby points.
---@param hitPos vec3
---@param rayDirection vec3 @Normalized.
---@param outNormal vec3
local function findHitNormal(hitPos, rayDirection, outNormal)
  outNormal:set(0, 0, 0)
  collisionProbeStart:set(hitPos - rayDirection * COLLISION.NORMAL_PROBE_BACK)

  if runtimeConfig.collisionHandlingMethod == COLLISION.HANDLING_SMART_PHYSICS_SHAPES then
    if collisionRaysLeft <= 0 then return end
    render.createRay(collisionProbeStart, rayDirection, COLLISION.NORMAL_PROBE_BACK * 2)
      :physics(nil, outNormal)
    collisionRaysLeft = collisionRaysLeft - 1
  else
    if collisionRaysLeft <= 0 then return end
    local liftSide = rayDirection.y <= 0 and 1 or -1
    collisionProbeStart:set(collisionProbeStart + WORLD_UP * (liftSide * COLLISION.NORMAL_PHYSICS_LIFT))
    collisionNormalAim:set(hitPos - collisionProbeStart)
    local aimLength = #collisionNormalAim
    collisionNormalAim:set(collisionNormalAim / aimLength)
    local physicsDistance = render.createRay(collisionProbeStart, collisionNormalAim, aimLength * 2)
      :physics(nil, outNormal)
    collisionRaysLeft = collisionRaysLeft - 1
    if physicsDistance == nil or physicsDistance < 0
        or math.abs(physicsDistance - aimLength) > COLLISION.NORMAL_PHYSICS_MATCH then
      outNormal:set(0, 0, 0)
    end
  end

  if #outNormal < 0.0001
      and runtimeConfig.collisionHandlingMethod ~= COLLISION.HANDLING_SMART_PHYSICS_SHAPES then
    collisionProbeStart:set(hitPos - rayDirection * COLLISION.NORMAL_PROBE_BACK)
    rayDirection:cross(WORLD_UP, collisionNormalSideA)
    if #collisionNormalSideA < 0.0001 then collisionNormalSideA:set(1, 0, 0) end
    collisionNormalSideA:normalize()
    collisionNormalSideA:cross(rayDirection, collisionNormalSideB)
    collisionNormalSideB:normalize()

    local hasA = probeNearHit(hitPos, collisionNormalSideA, collisionNormalHitA)
      or probeNearHit(hitPos, collisionNormalSideA * -1, collisionNormalHitA)
    local hasB = probeNearHit(hitPos, collisionNormalSideB, collisionNormalHitB)
      or probeNearHit(hitPos, collisionNormalSideB * -1, collisionNormalHitB)
    if not hasA or not hasB then return end

    collisionNormalSideA:set(collisionNormalHitA - hitPos)
    collisionNormalSideB:set(collisionNormalHitB - hitPos)
    collisionNormalSideA:cross(collisionNormalSideB, outNormal)
  end

  local normalLength = #outNormal
  if normalLength < 0.0001 then
    outNormal:set(0, 0, 0)
    return
  end
  outNormal:set(outNormal / normalLength)
  if outNormal:dot(rayDirection) > 0 then outNormal:set(outNormal * -1) end
end

-- 1 for ground, -1 for a ceiling, 0 for a wall (anything steeper than 30 degrees, both from
-- level and from the car's own tilt, so banking is ground), nil when the surface angle can't be
-- read.
---@param hitPos vec3
---@param rayDirection vec3 @Normalized.
---@return integer|nil
local function classifySurface(hitPos, rayDirection)
  findHitNormal(hitPos, rayDirection, collisionHitNormal)
  if #collisionHitNormal < 0.5 then return nil end
  local alongCarUp = collisionHitNormal:dot(collisionCarUp)
  local minNormal = COLLISION.GROUND_MIN_NORMAL_Y
  if collisionHitNormal.y >= minNormal or alongCarUp >= minNormal then return 1 end
  if collisionHitNormal.y <= -minNormal or alongCarUp <= -minNormal then return -1 end
  return 0
end

---@return integer
local function classifyRayCost()
  return runtimeConfig.collisionHandlingMethod == COLLISION.HANDLING_SMART_PHYSICS_SHAPES and 1 or 5
end

-- classifySurface, reusing the previous reading when the hit is close to the previous hit (or
-- when the frame's ray budget can't pay for a new one).
---@param cache {valid: boolean, position: vec3, surface: integer|nil}
---@param hitPos vec3
---@param rayDirection vec3 @Normalized.
---@return integer|nil
local function classifySurfaceCached(cache, hitPos, rayDirection)
  if cache.valid and (hitPos:distanceSquared(cache.position)
      < COLLISION.SURFACE_CACHE_DISTANCE * COLLISION.SURFACE_CACHE_DISTANCE
      or collisionRaysLeft < classifyRayCost()) then
    return cache.surface
  end
  if collisionRaysLeft < classifyRayCost() then return nil end
  local surface = classifySurface(hitPos, rayDirection)
  cache.valid = true
  cache.position:set(hitPos)
  cache.surface = surface
  return surface
end

-- Camera offset from the target after orbiting it vertically by angleRad, written to collisionLiftProbe.
---@param angleRad number
---@param elevationRad number
---@param offsetLength number
local function setLiftedOffset(angleRad, elevationRad, offsetLength)
  local liftedElevation = elevationRad + angleRad
  collisionLiftProbe:set(
    collisionLiftHorizontal * (math.cos(liftedElevation) * offsetLength)
      + WORLD_UP * (math.sin(liftedElevation) * offsetLength)
  )
end

-- Whether the camera's own, unlifted spot is clear: the line from the car to it and, unless
-- the lift is under a ceiling, the clearance below it. Two rays at most.
---@param targetPos vec3
---@param elevationRad number
---@param offsetLength number
---@param liftSign number
---@return boolean|nil @nil when the frame has no rays left for it.
local function isLiftGoalClear(targetPos, elevationRad, offsetLength, liftSign)
  local clearance = runtimeConfig.collisionGroundClearance
  local probeLength = offsetLength + clearance
  if collisionRaysLeft - COLLISION.WALL_RAY_RESERVE < 2 then return nil end
  setLiftedOffset(0, elevationRad, offsetLength)
  collisionLiftDirection:set(collisionLiftProbe / offsetLength)
  if castCollisionRay(targetPos, collisionLiftDirection, probeLength) < probeLength then
    return false
  end
  if liftSign < 0 then return true end
  collisionProbeStart:set(targetPos + collisionLiftProbe)
  collisionProbeDirection:set(0, -1, 0)
  return castCollisionRay(collisionProbeStart, collisionProbeDirection, clearance) >= clearance
end

-- Whether the car is under a bridge or in a tunnel, so a ceiling hit really is one and not the
-- underside of a tree or a sign between the car and a high camera. One ray.
---@param targetPos vec3
---@param ceilingHeight number
---@return boolean
local function isCarUnderCover(targetPos, ceilingHeight)
  local length = math.max(ceilingHeight - targetPos.y, 0) + COLLISION.COVER_MARGIN
  collisionProbeDirection:set(0, 1, 0)
  return castCollisionRay(targetPos, collisionProbeDirection, length) < length
end

-- Vertical orbit (positive is up) at the same distance that keeps the line of sight the ground
-- clearance above the ground (below a ceiling) and the camera that far off the ground under it.
-- Starts from last frame's rise, lowered by a small step: if that is clear, the unlifted spot is
-- checked too, and when it is free the rise lets go at once (the spring brings the camera home);
-- otherwise the lowered step is the answer. When the start is blocked, each pass reads the contact
-- point and jumps straight to the angle that clears it. Usually two to four rays a frame. Walls
-- end the search: pulling in handles them.
---@param targetPos vec3
---@param elevationRad number
---@param offsetLength number
---@param previousLift number
---@param dt number
---@return number lift, boolean atLimit, boolean complete @`atLimit` when the rise is maxed out and
---still blocked; `complete` false when the ray budget or jump count cut the search short.
local function findLiftAngle(targetPos, elevationRad, offsetLength, previousLift, dt)
  local clearance = runtimeConfig.collisionGroundClearance
  -- The rise may go as far as the camera's own pitch range: however far the user pushes the camera
  -- into the ground, it ends up just above it at full distance.
  local minElevation = CAMERA_PITCH_MIN_RAD
  local maxElevation = CAMERA_PITCH_MAX_RAD
  local probeLength = offsetLength + clearance

  local liftSign = math.sign(previousLift)
  local lift = previousLift
  local easingDown = liftSign ~= 0 and collisionLiftComplete
  -- An unfinished search resumes exactly where it stopped; a finished one eases back down.
  if easingDown then
    local descent = math.max(
      math.abs(previousLift) * COLLISION.LIFT_TARGET_RELEASE_RATE,
      COLLISION.LIFT_MIN_DESCENT_SPEED_RAD
    ) * math.max(dt, 0)
    lift = previousLift - liftSign * descent
    if lift * liftSign <= 0 then lift = 0 end
  end
  local liftedElevation = math.clamp(elevationRad + lift, minElevation, maxElevation)

  local searchCut = true
  collisionReuse.liftFinal = true
  for jump = 1, COLLISION.LIFT_MAX_JUMPS do
    if collisionRaysLeft - COLLISION.WALL_RAY_RESERVE < 1 + classifyRayCost() then
      collisionReuse.liftFinal = false
      return liftedElevation - elevationRad, false, false
    end
    setLiftedOffset(liftedElevation - elevationRad, elevationRad, offsetLength)
    collisionLiftDirection:set(collisionLiftProbe / offsetLength)

    local surface
    local clearingElevation
    local hitDistance = castCollisionRay(targetPos, collisionLiftDirection, probeLength)
    if hitDistance < probeLength then
      collisionLiftHit:set(targetPos + collisionLiftDirection * hitDistance)
      -- Only the first contact of the frame is read; later ones are the same ground further
      -- along (and often too grazing to read anyway).
      if jump == 1 then
        surface = classifySurfaceCached(liftSurfaceCache, collisionLiftHit, collisionLiftDirection)
        if surface == -1 and not isCarUnderCover(targetPos, collisionLiftHit.y) then
          -- Not a real ceiling: no ducking for it, and an existing duck lets go.
          searchCut = false
          if liftSign < 0 then return 0, false, true end
          break
        end
      end
      if surface == nil then surface = liftSign end
      if surface == 0 then
        searchCut = false
        -- A wall across the lowered start says nothing about the ground (an embankment beside
        -- the road reads as a wall): keep last frame's rise rather than letting it sag.
        if jump == 1 and easingDown then return previousLift, collisionLiftAtLimit, true end
        break
      end
      local hitHorizontal = math.max(0.1, math.sqrt(
        (collisionLiftHit.x - targetPos.x) ^ 2 + (collisionLiftHit.z - targetPos.z) ^ 2
      ))
      ---@diagnostic disable-next-line: redundant-parameter
      clearingElevation = math.atan2(
        collisionLiftHit.y + surface * clearance - targetPos.y,
        hitHorizontal
      )
    elseif liftSign >= 0 then
      collisionProbeStart:set(targetPos + collisionLiftProbe)
      collisionProbeDirection:set(0, -1, 0)
      local below = castCollisionRay(collisionProbeStart, collisionProbeDirection, clearance)
      if below >= clearance then
        collisionReuse.liftFinal = jump > 1 or lift == 0
        return liftedElevation - elevationRad, false, true
      end
      -- Resting on the ground under the camera: this rise is exact, no need to re-check it.
      local restingElevation = math.clamp(math.asin(math.clamp(
        (collisionLiftProbe.y + clearance - below) / offsetLength, -1, 1
      )), minElevation, maxElevation)
      if restingElevation > liftedElevation then
        return restingElevation - elevationRad, false, true
      end
      surface = 1
      clearingElevation = restingElevation
    else
      collisionReuse.liftFinal = jump > 1 or lift == 0
      return liftedElevation - elevationRad, false, true
    end

    if liftSign ~= 0 and surface ~= liftSign then
      searchCut = false
      -- The rise being eased is the wrong way round for what is there now: drop it and search
      -- afresh next frame rather than keep a blocked angle.
      if jump == 1 then return 0, false, false end
      break
    end
    liftSign = surface

    local nextElevation = math.clamp(clearingElevation, minElevation, maxElevation)
    if (nextElevation - liftedElevation) * liftSign <= 0.00001 then
      if nextElevation ~= clearingElevation then
        return liftedElevation - elevationRad, true, true
      end
      searchCut = false
      break
    end
    liftedElevation = nextElevation
  end

  if searchCut then collisionReuse.liftFinal = false end
  return liftedElevation - elevationRad, false, not searchCut
end

---@param arc CollisionArc
---@param position vec3
---@param dt number
local function updateArc(arc, position, dt)
  if not arc.valid or dt <= 0 or dt > 0.2 or position:distanceSquared(arc.position) > 625 then
    arc.valid = true
    arc.position:set(position)
    arc.velocity:set(0, 0, 0)
    arc.turnRate = 0
    return
  end
  local step = lookahead.step
  step:set((position - arc.position) / dt)
  -- Rate of turn: the heading change between the tracked and the new horizontal velocity.
  local oldSpeed = math.sqrt(arc.velocity.x * arc.velocity.x + arc.velocity.z * arc.velocity.z)
  local newSpeed = math.sqrt(step.x * step.x + step.z * step.z)
  local turnRate = 0
  if oldSpeed > 0.5 and newSpeed > 0.5 then
    ---@diagnostic disable-next-line: redundant-parameter
    turnRate = math.atan2(
      arc.velocity.z * step.x - arc.velocity.x * step.z,
      arc.velocity.x * step.x + arc.velocity.z * step.z
    ) / dt
  end
  local blend = 1 - math.exp(-COLLISION.ARC_SMOOTHING * dt)
  arc.turnRate = arc.turnRate + (turnRate - arc.turnRate) * blend
  arc.velocity:set(arc.velocity + (step - arc.velocity) * blend)
  arc.position:set(position)
end

-- Where the arc puts its point `time` seconds from now: a circle in the horizontal plane at the
-- tracked speed and rate of turn, and a straight climb.
---@param arc CollisionArc
---@param time number
---@param out vec3
local function predictArc(arc, time, out)
  local velocity = arc.velocity
  out:set(arc.position)
  out.y = out.y + velocity.y * time
  local speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
  if speed < 0.0001 then return end
  local dirX, dirZ = velocity.x / speed, velocity.z / speed
  local turn = arc.turnRate * time
  local along, across = speed * time, 0
  if math.abs(turn) > 0.001 then
    local radius = speed / arc.turnRate
    along = radius * math.sin(turn)
    across = radius * (1 - math.cos(turn))
  end
  -- (dirZ, -dirX) is the side a positive rate of turn heads towards.
  out.x = out.x + dirX * along + dirZ * across
  out.z = out.z + dirZ * along - dirX * across
end

-- Casts the predicted line of sight with the frame's leftover rays and records the rise (ground,
-- ceiling) or pull-in (wall) it will need. Nothing found, or no rays left: nothing asked for.
local function castLookahead()
  lookahead.liftSide = 0
  lookahead.clear = false
  lookahead.pullIn = 0
  if collisionRaysLeft < 1 or not lookahead.cameraArc.valid then return end
  local time = collisionLiftTarget < 0 and COLLISION.CEILING_LOOKAHEAD_TIME or COLLISION.LOOKAHEAD_TIME
  predictArc(lookahead.targetArc, time, lookahead.target)
  predictArc(lookahead.cameraArc, time, lookahead.camera)
  local direction = lookahead.direction
  direction:set(lookahead.camera - lookahead.target)
  local length = #direction
  if length < 0.5 then return end
  direction:set(direction / length)

  local clearance = runtimeConfig.collisionGroundClearance
  local probeLength = length + clearance
  local hitDistance = castCollisionRay(lookahead.target, direction, probeLength)
  if hitDistance >= probeLength then
    lookahead.clear = true
    return
  end
  if hitDistance < COLLISION.LOOKAHEAD_MIN_HIT then return end
  local hit = lookahead.hit
  hit:set(lookahead.target + direction * hitDistance)
  local surface = classifySurfaceCached(lookahead.surfaceCache, hit, direction)
  if surface == 0 then
    local travel = lookahead.target:distance(lookahead.targetArc.position)
    if travel <= COLLISION.LOOKAHEAD_WALL_MAX_TRAVEL then
      lookahead.pullIn = math.max(0, length - hitDistance)
    end
  elseif surface == 1 then
    -- Ground only: a predicted ceiling would duck the camera for something that may not be there.
    local target = lookahead.target
    local hitHorizontal = math.max(0.1, math.sqrt((hit.x - target.x) ^ 2 + (hit.z - target.z) ^ 2))
    ---@diagnostic disable-next-line: redundant-parameter
    local elevation = math.atan2(direction.y, math.sqrt(direction.x ^ 2 + direction.z ^ 2))
    ---@diagnostic disable-next-line: redundant-parameter
    local clearing = math.atan2(hit.y + surface * clearance - target.y, hitHorizontal)
    -- Kept as an elevation, not a rise: the predicted line may be lower than the camera is now.
    if (clearing - elevation) * surface > 0 then
      lookahead.lift = clearing
      lookahead.liftSide = surface
    end
  end
end

-- Ground or a tunnel ceiling between the car and the camera: orbit the camera over (or under)
-- it at the same distance and keep aiming at the car, instead of pulling the camera in.
---@param targetPos vec3
---@param desiredCameraPosition vec3
---@param desiredCameraDirection vec3
---@param dt number
---@param reuse boolean @Nothing moved: keep last frame's target instead of solving again.
local function applySurfaceLift(targetPos, desiredCameraPosition, desiredCameraDirection, dt, reuse)
  collisionLiftOffset:set(desiredCameraPosition - targetPos)
  local offsetLength = #collisionLiftOffset
  collisionLiftHorizontal:set(collisionLiftOffset.x, 0, collisionLiftOffset.z)
  local horizontalLength = #collisionLiftHorizontal
  if offsetLength <= 0.0001 or horizontalLength <= 0.0001 then
    collisionLiftAngleRad = 0
    collisionLiftVelocity = 0
    collisionLiftTarget = 0
    collisionLiftAtLimit = false
    collisionHold.final = nil
    return
  end
  collisionLiftHorizontal:set(collisionLiftHorizontal / horizontalLength)
  ---@diagnostic disable-next-line: redundant-parameter
  local elevationRad = math.atan2(collisionLiftOffset.y, horizontalLength)

  -- Last frame's target, as the same elevation seen from this frame's pitch. Pitched past it:
  -- nothing to hold any more.
  local previousTarget = 0
  if collisionLiftTarget ~= 0 then
    previousTarget = collisionHold.goal - elevationRad
    if previousTarget * collisionLiftTarget <= 0 then previousTarget = 0 end
  end
  local neededAngle, atLimit, complete
  if reuse then
    neededAngle, atLimit, complete = previousTarget, collisionLiftAtLimit, true
  else
    -- The camera's own spot seen clear for a moment: the ground or ceiling was in the way only
    -- briefly (a bridge, a crest), so let go and go there, however the search below is doing.
    -- Under a ceiling, a clear line where the car is heading counts too.
    local goalClear = previousTarget ~= 0
      and isLiftGoalClear(targetPos, elevationRad, offsetLength, math.sign(previousTarget))
    if previousTarget < 0 and lookahead.clear then goalClear = true end
    if goalClear == false or previousTarget == 0 then
      collisionHold.goalClear = 0
    elseif goalClear then
      collisionHold.goalClear = collisionHold.goalClear + math.max(dt, 0)
    end
    if collisionHold.goalClear >= COLLISION.RELEASE_HOLD then
      collisionHold.goalClear = 0
      neededAngle, atLimit, complete = 0, false, true
    else
      neededAngle, atLimit, complete = findLiftAngle(
        targetPos, elevationRad, offsetLength, previousTarget, dt
      )
      -- Start rising for what is coming.
      local side = lookahead.liftSide
      if side ~= 0 then
        local ahead = math.clamp(lookahead.lift, CAMERA_PITCH_MIN_RAD, CAMERA_PITCH_MAX_RAD)
          - elevationRad
        if ahead * side > 0 and neededAngle * side >= 0 and math.abs(ahead) > math.abs(neededAngle) then
          neededAngle = ahead
        end
      end
      -- Hold a falling rise briefly before letting it go.
      local falling = neededAngle * previousTarget >= 0
        and math.abs(neededAngle) < math.abs(previousTarget)
      if not falling then
        collisionHold.liftTimer = COLLISION.RELEASE_HOLD
      elseif collisionHold.liftTimer > 0 then
        collisionHold.liftTimer = collisionHold.liftTimer - math.max(dt, 0)
        neededAngle, atLimit = previousTarget, collisionLiftAtLimit
      end
    end
  end
  collisionLiftAtLimit = atLimit
  collisionLiftComplete = complete
  collisionLiftTarget = neededAngle
  collisionHold.goal = elevationRad + neededAngle
  local springDt = math.max(dt, 0)

  -- Camera: critically damped spring towards the target, one frequency, no overshoot.
  local frequency = COLLISION.LIFT_FOLLOW_FREQUENCY
  local offset = collisionLiftAngleRad - collisionLiftTarget
  local decay = math.exp(-frequency * springDt)
  local springTerm = (collisionLiftVelocity + frequency * offset) * springDt
  collisionLiftAngleRad = collisionLiftTarget + (offset + springTerm) * decay
  collisionLiftVelocity = (collisionLiftVelocity - frequency * springTerm) * decay
  -- Still short of the target: pitching fast into the ground stops dead on the clearance line
  -- instead of dipping in and bouncing back out. Already under it: climb back without sinking.
  local side = math.sign(collisionLiftTarget)
  local final = collisionHold.final
  if final and side ~= 0 and (collisionLiftTarget - collisionLiftAngleRad) * side > 0 then
    local keep = final - elevationRad
    local catch = collisionLiftTarget
    if (collisionLiftTarget - keep) * side > COLLISION.LIFT_SNAP_RAD then
      catch = collisionLiftTarget
        + (keep - collisionLiftTarget) * math.exp(-COLLISION.LIFT_CATCH_FREQUENCY * springDt)
    end
    if (catch - collisionLiftAngleRad) * side > 0 then
      collisionLiftAngleRad = catch
      collisionLiftVelocity = 0
    end
  end
  collisionHold.final = elevationRad + collisionLiftAngleRad

  if math.abs(collisionLiftAngleRad) < 0.0001 and math.abs(collisionLiftVelocity) < 0.0001
      and collisionLiftTarget == 0 then
    collisionLiftAngleRad = 0
    collisionLiftVelocity = 0
    collisionHold.final = elevationRad
    return
  end

  setLiftedOffset(collisionLiftAngleRad, elevationRad, offsetLength)
  desiredCameraPosition:set(targetPos + collisionLiftProbe)

  -- Rotate the view direction by the same vertical orbit so the framing is unchanged.
  local cosAngle = math.cos(collisionLiftAngleRad)
  local sinAngle = math.sin(collisionLiftAngleRad)
  local alongHorizontal = desiredCameraDirection:dot(collisionLiftHorizontal)
  local alongUp = desiredCameraDirection.y
  collisionLiftSide:set(
    desiredCameraDirection
      - collisionLiftHorizontal * alongHorizontal
      - WORLD_UP * alongUp
  )
  desiredCameraDirection:set(
    collisionLiftSide
      + collisionLiftHorizontal * (alongHorizontal * cosAngle - alongUp * sinAngle)
      + WORLD_UP * (alongHorizontal * sinAngle + alongUp * cosAngle)
  )
  desiredCameraDirection:normalize()
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
    local cornerPos = collisionRayDestinations[i] ---@cast cornerPos -?
    local rayDest = collisionRayDestinations[i % 4 + 1] ---@cast rayDest -?
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
---@return number @How much the camera was pulled in: corrected distance / desired distance.
local function applyCameraCollision(targetPos, desiredCameraPosition, desiredCameraDirection, dt)
  collisionRaysLeft = COLLISION.RAY_BUDGET

  local staticDistanceSquared = COLLISION.STATIC_DISTANCE * COLLISION.STATIC_DISTANCE
  local reuse = collisionReuse.hasPose
    and (collisionReuse.liftFinal or not isSmartCollision())
    and targetPos:distanceSquared(collisionReuse.target) < staticDistanceSquared
    and desiredCameraPosition:distanceSquared(collisionReuse.desired) < staticDistanceSquared
  -- Compare against the pose the answer was worked out for, not last frame's: slow movement
  -- (smoothing, a held key) stays under the threshold every frame but adds up.
  if not reuse then
    collisionReuse.target:set(targetPos)
    collisionReuse.desired:set(desiredCameraPosition)
    collisionReuse.hasPose = true
  end

  updateArc(lookahead.targetArc, targetPos, dt)
  updateArc(lookahead.cameraArc, desiredCameraPosition, dt)
  if reuse or not isSmartCollision() then
    lookahead.liftSide = 0
    lookahead.clear = false
    lookahead.pullIn = 0
  end

  if isSmartCollision() then
    applySurfaceLift(targetPos, desiredCameraPosition, desiredCameraDirection, dt, reuse)
  end

  collisionDirection:set(desiredCameraPosition - targetPos)
  local directionLength = #collisionDirection ---@type number
  collisionLastDesiredDistance = directionLength
  if directionLength <= 0.0001 then
    collisionPullIn = 0
    collisionPullVelocity = 0
    collisionHasLastNearClipCenter = false
    collisionUseRaycast = true
    return 1
  end

  local assumedNearClipDistance = COLLISION.ASSUMED_NEAR_CLIP_DISTANCE

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
  collisionCamRight:set(collisionCamRight * COLLISION.NEAR_CLIP_HALF_WIDTH)
  collisionCamUp:set(collisionCamUp * COLLISION.NEAR_CLIP_HALF_HEIGHT)

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

  -- Smart modes always cast the four corners: cheaper than the near-clip edge check plus corners.
  if reuse then
    collisionUseRaycast = false
  elseif isSmartCollision() then
    collisionUseRaycast = true
  elseif not collisionUseRaycast and isObstacleInFrontOfCamera() then
    collisionUseRaycast = true
  end

  local closestHit = directionLength ---@type number
  local hitRegistered = false
  if reuse then
    -- Only an actual wall hit carries over; with none, the desired distance (which zooming changes)
    -- is free, or a stale "hit" at the old distance would pull the camera in.
    hitRegistered = collisionReuse.hitRegistered
    if hitRegistered then
      closestHit = math.min(collisionReuse.closestHit, directionLength)
    end
  elseif collisionUseRaycast then
    -- Smart modes cast two opposite corners (top-right, bottom-left) instead of all four: walls
    -- are vertical and the lift handles ground, so the diagonal still covers both sides.
    for i = 1, 4, isSmartCollision() and 2 or 1 do
      local cornerPos = collisionRayDestinations[i]
      collisionRayStart:set(cornerPos - collisionDirection)
      local hitDistance = castCollisionRay(
        collisionRayStart,
        collisionDirection,
        closestHit
      )
      -- In smart modes ground and ceilings are the lift's job, never a reason to pull in, unless
      -- the lift is maxed out and still blocked. Only walls (or unreadable surfaces) pull in.
      if hitDistance < closestHit and isSmartCollision() and not collisionLiftAtLimit then
        collisionWallHitPoint:set(collisionRayStart + collisionRayDirection * hitDistance)
        collisionEdgeDirection:set(collisionRayDirection)
        local surface = classifySurfaceCached(
          cornerSurfaceCaches[i], collisionWallHitPoint, collisionEdgeDirection
        )
        if surface == 1 or surface == -1 then
          hitDistance = closestHit
        end
      end
      -- Physics-shape modes only count what is low enough to be a wall beside the road: a line that
      -- passes through a tree trunk or a tall bank well above the car doesn't pull the camera in.
      if hitDistance < closestHit and car ~= nil and isPhysicsShapeCollision() then
        collisionWallProbe:set(collisionRayStart + collisionRayDirection * hitDistance)
        if collisionWallProbe.y - car.position.y > runtimeConfig.collisionMaxHitHeight then
          hitDistance = closestHit
        end
      end
      if hitDistance < closestHit then
        closestHit = hitDistance
        hitRegistered = true
      end
    end
    closestHit = math.max(closestHit, math.min(runtimeConfig.collisionMinDistance, directionLength))
  end

  collisionReuse.closestHit = closestHit
  collisionReuse.hitRegistered = hitRegistered
  if not hitRegistered then
    collisionUseRaycast = false
  end

  -- Ease the pull-in (how far in from the desired distance) rather than the distance itself, so
  -- zooming with no wall around is untouched.
  local stepDt = math.max(dt, 0)
  local wallPullIn = directionLength - closestHit
  local expected = math.max(lookahead.pullIn, collisionPullIn)
  local surprise = hitRegistered and wallPullIn > expected + math.max(
    COLLISION.WALL_MATCH_MIN, directionLength * COLLISION.WALL_MATCH_FRACTION
  )
  if surprise then
    collisionHold.wallTime = collisionHold.wallTime + stepDt
  elseif not reuse then
    collisionHold.wallTime = 0
  end
  local waiting = surprise and collisionHold.wallTime <= COLLISION.WALL_WAIT
  if waiting then wallPullIn = math.min(wallPullIn, expected) end
  local targetPullIn = math.max(
    wallPullIn,
    math.min(lookahead.pullIn, directionLength - runtimeConfig.collisionMinDistance)
  )
  local inside = hitRegistered and not waiting
  -- Hold a falling pull-in briefly before letting it go.
  if targetPullIn >= collisionHold.pullIn then
    collisionHold.pullIn = targetPullIn
    collisionHold.pullTimer = COLLISION.RELEASE_HOLD
  elseif collisionHold.pullTimer > 0 then
    collisionHold.pullTimer = collisionHold.pullTimer - stepDt
    targetPullIn = collisionHold.pullIn
  else
    collisionHold.pullIn = targetPullIn
  end
  if stepDt > 0 then
    -- Critically damped spring, then the speed and acceleration caps.
    local fast = inside and COLLISION.PULL_FAST_FACTOR or 1
    local frequency = COLLISION.PULL_FREQUENCY * fast
    local offset = collisionPullIn - targetPullIn
    local decay = math.exp(-frequency * stepDt)
    local springTerm = (collisionPullVelocity + frequency * offset) * stepDt
    local springPullIn = targetPullIn + (offset + springTerm) * decay
    local springVelocity = (collisionPullVelocity - frequency * springTerm) * decay
    local maxSpeed = math.max(
      COLLISION.PULL_MAX_SPEED,
      directionLength * COLLISION.PULL_MAX_SPEED_PER_METRE
    ) * fast
    local maxVelocityChange = COLLISION.PULL_MAX_ACCELERATION
      * (maxSpeed / COLLISION.PULL_MAX_SPEED) * stepDt
    local velocity = math.clamp(
      math.clamp(
        springVelocity,
        collisionPullVelocity - maxVelocityChange,
        collisionPullVelocity + maxVelocityChange
      ),
      -maxSpeed,
      maxSpeed
    )
    if velocity == springVelocity then
      collisionPullIn = springPullIn
    else
      collisionPullIn = collisionPullIn + velocity * stepDt
    end
    collisionPullVelocity = velocity
    -- Inside a wall by a little: no easing in, the camera goes straight to the near side of it
    -- (the way the lift stops dead on the ground). Bigger gaps take the quick spring above.
    local snap = math.max(COLLISION.WALL_SNAP_MIN, directionLength * COLLISION.WALL_SNAP_FRACTION)
    if inside and collisionPullIn < targetPullIn and targetPullIn - collisionPullIn <= snap then
      collisionPullIn = targetPullIn
      collisionPullVelocity = 0
    end
  end
  collisionPullIn = math.clamp(
    collisionPullIn,
    0,
    math.max(0, directionLength - runtimeConfig.collisionMinDistance)
  )
  local smoothedDistance = directionLength - collisionPullIn

  collisionLastNearClipCenter:set(collisionNearClipCenter)
  collisionHasLastNearClipCenter = true
  if not reuse and isSmartCollision() then castLookahead() end

  collisionCorrectedPosition:set(
    targetPos
      + collisionDirection
        * ((smoothedDistance + assumedNearClipDistance) / directionLength)
  )
  desiredCameraPosition:set(collisionCorrectedPosition)
  return math.min(1, (smoothedDistance + assumedNearClipDistance) / directionLength)
end

---@param dt number
---@param targetCar ac.StateCar
---@param config BeamNGOrbitCameraConfig
---@param input BeamNGOrbitCameraInput
---@return BeamNGOrbitCameraPose?
function M.update(dt, targetCar, config, input)
  if targetCar == nil then return nil end

  applyRuntimeConfig(config)

  if car == nil or currentCarIndex ~= targetCar.index then
    car = targetCar
    currentCarIndex = targetCar.index
    resetCameraState(runtimeConfig.keepViewOnCarSwitch)
  else
    car = targetCar
  end

  if not orbitInitialized then
    orbitPitchRad = runtimeConfig.cameraPitchRad
    displayedPitchRad = orbitPitchRad
    orbitYawRad = 0
    displayedYawRad = 0
    orbitDistance = runtimeConfig.cameraDistance
    displayedDistance = orbitDistance
    orbitTanHalfFov = fovToTanHalf(runtimeConfig.cameraFov)
    displayedTanHalfFov = orbitTanHalfFov
    orbitInitialized = true
  end

  local carSpeed = math.abs(car.speedMs)
  if smoothedSpeed == nil or math.abs(carSpeed - smoothedSpeed) > 20 then
    smoothedSpeed = carSpeed
  else
    smoothedSpeed = smoothedSpeed + (carSpeed - smoothedSpeed) * (1 - math.exp(-SPEED_SMOOTHING * math.max(dt, 0)))
  end

  effectiveRelaxation = getEffectiveRelaxation(carSpeed)

  collisionCarUp:set(car.up)
  local carHeading = planarHeading(car.look)
  if carHeading == VEC3_ZERO then
    carHeading = headingInitialized and headingReference or lastValidCarHeading
  else
    lastValidCarHeading = carHeading
  end

  local carPosition = car.transform.position
  local targetPos = carPosition + WORLD_UP * runtimeConfig.cameraTargetHeightOffset
  updateAabbReferences()
  updateRearReference()
  local replayHold = shouldHoldReplayCamera(ac.getSim(), targetPos, carHeading, carSpeed, dt)
  if replayHold then
    holdCameraToCar(targetPos, carHeading)
  else
    handleLockedCameraHemisphere(targetPos)
    updateMovementHeading(targetPos, carHeading, dt)
    tmpHorizontal:set(headingReference.x, 0, headingReference.z)
    if #tmpHorizontal > 0.0001 then
      tmpHorizontal:normalize()
      replayHoldYawRad = signedHeadingError(carHeading, tmpHorizontal)
    end
  end

  input = input or {}
  local manualYawStepRad = tonumber(input.yawStepRad) or 0.0
  local manualPitchStepRad = tonumber(input.pitchStepRad) or 0.0
  local zoomStep = tonumber(input.zoomStep) or 0.0
  local zoomDistanceStep = tonumber(input.zoomDistanceStep) or 0.0
  local zoomFovStep = tonumber(input.zoomFovStep) or 0.0
  local zoomDollyStep = tonumber(input.zoomDollyStep) or 0.0
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
  if manualRotationActive
      or math.abs(zoomStep) > INPUT_ANGLE_EPSILON_RAD
      or math.abs(zoomDistanceStep) > INPUT_ANGLE_EPSILON_RAD
      or math.abs(zoomFovStep) > INPUT_ANGLE_EPSILON_RAD
      or math.abs(zoomDollyStep) > INPUT_ANGLE_EPSILON_RAD then
    cameraOrbitActive = true
  end

  -- Input edits what the user sees. Pitching into the ground (or a ceiling) that holds the camera
  -- is dropped: the lift stays, the camera stays clear, and the pitch doesn't wind away unseen.
  -- Pitching away from it first takes on the real camera pitch, so the first nudge moves the
  -- camera instead of winding back an offset hidden in the ground. Zooming while a wall holds the
  -- camera in does the same with the distance. Without input the requested position is kept, and
  -- the camera returns to it once clear.
  local liftHolding = math.abs(collisionLiftTarget) > INPUT_ANGLE_EPSILON_RAD
    and collisionLiftTarget
    or collisionLiftAngleRad
  if liftHolding * manualPitchStepRad < 0 then
    manualPitchStepRad = 0
  end
  if math.abs(manualPitchStepRad) > INPUT_ANGLE_EPSILON_RAD
      and collisionLiftAngleRad * manualPitchStepRad > 0 then
    displayedPitchRad = math.clamp(
      displayedPitchRad + collisionLiftAngleRad,
      CAMERA_PITCH_MIN_RAD,
      CAMERA_PITCH_MAX_RAD
    )
    orbitPitchRad = displayedPitchRad
    collisionLiftAngleRad = 0
    collisionLiftVelocity = 0
    collisionLiftTarget = 0
    collisionLiftComplete = true
    collisionHold.liftTimer = 0
    collisionReuse.hasPose = false
  end
  local zoomInputActive = math.abs(zoomStep) > INPUT_ANGLE_EPSILON_RAD
    or math.abs(zoomDistanceStep) > INPUT_ANGLE_EPSILON_RAD
    or math.abs(zoomFovStep) > INPUT_ANGLE_EPSILON_RAD
    or math.abs(zoomDollyStep) > INPUT_ANGLE_EPSILON_RAD
  if zoomInputActive and collisionPullIn > 0.001 and collisionLastDesiredDistance > 0.001 then
    local pullRatio = math.clamp(
      (collisionLastDesiredDistance - collisionPullIn) / collisionLastDesiredDistance,
      0.01,
      1
    )
    orbitDistance = clampDistance(displayedDistance * pullRatio)
    displayedDistance = orbitDistance
    if runtimeConfig.collisionKeepSubjectSize then
      orbitTanHalfFov = math.min(displayedTanHalfFov / pullRatio, MANUAL_TAN_HALF_FOV_MAX)
      displayedTanHalfFov = orbitTanHalfFov
    end
    collisionPullIn = 0
    collisionPullVelocity = 0
    collisionHold.pullIn = 0
    collisionHold.pullTimer = 0
    collisionHold.wallTime = 0
    collisionReuse.hasPose = false
  end

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
  applyFovZoom(zoomFovStep)
  applyDollyZoom(zoomDollyStep)

  -- Smoothed in log space so a dolly zoom keeps distance * tan(fov / 2) constant mid-transition.
  local distanceSmoothingT = (dt * 8) / (1 + dt * 8)
  displayedDistance = displayedDistance
    * (orbitDistance / displayedDistance) ^ distanceSmoothingT
  displayedTanHalfFov = displayedTanHalfFov
    * (orbitTanHalfFov / displayedTanHalfFov) ^ distanceSmoothingT

  updateDynamicPitchState(smoothedSpeed, manualRotationActive, dt)

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

  -- Both from the smoothed distance: the zoom target jumps a whole wheel notch at once, and using
  -- it here made the speed-FOV compensation jump (and bounce) ahead of the zoom smoothing.
  local dynamicFov, dynamicDistance = calculateDynamicFovAndDistance(
    displayedDistance,
    displayedDistance,
    smoothedSpeed,
    targetPos
  )
  local horizontalDistance = math.cos(displayedPitchRad) * dynamicDistance
  local verticalDistance = math.sin(displayedPitchRad) * dynamicDistance

  baseCameraPosition:set(
    targetPos
      - orbitForward * horizontalDistance
      + WORLD_UP * verticalDistance
  )

  -- Scaled with the zoom so it stays the same angle: a fixed rise tilts a close camera far more.
  local heightOffset = calculateDynamicHeight(smoothedSpeed)
    * dynamicDistance / math.max(runtimeConfig.cameraDistance, 0.1)
  finalCameraPosition:set(baseCameraPosition + WORLD_UP * heightOffset)

  baseDirection:set(targetPos - baseCameraPosition)
  if #baseDirection > 0.0001 then
    baseDirection:normalize()
  else
    baseDirection:set(orbitForward)
  end

  local dynamicPitchAngleRad = 0.0
  if dynamicPitchBlend > 0.0001 and runtimeConfig.dynamicPitchAtSpeedRad > 0 then
    local pitchLimitRad = calculateDynamicPitchLimit(
      targetPos, tanHalfToFov(displayedTanHalfFov), displayedPitchRad, dynamicDistance
    )
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

  local collisionEnabled =
    supportsCollisions
    and runtimeConfig.collisionHandlingMethod ~= COLLISION.HANDLING_DISABLED
    and (
      not runtimeConfig.disableCollisionWhenRecentered
      or cameraOrbitActive
    )
  local outputFov = dynamicFov
  if collisionEnabled then
    local pullInRatio = applyCameraCollision(targetPos, finalCameraPosition, finalDirection, dt)
    if runtimeConfig.collisionKeepSubjectSize and pullInRatio < 1 then
      outputFov = math.max(dynamicFov, tanHalfToFov(math.min(
        fovToTanHalf(dynamicFov) / math.max(pullInRatio, 0.0001),
        fovToTanHalf(runtimeConfig.collisionMaxFov)
      )))
    end
  else
    resetCollisionState()
  end

  outputPose.position:set(finalCameraPosition)
  outputPose.direction:set(finalDirection)
  outputPose.up:set(WORLD_UP)
  outputPose.fov = outputFov
  outputPose.currentPitch = math.deg(displayedPitchRad + dynamicPitchAngleRad)
  outputPose.currentDistance = dynamicDistance
  outputPose.currentFov = outputFov
  outputPose.currentHeight = runtimeConfig.cameraTargetHeightOffset + heightOffset
  outputPose.orbitPitch = math.deg(orbitPitchRad)
  outputPose.orbitDistance = orbitDistance
  outputPose.orbitFov = tanHalfToFov(orbitTanHalfFov)
  lastAppliedFov = dynamicFov

  return outputPose
end

function M.reset()
  resetCameraState()
end

return M