class_name Interactable
extends Node2D
## Base class for anything the player can use with E (and optionally F).
## The Run picks the nearest one in range and shows its prompt on the HUD.

var interact_radius := 22.0
var enabled := true


func can_interact() -> bool:
	return enabled


func prompt() -> String:
	return ""


func alt_prompt() -> String:
	return ""


func interact(_run: Node) -> void:
	pass


func alt_interact(_run: Node) -> void:
	pass


## If this object holds an item, return it so the HUD can show a tooltip.
func tooltip_item() -> Variant:
	return null
