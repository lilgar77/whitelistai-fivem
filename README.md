# whitelistai-fivem

Ressource FiveM (dossier `whitelistai/`) téléchargée par les owners depuis leur espace.
Installation et configuration : voir [`whitelistai/README.md`](whitelistai/README.md).

Téléchargement (toujours la dernière version) :
`https://github.com/lilgar77/whitelistai-fivem/releases/latest/download/whitelistai.zip`

## Publier une version

1. Monter `version` dans `whitelistai/fxmanifest.lua` (ex : `1.1.0`) et committer.
2. `git tag v1.1.0 && git push origin main --tags`
3. GitHub Actions lance les tests, vérifie que le tag correspond au fxmanifest, puis publie
   `whitelistai.zip` dans la release.

## Tests

Les natives FiveM sont simulées dans un vrai Lua 5.4 (via `lupa`), aucun serveur FiveM n'est nécessaire :

```bash
uv run --with lupa python tests/run.py whitelistai              # tous les scénarios
uv run --with lupa python tests/run.py whitelistai code_ok      # un seul
```

## Contrat d'API (à implémenter côté backend)

Toutes les routes sont sous `/api/fivem`, appelées par le serveur FiveM avec
`Authorization: Bearer wai_...` (clé propre à chaque serveur WhitelistAI, stockée hachée).
Réponses en JSON ; une clé invalide ou révoquée renvoie `401`, l'excès de requêtes `429`.

| Route | Corps | Réponse `200` |
| --- | --- | --- |
| `POST /fivem/hello` | `{resource_version, hostname}` | `{server_name, latest_version?, download_url?}` (marque le serveur « connecté » ; la console prévient si `latest_version` est plus récente) |
| `POST /fivem/check` | `{license, name}` | `{status: "allowed" \| "unlinked" \| "revoked", apply_url}` |
| `POST /fivem/redeem` | `{license, code, name}` | `{status: "allowed"}` |

- `license` : `license:<hex>`, licence Rockstar vérifiée par FiveM.
- `check` : `allowed` si la licence est liée à une candidature acceptée de ce serveur,
  `revoked` si l'owner l'a refusée ensuite, sinon `unlinked` (avec `apply_url` en https).
- `redeem` : `code` normalisé (8 caractères `[2-9A-HJ-NP-Z]`, sans tiret). Erreurs :
  `404 invalid_code` (inconnu, expiré ou d'un autre serveur), `409 code_used`
  (déjà lié à une autre licence). Le code est à usage unique.
