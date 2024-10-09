extends AnimatedSprite3D

@export var idle: SpriteFrames 
@export var jump: SpriteFrames
@export var falling: SpriteFrames

var is_jumping: bool = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_jumping:
		sprite_frames = jump
	else:
		sprite_frames = idle
	play()
		
func _physics_process(delta: float):
	if get_parent().get_node("RayCast3D").is_colliding():
		is_jumping = false
	else:
		is_jumping = true
