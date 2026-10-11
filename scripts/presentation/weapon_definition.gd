class_name WeaponDefinition
extends Resource

@export var weapon_id: String = "pulse"
@export var title: String = "Pulse"
@export var sprite: Texture2D
@export var shot_sound: AudioStreamWAV
@export var continuous_sound: AudioStreamWAV
@export var muzzle_uv: Vector2 = Vector2(0.14, 0.19)
@export var flash_color: Color = Color("8cf5e5")
@export var continuous_interval_s: float = 0.1


func validate() -> String:
	if weapon_id.is_empty() or title.is_empty() or sprite == null or shot_sound == null or continuous_sound == null:
		return "Profil d’arme incomplet."
	if shot_sound.data.is_empty() or continuous_sound.data.is_empty() or shot_sound.mix_rate <= 0 or continuous_sound.mix_rate <= 0:
		return "Son d’arme vide ou fréquence invalide."
	if not muzzle_uv.is_finite() or muzzle_uv.x < 0.0 or muzzle_uv.x > 1.0 or muzzle_uv.y < 0.0 or muzzle_uv.y > 1.0:
		return "Position de sortie du tir invalide."
	if not is_finite(continuous_interval_s) or continuous_interval_s < 0.05 or continuous_interval_s > 1.0:
		return "Cadence visuelle invalide."
	return ""
