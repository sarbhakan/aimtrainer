# QA040 — import source et focus sans édition

Audit ciblé du checkout partagé 0.4, le 12 octobre 2026 (Europe/Paris), avec le wrapper
`tools/godot.sh` et Godot `4.7.2.stable.official.ed1daf0bf`.

## Périmètre gelé

Seuls `scripts/ui/sensitivity_import.gd`, `tests/ux_flow_tests.gd` et ce document
sont modifiés par cette intervention. Dashboard n’a pas nécessité de correction.
Main, services backend, métadonnées et autres interfaces restent hors du patch.
Les changements simultanés des autres agents ne font pas partie de ce travail.

Le correctif ajoute une protection à `ReadableSpinBox`, sans changer la mise en
page, les formats lisibles, `step = 0.0` ni les pas des flèches. Le cache float
`original_value` conserve le nombre exact lorsque Godot relit le texte original.
Cette protection reste valable après `finish_edit()`, car le parse natif du blur
arrive après cette méthode. Elle restaure la propriété `value` avant les callbacks
du formulaire. Un nouveau `set_precise_value()` invalide le texte ancien ; une
édition réelle reste prise en compte.

## Attribution des 13 RED du journal initial

Référence conservée : `/tmp/aimlocal-qa040-expanded.log`, 301 assertions,
13 échecs. Le runner `/tmp/aimlocal-qa040-replay.gd` a ensuite évolué : ce journal
ne décrit donc pas exactement sa version actuelle.

| Cas | Nombre | Qualification et suite |
| --- | ---: | --- |
| QA040-02 | 2 | Vrai défaut de contexte statistique : `engine_version`, `renderer`, `scenario_revision` et `scenario_fingerprint` changés, mais ancienne `comparison_key` acceptée et record annoncé. Correctif de cohérence de clé pris en charge par le parent ; aucune modification ici. |
| QA040-06 | 2 | Fixture invalide : zéro tir avec précision annoncée à 100 %. Le refus « Précision disponible sans tir. » est légitime ; le bilan insufficient suivant est une conséquence de cette fixture refusée. Correction de fixture réservée au parent. |
| QA040-07 | 1 | Égalité JSON bit à bit trop stricte pour les derniers ULP, selon le diagnostic transmis par le parent. Tolérance numérique du contrat : `1e-14`; positions et métadonnées restent strictes. Le journal initial ne donne pas les champs flottants divergents ; aucun diff supplémentaire n’est inventé ici. |
| QA040-12 | 8 | Deux faux RED de fixture, cinq RED dus au même parse natif CS2, un faux RED d’égalité JSON CoD ; détails ci-dessous. |

Les autres cas adversariaux restent à finaliser par le parent depuis son journal.
QA040-13 avait passé ses 4 224 événements souris avec zéro I/O du store ; ce
résultat antérieur n’est pas présenté comme un nouvel essai de cette intervention.

## QA040-12 : avant le premier focus

Les deux imports ont `draft.error == ""`. Le formulaire standalone restaure le
profil complet exactement. Avec Dashboard, la seule différence initiale est la
clé `invert_y = false`, ajoutée par `read_profile()` alors que la fixture issue de
`default_profile()` ne la contenait pas. La référence historique, la distance et
les DPI sont exacts avant le focus : ce RED n’est pas une quantification du Range.

La fixture permanente déclare explicitement `invert_y = false`, puis compare le
profil complet strictement. Elle vérifie également chaque `control.value` contre
la donnée historique avant de commencer l’édition. Aucune tolérance mémoire et
aucune suppression de métadonnée ne masquent un écart.

## QA040-12 : les huit RED, champ par champ

| RED initial | Cause exacte |
| --- | --- |
| Draft initial CS2 | Clé `invert_y = false` présente dans le draft, absente de la fixture. |
| Ouvrir/quitter la sensibilité CS2 | `2.01234567890123417` devient `2.01234567890123461` : `+4.4408920985006262e-16`, soit +1 ULP. |
| Draft après focus de la sensibilité CS2 | `reference_game.sensitivity` change comme ci-dessus ; `cm_per_360` et `reference_game.source_cm_per_360` passent de `34.41823519519343932` à `34.41823519519343222`, soit −1 ULP (`−7.1054273576010019e-15`). |
| Draft après focus de m_yaw CS2 | Conséquence du champ précédent : `m_yaw = 0.016500123456789` est lui-même inchangé. Le draft porte encore la sensibilité et la distance déjà modifiées. |
| Appliquer CS2 | La sensibilité et la distance altérées sont appliquées puis enregistrées. Les DPI actifs restent `1600.125`, distincts des DPI source `800.125`. |
| Modèle Dashboard après appliquer CS2 | Même altération de `reference_game.sensitivity`, `reference_game.source_cm_per_360` et du canonique `cm_per_360`. |
| Draft initial CoD | Même clé `invert_y = false` absente de la fixture. |
| Appliquer CoD, comparaison du profil chargé | Aucun changement mémoire ni de la mesure `34.12345678901234`. Seul `reference_game.yaw_deg` diffère après JSON : bits little-endian `96255b533a5e7b3f` → `8b255b533a5e7b3f`, soit −11 ULP (`−9.540979117872439e-18`). Cet écart respecte la tolérance disque. |

La valeur CS2 avant blur est bien celle de l’historique : bits
`9105f9b048190040`. Le texte natif `2.0123456789012342`, relu par
`String.to_float()`, produit les bits `9205f9b048190040`. Les six décimales
lisibles `2.012346` ne sont jamais utilisées pour reconstruire le modèle.

Après correction, le cache mémoire CS2 garde `9105f9b048190040`, la distance garde
`2db21abb88354140`, et les drafts restent strictement identiques pendant les
callbacks du Range et après blur. Le petit écart JSON CoD demeure accepté sur
disque uniquement ; le cache mémoire reste exact jusqu’à une vraie édition.

## Régressions permanentes et preuves

`test_source_focus()` couvre six champs avec de vrais changements de focus :
DPI, sensibilité et m_yaw personnalisé CS2 ; DPI, sensibilité et mesure CoD.
Les deux références utilisent `dpi_source = 800.125` et `dpi_actuel = 1600.125`.
Les formats attendus sont `800.125`, `2.012346`, `0.0165`, `5.012346` et
`34.123457`. Les entiers restent affichés sans décimale inutile dans le test
d’import existant.

Les tests contrôlent l’égalité mémoire avant focus, après focus lisible, après
blur natif, pendant les callbacks, après Entrée sans modification et après le
vrai signal d’import vers Main. Ils vérifient le coefficient de la caméra réelle
et son application à 1 000 counts. Une édition explicite reste applicable.

Les fixtures Main utilisent un store unique sous `/tmp/aimlocal-qa040-ux-*`,
injecté avant `_ready()`. Le wrapper utilise des dossiers XDG sous
`/tmp/aimlocal-qa040-import-runtime`; les anciens tests `user://tests/ux-*`
restent donc également isolés du profil de production. La comparaison disque
autorise seulement les nombres avec `abs(delta) <= 1e-14 * max(1, abs(attendu))` ;
les clés et les autres métadonnées restent identiques. Réimporter le profil
chargé doit ensuite préserver ce cache exactement en mémoire.

| Vérification exécutée | Résultat | Journal |
| --- | --- | --- |
| `--check-only` du replay transmis | Code 0, aucune erreur de script ; replay complet non exécuté | Contrôle initial dans cette session |
| `--check-only` du probe et du runner UX | Code 0, aucune erreur de script | `/tmp/aimlocal-qa040-import-fixed-check.log`, `/tmp/aimlocal-qa040-ux-check.log` |
| Probe standalone/import/application/clavier réel | 41 assertions, 0 échec, code 0 | `/tmp/aimlocal-qa040-import-fixed.log` |
| Import précis existant + nouvelles régressions permanentes | 85 assertions, 0 échec, code 0 | `/tmp/aimlocal-qa040-ux-import.log` |
| Même suite contre l’ancien formulaire, copie temporaire du projet | 85 assertions, 9 échecs attendus, code 1 : dérive CS2, propagation au draft puis à la caméra | `/tmp/aimlocal-qa040-ux-baseline.log` |
| Suite UX complète isolée | 205 assertions, 0 échec, code 0 | `/tmp/aimlocal-qa040-ux-full.log` |

Le contrôle négatif remplace uniquement le formulaire dans la copie
`/tmp/aimlocal-qa040-import-baseline-project` avec le snapshot antérieur. Le
checkout partagé n’est jamais revenu à l’ancien code. Aucune assertion n’a été
désactivée pour obtenir le passage de la suite corrigée.

Les runners temporaires sont `/tmp/aimlocal-qa040-import-audit.gd` et
`/tmp/aimlocal-qa040-ux-runner.gd`. Rejouer les tests ciblés depuis le checkout :

```bash
AIM_LOCAL_TOOLS_DIR=/tmp/aimlocal-qa040-import-runtime \
GODOT_BIN=/workspace/.aim-local-tools/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64 \
timeout 30s bash tools/godot.sh --headless --check-only --script /tmp/aimlocal-qa040-ux-runner.gd

AIM_LOCAL_TOOLS_DIR=/tmp/aimlocal-qa040-import-runtime \
GODOT_BIN=/workspace/.aim-local-tools/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64 \
timeout 50s bash tools/godot.sh --headless --script /tmp/aimlocal-qa040-ux-runner.gd
```

## Limites de cette validation

Ces essais sont synthétiques et headless sous Linux ; aucun essai de souris
physique ni lancement Windows n’est revendiqué. Le replay adversarial complet
et les suites backend annoncées à 3 531, 1 560 et 896 assertions ne sont pas
relancés ici. Aucun import global, export, commit ni push n’est effectué.
Godot et le wrapper sont déjà opérationnels ; aucune nouvelle configuration
d’environnement, installation ou instruction de démarrage n’est nécessaire.
