--------
-- BeamNG-style Orbit Camera companion Lua App.
--
-- Keeps orchestration only. Persisted settings, device input and optional OBS
-- rendering each live in their own module.
--------

local Settings = require('modules/settings')
local Input = require('modules/input')
local ObsIntegration = require('modules/obs-integration')

Input.setSettings(Settings)

local VERSION_TEXT = 'App: v1.1.0, Cam: v1.1.0'
local cameraIndex = -1;
local cameraActive = false
local playerWasInPit = false

local cameraBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.camera_bridge'),
  cameraIndex = ac.StructItem.uint32(),
}, false, ac.SharedNamespace.Shared)

local function updateAutomaticRecenter()
  local playerCar = ac.getCar(0)
  if playerCar == nil then
    return
  end

  local playerInPit = playerCar.isInPit
  if playerInPit and not playerWasInPit then
    Input.cameraInput.recenterKeepValuesPressed = true
  end
  playerWasInPit = playerInPit
end

ac.onSessionStart(function(_, restarted)
  if not restarted then return end

  Input.cameraInput.recenterKeepValuesPressed = true
end)

---@param dt number
---@diagnostic disable-next-line: duplicate-set-field
function script.update(dt)

  cameraIndex = cameraBridge.cameraIndex

  local sim = ac.getSim()

  cameraActive = sim.cameraMode == ac.CameraMode.Drivable and
                 cameraIndex == 1 and sim.driveableCameraMode == ac.DrivableCamera.Chase or
                 cameraIndex == 2 and sim.driveableCameraMode == ac.DrivableCamera.Chase2
  local shouldUpdate = cameraActive or
                       ObsIntegration.enabled

  if shouldUpdate then
    if cameraActive then
      Input.update(dt)
      Settings.update()
    end

    updateAutomaticRecenter()

    ObsIntegration.update(dt, Settings.cameraConfig, Input.cameraInput)

    Input.writeToBridge()
    Input.reset()
  end
end

local function drawTabs()
  ui.tabItem('Camera', Settings.drawCameraTab)
  ui.tabItem('Controls', Input.drawControlsTab)
  ui.tabItem('OBS Integration', ObsIntegration.drawObsIntegrationTab)
end

---@param label string
---@param active boolean
local function drawStatus(label, active)
  ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
  ui.text(label)
  ui.popStyleColor()
  ui.sameLine()

  ui.pushStyleColor(
    ui.StyleColor.Text,
    active and rgbm.colors.lime or rgbm.colors.gray
  )
  ui.text(active and 'active' or 'inactive')
  ui.popStyleColor()
end

local function drawStatusBar()
  local windowSize = ui.windowSize()
  local textDim = ui.measureText('C')

  ui.setCursorY(windowSize.y - textDim.y - 8)

  drawStatus('Cam:', cameraActive)
  ui.sameLine()
  drawStatus('Obs:', ObsIntegration.enabled)
end

---@param dt number
function script.windowMain(dt)
  ui.textColored(VERSION_TEXT, rgbm.colors.gray)
  ui.tabBar('beamngOrbitCameraTabs', drawTabs)
  drawStatusBar()
end
