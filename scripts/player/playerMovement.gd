extends RigidBody3D

@export var speed: float = 10.0
@export var jump_strength: float = 20.0
@export var death_plane = -20

@export var camera: Camera3D
@export var spawnPos: Node3D

var is_moving: bool = false
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
			is_moving = true
		elif event.is_released():
			is_moving = false

func _process(delta: float) -> void:
	if is_moving:
		follow_mouse()
	
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

func follow_mouse() -> void:
	var mouse_position = get_viewport().get_mouse_position()
	var mouse_movement = mouse_position - last_mouse_position  # Calculate the change in mouse position
	last_mouse_position = mouse_position  # Update the last mouse position

	# Access camera transform properly
	var camera_transform = camera.global_transform
	var right_direction = camera_transform.basis.x.normalized()
	var forward_direction = -camera_transform.basis.z.normalized()  # In Godot, Z is forward, but we want to move in the direction we face

	# Calculate movement direction based on mouse movement in camera space
	var move_direction = (right_direction * mouse_movement.x + forward_direction * mouse_movement.y).normalized()

	# Set the linear velocity directly based on the movement direction
	linear_velocity.x = move_direction.x * speed
	linear_velocity.z = -move_direction.z * speed
	# Keep Y velocity unchanged (e.g., jumping)
