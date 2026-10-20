import json, sys, pathlib
from lupa import lua54

HERE = pathlib.Path(__file__).parent
PRELUDE = r'''
json = { encode = py_encode, decode = function(s) return py_decode(s) end }
NOW = 0
local tasks = {}
function CreateThread(fn) tasks[#tasks+1] = { co = coroutine.create(fn), wake = NOW } end
Citizen = {}
function Wait(ms) coroutine.yield(ms or 0) end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
function GetGameTimer() return NOW end
promise = {}
function promise.new()
  local p = { done = false }
  function p:resolve(v) self.done = true; self.value = v end
  return p
end
function Citizen.Await(p) while not p.done do Wait(10) end return p.value end
function run(limit)
  limit = limit or 100000
  local stop = NOW + limit
  while NOW < stop do
    local ran = false
    for i = #tasks, 1, -1 do
      local t = tasks[i]
      if coroutine.status(t.co) == 'dead' then table.remove(tasks, i)
      elseif t.wake <= NOW then
        local ok, ms = coroutine.resume(t.co)
        if not ok then error(ms) end
        t.wake = NOW + (ms or 0); ran = true
      end
    end
    if not ran then NOW = NOW + 10 end
  end
end
-- FiveM natives
CONVARS = {}
function GetConvar(k, d) local v = CONVARS[k]; if v == nil then return d end return v end
function GetCurrentResourceName() return 'whitelistai' end
function GetResourceMetadata() return '1.0.0' end
function LoadResourceFile(_, f) return py_files[f] end
function SaveResourceFile(_, f, d) py_files[f] = d; return true end
LOGS = {}
_print = print
function print(m) LOGS[#LOGS+1] = m end
HANDLERS = {}
function AddEventHandler(n, fn) HANDLERS[n] = fn end
PLAYERS = {}
function GetPlayerIdentifierByType(src, t) return PLAYERS[src] and PLAYERS[src][t] end
function IsPlayerAceAllowed(src, ace) return PLAYERS[src] and PLAYERS[src].ace == ace end
REQUESTS = {}
API = function(path, body) return 500, '' end
function PerformHttpRequest(url, cb, method, data, headers)
  REQUESTS[#REQUESTS+1] = { url = url, method = method, body = data, headers = headers }
  CreateThread(function()
    Wait(50)
    local status, text = API(url, json.decode(data ~= '' and data or '{}'), headers)
    if status ~= nil then cb(status, text, {}) end
  end)
end
'''

RESOURCE_FILES = ['config.lua', 'server/utils.lua', 'server/api.lua', 'server/cache.lua', 'server/main.lua']


def new_runtime():
    """Lua 5.4 with simulated FiveM natives and a JSON bridge (resource not loaded yet)."""
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    def to_py(v):
        if lua54.lua_type(v) == 'table':
            keys = list(v.keys())
            if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys)+1)):
                return [to_py(v[k]) for k in sorted(keys)]
            return {str(k): to_py(v[k]) for k in keys}
        return v
    def to_lua(v):
        if isinstance(v, dict): return lua.table_from({k: to_lua(x) for k, x in v.items()})
        if isinstance(v, list): return lua.table_from([to_lua(x) for x in v])
        return v
    g.py_encode = lambda t: json.dumps(to_py(t))
    g.py_decode = lambda s: to_lua(json.loads(s))
    g.py_files = lua.table()
    lua.execute(PRELUDE)
    return lua, to_py


def load_resource(lua, res):
    for f in RESOURCE_FILES:
        lua.execute((pathlib.Path(res) / f).read_text())


def run_scenario(res, name):
    lua, _ = new_runtime()
    g = lua.globals()
    lua.execute((HERE / 'scenarios.lua').read_text())
    g.SCENARIOS[name].setup()
    load_resource(lua, res)
    g.SCENARIOS[name].test()


def main():
    res = sys.argv[1]
    names = sys.argv[2:] or list(lua54.LuaRuntime().execute((HERE / "scenarios.lua").read_text() + " local n = {} for k in pairs(SCENARIOS) do n[#n+1] = k end table.sort(n) return table.concat(n, \",\")").split(","))
    failed = 0
    for n in names:
        try:
            run_scenario(res, n); print('PASS', n)
        except Exception as e:
            failed += 1; print('FAIL', n, '->', e)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
