Utils = {}

local PREFIX = '^5[WhitelistAI]^7 '

function Utils.info(msg)
    print(PREFIX .. msg)
end

function Utils.warn(msg)
    print(PREFIX .. '^3' .. msg .. '^7')
end

function Utils.error(msg)
    print(PREFIX .. '^1' .. msg .. '^7')
end

function Utils.debug(msg)
    if Config.Debug then
        print(PREFIX .. '^8' .. msg .. '^7')
    end
end

-- Access codes: 8 characters, no ambiguous ones (0/O, 1/I). Players may type
-- them in lowercase, with spaces or dashes.
local CODE_LENGTH = 8
local CODE_PATTERN = '^[2-9A-HJ-NP-Z]+$'

function Utils.normalizeCode(raw)
    if type(raw) ~= 'string' or #raw > 32 then
        return nil
    end
    local code = raw:upper():gsub('[%s%-]', '')
    if #code ~= CODE_LENGTH or not code:match(CODE_PATTERN) then
        return nil
    end
    return code
end

-- Rockstar license of a connecting player (always present unless sv_lan is on).
function Utils.getLicense(src)
    local license = GetPlayerIdentifierByType(src, 'license')
    if type(license) == 'string' and license:match('^license:%x+$') then
        return license
    end
    return nil
end

-- Player names are free text: keep them short and printable before sending them.
function Utils.cleanName(name)
    if type(name) ~= 'string' then
        return ''
    end
    name = name:gsub('[%c]', ''):gsub('%^%d', '')
    return name:sub(1, 64)
end

function Utils.isHttpsUrl(url)
    return type(url) == 'string' and url:match('^https://[%w%.%-]+[:/]?') ~= nil and #url <= 512
end

-- API base URL: https only, except for a local test backend.
function Utils.isAllowedApiUrl(url)
    if Utils.isHttpsUrl(url) then
        return true
    end
    return type(url) == 'string'
        and (url:match('^http://localhost[:/]') or url:match('^http://127%.0%.0%.1[:/]')) ~= nil
end

-- Sliding-window counter, keyed by license (code attempts per player).
local attempts = {}
local WINDOW_MS = 10 * 60 * 1000

function Utils.registerAttempt(key)
    local now = GetGameTimer()
    local list = attempts[key] or {}
    local kept = {}
    for _, t in ipairs(list) do
        if now - t < WINDOW_MS then
            kept[#kept + 1] = t
        end
    end
    kept[#kept + 1] = now
    attempts[key] = kept
    return #kept
end

function Utils.attemptCount(key)
    local now = GetGameTimer()
    local count = 0
    for _, t in ipairs(attempts[key] or {}) do
        if now - t < WINDOW_MS then
            count = count + 1
        end
    end
    return count
end

-- Forget old entries so the table does not grow forever.
CreateThread(function()
    while true do
        Wait(WINDOW_MS)
        for key in pairs(attempts) do
            if Utils.attemptCount(key) == 0 then
                attempts[key] = nil
            end
        end
    end
end)

-- "1.10.0" > "1.9.2": compares dotted numeric versions; anything malformed is never newer.
function Utils.isNewerVersion(candidate, current)
    if type(candidate) ~= 'string' or not candidate:match('^%d+%.%d+%.%d+$') then
        return false
    end
    local a, b = {}, {}
    for n in candidate:gmatch('%d+') do a[#a + 1] = tonumber(n) end
    for n in tostring(current):gmatch('%d+') do b[#b + 1] = tonumber(n) end
    for i = 1, 3 do
        if (a[i] or 0) ~= (b[i] or 0) then
            return (a[i] or 0) > (b[i] or 0)
        end
    end
    return false
end
