# AIM/LOCAL — Cahier des charges et plan de réalisation d’un aim trainer FPS sur Windows

> **Catalogue et calibration actuels : V2.** Consulter le [guide d’implémentation V2](EXERCICES_ET_CALIBRATION_V2.markdown), le [plan de réception V2](TEST_PLAN_V2.md) et le [cahier V2 original](reference/v2/AIM_LOCAL_SPECIFICATIONS_V2.md). Le cahier V1 ci-dessous reste conservé pour l’historique ; le kit V2 original reste inchangé.

**Version du document :** 1.0 — 11 octobre 2026  
**Statut :** spécification de référence, destinée à être utilisée avec ChatGPT et Codex  
**Nom de travail :** AIM/LOCAL (nom à confirmer avant publication)  
**Plateforme prioritaire :** Windows 10/11, x86-64, souris et clavier  
**Type :** application 3D native, hors ligne, distribuable sous forme d’exécutable Windows  
**Approche :** prototype court → cœur de gameplay fiable → contenu → mesure de progression → distribution

> **Principe directeur.** AIM/LOCAL n’est pas une copie visuelle d’Aim Lab : c’est un outil original, simple et réactif, destiné à exercer la précision à la souris. La qualité du produit dépend d’abord de la fidélité de l’input, de la conception des scénarios et de la fiabilité de la mesure ; pas de la sophistication des graphismes.

---

## Sommaire

| Chapitres pairs (0, 2, 4…) | Chapitres impairs (1, 3, 5…) |
|---|---|
| [0. Décisions de conception — à lire avant de développer](#chapitre-0) | [1. Vision, objectifs et limites du produit](#chapitre-1) |
| [2. Choix technologiques : pourquoi Godot, et quelles alternatives ?](#chapitre-2) | [3. Parcours de l’utilisateur et écrans](#chapitre-3) |
| [4. Fidélité de la souris : le chantier critique](#chapitre-4) | [5. Sensibilité : modèle mathématique, conversion et limites](#chapitre-5) |
| [6. Assistant de recherche d’une sensibilité adaptée](#chapitre-6) | [7. Catalogue d’exercices : couverture complète, développement progressif](#chapitre-7) |
| [8. Génération des cibles, hitboxes et simulation](#chapitre-8) | [9. Scoring : mesurer l’amélioration et éviter les faux progrès](#chapitre-9) |
| [10. Routines, temps de repos et progression](#chapitre-10) | [11. Architecture fonctionnelle — séparation des responsabilités](#chapitre-11) |
| [12. Formats de données et persistance](#chapitre-12) | [13. Direction artistique : 3D flat, minimaliste et utile](#chapitre-13) |
| [14. Performance, latence et instrumentation](#chapitre-14) | [15. Validation : tests automatiques, manuels et critères de qualité](#chapitre-15) |
| [16. Distribution sous Windows : de Godot à un `.exe`](#chapitre-16) | [17. Développer le projet avec ChatGPT et Codex : méthode concrète](#chapitre-17) |
| [18. Connecteurs, MCP et services externes : faut-il en installer ?](#chapitre-18) | [19. Licence, sécurité et respect des jeux tiers](#chapitre-19) |
| [20. Roadmap : développement par livrables vérifiables](#chapitre-20) | [21. Backlog priorisé — exigences traçables](#chapitre-21) |
| [22. Risques, erreurs courantes et décisions de mitigation](#chapitre-22) | [23. Prompts prêts à utiliser avec Codex](#chapitre-23) |
| [24. Fichier `AGENTS.md` minimal — exemple à donner à Codex](#chapitre-24) | [25. Scénario de réception : comment savoir que le projet est réellement réussi ?](#chapitre-25) |
| [26. Sources vérifiées et statut des informations](#chapitre-26) | [27. Recommandation finale de cadrage](#chapitre-27) |

---

<a id="chapitre-0"></a>

## 0. Décisions de conception — à lire avant de développer

| Sujet | Décision recommandée | Justification |
|---|---|---|
| Moteur | **Godot 4.7.2 stable ou correctif stable 4.7.x ultérieur vérifié**, édition standard, **GDScript** | Gratuit, code ouvert, scène 3D légère, UI et export Windows accessibles. Godot 4.7.2 corrige en particulier un problème de souris à 2–8 kHz sous Windows [S1]. |
| Rendu | **3D flat**, couleurs pleines, géométrie basique, renderer **Compatibility** en première intention, à comparer au renderer Mobile par benchmark | Maximum de lisibilité et peu de dépendances GPU ; choisir sur mesure, pas sur intuition [S2]. |
| Input | Souris **capturée en entraînement**, mouvement `screen_relative`, tests de raw input Windows, accumulation configurable/mesurée | Évite les écarts dus au scaling de la fenêtre ; priorité au mouvement reproductible [S3–S5]. |
| Sensibilité | Modèle interne unique en **degrés de caméra par count souris** + `cm/360` | Unité physique explicite pour les conversions validées. |
| Scénarios | **Définis par des données** (`.tres`/JSON validé) et joués par un moteur commun | Ajouter 30 exercices ne doit pas impliquer 30 moteurs de jeu différents. |
| Statistiques | Données brutes de performance + scores **versionnés** ; comparaisons à difficulté constante | Des scores sans contexte induiraient des conclusions trompeuses. |
| Stockage | D’abord **local**, `user://`, JSON versionné + export CSV ; SQLite seulement si le volume le justifie | Pas de compte, serveur, cloud ou base externe nécessaires au lancement [S6]. |
| Distribution | Export Windows x86-64 en **`.exe`** + éventuel `.pck`, empaquetés en `.zip` | Facile à envoyer et à utiliser sans Godot installé [S7]. |
| Développement IA | **ChatGPT** pour cadrage/revue, **Codex** sur un dépôt local Git pour écrire, exécuter, tester et corriger | Travail itératif vérifiable, plutôt qu’un prompt unique « fais tout ». |
| MCP/connecteurs | **Aucun obligatoire**. GitHub utile plus tard pour le dépôt, les issues, la CI et les releases. | Les MCP ne remplacent ni le moteur de jeu, ni les tests à la souris. |

**À ne pas promettre :** aucune formule ne peut identifier universellement « la meilleure sensibilité » d’un joueur ; un même `cm/360` n’assure pas une perception identique dans deux jeux dont les FOV, zooms, animations, distances et comportements de caméra diffèrent ; un exécutable d’entraînement ne peut pas garantir le transfert des performances vers un FPS compétitif. Le produit doit **mesurer, aider à choisir et expliquer les limites**, pas fabriquer une précision illusoire.

**Configuration du poste envisagé :** Ryzen 7 7800X3D et Radeon RX 7900 XT : largement adaptée au prototypage. Ne pas en déduire que l’application tournera pareil sur un PC portable ou avec une souris 8 000 Hz ; prévoir des essais matériels variés.

---

<a id="chapitre-1"></a>

## 1. Vision, objectifs et limites du produit

### 1.1 Objectif principal

Créer un programme Windows que l’on ouvre, configure en moins de deux minutes et lance immédiatement pour améliorer des habiletés utiles aux FPS : placement du viseur, acquisition de cible, micro-ajustements, précision de clic, suivi de mouvement, transition entre cibles et contrôle lors des déplacements.

Le produit doit permettre de répondre à quatre questions :

1. **Sur quoi dois-je travailler ?** Exemple : je touche les grosses cibles, mais je surcorrige les petits flicks.
2. **Quel exercice effectuer ?** Une routine ciblée, courte et sans configuration pénible.
3. **Comment progresse ma régularité ?** Comparaisons sur 7/30 jours à scénario identique.
4. **Mon réglage souris reste-t-il cohérent avec mon jeu principal ?** Fiche DPI, sensibilité, FOV, ADS et distance `cm/360`, avec niveau de confiance.

### 1.2 Principes d’expérience utilisateur

- **Lancement rapide :** démarrer une séance récente en deux actions maximum depuis l’accueil.
- **Lisibilité maximale :** une cible se détache toujours du fond, même en mouvement ; pas de textures distrayantes.
- **Aucun compte requis :** le programme fonctionne intégralement sans Internet.
- **Sensibilité prévisible :** pas d’accélération/smoothing caché ajouté par l’application.
- **Répétition contrôlée :** on peut rejouer une configuration précise, avec une graine aléatoire connue.
- **Scores explicables :** le joueur voit le nombre de touches, la précision et les temps, pas seulement un nombre abstrait.
- **Ergonomie clavier/souris :** Escape met en pause, libère le pointeur et permet de revenir au menu.
- **Respect de la fatigue :** pauses facultatives, séances courtes, fin de séance claire ; aucun mécanisme culpabilisant.

### 1.3 Hors périmètre initial

- Multiplayer, matchmaking et classements mondiaux.
- Publicité, monétisation, création de compte et télémétrie distante.
- Images réalistes, personnages détaillés, armes authentiques, ballistique complexe.
- Superposition / injection de DLL dans Valorant, CS2, Call of Duty ou leurs processus ; interaction avec anti-cheat.
- Écriture automatique non vérifiée dans les configurations des jeux.
- « Diagnostic médical », estimation de capacités cognitives ou garantie de gain de rang en jeu.

### 1.4 Définition de « terminé »

Un **produit utilisable** doit : démarrer via son `.exe`, fonctionner hors ligne, offrir des exercices de clic et de tracking solides, maintenir un input stable, conserver les résultats, convertir au minimum CS2 ↔ Valorant sous hypothèses affichées, afficher une progression et permettre des routines avec pauses. Une longue liste de modes non testés ne remplace pas ces bases.

---

<a id="chapitre-2"></a>

## 2. Choix technologiques : pourquoi Godot, et quelles alternatives ?

### 2.1 Comparatif rapide

| Solution | Atouts | Risques/coûts | Verdict |
|---|---|---|---|
| **Godot 4.7.2 + GDScript** | Projet léger ; 3D + UI intégrées ; export Windows ; développement itératif simple ; licence MIT ; input Windows amélioré | Il faut valider expérimentalement le chemin d’entrée, le timing et le rendu sur plusieurs configurations | **Recommandation principale** |
| Godot + C# | Typage robuste et bibliothèques .NET | Pipeline d’export/SDK et complexité supplémentaires | Option si le projet grossit et si les tests le justifient |
| Unity + C# | Écosystème abondant et outils mûrs | Environnement et dépendances plus volumineux ; configuration du système d’input à auditer | Alternative possible, non nécessaire |
| Unreal Engine | Excellentes capacités 3D | Plus lourd que nécessaire pour des cibles abstraites | À écarter pour ce cahier des charges |
| C++ / SDL3 / rendu personnalisé | Contrôle fin de l’input et du timing | Bien plus de travail sur la caméra, l’UI, les tests et la distribution | Plan B **uniquement** si les mesures montrent un problème structurel non corrigeable dans Godot [S8] |

**Règle :** ne pas commencer par une architecture native C++ « pour faire pro ». Si la fidélité mesurée de Godot est suffisante, conserver le moteur simple. Si elle ne l’est pas, isoler l’input derrière une interface et remplacer seulement cette partie, éventuellement par une extension native, plutôt que réécrire le jeu.

### 2.2 Versions et dépendances

**Indispensables sur le poste de développement :**

- Windows 10/11 x64 ; pilotes de la carte graphique à jour ; souris avec DPI réglable ; un écran dont le taux de rafraîchissement est connu.
- Godot **4.7.2 stable** (ou une version stable ultérieure testée) et les **export templates** correspondant exactement à sa version.
- Git pour l’historique et les retours arrière.
- Codex dans un environnement ayant accès au dossier du projet, au terminal et à Godot ; VS Code en complément facultatif.

**Facultatifs :**

- GdUnit4 pour les tests d’intégration/Unit Godot, après vérification de compatibilité exacte avec la version retenue [S9].
- GitHub pour héberger le dépôt, lancer GitHub Actions et publier un `.zip`.
- Un outil de capture vidéo 120/240 fps, un écran à haute fréquence et, idéalement, une caméra haute vitesse pour des mesures matérielles de latence ; l’overlay interne seul **ne mesure pas** la latence physique de bout en bout.
- SQLite via bibliothèque/extension validée, **pas avant** d’avoir rencontré des limites réelles avec le format local.

**À éviter au MVP :** Firebase, Supabase, serveur Node.js, compte cloud, microservices, lecteur de DPI constructeur, gestionnaire de pilotes, overlay en jeu, réseau permanent, moteur physique surdimensionné, machine learning présenté comme nécessaire.

### 2.3 Politique sur les plugins

Chaque plugin doit avoir : auteur identifié, version compatible, licence vérifiée, nécessité argumentée, tests d’export Windows et stratégie de retrait. Éviter les plugins communautaires qui réclament des droits d’exécution système sans justification.

---

<a id="chapitre-3"></a>

## 3. Parcours de l’utilisateur et écrans

### 3.1 Premier démarrage (assistant de configuration)

**Écran 1 — Matériel :** indiquer DPI réel/nominal de la souris (ex. 800 ou 1600), polling rate déclaré (125/500/1000/2000/4000/8000 Hz), fréquence du moniteur, résolution, format d’écran, main dominante si utile. **Ne jamais inventer le DPI par détection automatique** : les API Windows classiques ne révèlent pas de façon fiable le palier DPI configuré dans tous les logiciels fabricants.

**Écran 2 — Jeu de référence :** sélectionner « CS2 », « Valorant », « Call of Duty (version exacte) », « autre jeu » ou « réglage manuel » ; indiquer la sensibilité et, si applicable, le FOV, la résolution/aspect ratio, l’ADS et les options d’accélération ou de smoothing.

**Écran 3 — Vérification :** afficher `cm/360°` estimé, la rotation attendue pour 10 cm, et une scène d’essai. Proposer **mesure physique à la règle** : déplacer la souris d’une distance connue, comparer l’angle mesuré et l’angle calculé, puis enregistrer un résultat de validation. La mesure doit distinguer « problème de DPI réel », « paramètre erroné », « compensation logicielle » et « imprécision du geste ».

**Écran 4 — Essai court :** 30 s de cibles statiques puis 30 s de tracking ; enregistrer la première référence sans la présenter comme un classement définitif.

### 3.2 Accueil

Composition textuelle suggérée :

```text
AIM/LOCAL        Profil : CS2 • 800 DPI • 25,98 cm/360°           [Paramètres]

[ DÉMARRER LA ROUTINE DU JOUR ]    [ Reprendre le dernier exercice ]

Aujourd'hui          Dernières séances         Exercices recommandés
12 min entraînées    Précision : 83 %          Microshot / Tracking lisse

[ Exercices ] [ Routines ] [ Sensibilité ] [ Progression ] [ Profils ]
```

Informations visibles **sans surcharger** : dernier FPS, sensibilité actuelle, profil de référence, progression récente, accès au bouton principal.

### 3.3 Bibliothèque d’exercices

- Recherche par nom et filtres : clic, précision, tracking, switching, mouvement, difficulté, durée.
- Chaque fiche affiche : objectif, nombre de cibles, taille angulaire, vitesse, durée, arme simulée éventuelle, mesures évaluées, record personnel sous la même configuration.
- Actions : **Lancer**, **Personnaliser**, **Ajouter à une routine**, **Dupliquer**.
- Présets officiels/standards verrouillés séparés des variantes personnalisées : leurs classements locaux ne sont pas mélangés.

### 3.4 Pendant l’entraînement

- En jeu : viseur central, cibles nettement visibles, chronomètre, touches/ratés, taux de précision, barre de progression et éventuellement une seule indication de coaching.
- Options : afficher/masquer toutes les statistiques, son toucher/rater, couleur cible/fond, taille viseur, bouton pause.
- Compte à rebours 3–2–1 configurable et **période de préparation exclue des statistiques**.
- Pause : horloge **figée**, souris libérée, reprise avec court compte à rebours. Perte de focus = pause automatique (configurable, activée par défaut).
- Fin : freeze clair, score, meilleurs indicateurs, évolution par rapport à la médiane historique à scénario comparable, « refaire » / « suivant ».

### 3.5 Sensibilité / profils / progression

**Sensibilité :** import manuel, conversion, comparaison `cm/360`, validation physique, sauvegarde de profils ; bouton « copier la valeur » et instructions pour la renseigner dans chaque jeu.  
**Progression :** courbes 7/30/90 jours, record, médiane/percentiles, stabilité, volume d’entraînement, comparaison à configuration identique ; afficher les changements de sensibilité comme événements.  
**Profils :** plusieurs jeux et plusieurs ensembles de paramètres de souris ; un profil actif à la fois, sans perdre l’historique.

---

<a id="chapitre-4"></a>

## 4. Fidélité de la souris : le chantier critique

### 4.1 Ce qui entre réellement dans l’application

Parcours simplifié :

```text
Capteur et firmware souris
      ↓ (counts + boutons, fréquence variable)
Windows / couche HID / messages raw input
      ↓
Godot, souris capturée + événements de mouvement
      ↓
InputSampler → mouvement angulaire (yaw / pitch)
      ↓
Caméra logique / rendu / test de collision
      ↓
Frame réellement affichée sur le moniteur
```

Il faut distinguer :

- **DPI/CPI nominal** : counts annoncés par pouce parcouru (1 pouce = 2,54 cm). Le DPI réel peut légèrement différer du chiffre configuré.
- **Polling rate** : nombre maximal de rapports transmis par seconde, pas une garantie de fréquence constante pendant tous les mouvements.
- **Raw input** : mouvements relatifs avant la transformation normale du curseur Windows ; ne signifie pas absence de tous traitements éventuels par le capteur/firmware.
- **Sensibilité du jeu** : transformation des counts en rotation angulaire.
- **FOV et ratio** : projection d’une rotation donnée sur l’écran, donc perception visuelle.
- **Latence** : durée entre mouvement/clic et effet affiché ; dépend aussi du système, du moteur, du GPU et de l’écran.

### 4.2 Chemin Godot recommandé

Sous Windows, exploiter le mode souris capturée et **`InputEventMouseMotion.screen_relative`**, qui est préférable à `relative` pour éviter le changement d’échelle lié à la fenêtre [S3]. Godot utilise un chemin de raw input Windows en capture ; son traitement des souris à haute fréquence a été amélioré à partir de 4.7.2 [S1, S4, S5].

**Principes d’implémentation :**

1. `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` dès l’entrée dans une épreuve.
2. Lire **`event.screen_relative`**, pas `event.position`, qui représente le centre en capture.
3. Ne pas multiplier le mouvement par `delta`/FPS : un événement représente déjà une quantité de mouvement. **Un facteur de temps supplémentaire serait un bug.**
4. Convertir counts → degrés avec le multiplicateur explicite de la caméra ; sans courbe d’accélération, ni lissage implicite.
5. Mettre à jour la caméra d’entraînement avec le moins de délais possible ; distinguer caméra logique, simulation des cibles et rendu.
6. Mesurer deux configurations d’accumulation de Godot : `Input.use_accumulated_input = true` (événements fusionnés par frame) et `false` (événements plus fréquents). Sélectionner le défaut après tests de latence **et** de charge CPU à 1/4/8 kHz ; ne pas affirmer que `false` est systématiquement meilleur [S3, S5].
7. Garder `_input()` extrêmement léger : aucune écriture disque, calcul statistique coûteux, allocation répétée ou recherche de nœuds pour chaque événement.
8. À la sortie/pause/perte de focus : libérer la souris (`MOUSE_MODE_VISIBLE`) et ignorer les deltas parasites de recentrage et de reprise.

**Pseudo-code à adapter à Godot 4.7.2, non présenté comme un script prêt à copier sans tests :**

```gdscript
# Contrat de l'InputSampler, exemple illustratif
func on_mouse_motion(screen_relative: Vector2) -> void:
    if not training_active or not window_has_focus:
        return
    yaw_degrees   -= screen_relative.x * degrees_per_count_x
    pitch_degrees -= screen_relative.y * degrees_per_count_y
    pitch_degrees = clampf(pitch_degrees, min_pitch, max_pitch)
    # Ne PAS multiplier par le frame delta.
    # Appliquer la rotation selon la convention des axes validée par des tests.
```

La convention de signe et d’orientation **doit être testée** sur la scène 3D (gauche/droite, haut/bas, pitch inversé et limites). Dans Godot, les angles natifs des rotations utilisent souvent des radians : centraliser la conversion et ne jamais mélanger degrés/radians.

### 4.3 Input sampler : spécification

Construire un composant isolé qui reçoit des événements et expose :

- `mouse_delta_counts_x/y` (sur Windows en mode capture, à valider par le test de counts) ;
- `logical_yaw/pitch` ;
- `last_event_time_monotonic_us` et `input_sequence_number` ;
- clic gauche/droit, press/release, perte de focus ;
- cumul des mouvements, sans appliquer deux fois le même événement ;
- compteur d’événements par seconde observé, **sans l’assimiler automatiquement au polling rate matériel**.

Enregistrer les événements détaillés seulement lors d’un **mode diagnostic/replay optionnel** pour éviter de produire d’énormes fichiers à 8 kHz.

### 4.4 Simulation, cible et rendu : trois temps différents

- **Input** : recevoir les mouvements dès que possible, hors file de traitement coûteuse.
- **Simulation** : déplacer les cibles selon une horloge monotone, avec lois déterministes ; la vitesse ne doit pas dépendre du FPS.
- **Rendu** : interpoler les positions animées si nécessaire pour la fluidité, mais ne pas rendre une cible à une position nettement différente de celle prise en compte par la détection des touches.

**Point délicat :** pour un tir sur cible mobile, il faut définir **quelle position de la cible est utilisée au moment du clic**. Le simple fait d’utiliser un raycast physique au tick suivant peut fausser les tirs rapides. Pour des sphères simples, envisager un **test analytique rayon–sphère** dans un module léger avec snapshot cohérent de la pose de la cible. Documenter si cette pose correspond au temps d’input, au temps de simulation ou à la pose interpolée rendue. Ce choix doit être testé au ralenti et sur cible rapide.

### 4.5 Tests de vérité indispensables

| ID | Expérience | Résultat attendu |
|---|---|---|
| IN-01 | Injecter 1 000 counts positifs horizontaux, à différentes répartitions dans le temps | Même rotation finale à sensibilité constante ; erreur de cumul quasi nulle |
| IN-02 | Rejouer la même séquence à 60, 144 et 240 FPS | Rotation totale identique ; timing/visuel évalué séparément |
| IN-03 | Changer résolution, mode fenêtré, fullscreen et scaling Windows | Pas de changement de sensibilité angulaire brute |
| IN-04 | Comparer souris 500/1000/4000/8000 Hz | Aucun blocage ni effondrement massif du FPS ; pas d’événements perdus dans le test de référence |
| IN-05 | Déplacer physiquement la souris de 10 cm dans 5 répétitions | Rotation approximativement conforme au `cm/360` annoncé, tolérance mesurée et expliquée |
| IN-06 | Alt+Tab, Esc, reprise, changement d’écran | Pas de rotation parasite ; pointeur récupérable ; score en pause |
| IN-07 | Vérifier absence de smoothing/accélération involontaires | Même rotation finale pour une même quantité de counts, mouvements lent/rapide |
| IN-08 | Tester déplacement et clic très rapprochés | Ordre des événements respecté ; pas de clic enregistré sur la mauvaise cible |

**Seuil d’acceptation initial :** 0 événement de mouvement « oublié » dans les tests de séquences synthétiques ; écart de rotation numérique < 0,1 % sur une séquence déterministe ; la tolérance d’un test **physique manuel** doit être plus large et documentée, car la règle et le geste sont imparfaits. Ces seuils sont des **objectifs de conception**, pas des performances déjà mesurées.

### 4.6 Si le comportement Godot n’est pas suffisant

**Plan d’escalade :** reproduction minimale → profilage → essai 4.7.x stable corrigé → isolation d’un module `InputBackend` → éventuelle extension native Windows utilisant `WM_INPUT` et, si nécessaire, la lecture tamponnée `GetRawInputBuffer` [S4]. Ne jamais écouter/altérer l’input d’un jeu tiers en parallèle : l’application mesure seulement ce qui se passe **dans sa fenêtre**.

---

<a id="chapitre-5"></a>

## 5. Sensibilité : modèle mathématique, conversion et limites

### 5.1 Unités canoniques

Le moteur ne raisonne **pas** d’abord en « sensibilité 0,4 » (nombre qui varie selon le jeu). Il stocke :

- `dpi`: counts annoncés par pouce ;
- `yaw_coefficient_deg_per_count_per_sens_unit`: facteur horizontal natif du profil de jeu ;
- `sensitivity`: multiplicateur in-game ;
- `degrees_per_count_x = yaw_coefficient × sensitivity` ;
- `cm_per_360 = (360 × 2,54) / (dpi × degrees_per_count_x)` ;
- des propriétés **séparées** pour pitch/Y, zoom/ADS, FOV et éventuelle accélération.

Pour une même distance physique et un capteur stable, la rotation visée vaut :

```text
counts_par_cm ≈ DPI / 2,54
degres_par_cm = (DPI / 2,54) × yaw_coefficient × sensitivity
cm_par_360 = 360 / degres_par_cm
```

Ces équations supposent une réponse angulaire **linéaire** à l’input, en mode hipfire et selon le coefficient exact du jeu/version. Une courbe d’accélération, un multiplicateur FOV/ADS ou un coefficient mal validé rendent la formule incomplète.

### 5.2 Conversion entre deux jeux linéaires

Pour conserver le **même `cm/360` horizontal**, avec éventuellement un DPI différent :

```text
sens_destination = sens_source × (DPI_source / DPI_destination)
                              × (yaw_source / yaw_destination)
```

Si DPI identique : `sens_destination = sens_source × yaw_source / yaw_destination`.

**Exemple de travail : CS2 → Valorant**, avec coefficients hipfire couramment documentés, à vérifier en situation et à réexaminer à chaque mise à jour de ces jeux :

- CS2 avec `m_yaw = 0,022°/count` pour une unité de sensibilité [S10]. Le joueur peut changer `m_yaw` : ce n’est donc **pas** une constante absolue de sa configuration.
- Valorant avec un facteur rapporté de `0,07°/count` par unité de sensibilité [S11, source tierce et non une API officielle contractuelle].
- Sensibilité CS2 `2,0`, DPI `800` → `cm/360 ≈ 25,98 cm`.
- Sensibilité Valorant équivalente = `2,0 × 0,022 / 0,07 ≈ 0,628571`.
- L’opération inverse donne `0,628571 × 0,07 / 0,022 ≈ 2,0`.

**Important :** certaines pages web d’outils affichent des rapports inversés dans leurs textes malgré une bonne formule ailleurs. Ne **jamais** copier un coefficient arbitraire ou une table web sans tester le calcul aller-retour et, si possible, la rotation réelle à la souris. Le produit doit exposer la formule et sa source.

### 5.3 eDPI : utile, mais à ne pas confondre avec `cm/360`

`eDPI = DPI × sensibilité du jeu`. Cette valeur est surtout comparable **à l’intérieur d’un même modèle de sensibilité**, pas directement entre CS2, Valorant et Call of Duty. Pour comparer les jeux, utiliser le coefficient de rotation validé et `cm/360`.

### 5.4 FOV, ratio d’écran et « même sensation »

Deux jeux peuvent avoir un `cm/360` identique et un **ressenti visuel différent**. En projection perspective, la translation apparente d’une cible dépend notamment du champ de vision :

```text
hFOV = 2 × atan(tan(vFOV/2) × largeur/hauteur)
vFOV = 2 × atan(tan(hFOV/2) × hauteur/largeur)
```

*Attention : fonctions trigonométriques en radians dans l’implémentation ; convertir explicitement à l’entrée/sortie.*

Pour un point proche du centre, sa coordonnée horizontale projetée (en pixels) peut s’approcher par :

```text
x ≈ (largeur_pixels / 2) × tan(angle_horizontal) / tan(hFOV / 2)
```

Conséquences :

- le **matching `cm/360`** reproduit la quantité de rotation réelle par déplacement de souris ;
- le **matching FOV** rend la taille et la vitesse apparente des cibles plus comparables ;
- le **matching « distance moniteur »** vise une égalité de mouvement sur l’écran pour une position donnée, et n’est généralement pas équivalent au matching 360° sur l’ensemble des angles ;
- un jeu avec caméra, FOV, aspect ratio étiré, zoom ou réticule atypique ne peut pas être reproduit parfaitement par un scalaire unique.

Prévoir un choix explicite : **« Rotation identique (cm/360) » — défaut recommandé**, **« FOV identique lorsque connu »**, puis éventuellement **« correspondance visuelle locale près du centre »** comme mode avancé clairement marqué *approximation*. Ne pas afficher « 100 % identique » sans mesure.

### 5.5 Coefficients de visée ADS, scopes et Call of Duty

**Call of Duty n’est pas un seul profil.** Les paramètres peuvent dépendre de l’épisode, de la version, du FOV, de l’arme, du zoom, du mode ADS et du *Monitor Distance Coefficient*. Activision décrit notamment ces paramètres pour *Modern Warfare (2019)* [S12] : cette documentation prouve la nécessité d’un modèle détaillé, mais **ne valide pas automatiquement les constantes des épisodes de 2026**.

**Spécification du support multi-jeux :**

| Jeu | MVP | Après validation |
|---|---|---|
| CS2 | Profil hipfire avec `sensitivity`, DPI, `m_yaw` configurable ; conversion `cm/360` | Vérification de `m_pitch`, ratio étiré, zoom, lecture assistée de paramètres si fiable |
| Valorant | Profil hipfire avec DPI et sensibilité ; conversion avec hypothèse/source affichées | ADS/scopes, documentation de FOV et de paramètres confirmée par essais |
| Call of Duty | **Profil manuel générique**, angle mesuré, version explicitée ; aucune constante magique universelle | Adaptateurs distincts par **titre + build + mode de visée**, testés et sourcés |
| Apex Legends, Overwatch 2, Fortnite, R6 Siege | Fiche manuelle `cm/360` et paramètres librement renseignés | Adaptateurs progressifs, un par un, si vérifiés |
| Autre jeu | Profil custom : DPI, FOV, angle par count **ou** `cm/360` mesuré | Import depuis format documenté si possible |

**Ne pas annoncer qu’un profil Call of Duty est « exact »** si seuls des convertisseurs non officiels et aucune vérification in-game sont disponibles.

### 5.6 Importer, exporter, « copier directement dans les jeux »

Construire trois niveaux :

1. **Niveau A — toujours disponible :** importer les valeurs **manuellement** ; enregistrer un profil ; exporter la fiche JSON/CSV ; bouton **Copier la sensibilité** (presse-papiers) et texte montrant dans quel menu du jeu la saisir.
2. **Niveau B — jeux compatibles :** proposer du texte de commande prêt à copier lorsqu’une commande documentée existe (par exemple une commande de sensibilité de console CS2), sans la lancer dans un autre processus.
3. **Niveau C — option future :** lire des fichiers de configuration **seulement pour les jeux/versions dont le format est validé** ; toute écriture nécessite sauvegarde `.bak`, simulation des changements, confirmation explicite, jeu fermé, vérification du chemin, et procédure de restauration. **Désactivée par défaut.**

**Interdictions techniques du projet :** modification de processus d’un jeu tiers ; injection, hooks globaux, contournement anti-cheat ; accès aux fichiers sans consentement ; promesse d’un clic qui change les paramètres de tous les FPS. Valorant, par exemple, doit être considéré comme une **saisie manuelle dans les menus** tant qu’une méthode autorisée, documentée et fiable n’est pas disponible.

### 5.7 Contrôles de validation des conversions

- [ ] DPI > 0 et dans une plage plausible ; sensibilité > 0 ; aucun `NaN`, infini ou division par zéro.
- [ ] Paramètres horizontaux/verticaux et ADS non confondus.
- [ ] Conversion A→B→A : erreur numérique < `1e-6` hors contraintes d’arrondi propres au jeu.
- [ ] Déplacer physiquement 10/20 cm, faire plusieurs essais et comparer l’angle.
- [ ] Afficher la **précision de confiance** : « confirmé par test », « coefficient documentaire », « saisi manuellement », « estimation ».
- [ ] Avertir si FOV, zoom, mode de caméra ou options d’accélération diffèrent.
- [ ] Garder le nombre original, le nombre arrondi à renseigner et le `cm/360` effectif après arrondi.

---

<a id="chapitre-6"></a>

## 6. Assistant de recherche d’une sensibilité adaptée

### 6.1 Réalité du problème

La « sensibilité parfaite » est **contextuelle** : surface disponible, prise en main, habits moteurs, type de FPS, taille des cibles, distance, fatigue, rôle tactique. L’application peut recommander **une plage raisonnable mesurée chez l’utilisateur**, pas prétendre trouver un optimum définitif.

### 6.2 Protocole expérimental proposé

1. **Point de départ :** sensibilité actuelle, DPI, `cm/360` et jeu de référence validés.
2. **Candidates :** proposer trois réglages, par exemple `0,90 ×`, `1,00 ×`, `1,10 ×` la sensibilité de départ. Prévoir limites min/max personnalisables.
3. **Scénarios de test fixes :** petits flicks, grands flicks, microcorrection, tracking lent, tracking rapide ; même FOV, taille, durée et niveau pour chaque candidate.
4. **Familiarisation :** 1–2 essais non comptés par candidate, afin de réduire le biais de nouveauté.
5. **Ordre contrebalancé :** répartir les candidates dans des séquences du type ABC, BCA, CAB d’une répétition à l’autre pour limiter les biais de chauffe/fatigue ; pauses identiques.
6. **Mesures :** précision, rapidité, régularité, erreur angulaire, overshoot, confort **subjectif** (question très courte en fin de série).
7. **Comparaison :** médiane et dispersion, plus un score composite transparent. Ne pas départager deux candidates lorsque la différence est trop faible au regard de la variabilité.
8. **Résultat :** afficher « plage conseillée » + avantages/inconvénients (« plus rapide sur grands mouvements », « plus stable sur petites cibles ») ; possibilité de conserver le réglage d’origine.
9. **Validation différée :** rejouer quelques tests 2–7 jours plus tard et observer les résultats **dans le FPS réel**.

### 6.3 Algorithme de recommandation (V1, sans IA)

- Normaliser les mesures **au sein d’un même scénario et d’une même session de calibration**, pas entre n’importe quels exercices.
- Définir des pondérations **affichées et réglables** : par exemple 35 % précision flick, 25 % temps flick, 30 % tracking, 10 % régularité. Ce sont des choix de produit, pas des normes scientifiques.
- Comparer au moins 2–3 passages par candidate ; lorsqu’ils divergent fortement, demander un essai supplémentaire au lieu d’affirmer un gagnant.
- Afficher les valeurs brutes et une **incertitude** (dispersion, intervalle de variation observé) plutôt que des décimales pseudo-scientifiques.
- Ne jamais modifier le DPI matériel à l’insu de l’utilisateur ; suggérer la valeur à régler dans le logiciel constructeur si nécessaire.

### 6.4 Ce qui peut être ajouté en V2

Recherche par intervalles successifs ; profils par objectif (« tracking », « tactical FPS », « arena FPS ») ; réévaluation après adaptation ; analyse de la trajectoire (survol, sous-correction, tremblements). Le module ne doit jamais être une boîte noire : les critères restent inspectables.

---
<a id="chapitre-7"></a>

## 7. Catalogue d’exercices : couverture complète, développement progressif

### 7.1 Objectif de conception

La richesse vient de la **combinatoire d’un petit nombre de mécaniques fiables** : apparition, acquisition, cible mobile, tir, changement de cible, déplacement joueur, score, durée. Chaque exercice est un `ScenarioDefinition` configurable, pas une scène indépendante réinventant toute la logique.

**Priorités :**
- **P0** : noyau indispensable à une première application réellement jouable.
- **P1** : première version complète, utile au quotidien.
- **P2** : approfondissement/spécialisation, seulement après stabilisation et tests.

### 7.2 Famille A — Clic, flick et précision statique

| ID | Exercice | Règle principale | Mesures prioritaires | Priorité |
|---|---|---|---|---|
| C01 | **Static Single** | Une sphère immobile ; nouvelle cible après touche | Accuracy, temps par cible, cadence | **P0** |
| C02 | **Microshot** | Petites cibles proches du centre | Précision fine, sur-correction | P1 |
| C03 | **Grid Targets** | Plusieurs sphères en grille ; choix libre | Cibles/min, précision, trajet du viseur | **P0** |
| C04 | **Wide Flick** | Apparition loin du viseur, grands angles | Temps d’acquisition, overshoot | P1 |
| C05 | **Sixshot** | Six petites cibles réparties, remplacées individuellement | Hits/min, contrôle fin | P1 |
| C06 | **180° Turns** | Objectifs hors champ nécessitant de se retourner | Temps de rotation, centrage final | P2 |
| C07 | **Vertical Flicks** | Cibles à forte variation de hauteur | Erreurs verticales et temps | P1 |
| C08 | **Horizontal Flicks** | Cibles à forte variation latérale | Erreurs horizontales et temps | P1 |
| C09 | **Sequence Memory** | Ordre de cibles visible, à suivre | Rapidité/erreurs de séquence | P2 |
| C10 | **Corner Precision** | Petites cibles vers les bords du FOV | Précision hors centre | P2 |
| C11 | **Distance Scaling** | Cibles à différentes distances mais taille angulaire contrôlée | Vitesse/précision par taille | P1 |
| C12 | **One Tap Discipline** | Tir unique, aucun crédit pour spam | First-shot hit rate, miss rate | P1 |

**Règles communes :** compter explicitement tirs ratés et cibles non atteintes. Une cible qui apparaît au centre exact du viseur ne doit pas être comptabilisée comme un flick normal. Les cibles ne doivent pas se chevaucher si le scénario ne le demande pas.

### 7.3 Famille B — Clic sur cibles dynamiques et réactivité

| ID | Exercice | Règle principale | Mesures prioritaires | Priorité |
|---|---|---|---|---|
| D01 | **Pop-up** | Cible apparaît brièvement puis disparaît | Taux d’acquisition, temps de réaction | P1 |
| D02 | **Moving Click** | Cibles qui se déplacent avant tir | Précision sur mobile, latence de clic | P1 |
| D03 | **Bounce Click** | Trajectoire à rebonds | Hits avant disparition, timing | P2 |
| D04 | **Strafe Tapping** | Cible alterne déplacements gauche/droite | Précision des clics au changement | P1 |
| D05 | **Flash Targets** | Cibles visibles 200–800 ms configurables | Succès par fenêtre d’exposition | P1 |
| D06 | **Reaction Colors** | Ne cliquer que sur les cibles de la bonne couleur | Réaction correcte, fausses alarmes | P2 |
| D07 | **Adaptive Size** | Taille ajustée en fonction du niveau, avec bornes | Niveau atteint + accuracy | P2 |
| D08 | **Crossing Targets** | Deux ou plusieurs cibles se croisent | Sélection correcte, clics ratés | P2 |
| D09 | **Timing Windows** | Cible devient active pendant une fenêtre | Timing relatif, précision | P2 |

**Précaution sur « temps de réaction » :** mesurer depuis l’événement d’apparition logique/rendue tel qu’il est défini par le scénario. Sans matériel externe, on mesure une **estimation logicielle**, pas directement le temps neurophysiologique de réaction du joueur.

### 7.4 Famille C — Tracking continu

| ID | Exercice | Règle principale | Mesures prioritaires | Priorité |
|---|---|---|---|---|
| T01 | **Smooth Horizontal** | Suivre une sphère mobile horizontalement | Temps sur cible, erreur angulaire | **P0** |
| T02 | **Smooth Vertical** | Mouvement vertical régulier | Erreur verticale, stabilité | P1 |
| T03 | **Smooth Diagonal** | Mouvement diagonal | Maintien et correction | P1 |
| T04 | **Circle Track** | Cible en orbite régulière | Erreur moyenne, dérive | P1 |
| T05 | **Strafe Track** | Cible alterne des strafes simples | Temps sur cible, temps de réacquisition | **P0** |
| T06 | **Reactive Tracking** | Direction modifiée selon séquence déterministe | Retard de reprise, erreur après virage | P1 |
| T07 | **Random Smooth** | Trajectoire courbe aléatoire **lissée** | Couverture, stabilité | P1 |
| T08 | **Close Fast** | Cible proche et rapide angulairement | Erreur, réacquisition | P2 |
| T09 | **Far Small** | Petite cible lente, amplitude faible | Précision fine continue | P1 |
| T10 | **Vertical Switch** | Tracking avec changement brusque d’altitude | Temps de rattrapage | P2 |
| T11 | **Long Track** | Tracking de 60–120 s avec pauses proposées | Dérive et régularité | P2 |
| T12 | **Burst Tracking** | Tenir le viseur sur la cible pendant de courtes rafales | Hit time par burst | P1 |

**Mesure fondamentale :** `time_on_target / active_tracking_time`, mais avec définition explicite de « sur cible » (intersection du rayon de visée et d’une forme hitbox/zone visible) et gestion de l’échantillonnage. Compléter par l’erreur angulaire moyenne/médiane et le percentile 95 afin de ne pas masquer les grosses pertes de suivi.

**Attention aux scores à FPS variable :** un algorithme qui ajoute simplement `+1` à chaque frame où le viseur est sur une cible récompense artificiellement les PC à haut FPS. Intégrer **des durées réelles** (secondes), jamais des nombres de frames bruts.

### 7.5 Famille D — Target switching

| ID | Exercice | Règle principale | Mesures prioritaires | Priorité |
|---|---|---|---|---|
| S01 | **Multi Switch** | Plusieurs cibles immobiles ; changer immédiatement après une touche | Temps de transition, précision | **P0** |
| S02 | **Moving Switch** | Idem, cibles mobiles | Temps de transition + tenue | P1 |
| S03 | **Priority Switch** | Priorités de cibles par couleur / point | Choix correct, vitesse | P1 |
| S04 | **Hold Then Switch** | Garder le viseur sur une cible N ms avant la suivante | Tenue, réactivité, transition | P1 |
| S05 | **Multi-HP** | Chaque cible nécessite N impacts/une durée de tenue | Répartition, précision | P2 |
| S06 | **Peripheral Switch** | Cibles apparaissant en périphérie | Détection + acquisition | P2 |

### 7.6 Famille E — Mouvement et aim combinés

| ID | Exercice | Règle principale | Mesures prioritaires | Priorité |
|---|---|---|---|---|
| M01 | **Strafe Aim** | Se déplacer au clavier tout en visant des cibles | Accuracy en déplacement | P1 |
| M02 | **Counter-Strafe Basics** | Arrêt/direction opposée et tir lorsque vitesse sous un seuil | Erreur de synchronisation mouvement/tir | P2 |
| M03 | **Peek & Click** | Sortir d’un abri, acquérir et tirer | Temps visible jusqu’au tir, précision | P2 |
| M04 | **Elevation Aim** | Marcher/sauter dans une arène simple | Erreur angulaire en mouvement | P2 |
| M05 | **Strafe Tracking** | Joueur et cible se déplacent en même temps | Temps sur cible | P1 |
| M06 | **Target Occlusion** | Les cibles passent derrière un obstacle | Reprise du tracking, clics invalides | P2 |

**Limite de réalisme :** la physique de mouvement de CS2, Valorant ou Call of Duty (accélération, friction, inertie, pénalités de tir) n’est pas reproduite à l’identique sans un modèle spécifique et validé. Ces modes entraînent des principes généraux de coordination, **pas des timings de jeu garantis au milliseconde**.

### 7.7 Famille F — Techniques et diagnostics ciblés

| ID | Exercice | Règle principale | Mesures prioritaires | Priorité |
|---|---|---|---|---|
| X01 | **Overshoot Clinic** | Grand mouvement puis micro-correction | Dépassement initial, correction | P1 |
| X02 | **Undershoot Clinic** | Mesurer les arrêts trop courts | Distance restante et temps | P1 |
| X03 | **Centering** | Stabiliser le viseur sur point central | Écart angulaire, micro-jitter | P1 |
| X04 | **Pace & Accuracy** | Paliers de vitesse imposée puis libre | Courbe vitesse–précision | P1 |
| X05 | **180 Reacquire** | Rotation puis acquisition d’une petite cible | Erreur de recentrage | P2 |
| X06 | **Distractor Suppression** | Cibles utiles au milieu de sphères leurres | False positives, attention | P2 |
| X07 | **Zoom/ADS Transition** | Changement de FOV et de profil sensibilité lors de la visée | Précision au zoom, timing | P2 |
| X08 | **Pattern Drill** | Trajectoires reproductibles réutilisables pour calibrer | Erreur par segment | P1 |
| X09 | **Endurance Control** | Séries courtes répétées avec pauses contrôlées | Variabilité inter-séries | P2 |
| X10 | **Recoil Control — abstrait** | Compenser un motif **inventé** et clairement identifié | Écart à la trajectoire cible | P2 |

**Volume cible du catalogue :** **55 variantes décrites** ci-dessus. Le lancement ne doit pas exiger d’implémenter 49 moteurs : viser **5 scénarios P0 de référence**, puis enrichir grâce à la configuration commune.

### 7.8 Schéma commun à tous les exercices

Chaque définition de scénario doit posséder :

| Domaine | Champs | Exemple |
|---|---|---|
| Identité | `id`, `revision`, `name`, `family`, `tags`, `description` | `T05`, `1`, `Strafe Track`, `tracking` |
| Temps | `warmup_s`, `active_s`, `rest_after_s`, `countdown_s` | 5 / 45 / 20 / 3 |
| Caméra | `fov_source`, `fov_value_deg`, `fov_axis`, `mouse_profile_ref` | Horizontal, 103°, 16:9 |
| Cibles | `shape`, `angular_diameter_deg`, `max_active`, `spawn_zone`, `lifetime_s` | Sphère, 1,3°, 1, centre ±15° |
| Mouvement cible | `motion_type`, `speed_deg_s`, `accel`, `turn_interval`, `seed` | Strafe, 12°/s, seed 12345 |
| Actions | `shoot_type`, `hold_required`, `cooldown_ms`, `ammo` | Click / hold / auto |
| Score | `metric_profile`, `score_formula_version`, `leaderboard_group_key` | Tracking v1 |
| Accessibilité | `contrast`, `audio`, `difficulty_tier` | Contraste haut |
| Validation | `min`, `max`, `allowed_values`, `schema_version` | Speed 0…120°/s |

Toutes les unités physiques doivent être **dans les noms des champs** : `_deg`, `_deg_s`, `_ms`, `_s`, `_cm`. C’est un garde-fou majeur contre les bugs de conversion.

---

<a id="chapitre-8"></a>

## 8. Génération des cibles, hitboxes et simulation

### 8.1 Système de coordonnées

- Caméra FPS placée dans une arène abstraite, dont l’origine logique et la profondeur sont explicites.
- Les cibles sont générées d’abord en **coordonnées angulaires** (yaw et pitch relatifs à la caméra ou au monde), puis converties en positions 3D.
- Limites de spawn en degrés, contrôlées afin qu’une cible n’apparaisse pas partiellement hors écran si ce n’est pas intentionnel.
- Rayon apparent (diamètre angulaire) contrôlé indépendamment de la profondeur.

Pour une **sphère** située à la distance `d` de la caméra et devant celle-ci, de diamètre angulaire apparent `α` :

```text
rayon_sphere = d × sin(α / 2)
```

Cette relation géométrique suppose une sphère visible entière et la caméra à distance de son centre. Pour un **disque plan face à la caméra**, une relation adaptée est `rayon_disque = d × tan(α/2)`. Ne pas mélanger les deux formes de collision dans les tests sans le documenter.

**Avantage :** une sphère de 1° à 8 m et une autre de 1° à 20 m ont des tailles visuelles proches ; la difficulté ne change pas accidentellement avec la profondeur.

### 8.2 Règles de génération

- Définir une graine (`seed`) et un PRNG de scénario stable ; enregistrer le résultat de la graine dans chaque tentative.
- Interdire les cibles inaccessibles, hors caméra, derrière un obstacle non prévu, ou trop proches d’autres cibles.
- Séparer **génération aléatoire** et **rendu** : aucune génération différente parce que le FPS change.
- Les tests standard utilisent une distribution contrôlée (zones, angles, tailles) ; les scénarios « random » le déclarent explicitement.
- Prévoir au besoin une distance angulaire minimale entre cible précédente et nouvelle cible afin d’éviter de fausser les scores avec des spawns faciles.
- Les trajectoires rapides restent **continues** en position, sauf téléportation explicitement prévue ; les virages ont des bornes d’accélération pour être lisibles.

### 8.3 Collisions de tirs

- Un **clic** = un événement de tir validé, compté une fois ; les press/release ne doivent pas produire deux tirs.
- Le rayon part du centre de la caméra de visée (réticule logique) vers la direction du viseur.
- S’il existe plusieurs cibles sur la même direction, choisir la plus proche touchée, ou appliquer une règle déterministe de priorité déclarée.
- Une cible détruite ne doit plus recevoir de points après son remplacement.
- Ne pas compter les tirs au menu, pendant la pause ou durant le compte à rebours.
- Un tir hors cible = `miss` ; un tir sur leurre = `false_positive` si le scénario le demande.
- Les cibles à santé multiple gardent une **identité unique** ; chaque impact et l’élimination sont des événements distincts.

### 8.4 Collisions de tracking

- L’intersection « sur cible » est mesurée sur une **durée**, pas en nombre de frames.
- Calculer l’**erreur angulaire** entre le vecteur de regard `v` et la direction du centre de cible `t` : `acos(clamp(dot(normalize(v), normalize(t)), -1, 1))`.
- L’erreur est nulle au centre et augmente vers l’extérieur ; elle est interprétable même sans tir.
- Pour une cible sphérique, considérer la cible « acquise » lorsque le rayon de visée intersecte sa silhouette/hitbox ; possibilité d’une marge affichée séparément, **pas d’aim assist invisible**.
- Pour réduire le biais temporel, échantillonner à une cadence logique suffisante ou intégrer sur segments ; tester la convergence en doublant la cadence de simulation.
- Gérer les instants sans cible active et les pauses : ils ne figurent pas au dénominateur du tracking.

### 8.5 Horloge et reproductibilité

Conserver une **horloge monotone**, jamais dépendante de l’heure système réglable par l’utilisateur. Chaque tentative enregistre `start_time_monotonic`, `elapsed_active_us`, `pause_durations`, `scenario_seed`, `definition_revision` et `score_formula_revision`. À l’export JSON, la date civile ISO est ajoutée pour l’historique.

Un replay reconstitue le **scénario et les actions logiques** selon la version déclarée ; la précision temporelle d’une reproduction de l’input matériel dépend des informations réellement capturées. Ne pas promettre une reconstitution parfaite si seules les statistiques finales sont stockées.

---

<a id="chapitre-9"></a>

## 9. Scoring : mesurer l’amélioration et éviter les faux progrès

### 9.1 Politique générale

**Toujours sauvegarder les valeurs brutes**, puis calculer un score composite optionnel. Un score unique peut servir de motivation mais ne doit pas masquer la progression réelle.

Les comparaisons historiques requièrent une clé de contexte, au minimum :

```text
scenario_id + scenario_revision + difficulty_tier + duration
+ target_angular_size + target_speed + spawn_distribution
+ fov + aspect_ratio + metric_version
```

Pour des analyses plus strictes, distinguer également DPI, `cm/360`, profil souris, FPS/refresh et version du moteur. **Changer la sensibilité** peut être un objectif de test, mais l’application doit alors montrer qu’il s’agit d’une comparaison « conditions différentes ».

### 9.2 Statistiques clic/flick

- `shots_fired`, `hits`, `misses`, `false_positives`, `targets_spawned`, `targets_cleared`.
- `accuracy = hits / shots_fired × 100` si `shots_fired > 0` ; sinon `N/A`, pas `100 %`.
- `hit_rate = hits / active_seconds` et `targets_cleared_per_min`.
- Temps acquisition par cible (apparition → touche), médiane, p90/p95 ; cibles expirées traitées séparément (ne pas effacer l’échec).
- Écart angulaire au premier tir, nombre de corrections, overshoot/undershoot (définition temporelle documentée).
- Efficacité de trajectoire : rapport entre plus court déplacement angulaire plausible et distance parcourue par le viseur, borné entre 0 et 1 ; **diagnostic**, pas une mesure absolue de talent.
- Amplitude des flicks par catégorie (courts, moyens, longs) pour identifier les faiblesses spécifiques.

### 9.3 Statistiques tracking

- `target_exposed_time_s`, `on_target_time_s`, `on_target_ratio`.
- Erreur angulaire moyenne, médiane et p95, en degrés ; éventuellement erreur dans le plan écran (pixels) seulement avec FOV et résolution joints.
- Temps de réacquisition après changement de direction, overshoot de poursuite et dérive.
- Répartition erreur horizontale/verticale.
- Pour les modes de tir continu : temps avec réticule sur cible, tirs valides, taux d’impacts ; ne pas confondre « garder le viseur » et « tirer ».

### 9.4 Scores composites : propositions, pas vérités universelles

**V1 :** utiliser en priorité des métriques métier explicites et des records par scénario. Si un nombre principal est nécessaire : choisir une formule fixe par famille, versionnée et expliquée sur l’écran de détail.

Exemple pédagogique pour une famille de tirs sur scénario **strictement fixe** :

```text
accuracy_fraction = hits / max(shots, 1)
throughput = hits / max(active_seconds, epsilon)
score_click_v1 = round(1000 × accuracy_fraction × min(throughput / reference_rate, 2))
```

`reference_rate` est un paramètre du scénario, validé par tests ; le plafond `2` est arbitraire et doit être affiché. **Ne pas comparer les scores de deux scénarios différents** ni changer cette formule silencieusement. Garder surtout `accuracy` et `hits/min` visibles.

Exemple tracking : `score_tracking_v1 = round(1000 × on_target_time_s / target_exposed_time_s)`, avec si besoin mesures de vitesse/difficulté en dehors de ce score. Le ratio sur cible est simple et robuste, mais ne mesure pas tout : une très grosse cible donne évidemment un score élevé. Comparer **à taille et trajectoire identiques**.

### 9.5 Progrès et visualisations

Sur chaque scénario de référence :

- Courbe chronologique de la **médiane glissante** sur 5–10 séances ; en parallèle record absolu et dispersion.
- Comparaison « 10 dernières séances » vs « 10 premières comparables » en affichant les effectifs.
- Distinction entre **précision** et **vitesse** (idéalement nuage de points) pour éviter de récompenser une hausse du score obtenue par simple spam.
- Si l’échantillon est faible, afficher « données insuffisantes » ; ne pas déduire une tendance d’un record unique.
- Historique des changements de DPI, de sensibilité, de FOV et de configuration.
- Récapitulatif hebdomadaire local : temps par compétence, points d’amélioration observés, exercices conseillés.
- Export CSV et JSON, sans internet.

### 9.6 Suggestion d’exercices basée sur des règles simples

1. Détecter les familles moins entraînées dans les 7 derniers jours.
2. Évaluer pour chacune l’évolution de l’accuracy/du tracking à difficulté fixe.
3. Si la précision est faible : proposer un scénario plus lent ou des cibles légèrement plus grandes.
4. Si la précision reste haute et stable sur plusieurs séances : proposer une difficulté supérieure.
5. Alterner exercices proches du jeu principal et exercices généraux de contrôle moteur.
6. Afficher **pourquoi** un exercice a été suggéré ; permettre de refuser et de masquer une recommandation.

**Règle scientifique de prudence :** la recherche sur le mélange des exercices (*contextual interference*) relève des résultats nuancés, avec différences entre laboratoire et sport pratiqué. Utiliser la variété comme choix pédagogique plausible, **sans promettre automatiquement un meilleur transfert dans Valorant ou CS2** [S13–S14].

---

<a id="chapitre-10"></a>

## 10. Routines, temps de repos et progression

### 10.1 Constructeur de routine

Une routine est une suite versionnée de `RoutineStep` :

```text
Démarrage → Échauffement → Exercice 1 → Pause → Exercice 2
          → Pause → Exercice 3 → Résumé / Export
```

Chaque étape peut être : scénario, échauffement, pause, écran d’instructions ou test de calibration. Paramètres : durée, répétitions, niveau de difficulté, pause, nombre d’essais et option « démarrer automatiquement l’étape suivante ».

### 10.2 Routines proposées au lancement

| Routine | Durée indicative | Contenu | Objectif |
|---|---:|---|---|
| **Warm-up FPS** | 5–7 min | Static Single → Microshot → Strafe Track | Mise en route avant le jeu |
| **Précision tactique** | 10–15 min | Small dots → One Tap → Wide Flick → pauses | First-shot accuracy |
| **Tracking** | 10–15 min | Smooth Horizontal → Circle Track → Reactive Tracking | Continuité du suivi |
| **Polyvalente** | 15–20 min | Static → Flick → Track → Switch → récap | Travail général |
| **Calibration** | 15–25 min | Trois sensibilités × scénarios constants, ordre alterné | Comparer des réglages |
| **Courte pause** | 2–3 min | Une tâche lente de précision, puis arrêt | Utilisation facultative et légère |

Ces durées sont des **présets ergonomiques**, pas une prescription médicale. Le joueur peut régler les pauses, sauter une étape, arrêter à tout moment et désactiver les rappels.

### 10.3 Gestion d’état stricte

```text
MAIN_MENU → PREPARATION → COUNTDOWN → RUNNING
   ↑                         ↙      ↘
   └────── RESULTS ← FINISHED       PAUSED ↔ RUNNING
                                     ↓
                                   ABORTED
```

Transitions non autorisées rejetées et testées : un clic ne doit pas enregistrer de point dans `PAUSED` ; un abandon n’est pas un record ; la fin de routine doit enregistrer uniquement les épreuves réellement achevées. **Ne pas confondre « pause automatique » et « exercice terminé ».**

### 10.4 Réglage automatique de la difficulté

Mécanisme optionnel : si plusieurs séances montrent une précision stable au-dessus d’un seuil défini, réduire un peu la taille angulaire ou accroître la vitesse. **Il faut alors créer un nouveau contexte de score**. Prévoir un mode **Benchmark fixe**, dans lequel aucune adaptation n’intervient, afin de mesurer honnêtement les progrès.

---

<a id="chapitre-11"></a>

## 11. Architecture fonctionnelle — séparation des responsabilités

### 11.1 Vue d’ensemble

```text
┌────────────────────────── APPLICATION UI ────────────────────────────┐
│ Accueil │ Exercices │ Routines │ Sensibilité │ Statistiques │ Options │
└────────────────────────────┬─────────────────────────────────────────┘
                             │ commandes/événements
┌────────────────────────────▼─────────────────────────────────────────┐
│                         USE CASES                                   │
│ StartSession │ Pause │ Complete │ Compare │ ConvertSensitivity       │
└───┬────────────────┬───────────────────┬──────────────────────┬─────┘
    │                │                   │                      │
┌───▼─────────┐ ┌────▼────────────┐ ┌────▼────────────────┐ ┌──▼────────┐
│ InputBackend│ │ ScenarioEngine  │ │ SensitivityService  │ │ Statistics│
│ CameraAim   │ │ Spawn/Motion    │ │ GameProfileAdapters │ │ Progress  │
└───┬─────────┘ │ Targets/HitTest │ └─────────────────────┘ └──┬────────┘
    │           └────┬────────────┘                            │
    └────────────┬───┘                                         │
                 ▼                                             ▼
          SessionEventBus / Immutable Result             StorageRepository
                 │                                             │
                 └──────────────→ `user://` JSON/CSV ←──────────┘
```

**La dépendance doit aller vers les abstractions**, pas vers un écran précis. Exemple : `ScenarioEngine` connaît `AimSample` et `ScenarioDefinition`, mais pas un bouton dans `MainMenu.tscn`. `SensitivityService` ne dépend pas du rendu 3D et se teste avec des valeurs numériques seules.

### 11.2 Modules attendus

| Module | Responsabilité | Ne doit pas faire |
|---|---|---|
| `AppState` | Profil actif, navigation, préférences générales | Calculer collisions |
| `InputBackend` | Capturer mouvements/clics/focus ; horodatage | Appliquer règles de score |
| `AimCamera` | Transformer deltas en yaw/pitch, poser la caméra | Connaître les jeux externes |
| `SensitivityService` | DPI, degrés/count, conversions, validation | Modifier des jeux sans consentement |
| `GameProfileRegistry` | Catalogue d’adaptateurs versionnés, sources | Supposer tous les jeux linéaires |
| `ScenarioCatalog` | Charger/valider définitions d’exercices | Sauvegarder les scores |
| `ScenarioEngine` | États, spawn, motion, progression temporelle | Mettre à jour des tableaux d’UI |
| `TargetFactory` | Créer/réutiliser les sphères et hitboxes | Déterminer l’accuracy |
| `HitDetection` | Intersection rayon/cible cohérente temporellement | Définir le score composite |
| `SessionRecorder` | Agréger événements et données brutes | Faire l’export Windows |
| `ScoringService` | Dériver métriques et scores versionnés | Changer les règles sans révision |
| `ProgressService` | Comparaisons, médianes, recommandations | Recalculer à chaque frame |
| `RoutineEngine` | Ordonnancement exercices/pauses | Piloter le capteur souris directement |
| `StorageRepository` | Persistance, backup, migration, export | Corriger silencieusement les données |
| `Diagnostics` | FPS, frametimes, mode input, logs de test | Collecte distante cachée |
| `UI` | Présenter et déclencher commandes | Contenir les formules métier |

### 11.3 Arborescence recommandée du dépôt

```text
aim-local/
├─ project.godot
├─ export_presets.cfg
├─ README.md
├─ LICENSES/
│  └─ GODOT_LICENSE.txt
├─ docs/
│  ├─ SPECIFICATION.md           # Ce cahier des charges
│  ├─ ARCHITECTURE.md
│  ├─ SENSITIVITY_MATH.md
│  ├─ SCENARIO_SCHEMA.md
│  ├─ TEST_PLAN.md
│  └─ DECISIONS.md               # ADR / arbitrages
├─ assets/
│  ├─ fonts/
│  ├─ icons/
│  └─ audio/
├─ scenes/
│  ├─ app/Main.tscn
│  ├─ ui/Home.tscn
│  ├─ ui/ScenarioBrowser.tscn
│  ├─ ui/SensitivityWizard.tscn
│  ├─ ui/Results.tscn
│  ├─ ui/Progress.tscn
│  ├─ training/Arena.tscn
│  ├─ training/Target.tscn
│  └─ training/TrainingHud.tscn
├─ scripts/
│  ├─ core/                  # Horloge, états, types, événements
│  ├─ input/                 # InputBackend, InputSampler, caméra
│  ├─ training/              # Moteur de scénario, cibles, collisions
│  ├─ sensitivity/           # Conversions et adaptateurs de jeux
│  ├─ statistics/            # Métriques, scores, graphiques
│  ├─ routines/              # Orchestration et pauses
│  ├─ persistence/           # Données locales et migrations
│  ├─ diagnostics/           # Perf, logs, sanity checks
│  └─ ui/                    # Contrôleurs d'écrans
├─ content/
│  ├─ scenarios/
│  ├─ routines/
│  └─ games/
├─ tests/
│  ├─ unit/
│  ├─ integration/
│  ├─ golden_scenarios/
│  └─ manual/
├─ tools/
│  ├─ validate_content.gd
│  └─ export_windows.ps1
└─ dist/                     # Non suivi par Git
```

**Règles de dépendance :** `core` → ne dépend de personne ; `sensitivity`, `scoring` et `scenario definitions` → `core` ; `training` → `core + input + definitions` ; `UI` → services publics ; `persistence` implémente des interfaces de stockage. Les **tests** peuvent dépendre de n’importe quel module, mais le jeu ne doit jamais dépendre des tests.

### 11.4 Gestion des événements

Événements de domaine typés à définir :

```text
SessionStarted
TargetSpawned / TargetExpired
MouseShot / TargetHit / ShotMissed
TrackingSample / TargetDirectionChanged
PauseStarted / PauseEnded
SessionFinished / SessionAborted
SensitivityProfileChanged
RoutineStepCompleted
```

Chaque événement important a un identifiant de session, un timestamp monotone, un identifiant de cible (si pertinent), une révision de schéma et des données minimales. Une même action ne doit **jamais** être traitée deux fois (idempotence des points critiques). L’UI réagit à ces événements ; elle ne doit pas « inventer » des touches indépendamment du moteur.

### 11.5 Interfaces structurantes, sans dépendance imposée au langage

```text
IInputBackend.poll_or_dispatch() -> AimInputEvent
ISensitivityConverter.to_degrees_per_count(profile) -> Vector2
ISensitivityConverter.convert(source, target, dpi_source, dpi_target) -> ConversionResult
IScenarioCatalog.load(id, revision) -> ValidatedScenario
IScenarioEngine.start(scenario, seed, mouse_profile) -> Session
IHitDetection.try_hit(aim_pose, target_snapshot) -> HitResult
IScoring.compute(raw_events, scoring_version) -> Metrics
IResultRepository.save(result) -> SaveResult
IProgress.compare(result_set, comparison_key) -> ComparisonResult
```

Ces interfaces sont **des contrats logiques**. Il est acceptable d’utiliser des classes GDScript ordinaires, des `Resource` typées et des signaux Godot plutôt que d’inventer une « architecture entreprise » lourde.

---

<a id="chapitre-12"></a>

## 12. Formats de données et persistance

### 12.1 Stratégie simple

- `res://` : ressources incluses dans l’application (scénarios, thème, ressources du moteur).
- `user://` : préférences, profils, résultats, routines personnelles, exports [S6].
- Ne pas écrire dans le dossier de l’exécutable, souvent non modifiable pour un utilisateur standard.
- Sauvegardes par écriture temporaire → fermeture/flush → remplacement contrôlé, avec backup d’une version précédente.
- En cas de JSON corrompu : **ne pas écraser immédiatement** ; proposer restauration/réparation ou démarrage avec profil vierge sans supprimer le fichier endommagé.

### 12.2 Exemple de profil de jeu — `user://profiles/cs2-main.json`

```json
{
  "schema_version": 1,
  "profile_id": "cs2-main",
  "name": "CS2 - Principal",
  "game_id": "cs2",
  "game_version_hint": "manual-user-setting",
  "dpi": 800,
  "polling_rate_hz_declared": 1000,
  "sensitivity": 2.0,
  "yaw_coefficient_deg_per_count_per_sens_unit": 0.022,
  "pitch_coefficient_deg_per_count_per_sens_unit": 0.022,
  "cm_per_360_x": 25.9772727273,
  "fov": { "axis": "horizontal", "degrees": null, "source": "unknown" },
  "aspect_ratio": "16:9",
  "ads": { "model": "not_configured", "sensitivity_multiplier": null },
  "acceleration": { "enabled": false, "source": "user_declared" },
  "source": {
    "kind": "user_entered_with_documented_coefficient",
    "verified_by_physical_test": false,
    "notes": "m_yaw can be customized in CS2"
  }
}
```

Dans l’application, il vaut mieux **recalculer** `cm_per_360_x` à partir des champs canoniques pour éviter une incohérence si l’utilisateur modifie DPI ou sensibilité ; le champ sauvegardé est une valeur dérivée/cache, validée à la lecture.

### 12.3 Exemple de définition d’exercice — `content/scenarios/T01.json`

```json
{
  "schema_version": 1,
  "scenario_id": "T01",
  "revision": 1,
  "name": "Smooth Horizontal",
  "family": "tracking",
  "seed_policy": "new_random_seed_saved_per_attempt",
  "timing": {
    "warmup_s": 3,
    "duration_s": 45,
    "pause_after_s": 20
  },
  "camera": { "fov_deg": 103, "fov_axis": "horizontal", "aspect_ratio": "16:9" },
  "targets": {
    "shape": "sphere",
    "angular_diameter_deg": 2.5,
    "active_count": 1,
    "distance_m": 10.0,
    "spawn_yaw_deg": [-12.0, 12.0],
    "spawn_pitch_deg": [-3.0, 3.0]
  },
  "motion": {
    "kind": "horizontal_pingpong",
    "angular_speed_deg_s": 10.0,
    "turn_behavior": "continuous"
  },
  "interaction": { "kind": "crosshair_tracking", "fire_required": false },
  "scoring": { "metric_profile": "tracking", "formula_version": 1 }
}
```

**Important :** `fov=103°` ci-dessus est **un exemple de contenu du simulateur**, pas une garantie que tous les jeux ont ce FOV ni une hypothèse imposée au profil CS2.

### 12.4 Exemple de résultat — `user://sessions/uuid.json`

```json
{
  "schema_version": 1,
  "session_id": "generated-uuid",
  "created_at_utc": "2026-10-11T18:00:00Z",
  "app_version": "0.3.0",
  "scenario": { "id": "T01", "revision": 1, "seed": 12345 },
  "context": {
    "profile_id": "cs2-main",
    "dpi": 800,
    "cm_per_360_x": 25.9772727273,
    "fov_deg": 103,
    "fov_axis": "horizontal",
    "aspect_ratio": "16:9",
    "display_refresh_hz": 144,
    "input_accumulation": false
  },
  "timing": { "active_duration_s": 45.0, "paused_duration_s": 0.0 },
  "raw_summary": {
    "target_exposed_time_s": 45.0,
    "on_target_time_s": 32.4,
    "angular_error_mean_deg": 1.14,
    "angular_error_p95_deg": 3.87
  },
  "score": { "formula_version": 1, "value": 720 },
  "performance": {
    "avg_fps": 238.1,
    "frametime_p99_ms": 5.8,
    "measurement_quality": "software_only"
  },
  "completed": true
}
```

Le résultat est **un exemple de schéma**, pas une performance réelle. Les données de profil **doivent être prises en snapshot** au démarrage du test ; une modification ultérieure des paramètres n’altère pas rétroactivement les anciennes séances.

### 12.5 Migration et croissance

- Définir `schema_version` dès le premier jour.
- Ajouter un script de migration v1→v2→… testé avec fichiers d’exemple.
- Sauvegarder seulement les métriques et événements indispensables en mode normal ; séries temporelles détaillées optionnelles, compressées ou à fréquence maîtrisée.
- P1 : exports CSV/JSON ; P2 : SQLite si calculs complexes sur des milliers de séances ; P3 : synchronisation facultative si un besoin apparaît.
- Boutons visibles **Exporter mes données**, **Ouvrir dossier de données**, **Supprimer mes données** avec confirmation.

---
<a id="chapitre-13"></a>

## 13. Direction artistique : 3D flat, minimaliste et utile

### 13.1 Scène 3D

**Arène :** petite pièce abstraite ou horizon neutre, sol mat, aucun objet distrayant. Les cibles sont des sphères ou disques 3D à silhouette franche, avec matériau simple ; l’éclairage doit servir à lire le relief, pas à impressionner.

**Personnalisation minimale :** couleur de fond, des cibles normales, des cibles prioritaires et du viseur ; contraste élevé ; taille du viseur ; épaisseur ; point central ou croix ; suppression du réticule optionnelle pour les modes spécifiques.

**À désactiver par défaut :** motion blur, profondeur de champ, chromatic aberration, vignette, caméra secouée, animation de zoom non nécessaire, bloom envahissant, volumétrie, ombres dynamiques inutiles et particules lourdes. Chaque effet non essentiel augmente la charge et complique la lecture des cibles.

**Feedback de hit :** changement bref de couleur ou disparition instantanée/contrôlée, petit son sec facultatif, chiffre de score discret. Il doit être évident qu’une cible est touchée, sans flash aveuglant ni feedback différé.

### 13.2 UI/HUD

- Typographie lisible sans effet de style excessif ; contraste de texte adapté.
- Fond sobre, palettes cohérentes et peu de couleurs simultanées.
- UI **non intrusive** pendant l’exercice ; données de performance dans une zone optionnelle.
- Navigation clavier et souris ; Tab dans les menus, Enter pour lancer/valider, Esc pour pause/retour.
- Fenêtre dimensionnable pour la configuration et plein écran/fenêtré sans bordure pour l’entraînement ; tester les DPI scaling Windows.
- Messages courts, précis et en français (traduction anglaise simple possible ensuite).

### 13.3 Options graphiques

Résolution, affichage, fréquence du moniteur **lue lorsque disponible**, V-Sync on/off, limite FPS (illimitée, adaptée à l’écran ou sélection manuelle), faible complexité des objets, HUD, thèmes contrastés. Exposer les conséquences possibles : V-Sync peut améliorer le tearing mais changer la latence, « illimité » peut chauffer le système et dégrader le frametime. **Ne pas imposer une configuration « pro » universelle.**

### 13.4 Audio

Trois canaux optionnels : hit, miss, compte à rebours/fin. Volume individuel, silence complet possible, aucun fichier audio sous licence inconnue. Éviter tout son qui masque la réactivité perçue du hit.

---

<a id="chapitre-14"></a>

## 14. Performance, latence et instrumentation

### 14.1 Budgets temporels

| Fréquence de rendu | Temps de frame disponible |
|---|---:|
| 60 FPS | 16,67 ms |
| 120 FPS | 8,33 ms |
| 144 FPS | 6,94 ms |
| 240 FPS | 4,17 ms |
| 360 FPS | 2,78 ms |

Le jeu doit **viser des frametimes stables** plutôt que le plus grand compteur FPS possible. Sur le poste de développement haut de gamme, 240 FPS est une **cible de performance à évaluer**, pas une promesse pour tous les utilisateurs. Sur du matériel plus modeste, viser 60/120/144 FPS selon l’écran et les ressources.

### 14.2 Mesures à exposer en mode diagnostic

- FPS moyen, 1 % low approximatif si échantillonnage correct, `frametime_p95/p99` ; période de mesure et méthode déclarées.
- Nombre de cibles, nœuds visibles, draw calls, charge script et physique lorsque Godot permet de les lire.
- Compteur d’événements souris reçus/s (information indicative, non équivalente au polling rate du capteur).
- Mode capture souris et paramètre d’accumulation de l’input.
- Temps mesuré entre **réception logicielle du clic** et **validation logique** du hit ; ne pas le baptiser « input-to-photon latency ».
- Détection des frames aberrantes, des opérations d’écriture disque et des transitions de focus.

### 14.3 Optimisations à privilégier

1. Réutiliser les cibles via **object pooling** plutôt que créer/supprimer des nœuds à chaque hit dans les modes rapides.
2. Précharger les ressources au menu/compte à rebours, jamais sur le chemin d’un tir.
3. Utiliser géométrie simple et matériaux partagés ; réduire le nombre de changements de matériaux/draw calls.
4. Ne pas recalculer les statistiques/historiques à chaque frame.
5. Tamponner les résultats en mémoire et persister à la fin d’une épreuve / lors d’une transition sûre.
6. Utiliser des fonctions mathématiques déterministes pour les trajectoires simples ; ne pas sur-solliciter la physique 3D si un test analytique suffit.
7. Distinguer les problèmes d’input à 8 kHz et les problèmes graphiques : mesurer les deux indépendamment.

### 14.4 Tests de matériel

**Matrice cible :**

| Classe | Exemples de test | Objectif |
|---|---|---|
| Poste de développement | 7800X3D, RX 7900 XT, souris 1000–8000 Hz, écran haut Hz | Profilage et stress-test |
| PC gaming moyen | CPU 6 cœurs récent, GPU intermédiaire, 144 Hz | Réalisme de la diffusion |
| Portable/bas de gamme | iGPU ou ancienne carte compatible, écran 60 Hz | Dégradation maîtrisée et compatibilité |
| Logiciel Windows | Windows 10/11, 100/125/150 % de scaling, mono/multi-écrans | Input et UI invariants |
| Modes vidéo | Fenêtré, bordureless et fullscreen si disponible | Focus, latence apparente, rendu |

**Plan de benchmark :** 1 minute de cible statique, 1 minute de tracking rapide et 1 minute de spam de clics ; répétitions à 1/4/8 kHz avec le même scénario, même seed et mêmes options. Stocker résultats et capture vidéo/graphes en laboratoire, sans affirmer un seuil universel.

### 14.5 Mesures de latence physiques (facultatives, version avancée)

Une vraie mesure input-to-photon requiert une référence physique ou un protocole instrumenté : capture à haute vitesse du geste/clic et de la première frame affichant le résultat, ou montage matériel approprié. Le temps système entre `on_mouse_button()` et `on_hit()` est uniquement **une latence interne au programme**, souvent bien inférieure à la latence globale.

---

<a id="chapitre-15"></a>

## 15. Validation : tests automatiques, manuels et critères de qualité

### 15.1 Pyramide de tests

**Tests unitaires sans scène 3D :** mathématiques DPI/`cm/360`, angles et degrés, FOV, normalisation, conversion, score, horloges, validation de données, migration JSON et arrondis.

**Tests d’intégration :** `ScenarioDefinition` → création → timer → tir → résultat ; tracking avec trajectoire déterministe ; pauses ; perte de focus ; changement de sensibilité ; sauvegarde/rechargement ; erreurs d’import.

**Tests de jeu automatisés :** input synthétique, trajectoires de la caméra, séquences d’apparition, conditions de victoire, hits aux limites des sphères, comptage exact des événements.

**Tests manuels sur vrai PC :** ressenti du mouvement, calibrage physique, alt-tab, polling rate, stabilité audio/rendu, géométries réelles et couleurs. Aucune batterie purement automatisée ne remplace ce point.

### 15.2 Tests mathématiques de référence

| ID | Entrée | Résultat / propriété |
|---|---|---|
| MATH-01 | 800 DPI, CS2 sens `2`, yaw `0,022` | `25,9772727 cm/360°` |
| MATH-02 | CS2 sens 2 → Valorant, DPI identique, yaw 0,07 | sens `0,6285714…` |
| MATH-03 | MATH-02 inverse | sens CS2 ≈ 2, sous tolérance de calcul |
| MATH-04 | Même sensibilité, DPI doublé | `cm/360` divisé par deux, si yaw identique |
| MATH-05 | DPI nul ou négatif | Erreur de validation, pas crash/`NaN` |
| MATH-06 | hFOV 90°, aspect 16:9 | vFOV ≈ 58,72° |
| MATH-07 | Un mouvement de 500 counts vs 200+300 counts | Rotation totale identique |
| MATH-08 | 45 s actives + 20 s de pause | `active_duration_s = 45`, pas 65 |
| MATH-09 | Tracking « sur cible » 30 s sur 45 s exposées | Ratio 66,666… % quel que soit FPS |
| MATH-10 | 0 tirs | Précision « N/A », aucune division par zéro |

### 15.3 Tests de collisions / scénario

- Clic sur bord de hitbox : comportement cohérent entre raycast et silhouette.
- Cibles superposées : règle de priorité déterministe.
- Apparition/départ au même instant qu’un tir : ordre défini et reproductible.
- Cibles mobiles rapides à 60 vs 240 FPS : mêmes résultats pour un replay synthétique équivalent.
- Spam de clics : un clic pressé = un tir, pas deux ; limitation optionnelle suivant scénario.
- Restart : aucune ancienne cible, timer, statistique ou signal résiduel.
- Fenêtre inactive : l’exercice se met en pause ; aucun événement de mouvement hors focus compté.
- Une session avortée ne peut devenir un record.
- Un fichier de scenario invalide provoque une erreur explicite et un retour sûr au menu.
- Un fichier de données endommagé n’empêche pas de lancer l’application.

### 15.4 Tests de qualité non fonctionnelle

| Critère | Condition d’acceptation proposée |
|---|---|
| Installation | Un utilisateur non développeur peut lancer l’application depuis un ZIP Windows sans installer Godot |
| Démarrage | Menu visible et interactif sans connexion Internet |
| Entrée souris | Pas de sensibilité modifiée par les FPS/résolution ; tests physiques et synthétiques documentés |
| Framerate | Jeu fluide sur les profils matériels déclarés, p99 instrumenté ; pas de gros gel pendant un tir |
| Sauvegarde | Une session terminée réapparaît après fermeture/reprise |
| Export | CSV/JSON lisibles avec dates, unités et révisions |
| Pause/focus | Pas de point fantôme, curseur récupérable, chronomètre correct |
| Configuration | Un profil valide donne des résultats reproductibles ; une valeur invalide affiche un message clair |
| Sécurité | Pas de modification cachée des paramètres d’un FPS tiers |
| Accessibilité | Contrastes suffisants, sons désactivables, commandes utilisables sans souris capturée dans les menus |
| Documentation | README compréhensible, historique des versions, limites des conversions explicites |

### 15.5 Qualité automatisée dans le dépôt

- Scripts/ressources parseables par Godot **sans erreur**.
- Tests unitaires et d’intégration exécutables en local, idéalement depuis CLI headless.
- Validation automatique de tous les JSON de `content/scenarios` et `content/games`.
- Vérification qu’aucun scénario n’utilise de champ inconnu silencieusement : refuser ou avertir suivant `schema_version`.
- Revue des changements avec comparatif de fichiers, résumé des tests effectivement exécutés et anomalies ouvertes.
- Export Windows de **release** testé après chaque jalon significatif ; aucun code « prêt » sans ouverture du `.exe` au moins sur le poste principal.

---

<a id="chapitre-16"></a>

## 16. Distribution sous Windows : de Godot à un `.exe`

### 16.1 Mise en place initiale sur un PC Windows

1. Télécharger **Godot 4.7.2 stable** depuis l’archive officielle [S15] ; extraire dans un dossier, par exemple `C:\Dev\Godot\`.
2. Installer Git et, si souhaité, VS Code ; connecter Codex au répertoire local du futur projet.
3. Créer un projet Godot 3D intitulé `AimLocal`. Choisir **Compatibility** pour démarrer (ou tester Mobile si performance mesurée supérieure).
4. Dans Godot, lancer une première scène `Main.tscn` en dehors de tout assistant magique : une fenêtre, un menu et un bouton « Test souris » suffisent.
5. Installer les **export templates** correspondant exactement à la version Godot choisie via l’interface d’export.
6. Ajouter un preset **Windows Desktop**, architecture **x86_64**, mode release. Choisir si le pack de données est **embarqué** dans l’EXE ou livré séparément [S7].
7. Faire un **premier export immédiatement**, même si le jeu ne montre encore qu’un menu : cela détecte tôt les problèmes de version, chemins et packaging.

### 16.2 Commandes terminal (à exécuter par Codex ou manuellement)

Depuis PowerShell, dans le dossier racine du projet (si Godot est dans le PATH sous le nom `godot`) :

```powershell
# Depuis le répertoire qui contient project.godot
# Le préset 'Windows Desktop' doit d'abord exister dans export_presets.cfg.
New-Item -ItemType Directory -Force -Path .\dist | Out-Null

godot --headless --path . --editor --import

godot --headless --path . --export-release "Windows Desktop" "dist/AimLocal.exe"
```

Sinon, remplacer `godot` par le **chemin réel** de `Godot_v4.7.2-stable_win64_console.exe` (ou le nom exact téléchargé), en utilisant l’opérateur PowerShell `&` :

```powershell
& "C:\Dev\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --editor --import
```

**À vérifier :** l’export peut produire un **`.pck`** en plus de l’EXE si l’option d’embarquement n’est pas activée. Dans ce cas, distribuer **les deux fichiers**, sans changer leurs noms indépendamment, dans un ZIP. Ne jamais annoncer « un seul EXE » avant d’avoir inspecté le résultat. Les options CLI d’export sont documentées par Godot [S16].

### 16.3 Package de diffusion

```text
AimLocal-v1.0.0-windows-x64.zip
└─ AimLocal/
   ├─ AimLocal.exe
   ├─ AimLocal.pck              # Seulement si pack non embarqué
   ├─ README.txt
   ├─ CHANGELOG.txt
   └─ LICENSES/
      └─ GODOT_LICENSE.txt
```

**Comportement attendu :** double-clic sur `.exe` ; création automatique des données dans `user://`, sans droits administrateur et sans connexion. Le dossier de sauvegarde doit être consultable via un bouton dans les options. Un antivirus/SmartScreen peut avertir pour un exécutable artisanal non signé ; expliquer la provenance et, si diffusion publique, prévoir **signature du code** [S7]. Ne jamais proposer de désactiver l’antivirus pour contourner un problème de distribution.

### 16.4 Tester le ZIP comme un véritable destinataire

- Copier le ZIP sur une **autre machine** ou dans un dossier utilisateur Windows vierge.
- Extraire ; exécuter sans Godot installé ; s’assurer qu’aucune DLL/ressource manque.
- Tester le premier lancement, l’exercice, la sauvegarde, la fermeture, le relancement et l’export de données.
- Vérifier fonctionnements sans accès réseau, sans admin, avec clavier/souris standard.
- Vérifier Windows Defender/SmartScreen et l’identification de l’éditeur ; envisager la signature si nécessaire.
- Sauvegarder une release précise avec son commit Git, le hash SHA-256 du ZIP et la version des templates Godot.

### 16.5 Automation de build, étape ultérieure

Une GitHub Actions Windows peut : récupérer une version **épinglée** de Godot et ses templates, importer le projet, valider les données/tester, exporter, archiver le résultat et le joindre à une Release. Épingler les actions officielles ou de confiance par version/commit et protéger les permissions du dépôt. Ne pas ajouter une CI complexe tant que l’export local n’a pas réussi plusieurs fois.

---

<a id="chapitre-17"></a>

## 17. Développer le projet avec ChatGPT et Codex : méthode concrète

### 17.1 Répartition des rôles

| Outil / rôle | Travail principal |
|---|---|
| **Utilisateur** | Évaluer le ressenti de l’aim, mesurer les mouvements physiques, valider les exercices, signaler les défauts |
| **ChatGPT — conception produit** | Clarifier les règles, décomposer le backlog, détailler les critères d’acceptation, challenger les hypothèses |
| **Codex — implémentation** | Créer/modifier les `.gd`, `.tscn`, contenus JSON, tests ; lancer les commandes de build/test dans l’environnement où il a accès au projet |
| **Godot Editor** | Visualiser et tester les scènes en temps réel, vérifier input et gameplay |
| **Git/GitHub** | Historique, retours arrière, branches, revues et distribution de versions |
| **Auditeur IA** | Relire chaque jalon au regard des tests, du budget performance et de ce cahier des charges |

**Important :** ChatGPT en conversation ne pilote pas automatiquement un éditeur Godot local par le seul fait d’avoir ce fichier Markdown. Pour manipuler **réellement** le dépôt, les commandes et l’application Windows, Codex doit avoir accès au répertoire et à l’environnement d’exécution. Inversement, même avec cet accès, l’IA ne peut pas ressentir physiquement la souris à la place du joueur.

### 17.2 Créer et tenir à jour la référence

- Placer ce document à `docs/SPECIFICATION.md` dans le dépôt.
- Ajouter `AGENTS.md` à la racine : objectifs, chemins, commandes, règles d’architecture, fichiers à ne pas modifier et protocole de validation.
- Conserver `docs/DECISIONS.md` pour noter les arbitrages (ex. « Compatibility retenu après bench », « accumulation input activée par défaut »).
- Chaque prompt Codex doit pointer sur **une fonctionnalité limitée**, sa définition « terminé » et des tests précis.
- Demander à Codex une courte sortie structurée : **fichiers modifiés, commandes réellement lancées, résultats réels, limites, points à tester physiquement**.

### 17.3 Boucle de réalisation recommandée

```text
Besoin → Spécification → Petit lot de code → Tests auto
      → Ouverture Godot → Essai souris réel → Correction
      → Commit Git → Passage au lot suivant
```

Ne pas confier « 55 exercices + gestion souris + export + UI » dans un seul prompt et accepter un résultat qui « compile » comme gage de qualité. L’approche efficace est de **faire fonctionner 1 exercice de bout en bout**, puis généraliser.

### 17.4 Travail en branches / retours arrière

- `main` : version jouable et exportable.
- `feature/raw-input-diagnostics`, `feature/scenario-t01`, etc. : un objectif précis.
- Commits décrivant les changements ; chaque jalon inclut un tag (`v0.1-prototype`, `v0.2-input`, etc.).
- Ne jamais fusionner du code sans savoir si Godot l’a analysé correctement et si les tests disponibles ont été exécutés.
- En cas de bug introduit par une génération IA, revenir au dernier commit fonctionnel plutôt que multiplier les patchs aléatoires.

---

<a id="chapitre-18"></a>

## 18. Connecteurs, MCP et services externes : faut-il en installer ?

### 18.1 Réponse synthétique

**Non, aucun connecteur/MCP n’est nécessaire pour construire la V1.** Un projet Godot local, un système de fichiers accessible, un terminal et Git suffisent. Le serveur MCP est un moyen pour un assistant IA de **communiquer avec des outils externes** ; il n’améliore pas en lui-même la précision du mouvement souris ni la latence.

### 18.2 Ce qui peut vraiment aider

| Intégration | Usage | Priorité | Réserve |
|---|---|---|---|
| **GitHub (connecteur natif ou GitHub MCP officiel)** | Dépôt, issues, PR, CI, releases | **Facultatif, utile P1** | Permissions minimales, accès au dépôt seulement [S17] |
| CLI Godot et terminal local | Exécution, tests, exports, recherche de logs | **Très utile dès P0** | Ce n’est pas un MCP nécessaire ; le terminal local suffit |
| Recherche documentation Godot/Windows | Vérifier les API et les changements de version | **Très utile dès P0** | Privilégier les docs officielles et adaptées à 4.7.2 |
| MCP communautaire pour piloter Godot | Actions dans l’éditeur depuis un agent | **Optionnel P2** | Fiabilité/permissions/maintenance à auditer ; pas une dépendance cœur |
| Gestionnaire de tâches (GitHub Issues/Projects) | Suivi des jalons et anomalies | Optionnel | Peut être fait dans `docs/BACKLOG.md` au début |
| Cloud analytics, Firebase, comptes | Classement en ligne, synchro | **À exclure V1** | Coûts, RGPD, sécurité, complexité inutiles |
| Services d’IA « entraînement optimal » | Recommandation automatique | **À exclure V1** | Peu de données initiales et résultats potentiellement trompeurs |

### 18.3 Sécurité des connecteurs

- N’installer que des MCP identifiés, maintenus, dont le code et les permissions peuvent être contrôlés.
- Ne pas donner à un agent les accès administrateur Windows, des clés API globales, ni l’autorisation d’exécuter des scripts distants inconnus.
- Pour GitHub, limiter le jeton au **dépôt** et aux droits nécessaires ; commencer en **lecture seule** si c’est suffisant.
- Les descriptions d’issues/PR et les pages web peuvent contenir des consignes malveillantes : elles restent du **contenu**, pas des instructions que l’IA doit suivre à l’aveugle.
- Ne jamais exposer des secrets dans les logs, le chat, les commits ou un `.json` du projet.
- Toute écriture dans des fichiers de jeu tiers et tout lancement d’un exécutable non contrôlé doivent rester soumis à confirmation explicite.

**Si ChatGPT/Codex dispose déjà d’une intégration GitHub native, ne pas empiler un deuxième MCP identique sans besoin.**

---

<a id="chapitre-19"></a>

## 19. Licence, sécurité et respect des jeux tiers

### 19.1 Licence de l’application

Godot est sous **licence MIT** [S18]. Le jeu créé peut choisir sa propre licence, mais la distribution doit respecter les mentions de licence et composants tiers nécessaires. Conserver un dossier `LICENSES/` ou un écran crédits. Les icônes, polices et sons doivent eux aussi être utilisables sous leurs licences.

### 19.2 Différenciation vis-à-vis d’Aim Lab

Le projet s’inspire du **genre aim trainer**, mais ne doit pas recopier des interfaces, logos, marques, images, ressources propriétaires, code ou bases de données protégées. Utiliser un nom, une palette et des illustrations originaux. Les noms Valorant/CS2/Call of Duty peuvent servir à indiquer une **compatibilité de paramètres**, avec une mention « non affilié » appropriée si publication.

### 19.3 Sécurité locale et vie privée

- Application hors ligne par défaut, aucune requête réseau nécessaire.
- Pas de privilèges administrateur et pas de services Windows installés.
- L’input souris/clavier est utilisé **uniquement lorsque l’application a le focus** ; aucune collecte globale, aucun keylogger.
- Journaux techniques limités au nécessaire, sans texte tapé dans d’autres applications.
- Données locales consultables, exportables et supprimables par l’utilisateur.
- Les fichiers importés doivent être limités en taille, validés et traités comme non fiables ; aucun script embarqué dans un scénario fourni par un tiers.
- Packaging reproductible, hash des releases, contrôle antivirus/SmartScreen.

---
<a id="chapitre-20"></a>

## 20. Roadmap : développement par livrables vérifiables

La séquence suivante est volontairement **ordonnée par risques**. L’ordre de travail compte plus que le nombre de fonctions annoncées. Aucune phase suivante ne doit servir à masquer un défaut de la précédente.

### Phase 0 — Initialisation, dépôt et premier exécutable

**Livrables :** projet Godot ouvrable, `Main.tscn`, écran minimal, `AGENTS.md`, structure des dossiers, `.gitignore`, `README.md`, `export_presets.cfg`, premier `AimLocal.exe` fonctionnel, version de Godot épinglée.

**Critères de sortie :** Godot ouvre le projet sans erreur ; un clic dans le menu fonctionne ; export Windows release réussi ; EXE démarré hors de l’éditeur ; Git contient un commit restaurable.

### Phase 1 — Prototype d’input et calibration angulaire

**Livrables :** arène vide et caméra FPS, viseur, capture/libération de souris, compteur de counts/deltas, système `degrees_per_count`, écran de diagnostics, protocole de rotation et calcul `cm/360`.

**Critères de sortie :** mêmes counts → même rotation à FPS différents ; pas de scaling souris lié à la résolution ; perte de focus propre ; essais vrais souris à 1000 Hz puis taux plus élevés ; affichage de la rotation attendue.

**Décision après phase :** mesurer et fixer provisoirement la configuration d’accumulation de l’input et le renderer ; tout choix est noté dans `docs/DECISIONS.md`.

### Phase 2 — Premier exercice parfaitement fonctionnel : C01

**Livrables :** cible sphérique, génération, collision du tir, animation/feedback minimal, chronomètre, hits/miss, fin de séance, bouton Rejouer.

**Critères de sortie :** aucune touche fantôme, pas de double comptage, timing indépendant du FPS, scénario possible en 30/60 secondes, tests des bords de hitbox, reprise après pause correcte.

### Phase 3 — Moteur de scénario data-driven + résultats sauvegardés

**Livrables :** `ScenarioDefinition`, validateur, RNG seed, moteur générique, résultat JSON local, lecteur/affichage de l’historique, premier tableau de progression.

**Critères de sortie :** deux variantes de C01 réalisables **uniquement en changeant les données**, sans duplication du moteur ; fermeture/reprise conserve les résultats ; JSON corrompu géré sans perte silencieuse.

### Phase 4 — Tracking et switching de référence

**Livrables :** T01, T05 et S01 ; lois de déplacement ; intégration temporelle du tracking ; diagnostics de précision, erreur angulaire et réacquisition.

**Critères de sortie :** même tracking synthétique à 60/144/240 FPS → score équivalent dans tolérance ; cible rapide visuellement cohérente avec hitbox ; cibles de switching correctement identifiées et retirées.

### Phase 5 — Convertisseur FPS fiable

**Livrables :** `SensitivityService`, profils DPI, CS2/Valorant hipfire, custom `cm/360`, convertisseur, validation, bouton copier, fiche de profil et marquage de confiance.

**Critères de sortie :** tests MATH-01 à 10 réussis ; conversion aller-retour stable ; limites FOV/ADS visibles ; aucune écriture cachée dans un jeu tiers ; calibration physique utilisable.

### Phase 6 — Catalogue, routines et pauses

**Livrables :** 10–15 exercices **P0/P1 testés**, bibliothèque filtrable, routine éditable, pauses, transitions stables, résultats de routine.

**Critères de sortie :** une routine complète s’exécute sans avoir à retourner au menu ; l’abandon n’est pas compté comme un record ; le même scénario dans deux routines utilise la même implémentation.

### Phase 7 — Progression et coaching descriptif

**Livrables :** courbes, comparaisons valides, records, médianes, export CSV/JSON, suivi des conditions, recommandations explicables.

**Critères de sortie :** une modification de difficulté ne produit pas de « faux progrès » comparé au scénario de référence ; données manquantes signalées ; export/import d’échantillons valides.

### Phase 8 — Assistant expérimental de sensibilité

**Livrables :** protocole multi-candidates, ordre contrebalancé, familiarisation, pauses, comparaison par compétence, dispersion et plage suggérée.

**Critères de sortie :** le système n’affiche pas de gagnant péremptoire quand les écarts sont faibles ; l’utilisateur peut conserver son réglage d’origine ; hypothèses et incertitude visibles.

### Phase 9 — Qualité produit et diffusion

**Livrables :** 20–30 variantes de scénarios réellement testées (puis enrichissement vers le catalogue complet), options vidéo, préférences UI, tests sur un deuxième PC, documentation utilisateur, logo original simple, ZIP de distribution, release GitHub éventuelle.

**Critères de sortie :** la checklist d’acceptation globale est passée, y compris export, sauvegarde, récupération de la souris, absence de ralentissements anormaux au stress test et vérification des licences.

### Phase 10 — Enrichissement contrôlé

**Après release jouable :** enrichir vers les **55 exercices/variantes recensés**, ajouter des adaptateurs de jeux vérifiés titre par titre, comparer plusieurs méthodes de FOV/ADS, SQLite éventuel, replays de diagnostic, partage volontaire de routines, et seulement ensuite explorer classements/services en ligne.

---

<a id="chapitre-21"></a>

## 21. Backlog priorisé — exigences traçables

| Code | Exigence | Priorité | Démonstration de réussite |
|---|---|---|---|
| REQ-001 | Démarrer depuis EXE Windows sans Godot installé | P0 | Test sur machine propre |
| REQ-002 | Capturer souris et mesurer mouvement relatif sans dépendre du FPS | P0 | IN-01 à IN-03 |
| REQ-003 | Pause, reprise, focus, sortie souris sans blocage | P0 | IN-06 + tests UI |
| REQ-004 | Cibles sphériques 3D flat, contrastées | P0 | Capture + test manuel |
| REQ-005 | C01 avec tirs hits/misses et temps cohérents | P0 | Intégration automatisée |
| REQ-006 | Enregistrer/recharger profil DPI et sensibilité | P0 | Test redémarrage |
| REQ-007 | Calculer `cm/360` et conversion aller-retour | P0 | MATH-01 à 05 |
| REQ-008 | Sauvegarder résultat local, y compris contexte | P0 | Persistence roundtrip |
| REQ-009 | T01 tracking sur durée réelle | P0 | MATH-09 et test 60↔240 FPS |
| REQ-010 | S01 switching sans double comptage | P0 | Test séquence simulée |
| REQ-011 | Charger scénario depuis données validées | P0 | Changer taille/vitesse sans nouveau code |
| REQ-012 | Historique local avec comparaison même contexte | P1 | Comparateur refuse difficulté différente |
| REQ-013 | Interface d’exercices avec filtres | P1 | Parcours utilisateur |
| REQ-014 | Éditeur simple de routines et pauses | P1 | Routine complète testée |
| REQ-015 | Convertisseur CS2/Valorant et profil custom | P1 | Test numérique + physique |
| REQ-016 | Copier une valeur paramètre vers presse-papiers | P1 | Coller dans un éditeur et vérifier |
| REQ-017 | Diagnostics 1000/4000/8000 Hz | P1 | Benchmark comparatif |
| REQ-018 | Export CSV/JSON de toutes les séances | P1 | Relecture externe |
| REQ-019 | 10–15 exercices testés | P1 | Test standard par scénario |
| REQ-020 | Assistant de comparaison de sensibilité | P1 | 3 candidates / répétitions / dispersion |
| REQ-021 | Recommandations explicables d’exercices | P2 | Justification affichée |
| REQ-022 | Adaptateurs spécifiques CoD par version | P2 | Documentation + mesure avant activation |
| REQ-023 | Lecture contrôlée de fichiers de config jeux | P2 | Allowlist, tests, aucune écriture silencieuse |
| REQ-024 | Replays détaillés, diagnostics input à haute fréquence | P2 | Fichier temporaire borné/reproductible |
| REQ-025 | CI automatique et signatures de release | P2 | Workflow testé et package vérifié |

---

<a id="chapitre-22"></a>

## 22. Risques, erreurs courantes et décisions de mitigation

| Risque | Symptôme | Cause probable | Atténuation |
|---|---|---|---|
| Sensibilité qui varie avec le FPS | Le même mouvement donne une rotation différente | Multiplication par `delta`, double traitement ou échelle `relative` | `screen_relative`, tests synthétiques, unités explicites |
| FPS qui chute avec souris 8 kHz | Jeu saccadé seulement lorsqu’on bouge la souris | Traitement d’événements trop coûteux / ancien Godot | Godot 4.7.2+, `_input()` léger, benchmarks [S1] |
| Hitbox en retard sur la cible | Le joueur voit une touche mais l’outil la rate | Position de simulation ≠ position affichée | Snapshot cohérent au clic, test temporel |
| Temps de tracking faussé | Score dépend des FPS | Comptage des frames | Intégration des durées réelles |
| Scénarios difficiles à maintenir | Chaque exercice contient du code dupliqué | Pas de moteur commun | Scénarios data-driven, comportements composables |
| « Conversion exacte » trompeuse | Même `cm/360`, ressenti différent | FOV/ADS/ratio/accélération ignorés | Niveau de confiance, choix de méthode, validation en jeu |
| Sauvegarde corrompue | Perte de profil après crash | Écriture interrompue | Temp + backup + migration + récupération |
| Scores artificiellement gonflés | Records obtenus avec cibles énormes ou très faciles | Mauvaise comparabilité | Clé de scénario/difficulté/révision |
| Régression introduite par IA | Une correction casse plusieurs modes | Prompt trop large, aucun test | Lots courts, tests, Git, validation du `.exe` |
| Dépendances MCP fragiles | Build lié à un outil tiers | Outil central alors que facultatif | Pas de MCP requis au cœur, accès local standard |
| Conflit de licence / marque | Problème à la diffusion | Assets ou branding copiés | Créations originales, attribution de Godot et des tiers |
| Trop d’options dès le début | Menus compliqués, cœur non testé | Scope creep | P0 puis P1, fonctionnalités avancées masquées |

---

<a id="chapitre-23"></a>

## 23. Prompts prêts à utiliser avec Codex

**Mode d’emploi :** ouvrir **le dossier du dépôt Godot** avec un agent Codex qui peut lire/écrire les fichiers et lancer Godot/PowerShell. Copier un prompt à la fois. Chaque prompt suppose la présence de `docs/SPECIFICATION.md`. Demander explicitement une synthèse des tests **réellement exécutés**, pas des tests supposés. Les instructions ci-dessous s’adressent à cet agent de développement, pas au jeu lui-même.

### Prompt 0 — Initialiser le dépôt et produire un premier build

```text
Tu travailles dans un dépôt Windows pour le projet AIM/LOCAL.
Lis entièrement docs/SPECIFICATION.md, en particulier les sections 0, 2,
11, 15, 16 et la Phase 0. Utilise Godot 4.7.2 stable + GDScript.

Objectif unique : initialiser un projet Godot propre, une scène Main.tscn
fonctionnelle, un écran d'accueil minimal avec un bouton Test, README,
AGENTS.md, .gitignore, arborescence suggérée et preset export Windows x64.
Ne code encore AUCUN gameplay complexe.

Contraintes : n'ajoute pas de dépendance externe sans nécessité ni demande,
ne modifie aucun fichier d'un jeu tiers, garde la possibilité de faire un
export offline. Si Godot est installé, détecte sa version, lance l'import
headless, vérifie les erreurs du projet et réalise un export Windows release.
Si l'outil n'est pas installé, indique exactement ce qui manque ; ne simule
pas une compilation réussie. Ne cache aucun message d'erreur.

Termine avec : liste des fichiers, commandes et résultats exacts des tests,
chemin de sortie de l'exécutable s'il existe, et prochaine tâche minimale.
```

### Prompt 1 — Fiabiliser l’input FPS

```text
Lis docs/SPECIFICATION.md sections 4, 5, 14 et 15.
Implémente uniquement l'InputBackend, la caméra FPS et un écran diagnostic.

Utilise MOUSE_MODE_CAPTURED pour l'entraînement et
InputEventMouseMotion.screen_relative. Définis un multiplicateur explicite
de degrés/count, aucun facteur frame delta. Gère pause, Esc, Alt+Tab,
perte/reprise de focus, inversion Y, limites de pitch et logs optionnels.
Expose un compteur de mouvements reçus, yaw/pitch accumulés et `cm/360`.

Écris des tests déterministes : 1000 counts d'un bloc contre 200+300+500,
différentes durées de frames, résolution/window scaling simulé si possible.
Mesure les modes Input.use_accumulated_input true/false sans choisir une
configuration par supposition. Fournis un guide de vérification physique.
N'ajoute pas encore de scores ni de bibliothèque d'exercices.

Résultat attendu : projet exécuté et testé ; mentionne toute incertitude
qu'un essai sur souris réelle doit lever.
```

### Prompt 2 — Un exercice C01 de bout en bout

```text
Lis sections 7.2, 8, 9.2, 10.3 et Phase 2 de la SPECIFICATION.
Implémente C01 Static Single : sphère 3D simple, spawn valide en degrés,
viseur, clic/hit/miss, chronomètre, pause, fin, écran résultat et Rejouer.
Ne crée pas une architecture de 55 scènes copiées.

Sépare explicitement Input, CameraAim, Target, HitDetection et
SessionRecorder. Définis un ordre d'événements sans double comptage.
Écris tests pour tir sur cible, hors cible, clic pendant pause, restart,
fin de timer et clic sur frontière hitbox.

Accepte le changement de durée/taille sans modifier la logique de collision.
Fais un export Windows release et décris ce qui a été effectivement vérifié.
```

### Prompt 3 — Rendre les exercices data-driven

```text
Lis sections 7.8, 8, 11 et 12 de docs/SPECIFICATION.md.
Refactore C01 pour le piloter depuis une définition de scénario validée.
Crée les schemas typés GDScript nécessaires et deux variantes distinctes
chargées depuis des fichiers de données, sans recopier le moteur.

Ajoute la seed de scénario, horloge monotone, états explicites et un
validateur strict (bornes, unités, valeurs inconnues). Vérifie aussi que les
ressources .json sont effectivement intégrées à l'export Godot Windows
(voir filtre d'inclusion des fichiers non-ressources dans le preset).

Tests : JSON invalide, taille négative, cible hors écran, même seed = mêmes
spawns, exporter puis démarrer le scénario depuis le EXE, pas seulement
l'éditeur. Fournis résultat exact de chaque test.
```

### Prompt 4 — Tracking T01 et T05 sans score dépendant du FPS

```text
Lis sections 7.4, 8.4, 8.5, 9.3 et 15.
Ajoute T01 Smooth Horizontal puis T05 Strafe Track en réutilisant le
ScenarioEngine. Mesure le temps sur cible en secondes réelles et l'erreur
angulaire de visée. Ne compte JAMAIS des frames comme des millisecondes.

Définis une position de cible cohérente entre rendu et hit-test, y compris
au moment d'un changement de direction. Tests synthétiques sur les mêmes
séquences à 60, 144 et 240 FPS : score comparable, sans cible fantôme.
Affiche l'accuracy tracking, l'erreur moyenne et p95, et le temps actif.
N'invente pas de données de performance si non mesurées.
```

### Prompt 5 — Convertir correctement les sensibilités

```text
Lis entièrement les sections 5 et 6, ainsi que les sources S10 à S12.
Crée un SensitivityService testable indépendamment du rendu, avec unités
explicites : DPI, coefficient deg/count/unité de sens, sens, cm/360, FOV.

Profils V1 : CS2 avec m_yaw paramétrable, Valorant hipfire avec coefficient
identifié comme valeur documentaire tierce, et jeu custom renseigné par
l'utilisateur. Ajoute saisie/validation, sauvegarde, bouton presse-papiers,
conversion A→B avec DPI différents, résultat arrondi et avertissements
FOV/ADS. Ne touche PAS aux fichiers ni processus de jeux tiers.

Écris et exécute tous les tests MATH-01 à MATH-10 pertinents. Vérifie
l'exemple CS2 2,0/800 DPI → Valorant 0,6285714. Prévois un protocole de
mesure physique cm/360 et un indicateur de confiance explicite.
```

### Prompt 6 — Historique, scores et progressions fiables

```text
Lis les sections 9 et 12. Conçois une persistance locale versionnée dans
user:// avec sauvegarde atomique/backup, gestion d'erreurs, résultats bruts,
revision des scénarios et profil souris capturé au début de chaque session.

Expose un tableau de résultats avec accuracy, hits/min ou on-target ratio,
score composite versionné et courbe de progression. Refuse par défaut une
comparaison de scores dont scénario, difficulté ou version diffèrent.
Tests : rechargement, migration de fichier, corruption JSON, 0 tirs,
pause non comptée, ancienne séance non modifiée par nouveaux réglages.
```

### Prompt 7 — Routines et déploiement

```text
Lis les sections 10, 16, 20 et 21.
Crée le constructeur simple de routine, les pauses paramétrables et un
parcours complet Warm-up FPS. Ajoute une checklist automatisable de build
Windows, puis génère le ZIP de distribution, README et licences requises.

Teste une routine réellement jouable, la pause, la sortie volontaire, le
redémarrage, l'absence de compte internet et l'ouverture de l'EXE hors Godot.
Tout échec doit être remonté sans être minimisé. Ne désactive aucune
protection Windows et n'ajoute aucun installateur nécessaire au MVP.
```

### Prompt 8 — Audit contradictoire avant release

```text
Agis comme une équipe d'audit : expert Godot 4.7.x, spécialiste input souris
Windows, ingénieur QA, développeur gameplay, analyste de données et expert
distribution Windows. Lis docs/SPECIFICATION.md et inspecte le dépôt réel.

Examine :
- input multiplié à tort par delta, scaling de résolution, mode souris ;
- timestamps, doublons, frames, tracking sur durée réelle ;
- hitbox mobile incohérente avec le rendu ;
- confusion deg/rad, FOV, DPI, eDPI, ADS et cm/360 ;
- scores invalidement comparés entre difficultés différentes ;
- corruption/migration des sauvegardes, perte de focus, restauration souris ;
- performances 1/4/8 kHz, allocations sur _input, frametimes ;
- export Windows et inclusion des fichiers JSON ;
- licences, accès fichiers, modification accidentelle de jeux tiers.

Pour chaque défaut : criticité, reproduction, origine, correctif minimal et
preuve de résolution. N'affirme pas avoir exécuté un test non lancé.
Corrige d'abord les problèmes bloquants, puis re-teste et propose la release.
```

---

<a id="chapitre-24"></a>

## 24. Fichier `AGENTS.md` minimal — exemple à donner à Codex

```markdown
# Règles de développement AIM/LOCAL

- Lire `docs/SPECIFICATION.md` avant toute implémentation majeure.
- Utiliser Godot 4.7.2 stable (ou version corrigée explicitement approuvée),
  GDScript typé là où c'est utile, et une architecture modulaire.
- Priorités : exactitude input > justesse des scores > fluidité > ergonomie > graphisme.
- Les unités sont explicites dans les noms : deg, rad, counts, ms, s, cm.
- Ne jamais multiplier un événement souris par le frame delta.
- Ne pas ajouter de plugin/MCP ni réseau sans besoin validé.
- Aucun hook/injecteur/modification d'un FPS tiers.
- Tout nouveau scénario est piloté par une définition valide et utilise le
  moteur commun ; ne pas dupliquer le cœur gameplay.
- Toujours produire/revoir des tests des calculs et du comportement modifié.
- Après modification : analyser le projet avec Godot et lancer les tests
  disponibles ; signaler honnêtement tout outil non accessible.
- Avant chaque jalon de release : export Windows release et ouverture du jeu.
- Ne jamais modifier les sauvegardes utilisateur existantes sans migration.
- Faire des commits petits, lisibles et réversibles.
```

---

<a id="chapitre-25"></a>

## 25. Scénario de réception : comment savoir que le projet est réellement réussi ?

**Test « une personne qui ne connaît pas Godot » :**

1. Un ami reçoit un ZIP sur Windows.
2. Il extrait le dossier, lance le `.exe`, choisit son DPI et son jeu (ou un `cm/360` mesuré) sans être obligé de créer un compte.
3. Il ajuste si besoin son profil dans un écran clair ; un exercice C01 se lance en deux clics.
4. Les cibles sont lisibles et le viseur répond immédiatement, sans sensation de glisse logicielle indésirable.
5. Les tirs réussis/ratés sont reconnus de façon prévisible ; le tracking ne change pas brutalement de difficulté avec les FPS.
6. Il termine sa séance, voit **ce qu’il a fait** (hits, miss, précision, temps), puis une comparaison raisonnable avec ses essais précédents.
7. Il démarre une routine avec des pauses et retrouve ses résultats le lendemain.
8. Il voit sa sensibilité convertie pour CS2/Valorant avec hypothèses affichées et sait la copier dans le menu du jeu visé.
9. Il peut arrêter à tout moment : Esc libère la souris, le programme ne bloque pas Windows, les données restent locales.
10. Le produit a été testé sur au moins **deux configurations Windows distinctes** et le `README` permet de le lancer sans assistance.

**Si ce parcours fonctionne bien, le projet a déjà une valeur réelle**, même avant d’avoir toutes les variantes spécialisées et les intégrations avancées.

---

<a id="chapitre-26"></a>

## 26. Sources vérifiées et statut des informations

Sources consultées pour **l’architecture et les hypothèses**, à revalider lors de changements majeurs de version. Les formules géométriques et les tests d’acceptation sont des propositions d’ingénierie ; la présence d’une source externe ne transforme pas un choix du projet en spécification officielle d’un jeu tiers.

### Sources techniques prioritaires

- **[S1] Godot Engine (24 août 2026)** — [Fixing high polling rate mice on Windows in Godot](https://godotengine.org/article/fixing-high-polling-rate-mice-on-windows/). Correction du problème de polling rate élevée à partir de Godot **4.7.2** et description de la lecture tamponnée Windows. **Officiel, très pertinent.**
- **[S2] Godot Engine** — [Overview of renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html). Comparaison Forward+, Mobile et Compatibility, choix en fonction du projet. **Documentation officielle.**
- **[S3] Godot Engine 4.7** — [InputEventMouseMotion](https://docs.godotengine.org/en/4.7/classes/class_inputeventmousemotion.html) et [Mouse and input coordinates](https://docs.godotengine.org/en/4.7/tutorials/inputs/mouse_and_input_coordinates.html). Usage de `screen_relative` en capture, accumulation et scaling. **Documentation officielle.**
- **[S4] Microsoft Learn** — [Raw Input Overview](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input), [GetRawInputData](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getrawinputdata) et [Using Raw Input](https://learn.microsoft.com/en-us/windows/win32/inputdev/using-raw-input). API et file d’input Windows. **Documentation officielle.**
- **[S5] Godot Engine (24 août 2026)** — [Étude technique du traitement des souris à haut polling rate](https://godotengine.org/article/fixing-high-polling-rate-mice-on-windows/). Notamment charge potentielle de `_input()` quand l’accumulation est désactivée. **Officiel.**
- **[S6] Godot Engine 4.7** — [File system](https://docs.godotengine.org/en/4.7/tutorials/scripting/filesystem.html) et [File paths in Godot projects](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html). Usage correct de `user://`. **Documentation officielle.**
- **[S7] Godot Engine 4.7** — [Exporting for Windows](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html). Exécutable, PCK, signature de code. **Documentation officielle.**
- **[S8] SDL Wiki** — [SDL3: SetWindowRelativeMouseMode](https://wiki.libsdl.org/SDL3/SDL_SetWindowRelativeMouseMode). Alternative technique pour une application native en contrôle direct de la souris. **Documentation officielle du projet SDL.**
- **[S9] GdUnit4** — [Framework de tests pour Godot](https://github.com/godot-gdunit-labs/gdUnit4). Option communautaire à tester avec la version Godot verrouillée. **Tiers, non obligatoire.**
- **[S15] Godot Engine** — [Télécharger Godot 4.7.2 stable](https://godotengine.org/download/archive/4.7.2-stable/), daté du **18 août 2026**. **Archive officielle.**
- **[S16] Godot Engine 4.7** — [Exporting projects](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html) et [Command line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html). Presets, templates, filtres JSON, CLI. **Documentation officielle.**
- **[S17] GitHub** — [GitHub MCP Server (projet officiel)](https://github.com/github/github-mcp-server) et [documentation GitHub](https://docs.github.com/en/copilot/how-tos/copilot-in-your-ide/customize-copilot/extend-copilot-with-tools-and-context/set-up-the-github-mcp-server). **Optionnel** : accès dépôt/PR/issues/actions.
- **[S18] Godot Engine** — [License](https://godotengine.org/license/) et [Complying with licenses](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html). Licence MIT et notices de redistribution. **Officiel.**

### Sources de paramètres FPS (niveau de confiance différent)

- **[S10] Total CS (tiers spécialisé)** — [CS2: m_yaw](https://totalcsgo.com/commands/myaw). Valeur par défaut documentée `0,022`, modifiable par le joueur. À **valider sur la version et la configuration du jeu**.
- **[S11] Valorant Sensitivity Converter (tiers, 2026)** — [Yaw Value 0.07](https://valorantsensconverter.com/valorant-sensitivity-yaw/). Valeur commune documentée `0,07`. **Pas un contrat d’API Riot Games** ; le site comporte par ailleurs des incohérences textuelles sur le sens de certains rapports : la formule du projet doit être dérivée et testée indépendamment. Ne pas traiter les promesses de « transfert parfait » de sites commerciaux comme une preuve.
- **[S12] Activision (25 octobre 2019)** — [Modern Warfare: Controls and Settings PC](https://blog.activision.com/call-of-duty/2019-10/Getting-Started-in-Modern-Warfare-Controls-and-Settings-PC). ADS Relative/Legacy, Monitor Distance Coefficient, accélération, filtrage et smoothing pour **cet épisode**. **Officiel mais ancien et non transférable tel quel aux autres éditions de Call of Duty.**

### Sources pour la logique d’entraînement (interprétation prudente)

- **[S13] Czyż et al., Scientific Reports (2024)** — [High contextual interference improves retention in motor learning: systematic review and meta-analysis](https://www.nature.com/articles/s41598-024-65753-3). Effets du mélange des pratiques, plus nets dans certains contextes de laboratoire que dans les situations appliquées. **Recherche évaluée par les pairs, non spécifique à l’aim FPS.**
- **[S14] Revue et méta-analyse en sciences du sport (2023/2024)** — [The myth of contextual interference learning benefit in sports practice](https://www.sciencedirect.com/science/article/pii/S1747938X23000301). Résultats plus réservés sur la généralisation du bénéfice en sport. **Contrepoint important.**

### Sources à vérifier lors de l’implémentation d’adaptateurs supplémentaires

1. Documentation/notes du développeur du jeu ciblé, dans la **version exacte** concernée.
2. Méthode et unités de son FOV, en précisant FOV horizontal ou vertical et aspect ratio.
3. Présence d’options ADS, zoom, monitor distance, accélération, smoothing ou de multiplicateurs distincts.
4. Test de rotation physique en conditions reproductibles ; test aller-retour de conversion.
5. Accessibilité **autorisée** des paramètres du jeu : menu, presse-papiers, console documentée, ou lecture de configuration officielle.

---

<a id="chapitre-27"></a>

## 27. Recommandation finale de cadrage

### Ce qu’il faut réellement construire en premier

Un seul flux : **j’ouvre → je renseigne ma souris → je vise une sphère → je tire → j’obtiens un résultat → je recommence**. Ce flux contient déjà toutes les difficultés structurantes : input, timing, géométrie 3D, règles, score, sauvegarde et export. Une fois cette base validée, le tracking et les autres exercices sont des extensions maîtrisées.

### Ordre non négociable des priorités

**1. Fidélité de l’aim et du timing** → **2. Gameplay et hitbox cohérents** → **3. Scores exploitables** → **4. Sensibilité multi-jeux documentée** → **5. Routines et progression** → **6. Richesse du catalogue** → **7. Habillage et diffusion avancée**.

### Les trois preuves à obtenir avant d’annoncer une V1 fiable

1. **Preuve physique :** le mouvement à `cm/360` annoncé se rapproche de la rotation réelle mesurée, indépendamment de la résolution et du FPS, selon un protocole répété.
2. **Preuve logique :** les mêmes événements synthétiques donnent les mêmes scores, et les différents FPS ne changent pas le résultat d’un tracking de référence.
3. **Preuve produit :** un second PC Windows ouvre l’EXE, joue une routine, enregistre un résultat et retrouve ses données sans installation de Godot.

**Conclusion :** c’est un projet réalisable avec Godot et un workflow ChatGPT/Codex, sans infrastructure lourde ni MCP obligatoire. Le défi central n’est pas de fabriquer des sphères en 3D ; c’est de créer un outil d’entraînement dont la réaction de la souris, la mesure des performances et les conversions de sensibilité inspirent une confiance justifiée.
