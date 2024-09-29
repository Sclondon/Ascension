extends Camera3D

# Reference to the player
@export var player: Node3D

# Store the initial offset based on the camera's current position relative to the player
var camera_offset: Vector3

# Speed of the camera movement
@export var smooth_speed: float = 5.0  # Adjust this for more or less smoothness

func _ready():
	if player != null:
		# Calculate the initial offset based on the camera's position in the editor
		camera_offset = global_transform.origin - player.global_transform.origin

#func _process(delta):
	#if player != null:
		## Get the target position (player position + offset)
		#var target_position = player.global_transform.origin + camera_offset
		#
		## Smoothly move the camera towards the target position using lerp
		#global_transform.origin = global_transform.origin.lerp(target_position, smooth_speed * delta)
		#
		## Smoothly rotate the camera to look at the player
		#var current_rotation = global_transform.basis
		#var target_rotation = (player.global_transform.origin - global_transform.origin).normalized()
#
		## Apply the rotation smoothly
		#look_at(player.global_transform.origin, Vector3.UP)
