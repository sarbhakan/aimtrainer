# Références d’exercices et audit de calibration

Recherche/QA du **11 octobre 2026, Europe/Paris**, sur le checkout `fa5b289`.
Périmètre : ce document uniquement ; lecture du code, des définitions et des tests, sans modification du produit.

**Lecture historique :** les observations ci-dessous portent sur la 0.2.0. L’intégration 0.3.0 ajoute les blocs de comparaison du protocole 2, la géométrie révision 2 et les imports explicites ; consulter `docs/CALIBRATION.md`, `docs/DECISIONS.md` et `docs/QA_REVIEW.md` pour le comportement actuel et les contre-exemples retestés. Les paramètres proposés ici ne deviennent pas pour autant des règles confirmées d’Aimlabs.

## 1. Niveau de preuve et limites

- **Confirmé dans le dépôt** : comportement lisible dans les sources AIM/LOCAL à la révision auditée, éventuellement couvert par les tests exécutés ci-dessous. Ce n’est pas une observation d’Aimlabs.
- **Confirmé documentaire externe** : texte effectivement consulté sur une page publique accessible. Cela confirme ce que son auteur documente, pas un essai de son logiciel.
- **Proposé** : conception originale à implémenter et à réceptionner ; aucun coefficient, score ou mouvement privé d’Aimlabs n’en est déduit.
- **Non accessible / non vérifié** : requête refusée ou page absente. Les références héritées de la SPEC restent documentaires et ne sont pas requalifiées en vérifications actuelles.

Les sites Aimlabs, sa page Steam et les trois références FPS de la SPEC ont refusé le tunnel du proxy : `curl: (56) CONNECT tunnel failed, response 403`, HTTP applicatif `000`. Ce n’est pas un HTTP 403 délivré par ces sites ; leur contenu n’a pas été reçu. Aucun changement de proxy, domaine miroir ou contournement n’a été tenté. Le dépôt public indépendant de SensitivityMatcher sur GitHub est accessible ; ce n’est pas une copie du site Aimlabs.

**Aucune règle exacte de Gridshot, Microshot, Sixshot, Spidershot, du tracking, du switching ou du chercheur de sensibilité d’Aimlabs n’a pu être confirmée en ligne pendant cette mission.** Les durées, diamètres, distributions, lois de mouvement, formules de score, délais de tir et algorithmes de recommandation de ses variantes restent inconnus ici. Ne pas annoncer une reproduction exacte ni des scores comparables à ses classements. Aucun asset propriétaire n’est récupéré.

## 2. Journal des sources réellement demandées

Toutes les consultations et tentatives ci-dessous datent du **11 octobre 2026, Europe/Paris**. Les requêtes utilisent `curl --location --max-time 25 --connect-timeout 10`, sans exécution de contenu téléchargé ni installation de logiciel tiers.

| ID | URL demandée | Résultat et portée |
|---|---|---|
| R01 | <https://aimlabs.com/> | Tunnel proxy refusé, 403 ; page officielle non consultable. Aucune preuve sur les tâches ou la calibration. |
| R02 | <https://support.aimlabs.com/hc/en-us> | Tunnel proxy refusé, 403 ; existence et contenu de cette route non établis. |
| R03 | <https://store.steampowered.com/app/714010/Aimlabs/> | Tunnel proxy refusé, 403 ; page de distribution non consultable. |
| R04 | <https://totalcsgo.com/commands/myaw> | Tunnel proxy refusé, 403 ; source tierce citée par SPEC §26/S10, non revérifiée. |
| R05 | <https://valorantsensconverter.com/valorant-sensitivity-yaw/> | Tunnel proxy refusé, 403 ; source tierce citée par SPEC §26/S11, non revérifiée. |
| R06 | <https://blog.activision.com/call-of-duty/2019-10/Getting-Started-in-Modern-Warfare-Controls-and-Settings-PC> | Tunnel proxy refusé, 403 ; référence officielle héritée de SPEC §26/S12 pour **Modern Warfare (2019)** seulement. |
| R07 | <https://github.com/KovaaK/SensitivityMatcher> | HTTP 200, dépôt public consulté ; branche annoncée `master`, commit `e77d601e81afa16aefe7f150346ef489525207f0`. |
| R08 | <https://github.com/KovaaK/FPSAimTrainer> | HTTP 404 ; cette piste ne constitue pas une source utilisable sur les exercices de KovaaK’s. |
| R09 | <https://raw.githubusercontent.com/KovaaK/SensitivityMatcher/master/README.md> | HTTP 200, README consulté ; parcours d’import de sensibilité et de mesure d’une rotation décrit. |
| R10 | <https://github.com/KovaaK/SensitivityMatcher/tree/e77d601e81afa16aefe7f150346ef489525207f0/ReleaseAssets> | HTTP 200, arborescence consultée pour identifier les deux documents suivants à révision fixe. |
| R11 | <https://raw.githubusercontent.com/KovaaK/SensitivityMatcher/e77d601e81afa16aefe7f150346ef489525207f0/ReleaseAssets/CustomYawList.ini> | HTTP 200, liste consultée ; entrées distinctes pour des échelles de réglage, notamment Fortnite Slider/Config. **Pas de validation CS2, VALORANT ou Call of Duty dans ce fichier.** |
| R12 | <https://raw.githubusercontent.com/KovaaK/SensitivityMatcher/e77d601e81afa16aefe7f150346ef489525207f0/ReleaseAssets/ReleaseNotes.md> | HTTP 200, notes de version 1.5 consultées ; réglage de départ confortable, mesure physique et visibilité des corrections documentés. |

### Enseignements publics effectivement documentés

R09 propose de choisir le jeu d’origine, saisir sa sensibilité, puis régler le jeu de destination. Il décrit aussi un mode de mesure avec un repère et un tour complet, ainsi qu’une vérification de dérive sur plusieurs tours. **La promesse commerciale de précision du README n’est pas une mesure réalisée ici.**

R12 décrit deux gestes de 180° confortables pour obtenir un point de départ, une calibration CPI et un historique de convergence. Il mentionne le retrait d’un mécanisme automatique jugé trop caché. Cela soutient une proposition pédagogique : importer le réglage connu, rendre les changements explicites et distinguer confort initial, mesure angulaire et comparaison de performances.

Ces documents concernent un outil de correspondance/mesure, **pas une preuve d’un optimum de sensibilité par exercices**, ni le moteur de KovaaK’s. Leur répétiteur et leurs raccourcis agissent dans des jeux tiers ; ne pas les intégrer ou les lancer. AIM/LOCAL doit rester autonome : test dans sa propre fenêtre, règle physique et saisie manuelle dans les menus du jeu tiers, conformément à SPEC §5.7 et §19.

## 3. Matrice des exercices : dépôt actuel et variantes proposées

Les noms Aimlabs ci-dessous servent uniquement de repères de recherche. Les propositions sont des variantes originales du genre, **non des comportements Aimlabs confirmés**. La difficulté doit être explicitement fixe pendant une comparaison et chaque changement mécanique doit modifier la révision/empreinte du scénario.

| Repère demandé | Confirmé dans AIM/LOCAL à `fa5b289` | Proposition originale et mesure utile |
|---|---|---|
| Gridshot | C03 : grille 3×3, **six** sphères actives de 1,2°, remplacement après impact, cellules distinctes. | Ajouter si souhaité une variante distincte à **trois** cibles plus larges, sans renommer silencieusement C03. Choix libre, remplacement de la seule cible touchée, un clic = un tir. Mesurer touches/min, précision, temps entre touches, ratés et trajets. Nombre/taille exacts de Gridshot non vérifiés. |
| Microshot | C02 : une sphère de 0,65°, zone ±4°/±3°, transition minimale 1,4°, remplacée à la touche. Pas de retour obligatoire au centre. | Petit déplacement puis correction fine ; option distincte « centre → cible proche → centre ». Définir si le centre est cliqué ou acquis par maintien. Mesurer premier tir, erreur du clic, acquisition médiane/p95 ; ne pas présenter une mesure d’overshoot comme existante sans détection de trajectoire. |
| Sixshot | C05 : six sphères de 0,7°, dispersion ±16°/±9°, remplacement individuel, difficulté fixe. | Conserver une variante précision multi-cibles : aucune croissance cachée, pas de points sur une cible détruite, exclusion des chevauchements. Distinguer cadence et précision. Aucun diamètre ou multiplicateur de score Aimlabs n’est connu ici. |
| Spidershot | C04 : grands écarts, une sphère de 1,4°, zone ±24°/±10°, transition minimale 14°. Ce n’est pas une alternance structurée centre/périphérie. | Nouvelle variante à phases « acquérir le centre → cible périphérique → revenir ». Tir centre distinct du tir périphérique ; score/performance périphérique séparés pour ne pas gonfler les résultats avec les retours faciles. Position périphérique seedée, taille et visibilité contrôlées. Séquence exacte d’Aimlabs non vérifiée. |
| Tracking fluide | T01 : sinusoïde horizontale, sphère de 2°, amplitude 10,8°, paramètre vitesse 12°/s ; T02/T03/T04 couvrent d’autres axes. | Trajectoire continue et différentiable ; publier amplitude et loi de vitesse. Mesurer fraction du temps sur cible, erreur angulaire moyenne/p95 et pertes de suivi. La vitesse d’une sinusoïde n’est pas constante ; ne pas confondre paramètre et vitesse 3D. |
| Tracking réactif | T05 : allers-retours triangulaires **périodiques**, sphère de 1,8°, paramètre vitesse 26°/s. T06 de la SPEC n’est pas implémenté. | Ajouter une variante avec changements de direction/vitesse seedés et bornés, continuité de position, difficulté fixe, sans téléportations implicites. Mesurer retour sur cible après **chaque virage défini**, en plus du temps sur cible ; la réacquisition actuelle inclut aussi la première acquisition et n’est pas cette nouvelle mesure événementielle. |
| Switching | S01 : quatre sphères de 1,3°, chacune disparaît après un clic réussi ; S02 : quatre mobiles. Le moteur mesure le temps entre touches. | Distinguer « transitions en un tir » du véritable maintien puis changement de cible : variante séparée avec santé ou durée de tenue, cibles mobiles, dégâts intégrés au temps. Mesurer temps de transition hors cible et durée de tenue, pas seulement le nombre de clics. Ne pas assimiler le son continu cosmétique à un système de dégâts. |

### Contrats communs à réceptionner

- **Apparition** : graine, bornes, espacement, durée et règles d’expiration explicites ; pas de cible partiellement hors champ ni derrière un obstacle inattendu. Un changement de difficulté ne peut pas rester dans le même groupe de comparaison.
- **Hitbox** : silhouette visible cohérente avec l’intersection logique ; un tir raté est compté, une cible remplacée ne rapporte jamais deux éliminations.
- **Tracking** : intégrer des secondes et conserver les actions horodatées ; pas de score proportionnel au nombre de frames. Afficher clairement que le maintien du clic est facultatif dans les suivis actuels.
- **Physique** : tir depuis le réticule de la caméra, sans spread, gravité ou recul logique ajouté à la comparaison. Animation de l’arme uniquement visuelle ; aucun déplacement du yaw/pitch ou du point de tir.
- **Feedback** : impact à la cible et flash à la bouche visuellement cohérents ; son arrêté à la pause/focus/menu. Ne pas sacrifier la lisibilité du réticule ou des petites cibles à l’animation.
- **Comparabilité** : scores locaux versionnés, jamais annoncés comme identiques aux scores Aimlabs. Conserver les métriques brutes et la difficulté dans le bilan/export.

## 4. Audit de la calibration existante

Sources lues : `scripts/sensitivity/calibration_service.gd`, `scripts/sensitivity/sensitivity_service.gd`, `scripts/core/main.gd`, `scripts/ui/dashboard.gd`, `scripts/ui/session_panel.gd`, `tests/domain_tests.gd`, `docs/CALIBRATION.md`, `docs/DECISIONS.md` D06–D12 et SPEC §3, §5–9, §15, §19, §26.

### 4.1 Ce qui existe réellement

Le service **compare déjà plusieurs sensibilités sur les mêmes exercices, puis passe à d’autres exercices**. Le problème remonté ne prouve pas l’absence de cette mécanique ; il révèle une compréhension insuffisante du parcours et une difficulté de départ potentiellement inadaptée.

- Protocole 1 : C02, C04, S01, T01, T05 ; vitesses angulaires A = 90 %, B = référence, C = 110 %. Les distances physiques sont `cm_ref / facteur`, pas `cm_ref × facteur`.
- 15 familiarisations : cinq exercices × trois candidats, 8 s chacun, ordre A/B/C fixe pour chaque exercice. Puis 45 passages mesurés : cinq exercices × trois candidats × trois répétitions, 12 s chacun.
- Compte à rebours 2 s, repos minimal 3 s et confort 1–5 par passage ; environ 16 minutes **minimales**, davantage avec les confirmations et les pauses choisies.
- Graine : `graine_calibration + index_exercice × 7919 + (répétition + 1) × 1009`. La familiarisation utilise répétition −1 ; les trois candidats d’un même exercice/répétition partagent la graine. Les répétitions suivantes utilisent d’autres graines.
- Les candidats changent automatiquement avant le passage. Les valeurs numériques restent masquées pendant le protocole ; A/B/C n’est pas un double aveugle.

| Répétition mesurée | Ordre des exercices | Ordre de C02 | Ordre de C04 | Ordre de S01 | Ordre de T01 | Ordre de T05 |
|---|---|---|---|---|---|---|
| 1 | C02 → C04 → S01 → T01 → T05 | ABC | BCA | CAB | ABC | BCA |
| 2 | C04 → S01 → T01 → T05 → C02 | BCA | CAB | ABC | BCA | CAB |
| 3 | S01 → T01 → T05 → C02 → C04 | CAB | ABC | BCA | CAB | ABC |

Chaque candidat occupe une fois chaque position dans les trois passages d’un exercice. L’ordre des exercices **tourne**, mais trois répétitions ne permettent pas à chaque exercice d’occuper chacune des cinq positions. Ce n’est pas un contrebalancement complet de tous les facteurs. La familiarisation commence toujours par A ; son exclusion des scores ne supprime pas tout effet d’apprentissage ultérieur.

Une graine commune ne garantit pas des cibles identiques aux mêmes instants : en clic/switching, les impacts déclenchent les remplacements et les choix du joueur influencent l’état des cibles. Elle contrôle la génération pour un historique d’actions identique, pas un film temporel fixe indépendamment de la performance. Le tracking analytique est mieux apparié temporellement. Ne pas promettre une exposition strictement identique sans protocole adapté.

### 4.2 Mesure, décision et protections

- Clic/transitions : utilité = touches/s × précision² ; suivi : temps sur cible / temps exposé. La médiane de trois essais et la MAD multipliée par 1,4826 sont calculées pour chaque cellule exercice/candidat.
- Normalisation uniquement **au sein de l’exercice**, par sa meilleure médiane. Pondération prédéfinie : polyvalent 20 % chacun ; précision 30/25/20/15/10 % ; suivi 10/10/10/35/35 %.
- L’écart doit dépasser `max(0,03 ; racine(dispersion_meilleur² + dispersion_second²))`. C’est une règle heuristique, **pas un intervalle de confiance, un percentile population ou une preuve causale**.
- Il faut trois essais actifs et valides dans chacune des quinze cellules ; un exercice sans signal bloque le conseil. Une faible séparation conserve la référence et fournit une plage. Un confort médian du meilleur candidat ≤ 2 bloque l’application. Un gagnant au bord propose d’affiner, sans extrapoler.
- Abandon, changement de DPI/FOV/format/input, mauvaise graine/révision, manque d’activité ou instabilité excessive des frames interdisent l’acceptation. Le checkpoint est vérifié en reconstituant le plan ; l’acceptation et la sauvegarde ne doivent avancer qu’une fois.

Ces garde-fous doivent survivre à la refonte pédagogique. Trois essais restent peu nombreux ; confirmer un conseil lors d’une autre séance et dans le jeu réel. La médiane globale de confort peut masquer une douleur ponctuelle : prévoir un arrêt explicite « gêne/douleur » plutôt que déduire l’absence de douleur d’une moyenne favorable.

### 4.3 Pourquoi l’utilisateur ne le voit pas

1. **Réglage courant peu identifiable** : badge « DPI · nombre » sans unité de jeu évidente, ouvrant la calibration ; champ modifiable « Sensibilité AIM/LOCAL » enfoui dans les paramètres avancés. Le parcours « je connais ma sensibilité VALORANT » est absent.
2. **Conversion seulement sortante** : la page calcule une valeur à recopier à partir du profil actuel ; aucun formulaire jeu d’origine + sensibilité → profil utilisé pour jouer.
3. **Début long et mal contextualisé** : quinze familiarisations avant le premier essai mesuré. L’écran présente « passage n/60 », mais pas « exercice 2/5, comparaison 1/3, réglage testé 2/3 ».
4. **Comparaison invisible pendant les blocs** : les détails A/B/C sont repliés, le HUD ne donne pas une explication claire du changement automatique. La nouvelle sensibilité ressemble à un résultat détaché des exercices.
5. **Aperçu et jeu différents** : les vignettes sont illustratives et reframent les cibles ; elles ne garantissent pas leur taille réelle à l’écran. Une petite cible vue de loin est alors ressentie comme un défaut de placement.

## 5. Proposition pédagogique, sans perdre les contrôles expérimentaux

### Strate A — Rendre visible le protocole 1, sans le changer

Priorité : ajouter une carte permanente **« Sensibilité utilisée ici : … »**, éditable depuis l’accueil, l’entraînement et Ma sensibilité. Offrir « J’importe mon jeu » et « Je règle AIM/LOCAL ». Le profil est appliqué explicitement, sauvegardé, puis utilisé au prochain départ ; aucune modification au milieu d’un essai comparatif.

Avant le départ : « Nous essayons trois réglages autour du vôtre. Vous rejouez le même exercice avec chaque réglage. Les premiers passages servent à vous habituer ; les suivants sont comparés. » Montrer cinq compétences avec aperçu, le temps minimal et l’arrêt/reprise.

Pendant la familiarisation : « Découverte · exercice 1/5 · réglage 2/3 · non noté ». Pendant les mesures : **« Comparaison 1/3 · exercice 2/5 · réglage 1/3 »**. Ajouter « Le réglage change automatiquement ; gardez vos DPI ». Montrer un bloc local de trois cases et les blocs suivants plutôt qu’un unique compteur 60.

Après les trois candidats : afficher une comparaison **provisoire limitée à cet exercice**, avec précision/cadence ou temps sur cible, confort et mention « résultat à confirmer après les répétitions ». Garder A/B/C et ne pas révéler un « gagnant » global avant la fin, pour limiter l’effet d’attente. Pas d’application anticipée.

Cette strate respecte les checkpoints/version 1 puisqu’elle ne change ni les graines, ni l’ordre, ni les durées, ni les scores. Le conseil final indique ce qui a aidé et ce qui reste incertain, puis permet « Garder mon réglage », « Appliquer », « Convertir vers mon jeu ».

### Strate B — Option de parcours réellement bloqué par exercice

Si le produit choisit « finir complètement un exercice avant de passer au suivant », créer un **protocole 2**, sans changer silencieusement les checkpoints 1 :

1. Pour un exercice : trois familiarisations A/B/C de 8 s, immédiatement suivies de trois comparaisons de trois candidats de 12 s chacune.
2. Utiliser ABC, BCA, CAB, avec décalage déterministe par exercice ; mêmes graines entre candidats d’une répétition, nouvelles graines entre répétitions/familiarisation.
3. Passer à l’exercice suivant après un bilan de compétence provisoire : « sur cet exercice, voici les compromis ; le conseil final dépend des cinq compétences ».
4. Conserver les 15 familiarisations, 45 essais mesurés, compte à rebours 2 s et repos minimal 3 s. Proposer un repos plus long entre exercices, par exemple 20–30 s : **choix produit à tester**, pas durée scientifique démontrée. Même politique pour tous les candidats, pauses effectives enregistrées.
5. Déterminer l’ordre des exercices par graine et le conserver à la reprise ; varier/counterbalancer cet ordre entre séances de validation. Ne pas changer difficulté, FOV, matériel, objectif ou poids pendant la séance.

Un tel bloc facilite la compréhension et rapproche familiarisation/mesure ; il accroît aussi l’apprentissage spécifique et la fatigue locale. Le contrebalancement des candidats ne supprime pas ces biais. Garder une confirmation différée, une sortie pour fatigue et un résultat prudent. Ne pas réduire à un unique essai parce que l’un des trois scores paraît bon ; ne pas supprimer une mauvaise performance valide pour favoriser le conseil.

L’intégration doit décider explicitement entre A et B. B nécessite version du plan, restauration des anciens checkpoints ou refus explicite avec possibilité de conserver les fichiers, mise à jour des documents et tests d’ordre/reprise. A est un premier jalon à moindre risque.

## 6. Import/conversion : coefficients et confiance

### 6.1 État de vérification au 11 octobre 2026

| Profil | Valeur dans le dépôt | Preuve disponible pendant cette mission | Présentation autorisée |
|---|---|---|---|
| Counter-Strike 2, hipfire | 0,022 degré/count/unité, éditable | SPEC S10 renvoie à Total CS ; R04 inaccessible. Pas de documentation Valve/build ni de test CS2 reçu ici. | **Coefficient documentaire non revérifié** ; demander le `m_yaw` réellement utilisé, montrer l’hypothèse. Ne pas remplacer par une constante supposée issue de CS:GO. |
| VALORANT, hipfire | 0,07 degré/count/unité | SPEC S11, convertisseur tiers ; R05 inaccessible. Aucun contrat officiel Riot ni build actuel testé. | **Coefficient documentaire non revérifié** ; conversion linéaire hipfire seulement, contrôle dans le jeu requis. |
| Call of Duty: Modern Warfare (2019), PC | Aucun préréglage numérique | SPEC S12/R06 : documentation Activision du 25 octobre 2019, inaccessible ici. La SPEC décrit Relative/Legacy, Monitor Distance Coefficient et traitements souris ; ce n’est pas une preuve de yaw. | Profil manuel portant ce **titre précis**, mode et version ; ne pas lui attribuer un yaw par analogie. |
| Autres titres, dont Modern Warfare II (2022), Modern Warfare III (2023), Black Ops 6 (2024), Warzone | Aucun coefficient validé ici | Aucune source de coefficient consultée avec succès, aucun build/mode testé. « Warzone » seul ne suffit pas à définir une version. | **Pas de préréglage automatique Call of Duty générique**. Exiger titre, build, plateforme PC/souris, hipfire/ADS et coefficient connu ou mesure manuelle. ADS/zoom non supportés tant que leur modèle n’est pas vérifié. |

R11 et R12 n’établissent aucun des coefficients CS2/VALORANT/Call of Duty. Les références de la SPEC sont conservées avec leurs niveaux de confiance ; elles ne deviennent pas officielles parce que le calcul numérique réussit. En particulier, aucun coefficient « Call of Duty » universel ne doit être ajouté dans l’interface ou le service.

### 6.2 Contrat d’import proposé

Formulaire simple : **jeu d’origine et mode**, **DPI utilisés dans ce jeu**, **sensibilité**, puis DPI actuellement utilisés dans AIM/LOCAL. Si les DPI sont les mêmes, une case peut éviter la double saisie. Ne pas détecter ou modifier le DPI matériel à l’insu du joueur.

Pour un profil linéaire hipfire validé/documentaire :

```text
cm_source = 914,4 / (DPI_source × yaw_source × sens_source)
sens_AIM_LOCAL = 914,4 / (DPI_actuels × cm_source × 0,022)
sens_destination = 914,4 / (DPI_destination × cm_source × yaw_destination)
```

Conserver la distance canonique en pleine précision, le jeu/mode/source déclarés et le niveau de confiance. Afficher un aperçu « Votre réglage VALORANT devient … dans AIM/LOCAL », puis bouton **Utiliser ce réglage**. Toute modification d’un simple aperçu ne doit pas remplacer silencieusement le profil sauvegardé ou un checkpoint actif.

Exemple numérique **conditionnel aux coefficients ci-dessus**, pas preuve de leur validité in-game : CS2 2,0 à 800 DPI et `m_yaw = 0,022` → 25,977272727273 cm/360 → VALORANT 0,628571428571 à 800 DPI → AIM/LOCAL 2,0. Le rapport inverse est `0,07 / 0,022`, et non le même multiplicateur dans les deux sens. Des DPI source/destination différents nécessitent aussi leur rapport.

La conversion conserve un angle par distance physique ; **pas** une sensation identique à FOV/zoom différents, une vitesse écran ou une balistique. Garder l’original, l’arrondi recopiable et l’erreur d’arrondi. Sans coefficient connu, proposer la mesure physique d’un tour dans le jeu puis saisir les cm dans AIM/LOCAL ; ne pas deviner le yaw.

## 7. Distance ressentie, lisibilité et aperçu

### Diagnostic limité à la lecture du dépôt

La caméra est à `(0, 1,6, 0)` ; le pool affiche les cibles autour du même point à `distance_m = 8`. Les directions et le rayon/sphère sont calculés dans un repère local cohérent. Le rayon est `distance × sin(diamètre_angulaire / 2)`. **Aucun éloignement dynamique du joueur n’a été trouvé dans ce chemin**, mais le problème remonté n’a pas été reproduit sur la machine de l’utilisateur.

Une explication plausible est la taille angulaire : C02 ne fait que 0,65°. Centré, à FOV vertical 75°, son diamètre projeté vaut environ `hauteur_viewport × tan(0,325°) / tan(37,5°)` : **3,3 pixels à 450 px de haut et 5,3 pixels à 720 px**. Une cible aussi petite peut être techniquement visible mais pédagogiquement inadaptée. Le recadrage illustratif des aperçus amplifie la différence ressentie. Cela ne prouve pas une erreur de distance ni un problème de collision.

### Actions proposées au parent

- Ajouter une courte **vérification de visibilité avant calibration** : vraie caméra et vraie taille, trois cibles représentatives, aucun score ; le joueur confirme « Je vois et touche les cibles ». Si non, permettre un profil de difficulté lisible, fixé **avant** la comparaison.
- Ne pas « rapprocher » seulement les meshes : changer la profondeur doit aussi conserver le diamètre angulaire et la cohérence collision/rendu. Si l’on agrandit réellement les cibles, c’est un scénario/révision/contexte différents.
- Tester diamètre projeté, position de caméra, aspect, FOV et possibles recouvrements par le HUD/sprite. Ne pas imposer une taille minimale en pixels qui change silencieusement la difficulté d’un même test selon la résolution.
- Au survol **ou focus clavier**, ouvrir un panneau ancré à la carte : titre, animation originale du scénario, description d’une phrase et instruction « clic »/« suivre ». Au clic, conserver le panneau sélectionné et son départ explicite. Ce n’est pas une vidéo Aimlabs.
- Prévoir fermeture au changement de page/filtre et panneau toujours dans les limites de la fenêtre ; une seule animation active, arrêt hors visibilité et respect du mode mouvement réduit. Le popup ne doit pas capter un clic de tir destiné à la sélection.
- Les pages peuvent utiliser des colonnes proportionnelles à la largeur disponible plutôt qu’un formulaire central limité à 1 200 px. L’aperçu peut occuper la seconde colonne ; conserver une largeur de lecture raisonnable et les actions visibles en petite fenêtre, sans remplir les marges de texte inutile.

## 8. Risques et tests de réception à intégrer

Les tests ci-dessous sont des **critères proposés**, pas des exécutions annoncées. Les agents QA peuvent simuler états/actions, comparer les replays et inspecter des rendus ; ils ne remplacent pas une souris réelle ou un joueur découvrant le produit.

| ID | Vérification concrète | Résultat attendu |
|---|---|---|
| QA-01 | Depuis accueil puis entraînement, retrouver et éditer le réglage sans ouvrir « avancé ». | Valeur nommée « Sensibilité AIM/LOCAL », DPI et jeu de départ identifiables ; application/sauvegarde explicites. Test utilisateur : il explique le réglage actif sans aide. |
| QA-02 | Importer CS2 2/800 avec yaw 0,022, puis VALORANT 0,628571428571/800 ; exporter en sens inverse. | Même cm canonique, même rotation synthétique ; aller-retour sans accumulation d’arrondis. Tolérance mathématique documentée. Cela ne confirme pas les coefficients tiers. |
| QA-03 | Refaire QA-02 avec DPI source 800 et actuels/destination 1 600 ; saisir virgule décimale, zéro, négatif, NaN, infini et cm hors 5–150. | DPI distincts traités correctement, entrée française valide ; erreurs explicites pour invalides/hors limites, ni clamp muet ni écrasement du profil. |
| QA-04 | Sélectionner « Call of Duty » sans titre/build/mode et sans coefficient. | Aucun résultat automatique fondé sur un yaw générique ; guider vers profil manuel/mesure, ADS non annoncé exact. |
| QA-05 | Simuler les 60 passages, vérifier cellules, ordres, graines et familiarisations. | Exactement 15 non notés et 45 notés, trois essais par cellule ; chaque candidat une fois par position ; affichage bloc/exercice/répétition cohérent avec le plan réel. |
| QA-06 | Reprendre un checkpoint, invalider un essai, provoquer un échec de sauvegarde et double-cliquer Continuer. | Même candidat/graine répétés après invalidation ; aucune acceptation perdue ou doublée, aucune nouvelle difficulté ; changement de protocole traité explicitement. |
| QA-07 | Injecter égalité, scores nuls, dispersion forte, meilleur au bord, confort ≤ 2, puis demande d’arrêt pour douleur. | Conserver référence/plage quand incertain ou insuffisant, pas d’application anticipée, affinage seulement vers un réglage testé ; arrêt immédiat disponible. |
| QA-08 | Rejouer les mêmes actions horodatées à 60/144/240 FPS et avec découpage différent des frames. | Même score/mesures logiques dans les tolérances, pauses sans crédit, ni temps de rendu ni cadence du sprite utilisés dans le score. |
| QA-09 | Comparer rayons juste dedans/dehors, rendu et diamètre projeté à 8 puis 20 m, plusieurs FOV/aspects ; démarrer après un précédent exercice. | Même diamètre angulaire à profondeur différente, impacts cohérents avec la silhouette, caméra réinitialisée au repère prévu ; aucune cible involontairement inaccessible. |
| QA-10 | Afficher calibration et exercices à 800×450, 1 280×720 et 1 920×1 080 ; montrer leur vraie taille avant départ. | Cibles de référence lisibles, confirmation de visibilité, changement de difficulté visible/versionné ; HUD/sprite ne masquent pas cible/réticule. Vérifier les marges visuellement, pas seulement l’absence de débordement. |
| QA-11 | Survoler/focaliser rapidement dix cartes, filtrer, quitter la page, activer mouvement réduit. | Bon titre/description/aperçu, panneau dans la fenêtre, pas d’accumulation de nœuds, une seule animation active ; clic et navigation clavier restent utilisables. |
| QA-12 | Tir unique, maintien en suivi, pause/focus/menu, changement d’arme/volume. | Impacts et animation visuelle perceptibles ; aucune dérive caméra, aucun gain de score via animation/son, arrêt des sons à la sortie. Écoute réelle à réceptionner séparément. |
| QA-13 | Si ajout de variantes : simuler cycle centre/périphérie, virages réactifs et cible à santé multiple. | Phases/identités/événements distincts, position continue aux virages, durée/dégâts indépendants des FPS ; mesures ne prétendent pas reprendre les formules Aimlabs. |
| QA-14 | Deux séances de calibration espacées, avec ordre d’exercices et pauses conservés dans les résultats. | Comparer stabilité et confort plutôt que promettre un optimum ; expliquer un conseil divergent. Confirmation dans le FPS réel effectuée et consignée par le joueur, pas simulée par un bot. |

### Jalons recommandés pour le parent

1. **Import + réglage courant** : QA-01 à QA-04, sans toucher le scoring. C’est la lacune fonctionnelle la plus visible.
2. **Visibilité de l’arène + pédagogie du protocole 1** : QA-05 à QA-10 ; reproduire le signalement de distance avant de retuner les scénarios.
3. **Aperçus contextualisés + feedback d’arme** : QA-11/12, contrôle des FPS et absence d’effet mécanique.
4. **Nouvelles mécaniques / protocole 2 seulement si retenu** : QA-06/13/14, versions et migration explicites ; aucune promesse de parité avec Aimlabs.

## 9. Vérifications effectivement exécutées et intégration

- Lecture des instructions `AGENTS.md`, de `docs/DECISIONS.md`, du protocole `docs/CALIBRATION.md` et des sections pertinentes de la SPEC ; audit du service, du parcours UI, des scénarios, de la géométrie et des tests existants.
- Douze requêtes `curl` : cinq HTTP 200, six tunnels refusés par le proxy, une page HTTP 404. Leur résultat est détaillé au §2. Aucun contenu de site refusé n’a été consulté.
- `bash tools/test.sh` avec Godot **4.7.2 standard** : **797 assertions, 0 échec, 1 contrôle non exécuté**. Le contrôle non exécuté est la capture réelle du pointeur en headless. Cette suite couvre l’implémentation existante ; elle ne démontre pas que les propositions QA ci-dessus sont réalisées.
- Calculs de référence indépendants avec `awk` : exemple CS2→VALORANT conditionnel et diamètre projeté C02 à hauteurs 450/720, présentés au §6/7.
- `git diff --check` et vérification du nouveau Markdown avec `git diff --no-index --check /dev/null docs/REFERENCE_TASKS.md` : aucune anomalie d’espaces détectée. Le second appel peut retourner 1 parce que le fichier est nouveau, sans diagnostic d’erreur.

Une seconde passe, après apparition des modifications des agents en parallèle, a exécuté `bash tools/godot.sh --headless --editor --import` sans erreur de script dans le journal, puis `bash tools/test.sh`. **Cette relance n’est pas verte** : `tests/sensitivity_import_tests.gd:30` et `tests/sensitivity_import_tests.gd:53` signalent l’impossibilité d’inférer le type des variables `altered` et `reloaded`, empêchant la compilation du lanceur. La suite termine avec code 1 après son garde-fou de 90 s. Ces fichiers sont hors périmètre et n’ont pas été modifiés par cette mission. Le parent doit corriger/vérifier leur typage puis relancer la suite intégrée ; les 797 assertions précédentes ne valident pas l’ensemble des changements concurrents.

**Non exécutés** : mesure HID/DPI réelle, écoute humaine, tests natifs Windows, essai d’Aimlabs/KovaaK’s, confirmation physique dans CS2/VALORANT/Call of Duty, nouvelle validation graphique ou test utilisateur. Aucune formule propriétaire n’est connue ou déduite.

**Seul fichier écrit par cette mission : `docs/REFERENCE_TASKS.md`.** Aucun code, scénario, autre documentation, téléchargement Windows, branche, worktree, commit ou push n’est modifié/créé par cette mission. Les besoins d’intégration sont les quatre jalons ci-dessus ; le parent arbitre le protocole et réalise les changements dans ses périmètres.
