extends SceneTree

var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("V2 FOUNDATION: " + description)


func _run() -> void:
	for seed: int in [1, 42, 0]:
		var expected: Array = {1: [270369, 67634689, 2647435461, 307599695, 2398689233], 42: [11355432, 2836018348, 476557059, 3648046016, 3759983556], 0: [1085196063, 2447379481, 2618286376, 1701901981, 265159372]}[seed]
		var random := V2Random.new(seed)
		for value: int in expected:
			_check(random.next_uint32() == value, "xorshift32 fixture " + str(seed))
	_check(V2Random.stream_seed(["2026-10-12-v2.0", "0000000000000000000000000000002a", "EX01", "standard", "micro", "layout/0/0/candidate"]) == 3405335691, "tuple ASCII / seed")
	var rectangle_rng := V2Random.new(42)
	var rectangle: Array = V2Geometry.sample_rectangle(rectangle_rng, [-22.0, 22.0], [-12.0, 12.0])
	_check(absf(float(rectangle[0]) + 21.883668723050505) < 1e-12 and absf(float(rectangle[1]) - 3.8222552379247894) < 1e-12, "rectangle solid angle")
	var annulus_rng := V2Random.new(42)
	var annulus: Array = V2Geometry.sample_annulus(annulus_rng, V2Geometry.direction_deg(13.0, -6.0), 5.0, 12.0)
	_check(absf(float(annulus[0]) - 19.629779579337786) < 1e-10 and absf(float(annulus[1]) + 16.072963296778543) < 1e-10, "annulus canonical draw order")
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/v2/empreintes.fixtures.json"))
	for fixture: Dictionary in fixtures.fixtures:
		if fixture.has("input"):
			var encoded: Dictionary = V2Canonical.encode(fixture.input)
			_check(bool(encoded.ok), "canonical finite supported fixture")
			if fixture.has("encoded_hex"):
				_check(encoded.bytes.hex_encode() == fixture.encoded_hex, "canonical bytes " + String(fixture.get("id", "")))
			if fixture.has("semantic_sha256"):
				_check(V2Canonical.semantic_sha256(fixture.input) == fixture.semantic_sha256, "semantic sha256")
	_check(not bool(V2Canonical.encode(NAN).ok), "reject NaN")
	_check(not bool(V2Canonical.encode(INF).ok), "reject infinity")
	var native_named: Dictionary = {}
	native_named[&"field"] = &"value"
	_check(not bool(V2Canonical.encode(native_named).ok), "raw native names do not bypass strict JSON canonical contract")
	_check(V2Canonical.semantic_sha256(V2Canonical.json_ready(native_named)) == V2Canonical.semantic_sha256({"field": "value"}), "producer converts native names without changing semantic strings")
	_check(not bool(V2Canonical.encode(V2Canonical.json_ready({42: "value"})).ok), "producer does not sanitize unsupported integer JSON keys")
	_check(V2Canonical.float64_hex(-0.0) == "8000000000000000", "gain bits preserve negative zero outside semantic canonical encoding")
	_check(V2Canonical.semantic_sha256(-0.0) == V2Canonical.semantic_sha256(0.0), "semantic negative zero normalized")
	var contact := V2Contact.new()
	var integrated: Dictionary = contact.integrate(func(time_s: float) -> float: return time_s - 0.1234567, 1.0, 0.0, 1.0)
	_check(bool(integrated.ok), "contact bounded integration")
	_check(float(integrated.lower_s) <= 0.1234567 and float(integrated.upper_s) >= 0.1234567, "contact bounds enclose exact root")
	_check(float(integrated.upper_s) - float(integrated.lower_s) <= 0.0005, "contact error budget")
	var impossible := V2Contact.new()
	impossible.evaluations = V2Contact.MAX_EVALUATIONS_PER_PHASE
	_check(not bool(impossible.integrate(func(_time_s: float) -> float: return 0.0, 1.0, 0.0, 0.01).ok), "budget exhaustion invalidates")
	var tangent := V2Contact.new()
	_check(not bool(tangent.integrate(func(_time_s: float) -> float: return 0.0, 1.0, 0.0, 0.004).ok), "persistent ambiguous slab cannot fabricate narrow contact bounds")
	var metrics: Dictionary = {"hits": 8, "shots": 10, "contact_s": 15.0, "credited_work": 1.75}
	_check(is_equal_approx(float(V2Scores.phase_score({"duration_s": 20, "scoring": {"id": "click_v3"}}, metrics)), 320.0), "click precision exponent 1")
	_check(is_equal_approx(float(V2Scores.phase_score({"duration_s": 30, "scoring": {"id": "opportunities_v2"}, "spawn": {"schedule": {"slots": 10}}}, metrics)), 640.0), "opportunity denominator")
	_check(is_equal_approx(float(V2Scores.phase_score({"duration_s": 20, "scoring": {"id": "contact_v2"}}, metrics)), 750.0), "full scheduled contact exposure")
	_check(is_equal_approx(float(V2Scores.phase_score({"duration_s": 20, "scoring": {"id": "switch_work_v3"}}, metrics)), 87.5), "switch partial work")
	_check(V2Scores.accuracy({"hits": 0, "shots": 0}) == null, "no shot no accuracy")
	_check(V2Scores.percentile([], 0.5) == null, "no latency no zero")
	_check(V2Scores.displayed_score(87.5) == 88, "half up display")
	print("V2 FOUNDATION : %d assertions, %d échecs" % [assertions, failures])
	quit(0 if failures == 0 else 1)
