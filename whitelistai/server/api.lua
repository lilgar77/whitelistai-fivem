Api = {}

local VERSION = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0'
Api.VERSION = VERSION
local KEY_PATTERN = '^wai_[%w_%-]+$'

local apiKey = nil
local baseUrl = nil

-- Reads the key and URL from the server.cfg. Returns false (and says why) if
-- they are unusable; the key itself is never printed.
function Api.configure()
    local key = GetConvar('whitelistai_key', '')
    if key == '' then
        Utils.error('Clé API manquante : ajoute `set whitelistai_key "wai_..."` dans ton server.cfg.')
        return false
    end
    if #key < 36 or #key > 128 or not key:match(KEY_PATTERN) then
        Utils.error('Clé API invalide : copie-la à nouveau depuis ton espace WhitelistAI.')
        return false
    end

    local url = GetConvar('whitelistai_api_url', Config.ApiUrl):gsub('/+$', '')
    if not Utils.isAllowedApiUrl(url) then
        Utils.error('whitelistai_api_url doit commencer par https://')
        return false
    end

    apiKey = key
    baseUrl = url
    return true
end

-- One JSON request. Always returns { status = <http code, 0 if unreachable>, data = <table|nil> }.
-- PerformHttpRequest has no timeout of its own, so we race it against a timer.
local function request(method, path, body)
    local p = promise.new()
    local settled = false

    local headers = {
        ['Authorization'] = 'Bearer ' .. apiKey,
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json',
        ['User-Agent'] = 'whitelistai-fivem/' .. VERSION,
    }

    PerformHttpRequest(baseUrl .. path, function(status, text)
        if settled then
            return
        end
        settled = true
        local data = nil
        if type(text) == 'string' and text ~= '' and #text < 65536 then
            local ok, decoded = pcall(json.decode, text)
            if ok and type(decoded) == 'table' then
                data = decoded
            end
        end
        p:resolve({ status = tonumber(status) or 0, data = data })
    end, method, body and json.encode(body) or '', headers)

    SetTimeout(Config.RequestTimeout, function()
        if not settled then
            settled = true
            p:resolve({ status = 0, data = nil })
        end
    end)

    return Citizen.Await(p)
end

local function errorCode(res)
    local detail = res.data and res.data.detail
    return type(detail) == 'string' and detail or nil
end

-- Tells WhitelistAI the resource is installed (shown as "connected" on the dashboard).
function Api.hello()
    return request('POST', '/fivem/hello', {
        resource_version = VERSION,
        hostname = Utils.cleanName(GetConvar('sv_hostname', '')),
    })
end

-- Result: { kind = 'allowed' | 'unlinked' | 'revoked' | 'rate_limited' | 'unavailable', applyUrl = ... }
function Api.check(license, name)
    local res = request('POST', '/fivem/check', { license = license, name = name })

    if res.status == 200 and res.data then
        local status = res.data.status
        local applyUrl = Utils.isHttpsUrl(res.data.apply_url) and res.data.apply_url or nil
        if status == 'allowed' or status == 'unlinked' or status == 'revoked' then
            return { kind = status, applyUrl = applyUrl }
        end
    elseif res.status == 429 then
        return { kind = 'rate_limited' }
    elseif res.status == 401 or res.status == 403 then
        Utils.error('WhitelistAI refuse la clé API (régénérée ou serveur supprimé ?).')
    elseif res.status ~= 0 then
        Utils.warn(('Réponse inattendue de WhitelistAI (HTTP %d).'):format(res.status))
    end
    return { kind = 'unavailable' }
end

-- Result: { kind = 'allowed' | 'invalid' | 'used' | 'rate_limited' | 'unavailable' }
function Api.redeem(license, code, name)
    local res = request('POST', '/fivem/redeem', { license = license, code = code, name = name })

    if res.status == 200 and res.data and res.data.status == 'allowed' then
        return { kind = 'allowed' }
    elseif res.status == 404 or (res.status == 400 and errorCode(res) == 'invalid_code') then
        return { kind = 'invalid' }
    elseif res.status == 409 then
        return { kind = 'used' }
    elseif res.status == 429 then
        return { kind = 'rate_limited' }
    elseif res.status == 401 or res.status == 403 then
        Utils.error('WhitelistAI refuse la clé API (régénérée ou serveur supprimé ?).')
    end
    return { kind = 'unavailable' }
end
