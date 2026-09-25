class_name Tuning
# Movement constants shared by the player and the level generator, so the
# generator only ever builds jumps the bird can actually make.

const GRAVITY := 30.0
const RISE_GRAVITY_HELD := 0.7       # holding jump while rising floats a little
const FALL_GRAVITY := 1.15
const TERMINAL_VY := -26.0
const JUMP_SPEED := 13.5             # ground jump: ~3 m, free
const FLAP_SPEED := 11.0             # air flap: ~2 m more, costs stamina

# One stamina bucket. A flap always costs a third of the starting bucket;
# gold feathers make the bucket bigger (up to the cap).
const BASE_STAMINA := 100.0
const STAMINA_CAP := 200.0
const FLAP_COST := 33.0
const JUMP_COST := 20.0             # the jump off the ground costs a bit too
const REGEN_RATE := 55.0             # per second while standing
const REGEN_DELAY := 0.25
const FEATHER_BONUS := 5.0           # bucket growth per gold feather
const FEATHER_REFILL := 33.0         # and it tops you up by one flap

# Holding jump while falling glides: gravity barely pulls, drains stamina
const GLIDE_GRAVITY := 0.12          # fraction of normal gravity while gliding
const GLIDE_MAX_SINK := 5.0          # glide never falls faster than this (m/s)
const GLIDE_COST := 24.0             # stamina per second
const GLIDE_BRAKE := 45.0            # how quickly a fast fall slows into a glide

# Air columns: push per second squared while inside (gravity is 30)
const UPDRAFT := 55.0
const DOWNDRAFT := 30.0
const DRAFT_MAX_RISE := 10.0         # updrafts lift you to at most this speed

# Seeds top stamina up (without growing the bucket); poison drains it and
# stops it recovering for a moment
const SEED_STAMINA := 40.0
const POISON_DRAIN := 50.0
const POISON_SICK := 2.5             # seconds without regen after eating poison

const RUN_SPEED := 7.0               # around the tower, m/s at any radius
const RADIAL_SPEED := 5.0            # in / out from the tower
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 40.0

const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const WALL_MARGIN := 0.35            # closest the bird gets to the wall
const OUTER_REACH := 8.5             # furthest out from a face centre (turrets live out here)
const FOOT_TOLERANCE := 0.2
const STUN_FALL := 14.0              # falls longer than this stun briefly
const STUN_TIME := 0.45

# The generator assumes a jump plus this many flaps for a path jump:
# 20 + 2 x 33 = 86 of the starting 100, so there's a little to spare.
const PATH_FLAPS := 2

# Horizontal distance covered by a jump that lands dy above the take-off
# point, using `flaps` flaps at each apex. Conservative: ignores the
# hold-to-float bonus. Returns -1 if the height can't be reached.
static func air_distance(dy: float, flaps: int) -> float:
	var dt := 1.0 / 240.0
	var y := 0.0
	var vy := JUMP_SPEED
	var t := 0.0
	var reached := dy <= 0.0
	while t < 8.0:
		var g := GRAVITY * (FALL_GRAVITY if vy < 0.0 else 1.0)
		vy = max(vy - g * dt, TERMINAL_VY)
		y += vy * dt
		t += dt
		if vy <= 0.0 and flaps > 0:
			vy = FLAP_SPEED
			flaps -= 1
		if y >= dy:
			reached = true
		elif vy < 0.0:
			if reached:
				return RUN_SPEED * t
			if flaps == 0:
				return -1.0
	return RUN_SPEED * t

static func max_jump_height(flaps: int) -> float:
	var h := JUMP_SPEED * JUMP_SPEED / (2.0 * GRAVITY)
	return h + flaps * FLAP_SPEED * FLAP_SPEED / (2.0 * GRAVITY)

# Equivalent run distance for a hop that moves `tangential` metres around the
# tower and `radial` metres in/out: the two axes move independently, and
# in/out is slower, so the longer of the two (scaled) sets the time needed.
static func hop_length(tangential: float, radial: float) -> float:
	return max(tangential, radial * RUN_SPEED / RADIAL_SPEED)
