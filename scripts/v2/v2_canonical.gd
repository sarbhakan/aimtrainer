class_name V2Canonical
extends RefCounted

const VERSION: String = "AIM-CANON-1"
const MAX_SAFE_INTEGER: int = 9007199254740991

var output := PackedByteArray()
var error: String = ""


static func encode(value: Variant) -> Dictionary:
	var encoder := V2Canonical.new()
	encoder.append_value(value)
	return {"ok": encoder.error.is_empty(), "bytes": encoder.output if encoder.error.is_empty() else PackedByteArray(), "error": encoder.error}


static func semantic_sha256(value: Variant) -> String:
	var encoded := encode(value)
	if not encoded.ok:
		return ""
	var bytes := VERSION.to_ascii_buffer()
	bytes.append(0)
	bytes.append_array(encoded.bytes)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func float64_hex(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.reverse()
	return bytes.hex_encode()


static func float64_from_hex(value: String) -> float:
	if value.length() != 16 or not value.is_valid_hex_number():
		return NAN
	var bytes := value.hex_decode()
	bytes.reverse()
	return bytes.decode_double(0)


static func json_ready(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key: Variant in value:
			var normalized_key: Variant = String(key) if key is StringName else key
			normalized[normalized_key] = json_ready(value[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for element: Variant in value:
			normalized.append(json_ready(element))
		return normalized
	return value


func append_length(length: int) -> void:
	if length < 0 or length > 4294967295:
		error = "CANON_LENGTH_RANGE"
		return
	for shift in [24, 16, 8, 0]:
		output.append((length >> shift) & 255)


static func utf8_less(first: String, second: String) -> bool:
	var first_bytes := first.to_utf8_buffer()
	var second_bytes := second.to_utf8_buffer()
	for byte_index in mini(first_bytes.size(), second_bytes.size()):
		if first_bytes[byte_index] != second_bytes[byte_index]:
			return first_bytes[byte_index] < second_bytes[byte_index]
	return first_bytes.size() < second_bytes.size()


func append_value(value: Variant) -> void:
	if not error.is_empty():
		return
	match typeof(value):
		TYPE_NIL:
			output.append(90)
		TYPE_BOOL:
			output.append(84 if value else 70)
		TYPE_INT, TYPE_FLOAT:
			if typeof(value) == TYPE_INT and (value < -MAX_SAFE_INTEGER or value > MAX_SAFE_INTEGER):
				error = "CANON_UNSAFE_INTEGER"
				return
			var number := float(value)
			if not is_finite(number):
				error = "CANON_NONFINITE"
				return
			if number == 0.0:
				number = 0.0
			output.append(78)
			output.append_array(float64_hex(number).hex_decode())
		TYPE_STRING:
			for character_index in value.length():
				var codepoint: int = value.unicode_at(character_index)
				if codepoint >= 55296 and codepoint <= 57343:
					error = "CANON_INVALID_UTF8"
					return
			var bytes: PackedByteArray = value.to_utf8_buffer()
			output.append(83)
			append_length(bytes.size())
			output.append_array(bytes)
		TYPE_ARRAY:
			output.append(65)
			append_length(value.size())
			for element in value:
				append_value(element)
		TYPE_DICTIONARY:
			var keys: Array[String] = []
			for key in value:
				if typeof(key) != TYPE_STRING:
					error = "CANON_NONSTRING_KEY"
					return
				keys.append(key)
			keys.sort_custom(utf8_less)
			output.append(79)
			append_length(keys.size())
			for key in keys:
				append_value(key)
				append_value(value[key])
		_:
			error = "CANON_UNSUPPORTED_TYPE"
