class_name ExercisePreviewPopup
extends PanelContainer

var definition: ScenarioDefinition
var anchor: Control
var title_label: Label
var preview: ScenarioPreview
var preview_frame: PanelContainer
var description_label: Label


func _ready() -> void:
	set_as_top_level(true)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := AimUI.style(Color("142330"), AimUI.SPACE_LG, AimUI.HOVER_BORDER, 14)
	panel.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	panel.shadow_size = 8
	add_theme_stylebox_override("panel", panel)
	var content := AimUI.column(self, AimUI.SPACE_SM)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = AimUI.label("", 20)
	content.add_child(title_label)
	preview_frame = PanelContainer.new()
	preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_theme_stylebox_override("panel", AimUI.style(Color("0d1824"), AimUI.SPACE_SM, Color("2b4050"), 10))
	content.add_child(preview_frame)
	preview = ScenarioPreview.new()
	preview_frame.add_child(preview)
	description_label = AimUI.label("", 14)
	content.add_child(description_label)
	resized.connect(place_in_viewport)
	minimum_size_changed.connect(func() -> void: fit_content_size.call_deferred())
	get_viewport().size_changed.connect(_viewport_resized)
	visibility_changed.connect(refresh_preview_animation)
	AimUI.feedback(self).motion_changed.connect(func(_enabled: bool) -> void: refresh_preview_animation())
	hide()


func present(source: ScenarioDefinition, source_anchor: Control) -> void:
	var changed := not visible or definition != source
	definition = source
	anchor = source_anchor
	title_label.text = ScenarioCopy.title(source)
	description_label.text = ScenarioCopy.description(source)
	fit_width()
	if changed:
		preview.configure(source, true)
	else:
		refresh_preview_animation()
	show()
	if changed:
		AimUI.fade_in(self)
	fit_content_size.call_deferred()
	place_in_viewport()
	place_in_viewport.call_deferred()


func dismiss() -> void:
	hide()
	anchor = null
	preview.animated = false
	preview.set_process(false)


func refresh_preview_animation() -> void:
	if preview != null:
		preview.refresh_animation()


func fit_width() -> void:
	var viewport_size := get_viewport_rect().size
	var width_px := minf(clampf(viewport_size.x * 0.29, 320.0, 420.0), viewport_size.x - AimUI.SPACE_MD * 2.0)
	custom_minimum_size.x = maxf(width_px, 0.0)
	var frame_width_px := get_theme_stylebox("panel").get_minimum_size().x + preview_frame.get_theme_stylebox("panel").get_minimum_size().x
	preview.custom_minimum_size.y = maxf((custom_minimum_size.x - frame_width_px) / preview.display_aspect, 0.0) + ScenarioPreview.PLAYBACK_BAR_HEIGHT_PX
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
	var bounds := get_viewport_rect().grow(-AimUI.SPACE_MD)
	var anchor_rect := anchor.get_global_rect()
	var next_position := Vector2(anchor_rect.end.x + AimUI.SPACE_SM, anchor_rect.position.y)
	if next_position.x + size.x > bounds.end.x:
		next_position.x = anchor_rect.position.x - size.x - AimUI.SPACE_SM
	if next_position.x < bounds.position.x:
		next_position.x = anchor_rect.position.x
		next_position.y = anchor_rect.end.y + AimUI.SPACE_SM
		if next_position.y + size.y > bounds.end.y:
			next_position.y = anchor_rect.position.y - size.y - AimUI.SPACE_SM
	position = Vector2(
		clampf(next_position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x)),
		clampf(next_position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y)))


func _viewport_resized() -> void:
	if visible:
		fit_width()
		place_in_viewport.call_deferred()
