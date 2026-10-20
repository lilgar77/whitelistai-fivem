local configured = false
local DOWNLOAD_URL = 'https://github.com/lilgar77/whitelistai-fivem/releases/latest'

-- Card asking for the access code, with a button to the application page.
-- Built as a table and JSON-encoded, so no text can break out of the card.
local function codeCard(applyUrl, errorText)
    local body = {
        { type = 'TextBlock', text = Config.Messages.code_title, size = 'Large', weight = 'Bolder' },
        { type = 'TextBlock', text = Config.Messages.code_text, wrap = true },
    }
    if errorText then
        body[#body + 1] = { type = 'TextBlock', text = errorText, color = 'Attention', wrap = true }
    end
    body[#body + 1] = {
        type = 'Input.Text',
        id = 'code',
        placeholder = Config.Messages.code_placeholder,
        maxLength = 16,
    }

    local actions = {
        { type = 'Action.Submit', title = Config.Messages.code_submit, data = { action = 'redeem' } },
    }
    if applyUrl then
        actions[#actions + 1] = { type = 'Action.OpenUrl', title = Config.Messages.apply_button, url = applyUrl }
    end

    return json.encode({
        type = 'AdaptiveCard',
        version = '1.3',
        ['$schema'] = 'http://adaptivecards.io/schemas/adaptive-card.json',
        body = body,
        actions = actions,
    })
end

-- What to do when WhitelistAI cannot answer (see Config.OfflineMode).
local function offlineDecision(license, deferrals)
    if Config.OfflineMode == 'open' then
        Utils.warn('WhitelistAI injoignable : joueur autorisé (OfflineMode = open).')
        deferrals.done()
    elseif Config.OfflineMode == 'cache' and Cache.has(license) then
        Utils.debug(('%s autorisé depuis le cache local.'):format(license))
        deferrals.done()
    else
        deferrals.done(Config.Messages.unavailable)
    end
end

-- Shows the code card until the player enters a valid code or runs out of attempts.
local function askForCode(license, name, applyUrl, deferrals)
    local busy = false

    local function show(errorText)
        deferrals.presentCard(codeCard(applyUrl, errorText), function(data)
            if busy or type(data) ~= 'table' then
                return
            end
            busy = true

            CreateThread(function()
                if Utils.attemptCount(license) >= Config.MaxCodeAttempts then
                    deferrals.done(Config.Messages.too_many_attempts)
                    return
                end

                local code = Utils.normalizeCode(data.code)
                if not code then
                    busy = false
                    show(Config.Messages.code_format)
                    return
                end

                Utils.registerAttempt(license)
                deferrals.update(Config.Messages.checking)
                local result = Api.redeem(license, code, name)

                if result.kind == 'allowed' then
                    Cache.allow(license)
                    Utils.info(('%s a validé son code d’accès.'):format(name))
                    deferrals.update(Config.Messages.welcome)
                    Wait(1000)
                    deferrals.done()
                elseif result.kind == 'rate_limited' then
                    deferrals.done(Config.Messages.rate_limited)
                elseif result.kind == 'unavailable' then
                    deferrals.done(Config.Messages.unavailable)
                elseif Utils.attemptCount(license) >= Config.MaxCodeAttempts then
                    deferrals.done(Config.Messages.too_many_attempts)
                else
                    busy = false
                    show(result.kind == 'used' and Config.Messages.code_used or Config.Messages.code_invalid)
                end
            end)
        end)
    end

    if Utils.attemptCount(license) >= Config.MaxCodeAttempts then
        deferrals.done(Config.Messages.too_many_attempts)
        return
    end
    show(nil)
end

AddEventHandler('playerConnecting', function(playerName, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update(Config.Messages.checking)

    local license = Utils.getLicense(src)
    if not license then
        deferrals.done(Config.Messages.no_license)
        return
    end

    if IsPlayerAceAllowed(src, Config.BypassAce) then
        Utils.debug(('%s entre grâce à la permission %s.'):format(license, Config.BypassAce))
        deferrals.done()
        return
    end

    if not configured then
        offlineDecision(license, deferrals)
        return
    end

    local name = Utils.cleanName(playerName)
    local result = Api.check(license, name)
    Utils.debug(('%s (%s) : %s'):format(name, license, result.kind))

    if result.kind == 'allowed' then
        Cache.allow(license)
        deferrals.done()
    elseif result.kind == 'revoked' then
        Cache.forget(license)
        deferrals.done(Config.Messages.revoked)
    elseif result.kind == 'unlinked' then
        Cache.forget(license)
        askForCode(license, name, result.applyUrl, deferrals)
    elseif result.kind == 'rate_limited' then
        deferrals.done(Config.Messages.rate_limited)
    else
        offlineDecision(license, deferrals)
    end
end)

CreateThread(function()
    Cache.load()

    if GetConvar('sv_lan', 'false') == 'true' then
        Utils.warn('sv_lan est activé : les comptes Rockstar ne sont pas vérifiés, la whitelist n’est pas fiable.')
    end

    configured = Api.configure()
    if not configured then
        Utils.error('Ressource désactivée tant que la configuration est incomplète (accès selon OfflineMode).')
        return
    end

    local res = Api.hello()
    if res.status == 200 then
        local serverName = res.data and type(res.data.server_name) == 'string' and res.data.server_name or '?'
        Utils.info(('Connecté à WhitelistAI : %s'):format(Utils.cleanName(serverName)))

        local latest = res.data and res.data.latest_version
        if Utils.isNewerVersion(latest, Api.VERSION) then
            local url = Utils.isHttpsUrl(res.data.download_url) and res.data.download_url or DOWNLOAD_URL
            Utils.warn(('Mise à jour disponible (%s, tu as la %s) : %s'):format(latest, Api.VERSION, url))
        end
    elseif res.status == 401 or res.status == 403 then
        Utils.error('Clé API refusée par WhitelistAI : vérifie-la dans ton espace (elle a peut-être été régénérée).')
    else
        Utils.warn('WhitelistAI ne répond pas pour le moment, la ressource réessaiera à chaque connexion.')
    end
end)
