fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whitelistai'
author 'LILGAR'
description 'Whitelist automatique WhitelistAI (https://whitelistai.fr)'
version '1.0.1'

-- Server only: nothing is ever sent to the players' game.
server_scripts {
    'config.lua',
    'server/utils.lua',
    'server/api.lua',
    'server/cache.lua',
    'server/main.lua',
}
