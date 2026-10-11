extends Node

signal motion_changed(enabled: bool)

const TRANSITION_S: float = 0.10
const FADE_S: float = 0.14

static var motion_allowed: bool = true
static var instances: Array[WeakRef] = []

var control: Control
var button: BaseButton
var interaction_tween: Tween
var fade_tween: Tween
var resting_tint: Color = Color.WHITE
var target_tint: Color = Color.WHITE
var hovered: bool = false
var held: bool = false


static func set_motion_enabled(enabled: bool) -> void:
	motion_allowed = enabled
	for reference in instances.duplicate():
		var feedback: Node = reference.get_ref()
		if is_instance_valid(feedback):
			feedback.call(&"finish_motion")
			feedback.emit_signal(&"motion_changed", enabled)
		else:
			instances.erase(reference)


func _ready() -> void:
	control = get_parent() as Control
	button = control as BaseButton
	instances.append(weakref(self))
	control.visibility_changed.connect(refresh_visibility)
	if button != null:
		resting_tint = button.self_modulate
		target_tint = resting_tint
		hovered = button.is_hovered()
		button.mouse_entered.connect(func() -> void:
			hovered = true
			refresh_interaction())
		button.mouse_exited.connect(func() -> void:
			hovered = false
			refresh_interaction())
		button.focus_entered.connect(refresh_interaction)
		button.focus_exited.connect(refresh_interaction)
		button.button_down.connect(func() -> void:
			held = true
			refresh_interaction())
		button.button_up.connect(func() -> void:
			held = false
			refresh_interaction())
		refresh_interaction(true)


func refresh_interaction(immediate: bool = false) -> void:
	if button == null:
		return
	var tint := resting_tint
	if button.is_visible_in_tree() and not button.disabled:
		if held:
			tint *= Color(0.90, 0.96, 0.96, 1.0)
		elif hovered or button.has_focus():
			tint *= Color(0.96, 1.0, 1.0, 1.0)
	immediate = immediate or not motion_allowed or not button.is_visible_in_tree()
	if tint.is_equal_approx(target_tint) and not immediate:
		return
	target_tint = tint
	if interaction_tween != null:
		interaction_tween.kill()
		interaction_tween = null
	if immediate or button.self_modulate.is_equal_approx(tint):
		button.self_modulate = tint
		return
	interaction_tween = create_tween()
	interaction_tween.tween_property(button, "self_modulate", tint, TRANSITION_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func fade_in() -> void:
	finish_fade()
	if not motion_allowed or not control.is_visible_in_tree():
		return
	control.modulate.a = 0.0
	fade_tween = create_tween()
	fade_tween.tween_property(control, "modulate:a", 1.0, FADE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func finish_fade() -> void:
	if fade_tween != null:
		fade_tween.kill()
		fade_tween = null
	if control != null:
		control.modulate.a = 1.0


func finish_motion() -> void:
	finish_fade()
	refresh_interaction(true)


func refresh_visibility() -> void:
	if not control.is_visible_in_tree():
		hovered = false
		held = false
		finish_motion()
	else:
		if button != null:
			hovered = button.is_hovered()
		refresh_interaction(true)


func _exit_tree() -> void:
	finish_motion()
	for reference in instances.duplicate():
		if reference.get_ref() == self:
			instances.erase(reference)
