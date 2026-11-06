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
local presetRowSize = vec2()
local presetRowEnd = vec2()
local presetRenameButtonSize = vec2()
local presetDeleteButtonSize = vec2()
local presetActionsButtonSize = vec2()
local presetRenameSaveButtonSize = vec2()
local presetRenameCancelButtonSize = vec2()
local presetComboFramePadding = vec2()
---@type string?
local presetActionsId = nil
local MODIFIED_PARAM_COLOR = rgbm.colors.yellow
local PRESET_BUTTON_SPACING = 8
local PRESET_ROW_SPACING = vec2(0, 0)
local PRESET_ROW_PADDING = vec2(0, 0)
local PRESET_ROW_TEXT_ALIGN = vec2(0, 0.5)
local PRESET_TRANSPARENT_BACKGROUND = rgbm(0, 0, 0, 0)

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

local function getSelectedPresetName()
  local preset = getSelectedPreset()
  return preset and preset.name or 'No preset'
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
  for _, preset in ipairs(presets) do
    if preset.id ~= excludedId and preset.name:lower() == name:lower() then
      return 'A preset with this name already exists.'
    end
  end
  return nil
end

---@param name string
local function saveCurrentPreset(name)
  if getPresetNameError(name) then return end
  ---@type BeamNGOrbitCameraPreset
  local preset = {
    id = createPresetId(),
    name = name,
    cameraConfig = snapshotCameraConfig(),
  }
  if not savePresetFile(preset) then return end
  table.insert(presets, preset)
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
  presetRenameId = nil
  presetNameDraft = nextAvailablePresetName()
  focusPresetName = true
end

local function drawPresetSelector()
  local modified = hasCameraChanges()
  local selected = getSelectedPreset()
  local canUpdate = modified and selected and selected.id ~= DEFAULT_PRESET_ID
  local buttonsWidth = 0.0
  if presetNameDraft ~= nil and presetRenameId == nil then
    buttonsWidth = getPresetButtonWidth('Save') + getPresetButtonWidth('Cancel') + PRESET_BUTTON_SPACING * 2
  else
    if canUpdate then
      buttonsWidth = buttonsWidth + getPresetButtonWidth('Save') + PRESET_BUTTON_SPACING
    end
    if modified then
      buttonsWidth = buttonsWidth + getPresetButtonWidth('Reset') + PRESET_BUTTON_SPACING
    end
  end
  ui.pushItemWidth(math.max(80, ui.availableSpaceX() - buttonsWidth))
  if presetNameDraft ~= nil and presetRenameId == nil then
    if focusPresetName then
      ui.setKeyboardFocusHere()
      focusPresetName = false
    end
    local _, submitted
    presetNameDraft, _, submitted = ui.inputText('##cameraPresetName', presetNameDraft --[[@as string]])
    ui.popItemWidth()
    local name = presetNameDraft:match('^%s*(.-)%s*$') or ''
    local nameError = getPresetNameError(name, presetRenameId)
    local saveClicked = drawPresetButton('Save')
    local cancelClicked = drawPresetButton('Cancel')
    if cancelClicked then
      presetNameDraft = nil
      presetRenameId = nil
    elseif (saveClicked or submitted) and not nameError then
      saveCurrentPreset(name)
    elseif nameError then
      ui.textColored(nameError, MODIFIED_PARAM_COLOR)
    end
    return
  end
  local comboHeight = ui.frameHeight()
  presetComboFramePadding:set(0, (comboHeight - ui.textLineHeight()) * 0.5)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, PRESET_ROW_PADDING)
  ui.pushStyleVar(ui.StyleVar.FramePadding, presetComboFramePadding)
  ui.pushStyleVar(ui.StyleVar.PopupBorderSize, 0)
  local popupBackground = ui.styleColor(ui.StyleColor.PopupBg):clone()
  popupBackground.r = popupBackground.r * 0.8
  popupBackground.g = popupBackground.g * 0.8
  popupBackground.b = popupBackground.b * 0.8
  ui.pushStyleColor(ui.StyleColor.PopupBg, popupBackground)
  if modified then ui.pushFont(ui.Font.Italic) end
  local comboOpen = ui.beginCombo('##cameraPresets', ' ' .. getSelectedPresetName())
  ui.popStyleColor()
  ui.popStyleVar()
  ui.popStyleVar()
  ui.popStyleVar()
  ---@type string?
  local presetToSelect = nil
  ---@type string?
  local presetToDelete = nil
  ---@type BeamNGOrbitCameraPreset?
  local presetToRename = nil
  if comboOpen then
    if modified then ui.pushFont(ui.Font.Main) end
    ui.pushStyleVar(ui.StyleVar.ItemSpacing, PRESET_ROW_SPACING)
    ui.pushStyleVar(ui.StyleVar.SelectablePadding, PRESET_ROW_PADDING)
    ui.pushStyleVar(ui.StyleVar.SelectableTextAlign, PRESET_ROW_TEXT_ALIGN)
    local rowWidth = ui.availableSpaceX()
    local rowHeight = ui.frameHeight()
    presetRenameButtonSize:set(getPresetButtonWidth('Rename'), rowHeight)
    presetDeleteButtonSize:set(getPresetButtonWidth('Delete'), rowHeight)
    presetActionsButtonSize:set(getPresetButtonWidth('…'), rowHeight)
    presetRenameSaveButtonSize:set(getPresetButtonWidth('Save'), rowHeight)
    presetRenameCancelButtonSize:set(getPresetButtonWidth('Cancel'), rowHeight)
    local anyRowHovered = false
    for _, preset in ipairs(presets) do
      local isSelected = preset.id == selectedPresetId
      local canEdit = preset.id ~= DEFAULT_PRESET_ID
      local renaming = presetRenameId == preset.id
      local rowStart = ui.getCursor()
      presetRowEnd:set(rowStart.x + rowWidth, rowStart.y + rowHeight)
      local rowHovered = ui.rectHovered(rowStart, presetRowEnd)
      anyRowHovered = anyRowHovered or rowHovered
      if rowHovered and presetActionsId ~= preset.id then presetActionsId = nil end
      local showActionsButton = canEdit and rowHovered and not renaming
      local showActions = showActionsButton and presetActionsId == preset.id
      local rowColor = ui.styleColor(rowHovered and ui.StyleColor.HeaderHovered or ui.StyleColor.Header)
      if isSelected or rowHovered then ui.drawRectFilled(rowStart, presetRowEnd, rowColor) end
      if renaming then
        local inputWidth = rowWidth - presetRenameSaveButtonSize.x - presetRenameCancelButtonSize.x
        ui.pushItemWidth(inputWidth)
        if focusPresetName then
          ui.setKeyboardFocusHere()
          focusPresetName = false
        end
        local _, submitted
        presetNameDraft, _, submitted = ui.inputText('##renamePreset' .. preset.id, presetNameDraft --[[@as string]])
        ui.popItemWidth()
        local name = presetNameDraft:match('^%s*(.-)%s*$') or ''
        local nameError = getPresetNameError(name, presetRenameId)
        ui.sameLine(0, 0)
        local saveClicked = ui.button('Save###savePresetName' .. preset.id, presetRenameSaveButtonSize)
        ui.sameLine(0, 0)
        local cancelClicked = ui.button('Cancel###cancelPresetName' .. preset.id, presetRenameCancelButtonSize)
        if cancelClicked then
          presetNameDraft = nil
          presetRenameId = nil
        elseif (saveClicked or submitted) and not nameError then
          renamePreset(preset.id, name)
        elseif nameError then
          ui.textColored(nameError, MODIFIED_PARAM_COLOR)
        end
      else
        presetRowSize:set(showActions
          and rowWidth - presetRenameButtonSize.x - presetDeleteButtonSize.x - presetActionsButtonSize.x
          or showActionsButton and rowWidth - presetActionsButtonSize.x
          or rowWidth, rowHeight)
        ui.pushStyleColor(ui.StyleColor.Header, PRESET_TRANSPARENT_BACKGROUND)
        ui.pushStyleColor(ui.StyleColor.HeaderHovered, PRESET_TRANSPARENT_BACKGROUND)
        ui.pushStyleColor(ui.StyleColor.HeaderActive, PRESET_TRANSPARENT_BACKGROUND)
        if ui.selectable(' ' .. preset.name .. '###' .. preset.id, isSelected, ui.SelectableFlags.None, presetRowSize) then
          presetToSelect = preset.id
        end
        ui.popStyleColor()
        ui.popStyleColor()
        ui.popStyleColor()
        if showActions then
          ui.sameLine(0, 0)
          if ui.button('Rename###renamePreset' .. preset.id, presetRenameButtonSize) then
            presetToRename = preset
            presetActionsId = nil
          end
          ui.sameLine(0, 0)
          if ui.button('Delete###deletePreset' .. preset.id, presetDeleteButtonSize) then
            presetToDelete = preset.id
            presetActionsId = nil
          end
        end
        if showActionsButton then
          ui.sameLine(0, 0)
          if ui.button('…###presetActions' .. preset.id, presetActionsButtonSize) then
            if presetActionsId == preset.id then
              presetActionsId = nil
            else
              presetActionsId = preset.id
            end
          end
        end
      end
    end
    if not anyRowHovered then presetActionsId = nil end
    ui.popStyleVar()
    ui.popStyleVar()
    ui.popStyleVar()
    if modified then ui.popFont() end
    if presetToDelete then ui.closePopup() end
    ui.endCombo()
  else
    presetActionsId = nil
    if presetRenameId ~= nil then
      presetNameDraft = nil
      presetRenameId = nil
      focusPresetName = false
    end
  end
  if modified then ui.popFont() end
  ui.popItemWidth()
  if presetToDelete then
    deletePreset(presetToDelete)
    return
  end
  if presetToRename then
    presetRenameId = presetToRename.id
    presetNameDraft = presetToRename.name
    focusPresetName = true
    return
  end
  if presetToSelect then
    selectPreset(presetToSelect)
    return
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
