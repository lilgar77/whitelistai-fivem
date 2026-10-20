# WhitelistAI pour FiveM

Ressource serveur qui laisse entrer automatiquement les joueurs acceptés sur WhitelistAI.
Compatible ESX, QBCore et serveurs standalone : elle ne touche pas à ta base de données.

## Installation

1. Dépose le dossier `whitelistai` dans `resources/`.
2. Dans ton `server.cfg` :

   ```cfg
   set whitelistai_key "wai_xxxxxxxxxxxxxxxx"   # ta clé, depuis ton espace WhitelistAI
   ensure whitelistai

   # Le staff entre sans whitelist (optionnel)
   add_ace group.admin whitelistai.bypass allow
   ```

3. Redémarre le serveur. La console affiche `Connecté à WhitelistAI : <ton serveur>`.

> ⚠️ Utilise bien `set` pour la clé, **jamais `setr` ni `sets`** : elles la rendraient visible
> par les joueurs. Si ta clé fuite, régénère-la depuis ton espace : l'ancienne est
> immédiatement désactivée.

## Côté joueur

1. Il passe la whitelist sur le site.
2. Une fois accepté, il reçoit un code d'accès (ex : `8K3F-Q2HD`).
3. À sa première connexion au serveur, il entre ce code. C'est tout : ensuite il entre directement.

Le code ne sert qu'une fois : il est lié au compte Rockstar du premier joueur qui l'utilise.

## Configuration (`config.lua`)

| Option | Rôle |
| --- | --- |
| `BypassAce` | Permission ACE qui laisse entrer sans whitelist (`whitelistai.bypass`). |
| `OfflineMode` | Si WhitelistAI est injoignable : `cache` (joueurs déjà acceptés seulement), `closed` ou `open`. |
| `CacheDays` | Durée de mémorisation locale d'un joueur accepté. |
| `MaxCodeAttempts` | Codes faux autorisés par joueur sur 10 minutes. |
| `Messages` | Tous les textes affichés aux joueurs. |

## Sécurité

- Script 100 % serveur : rien n'est envoyé au jeu des joueurs, la clé reste sur ta machine.
- Connexion chiffrée (HTTPS) uniquement, et c'est ton serveur qui contacte WhitelistAI :
  aucun port à ouvrir, aucun accès à ta base de données.
- Les joueurs sont identifiés par leur licence Rockstar, vérifiée par FiveM
  (ne pas activer `sv_lan` en production).
- Un joueur retiré de la whitelist est refusé dès sa connexion suivante.
