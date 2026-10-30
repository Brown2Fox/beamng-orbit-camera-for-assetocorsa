
local Settings = require('modules/settings')
local Input = require('modules/input')
local ObsIntegration = require('modules/obs-integration')

Input.setSettings(Settings)

local VERSION_TEXT = 'Ver: 2.0.0'
local cameraIndex = -1;
local cameraActive = false
local playerWasInPit = false

---@class CameraBridgeLayout
---@field cameraIndex integer
---@field currentPitch number
---@field currentDistance number
---@field currentFov number
---@field currentHeight number
---@field orbitPitch number
---@field orbitDistance number
---@field orbitFov number

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

---@param keepValues boolean
local function requestRecenter(keepValues)
    if keepValues then
      Input.cameraInput.recenterKeepValuesPressed = true
    else
      Input.cameraInput.recenterPressed = true
    end
end

local function updateAutomaticRecenter()
  local playerCar = ac.getCar(0)
  if playerCar == nil then
    return
  end

  local playerInPit = playerCar.isInPit
  if playerInPit and not playerWasInPit then
    requestRecenter(true)
  end
  playerWasInPit = playerInPit
end

ac.onSessionStart(function(_, restarted)
  if not restarted then return end

  requestRecenter(true)
end)

local function settingsUpdate()
  local recenterRequested, keepValues = Settings.consumeRecenterRequest()
  if recenterRequested then requestRecenter(keepValues) end
  Settings.update()
end

---@param dt number
function script.update(dt)

  cameraIndex = cameraBridge.cameraIndex

  local sim = ac.getSim()

  cameraActive = sim.cameraMode == ac.CameraMode.Drivable and
                 cameraIndex == 1 and sim.driveableCameraMode == ac.DrivableCamera.Chase or
                 cameraIndex == 2 and sim.driveableCameraMode == ac.DrivableCamera.Chase2
  local shouldUpdate = cameraActive or
                        ObsIntegration.enabled

  Settings.setLiveCameraValues(
    cameraActive,
    cameraBridge.currentDistance,
    cameraBridge.currentFov,
    cameraBridge.currentPitch,
    cameraBridge.currentHeight,
    cameraBridge.orbitDistance,
    cameraBridge.orbitPitch,
    cameraBridge.orbitFov
  )

  if shouldUpdate then
    if cameraActive then
      Input.update(dt)
      settingsUpdate()
    end

    updateAutomaticRecenter()

    ObsIntegration.update(dt, Settings.cameraConfig, Input.cameraInput)

    Input.writeToBridge()
    Input.reset()
  end
end

local function drawPage()
  Settings.drawCameraTab()

  ui.newLine()
  if Settings.collisionsSupported() then
    ui.treeNode('Obstacles: ' .. Settings.collisionSummary() .. '###obstacles', Settings.drawCollisionSettings)
  end
  ui.treeNode('Controls: ' .. Input.controlsSummary() .. '###controls', Input.drawControlsTab)
  ui.treeNode('Streaming: ' .. (ObsIntegration.enabled and 'OBS on' or 'off') .. '###streaming', ObsIntegration.drawObsIntegrationTab)
end

local function drawStatusBar()
  ui.newLine()
  if cameraActive then
    ui.textColored('Cam: active', rgbm.colors.lime)
  end
  if ObsIntegration.enabled then
    if cameraActive then ui.sameLine() end
    ui.textColored('Obs: active', rgbm.colors.lime)
  end
end

---@param _dt number
function script.windowMain(_dt)
  ui.textColored(VERSION_TEXT, rgbm.colors.gray)
  drawPage()
  drawStatusBar()
end

