-- Local list of recently accepted players, only used when WhitelistAI is unreachable,
-- so an outage does not lock the regulars out. It never grants access on its own
-- while the API answers.
Cache = {}

local RESOURCE = GetCurrentResourceName()
local FILE = 'whitelist_cache.json'
local entries = {}
local dirty = false

local function ttl()
    return math.max(1, tonumber(Config.CacheDays) or 7) * 86400
end

function Cache.load()
    local raw = LoadResourceFile(RESOURCE, FILE)
    if not raw or raw == '' then
        return
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        Utils.warn('Cache local illisible, il sera recréé.')
        return
    end
    local now = os.time()
    for license, expires in pairs(data) do
        if type(license) == 'string' and license:match('^license:%x+$')
            and type(expires) == 'number' and expires > now then
            entries[license] = expires
        end
    end
end

function Cache.allow(license)
    entries[license] = os.time() + ttl()
    dirty = true
end

function Cache.forget(license)
    if entries[license] then
        entries[license] = nil
        dirty = true
    end
end

function Cache.has(license)
    local expires = entries[license]
    return expires ~= nil and expires > os.time()
end

local function save()
    if not dirty then
        return
    end
    local now = os.time()
    for license, expires in pairs(entries) do
        if expires <= now then
            entries[license] = nil
        end
    end
    SaveResourceFile(RESOURCE, FILE, json.encode(entries), -1)
    dirty = false
end

-- Written at most once a minute, and when the resource stops.
CreateThread(function()
    while true do
        Wait(60000)
        save()
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE then
        save()
    end
end)
