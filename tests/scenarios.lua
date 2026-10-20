SCENARIOS = {}
local KEY = 'wai_' .. string.rep('a1B2', 10)
local LIC = 'license:0123abcdef4567'

local function assertEq(a, b, what)
  if a ~= b then error(('%s: attendu %s, obtenu %s'):format(what, tostring(b), tostring(a)), 2) end
end
local function assertTrue(v, what) if not v then error(what, 2) end end

local function logsContain(s)
  for _, l in ipairs(LOGS) do if l:find(s, 1, true) then return true end end
  return false
end
local function requestsTo(suffix)
  local n, last = 0, nil
  for _, r in ipairs(REQUESTS) do if r.url:sub(-#suffix) == suffix then n = n + 1; last = r end end
  return n, last
end

local function connect(src, name, player)
  PLAYERS[src] = player or { license = LIC }
  local d = { updates = {}, cards = {} }
  function d.defer() d.deferred = true end
  function d.update(m) d.updates[#d.updates + 1] = m end
  function d.done(m) d.finished = true; d.reason = m end
  function d.presentCard(card, cb) d.cards[#d.cards + 1] = json.decode(card); d.cb = cb end
  CreateThread(function()
    source = src
    HANDLERS.playerConnecting(name, function() end, d)
  end)
  run(2000)
  return d
end

local function lastCardTexts(d)
  local card = d.cards[#d.cards]
  local out = {}
  for _, b in ipairs(card.body) do if b.text then out[#out + 1] = b.text end end
  return table.concat(out, ' | '), card
end

local function api(routes)
  API = function(url, body, headers)
    for suffix, fn in pairs(routes) do
      if url:sub(-#suffix) == suffix then return fn(body, headers) end
    end
    return 404, '{"detail":"Not Found"}'
  end
end

local function standard(routes)
  return function()
    CONVARS.whitelistai_key = KEY
    routes['/fivem/hello'] = routes['/fivem/hello'] or function() return 200, '{"server_name":"Nova City"}' end
    api(routes)
  end
end

SCENARIOS.missing_key = {
  setup = function() api({}) end,
  test = function()
    run(500)
    assertTrue(logsContain('Clé API manquante'), 'log clé manquante')
    local d = connect(1, 'Bob')
    assertEq(d.reason, Config.Messages.unavailable, 'refus')
    assertEq(#REQUESTS, 0, 'aucune requête')
  end,
}

SCENARIOS.bad_key_and_http_url = {
  setup = function() CONVARS.whitelistai_key = 'wai_court'; api({}) end,
  test = function()
    run(500)
    assertTrue(logsContain('Clé API invalide'), 'log clé invalide')
    CONVARS.whitelistai_key = KEY
    CONVARS.whitelistai_api_url = 'http://evil.example.com/api'
    assertEq(Api.configure(), false, 'http refusé')
    CONVARS.whitelistai_api_url = 'http://localhost:8000/api/'
    assertEq(Api.configure(), true, 'localhost accepté')
  end,
}

SCENARIOS.allowed = {
  setup = standard({ ['/fivem/check'] = function() return 200, '{"status":"allowed"}' end }),
  test = function()
    run(500)
    assertTrue(logsContain('Connecté à WhitelistAI : Nova City'), 'log hello')
    local d = connect(1, 'Bob^1 "Le Rouge"\n')
    assertTrue(d.finished and d.reason == nil, 'autorisé')
    assertTrue(Cache.has(LIC), 'mis en cache')
    local _, r = requestsTo('/fivem/check')
    assertEq(r.headers.Authorization, 'Bearer ' .. KEY, 'en-tête auth')
    assertEq(r.url, 'https://back.whitelistai.fr/api/fivem/check', 'url')
    local body = json.decode(r.body)
    assertEq(body.license, LIC, 'license envoyée')
    assertEq(body.name, 'Bob "Le Rouge"', 'nom nettoyé')
    for _, l in ipairs(LOGS) do assertTrue(not l:find(KEY, 1, true), 'clé jamais loggée') end
    run(70000)
    assertTrue(py_files['whitelist_cache.json']:find(LIC, 1, true), 'cache écrit sur disque')
  end,
}

SCENARIOS.revoked = {
  setup = standard({ ['/fivem/check'] = function() return 200, '{"status":"revoked"}' end }),
  test = function()
    run(500)
    Cache.allow(LIC)
    local d = connect(1, 'Bob')
    assertEq(d.reason, Config.Messages.revoked, 'refusé')
    assertTrue(not Cache.has(LIC), 'retiré du cache')
  end,
}

SCENARIOS.bypass_and_no_license = {
  setup = standard({}),
  test = function()
    run(500)
    local d = connect(1, 'Admin', { license = LIC, ace = 'whitelistai.bypass' })
    assertTrue(d.finished and d.reason == nil, 'staff autorisé')
    assertEq(requestsTo('/fivem/check'), 0, 'pas de check pour le staff')
    d = connect(2, 'Ghost', {})
    assertEq(d.reason, Config.Messages.no_license, 'sans licence')
    d = connect(3, 'Fake', { license = 'license:<script>' })
    assertEq(d.reason, Config.Messages.no_license, 'licence malformée')
  end,
}

SCENARIOS.code_ok = {
  setup = standard({
    ['/fivem/check'] = function() return 200, '{"status":"unlinked","apply_url":"https://whitelistai.fr/apply/nova"}' end,
    ['/fivem/redeem'] = function(body)
      if body.code == '8K3FQ2HD' then return 200, '{"status":"allowed"}' end
      return 404, '{"detail":"invalid_code"}'
    end,
  }),
  test = function()
    run(500)
    local d = connect(1, 'Bob')
    assertTrue(not d.finished, 'en attente du code')
    local _, card = lastCardTexts(d)
    assertEq(card.actions[2].url, 'https://whitelistai.fr/apply/nova', 'bouton postuler')
    d.cb({ code = ' 8k3f-q2hd ', action = 'redeem' })
    d.cb({ code = '8k3f-q2hd', action = 'redeem' }) -- double clic ignoré
    run(3000)
    assertEq(requestsTo('/fivem/redeem'), 1, 'une seule requête')
    assertTrue(d.finished and d.reason == nil, 'autorisé après code')
    assertTrue(Cache.has(LIC), 'en cache')
  end,
}

SCENARIOS.code_format_and_used = {
  setup = standard({
    ['/fivem/check'] = function() return 200, '{"status":"unlinked","apply_url":"javascript:alert(1)"}' end,
    ['/fivem/redeem'] = function() return 409, '{"detail":"code_used"}' end,
  }),
  test = function()
    run(500)
    local d = connect(1, 'Bob')
    local _, card = lastCardTexts(d)
    assertEq(#card.actions, 1, 'url non https ignorée')
    d.cb({ code = 'abc' })
    run(500)
    assertTrue(lastCardTexts(d):find(Config.Messages.code_format, 1, true), 'erreur de format')
    assertEq(requestsTo('/fivem/redeem'), 0, 'format faux non envoyé')
    d.cb({ code = 'IIII0000' })
    run(500)
    assertEq(requestsTo('/fivem/redeem'), 0, 'caractères ambigus refusés')
    d.cb({ code = '8K3F-Q2HD' })
    run(3000)
    assertTrue(lastCardTexts(d):find(Config.Messages.code_used, 1, true), 'code déjà utilisé')
    assertTrue(not d.finished, 'peut réessayer')
  end,
}

SCENARIOS.too_many_attempts = {
  setup = standard({
    ['/fivem/check'] = function() return 200, '{"status":"unlinked"}' end,
    ['/fivem/redeem'] = function() return 404, '{"detail":"invalid_code"}' end,
  }),
  test = function()
    run(500)
    local d = connect(1, 'Bob')
    for _ = 1, 10 do
      if d.finished then break end
      d.cb({ code = '22222222' })
      run(3000)
    end
    assertEq(d.reason, Config.Messages.too_many_attempts, 'bloqué')
    assertEq(requestsTo('/fivem/redeem'), Config.MaxCodeAttempts, 'nombre de requêtes')
    local d2 = connect(2, 'Bob')
    assertEq(d2.reason, Config.Messages.too_many_attempts, 'reconnexion aussi bloquée')
    NOW = NOW + 11 * 60 * 1000
    local d3 = connect(3, 'Bob')
    assertTrue(not d3.finished, 'débloqué après 10 min')
  end,
}

SCENARIOS.timeout_uses_cache = {
  setup = standard({ ['/fivem/check'] = function() return nil end }),
  test = function()
    run(500)
    Cache.allow(LIC)
    local d = connect(1, 'Bob')
    run(10000)
    assertTrue(d.finished and d.reason == nil, 'habitué autorisé hors ligne')
    local d2 = connect(2, 'New', { license = 'license:ffff' })
    run(10000)
    assertEq(d2.reason, Config.Messages.unavailable, 'inconnu refusé hors ligne')
  end,
}

SCENARIOS.offline_closed_and_401 = {
  setup = standard({
    ['/fivem/hello'] = function() return 401, '{"detail":"invalid_key"}' end,
    ['/fivem/check'] = function() return 401, '{"detail":"invalid_key"}' end,
  }),
  test = function()
    run(500)
    assertTrue(logsContain('Clé API refusée'), 'log clé refusée')
    Config.OfflineMode = 'closed'
    Cache.allow(LIC)
    local d = connect(1, 'Bob')
    assertEq(d.reason, Config.Messages.unavailable, 'fermé')
  end,
}

SCENARIOS.rate_limited_and_garbage = {
  setup = standard({ ['/fivem/check'] = function() return 429, '' end }),
  test = function()
    run(500)
    local d = connect(1, 'Bob')
    assertEq(d.reason, Config.Messages.rate_limited, '429')
    api({ ['/fivem/check'] = function() return 200, 'pas du json' end })
    local ok = pcall(function() d = connect(2, 'Bob') end)
    -- garbage JSON must not crash the handler
    assertTrue(ok and d.reason == Config.Messages.unavailable, 'réponse illisible')
  end,
}

SCENARIOS.update_notice = {
  setup = standard({
    ['/fivem/hello'] = function()
      return 200, '{"server_name":"Nova","latest_version":"1.10.0","download_url":"javascript:x"}'
    end,
  }),
  test = function()
    run(500)
    assertTrue(logsContain('Mise à jour disponible (1.10.0, tu as la 1.0.0) : https://github.com/lilgar77/whitelistai-fivem/releases/latest'), 'avertissement')
    assertEq(Utils.isNewerVersion('1.0.0', '1.0.0'), false, 'même version')
    assertEq(Utils.isNewerVersion('0.9.9', '1.0.0'), false, 'plus ancienne')
    assertEq(Utils.isNewerVersion('1.0.1; rm -rf', '1.0.0'), false, 'malformée')
  end,
}
