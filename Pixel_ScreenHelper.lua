script_name('Pixel Screen Helper')
script_author('Nikita Valeyev')
script_version('1.0.0')

-- =========================
-- Подключаемые библиотеки
-- =========================
local imgui = require 'mimgui'
local encoding = require 'encoding'
local json = require 'dkjson'
local render = require 'lib.render'
local inicfg = require 'inicfg'
local lfs = require 'lfs'
local ffi = require "ffi"

-- Для воспроизведения звуков, аудио
ffi.cdef[[
    int PlaySoundA(const char *pszSound, void* hmod, unsigned int fdwSound);
]]

local winmm = ffi.load("winmm")
local SND_ASYNC    = 0x0001
local SND_FILENAME = 0x00020000

require 'lib.moonloader'
require 'lib.sampfuncs'
require 'vkeys'
local vkeys = require 'vkeys'
local sampev = require 'lib.samp.events'

encoding.default = 'CP1251'
u8 = encoding.UTF8

-- Пользовательские + данные
local authorName = "Nikita Valeyev"
local lastdateUpdate = "16.09.2026"
local nickname = "Not found"

-- =========================
-- Переменные
-- =========================

-- Окна
local window = {
	mainMenu = imgui.new.bool(false)
}

-- Навигация
local selectedTab = 1 -- 1: Статистика, 2: Настройки и т.д.

-- Иконки
local Icons = {
    logo = nil
}

-- Таблица статистики
local statsData = {
    total = 0,
    time_used = 0,
    time_not_used = 0,
    flash_used = 0,
    bodycam_clicks = 0,
    sounds = {},
    history = {},
    lastUpdate = "Не определено"
}

-- Статистика за текущую сессию
local sessionScreenshots = 0

-- Таблица с итоговыми значениями статистики для вывода в UI
local calculatedStats = {
    today = 0,
    week = 0,
    month = 0,
    year = 0,
    total = 0,
    session = 0,
    time_used = 0,
    time_not_used = 0,
    flash_used = 0,
    bodycam_clicks = 0,
    favoriteSound = "Не определено",
    lastUpdate = "Никогда"
}

-- Переменные оверлея уведомлений
local ovlPushM = {
    -- Состояние и данные
    active = false,
    text = "",
    timer = 0,
    duration = 9999,
    alpha = 0,
	
	queue = {}, -- Очередь уведомлений
	
	-- Шрифты, размеры и цвета
    fontSize = 14,
    font = renderCreateFont('Arial', 14, 5),
    
    colors = {
        default = 0xFFFFFFFF,
        yellow  = 0xFFFFD200
    },
	
	-- Конфигурация типов (звуки, акцентные цвета и т.д.)
    types = {
        success = {
            sound = getWorkingDirectory() .. "\\config\\pixel_screenhelper\\sound\\success.wav",
            accentColor = 0xFF2ECC71 -- Зеленый
        },
        warning = {
            sound = getWorkingDirectory() .. "\\config\\pixel_screenhelper\\sound\\warning.wav",
            accentColor = 0xFFF1C40F -- Желтый
        },
        error = {
            sound = getWorkingDirectory() .. "\\config\\pixel_screenhelper\\sound\\error.wav",
            accentColor = 0xE74C3C -- Красный
        },
        info = {
            sound = nil,
            accentColor = 0xFF3498DB -- Синий
        }
    },
	
    -- Режим редактирования позиции
    editPos = false,
    isDragging = false,
    dragOffset = { x = 0, y = 0 },
	
	-- Расположение и размеры
    pos = { x = 20, y = 20 },
    padding = 10,
    radius = 12
}

-- Переменные настроек
local settings = {
    hotkeys = {
        mainMenu = 0x72, -- F3
		bodyCamera  = 0x22, -- PageDown
    },
    overlayPushM = true,
    overlayPushMSound = true,
    overlayPushMPos = { x = 20, y = 20 },
	bodycamState = false,
	autoTime = { enabled = true }, -- Автоматический /time
    flash    = { enabled = true, duration = 0.3, border = 10, color = {1.0, 1.0, 1.0} }, -- Вспышка
	selectedSoundIndex = 0,
	pushSound = true
}

-- Mimgui-переменные
local cfg = {
    overlayPushM      = imgui.new.bool(true),
    overlayPushMSound = imgui.new.bool(true),
	autoTimeEnabled   = imgui.new.bool(true),
    flashEnabled      = imgui.new.bool(true),
    flashDuration     = imgui.new.float(0.3),
    flashBorder       = imgui.new.int(10),
	selectedSoundIndex = imgui.new.int(0),
	pushSound         = imgui.new.bool(true),
}

-- Работа эффекта вспышки в реальном времени
local flashState = {
    alpha = 0.0,
    active = false
}

-- Активация вспышки при сделанном скриншоте
local function triggerFlash()
    if settings.flash.enabled then
        flashState.alpha = 1.0
        flashState.active = true
    end
end

-- Таблица звуков при сделанном скриншоте
local soundFiles = {
    getWorkingDirectory() .. "\\config\\pixel_screenhelper\\sound\\notify.wav",
    getWorkingDirectory() .. "\\config\\pixel_screenhelper\\sound\\notify2.wav",
    getWorkingDirectory() .. "\\config\\pixel_screenhelper\\sound\\notify3.wav",
}
local soundNames = { "Обычный", "Классический", "Премиум" }

-- ===================================
-- Функции скрипта
-- Тут находится основа, ядро работы
-- Разработчик: Nikita Valeyev
-- ===================================

-- ==============================
-- Функция форматирования и ввода
-- ==============================

-- Функция для форматирования числа с разделителями тысяч
local function formatNumber(num)
    local s = tostring(num)
    local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return u8(formatted)
end

-- Преобразование кода клавиши в понятное название
local function keyToName(key)
    if not key or type(key) ~= "number" or key == 0 then return "Не выбрано" end
    
    local names = {
        [0x01] = "LMB", [0x02] = "RMB", [0x04] = "MMB",
        [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter",
        [0x10] = "Shift", [0x11] = "Ctrl", [0x12] = "Alt",
        [0x13] = "Pause", [0x14] = "CapsLock", [0x1B] = "Esc", [0x20] = "Space",
        [0x21] = "PageUp", [0x22] = "PageDown", [0x23] = "End", [0x24] = "Home",
        [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
        [0x2C] = "PrintScreen", [0x2D] = "Insert", [0x2E] = "Delete", [0x91] = "ScrollLock",
        [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4", [0x74] = "F5",
        [0x76] = "F7", [0x77] = "F8", [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",
    }

    if key >= 0x41 and key <= 0x5A then return string.char(key) end -- A-Z
    if key >= 0x30 and key <= 0x39 then return string.char(key) end -- 0-9
    if key >= 0x60 and key <= 0x69 then return "Num " .. tostring(key - 0x60) end -- NumPad

    if names[key] then return names[key] end
    return "VK_" .. tostring(key)
end

-- Функция расчёта периодов (24ч, 7д, месяц, год)
local function updateStatsData()
    calculatedStats.total = statsData.total or 0
    calculatedStats.session = sessionScreenshots
    calculatedStats.time_used = statsData.time_used or 0
    calculatedStats.time_not_used = statsData.time_not_used or 0
    calculatedStats.flash_used = statsData.flash_used or 0
    calculatedStats.bodycam_clicks = statsData.bodycam_clicks or 0
    calculatedStats.lastUpdate = statsData.lastUpdate or "Не определено"

    -- Расчет временных периодов на основе истории
    local now = os.time()
    local todayCount, weekCount, monthCount, yearCount = 0, 0, 0, 0

    if statsData.history then
        for dateStr, count in pairs(statsData.history) do
            local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
            if y and m and d then
                local recTime = os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12})
                local diffDays = math.floor((now - recTime) / 86400)

                if diffDays < 1 then todayCount = todayCount + count end
                if diffDays < 7 then weekCount = weekCount + count end
                if diffDays < 30 then monthCount = monthCount + count end
                if diffDays < 365 then yearCount = yearCount + count end
            end
        end
    end

    calculatedStats.today = todayCount
    calculatedStats.week = weekCount
    calculatedStats.month = monthCount
    calculatedStats.year = yearCount

    -- Определение любимого звука
    local maxSoundClicks = 0
    local favSoundIdx = nil
    if statsData.sounds then
        for soundIdxStr, clicks in pairs(statsData.sounds) do
            if clicks > maxSoundClicks then
                maxSoundClicks = clicks
                favSoundIdx = tonumber(soundIdxStr)
            end
        end
    end

    if favSoundIdx and soundNames and soundNames[favSoundIdx] then
        calculatedStats.favoriteSound = u8(soundNames[favSoundIdx])
    else
        calculatedStats.favoriteSound = u8"Нет данных"
    end
end

-- =========================
-- UI стили
-- =========================

-- Цветовая палитра
local bgMatte      = imgui.ImVec4(0.05, 0.05, 0.05, 1.00)
local cardBg       = imgui.ImVec4(0.08, 0.08, 0.08, 1.00)
local borderClr    = imgui.ImVec4(0.13, 0.13, 0.13, 1.00)
local separatorClr = imgui.ImVec4(0.13, 0.13, 0.13, 1.00)

-- Цвета для кнопок
local purpleNormal  = imgui.ImVec4(0.53, 0.00, 0.98, 1.00)
local purpleHovered = imgui.ImVec4(0.62, 0.15, 1.00, 1.00)
local purpleActive  = imgui.ImVec4(0.45, 0.00, 0.85, 1.00)

imgui.OnInitialize(function()
    local style = imgui.GetStyle()

    style.WindowRounding    = 12.0
    style.FrameRounding     = 10.0
    style.ChildRounding     = 10.0
    style.GrabRounding      = 10.0
    style.PopupRounding     = 10.0
    style.ScrollbarRounding = 8.0
    style.WindowBorderSize  = 1.0
    style.ChildBorderSize   = 1.0
    style.WindowPadding     = imgui.ImVec2(12, 12)
    style.ItemSpacing       = imgui.ImVec2(8, 8)

    -- Применяем палитру к стилям
    style.Colors[imgui.Col.WindowBg]         = bgMatte
    style.Colors[imgui.Col.ChildBg]          = cardBg
    style.Colors[imgui.Col.Border]           = borderClr
    style.Colors[imgui.Col.Separator]        = separatorClr

    style.Colors[imgui.Col.TitleBg]          = cardBg
    style.Colors[imgui.Col.TitleBgActive]    = cardBg
    style.Colors[imgui.Col.TitleBgCollapsed] = cardBg

    -- Текстура логотипа
    Icons.logo = imgui.CreateTextureFromFile("moonloader\\config\\pixel_screenhelper\\img\\psh_logo.png")
end)

-- Цветовые для UI
local textColor    = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
local gray1        = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)
local green1       = imgui.ImVec4(0.20, 0.85, 0.35, 1.00)
local red1         = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
local yellow1      = imgui.ImVec4(1.0, 0.85, 0.25, 1.0)
local purple1      = imgui.ImVec4(0.47, 0.25, 1.0, 1.0)

-- Кастомная кнопка
local function ButtonWithStyle(label, width, height, colorNormal, colorHovered, colorActive)
    imgui.PushStyleColor(imgui.Col.Button, colorNormal)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, colorHovered)
    imgui.PushStyleColor(imgui.Col.ButtonActive, colorActive)

    local clicked = imgui.Button(label, imgui.ImVec2(width, height))

    imgui.PopStyleColor(3)

    return clicked
end

-- Переключатель / Тоггл / Чекбокс (Кастомный стиль)
-- Хранение состояния анимации кружка для каждого тоггла (относительная позиция: 0 = выключено, 1 = включено)
local toggleAnimationProgress = {}
function ToggleSwitch(id, state)
    local drawList = imgui.GetWindowDrawList()
    local pos = imgui.GetCursorScreenPos()

    local height = 22
    local width = height * 1.8
    local radius = height * 0.5

    -- Цвет фона
    local bgColor = state[0]
        and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.2, 0.4, 1.0, 1.0))
        or  imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.2, 0.2, 1.0))

    local knobColor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 1))

    -- Инициализация анимации
    if toggleAnimationProgress[id] == nil then
        toggleAnimationProgress[id] = state[0] and 1 or 0
    end

    -- Анимация
    local target = state[0] and 1 or 0
    toggleAnimationProgress[id] =
        toggleAnimationProgress[id] + (target - toggleAnimationProgress[id]) * 0.2

    drawList:AddRectFilled(pos, imgui.ImVec2(pos.x + width, pos.y + height), bgColor, radius)

    local knobX = pos.x + radius + toggleAnimationProgress[id] * (width - 2 * radius)
    drawList:AddCircleFilled(imgui.ImVec2(knobX, pos.y + radius), radius - 1, knobColor)

    -- Кнопка (ID - Ваджен)
    imgui.InvisibleButton("##" .. id, imgui.ImVec2(width, height))

    if imgui.IsItemClicked() then
        state[0] = not state[0]
        return true
    end

    return false
end

-- Выпадающий список
local dropdownState = {}
function StyledDropdown(id, label, items, currentIndex, width, enabled)
    if enabled == nil then enabled = true end
    if not items or #items == 0 then return false end
    
    width = width or 140
    dropdownState[id] = dropdownState[id] or false
    
    if not enabled then
        dropdownState[id] = false
    end
    
    local opened = dropdownState[id]
    local changed = false
    local buttonHeight = 26
    local io = imgui.GetIO()
    local mouseX, mouseY = io.MousePos.x, io.MousePos.y

    if label ~= "" then
        imgui.TextColored(textColor, label)
        imgui.SameLine()
    end

    local min = imgui.GetCursorScreenPos()
    local max = imgui.ImVec2(min.x + width, min.y + buttonHeight)
    imgui.Dummy(imgui.ImVec2(width, buttonHeight))
    
    local hovered = enabled and (mouseX >= min.x and mouseX <= max.x and mouseY >= min.y and mouseY <= max.y)
    local draw = imgui.GetWindowDrawList()
    local bgColor = hovered and imgui.ImVec4(0.15, 0.15, 0.16, 1.0) or imgui.ImVec4(0.10, 0.10, 0.12, 1.0)

    draw:AddRectFilled(min, max, imgui.ColorConvertFloat4ToU32(bgColor), 6)
    
    local currentText = u8(tostring(items[currentIndex[0] + 1] or "Выберите..."))
    local textPos = imgui.ImVec2(min.x + 8, min.y + (buttonHeight - imgui.GetTextLineHeight()) / 2)
    draw:AddText(textPos, imgui.ColorConvertFloat4ToU32(textColor), currentText)

    local arrowSize = 6
    local arrowCenterX = max.x - 15
    local arrowCenterY = min.y + buttonHeight / 2
    local arrowColor = imgui.ColorConvertFloat4ToU32(gray1)

    if opened then
        draw:AddTriangleFilled(
            imgui.ImVec2(arrowCenterX - arrowSize, arrowCenterY + arrowSize/2),
            imgui.ImVec2(arrowCenterX + arrowSize, arrowCenterY + arrowSize/2),
            imgui.ImVec2(arrowCenterX, arrowCenterY - arrowSize/2),
            arrowColor
        )
    else
        draw:AddTriangleFilled(
            imgui.ImVec2(arrowCenterX - arrowSize, arrowCenterY - arrowSize/2),
            imgui.ImVec2(arrowCenterX + arrowSize, arrowCenterY - arrowSize/2),
            imgui.ImVec2(arrowCenterX, arrowCenterY + arrowSize/2),
            arrowColor
        )
    end

    if enabled and hovered and imgui.IsMouseClicked(0) then
        dropdownState[id] = not opened
    end

    if opened and enabled then
        local foreDraw = imgui.GetForegroundDrawList()
        local listMin = imgui.ImVec2(min.x, max.y + 2)
        local listMax = imgui.ImVec2(min.x + width, max.y + 2 + #items * 24)
        
        foreDraw:AddRectFilled(listMin, listMax, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.07, 0.07, 0.08, 0.98)), 8)
        foreDraw:AddRect(listMin, listMax, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.20, 0.20, 0.22, 1.0)), 8)

        for i, value in ipairs(items) do
            local itemMin = imgui.ImVec2(listMin.x + 2, listMin.y + (i-1)*24 + 2)
            local itemMax = imgui.ImVec2(listMax.x - 2, listMin.y + i*24)
            local itemHovered = mouseX >= itemMin.x and mouseX <= itemMax.x and mouseY >= itemMin.y and mouseY <= itemMax.y
            
            local valText = u8(tostring(value or ""))

            if itemHovered then
                foreDraw:AddRectFilled(itemMin, itemMax, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.53, 0.00, 0.98, 0.85)), 6)
                if imgui.IsMouseClicked(0) then
                    currentIndex[0] = i - 1
                    dropdownState[id] = false
                    changed = true
                end
            end
            foreDraw:AddText(imgui.ImVec2(itemMin.x + 8, itemMin.y + 4), imgui.ColorConvertFloat4ToU32(textColor), valText)
        end

        if imgui.IsMouseClicked(0) and not hovered and not (mouseX >= listMin.x and mouseX <= listMax.x and mouseY >= listMin.y and mouseY <= listMax.y) then
            dropdownState[id] = false
        end
    end

    return changed
end

-- InputField поле ввода
local function InputCustom(width, drawFunc, isDisabled)
    -- Палитра для доступного поля (фиолетовый акцент)
    local col_normal  = imgui.ImVec4(0.18, 0.10, 0.28, 1.00)
    local col_hovered = imgui.ImVec4(0.25, 0.14, 0.38, 1.00)
    local col_active  = imgui.ImVec4(0.22, 0.12, 0.34, 1.00)
    local col_border  = imgui.ImVec4(0.45, 0.20, 0.75, 1.00)

    -- Палитра для недоступного поля (серый фон)
    local disabled_bg     = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
    local disabled_hover  = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    local disabled_active = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
    local disabled_border = imgui.ImVec4(0.18, 0.18, 0.18, 1.00)

    if isDisabled then
        imgui.PushStyleColor(imgui.Col.FrameBg, disabled_bg)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, disabled_hover)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, disabled_active)
        imgui.PushStyleColor(imgui.Col.Border, disabled_border)
        imgui.PushStyleColor(imgui.Col.Text, gray1)
    else
        imgui.PushStyleColor(imgui.Col.FrameBg, col_normal)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, col_hovered)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, col_active)
        imgui.PushStyleColor(imgui.Col.Border, col_border)
        imgui.PushStyleColor(imgui.Col.Text, textColor)
    end

    if width then
        imgui.SetNextItemWidth(width)
    end

    drawFunc()

    imgui.PopStyleColor(5)
end

-- Кнопка для назначения/перезначения клавиш
local function drawKeyInput(target, tooltip)
    tooltip = tooltip or "Нажмите для смены клавиши"
    local BTN_WIDTH  = 110
    local BTN_HEIGHT = 26
    
    local currentKey = settings.hotkeys[target] or 0
    local keyName = keyToName(currentKey)
    
    local names = {
        mainMenu = "Главное окно",
		bodyCamera = "Боди-камера",
    }
    local displayName = names[target] or target

	imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.53, 0.00, 0.98, 1.00))
	imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.62, 0.15, 1.00, 1.00))
	imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.45, 0.00, 0.85, 1.00))

    if imgui.Button(u8(keyName .. "##" .. target), imgui.ImVec2(BTN_WIDTH, BTN_HEIGHT)) then
        waitingKeyInputType = target
        ovlPushM.show("Назначить клавишу для: " .. displayName, 60)
    end

    imgui.PopStyleColor(3)
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8(tooltip))
    end
end

-- Кастомный слайдер
function SliderFloat(label, v, v_min, v_max, format)
    format = format or "%.2f"
    
	imgui.PushStyleVarFloat(imgui.StyleVar.GrabMinSize, 12.0) 
    imgui.PushStyleVarFloat(imgui.StyleVar.GrabRounding, 12.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6.0)
    
    -- Цвета полосы 
	imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.12, 0.12, 0.14, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.16, 0.16, 0.18, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.20, 0.20, 0.22, 1.00))
    
    -- Цвета ползунка
    imgui.PushStyleColor(imgui.Col.SliderGrab, imgui.ImVec4(0.53, 0.00, 0.98, 1.00))
    imgui.PushStyleColor(imgui.Col.SliderGrabActive, imgui.ImVec4(0.62, 0.15, 1.00, 1.00))

    local changed = imgui.SliderFloat(label, v, v_min, v_max, format)

    imgui.PopStyleColor(5)
    imgui.PopStyleVar(2)

    return changed
end

function SliderInt(label, v, v_min, v_max)
    imgui.PushStyleVarFloat(imgui.StyleVar.GrabRounding, 12.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6.0)
    
    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.12, 0.12, 0.14, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.16, 0.16, 0.18, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.20, 0.20, 0.22, 1.00))
    
    imgui.PushStyleColor(imgui.Col.SliderGrab, imgui.ImVec4(0.53, 0.00, 0.98, 1.00))
    imgui.PushStyleColor(imgui.Col.SliderGrabActive, imgui.ImVec4(0.62, 0.15, 1.00, 1.00))

    local changed = imgui.SliderInt(label, v, v_min, v_max)

    imgui.PopStyleColor(5)
    imgui.PopStyleVar(3)

    return changed
end

-- =========================
-- Функции работы с файлами
-- =========================

-- Быстрый доступ к папке скриншотов
local function getDefaultScreensFolder()
    local user = os.getenv("USERPROFILE")
    local arizona = user.."\\Documents\\GTA San Andreas User Files\\SAMP\\arizona\\screens"
    local normal = user.."\\Documents\\GTA San Andreas User Files\\SAMP\\screens"
    if lfs.attributes(arizona) then
        return arizona
    else
        return normal
    end
end

-- Функция для открытия папки со скриншотами в проводнике
local function openScreensFolder()
    local path = getDefaultScreensFolder()
    os.execute('explorer "' .. path .. '"')
    sampAddChatMessage("{9B59B6}[Pixel SH]: {FFFFFF}Папка со скриншотами открыта.", -1)
	ovlPushM.show("success", "Папка со скриншотами открыта.", 3)
end

-- Создание папок
local function getFolderPSH()
    local folder = "moonloader/config/pixel_screenhelper"
    if not lfs.attributes(folder) then
        lfs.mkdir(folder)
    end
    return folder
end

local function getSettingsPath()
    return getFolderPSH().."/"..nickname.."_settings.json"
end

local function getStatsPath()
    return getFolderPSH().."/"..nickname.."_stats.json"
end

-- Сохранение настроек
local function saveSettings()
    local path = getSettingsPath()
    local file = io.open(path, "w")

    if file then
        file:write(json.encode(settings, { indent = true }))
        file:close()
    end
end

-- Загрузка настроек
local function loadSettings()
    local path = getSettingsPath()
    local file = io.open(path, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local data = json.decode(content)
        if data then settings = data end
    else
        saveSettings()
    end
    
	settings.hotkeys = settings.hotkeys or {}
    settings.hotkeys.mainMenu   = settings.hotkeys.mainMenu or 0x72
    settings.hotkeys.bodyCamera = settings.hotkeys.bodyCamera or 0x22
	
    settings.autoTime = settings.autoTime or { enabled = true }
    settings.flash    = settings.flash or { enabled = true, duration = 0.3, border = 10, color = {1.0, 1.0, 1.0} }
	settings.selectedSoundIndex = settings.selectedSoundIndex or 0
    
    -- Синхронизация JSON и ImGui
    cfg.overlayPushM[0]      = (settings.overlayPushM ~= false)
    cfg.overlayPushMSound[0] = (settings.overlayPushMSound ~= false)
    cfg.autoTimeEnabled[0]   = (settings.autoTime.enabled ~= false)
	
    cfg.flashEnabled[0]      = (settings.flash.enabled ~= false)
    cfg.flashDuration[0]     = settings.flash.duration or 0.3
    cfg.flashBorder[0]       = settings.flash.border or 10
	cfg.selectedSoundIndex[0] = settings.selectedSoundIndex or 0
	cfg.pushSound[0]   = (settings.pushSound ~= false)
end

-- Сброс настроек
local function resetSettings()
	settings = {
        hotkeys = {
            mainMenu   = 0x72, -- F3
            bodyCamera = 0x22, -- PageDown
        },
        overlayPushM      = true,
        overlayPushMSound = true,
        overlayPushMPos   = { x = 20, y = 20 },
        bodycamState      = false,
		autoTime = { enabled = true },
        flash    = { enabled = true, duration = 0.3, border = 10, color = {1.0, 1.0, 1.0} },
		selectedSoundIndex = 0,
		pushSound = true
    }
	
	-- Синхронизация imgui-переменных
	cfg.overlayPushM[0]      = true
    cfg.overlayPushMSound[0] = true
    cfg.autoTimeEnabled[0]   = true
    cfg.flashEnabled[0]      = true
    cfg.flashDuration[0]     = 0.3
    cfg.flashBorder[0]       = 10
	cfg.selectedSoundIndex[0] = 0
	cfg.pushSound[0] = true

	-- Режим редактирования (перемещения оверлеев)
	ovlPushM.editPos = false
	ovlPushM.isDragging = false
	
	showCursor(false)
	
    saveSettings()
    sampAddChatMessage("{9B59B6}[Pixel SC]: {FFFFFF}Настройки сброшены к дефолтным значениям.", -1)
end

-- Сохранение статистики
local function saveStats()
    local path = getStatsPath()
    local file = io.open(path, "w+")
    if file then
        statsData.lastUpdate = os.date("%d.%m.%Y %H:%M:%S")
        file:write(encodeJson(statsData))
        file:close()
    end
end

-- Загрузка статистики
local function loadStats()
    local path = getStatsPath()
    if doesFileExist(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local decoded = decodeJson(content)
            if type(decoded) == "table" then
                statsData = decoded
                statsData.sounds = statsData.sounds or {}
                statsData.history = statsData.history or {}
            end
        end
    end
    updateStatsData()
end

-- =========================
-- Вспомогательные функции
-- =========================

-- Проигрывания звука, аудио
local function playNotificationSound(soundPath)
    if soundPath and soundPath ~= "" and doesFileExist(soundPath) then
        winmm.PlaySoundA(soundPath, nil, bit.bor(SND_ASYNC, SND_FILENAME))
    end
end

-- Расчёта размеров текста (Оверлея уведомлений)
function ovlPushM.calcSize(text, lineHeight)
    local maxWidth, lines = 0, 0
    for line in text:gmatch("[^\n]+") do
        local w = renderGetFontDrawTextLength(ovlPushM.font, line)
        if w > maxWidth then maxWidth = w end
        lines = lines + 1
    end
    return maxWidth, lines * lineHeight
end

-- Функция отрисовки цвета строки с тегами (Оверлея уведомлений)
function ovlPushM.drawRichLine(x, y, line, alpha)
    local ax = x
    local a = bit.lshift(math.floor(alpha * 255), 24)
    local color = ovlPushM.colors.default

    for chunk, tag in line:gmatch("([^%[]*)(%b[])") do
        if chunk ~= "" then
            renderFontDrawText(ovlPushM.font, chunk, ax, y, color + a)
            ax = ax + renderGetFontDrawTextLength(ovlPushM.font, chunk)
        end

        if tag == "[y]" then
            color = ovlPushM.colors.yellow
        elseif tag == "[/]" then
            color = ovlPushM.colors.default
        end
    end

    local tail = line:gsub(".*%]", "")
    if tail ~= "" then
        renderFontDrawText(ovlPushM.font, tail, ax, y, color + a)
    end
end

-- Управление отображением (Оверлея уведомлений)
function ovlPushM.show(typeOrText, textOrDuration, duration)
    local nType, nText, nDuration

    if ovlPushM.types[typeOrText] then
        nType = typeOrText
        nText = tostring(textOrDuration or "")
        nDuration = duration or 2.5
    else
        nType = "info"
        nText = tostring(typeOrText or "")
        nDuration = textOrDuration or 2.5
    end

    table.insert(ovlPushM.queue, {
        type = nType,
        text = nText,
        duration = nDuration
    })
end

-- Принудительная очистка оверлея и очереди
function ovlPushM.hide()
    ovlPushM.active = false
    ovlPushM.queue = {}
end

-- Функция фиксации нового скриншота
local function checkScreenshotStats()
    sessionScreenshots = sessionScreenshots + 1
    statsData.total = (statsData.total or 0) + 1

    -- Авто-тайм
    if cfg.autoTimeEnabled[0] then
        statsData.time_used = (statsData.time_used or 0) + 1
    else
        statsData.time_not_used = (statsData.time_not_used or 0) + 1
    end

    -- Вспышка
    if cfg.flashEnabled[0] then
        statsData.flash_used = (statsData.flash_used or 0) + 1
    end

    -- Звук
    if cfg.pushSound[0] then
        local currentIdx = tostring(cfg.selectedSoundIndex[0] + 1)
        statsData.sounds[currentIdx] = (statsData.sounds[currentIdx] or 0) + 1
    end

    -- Запись по датам (YYYY-MM-DD)
    local todayKey = os.date("%Y-%m-%d")
    statsData.history[todayKey] = (statsData.history[todayKey] or 0) + 1

    saveStats()
    updateStatsData()
end

-- Делаем скриншот (с эффектами, настройками)
local function takeTimedScreenshot()
    lua_thread.create(function()
	
		-- Фиксируем скриншот в статистику
		checkScreenshotStats()
		
        -- 1. Тайм перед скриншотом
        if cfg.autoTimeEnabled[0] then
            sampSendChat("/time")
        end

        -- 2. Эффект вспышки
        if cfg.flashEnabled[0] then
            triggerFlash()
        end
		
		-- 3. Уведомление о сохранении скриншота
        if cfg.overlayPushM[0] and ovlPushM then
            ovlPushM.show("Скриншот сохранён! +1", 2)
        end
		
		-- 4. Воспроизведение звука
        if cfg.pushSound[0] then
            local currentIdx = cfg.selectedSoundIndex[0] + 1
            playNotificationSound(soundFiles[currentIdx])
        end
    end)
end

-- =========================
-- Регистрация команд
-- =========================

-- Открытие главного окна
function cmd_smenu()
    window.mainMenu[0] = not window.mainMenu[0]
end

-- Открытие папки скриншотов
function cmd_scheck()
    openScreensFolder()
end

-- Просмотр доступных команд
function cmd_scrhelp()
    local prefix = "{9B59B6}[Pixel SH]: {FFFFFF}"
    sampAddChatMessage(prefix .. "Список всех доступных команд:", -1)
    sampAddChatMessage(prefix .. "{9B59B6}/smenu{FFFFFF} - открыть главное меню", -1)
    sampAddChatMessage(prefix .. "{9B59B6}/scheck{FFFFFF} - открывает папку со скриншотами", -1)
    sampAddChatMessage(prefix .. "{9B59B6}/scrhelp{FFFFFF} - просмотр всех команд", -1)
end

-- =========================
-- Все окна
-- =========================

-- Главное окно
imgui.OnFrame(function() return window.mainMenu[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(680, 420), imgui.Cond.FirstUseEver)
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
	
    imgui.Begin(u8"Pixel Screen Helper", window.mainMenu, flags)
	
        -- Левая часть: Меню
        imgui.BeginChild("Sidebar", imgui.ImVec2(180, 0), true)
            
            -- Блок логотипа и автора
            if Icons.logo then
                imgui.SetCursorPosX((180 - 80) / 2)
                imgui.Image(Icons.logo, imgui.ImVec2(80, 80))
            end
            
            -- Название и автор
            imgui.SetCursorPosX(30)
            imgui.TextColored(textColor, u8" Pixel Screen Helper")
            
            imgui.SetCursorPosX(30)
            imgui.TextColored(gray1, u8"Author: ")
            imgui.SameLine(78)
            imgui.TextColored(yellow1, u8"Nikita Valeyev")
            
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            -- Навигационные кнопки
            if ButtonWithStyle(u8"Статистика", 160, 36, purpleNormal, purpleHovered, purpleActive) then
                selectedTab = 1
            end
            
            if ButtonWithStyle(u8"Настройки", 160, 36, purpleNormal, purpleHovered, purpleActive) then
                selectedTab = 2
            end
            
            if ButtonWithStyle(u8"Открыть папку", 160, 36, purpleNormal, purpleHovered, purpleActive) then
                selectedTab = 3
            end
            
            if ButtonWithStyle(u8"Об авторе", 160, 36, purpleNormal, purpleHovered, purpleActive) then
                selectedTab = 4
            end

        imgui.EndChild()

        imgui.SameLine()

        -- Правая часть: Основной контент
        imgui.BeginChild("ContentArea", imgui.ImVec2(0, 0), true)
            
			if selectedTab == 1 then
                imgui.TextColored(textColor, u8"Статистика")
                imgui.Separator()
                imgui.Spacing()

                -- Карточка 1: Основная статистика по периодам
                imgui.BeginChild("MainStatsCard", imgui.ImVec2(0, 180), true, imgui.WindowFlags.NoScrollbar)
                    imgui.SetCursorPos(imgui.ImVec2(12, 12))
                    imgui.TextColored(purple1, u8"ВАША СТАТИСТИКА")
                    imgui.Spacing()

                    local halfWidth = (imgui.GetWindowWidth() - 36) / 2

                    imgui.BeginGroup()
                        imgui.TextColored(gray1, u8"За последние 24 часа:")
                        imgui.SameLine()
                        imgui.TextColored(textColor, tostring(calculatedStats.today))

                        imgui.Spacing()

                        imgui.TextColored(gray1, u8"За последние 7 дней:")
                        imgui.SameLine()
                        imgui.TextColored(textColor, tostring(calculatedStats.week))

                        imgui.Spacing()

                        imgui.TextColored(gray1, u8"За текущую сессию:")
                        imgui.SameLine()
                        imgui.TextColored(textColor, tostring(calculatedStats.session))
                    imgui.EndGroup()

                    imgui.SameLine(halfWidth + 24)

                    imgui.BeginGroup()
                        imgui.TextColored(gray1, u8"За последний месяц:")
                        imgui.SameLine()
                        imgui.TextColored(textColor, tostring(calculatedStats.month))

                        imgui.Spacing()

                        imgui.TextColored(gray1, u8"За последний год:")
                        imgui.SameLine()
                        imgui.TextColored(textColor, tostring(calculatedStats.year))

                        imgui.Spacing()

                        imgui.TextColored(gray1, u8"Всего сделано:")
                        imgui.SameLine()
                        imgui.TextColored(textColor, tostring(calculatedStats.total))
                    imgui.EndGroup()

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.TextColored(yellow1, u8"Последнее обновление статистики: ")
                    imgui.SameLine()
                    imgui.TextColored(textColor, u8(calculatedStats.lastUpdate))
                imgui.EndChild()

                imgui.Spacing()

                -- Карточка 2: Интересные метрики и эффекты
                imgui.BeginChild("MetricsStatsCard", imgui.ImVec2(0, 160), true, imgui.WindowFlags.NoScrollbar)
                    imgui.SetCursorPos(imgui.ImVec2(12, 12))
                    imgui.TextColored(purple1, u8"ИНТЕРЕСНЫЕ МЕТРИКИ И ЭФФЕКТЫ")
                    imgui.Spacing()

                    imgui.TextColored(gray1, u8"Использование /time:")
                    imgui.SameLine()
                    imgui.TextColored(textColor, string.format(u8"%d с таймом / %d без тайма", calculatedStats.time_used, calculatedStats.time_not_used))

                    imgui.Spacing()

                    imgui.TextColored(gray1, u8"Скриншотов со вспышкой:")
                    imgui.SameLine()
                    imgui.TextColored(textColor, tostring(calculatedStats.flash_used))

                    imgui.Spacing()

                    imgui.TextColored(gray1, u8"Активаций боди-камеры:")
                    imgui.SameLine()
                    imgui.TextColored(textColor, tostring(calculatedStats.bodycam_clicks))

                    imgui.Spacing()

                    imgui.TextColored(gray1, u8"Любимый звук уведомления:")
                    imgui.SameLine()
                    imgui.TextColored(textColor, calculatedStats.favoriteSound)
                imgui.EndChild()
                
			elseif selectedTab == 2 then
				imgui.TextColored(textColor, u8"Визуальные спецэффекты")
				imgui.Separator()
				imgui.Spacing()
				
				-- Карточка 1: Автоматический /time
				imgui.BeginChild("AutoTimeSettingsCard", imgui.ImVec2(0, 75), true, imgui.WindowFlags.NoScrollbar)
					imgui.SetCursorPos(imgui.ImVec2(12, 12))
					imgui.TextColored(purple1, u8"Автоматический /time")
					
					imgui.SameLine(imgui.GetWindowWidth() - 55)
					if ToggleSwitch("autotime_toggle", cfg.autoTimeEnabled) then
						settings.autoTime.enabled = cfg.autoTimeEnabled[0]
						saveSettings()
					end

					imgui.TextColored(gray1, u8"Автоматически отправляет команду /time в чат.")
				imgui.EndChild()
				imgui.Spacing()

				-- Карточка 2: Управление боди-камерой
				imgui.BeginChild("BodycamSettingsCard", imgui.ImVec2(0, 75), true, imgui.WindowFlags.NoScrollbar)
					imgui.SetCursorPos(imgui.ImVec2(12, 12))
					imgui.TextColored(purple1, u8"Управление боди-камерой")

					imgui.SameLine(imgui.GetWindowWidth() - 122)
					drawKeyInput("bodyCamera", "Нажмите для смены клавиши")

					imgui.TextColored(gray1, u8"Включение/отключение системной боди-камеры.")
				imgui.EndChild()
				imgui.Spacing()

				-- Карточка 3: Эффект вспышки
				imgui.BeginChild("FlashSettingsCard", imgui.ImVec2(0, 160), true)
					imgui.SetCursorPos(imgui.ImVec2(12, 12))
					imgui.TextColored(purple1, u8"Вспышка при создании скриншота")
					
					imgui.SameLine(imgui.GetWindowWidth() - 55)
					if ToggleSwitch("flash_toggle", cfg.flashEnabled) then
						settings.flash.enabled = cfg.flashEnabled[0]
						saveSettings()
					end

					imgui.TextColored(gray1, u8"Создает мягкий подсвечивающий градиент по краям экрана.")
					imgui.Spacing()
					imgui.Separator()
					imgui.Spacing()
					
					local isEnabled = cfg.flashEnabled[0]
					
					if not isEnabled then
						imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, imgui.GetStyle().Alpha * 0.4)
					end

					imgui.SetNextItemWidth(180)
					if SliderFloat(u8"Длительность (сек)", cfg.flashDuration, 0.1, 1.0, "%.2f") then
						if isEnabled then
							settings.flash.duration = cfg.flashDuration[0]
							saveSettings()
						else
							cfg.flashDuration[0] = settings.flash.duration
						end
					end

					imgui.SetNextItemWidth(180)
					if SliderInt(u8"Ширина рамки (px)", cfg.flashBorder, 5, 30) then
						if isEnabled then
							settings.flash.border = cfg.flashBorder[0]
							saveSettings()
						else
							cfg.flashBorder[0] = settings.flash.border
						end
					end
					
					imgui.SameLine(imgui.GetWindowWidth() - 80)
					if ButtonWithStyle(u8"Тест", 70, 24, purpleNormal, purpleHovered, purpleActive) then
						if isEnabled then
							triggerFlash()
						end
					end
					
					if not isEnabled then
						imgui.PopStyleVar()
					end

				imgui.EndChild()
				imgui.Spacing()

				-- Карточка 4: Уведомления (оверлей уведомления)
				imgui.BeginChild("OverlaySettingsCard", imgui.ImVec2(0, 110), true)
					imgui.SetCursorPos(imgui.ImVec2(12, 12))
					imgui.TextColored(purple1, u8"Оверлей уведомлений")
					
					imgui.SameLine(imgui.GetWindowWidth() - 55)
					if ToggleSwitch("overlay_toggle", cfg.overlayPushM) then
						settings.overlayPushM = cfg.overlayPushM[0]
						saveSettings()
					end

					imgui.TextColored(gray1, u8"Отображать всплывающее уведомление при сохранении скриншота.")
					imgui.Spacing()

					imgui.TextColored(purple1, u8"Звук уведомления")
					imgui.SameLine(imgui.GetWindowWidth() - 55)
					if ToggleSwitch("overlay_sound_toggle", cfg.overlayPushMSound) then
						settings.overlayPushMSound = cfg.overlayPushMSound[0]
						saveSettings()
					end
				imgui.EndChild()
				imgui.Spacing()

				-- Карточка 5: Звуковое оповещение
				imgui.BeginChild("SoundSettingsCard", imgui.ImVec2(0, 150), true)
					imgui.SetCursorPos(imgui.ImVec2(12, 12))
					imgui.TextColored(purple1, u8"Звуковое оповещение")
					
					imgui.SameLine(imgui.GetWindowWidth() - 55)
					if ToggleSwitch("sound_toggle", cfg.pushSound) then
						settings.pushSound = cfg.pushSound[0]
						saveSettings()
					end

					imgui.TextColored(gray1, u8"Воспроизводить звук при сохранении скриншота.")
					imgui.Spacing()
					imgui.Separator()
					imgui.Spacing()

					-- Проверка состояния тогла
					local isSoundEnabled = cfg.pushSound[0]
					
					if not isSoundEnabled then
						imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, imgui.GetStyle().Alpha * 0.4)
					end

					-- Передаем isSoundEnabled последним аргументом
					if StyledDropdown("sound_select", "", soundNames, cfg.selectedSoundIndex, 160, isSoundEnabled) then
						settings.selectedSoundIndex = cfg.selectedSoundIndex[0]
						saveSettings()
						
						-- Проигрываем звук для предпрослушивания
						local currentIdx = cfg.selectedSoundIndex[0] + 1
						playNotificationSound(soundFiles[currentIdx])
					end

					if not isSoundEnabled then
						imgui.PopStyleVar()
					end

					imgui.TextColored(red1, u8"Внимание: При выборе звука предварительно можно услышать его.")
				imgui.EndChild()
				
				-- Кнопка сброса настроек
				imgui.Spacing()
				imgui.Dummy(imgui.ImVec2(0, 2))
				local btnResetW, btnResetH = 180, 32
				imgui.SetCursorPosX((imgui.GetWindowWidth() - btnResetW) / 2)

				if ButtonWithStyle(
					u8"Сбросить настройки", 
					btnResetW, 
					btnResetH, 
					imgui.ImVec4(120/255, 0/255, 0/255, 1.0),
					imgui.ImVec4(160/255, 0/255, 0/255, 1.0),
					imgui.ImVec4(80/255, 0/255, 0/255, 1.0)
				) then
					if resetSettings then
						resetSettings()
					end
				end
				if imgui.IsItemHovered() then
					imgui.SetTooltip(u8"Сбрасывает настройки к дефолтным значениям.")
				end
                
		elseif selectedTab == 3 then
			imgui.TextColored(textColor, u8"Быстрый доступ")
			imgui.Separator()
			imgui.Spacing()

			if not screensPathBuffer then
				screensPathBuffer = imgui.new.char[512](getDefaultScreensFolder())
			end
			
			imgui.BeginChild("QuickAccessCard", imgui.ImVec2(0, 140), true, imgui.WindowFlags.NoScrollbar)
				imgui.TextColored(purple1, u8"Скриншоты игры")
				imgui.TextColored(gray1, u8"Быстрый переход к папке с сохранёнными кадрами.")
				
				imgui.Spacing()

				InputCustom(-1, function()
					imgui.InputText("##screens_path", screensPathBuffer, 512, imgui.InputTextFlags.ReadOnly)
				end, true)
				
				imgui.Spacing()
				imgui.Separator()

				if ButtonWithStyle(u8"Открыть папку", 120, 24, purpleNormal, purpleHovered, purpleActive) then
					local path = getDefaultScreensFolder()
					os.execute('explorer "' .. path .. '"')
				end
			imgui.EndChild()
                
		elseif selectedTab == 4 then
			imgui.TextColored(textColor, u8"Об авторе")
			imgui.Separator()
			imgui.Spacing()
			
			imgui.BeginChild("AuthorSupportCard", imgui.ImVec2(0, 150), true, imgui.WindowFlags.NoScrollbar)
				imgui.TextColored(purple1, u8"Разработчик:")
				imgui.SameLine()
				imgui.TextColored(yellow1, u8"Nikita Valeyev")
				imgui.TextColored(gray1, u8"Создание скриптов, интерфейсов и утилит для SA-MP / Arizona RP.")
				
				imgui.Spacing()
				imgui.TextWrapped(u8"Pixel Screen Helper - создан для комфортной работы со скриншотами, эффектами и авто-таймом.")
				imgui.Spacing()

				imgui.Separator()

				if ButtonWithStyle(u8"Подробнее", 120, 24, purpleNormal, purpleHovered, purpleActive) then
					os.execute('explorer "https://valeyevboss.github.io/nikitavaleyev.github.io/"')
				end
			imgui.EndChild()
		end
		
        imgui.EndChild()

    imgui.End()
end)

-- =========================
-- Оверлеи
-- =========================

-- Оверлей уведомлений
lua_thread.create(function()
    while true do
        local dt = wait(0) or 0.016

        -- Cледующее сообщение из очереди
        if cfg.overlayPushM[0] and not ovlPushM.active and #ovlPushM.queue > 0 and ovlPushM.alpha <= 0 then
            local nextMsg = table.remove(ovlPushM.queue, 1)
            ovlPushM.text = nextMsg.text
            ovlPushM.type = nextMsg.type or "info"
            ovlPushM.duration = nextMsg.duration
            ovlPushM.timer = 0
            ovlPushM.active = true

            -- Проигрываем звук при появлении
            local typeConfig = ovlPushM.types[ovlPushM.type]
            if typeConfig and typeConfig.sound and (settings.overlayPushMSound ~= false) then
                playNotificationSound(typeConfig.sound)
            end
        end

        -- Анимация альфы и таймер
        if not ovlPushM.active or not cfg.overlayPushM[0] then
            ovlPushM.alpha = math.max(ovlPushM.alpha - dt * 5, 0)
        else
            ovlPushM.timer = ovlPushM.timer + dt
            ovlPushM.alpha = math.min(ovlPushM.alpha + dt * 5, 1)

            if ovlPushM.timer >= ovlPushM.duration then
                ovlPushM.active = false
            end
        end

        -- Позиция
        local posX = settings.overlayPushMPos and settings.overlayPushMPos.x or 20
        local posY = settings.overlayPushMPos and settings.overlayPushMPos.y or 20

        local renderText = ovlPushM.text
        local currentAlpha = ovlPushM.alpha

        if ovlPushM.editPos then
            currentAlpha = 1.0
            if renderText == "" then
                renderText = "Тестовое уведомление\n[y]Вы в режиме редактирования[/]"
            end
        end

        -- Отрисовка
        if currentAlpha > 0 and (cfg.overlayPushM[0] or ovlPushM.editPos) then
            local lineHeight = ovlPushM.fontSize + 8
            local textWidth, textHeight = ovlPushM.calcSize(renderText, lineHeight)
            
            local bgWidth  = textWidth + ovlPushM.padding * 2 + 6
            local bgHeight = textHeight + ovlPushM.padding * 2

            local alphaByte = math.floor(currentAlpha * 0xCC)
            local bgColor = bit.lshift(alphaByte, 24) + 0x000000

            -- 1. Режим редактирования
            if ovlPushM.editPos then
                local mx, my = getCursorPos()
                local mouseDown = isKeyDown(VK_LBUTTON)

                if renderDrawBoxRounded then
                    renderDrawBoxRounded(posX - 2, posY - 2, bgWidth + 4, bgHeight + 4, ovlPushM.radius, 0xFFE01C47)
                else
                    renderDrawBox(posX - 2, posY - 2, bgWidth + 4, bgHeight + 4, 0xFFE01C47)
                end

                if not ovlPushM.isDragging and mouseDown then
                    if mx >= posX and mx <= posX + bgWidth and my >= posY and my <= posY + bgHeight then
                        ovlPushM.isDragging = true
                        ovlPushM.dragOffset.x = mx - posX
                        ovlPushM.dragOffset.y = my - posY
                    end
                end

                if ovlPushM.isDragging then
                    if mouseDown then
                        settings.overlayPushMPos.x = mx - ovlPushM.dragOffset.x
                        settings.overlayPushMPos.y = my - ovlPushM.dragOffset.y
                    else
                        ovlPushM.isDragging = false
                        saveSettings()
                    end
                end

                if isKeyJustPressed(VK_ESCAPE) then
                    ovlPushM.editPos = false
                    ovlPushM.isDragging = false
                    showCursor(false)
                    if ovlPushM.hide then ovlPushM.hide() end
                    saveSettings()
                end
            end

            -- 2. Отрисовка фона
            if renderDrawBoxRounded then
                renderDrawBoxRounded(posX, posY, bgWidth, bgHeight, ovlPushM.radius, bgColor)
            else
                renderDrawBox(posX, posY, bgWidth, bgHeight, bgColor)
            end

            -- 3. Отрисовка вертикальной цветной полоски индикатора типа
            local currentTypeConfig = ovlPushM.types[ovlPushM.type] or ovlPushM.types.info
            local accentAlpha = bit.lshift(math.floor(currentAlpha * 255), 24)
            local accentColor = currentTypeConfig.accentColor + accentAlpha

            if renderDrawBoxRounded then
                renderDrawBoxRounded(posX + 4, posY + 6, 3, bgHeight - 12, 2, accentColor)
            else
                renderDrawBox(posX + 4, posY + 6, 3, bgHeight - 12, accentColor)
            end

            -- 4. Отрисовка текста
            local ty = posY + ovlPushM.padding
            for line in renderText:gmatch("[^\n]+") do
                ovlPushM.drawRichLine(posX + ovlPushM.padding + 6, ty, line, currentAlpha)
                ty = ty + lineHeight
            end
        end
    end
end)

-- =========================
-- Эффекты
-- =========================

-- Рисование градиента
local function drawGradientHorizontal(x1, y1, x2, y2)
    local steps = settings.flash.border
    for i = 0, steps - 1 do
        local alpha = flashState.alpha * (1 - i / steps * 0.9)
        local color = bit.bor(0x00FFFFFF, bit.lshift(math.floor(alpha * 255), 24))
        local h = (y2 - y1) / steps
        renderDrawBox(x1, y1 + i * h, x2, y1 + (i + 1) * h, color)
    end
end

local function drawGradientVertical(x1, y1, x2, y2)
    local steps = settings.flash.border
    for i = 0, steps - 1 do
        local alpha = flashState.alpha * (1 - i / steps * 0.9)
        local color = bit.bor(0x00FFFFFF, bit.lshift(math.floor(alpha * 255), 24))
        local w = (x2 - x1) / steps
        renderDrawBox(x1 + i * w, y1, x1 + (i + 1) * w, y2, color)
    end
end

-- Поток анимации вспышки
lua_thread.create(function()
    while true do
        local dt = wait(0) or 0.016
        if flashState.active then
            flashState.alpha = flashState.alpha - dt / settings.flash.duration
            if flashState.alpha <= 0 then
                flashState.alpha = 0
                flashState.active = false
            end

            local sw, sh = getScreenResolution()
            local b = settings.flash.border

            drawGradientHorizontal(0, 0, sw, b)
            drawGradientHorizontal(0, sh - b, sw, sh)
            drawGradientVertical(0, 0, b, sh)
            drawGradientVertical(sw - b, 0, sw, sh)
        else
            wait(50)
        end
    end
end)

-- =========================
-- Основной цикл
-- =========================
function main()
    repeat wait(0) until isSampAvailable()
    local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result then nickname = sampGetPlayerNickname(id) end
	
	-- Регистрация команд
    sampRegisterChatCommand("smenu", cmd_smenu)
	sampRegisterChatCommand("scheck", cmd_scheck)
	sampRegisterChatCommand("scrhelp", cmd_scrhelp)
	
	-- Загрузка данных из файлов конфигурации
	loadSettings()
	loadStats()

    while true do
        wait(0)
		
		-- Перехват клавиши F8
        if wasKeyPressed(vkeys.VK_F8) and not sampIsChatInputActive() and not sampIsDialogActive() then
            takeTimedScreenshot()
        end
		
		-- Быстрое переключение боди-камеры
        local bodycamKey = settings.hotkeys.bodyCamera
        if bodycamKey and bodycamKey ~= 0 and wasKeyPressed(bodycamKey) and not sampIsChatInputActive() and not sampIsDialogActive() then
            settings.bodycamState = not settings.bodycamState
			
			-- Отправляем в статистику
			statsData.bodycam_clicks = (statsData.bodycam_clicks or 0) + 1
			saveStats()
			updateStatsData()
            
            if settings.bodycamState then
                sampSendChat("/bodycamera")
                if ovlPushM then ovlPushM.show("Боди-камера: Включена", 2) end
            else
                sampSendChat("/offbodycamera")
                if ovlPushM then ovlPushM.show("Боди-камера: Выключена", 2) end
            end
            
            saveSettings()
        end

        -- Если скрипт ожидает нажатия клавиши для её смены
        if waitingKeyInputType then
            for k = 0, 255 do
                if k ~= 0x10 and k ~= 0x11 and k ~= 0x12 and 
                   k ~= 0xA0 and k ~= 0xA1 and k ~= 0xA2 and k ~= 0xA3 and k ~= 0xA4 and k ~= 0xA5 then
                    
                    if wasKeyPressed(k) then
                        local newKey = (k == 0x1B) and 0 or k -- Esc снимает клавишу (ставит 0)

                        if type(waitingKeyInputType) == "string" and settings.hotkeys[waitingKeyInputType] ~= nil then
                            settings.hotkeys[waitingKeyInputType] = newKey
                            saveSettings()
                            sampAddChatMessage("{9B59B6}[Pixel SC]: {35FF35}Клавиша успешно обновлена!", -1)
                            waitingKeyInputType = nil
                            ovlPushM.hide()
                        end
                        break
                    end
                end
            end
        else
            -- Автоматическая проверка открытия окон по горячим клавишам
            for windowName, targetKey in pairs(settings.hotkeys) do
                if targetKey and targetKey ~= 0 and wasKeyPressed(targetKey) then
                    if window[windowName] then
                        window[windowName][0] = not window[windowName][0]
                    end
                end
            end
        end
    end
end

-- =========================
-- Сообщение при запуске
-- =========================
lua_thread.create(function()
    wait(7000)
	sampAddChatMessage(string.format("{9B59B6}[Pixel SC]: {FFFFFF}Автор скрипта: {FFD700}%s", authorName), -1)
	sampAddChatMessage(string.format("{9B59B6}[Pixel SC]: {FFFFFF}Последнее обновление: {FFD700}%s", lastdateUpdate), -1)
    sampAddChatMessage(string.format("{9B59B6}[Pixel SC]: {FFFFFF}Скрипт загружен! %s - меню.", keyToName(settings.hotkeys.mainMenu)), -1)
end)
