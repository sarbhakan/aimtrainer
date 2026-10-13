class_name V2Contact
extends RefCounted

const MAX_SLAB_S: float = 1.0 / 240.0
const MAX_EVALUATIONS_PER_SLAB: int = 8192
const MAX_EVALUATIONS_PER_PHASE: int = 4000000
const MAX_WIDTH_FRACTION: float = 0.0005

var evaluations: int = 0
var invalid_reason: String = ""


func integrate(error_at: Callable, velocity_bound_deg_s: float, from_s: float, to_s: float, width_fraction: float = MAX_WIDTH_FRACTION) -> Dictionary:
	var result: Dictionary = {"lower_s": 0.0, "upper_s": 0.0, "estimate_s": 0.0, "intervals": [], "definite_intervals": [], "ok": true}
	if not invalid_reason.is_empty():
		return _failure(result)
	if not is_finite(velocity_bound_deg_s) or velocity_bound_deg_s < 0.0 or to_s < from_s or width_fraction <= 0.0:
		invalid_reason = "unresolved_integration_error"
		return _failure(result)
	var cursor_s: float = from_s
	while cursor_s < to_s:
		var end_s: float = minf(to_s, cursor_s + MAX_SLAB_S)
		var slab: Dictionary = _slab(error_at, velocity_bound_deg_s, cursor_s, end_s, (end_s - cursor_s) * width_fraction)
		if not bool(slab.ok):
			return _failure(result)
		result.lower_s += float(slab.lower_s)
		result.upper_s += float(slab.upper_s)
		for interval: Array in slab.intervals:
			_append_interval(result.intervals, interval)
		for interval: Array in slab.definite_intervals:
			_append_interval(result.definite_intervals, interval)
		cursor_s = end_s
	result.estimate_s = (float(result.lower_s) + float(result.upper_s)) * 0.5
	return result


func _slab(error_at: Callable, velocity_bound_deg_s: float, from_s: float, to_s: float, maximum_width_s: float) -> Dictionary:
	var result: Dictionary = {"lower_s": 0.0, "upper_s": 0.0, "intervals": [], "definite_intervals": [], "ok": true}
	var pending: Array = [[from_s, to_s]]
	var unresolved_width_s: float = to_s - from_s
	var slab_evaluations: int = 0
	while not pending.is_empty():
		if unresolved_width_s <= maximum_width_s:
			result.upper_s += unresolved_width_s
			for unresolved: Array in pending:
				result.intervals.append([unresolved[0], (float(unresolved[0]) + float(unresolved[1])) * 0.5])
			break
		var interval: Array = _heap_pop(pending)
		var begin_s: float = float(interval[0])
		var end_s: float = float(interval[1])
		var middle_s: float = (begin_s + end_s) * 0.5
		if slab_evaluations >= MAX_EVALUATIONS_PER_SLAB or evaluations >= MAX_EVALUATIONS_PER_PHASE:
			invalid_reason = "unresolved_integration_error"
			return _failure(result)
		var error_deg: float = float(error_at.call(middle_s))
		slab_evaluations += 1
		evaluations += 1
		if not is_finite(error_deg):
			invalid_reason = "unresolved_integration_error"
			return _failure(result)
		var half_variation_deg: float = velocity_bound_deg_s * (end_s - begin_s) * 0.5
		if error_deg + half_variation_deg <= 0.0:
			result.lower_s += end_s - begin_s
			result.upper_s += end_s - begin_s
			unresolved_width_s = maxf(0.0, unresolved_width_s - (end_s - begin_s))
			result.intervals.append([begin_s, end_s])
			result.definite_intervals.append([begin_s, end_s])
		elif error_deg - half_variation_deg > 0.0:
			unresolved_width_s = maxf(0.0, unresolved_width_s - (end_s - begin_s))
			continue
		elif middle_s == begin_s or middle_s == end_s:
			invalid_reason = "unresolved_integration_error"
			return _failure(result)
		else:
			_heap_push(pending, [middle_s, end_s])
			_heap_push(pending, [begin_s, middle_s])
	result.intervals.sort_custom(func(first: Array, second: Array) -> bool: return float(first[0]) < float(second[0]))
	var merged: Array = []
	for interval: Array in result.intervals:
		_append_interval(merged, interval)
	result.intervals = merged
	result.definite_intervals.sort_custom(func(first: Array, second: Array) -> bool: return float(first[0]) < float(second[0]))
	var definite_merged: Array = []
	for interval: Array in result.definite_intervals:
		_append_interval(definite_merged, interval)
	result.definite_intervals = definite_merged
	return result


static func _higher_priority(first: Array, second: Array) -> bool:
	var first_width_s: float = float(first[1]) - float(first[0])
	var second_width_s: float = float(second[1]) - float(second[0])
	return first_width_s > second_width_s or (first_width_s == second_width_s and float(first[0]) < float(second[0]))


static func _heap_push(heap: Array, value: Array) -> void:
	heap.append(value)
	var position: int = heap.size() - 1
	while position > 0:
		var parent_position: int = (position - 1) / 2
		if not _higher_priority(heap[position], heap[parent_position]):
			break
		var previous: Array = heap[parent_position]
		heap[parent_position] = heap[position]
		heap[position] = previous
		position = parent_position


static func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var position: int = 0
	while position * 2 + 1 < heap.size():
		var child_position: int = position * 2 + 1
		if child_position + 1 < heap.size() and _higher_priority(heap[child_position + 1], heap[child_position]):
			child_position += 1
		if not _higher_priority(heap[child_position], heap[position]):
			break
		var previous: Array = heap[position]
		heap[position] = heap[child_position]
		heap[child_position] = previous
		position = child_position
	return result


func _failure(result: Dictionary) -> Dictionary:
	result.ok = false
	result.error = invalid_reason
	return result


static func _append_interval(intervals: Array, interval: Array) -> void:
	if float(interval[1]) <= float(interval[0]):
		return
	if not intervals.is_empty() and absf(float(intervals[-1][1]) - float(interval[0])) <= 1e-12:
		intervals[-1][1] = interval[1]
	else:
		intervals.append(interval.duplicate())
