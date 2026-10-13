extends SceneTree

const Store := preload("res://scripts/v2/v2_store.gd")
const Canonical := preload("res://scripts/v2/v2_canonical.gd")
const LegacySensitivity := preload("res://scripts/sensitivity/sensitivity_service.gd")
const LegacyEngine := preload("res://scripts/training/scenario_engine.gd")
const LegacyDefinition := preload("res://scripts/training/scenario_definition.gd")

var assertions: int = 0
var failures: int = 0
var fixture_roots: Array[String] = []


class FailingRenameStore:
	extends "res://scripts/v2/v2_store.gd"
	var failing_destination: String = ""

	func _rename_file(source: String, destination: String) -> Error:
		if destination.ends_with(failing_destination):
			return ERR_CANT_CREATE
		return super._rename_file(source, destination)


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func fixture_root() -> String:
	var root: String = "/tmp/aimlocal-v2-store-" + Crypto.new().generate_random_bytes(12).hex_encode()
	fixture_roots.append(root)
	DirAccess.make_dir_recursive_absolute(root)
	return root.path_join("v2")


func put_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "Le fixture doit pouvoir être écrit.")
		return
	file.store_string(contents)
	file.close()


func with_gain(profile: Dictionary, gain: float) -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result.gain_deg_per_relative_unit = gain
	result.gain_hex = Canonical.float64_hex(gain)
	result.cm_per_360 = 914.4 / (float(result.dpi) * gain) if result.dpi != null else null
	return result


func report_fixture(identifier: String = "session-one") -> Dictionary:
	return {"schema_version": "aimlocal.session.v2.0", "session_id": identifier,
		"app_version": "1.0.0-V2", "engine_version": "4.7.2", "catalogue_revision": "2026-10-12-v2.0",
		"score_version": "contact_v2", "program_id": "EX06", "difficulty": "standard",
		"completed": true, "valid": true, "duration_s": 60, "phases": [{"id": "reactive", "contact_s": 30.25, "exposure_s": 60}],
		"condition_snapshot": {"gain_hex": Canonical.float64_hex(0.03265714285714286)}}


func calibration_fixture() -> Dictionary:
	return {"calibration_id": "comparison-one", "protocol_id": "sustained_blocks_v2",
		"protocol_revision": "2026-10-12-v2.0", "plan_sha256": "a".repeat(64),
		"day_role": "express", "epoch": 0, "status": "pending", "checkpoint": {"completed_cells": []}}


func test_profile_and_legacy() -> void:
	var root: String = fixture_root()
	var store := Store.new(root)
	var legacy: Dictionary = LegacySensitivity.default_profile()
	legacy.dpi = 1600.0
	legacy.cm_per_360 = 34.12345678901234
	legacy.weapon_id = "vector"
	legacy.crosshair_style = "cross"
	legacy.reduced_motion = true
	legacy.reference_game = {"game_id": "valorant", "title": "VALORANT", "dpi": 800.0,
		"sensitivity": 0.42, "yaw_deg": 0.07, "source_cm_per_360": 914.4 / (800.0 * 0.42 * 0.07), "confidence": "documented"}
	var legacy_path: String = root.get_base_dir().path_join("profile.json")
	put_text(legacy_path, JSON.stringify(legacy, "\t", true, true))
	var legacy_bytes: PackedByteArray = FileAccess.get_file_as_bytes(legacy_path)
	var imported: Dictionary = store.load_profile()
	check(not imported.is_empty(), "L'ancien profil valide est lisible lorsque le profil V2 manque.")
	if imported.is_empty():
		return
	check(imported.dpi == 1600 and imported.reference_game.dpi == 800 and imported.reference_game.sensitivity == 0.42, "DPI actifs, DPI source et sensibilité source restent distincts.")
	check(imported.vertical_fov_deg == Store.VERTICAL_FOV_DEG and not imported.accumulated_input, "L'import adopte le FOV et l'input V2, sans copier les conditions legacy.")
	check(imported.weapon_id == "vector" and imported.crosshair_style == "cross" and imported.reduced_motion, "Les préférences cosmétiques importées sont conservées.")
	check(not FileAccess.file_exists(root.path_join("profile.json")), "Charger n'écrit pas automatiquement le profil importé.")
	var exact: Dictionary = with_gain(imported, Canonical.float64_from_hex("3fa0b867055f95bd"))
	check(store.save_profile(exact), "Un gain arbitraire exact et ses préférences peuvent être sauvegardés : " + store.last_error)
	var loaded: Dictionary = Store.new(root).load_profile()
	check(not loaded.is_empty() and loaded.gain_hex == exact.gain_hex and Canonical.float64_hex(loaded.gain_deg_per_relative_unit) == exact.gain_hex, "Le gain survit bit pour bit à un redémarrage sans reconstruction depuis le cm arrondi.")
	check(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes, "L'import et la sauvegarde V2 ne modifient jamais les octets legacy.")
	put_text(legacy_path, "ancien profil désormais illisible")
	check(Store.new(root).load_profile() == loaded, "Un profil V2 existant empêche tout réimport du profil legacy.")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(root.path_join("profile.json"))
	for mutation in [{"dpi": true}, {"gain_deg_per_relative_unit": NAN}, {"gain_hex": "7ff0000000000000"}, {"extra": 1}, {"accumulated_input": true}, {"sound_volume": "45"}]:
		var rejected: Dictionary = exact.duplicate(true)
		rejected.merge(mutation, true)
		check(not store.save_profile(rejected), "Une forme de profil invalide est refusée : " + str(mutation.keys()))
	check(FileAccess.get_file_as_bytes(root.path_join("profile.json")) == before, "Les profils invalides ne touchent pas le fichier accepté.")
	var unknown: Dictionary = exact.duplicate(true)
	unknown.dpi = null
	unknown.dpi_source = "unknown"
	unknown.cm_per_360 = null
	check(store.save_profile(unknown), "Un DPI inconnu conserve le gain exact sans inventer de cm/360.")
	check(Store.new(root).load_profile().get("dpi", false) == null, "La provenance DPI inconnue est durable.")


func test_reports_and_history() -> void:
	var root: String = fixture_root()
	var store := Store.new(root)
	var report: Dictionary = report_fixture()
	report["binary64_audit"] = [112.50000000000001, -0.0, 0.0326568788585, {"f64be": "literal_not_a_number"}, {"object": {"f64be": "literal_nested"}}]
	check(store.save_report(report), "Le rapport est enregistré avec son empreinte/version : " + store.last_error)
	var path: String = root.path_join("reports/session-one.json")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(store.save_report(report) and FileAccess.get_file_as_bytes(path) == before, "Réessayer le même commit est idempotent et ne réécrit pas le rapport.")
	var changed: Dictionary = report.duplicate(true)
	changed.phases[0].contact_s = 40.0
	check(not store.save_report(changed) and FileAccess.get_file_as_bytes(path) == before, "Le même ID ne remplace jamais un rapport différent.")
	for mutation in [{"session_id": "../escape"}, {"schema_version": 1}, {"catalogue_revision": false}, {"score_version": null}, {"performance": {"maximum_ms": INF}}, {"position": Vector3.ZERO}]:
		var rejected: Dictionary = report.duplicate(true)
		rejected.merge(mutation, true)
		check(not store.save_report(rejected), "Identités/types/nombres invalides refusés : " + str(mutation.keys()))
	var definition := LegacyDefinition.new()
	var engine := LegacyEngine.new()
	engine.start(definition, 1337, 1.0)
	engine.record_aim(0.01, 1.0, 0.0)
	engine.advance_to(1.0)
	var legacy_report: Dictionary = engine.result(LegacySensitivity.default_profile(), 16.0 / 9.0, true)
	legacy_report.session_id = "old-session"
	var legacy_path: String = root.get_base_dir().path_join("sessions/old-session.json")
	put_text(legacy_path, JSON.stringify(legacy_report, "\t", true, true))
	var legacy_bytes: PackedByteArray = FileAccess.get_file_as_bytes(legacy_path)
	var rows: Array = Store.new(root).history()
	check(rows.size() == 2, "L'historique présente V2 et legacy dans des espaces séparés.")
	if rows.size() == 2:
		check(rows[0].namespace == "v2" and rows[0].report == report and rows[0].read_only, "Le rapport V2 est intact et identifié en lecture seule.")
		check(rows[1].namespace == "legacy" and rows[1].report.schema_version == 1 and rows[1].read_only, "L'historique legacy conserve son format d'origine.")
		check(Canonical.float64_hex(rows[0].report.binary64_audit[0]) == Canonical.float64_hex(report.binary64_audit[0]) and Canonical.float64_hex(rows[0].report.binary64_audit[1]) == Canonical.float64_hex(-0.0), "Les doubles et zéro signé restent exacts ; les clés réservées littérales ne deviennent pas des nombres.")
	check(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes, "Afficher l'historique n'écrit aucun ancien rapport.")
	var forged: Dictionary = JSON.parse_string(before.get_string_from_utf8())
	forged.payload.phases[0].contact_s = 59.0
	put_text(path, JSON.stringify(forged, "\t", true, true))
	check(store.history().size() == 1, "Le hash détecte un rapport altéré et conserve l'historique legacy visible.")


func test_calibration_crash() -> void:
	var root: String = fixture_root()
	var store := Store.new(root)
	var baseline: Dictionary = with_gain(Store.default_profile(), Canonical.float64_from_hex("3fa0b867055f95bd"))
	check(store.save_profile(baseline), "A est durable avant de créer une comparaison.")
	var state: Dictionary = calibration_fixture()
	check(store.save_calibration_state(state), "La baseline actuelle est capturée avant tout gain temporaire : " + store.last_error)
	var resumed: Dictionary = Store.new(root).load_calibration_state()
	check(not resumed.is_empty() and resumed.baseline_profile.gain_hex == baseline.gain_hex, "Le checkpoint contient réellement les bits de A.")
	if resumed.is_empty():
		return
	var temporary: Dictionary = with_gain(baseline, baseline.gain_deg_per_relative_unit * 1.25)
	check(not store.save_profile(temporary) and store.last_error == "CALIBRATION_PROFILE_LOCKED", "Un gain temporaire ne devient jamais la préférence durable.")
	resumed.status = "active"
	resumed.temporary_gain_hex = temporary.gain_hex
	resumed.checkpoint = {"period": 1, "received_time_us": 192000000}
	check(store.save_calibration_state(resumed), "Le checkpoint peut progresser tout en gardant la baseline.")
	var state_path: String = root.path_join("calibration_state.json")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(state_path)
	var forged: Dictionary = resumed.duplicate(true)
	forged.baseline_profile = temporary
	check(not store.save_calibration_state(forged), "Un second snapshot ne remplace pas A par le gain actif B.")
	check(FileAccess.get_file_as_bytes(state_path) == before, "Une baseline rejetée préserve le checkpoint durable.")
	var other_store := Store.new(root)
	check(other_store.load_profile().gain_hex == baseline.gain_hex, "Après crash, load_profile restaure A et non le gain temporaire.")
	check(FileAccess.get_file_as_bytes(state_path) == before, "Le démarrage ne réécrit pas la baseline du checkpoint.")
	var stale_root: String = fixture_root()
	check(Store.new(stale_root).save_profile(temporary), "Le fixture simule un ancien writer qui avait persisté B.")
	put_text(root.path_join("profile.json"), FileAccess.get_file_as_string(stale_root.path_join("profile.json")))
	check(Store.new(root).load_profile().gain_hex == baseline.gain_hex, "La baseline durable A reste l'autorité même si le profil normal a été laissé à B par un autre writer.")
	check(FileAccess.get_file_as_bytes(state_path) == before, "La récupération ne capture jamais le profil B comme nouvelle baseline.")
	var rollback: Dictionary = resumed.duplicate(true)
	rollback.epoch = 1
	check(store.save_calibration_state(rollback), "Une nouvelle epoch complète peut être enregistrée.")
	check(not store.save_calibration_state(resumed), "Une epoch plus ancienne ne remplace pas l'histoire de reprise.")
	var missing_report: Dictionary = rollback.duplicate(true)
	missing_report.report_ids = ["uncommitted-cell"]
	check(not store.save_calibration_state(missing_report), "Un checkpoint ne déclare pas une cellule avant le commit de son rapport.")
	check(store.save_report(report_fixture("committed-cell")), "La cellule est committée avant le checkpoint.")
	rollback.report_ids = ["committed-cell"]
	check(store.save_calibration_state(rollback), "Le checkpoint accepte ensuite le rapport durable.")
	var lost_cells: Dictionary = rollback.duplicate(true)
	lost_cells.report_ids = []
	check(not store.save_calibration_state(lost_cells), "Une reprise ne supprime pas une cellule déjà committée.")
	var changed_plan: Dictionary = rollback.duplicate(true)
	changed_plan.protocol_revision = "autre-revision"
	check(not store.save_calibration_state(changed_plan), "La révision du protocole est figée avec le plan pending.")
	check(store.clear_calibration_state(), "La clôture restaure A puis publie une tombstone atomique : " + store.last_error)
	check(Store.new(root).load_calibration_state().is_empty(), "La clôture ne ressuscite pas l'ancienne backup pending au redémarrage.")
	check(store.save_profile(temporary), "B ne peut être enregistré volontairement qu'après clôture de la transaction temporaire.")
	check(Store.new(root).load_profile().gain_hex == temporary.gain_hex, "Une application explicite après clôture reste durable.")


func test_failures_and_strict_json() -> void:
	var root: String = fixture_root()
	var store := Store.new(root)
	var baseline: Dictionary = Store.default_profile()
	check(store.save_profile(baseline), "Le fixture A est enregistré.")
	var path: String = root.path_join("profile.json")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var failing := FailingRenameStore.new(root)
	failing.failing_destination = "/profile.json"
	check(not failing.save_profile(with_gain(baseline, 0.04)), "Un refus de rename est observable.")
	check(FileAccess.get_file_as_bytes(path) == before and Store.new(root).load_profile().gain_hex == baseline.gain_hex, "Un rename refusé conserve A et sa backup lisibles.")
	failing.failing_destination = "/calibration_state.json"
	check(not failing.save_calibration_state(calibration_fixture()), "Si la baseline ne devient pas durable, le caller n'est pas autorisé à appliquer le gain temporaire.")
	check(Store.new(root).load_calibration_state().is_empty(), "Un premier commit CAL refusé ne crée pas de faux pending.")
	check(store.save_calibration_state(calibration_fixture()), "Un refus I/O n'abandonne pas de lock empêchant une nouvelle tentative.")
	failing.failing_destination = "/calibration_state.json"
	check(not failing.clear_calibration_state(), "Une clôture qui échoue reste pending.")
	check(not Store.new(root).load_calibration_state().is_empty() and Store.new(root).load_profile().gain_hex == baseline.gain_hex, "Une clôture interrompue garde A et le journal de restauration.")
	check(store.clear_calibration_state(), "La clôture peut être réessayée sans perte.")
	var backup_root: String = fixture_root()
	var backup_store := Store.new(backup_root)
	check(backup_store.save_profile(baseline) and backup_store.save_profile(with_gain(baseline, 0.04)), "Le deuxième commit conserve une backup vérifiable.")
	var backup_path: String = backup_root.path_join("profile.json")
	put_text(backup_path, "fichier primaire corrompu")
	check(backup_store.load_profile().gain_hex == baseline.gain_hex and backup_store.last_error == "PROFILE_BACKUP_USED", "Une corruption est signalée et la backup valide restitue le gain exact.")
	check(not backup_store.save_profile(baseline) and FileAccess.get_file_as_string(backup_path) == "fichier primaire corrompu", "La récupération ne détruit pas silencieusement le fichier corrompu.")
	var malformed_root: String = fixture_root()
	var malformed_path: String = malformed_root.path_join("profile.json")
	var valid_envelope: String = before.get_string_from_utf8()
	for malformed in [valid_envelope.replace('"kind": "profile"', '"kind": "profile", "kind": "profile"'), valid_envelope.replace('"schema_version": "aimlocal.store.v2.0"', '"extra": 1, "schema_version": "aimlocal.store.v2.0"'), '{"a":1,}', '{"a":01}', '{"a":NaN}', '{"a":"\\uD800"}', '{"a":"\\u0xFF"}', '{"a":1e999}', '{"a":1.}', '{"a":9007199254740992}']:
		put_text(malformed_path, malformed)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(malformed_path)
		var rejected := Store.new(malformed_root)
		check(rejected.load_profile().is_empty() and not rejected.last_error.is_empty(), "JSON ou enveloppe non strict est refusé.")
		check(not rejected.save_profile(baseline) and FileAccess.get_file_as_bytes(malformed_path) == bytes, "Le fichier V2 inconnu/invalide est conservé sans réimport ni écrasement.")
	var invalid_utf8 := FileAccess.open(malformed_path, FileAccess.WRITE)
	invalid_utf8.store_buffer(PackedByteArray([123, 34, 192, 175, 34, 58, 49, 125]))
	invalid_utf8.close()
	check(Store.new(malformed_root).load_profile().is_empty(), "L'UTF-8 invalide est rejeté avant le décodeur moteur.")
	var blocked_root: String = fixture_root()
	put_text(blocked_root, "ce chemin est un fichier")
	check(not Store.new(blocked_root).save_profile(baseline), "Une racine occupée échoue explicitement sans toucher aux anciens fichiers.")


func test_verified_read_cache() -> void:
	var root: String = fixture_root()
	var store := Store.new(root)
	check(store.save_profile(Store.default_profile()), "Le cache ne supprime pas la vérification du premier commit.")
	var profile: Dictionary = store.load_profile()
	profile.gain_hex = "0".repeat(16)
	check(store.load_profile().gain_hex == Store.default_profile().gain_hex, "Les objets retournés ne peuvent pas modifier le document vérifié en cache.")
	var path: String = root.path_join("profile.json")
	var source: String = FileAccess.get_file_as_string(path)
	var altered: String = source.replace('"goal": "balanced"', '"goal": "tracking"')
	check(altered.length() == source.length() and altered != source, "Le fixture altère des octets sans changer la longueur du fichier.")
	put_text(path, altered)
	check(store.load_profile().is_empty(), "Le cache vérifie le SHA des octets réels, pas seulement la longueur ou la date du fichier.")
	put_text(path, source)
	check(store.load_profile().gain_hex == Store.default_profile().gain_hex, "Un document restauré est intégralement revérifié après invalidation du cache.")
	for index: int in 70:
		check(store.save_report(report_fixture("cache-report-%d" % index)), "Le cache borné ne refuse pas la persistance d'un historique plus grand.")
	check(store._verified_order.size() <= Store.VERIFIED_CACHE_DOCUMENTS and store._verified_bytes <= Store.VERIFIED_CACHE_BYTES, "Le cache ne conserve pas une quantité illimitée de rapports haute fréquence.")
	check(store.load_profile().gain_hex == Store.default_profile().gain_hex, "L'éviction ne modifie ni le fichier ni la précision du gain.")
	check(store._report_links_valid(["cache-report-0"]), "Les liens immuables restent vérifiés après éviction du corps du rapport.")
	DirAccess.remove_absolute(root.path_join("reports/cache-report-0.json"))
	check(not store._report_links_valid(["cache-report-0"]), "Une attestation en mémoire ne masque jamais un rapport disparu du disque.")


func remove_fixture(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		DirAccess.remove_absolute(path)
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname in directory.get_directories():
		remove_fixture(path.path_join(dirname))
	DirAccess.remove_absolute(path)


func run() -> void:
	test_profile_and_legacy()
	test_reports_and_history()
	test_calibration_crash()
	test_failures_and_strict_json()
	test_verified_read_cache()
	for root in fixture_roots:
		remove_fixture(root)
	print("V2 STORE : %d assertions, %d échecs." % [assertions, failures])
	quit(1 if failures > 0 else 0)
