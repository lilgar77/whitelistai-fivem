"""
Simulateur de serveur FiveM : fait tourner la vraie ressource contre une API WhitelistAI
(par défaut l'API locale) et te laisse jouer le rôle du joueur qui se connecte.

    uv run --with lupa python tests/simulate.py --key wai_...
    uv run --with lupa python tests/simulate.py --key wai_... --api https://back.whitelistai.fr/api
"""

import argparse
import json
import os
import pathlib
import re
import secrets
import sys
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from run import load_resource, new_runtime  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = ROOT / 'whitelistai'
COLORS = re.compile(r'\^\d')

PRESETS = {
    '2': ('Emma_RP', 'license:' + 'e1' * 20, 'déjà liée : entre directement'),
    '3': ('Hugo_RP', 'license:' + 'a7' * 20, 'refusé après liaison : bloqué'),
}


def http(to_py):
    def call(url, method, data, headers):
        request = urllib.request.Request(
            url, data=data.encode() if data else None, method=method, headers=dict(to_py(headers))
        )
        try:
            with urllib.request.urlopen(request, timeout=8) as response:
                return response.status, response.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode()
        except (urllib.error.URLError, TimeoutError):
            return 0, ''
    return call


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--key', default=os.environ.get('WHITELISTAI_KEY', ''), help='clé API du serveur (wai_...)')
    parser.add_argument('--api', default='http://127.0.0.1:8000/api', help='URL de l’API')
    args = parser.parse_args()

    lua, to_py = new_runtime()
    g = lua.globals()
    g.py_http = http(to_py)
    version = re.search(r"^version '([^']+)'", (RESOURCE / 'fxmanifest.lua').read_text(), re.M).group(1)
    lua.execute(f'''
function GetResourceMetadata() return '{version}' end
function PerformHttpRequest(url, cb, method, data, headers)
  CreateThread(function() Wait(10); local s, t = py_http(url, method, data, headers); cb(s, t, {{}}) end)
end
function connect(src, name, license)
  PLAYERS[src] = {{ license = license }}
  local d = {{ cards = {{}}, updates = {{}} }}
  function d.defer() end
  function d.update(m) d.updates[#d.updates + 1] = m end
  function d.done(m) d.finished = true; d.reason = m end
  function d.presentCard(c, cb) d.cards[#d.cards + 1] = json.decode(c); d.cb = cb end
  CreateThread(function() source = src; HANDLERS.playerConnecting(name, nil, d) end)
  run(3000)
  return d
end
function submit(d, code) d.cb({{ code = code, action = 'redeem' }}); run(3000) end
''')
    g.CONVARS.whitelistai_key = args.key
    g.CONVARS.whitelistai_api_url = args.api
    load_resource(lua, RESOURCE)

    printed = 0

    def flush_logs():
        nonlocal printed
        logs = list(to_py(g.LOGS) or [])
        for line in logs[printed:]:
            print('  [console] ' + COLORS.sub('', line))
        printed = len(logs)

    print(f'\nServeur FiveM simulé (ressource v{version}) → {args.api}')
    lua.execute('run(1000)')
    flush_logs()

    last = None
    src = 0
    while True:
        print('\nQui se connecte ?')
        print('  1. Un nouveau joueur (licence aléatoire)')
        for key, (name, _, note) in PRESETS.items():
            print(f'  {key}. {name} ({note})')
        if last:
            print(f'  4. Le même joueur qu’avant ({last[0]})')
        print('  q. Quitter')
        choice = input('> ').strip().lower()
        if choice == 'q':
            return
        if choice == '1':
            player = (f'Joueur_{secrets.token_hex(2)}', 'license:' + secrets.token_hex(20))
        elif choice in PRESETS:
            player = PRESETS[choice][:2]
        elif choice == '4' and last:
            player = last
        else:
            continue
        last = player
        src += 1
        name, license = player
        print(f'\n→ {name} ({license}) se connecte…')
        d = lua.globals().connect(src, name, license)
        flush_logs()

        shown = 0
        while not d.finished:
            cards = to_py(d.cards) or []
            if len(cards) == shown:
                print('  (en attente…)')
                break
            card = cards[-1]
            shown = len(cards)
            print('\n  ┌─ Écran de connexion FiveM')
            for block in card['body']:
                if block.get('text'):
                    print('  │ ' + block['text'])
            for action in card.get('actions', []):
                if action.get('url'):
                    print(f'  │ [{action["title"]}] {action["url"]}')
            print('  └─')
            code = input('  Code d’accès (vide = fermer FiveM) : ').strip()
            if not code:
                print('  Le joueur ferme FiveM.')
                break
            lua.globals().submit(d, code)
            flush_logs()

        if d.finished:
            if d.reason is None:
                print('  ✅ Connexion acceptée : le joueur est sur le serveur.')
            else:
                print(f'  ⛔ Connexion refusée : {d.reason}')


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print()
