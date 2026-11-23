# ASIA MAX — fichier de démarrage pour Claude Code

App perso de Noé et de son ami pour leur voyage en Asie de l'été 2027 (Chine, Hong Kong, Macao, Corée, Thaïlande). L'app transforme les réels Instagram / TikTok sauvegardés en fiches de lieux, que les deux voyageurs notent de 1 à 3 étoiles. Elle affiche ces fiches sur une carte et les range selon un itinéraire qui change encore.

> Ce fichier s'appelle `ASIA-MAX_CLAUDE.md` pour ne pas être confondu avec les fichiers des autres projets de Noé. À la première session, renomme-le en `CLAUDE.md` à la racine du dossier `asia-max` : Claude Code ne relit automatiquement que les fichiers nommés `CLAUDE.md`.

Références (liens privés sur claude.ai : Claude Code ne peut pas les ouvrir ; demande à Noé une capture ou un export si besoin) :
- Cahier des charges, 4 onglets (cadrage, modèle de données, cas limites, cahier technique) : https://claude.ai/artifact/BcHw3JFw226Gu1YrdXTZmF
- Maquettes des 7 écrans (cliquables) : https://claude.ai/artifact/FnjYJZ5Xvi4ojQUpj3AMgH

## Comment travailler sur ce projet

- Noé apprend en construisant. Explique en français, en deux ou trois phrases, ce que tu fais et pourquoi, surtout pour la base, la sécurité et le déploiement.
- Avance phase par phase (voir « Plan de développement »). Ne commence pas une phase tant que le critère « terminée quand » de la précédente n'est pas atteint et vérifié sur iPhone.
- **Budget zéro.** N'ajoute aucun service payant, aucun abonnement, aucune dépendance qui exige une carte bancaire, sans l'accord explicite de Noé. Reste dans les offres gratuites listées plus bas.
- **Préviens Noé AVANT** toute étape (inscription, activation d'une API, option d'un service) qui demande une carte bancaire, propose un « essai gratuit » ou peut devenir payante. Dis-le clairement au début de l'étape, pas après.
- Les choix du cahier des charges sont validés. Si une contrainte technique oblige à en changer un (modèle de données, règle de notation, catégories…), demande avant de le faire.
- Langues : interface de l'app en **français**. Contenu des fiches en **anglais**, avec le nom local (chinois, coréen, thaï) et sa transcription.
- Les deux utilisateurs ont un **iPhone**. Tout doit marcher dans Safari iOS en mode « app installée sur l'écran d'accueil » (PWA).

## Stack

| Brique | Choix | Notes |
| --- | --- | --- |
| App | Vite + React + TypeScript, PWA (`vite-plugin-pwa`) | Une seule base de code, installable sur l'écran d'accueil |
| Carte | MapLibre GL JS + tuiles OpenFreeMap | Gratuit, sans clé. Hors-ligne en V2 (extraits PMTiles par zone) |
| Style | CSS avec variables (tokens ci-dessous) | Reprendre la direction des maquettes |
| Hébergement | Cloudflare Pages | Déploiement à chaque push sur `main` |
| Base, auth, synchro, images | Supabase (offre gratuite) | Postgres + RLS, connexion par lien magique, Realtime, Storage, Edge Functions |
| Robot d'import | Python 3.12 dans GitHub Actions | Déclenché par `repository_dispatch` ; tâches planifiées pour le maintien en vie et la sauvegarde |
| Lecture Instagram | Apify : `apify/instagram-reel-scraper` (et l'acteur officiel pour les posts et carrousels) | 5 $ de crédit gratuit par mois, environ 0,0023 $ par réel |
| Lecture TikTok | `yt-dlp` | |
| Images de la vidéo | `ffmpeg` | Une image par lieu, au moment où il apparaît |
| IA | Gemini Flash, offre gratuite (SDK `google-genai`), sortie JSON stricte avec schéma | Lit directement vidéo, voix et texte à l'écran. Isoler l'appel dans **un seul module** (`worker/extract.py`) pour pouvoir changer d'IA |
| Vérification des lieux | Google Places API (New) : Text Search + Place Details, avec masques de champs, via la **Maps Demo Key** | Sans carte bancaire : limite quotidienne, puis arrêt jusqu'au lendemain, sans frais. Ne donne pas les photos ni les avis des utilisateurs : les images viennent des réels. Clé côté robot uniquement. Ne jamais lancer l'essai gratuit de Google Cloud sans accord de Noé |
| Taux de change | API Frankfurter (taux BCE) | Prix en euros affiché à côté du prix local |
| Notifications | Web Push (clés VAPID), envoyées par une Edge Function | iOS 16.4 ou plus, app installée sur l'écran d'accueil |
| Entrée des partages | Raccourci iPhone dans le menu Partager → Edge Function `share` | iOS ne gère pas le Web Share Target |

Le nom exact du modèle Gemini change souvent : vérifie le modèle Flash courant et ses limites gratuites dans la doc Google avant de l'écrire en dur, et mets-le dans une variable d'environnement.

## Structure du dépôt (cible)

```
app/                      PWA React
  src/screens/            Accueil, Noter, Fiche, Carte, Etape, Aujourdhui, Ajouter
  src/lib/                supabase client, calculs (note commune, budget, visa), geo (gcj02)
supabase/
  migrations/             schéma SQL versionné
  functions/share/        reçoit un lien partagé (clé secrète), nettoie l'URL, met en file, déclenche le robot
  functions/notify/       envoie les notifications web
worker/                   robot d'import Python
  main.py                 orchestre un job de la file
  fetch.py                Apify / yt-dlp / page web / capture
  extract.py              SEUL module qui parle à l'IA
  places.py               Google Places + contrôles de cohérence
  dedupe.py               anti-doublon
  media.py                extraction et compression des images
  geo.py                  conversions GCJ-02 <-> WGS-84
  tests/
.github/workflows/
  import.yml              repository_dispatch -> worker
  keepalive.yml           visite quotidienne de la base (pause Supabase après 7 jours)
  backup.yml              export hebdomadaire de la base dans le dépôt privé
```

## Modèle de données

Principe central : **un lieu appartient à une zone** (pays › région › ville › quartier), **jamais directement à une étape**. Une étape pointe aussi vers une zone. Si l'itinéraire change, aucun lieu n'est perdu.

Tables du socle (MVP) :

- `person` : nom, rôle (`voter` | `guest`). Seules deux personnes votent.
- `zone` : type (`country` | `region` | `city` | `district`), parent, nom anglais, nom local, centre.
- `place` :
  - identité et classement : zone, `category`, `kind` (`point` | `area` | `route` | `chain` | `taste` | `tip`), noms (anglais, local, transcription, `alt_names[]`) ;
  - position : `lat` et `lng` en **WGS-84**, `position_precision` (`exact` | `approx`), `google_place_id` (unique, facultatif), `business_status`, adresse locale ;
  - infos pratiques : horaires, jours de fermeture, prix par personne (min, max), `currency`, transport en plus du métro et son coût par personne, durée, meilleur moment ;
  - contenu : résumé, astuces, plats à commander, `needs_reservation` ;
  - états et liens : `to_confirm`, `out_of_trip` (masqué par défaut), `parent_place_id`, dates d'événement, `review_status` (`ok` | `to_check` | `to_review`).
- `media` : lieu, type (image du réel, photo du web, capture, photo perso), chemin dans Storage, crédit.
- `source` : plateforme, `format` (`video` | `carousel` | `photo` | `story` | `link` | `screenshot` | `manual`), `canonical_url` (unique), créateur, date de publication, légende, transcription complète, `sponsored`, `missing_info` (`dm` | `bio_link`), partagée par.
- `source_place` : source, lieu, `rank` (classement), `timestamp_s` ou `slide_index`, image associée, avis du créateur sur ce lieu.
- `import_job` : lien, partagé par, état (`pending` | `done` | `to_check` | `error`), essais, raison de l'échec, prochaine tentative.
- `rating` : lieu, personne, étoiles de 1 à 3, date. Clé unique (lieu, personne).
- `rating_history` : avant, après, date.
- `merge_history` : fiches fusionnées, sources et notes de chacune, auteur, date. Sert à « séparer » sans rien perdre.
- `stage` : zone, ordre, nombre de jours, dates facultatives, branche (principale ou parallèle), participants, décideurs.
- `leg` : départ, arrivée, mode, durée, distance.
- `task` (démarches avant le départ) : titre, qui, échéance, fait ou non, lien.

V2 : `day_plan`, `lodging`, `alert`, `visit`, `variant`.

Catégories (couleur de pin) : Manger `#C2412D`, Boire `#8B5A2B`, Culture `#2F5DA8`, Nature `#2E7D4F`, Loisirs et jeux `#7B3FA0`, Shopping `#B03A72`, Sortir `#1C1B19`, Pratique (gris).

## Règles métier à ne jamais casser

1. **Un lieu, une fiche.** Un « top 10 » donne 10 fiches, chacune avec son rang et sa propre image (image de la vidéo au moment du lieu, ou la bonne diapo).
2. **Jamais de doublon** :
   - même `canonical_url` → rien n'est recréé (on ajoute seulement « aussi partagé par ») ;
   - même `google_place_id` → fusion automatique ;
   - lieu absent de Google, même nom (anglais, local ou transcription) à moins de 150 m → fusion **proposée**, jamais automatique ;
   - sinon → nouvelle fiche.
3. **Jamais de lieu inventé.** Tout lieu proposé par l'IA doit être retrouvé dans Google Places, et la ville trouvée doit correspondre à celle du réel :
   - nom proche mais pas identique → fiche créée avec `to_confirm = true` (badge « à confirmer ») ;
   - introuvable ou ville incohérente → `review_status = 'to_check'` (« À vérifier »).
4. **Rien n'est perdu.** Un échec garde le job avec sa raison. Une fiche n'est jamais supprimée automatiquement.
5. **Tout se corrige en un geste** : fusionner, séparer, déplacer le point, changer la catégorie.
6. **L'origine reste visible** : lien, date, créateur, légende et transcription d'origine, consultables depuis la fiche.

Notation :
- Note commune = moyenne des notes des **décideurs de l'étape**. C'est vous deux par défaut ; à Suzhou ou à Pékin, seul celui qui y va compte.
- Étoile sur la carte, visible même dézoomé, si la note commune atteint 2.
- « Avis très différents » si l'écart entre les deux notes est de 2 étoiles.
- Aucun lieu n'est écarté : ceux notés 1 étoile restent en réserve.
- Une nouvelle source ne remet jamais les notes à zéro.

Prix : toujours **par personne**. Tout transport en plus du métro (taxi, bus, train spécial) est signalé avec son coût par personne. Équivalent en euros affiché à côté du prix local.

Réglages validés :
- rattachement à une étape dans un rayon de 30 km autour d'une ville, ou de 50 km du tracé pendant le road trip ;
- 2 à 3 images du réel et 2 photos du web au maximum par lieu, compressées en WebP d'environ 100 Ko ;
- alerte visa à 25 jours sur 30 par entrée en Chine continentale ;
- temps de conduite au Xinjiang × 1,5.

## Pipeline d'import

1. `share` (Edge Function) : vérifie la clé secrète du partageur, nettoie l'URL (supprime `igsh`, `utm_*`…), contrôle l'unicité de `canonical_url`, crée un `import_job`, envoie un `repository_dispatch` à GitHub.
2. `fetch.py` : récupère légende, tag de lieu, date, créateur, médias (vidéo, ou chaque diapo d'un carrousel).
3. `extract.py` : **un seul appel** à l'IA, avec la vidéo ou les images, la légende et le tag de lieu. Il renvoie une liste de lieux au format JSON validé par schéma :
   - noms anglais, local et transcription, ville, pays ;
   - catégorie, type de fiche, rang, `timestamp_s` ou `slide_index` ;
   - prix par personne et devise, transport en plus du métro ;
   - astuces, plats, avis du créateur ;
   - résumé réécrit, sans codes promo, hashtags ni bavardage ;
   - degré de certitude.
4. `places.py` : Text Search (nom + ville), contrôles nom et ville, puis Place Details (adresse locale, horaires, `businessStatus`). Ne demander que les champs utiles (masques de champs) pour rester dans le niveau gratuit.
5. `dedupe.py` : règles ci-dessus.
6. `media.py` : `ffmpeg` extrait l'image au `timestamp_s`, puis la compresse en WebP et l'envoie dans Storage.
7. Écriture en base. Realtime prévient les deux téléphones, `notify` envoie la notification.
8. Échec : 3 essais espacés, puis `to_check` avec la raison. Quota gratuit atteint : le job attend et repart au renouvellement du quota.

Cas à gérer dès le MVP : vidéo sans parole (texte à l'écran, légende, tag de lieu), « commente LISTE » (bouton « coller une liste reçue en message privé »), réel en langue étrangère, compte privé ou réel supprimé (`to_check` + demande de capture), lieux de plusieurs villes dans un même réel, lieu hors des régions du voyage (`out_of_trip`), import en masse par petits lots.

## Chine : points techniques

- **Coordonnées GCJ-02.** En Chine continentale (pas à Hong Kong ni à Macao), Google Places et Amap donnent des coordonnées GCJ-02, décalées de plusieurs centaines de mètres par rapport au GPS. Il faut :
  - stocker en WGS-84 et convertir à l'import (`worker/geo.py`) ;
  - reconvertir en GCJ-02 pour ouvrir Amap ;
  - tester la conversion avec des points connus.
- Boutons de carte :
  - Amap en Chine continentale ;
  - Google Maps ailleurs (`https://www.google.com/maps/search/?api=1&query=...&query_place_id=...`) ;
  - Naver en Corée.
  Vérifie le format actuel des liens Amap et Naver avant de les coder.
- Chaque fiche affiche l'adresse en langue locale, en grand, pour la montrer à un chauffeur.
- Connexion sur place : eSIM à routage international (Google et Instagram marchent), VPN de secours. Le Wi-Fi d'hôtel reste bloqué : le mode hors-ligne (V2) doit couvrir ce cas.

## Sécurité et secrets

- Aucune clé dans le code ni dans l'app. Secrets dans GitHub Actions (`APIFY_TOKEN`, `GEMINI_API_KEY`, `GOOGLE_PLACES_KEY`, `SUPABASE_SERVICE_ROLE_KEY`) et dans Supabase (clés VAPID, jeton GitHub pour le dispatch, `SHARE_TOKEN` par personne).
- RLS activée sur toutes les tables. Seules les deux adresses e-mail autorisées peuvent lire et écrire.
- Clé Google : Maps Demo Key, sans facturation possible. Quand sa limite du jour est atteinte, les jobs d'import attendent le lendemain (même logique que les autres quotas gratuits).
- Le formulaire de recommandation des proches (V2) passe par une Edge Function, sans accès direct à la base.

## Design

Tokens :
- fond `#F7F4EE`, encre `#1C1B19`, texte secondaire `#5E5A53`, bordures `#E3DDD2` ;
- accent vermillon `#B8321F`, étoiles `#D99A00` et `#F2B632` ;
- polices Inter (texte), Space Grotesk (titres), Noto Sans SC et KR (noms locaux).

Les 7 écrans de référence sont dans les maquettes : Accueil, Noter, Fiche lieu, Carte, Étape, Aujourd'hui, Ajouter un lieu. Barre d'onglets en bas. L'écran Noter montre une fiche à la fois, avec 3 boutons d'étoiles et « Annuler la dernière note ».

## Plan de développement

| Phase | Contenu | Terminée quand |
| --- | --- | --- |
| 0. Fondations | Dépôt, squelette PWA, projet Supabase, schéma initial, déploiement Cloudflare, `keepalive.yml` | L'app vide s'ouvre sur les deux iPhones, installée sur l'écran d'accueil |
| 1. Lieux et carte | Zones, fiches lieu, carte colorée par catégorie avec étoiles, ajout manuel simple | Des lieux saisis à la main apparaissent sur la carte |
| 2. Noter à deux | Connexion par lien magique, écran Noter, étoiles, Realtime, note commune | Une note donnée sur un iPhone apparaît sur l'autre en quelques secondes |
| 3. Import automatique | Raccourci, `share`, robot, IA, Places, anti-doublon, « À vérifier », images, `backup.yml` | Les 20 réels de test donnent les bonnes fiches |
| 4. Itinéraire | Étapes, rattachement automatique, budget par personne, compteur de visa, écran Aujourd'hui | L'itinéraire actuel est saisi et chaque lieu tombe dans la bonne étape |
| 5. V2 | Notifications, hors-ligne, veille et alertes, hébergements, fiches sans point, suggestions de lieux | Avant juin 2027 |

Suggestions de lieux par l'app (V2) : Noé doit fournir ses critères précis. **S'il oublie, le lui rappeler** au début de la phase 5.

## Tests

- Jeu de 20 réels de test fourni par Noé, à ranger dans `worker/tests/fixtures/links.txt` avec le résultat attendu. Il doit contenir au moins :
  - deux « top 10 », un en vidéo et un en carrousel ;
  - une vidéo sans parole ;
  - un réel « commente LISTE » ;
  - un réel en chinois ;
  - un même lieu dans deux réels ;
  - un plat sans adresse ;
  - un quartier ou un parc ;
  - un restaurant, un site, un réel où le lieu n'est pas nommé.
- Tests unitaires obligatoires : conversion GCJ-02, anti-doublon, note commune, compteur de visa, budget par personne.
- Avant de déclarer une phase terminée, la tester sur un vrai iPhone, installée sur l'écran d'accueil.

## Commandes

À compléter au fil de la phase 0 (installation, lancement local, migrations, déploiement, lancement du robot en local).
