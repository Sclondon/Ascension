extends AnimatedSprite3D

@export var camera: Camera3D
@export var idle: SpriteFrames 
@export var jump: SpriteFrames
@export var falling: SpriteFrames

var is_airborne: bool = false
var is_falling: bool = false
var is_slow: int = 1
var last_rotation: Vector3

func _ready():
	last_rotation = get_parent_node_3d().rotation

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_airborne:
		if is_falling:
			sprite_frames = falling
			speed_scale = 1.5
		else:
			sprite_frames = jump
			speed_scale = 2 * is_slow
	else:
		sprite_frames = idle
		speed_scale = 1.5
	play()
		
func _physics_process(delta: float):
	update_sprite_direction()
	
	if get_parent().get_node("RayCast3D").is_colliding():
		is_airborne = false
	else:
		is_airborne = true
	
	if get_parent_node_3d().linear_velocity.y < -10:
		is_falling = true
	else:
		is_falling = false
	
	if get_parent_node_3d().linear_velocity.y > -10 and get_parent_node_3d().linear_velocity.y < 10:
		is_slow = 2
	else:
		is_slow = 1
		

func update_sprite_direction():
	var current_rotation = get_parent_node_3d().rotation
	if abs(current_rotation.y - last_rotation.y) > 0.001:
		if last_rotation.y > current_rotation.y:
			scale.x = 1 
		else:  
			scale.x = -1
			
	last_rotation = current_rotation  # Update the last position for the next frame
