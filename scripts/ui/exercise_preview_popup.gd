class_name ExercisePreviewPopup
extends PanelContainer

var definition: ScenarioDefinition
var anchor: Control
var family_label: Label
var title_label: Label
var preview: ScenarioPreview
var description_label: Label
var measure_label: Label


func _ready() -> void:
	set_as_top_level(true)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", AimUI.style(Color("132330"), 14.0, Color("397b7e"), 12))
	var content := AimUI.column(self, 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	family_label = AimUI.label("", 10, AimUI.ACCENT)
	content.add_child(family_label)
	title_label = AimUI.label("", 19)
	content.add_child(title_label)
	preview = ScenarioPreview.new()
	preview.custom_minimum_size.y = 112.0
	content.add_child(preview)
	content.add_child(AimUI.label("Démonstration de l’exercice", 10, AimUI.MUTED))
	description_label = AimUI.label("", 14)
	content.add_child(description_label)
	measure_label = AimUI.label("", 12, AimUI.MUTED)
	content.add_child(measure_label)
	resized.connect(place_in_viewport)
	minimum_size_changed.connect(func() -> void: fit_content_size.call_deferred())
	get_viewport().size_changed.connect(_viewport_resized)
	hide()


func present(source: ScenarioDefinition, source_anchor: Control) -> void:
	definition = source
	anchor = source_anchor
	family_label.text = ScenarioCopy.family(source)
	title_label.text = ScenarioCopy.title(source)
	description_label.text = ScenarioCopy.description(source)
	measure_label.text = ScenarioCopy.measure(source)
	fit_width()
	preview.configure(source, true)
	show()
	fit_content_size.call_deferred()
	place_in_viewport()
	place_in_viewport.call_deferred()


func dismiss() -> void:
	hide()
	anchor = null
	preview.animated = false
	preview.set_process(false)


func fit_width() -> void:
	var viewport_size := get_viewport_rect().size
	var width_px := minf(clampf(viewport_size.x * 0.29, 300.0, 380.0), viewport_size.x - 24.0)
	custom_minimum_size.x = maxf(width_px, 0.0)
	preview.custom_minimum_size.y = 80.0 if viewport_size.y <= 540.0 else 112.0
	size.x = custom_minimum_size.x
	fit_content_size.call_deferred()


func fit_content_size() -> void:
	if not visible:
		return
	size = Vector2(custom_minimum_size.x, get_combined_minimum_size().y)
	place_in_viewport()


func place_in_viewport() -> void:
	if not visible or not is_instance_valid(anchor):
		return
	var bounds := get_viewport_rect().grow(-12.0)
	var anchor_rect := anchor.get_global_rect()
	var next_position := Vector2(anchor_rect.end.x + 10.0, anchor_rect.position.y)
	if next_position.x + size.x > bounds.end.x:
		next_position.x = anchor_rect.position.x - size.x - 10.0
	if next_position.x < bounds.position.x:
		next_position.x = anchor_rect.position.x
		next_position.y = anchor_rect.end.y + 10.0
		if next_position.y + size.y > bounds.end.y:
			next_position.y = anchor_rect.position.y - size.y - 10.0
	position = Vector2(
		clampf(next_position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x)),
		clampf(next_position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y)))


func _viewport_resized() -> void:
	if visible:
		fit_width()
		place_in_viewport.call_deferred()
