extends Node3D

@export var platform_scene: PackedScene
@export var tower_segment_height: float = 10.0  # Height of each tower segment
@export var platform_height_offset: float = 5.0  # Maximum height offset from the segment
@export var tower_radius: float = 5.0
@export var max_platforms_per_segment: int = 5  # Maximum number of platforms to spawn per segment
@export var spawn_probability: float = 0.5  # Probability of spawning each platform (0.0 to 1.0)
@export var number_of_sides: int = 6  # Number of sides of the tower (hexagon = 6, octagon = 8, etc.)
@export var min_height_between_platforms: float = 1.0  # Minimum distance between platforms
@export var remove_threshold: float = 20.0  # Threshold for removing platforms below the player
@export var player: Node3D                # Reference to the player

var platforms: Array = []
var platformsCollisionCheck: Array = []

func _ready():
	# Connect to the signal emitted when a new section is added
	get_parent().connect("new_section_added", Callable(self, "_on_new_section_added"))
	
func _process(delta: float):
	remove_platforms_below_player(player.global_transform.origin.y)

func _on_new_section_added(height: float):
	print("Signal received, height: ", height)  # Debug print
	if (height < 0):
		return
	# Randomly spawn platforms along the wall
	var platforms_to_spawn = randi() % (max_platforms_per_segment + 1)  # Random number of platforms up to max
	var spawned = 0  # Counter for how many times we try to spawn a platform
	platformsCollisionCheck.clear()

	if randf() < spawn_probability:  # Chance to spawn each platform
		var attempts = 0
		while spawned < platforms_to_spawn and attempts < 5:
			# Calculate the platform height relative to the tower segment
			var height_offset = randf_range(-platform_height_offset, platform_height_offset)  # Random offset
			var new_height = height + height_offset
			var angle = _get_random_angle()  # Get a random angle for platform placement
		
			# Calculate the new position for the platform
			var position = _calculate_platform_position(angle, new_height)

			if _is_position_valid(position):  # Check if the position is valid
				spawn_platform(position)  # Spawn the platform at the calculated position
				spawned += 1  # Successfully spawned a platform
				attempts = 0
				
			attempts += 1
	

func _get_random_angle() -> float:
	# Calculate angle step based on the number of sides
	var angle_step = TAU / number_of_sides  # Angle for each side
	return angle_step * (randi() % number_of_sides) + angle_step * (randf() * 0)  # Randomly choose one of the sides and add a little randomness

func _calculate_platform_position(angle: float, height: float) -> Vector3:
	# Calculate position on the outer edge of the tower
	var outer_radius = tower_radius + (randf() ) # Adjust the radius to be just outside the tower
	var x_pos = cos(angle) * outer_radius
	var z_pos = sin(angle) * outer_radius
	return Vector3(x_pos, height, z_pos)

func _is_position_valid(new_position: Vector3) -> bool:
	if new_position.y < 0:
		return false
	
	for platform in platformsCollisionCheck:
		# Calculate the distance between the new position and existing platforms
		if platform.global_transform.origin.distance_to(new_position) < min_height_between_platforms:
			return false  # Position is too close to another platform
	return true  # Position is valid

func spawn_platform(position: Vector3):
	var platform = platform_scene.instantiate()

	platform.global_transform.origin = position
	# Calculate the angle for rotation using atan2 for Y-axis alignment
	var angle = atan2(position.z, position.x)  # Calculate angle in radians
	platform.rotation_degrees.y = angle * (90 / PI)  # Convert to degrees

	print("Platform spawned at position: ", position)  # Debug print

	add_child(platform)
	platforms.append(platform)
	platformsCollisionCheck.append(platform)

func remove_platforms_below_player(player_height: float):
	for platform in platforms:
		var platform_height = platform.global_transform.origin.y
		
		# If platform is below the threshold, remove it
		if platform_height < player_height - remove_threshold:
			platforms.erase(platform)
			platform.queue_free()  # Safely remove the platform from the scene
			print("Removed platform at height: ", platform_height)
