class_name V2Random
extends RefCounted

const ZERO_SEED_REPLACEMENT: int = 0x6D2B79F5
const MASK: int = 0xffffffff
const MODULUS: int = 4294967296

var state: int


func _init(seed_value: int = 1) -> void:
	state = seed_value & MASK
	if state == 0:
		state = ZERO_SEED_REPLACEMENT


func next_uint32() -> int:
	state = (state ^ (state << 13)) & MASK
	state = (state ^ (state >> 17)) & MASK
	state = (state ^ (state << 5)) & MASK
	return state


func uniform01() -> float:
	return (float(next_uint32()) + 0.5) / 4294967296.0


func uniform(lower: float, upper: float) -> float:
	return lower + (upper - lower) * uniform01()


func randint(lower: int, upper: int) -> int:
	var count := upper - lower + 1
	if count <= 0 or count > MODULUS:
		return -1
	var threshold: int = (MODULUS / count) * count
	while true:
		var candidate := next_uint32()
		if candidate < threshold:
			return lower + candidate % count
	return -1


func shuffle(values: Array) -> Array:
	for element_index in range(values.size() - 1, 0, -1):
		var swap_index := randint(0, element_index)
		var previous: Variant = values[element_index]
		values[element_index] = values[swap_index]
		values[swap_index] = previous
	return values


static func stream_seed(parts: Array) -> int:
	for part in parts:
		if typeof(part) != TYPE_STRING:
			return -1
		for character_index in part.length():
			if part.unicode_at(character_index) > 127:
				return -1
	var digest := JSON.stringify(parts, "", false).sha256_text()
	var seed_value := digest.substr(0, 8).hex_to_int()
	return ZERO_SEED_REPLACEMENT if seed_value == 0 else seed_value


static func public_seed(revision: String, session_seed: String, program_id: String, difficulty: String, phase_id: String, stream_name: String) -> int:
	return stream_seed([revision, session_seed, program_id, difficulty, phase_id, stream_name])
