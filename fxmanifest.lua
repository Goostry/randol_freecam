fx_version 'cerulean'
game 'gta5'

author 'Randolio'
description 'Free Cam edited by Goostry'

shared_scripts {
    '@ox_lib/init.lua',
}

dependencies {
    'oxmysql'
}

client_scripts {
    'cl_freecam.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'sv_freecam.lua'
}

files {
    'locales/*.json'
}

lua54 'yes'