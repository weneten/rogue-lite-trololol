extends Node2D

# Throwaway harness: raises an arena, a sweep and an eruption ring, lets them
# run to a chosen moment, saves one frame and quits. Deleted after use — it is
# here so the wiring can be looked at in the engine that draws it rather than
# reasoned about.

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.07, 0.05, 0.09))

	var arena := FlameArena.spawn(self, Vector2(640, 360), Vector2(560, 290), 34, self)
	FlameWall.spawn_sweep(self, arena, Vector2.RIGHT, 60.0, 210.0, 2.8, 110.0, 0.6, 28, self)
	FlameEruption.spawn(self, arena, 1, 3, 1.8, 24, self)

	await get_tree().create_timer(2.1).timeout
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	image.save_png(OS.get_environment("WITCHFIRE_SHOT"))
	get_tree().quit()
