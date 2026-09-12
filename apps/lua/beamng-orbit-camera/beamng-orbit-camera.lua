
local Settings = require('modules/settings')
local Input = require('modules/input')
local ObsIntegration = require('modules/obs-integration')
local Extras = require('modules/extras')

Input.setSettings(Settings)

local VERSION_TEXT = 'Ver: 1.2.0'
local cameraIndex = -1;
local cameraActive = false
local playerWasInPit = false

local cameraBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.camera_bridge'),
  cameraIndex = ac.StructItem.uint32(),
  currentPitch = ac.StructItem.double(),
  currentDistance = ac.StructItem.double(),
  currentFov = ac.StructItem.double(),
  currentHeight = ac.StructItem.double(),
  orbitPitch = ac.StructItem.double(),
  orbitDistance = ac.StructItem.double(),
}, false, ac.SharedNamespace.Shared)

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
---@diagnostic disable-next-line: duplicate-set-field
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
    cameraBridge.orbitPitch
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

local tabContentSize = vec2()
local STATUS_BAR_GAP = 8
local SCROLLBAR_CONTENT_GAP = 8

local function drawTab(label, content)
  ui.tabItem(label, function()
    tabContentSize:set(ui.availableSpace())
    tabContentSize.y = tabContentSize.y - ui.measureText('C').y - STATUS_BAR_GAP
    if tabContentSize.y <= 0 then return end
    ui.childWindow('content', tabContentSize, function()
      local scrollbarGap = ui.getScrollMaxY() > 0 and SCROLLBAR_CONTENT_GAP or 0
      ui.beginGroup(math.max(1, ui.availableSpaceX() - scrollbarGap))
      content()
      ui.endGroup()
    end)
  end)
end

local function drawTabs()
  drawTab('Camera', Settings.drawCameraTab)
  drawTab('Controls', Input.drawControlsTab)
  drawTab('Extras', Extras.drawExtrasTab)
end

local function drawStatusBar()
  local windowSize = ui.windowSize()
  local textDim = ui.measureText('C')

  ui.setCursorY(windowSize.y - textDim.y - 8)
  if cameraActive then
    ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
    ui.text('Cam:')
    ui.popStyleColor()
    ui.sameLine()
    ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.lime)
    ui.text('active')
    ui.popStyleColor()
  end
  if ObsIntegration.enabled then
    if cameraActive then
      ui.sameLine()
    end
    ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
    ui.text('Obs:')
    ui.popStyleColor()
    ui.sameLine()
    ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.lime)
    ui.text('active')
    ui.popStyleColor()
  end
end

---@param dt number
function script.windowMain(dt)
  ui.textColored(VERSION_TEXT, rgbm.colors.gray)
  ui.tabBar('beamngOrbitCameraTabs', drawTabs)
  drawStatusBar()
end

