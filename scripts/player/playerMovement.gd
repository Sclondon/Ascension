extends RigidBody3D

@export var speed: float = 10.0
@export var jump_strength: float = 20.0
@export var death_plane = -20

@export var camera: Camera3D
@export var spawnPos: Node3D
@export var tower_position: Vector3  # Set this to the tower's position in the scene

var is_swiping: bool = false
var last_mouse_position: Vector2


# Reference to the height label
var height_label: Label

func _ready():
	$RayCast3D.enabled = true  # Ensure RayCast3D is enabled
	
	height_label = get_node("/root/main/CanvasLayer/Label")  # Adjust path to match your scene
	if height_label == null:
		print("Label not found, check the node path.")

	# Debugging: Check if the camera is null
	if camera == null:
		print("Error: Camera3D not found! Check the node path.")
	else:
		last_mouse_position = get_viewport().get_mouse_position()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Apply gravity
	apply_central_impulse(Vector3(0, -9.8 * state.step, 0))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed():
			# Check for custom jump action
			if $RayCast3D.is_colliding():
				apply_central_impulse(Vector3(0, jump_strength, 0))
			is_swiping = true
		elif event.is_released():
			is_swiping = false

func _process(delta: float) -> void:
	if is_swiping:
		swipe()
	
	# Get the player's height (y position)
	var current_height = global_transform.origin.y  # Y position represents the player's height

	# Update the label text with the player's current height
	if height_label != null:
		height_label.text = "Height: " + str(round(current_height))
		
	if current_height < death_plane:
		global_transform = spawnPos.transform
		linear_velocity.x = 0
		linear_velocity.y = 0
		linear_velocity.z = 0

func _physics_process(delta: float) -> void:
	look_at_tower()

func look_at_tower() -> void:
	var tower_position = Vector3.ZERO
	tower_position.y = global_transform.origin.y
	var player_position = global_transform.origin
	
	# Calculate the direction to the tower's center
	var direction_to_tower = (tower_position - player_position).normalized()
	
	# Set player's rotation to face the tower, keeping the y-axis fixed
	var look_rotation = Vector3(0, atan2(direction_to_tower.x, direction_to_tower.z), 0)
	set_angular_velocity(Vector3.ZERO)  # Prevent rotation through physics
	set_rotation_degrees(look_rotation * (180 / PI))  # Rotate the player

func swipe() -> void:
	var mouse_position = get_viewport().get_mouse_position()
	var swipe_distance = mouse_position - last_mouse_position  # Calculate swipe distance
	last_mouse_position = mouse_position  # Update for continuous swiping

	# Calculate movement direction based on swipe (in local space)
	var player_transform = global_transform

	# Transform the swipe direction into the player's local space
	var right_direction = player_transform.basis.x.normalized()
	var forward_direction = player_transform.basis.z.normalized()  # Forward direction based on where the player is looking

	# Adjust movement direction based on swipe distance
	var move_direction = (right_direction * swipe_distance.x + forward_direction * swipe_distance.y).normalized()

	# Apply movement in local space
	linear_velocity.x = -move_direction.x * speed
	linear_velocity.z = -move_direction.z * speed
