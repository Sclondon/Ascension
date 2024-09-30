extends Node3D

# Plane wall scene to instance
@export var wall_segment_scene: PackedScene
@export var section_height: float = 10.0  # Height of each wall segment
@export var tower_radius: float = 5.0     # Radius of the hexagon/octagon
@export var num_sides: int = 6            # Number of sides (6 for hexagon, 8 for octagon)
@export var spawn_distance: float = 50.0  # Distance from player at which new walls are generated
@export var max_sections: int = 5         # Max number of sections to keep
@export var player: Node3D                # Reference to the player

# Reference to the platform spawner node
@export var platform_spawner: Node3D

signal new_section_added(height)

# List to keep track of active tower sections
var tower_sections: Array = []

func _ready():
	# Initially generate a few tower sections
	for i in range(max_sections-1):
		add_new_section((-i-1) * (section_height/2))
		
	var tower_spawner = get_parent()
	if tower_spawner:
		tower_spawner.connect("new_section_added", Callable(self, "_on_new_section_added"))
		print("Signal connected")
	else:
		print("TowerSpawner not found")

func _process(delta):
	# Check the player's height and spawn new sections if needed
	if player.global_transform.origin.y > get_last_section_height() - spawn_distance:
		add_new_section(get_last_section_height())

	# Remove old sections if far below the player
	if tower_sections.size() > max_sections and tower_sections[0].global_transform.origin.y < player.global_transform.origin.y - 2 * spawn_distance:
		remove_old_section()

func add_new_section(height: float):
	var angle_step = TAU / num_sides
	for i in range(num_sides):
		var angle = i * angle_step
		var x_pos = cos(angle) * tower_radius
		var z_pos = sin(angle) * tower_radius

		var wall_segment = wall_segment_scene.instantiate()
		wall_segment.global_transform.origin = Vector3(x_pos, height, z_pos)
		wall_segment.look_at_from_position(Vector3(x_pos, height, z_pos), Vector3(0, height, 0), Vector3.UP)

		add_child(wall_segment)
		tower_sections.append(wall_segment)

	print("New section added at height: ", height)  # Debug print to verify emission
	emit_signal("new_section_added", height)  # Emit the signal

# Function to remove the oldest section
func remove_old_section():
	for i in range(num_sides):
		var old_wall = tower_sections.pop_front()
		old_wall.queue_free()

	print("Old section removed.")
	
# Get the height of the last section in the list
func get_last_section_height() -> float:
	if tower_sections.size() == 0:
		return 0
	return tower_sections.back().global_transform.origin.y + section_height
