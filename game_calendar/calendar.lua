local config = {
    fetchCalendar = true,
    apiUri = "https://wiki.rookgaard.pl/api/calendar",
    visibleMonths = 3,
    customCalendarFile = '/calendar/customCalendar.json'
}

local window = nil
local calendarButton = nil
local selectedDate = os.date("*t") -- current visible month
local currentDate = os.date("*t")
local calendarEvents = {}
local customCalendarLoaded = false

if (not g_resources.directoryExists("/calendar/")) then
    g_resources.makeDir("/calendar/")

    if (not g_resources.fileExists(config.customCalendarFile)) then
        g_resources.writeFileContents(config.customCalendarFile, "[]")
    end
end

function init()
    window = g_ui.displayUI("calendar")
    window:setVisible(false)
    calendarButton = modules.client_topmenu.addRightGameToggleButton('calendarButton', tr('Calendar'), '/images/topbuttons/calendar_window', toggleWindow, false, 10)
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if (window) then
        window:destroy()
        window = nil
    end

    if (calendarButton) then
        calendarButton:destroy()
        calendarButton = nil
    end

    calendarEvents = {}
end

function onGameEnd()
    if (calendarButton) then
        calendarButton:hide()
    end
    if (window) then
        window:hide()
    end
end

function onGameStart()
    calendarButton:setOn(false)
    calendarButton:show()
end

local function checkCalendarDayIfExist(year, month, day)
    if (not calendarEvents[year]) then
        calendarEvents[year] = {}
    end

    if (not calendarEvents[year][month]) then
        calendarEvents[year][month] = {}
    end

    if (not calendarEvents[year][month][day]) then
        calendarEvents[year][month][day] = {}
    end
end

local function convertToTimestamp(date)
    local pattern = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
    local runyear, runmonth, runday, runhour, runminute, runseconds = date:match(pattern)

    if (tonumber(runyear) < 2) then
        runyear = currentDate.year + tonumber(runyear)
    end

    return os.time({
        year = runyear,
        month = runmonth,
        day = runday,
        hour = runhour,
        min = runminute,
        sec = runseconds
    })
end

function parseResponse(data)
    if (not data or data == nil) then
        return
    end

    for _, values in pairs(data) do
        local fromDate = convertToTimestamp(values.fromDate)
        local toDate = values.toDate and convertToTimestamp(values.toDate) or fromDate
        for v = fromDate, toDate, 24 * 60 * 60 do
            local date = os.date('*t', v)
            checkCalendarDayIfExist(date.year, date.month, date.day)
            table.insert(
                calendarEvents[date.year][date.month][date.day],
                {
                    name = values.name,
                    color = values.color
                }
            )
        end
    end

    buildMonth(0)
end

local function getMonthDays(year, month)
    local dateTable = { year = year, month = month + 1, day = 1, hour = 0 }
    local monthInfo = os.date("*t", os.time(dateTable))
    monthInfo.day = monthInfo.day - 1
    return os.date("*t", os.time(monthInfo))
end

local function createEvent(day, name, color, isOld)
    local event = g_ui.createWidget('CalendarEvent', day)
    event:setId(day.calendarDayName:getText() .. '-' .. name)
    event.calendarEventName:setText(name)
    if (color) then
        event:setImageColor(color)
    end
    if (isOld and day:getOpacity() == 1) then
        event:setOpacity(0.5)
    end
end

local function getTimestamp(year, month, day)
    return os.time({ year = year, month = month, day = day })
end

local function addEventForDay(dayUI, year, month, day)
    if (calendarEvents[year]) then
        if (calendarEvents[year][month]) then
            local eventData = calendarEvents[year][month][day]
            if (eventData) then
                for _, data in pairs(eventData) do
                    local timestamp = getTimestamp(year, month, day)
                    local current = getTimestamp(currentDate.year, currentDate.month, currentDate.day)
                    createEvent(dayUI, data.name, data.color, timestamp < current)
                end
            end
        end
    end
end

function buildMonth(value)
    if (value ~= 0) then
        selectedDate.month = selectedDate.month + value
    else
        selectedDate = os.date('*t')
    end

    if (selectedDate.month < 1) then
        selectedDate.year = selectedDate.year - 1
        selectedDate.month = 12
    end

    if (selectedDate.month > 12) then
        selectedDate.year = selectedDate.year + 1
        selectedDate.month = 1
    end

    window.selectionList:destroyChildren()

    local previousMonth = getMonthDays(selectedDate.year, selectedDate.month - 1)
    local previousMonthName = os.date("%b", os.time(previousMonth))
    local isMonday = false
    for i = previousMonth.day - 6, previousMonth.day do
        local day = os.time({
            year = previousMonth.year, month = previousMonth.month, day = i
        })
        if (tonumber(os.date('%w', day)) == 1) then
            isMonday = true
        end

        if (isMonday) then
            local day = g_ui.createWidget("CalendarDay", window.selectionList)
            day:setId('prev' .. i)
            day.calendarDayName:setText(i .. ' ' .. previousMonthName .. (previousMonth.year ~= currentDate.year and ' ' .. previousMonth.year or ''))
            day:setOpacity(0.5)

            addEventForDay(day, previousMonth.year, previousMonth.month, i)
        end
    end
    if (previousMonth.year == currentDate.year and previousMonth.month < currentDate.month) then
        window.previousMonth:disable()
        window.previousMonth.previousMonthLabel:setImageClip(torect("0 0 12 21"))
    else
        window.previousMonth:enable()
        window.previousMonth.previousMonthLabel:setImageClip(torect("0 42 12 21"))
    end

    local currentMonth = getMonthDays(selectedDate.year, selectedDate.month)
    local currentMonthName = os.date("%b", os.time(currentMonth))
    local lastDayOfWeek = 0
    for i = 1, currentMonth.day do
        local day = g_ui.createWidget("CalendarDay", window.selectionList)
        day:setId(i)
        day.calendarDayName:setText(i .. ' ' .. currentMonthName .. (currentMonth.year ~= currentDate.year and ' ' .. currentMonth.year or ''))
        if (i == currentDate.day and currentMonth.month == currentDate.month and currentMonth.year == currentDate.year) then
            day.calendarDayNameContainer:setImageColor('#ff4444')
            day:setBorderColor('#810000')
        end

        addEventForDay(day, currentMonth.year, currentMonth.month, i)

        if (i == currentMonth.day) then
            lastDayOfWeek = tonumber(os.date('%w', os.time(currentMonth)))
        end
    end

    local nextMonth = getMonthDays(selectedDate.year, selectedDate.month + 1)
    local nextMonthName = os.date("%b", os.time(nextMonth))
    for i = 1, (7 - lastDayOfWeek) do
        local day = g_ui.createWidget("CalendarDay", window.selectionList)
        day:setId('next' .. i)
        day.calendarDayName:setText(i .. ' ' .. nextMonthName .. (nextMonth.year ~= currentDate.year and ' ' .. nextMonth.year or ''))
        day:setOpacity(0.5)
        addEventForDay(day, nextMonth.year, nextMonth.month, i)
    end

    local maxVisible = os.time(
        os.date(
        '*t',
        os.time({
            year = currentDate.year,
            month = currentDate.month + config.visibleMonths + 1,
            day = 1
        }))
    )
    if (os.time(nextMonth) >= maxVisible) then
        window.nextMonth:disable()
        window.nextMonth.nextMonthLabel:setImageClip(torect("12 0 12 21"))
    else
        window.nextMonth:enable()
        window.nextMonth.nextMonthLabel:setImageClip(torect("12 42 12 21"))
    end
end

local function loadCustomCalendar()
    if (g_resources.fileExists(config.customCalendarFile) and not customCalendarLoaded) then
        local status, result = pcall(function() 
            return json.decode(g_resources.readFileContents(config.customCalendarFile)) 
        end)
        if not status then
            return onError("Error while reading config file (" .. config.customCalendarFile .. "). To fix this problem you can delete customCalendar.json. Details: " .. result)
        end
        parseResponse(result)
        customCalendarLoaded = true
    end
end

function toggleWindow()
    if (not g_game.isOnline()) then
        return
    end

    if calendarButton:isOn() then
        window:setVisible(false)
        calendarButton:setOn(false)
    else
        if (table.size(calendarEvents) == 0 and config.fetchCalendar) then
            HTTP.getJSON(config.apiUri, parseResponse);
        else
            buildMonth(0)
        end
        loadCustomCalendar()
        window:setVisible(true)
        calendarButton:setOn(true)
    end
end
