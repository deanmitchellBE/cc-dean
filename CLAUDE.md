# CLAUDE.md — Plateforme IA cabinet d'avocats (eTeamsys)

> Fichier de contexte à placer à la racine du dépôt. Il ne contient AUCUN secret.
> Le token SECIB se met dans une variable d'environnement (`SECIB_API_TOKEN`), jamais dans le code, les logs ou Git.

## 1. Projet en une phrase

Portail web unique pour un cabinet d'avocats belge : l'avocat dicte, la plateforme transcrit, puis génère un projet de courrier/acte (via Claude sur AWS Bedrock, région UE) en s'appuyant sur les pièces du dossier lues dans SECIB. SECIB reste l'ERP de référence et n'est pas modifié.

**Phase 1 uniquement** : portail + SSO + dactylographie assistée (P1) + connecteur SECIB en **lecture seule**.
Hors périmètre : analyse de dossier (P2), OneDrive/Jura/Strada/veille (P3), toute écriture vers SECIB.

Spécification complète : `Cahier_des_charges_technique_Phase1.md`.

## 2. Stack

- Frontend : Vue.js 3
- Backend : Laravel (PHP), API REST
- Base : PostgreSQL
- Hébergement : OVHcloud (backend + BDD), frontend OVH ou Vercel
- IA : Claude via AWS Bedrock `eu-central-1` (jamais l'API Anthropic directe)
- Transcription : Whisper auto-hébergé (recommandé) ou API managée UE — interface interchangeable

## 3. Règles non négociables

1. **Lecture seule sur SECIB.** Aucun appel POST d'écriture (`SaveDocument`, `Dossier/Post`, etc.).
2. **Aucune copie du contenu des pièces en base.** On stocke uniquement des identifiants (`secib_dossier_id`, `secib_piece_id`). Le contenu est rechargé depuis SECIB à chaque besoin.
3. **Audio supprimé immédiatement après transcription.**
4. **Aucun contenu de pièce ni de dictée dans les logs.** Seulement des identifiants.
5. **RBAC côté backend sur chaque endpoint.** Voir §4 : SECIB ne filtre rien par utilisateur.
6. **Aucune action irréversible automatique** (envoi, dépôt, signature). Toute sortie porte « à valider par l'avocat ».
7. **Pas de données réelles en test.** Utiliser le sandbox SECIB quand il existe, sinon des mocks.
8. **Secrets** : variables d'environnement uniquement. Ne jamais commiter, afficher ou logger le token.

## 3bis. Statut de l'environnement SECIB

- Le **sandbox n'est pas encore disponible** (promis par Septeo, ~2 mois de test prévus). Tant qu'il n'existe pas, tout appel réel touche potentiellement la production du cabinet : **GET uniquement, sur des appels ciblés, jamais en boucle.**
- Forfait API : 40 €/mois par cabinet. Pas de limite stricte annoncée, mais Septeo recommande d'espacer les appels. Mettre un délai entre les requêtes et un cache court sur les métadonnées.

## 4. API SECIB — ce que l'on sait

Documentation Swagger (Swagger UI 2.x, instance du cabinet) :
`https://secibneo.secib.fr/8.6.0/swagger/ui/index`
Définition JSON : `https://secibneo.secib.fr/8.6.0/swagger/docs/v1` (titre « SEPTEO Avocats API 1.0 (SECIB) », 99 chemins).

**URL de base confirmée par la définition Swagger** (`host` + `basePath`) :
`https://secibneo.secib.fr/8.6.0/{cabinetId}/api/v1/<Ressource>/<Action>`
Le Swagger liste aussi `apiVersion` comme paramètre de chemin, mais il n'apparaît pas dans le gabarit de chemin : à ignorer jusqu'à preuve du contraire.

### Authentification

- Header : `Authorization: Bearer <access_token>` (description Swagger : « Bearer access_Token »). Aucun `securityDefinitions` dans le Swagger.
- **Obtention du token (validé le 13/10/2026)** : OAuth2 `client_credentials`.
  - `POST https://api.secib.fr/forward/<SECIB_CABINET_ID>/ApiToken`, corps `application/x-www-form-urlencoded` : `client_id`, `client_secret`, `grant_type=client_credentials`.
  - **Le GUID du cabinet s'écrit sans accolades** dans l'URL. Avec accolades (forme donnée par Septeo `{guid}`) → 400 `unauthorized_client`. En Basic auth → 500.
  - Réponse : `access_token` (~430 caractères), `token_type`, `expires_in: 28799` → **token valable 8 h**. Le mettre en cache côté backend et le renouveler avant expiration.
  - `client_secret` a la forme `<nombre>.<base64>.<base64>` (c'est la « clé » reçue). Le `cabinetId` est un GUID, distinct du premier segment de la clé.
  - `https://secibneo.secib.fr/8.6.0/token` existe aussi mais refuse ces identifiants (`unauthorized_client`) : ne pas l'utiliser.
- **Un seul token pour tout le cabinet.** Aucune segmentation par avocat côté API : les rôles des intervenants (avocat associé, avocat, stagiaire, secrétaire) sont visibles dans les données, mais leur application est entièrement à notre charge.
- Durée de vie du token : 8 h (`expires_in: 28799`). Prévoir une gestion propre des 401 (un seul renouvellement du token, puis message clair, pas de retry en boucle).

### Endpoints utiles pour la Phase 1 (tous GET)

| Endpoint | Usage |
|---|---|
| `Cabinet/GetInfoCabinet` | **Test de connexion** (sans paramètre) |
| `Dossier/GetDossierById` | Détail d'un dossier |
| `Dossier/Get` (GET : déprécié) / `Dossier/GetDossiers` (POST) | Liste filtrée de dossiers. Préférer les versions POST de lecture ; ce sont des requêtes de lecture malgré le verbe |
| `Document/GetListRepertoireDossier?dossierId=` | Répertoires d'un dossier |
| `Document/GetListeDocument` | Liste filtrée de documents (max 50 éléments par intervalle) |
| `Document/GetInfosDocument?documentId=` | Métadonnées d'un document |
| `Document/GetContentDocument?documentId=&withConvertPdf=` | Fichier (flux binaire), conversion PDF optionnelle |
| `Document/GetContentDocumentBase64` | Même chose encodée en base64 |
| `Partie/Get` | Parties d'un dossier (pour l'adressage des courriers) |
| `Personne/Get`, `Personne/GetPersonnePhysique`, `Personne/GetPersonneMorale` | Coordonnées |
| `Utilisateur/ListIntervenant` | Intervenants : nom, prénom, email, login, profil |

### Limites confirmées par Septeo

- `GetContentDocument` renvoie le **fichier** (PDF si conversion demandée), **pas de texte extrait**. Il faut donc une étape d'extraction de texte (parsing PDF, OCR si scan) côté plateforme. Ne pas passer par une duplication vers SharePoint : on l'écarte volontairement.
- À valider par un test : la conversion d'un document Word natif en PDF exploitable via `withConvertPdf=true`.
- Pas de webhook documenté : pour détecter de nouvelles pièces, il faudrait du polling.
- Écriture non activée dans l'usage courant et non souhaitée en Phase 1.

## 5. Diagnostic d'accès à l'API

**Ne pas deviner : tester, lire le code HTTP et le corps de la réponse, puis rapporter.**

### 5.0 Résultats du 13/10/2026 (environnement Claude Code cloud, sans identifiants)

| Appel | Résultat |
|---|---|
| GET `/8.6.0/swagger/ui/index` | 200, ~1,3 s : **le réseau sortant vers `secibneo.secib.fr` fonctionne** (hypothèse 5.5 écartée pour cet environnement) |
| GET `/8.6.0/swagger/docs/v1` | 200 : `host=secibneo.secib.fr`, `basePath=/8.6.0` → **variante A de 5.1 confirmée** |
| GET `/8.6.0/token` | 400 `unsupported_grant_type` → endpoint OAuth présent |
| POST `/8.6.0/token` `grant_type=client_credentials` | 400 `unauthorized_client` |
| GET `/8.6.0/0/api/v1/Cabinet/GetInfoCabinet` (cabinetId factice, avec ou sans Bearer) | 404, corps vide, ~0,5 s |

Un 404 avec un `cabinetId` invalide signifie qu'un 404 ne prouve **pas** une mauvaise URL : il peut aussi venir d'un mauvais `cabinetId`.

**Test avec identifiants (13/10/2026) : connexion OK.**

| Appel | Résultat |
|---|---|
| POST `api.secib.fr/forward/<guid>/ApiToken` (sans accolades) | 200, token valable 8 h |
| GET `/8.6.0/<guid>/api/v1/Cabinet/GetInfoCabinet` | **200, ~0,5 s**, renvoie le nom du cabinet, `VersionCabinet: 8.6.0`, `Localisation: BE` |

### 5.1 URL de base

Confirmée (voir 5.0) : `https://secibneo.secib.fr/8.6.0/$SECIB_CABINET_ID/api/v1/...`

Test (un seul appel, token jamais affiché) :

Le script lit `SECIB_CABINET_ID`, `SECIB_CLIENT_ID` et `SECIB_CLIENT_SECRET` dans l'environnement, obtient le token, puis appelle `GetInfoCabinet` :

```bash
./scripts/secib_check.sh
```

### 5.2 Cabinet ID

Résolu : c'est le GUID présent dans l'URL de token fournie par Septeo (sans accolades). Ce n'est pas le premier segment de la clé.

### 5.3 Format du token

Résolu : la clé est le `client_secret`, à échanger contre un access token (voir §4, Authentification).

### 5.4 Interpréter les réponses

| Code | Sens probable | Action |
|---|---|---|
| 401 | Token invalide, expiré ou mauvais format | Vérifier le header (`Bearer ` + espace), le format de la clé ; essayer l'échange sur `/token` |
| 403 | Token valide mais accès refusé : mauvais `cabinetId`, ou **IP non autorisée** | Tester un autre `cabinetId` ; demander à Septeo si une liste d'IP autorisées existe (le futur backend OVH aura une IP fixe à leur communiquer) |
| 404 | Mauvais `cabinetId` (constaté) ou mauvais chemin | Vérifier le `cabinetId` ; l'URL de base est confirmée |
| Timeout / DNS / TLS | Réseau ou egress restreint de l'environnement d'exécution | Voir 5.5 |

### 5.5 Réseau sortant

Vérifié le 13/10/2026 : l'environnement Claude Code cloud atteint `secibneo.secib.fr`. Si un autre environnement échoue, vérifier sa liste de domaines autorisés ou lancer les tests depuis la machine locale du développeur.

### 5.6 Ce qu'il faut rapporter

Pour chaque tentative : URL appelée (sans le token), code HTTP, début du corps de réponse, durée. `scripts/secib_check.sh` affiche exactement ces éléments.

## 6. Questions encore ouvertes (à poser à Septeo)

1. ~~Durée de vie du token~~ (8 h, constaté) ; nombre de tokens simultanés autorisés ?
2. ~~Mécanisme d'obtention du token~~ (résolu, voir §4).
3. Liste d'IP autorisées (allowlisting) ?
4. Date de mise à disposition du sandbox.
5. Juridiction et échéances : exposées par l'API (fiche dossier ou module agenda) ?
6. Mandat d'un prestataire externe : formalités attendues (avenant, sous-traitance RGPD, DPA).
7. Politique de versioning et préavis de dépréciation (`Dossier/Get` en GET est déjà marqué déprécié).

## 7. Prochaine étape de développement

1. ~~Rendre le client SECIB fonctionnel sur `GetInfoCabinet`~~ (OK en script). Le porter en Laravel, avec configuration par variables d'environnement : `SECIB_BASE_URL`, `SECIB_TOKEN_URL`, `SECIB_CABINET_ID`, `SECIB_CLIENT_ID`, `SECIB_CLIENT_SECRET`, et un token en cache (8 h).
2. Enchaîner sur `GetDossierById`, `GetListRepertoireDossier`, `GetInfosDocument`, puis `GetContentDocument` (test Word → PDF).
3. Encapsuler le client derrière une interface avec un mock, pour développer sans toucher à la production tant que le sandbox n'existe pas.
