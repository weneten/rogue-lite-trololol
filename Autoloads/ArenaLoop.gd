extends Node

# The arena is a torus: a finite rectangle whose edges are stitched to their opposites,
# so walking off the right edge brings the Hunter back on the left and there is no wall
# anywhere. It is still a finite world, and that is the point — every place stays a real
# place he can walk back to, which is what a fixed landmark (a dungeon gate) needs and
# what an endlessly generated plane cannot give.
#
# Two ways of naming a point live here and must not be mixed up:
#
#   absolute  folded into [-size/2, size/2). One canonical value per place in the world.
#   rebased   the same place written near an anchor, so it may sit outside that range.
#
# The trick that keeps the rest of the codebase simple: LoopRebaser rewrites the whole
# world around the local Hunter once per physics frame. After that pass, everything
# within half a world of him carries ordinary, seam-free coordinates — so plain
# distance_to / direction_to / lerp keep working untouched everywhere else. Only code
# handling points that are NOT already in his frame (spawn placement, network
# snapshots, fixed landmarks) has to call in here.

# Multiples of ArenaVisuals.FLOOR_PATCH and PROP_CELL, so the ground pattern and the
# prop grid both meet themselves at the seam instead of showing a join.
const WORLD_SIZE := Vector2(6144.0, 4096.0)

var world_size: Vector2 = WORLD_SIZE

var half_size: Vector2:
	get: return world_size * 0.5

# Folds a point onto its canonical copy inside the world rectangle.
func wrap_point(p: Vector2) -> Vector2:
	return Vector2(_fold(p.x, world_size.x), _fold(p.y, world_size.y))

# The shortest way from one point to another, which may run across the seam.
func delta(from: Vector2, to: Vector2) -> Vector2:
	return wrap_point(to - from)

func distance(a: Vector2, b: Vector2) -> float:
	return delta(a, b).length()

func distance_squared(a: Vector2, b: Vector2) -> float:
	return delta(a, b).length_squared()

# The copy of `p` lying nearest to `anchor`. This is what puts a point into the Hunter's
# frame, so the result is deliberately NOT folded back into the world rectangle.
func rebase(anchor: Vector2, p: Vector2) -> Vector2:
	return anchor + delta(anchor, p)

# A random point in a ring around `origin`, in `origin`'s own frame. Spawn code wants
# this rather than a clamp: on a torus there is no edge to be pushed away from, so the
# ring is never deformed and enemies always arrive at the distance the caller asked for.
#
# Deliberately not folded. Callers pass the Hunter's position, so the result is already
# in his frame; folding it here would put a spawn on the far side of the world for the
# one frame before LoopRebaser pulled it back, which reads as a pop.
func random_point_around(origin: Vector2, min_radius: float, max_radius: float) -> Vector2:
	var lo := minf(min_radius, max_radius)
	var hi := maxf(min_radius, max_radius)
	# Half a world is the farthest any two points can be, so a ring wider than that
	# would fold back onto itself and land behind the Hunter instead of away from him.
	hi = minf(hi, minf(half_size.x, half_size.y))
	lo = minf(lo, hi)

	var angle := randf_range(0.0, TAU)
	var radius := randf_range(lo, hi)
	return origin + Vector2(radius, 0.0).rotated(angle)

static func _fold(v: float, span: float) -> float:
	if span <= 0.0:
		return v

	return fposmod(v + span * 0.5, span) - span * 0.5
