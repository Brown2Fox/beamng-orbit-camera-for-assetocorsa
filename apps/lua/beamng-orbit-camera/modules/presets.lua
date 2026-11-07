---@class BeamNGOrbitCameraPresets
local M = {}

local PRESET_SELECTED_STORAGE_KEY = 'beamng_orbit_camera.selected_camera_preset'
local DEFAULT_PRESET_NAME = 'BeamNG.drive defaults'
local DEFAULT_PRESET_ID = 'beamng-drive-defaults'
local PRESET_DIRECTORY = ac.getFolder(ac.FolderID.ScriptConfig) .. '/presets'
local selectedPresetStorage = ac.storage(PRESET_SELECTED_STORAGE_KEY, DEFAULT_PRESET_ID) --[[@as ac.StoredValue]]
---@type table<string, boolean>
local RESERVED_PRESET_FILENAMES = {
  CON = true,
  PRN = true,
  AUX = true,
  NUL = true,
  COM1 = true,
  COM2 = true,
  COM3 = true,
  COM4 = true,
  COM5 = true,
  COM6 = true,
  COM7 = true,
  COM8 = true,
  COM9 = true,
  LPT1 = true,
  LPT2 = true,
  LPT3 = true,
  LPT4 = true,
  LPT5 = true,
  LPT6 = true,
  LPT7 = true,
  LPT8 = true,
  LPT9 = true,
}

---@class BeamNGOrbitCameraPreset
---@field id string
---@field name string
---@field cameraConfig table<string, number>
---@field filename string?

---@class BeamNGOrbitCameraPresetsContext
---@field cameraParams table<string, ParamDef>
---@field getParamDef fun(key: string): ParamDef
---@field getParamVal fun(key: string): number
---@field setParamVal fun(key: string, value: number)
---@field clampParamValIfNeeded fun(value: number?, paramDef: ParamDef): number
---@field resetCameraParams fun()

---@type BeamNGOrbitCameraPresetsContext
local Context

---@type BeamNGOrbitCameraPreset[]
local presets = {}
local selectedPresetId = DEFAULT_PRESET_ID

---@type string?
local presetNameDraft = nil
---@type string?
local presetRenameId = nil

local focusPresetName = false
local presetButtonSize = vec2()
local presetEditorPadding = vec2(3, 0)
---@type table<string, number>?
local presetCloneConfig = nil
local MODIFIED_PARAM_COLOR = rgbm.colors.yellow
local PRESET_BUTTON_SPACING = 8

---@return BeamNGOrbitCameraPreset?
local function getSelectedPreset()
  for _, preset in ipairs(presets) do
    if preset.id == selectedPresetId then return preset end
  end
  return nil
end

---@param key string
---@return number
function M.getReferenceParamVal(key)
  local preset = Context.cameraParams[key] and getSelectedPreset()
  if preset and preset.cameraConfig[key] ~= nil then
    return preset.cameraConfig[key]
  end
  return Context.getParamDef(key).defaultValue
end

---@param key string
---@return boolean
function M.isParamModified(key)
  local paramDef = Context.getParamDef(key)
  return Context.clampParamValIfNeeded(Context.getParamVal(key), paramDef)
    ~= Context.clampParamValIfNeeded(M.getReferenceParamVal(key), paramDef)
end

---@return boolean
local function hasCameraChanges()
  for key in pairs(Context.cameraParams) do
    if M.isParamModified(key) then return true end
  end
  return false
end

---@return table<string, number>
local function getDefaultCameraConfig()
  ---@type table<string, number>
  local result = {}
  for key, paramDef in pairs(Context.cameraParams) do
    result[key] = paramDef.defaultValue
  end
  return result
end

---@param rawPreset {id: string, name: string, cameraConfig: table<string, number>, filename: string?}
---@return BeamNGOrbitCameraPreset?
local function normalizePreset(rawPreset)
  if type(rawPreset) ~= 'table' or type(rawPreset.id) ~= 'string' or type(rawPreset.name) ~= 'string' then
    return nil
  end
  ---@type table<string, number>
  local cameraConfig = {}
  if type(rawPreset.cameraConfig) == 'table' then
    for key in pairs(Context.cameraParams) do
      local values = rawPreset.cameraConfig --[[@as table<string, number>]]
      local value = values[key]
      if type(value) == 'number' then cameraConfig[key] = value end
    end
  end
  if next(cameraConfig) == nil then return nil end
  return {
    id = rawPreset.id,
    name = rawPreset.name,
    cameraConfig = cameraConfig,
  }
end

---@param preset BeamNGOrbitCameraPreset
---@return boolean
local function savePresetFile(preset)
  if preset.id == DEFAULT_PRESET_ID then return false end
  local filename = preset.filename or preset.name .. '.ini'
  local config = ac.INIConfig(ac.INIFormat.Default, {})
  config:set('PRESET', 'ID', preset.id)
  config:set('PRESET', 'NAME', preset.name)
  for key in pairs(Context.cameraParams) do
    config:set('CAMERA', key, preset.cameraConfig[key])
  end
  io.createDir(PRESET_DIRECTORY)
  if not io.save(PRESET_DIRECTORY .. '/' .. filename, config:serialize(), false) then return false end
  preset.filename = filename
  return true
end

---@param filename string
---@return BeamNGOrbitCameraPreset?
local function loadPresetFile(filename)
  local config = ac.INIConfig.load(PRESET_DIRECTORY .. '/' .. filename, ac.INIFormat.Default)
  if config == nil then return nil end
  local id = config:get('PRESET', 'ID', '')
  local name = config:get('PRESET', 'NAME', '')
  if id == '' or id == DEFAULT_PRESET_ID or name == '' then return nil end
  ---@type table<string, number>
  local cameraConfig = {}
  for key in pairs(Context.cameraParams) do
    local value = config:get('CAMERA', key, ac.INIConfig.OptionalNumber)
    if type(value) ~= 'number' then return nil end
    cameraConfig[key] = value
  end
  return normalizePreset({
    id = id,
    name = name,
    filename = filename,
    cameraConfig = cameraConfig,
  })
end

local function loadPresetsFromFiles()
  presets = {}
  ---@type table<string, boolean>
  local loadedIds = {}
  local filenames = io.scanDir(PRESET_DIRECTORY, '*.ini') or {}
  table.sort(filenames)
  for _, filename in ipairs(filenames) do
    local preset = loadPresetFile(filename)
    if preset and not loadedIds[preset.id] then
      preset.filename = filename
      table.insert(presets, preset)
      loadedIds[preset.id] = true
    end
  end
end

local function ensureDefaultPreset()
  table.insert(presets, 1, {
    id = DEFAULT_PRESET_ID,
    name = DEFAULT_PRESET_NAME,
    cameraConfig = getDefaultCameraConfig(),
  })
end

---@return table<string, number>
local function snapshotCameraConfig()
  ---@type table<string, number>
  local snapshot = {}
  for key in pairs(Context.cameraParams) do
    snapshot[key] = Context.clampParamValIfNeeded(Context.getParamVal(key), Context.getParamDef(key))
  end
  return snapshot
end

---@param snapshot table<string, number>
local function applyCameraConfig(snapshot)
  for key in pairs(Context.cameraParams) do
    Context.setParamVal(key, Context.clampParamValIfNeeded(snapshot[key], Context.getParamDef(key)))
  end
end

---@param value string
---@return boolean
local function hasPresetById(value)
  for _, preset in ipairs(presets) do
    if preset.id == value then return true end
  end
  return false
end

---@param value string
local function selectPreset(value)
  if not hasPresetById(value) then return end
  presetCloneConfig = nil
  presetNameDraft = nil
  presetRenameId = nil
  selectedPresetId = value
  for _, preset in ipairs(presets) do
    if preset.id == value then
      applyCameraConfig(preset.cameraConfig)
      break
    end
  end
  selectedPresetStorage:set(selectedPresetId)
end

---@param direction integer
function M.cycle(direction)
  if #presets < 2 or direction == 0 then return end
  for index, preset in ipairs(presets) do
    if preset.id == selectedPresetId then
      local nextIndex = (index - 1 + direction) % #presets + 1
      local nextPreset = presets[nextIndex] ---@type BeamNGOrbitCameraPreset?
      if nextPreset then selectPreset(nextPreset.id) end
      return
    end
  end
end

---@return string
local function getSelectedPresetName()
  local preset = getSelectedPreset()
  if preset then return preset.name end
  return 'No preset'
end

local function createPresetId()
  local candidate = tostring(os.time())
  while hasPresetById(candidate) do
    candidate = candidate .. math.random(0, 9)
  end
  return candidate
end

local function nextAvailablePresetName()
  local counter = 1
  while true do
    local candidate = 'Preset ' .. counter
    local exists = false
    for _, preset in ipairs(presets) do
      if preset.name == candidate then
        exists = true
        break
      end
    end
    if not exists then return candidate end
    counter = counter + 1
  end
end

---@param name string
---@param excludedId string?
---@return boolean
local function presetNameTaken(name, excludedId)
  for _, preset in ipairs(presets) do
    if preset.id ~= excludedId and preset.name:lower() == name:lower() then return true end
  end
  return false
end

---@param name string
---@param excludedId string?
---@return string?
local function getPresetNameError(name, excludedId)
  if name == '' then return 'Enter a preset name.' end
  if name:find('##', 1, true) then return 'Preset names cannot contain ##.' end
  if name:find('[<>:"/\\|%?%*%c]') or name:find('[%. ]$') then
    return 'Preset name contains characters that cannot be used in a file name.'
  end
  local filenameStem = (name:match('^[^.]+') or name):upper()
  if RESERVED_PRESET_FILENAMES[filenameStem] then
    return 'Preset name cannot be used as a file name.'
  end
  if presetNameTaken(name, excludedId) then return 'A preset with this name already exists.' end
  return nil
end

---@param name string
---@param snapshot table<string, number>?
local function saveCurrentPreset(name, snapshot)
  if getPresetNameError(name) then return end
  ---@type BeamNGOrbitCameraPreset
  local preset = {
    id = createPresetId(),
    name = name,
    cameraConfig = snapshot or snapshotCameraConfig(),
  }
  if not savePresetFile(preset) then return end
  table.insert(presets, preset)
  if snapshot then applyCameraConfig(snapshot) end
  presetCloneConfig = nil
  selectedPresetId = preset.id
  presetNameDraft = nil
  presetRenameId = nil
  selectedPresetStorage:set(selectedPresetId)
end

---@param id string
---@param name string
local function renamePreset(id, name)
  if id == DEFAULT_PRESET_ID or getPresetNameError(name, id) then return end
  for _, preset in ipairs(presets) do
    if preset.id == id then
      local previousName = preset.name
      local previousFilename = preset.filename
      preset.name = name
      preset.filename = name .. '.ini'
      if not savePresetFile(preset) then
        preset.name = previousName
        preset.filename = previousFilename
        return
      end
      if previousFilename and previousFilename:lower() ~= preset.filename:lower() then
        io.deleteFile(PRESET_DIRECTORY .. '/' .. previousFilename)
      end
      presetNameDraft = nil
      presetRenameId = nil
      return
    end
  end
end

local function updateCurrentPreset()
  local preset = getSelectedPreset()
  if preset == nil or preset.id == DEFAULT_PRESET_ID or not hasCameraChanges() then return end
  local previousConfig = preset.cameraConfig
  preset.cameraConfig = snapshotCameraConfig()
  if not savePresetFile(preset) then
    preset.cameraConfig = previousConfig
    return
  end
  selectedPresetStorage:set(selectedPresetId)
end

local function resetCurrentPresetChanges()
  local preset = getSelectedPreset()
  if preset then
    applyCameraConfig(preset.cameraConfig)
  else
    Context.resetCameraParams()
  end
end

function M.resetChanges()
  resetCurrentPresetChanges()
end

---@param id string
local function deletePreset(id)
  if id == DEFAULT_PRESET_ID then return end
  ---@type integer?
  local removeIndex = nil
  for index, preset in ipairs(presets) do
    if preset.id == id then
      removeIndex = index
      break
    end
  end
  if removeIndex == nil then return end
  local preset = presets[removeIndex]
  if preset == nil or preset.filename == nil then return end
  local presetPath = PRESET_DIRECTORY .. '/' .. preset.filename
  if not io.deleteFile(presetPath) then return end
  io.deleteFile(presetPath .. '.bak')
  table.remove(presets, removeIndex)
  if selectedPresetId == id then selectPreset(DEFAULT_PRESET_ID) end
end

---@param label string
---@return number
local function getPresetButtonWidth(label)
  return ui.measureText(label).x + 16
end

---@param label string
---@return boolean
local function drawPresetButton(label)
  ui.sameLine(0, PRESET_BUTTON_SPACING)
  presetButtonSize:set(getPresetButtonWidth(label), 0)
  return ui.button(label, presetButtonSize)
end

local function startAddingPreset()
  presetCloneConfig = nil
  presetRenameId = nil
  presetNameDraft = nextAvailablePresetName()
  focusPresetName = true
end

---@param preset BeamNGOrbitCameraPreset
local function startCloningPreset(preset)
  presetCloneConfig = {}
  for key, value in pairs(preset.cameraConfig) do
    presetCloneConfig[key] = value
  end
  local baseName = preset.name .. ' (Clone)'
  local name = baseName
  local suffix = 2
  while presetNameTaken(name) do
    name = baseName .. ' ' .. suffix
    suffix = suffix + 1
  end
  presetRenameId = nil
  presetNameDraft = name
  focusPresetName = true
end

---@param renameId string?
local function drawPresetNameRow(renameId)
  ui.pushItemWidth(ui.availableSpaceX())
  local focus = focusPresetName
  if focus then
    ui.setKeyboardFocusHere()
    focusPresetName = false
  end
  ui.pushStyleVar(ui.StyleVar.FramePadding, presetEditorPadding)
  local draft, _, submitted = ui.inputText(renameId and '##rename' .. renameId or '##clone', presetNameDraft or '')
  ui.popStyleVar()
  ui.popItemWidth()
  if focus then ui.setScrollHereY(0.5) end
  local outsideClick = not ui.itemHovered()
    and (ui.mouseClicked(ui.MouseButton.Left) or ui.mouseClicked(ui.MouseButton.Right))
  if outsideClick or ui.keyPressed(ui.Key.Escape) then
    presetCloneConfig = nil
    presetRenameId = nil
    presetNameDraft = nil
    return
  end
  presetNameDraft = draft
  local name = draft:match('^%s*(.-)%s*$') or ''
  local nameError = getPresetNameError(name, renameId)
  if nameError then
    if ui.itemHovered() or ui.itemActive() or submitted then ui.setTooltip(nameError) end
    if submitted then focusPresetName = true end
  elseif submitted then
    if renameId then
      renamePreset(renameId --[[@as string]], name)
    elseif presetCloneConfig then
      saveCurrentPreset(name, presetCloneConfig)
    end
  end
end

local function drawPresetSelector()
  if presetNameDraft ~= nil and presetRenameId == nil and presetCloneConfig == nil then
    local buttonsWidth = getPresetButtonWidth('Save') + getPresetButtonWidth('Cancel') + 2 * PRESET_BUTTON_SPACING
    ui.pushItemWidth(math.max(80, ui.availableSpaceX() - buttonsWidth))
    if focusPresetName then
      ui.setKeyboardFocusHere()
      focusPresetName = false
    end
    local _, submitted
    presetNameDraft, _, submitted = ui.inputText('##cameraPresetName', presetNameDraft --[[@as string]])
    local cancelled = ui.keyPressed(ui.Key.Escape)
    ui.popItemWidth()
    local saveClicked = drawPresetButton('Save')
    local cancelClicked = drawPresetButton('Cancel')
    submitted = submitted or saveClicked
    cancelled = cancelled or cancelClicked
    local name = presetNameDraft:match('^%s*(.-)%s*$') or ''
    local nameError = getPresetNameError(name, presetRenameId)
    if cancelled then
      presetNameDraft = nil
      presetRenameId = nil
      presetCloneConfig = nil
    elseif submitted and not nameError then
      saveCurrentPreset(name)
    elseif nameError then
      ui.textColored(nameError, MODIFIED_PARAM_COLOR)
    end
    return
  end

  local modified = hasCameraChanges()
  local selected = getSelectedPreset()
  local canUpdate = modified and selected and selected.id ~= DEFAULT_PRESET_ID
  local buttonsWidth = 0.0
  if canUpdate then buttonsWidth = buttonsWidth + getPresetButtonWidth('Save') + PRESET_BUTTON_SPACING end
  if modified then buttonsWidth = buttonsWidth + getPresetButtonWidth('Reset') + PRESET_BUTTON_SPACING end
  ui.pushItemWidth(math.max(80, ui.availableSpaceX() - buttonsWidth))
  if modified then ui.pushFont(ui.Font.Italic) end
  local comboOpen = ui.beginCombo('##cameraPresets', getSelectedPresetName())
  ---@type string?
  local presetToSelect = nil
  ---@type string?
  local presetToDelete = nil
  ---@type BeamNGOrbitCameraPreset?
  local presetToRename = nil
  ---@type BeamNGOrbitCameraPreset?
  local presetToClone = nil
  if comboOpen then
    if modified then ui.pushFont(ui.Font.Main) end
    local editingId = presetRenameId
    local cloning = presetCloneConfig ~= nil
    for _, preset in ipairs(presets) do
      if editingId == preset.id then
        drawPresetNameRow(editingId)
      elseif editingId or cloning then
        ui.selectable(preset.name .. '###' .. preset.id, preset.id == selectedPresetId, ui.SelectableFlags.Disabled)
      else
        if ui.selectable(preset.name .. '###' .. preset.id, preset.id == selectedPresetId) then
          presetToSelect = preset.id
        end
        if ui.beginPopupContextItem('presetContext' .. preset.id, ui.MouseButton.Right) then
          if preset.id ~= DEFAULT_PRESET_ID and ui.menuItem('Rename', false, ui.SelectableFlags.DontClosePopups) then
            presetToRename = preset
            ui.closePopup()
          end
          if ui.menuItem('Clone', false, ui.SelectableFlags.DontClosePopups) then
            presetToClone = preset
            ui.closePopup()
          end
          if preset.id ~= DEFAULT_PRESET_ID and ui.menuItem('Delete') then presetToDelete = preset.id end
          ui.endPopup()
        end
      end
    end
    if cloning then drawPresetNameRow(nil) end
    if modified then ui.popFont() end
    ui.endCombo()
  elseif presetRenameId or presetCloneConfig then
    presetCloneConfig = nil
    presetRenameId = nil
    presetNameDraft = nil
    focusPresetName = false
  end
  if modified then ui.popFont() end
  ui.popItemWidth()
  if presetToDelete then
    deletePreset(presetToDelete)
  elseif presetToRename then
    presetCloneConfig = nil
    presetRenameId = presetToRename.id
    presetNameDraft = presetToRename.name
    focusPresetName = true
  elseif presetToClone then
    startCloningPreset(presetToClone)
  elseif presetToSelect then
    selectPreset(presetToSelect)
  end
  if canUpdate and drawPresetButton('Save') then updateCurrentPreset() end
  if modified and drawPresetButton('Reset') then resetCurrentPresetChanges() end
end

---@param context BeamNGOrbitCameraPresetsContext
function M.initialize(context)
  Context = context
  loadPresetsFromFiles()
  ensureDefaultPreset()
  selectedPresetId = tostring(selectedPresetStorage:get())
  if not hasPresetById(selectedPresetId) then
    selectedPresetId = presets[1] and presets[1].id or ''
    selectedPresetStorage:set(selectedPresetId)
  end
end

function M.draw()
  ui.alignTextToFramePadding()
  ui.text('Presets')
  ui.sameLine()
  ui.setCursorX(ui.getCursorX() + ui.availableSpaceX() - getPresetButtonWidth('+'))
  if ui.smallButton('+##addPreset') then startAddingPreset() end
  if ui.itemHovered() then ui.setTooltip('Create a preset from current camera settings') end
  ui.separator()
  drawPresetSelector()
end

return M
