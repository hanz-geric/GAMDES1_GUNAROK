extends Stage
## Stage 2. The sky darkens a little more each match from M3 to M5, so the
## player feels the run closing in without any text (GDD Section 7.2).

@onready var sky: Sprite2D = $Sky


func configure(ladder_step: int) -> void:
	var shade := clampf((ladder_step - 2) * 0.18, 0.0, 0.45)
	sky.modulate = Color(1.0 - shade, 1.0 - shade * 0.92, 1.0 - shade * 0.8)
