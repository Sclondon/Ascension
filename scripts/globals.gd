# SignalBus.gd
extends Node

class_name Globals

# Declare signals that you want to use globally
var player_score

signal player_died
signal score_updated(new_score: int)
signal death_floor_changed(height: float)
# Any other signals can be declared here
