extends CharacterBody2D

@export var down_speed = 600

var type
var f_type
var go_down_y = -1

func set_type(new_type):
	type = new_type
	$ItemSprite.texture = load("res://assets/items/shiny/" + str(type) + ".png")

func change_type(new_type):
	$ItemSprite.hide()
	set_type(new_type)
	
	$ChangeItemSprite.show()
	$ChangeItemSprite.play()
	
func change_type_fade(fade_type):
	f_type = fade_type
	$AnimationPlayer.play("fade_in")

func get_type():
	return type
	
func _ready():
	$ItemSprite.show()
	
	$ChangeItemSprite.hide()
	$ChangeItemSprite.stop()
	
	$RemoveItemSprite.hide()
	$RemoveItemSprite.stop()
	
func _process(delta):
	if go_down_y <= 0 or position.y == go_down_y:
		return
	
	var velocity = Vector2(0, 1)
	position += velocity * down_speed * delta
	
	if position.y > go_down_y:
		position.y = go_down_y
		go_down_y = -1

func is_not_moving():
	return go_down_y <= 0 or position.y == go_down_y

func go_down(gdy):
	go_down_y = gdy

func remove_with_animation():
	if $ChangeItemSprite.is_playing():
		$ChangeItemSprite.stop()
		$ChangeItemSprite.hide()
	
	$ItemSprite.hide()
	$RemoveItemSprite.show()
	$RemoveItemSprite.play()

func _on_RemoveItemSprite_animation_finished():
	$RemoveItemSprite.stop()
	$RemoveItemSprite.hide()
	queue_free()


func _on_ChangeItemSprite_animation_finished():
	$ChangeItemSprite.stop()
	$ChangeItemSprite.hide()
	
	$ItemSprite.show()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "fade_in":
		set_type(f_type)
		$AnimationPlayer.play("fade_out")
	
