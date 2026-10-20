Config = {}

-- La clé API ne se met PAS ici : ajoute dans ton server.cfg
--   set whitelistai_key "wai_..."
-- (avec `set`, jamais `setr` ni `sets` qui la rendraient visible des joueurs).

-- Adresse de l'API WhitelistAI (surchargeable avec `set whitelistai_api_url "..."`).
Config.ApiUrl = 'https://back.whitelistai.fr/api'

-- Les joueurs ayant cette permission ACE entrent sans whitelist (staff).
-- Exemple dans le server.cfg :
--   add_ace group.admin whitelistai.bypass allow
Config.BypassAce = 'whitelistai.bypass'

-- Si WhitelistAI est injoignable :
--   'cache'  : seuls les joueurs déjà acceptés (vus récemment) peuvent entrer (recommandé)
--   'closed' : personne n'entre
--   'open'   : tout le monde entre (déconseillé)
Config.OfflineMode = 'cache'

-- Durée pendant laquelle un joueur accepté reste dans le cache local (en jours).
Config.CacheDays = 7

-- Délai max d'une requête vers WhitelistAI (en millisecondes).
Config.RequestTimeout = 8000

-- Nombre d'essais de code autorisés par joueur, sur une fenêtre de 10 minutes.
Config.MaxCodeAttempts = 5

-- Affiche les connexions et décisions dans la console du serveur.
Config.Debug = false

Config.Messages = {
    checking = '🔎 Vérification de ta whitelist…',
    no_license = 'Impossible de vérifier ton compte Rockstar. Relance FiveM et réessaie.',
    revoked = '⛔ Ta whitelist a été retirée par le staff de ce serveur.',
    unavailable = '⚠️ La whitelist est momentanément indisponible. Réessaie dans quelques minutes.',
    rate_limited = '⏳ Trop de tentatives. Réessaie dans quelques minutes.',
    code_title = 'Whitelist requise',
    code_text = 'Pour rejoindre ce serveur, passe la whitelist sur le site. Une fois accepté, entre ici le code d’accès qui t’a été donné.',
    code_placeholder = 'Code d’accès (ex : 8K3F-Q2HD)',
    code_submit = 'Valider',
    apply_button = 'Passer la whitelist',
    code_invalid = '❌ Code invalide. Vérifie-le et réessaie.',
    code_used = '❌ Ce code a déjà été utilisé par un autre compte.',
    code_format = '❌ Le code doit contenir 8 caractères (ex : 8K3F-Q2HD).',
    too_many_attempts = '⛔ Trop de codes invalides. Réessaie dans 10 minutes.',
    welcome = '✅ Code validé, bienvenue !',
}
