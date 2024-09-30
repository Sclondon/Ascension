extends Camera3D

@export var orbit_distance: float = 10.0  # Distance from the player
@export var height_offset: float = 5.0    # Height above the player

# Reference to the player
@export var player: RigidBody3D

# Position of the tower center (assuming it's the origin)
var tower_center: Vector3 = Vector3.ZERO  

func _process(delta: float) -> void:
	if player:
		# Get the player's position
		var player_position = player.global_transform.origin

		# Calculate the camera position on the line extending from the center to the player
		tower_center.y = player_position.y
		var direction_to_player = (player_position - tower_center).normalized()
		global_transform.origin = player_position + direction_to_player * orbit_distance + Vector3(0, height_offset, 0)

		# Make the camera look at the player
		look_at(player_position, Vector3.UP)
