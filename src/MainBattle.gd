extends Node2D

signal enemy_won
signal player_won

@export var item_scene: PackedScene
@export var message_hint: PackedScene
@export var item_size = 80

@export var game_area_x = 320
@export var game_area_y = 64

var player_health = 100
var player_mana = 100
var player_dps = 1.0

var enemy_health = 100
var enemy_dps = 1.0
var background_type = 1

var player_type = 1
var enemy_type = 3

# matrix size
const N = 8
# matrix items
const M = 8
# minimum length for scored line
const MIN_SCORED_LINE = 3
# player time limit in sec
const PLAYER_TIME_LIMIT = 31 
# matrix of items
var play_matrix = []
# game flags
var is_player_turn
var is_enemy_turn
var is_finished
# player's time
var player_time
var current_enemy_spell = ""
var rewards_messages = []
var rewards_index = 0

func _ready():
	randomize()
	
	enemy_type = Global.battle_info.enemy_type
	enemy_health = Global.battle_info.enemy_health
	enemy_dps = Global.battle_info.enemy_damage
	
	background_type = Global.battle_info.enemy_background
	
	player_health = Global.player_info.health
	player_mana = Global.player_info.mana
	player_dps = Global.player_info.damage
	
	is_player_turn = Global.battle_info.status == "IN"
		
	is_enemy_turn = false
	is_finished = false
	
	$BackgroundGroup/TextureRect.texture = load("res://assets/background/game_background_" + str(background_type) + ".png")
	
	$PlayerHealthBar.max_health_value = player_health
	$PlayerHealthBar.init_with_max()
	$PlayerManaBar.max_mana_value = player_mana
	$PlayerManaBar.init_with_max()
	$PlayerAvatar.avatar_type = player_type
	$PlayerAvatar.refresh_avatar()
	
	$EnemyHealthBar.max_health_value = enemy_health
	$EnemyHealthBar.init_with_max()
	$EnemyAvatar.avatar_type = enemy_type
	$EnemyAvatar.refresh_avatar()
	
	if Global.battle_info.status == "IN":
		$PlayerHealthBar.set_health_value(Global.battle_info.c_player_health)
		$PlayerManaBar.set_mana_value(Global.battle_info.c_player_mana)
		$EnemyHealthBar.set_health_value(Global.battle_info.c_enemy_health)
	
	$PlayerSpellBox.is_selection_allowed = false
	$PlayerSpellBox.set_visible_spells(Global.player_info.spells)
	
	$MessageGroup/BigLabel.hide()
	hide_enemy_spell()


func _on_StartTimer_timeout():
	generate_matrix()
	
	if Global.battle_info.status == "IN":
		$PlayerSpellBox.is_selection_allowed = true
		check_spells()
		player_time = PLAYER_TIME_LIMIT
		$PlayerTimer.start()
	else:
		$GameTimer.start()


func _on_GameTimer_timeout():
	if is_finished:
		return
	
	move_upper_lines()
	
	if is_items_moving():
		return
	
	var scored_lines = score_matrix_play()
	
	if scored_lines.size() == 0:
		$GameTimer.stop()
		
		if $PlayerHealthBar.current_health_value <= 0:
			emit_signal("enemy_won")
			return
		
		if $EnemyHealthBar.current_health_value <= 0:
			emit_signal("player_won")
			return
		
		if is_player_turn:
			if $PlayerSpellBox.selected_spell == "EnemySkipSpell":
				$PlayerSpellBox.clear_selection()
			else:
				is_player_turn = false
				is_enemy_turn = true
		elif is_enemy_turn:
			is_player_turn = true
			is_enemy_turn = false
		else:
			is_player_turn = randf() > 0.5
			is_enemy_turn = not is_player_turn
		
		if is_enemy_turn:
			print_debug("Enemy turn")
			$PlayerSpellBox.is_selection_allowed = false
			$MessageGroup/MessageLabel.text = "Enemy's pick"
			$EnemyTimer.start()
		elif is_player_turn:
			print_debug("Player turn")
			save_data()
			hide_enemy_spell()
			$PlayerSpellBox.clear_selection()
			$PlayerSpellBox.is_selection_allowed = true
			check_spells()
			check_turn_items()
			player_time = PLAYER_TIME_LIMIT
			$PlayerTimer.start()
	
	var damage = 0
	for score_line in scored_lines:
		damage += score_line.score
	
	# scored line damage calculation
	if is_player_turn:
		do_enemy_damage(int(damage*MIN_SCORED_LINE*player_dps))
	elif is_enemy_turn:
		do_player_damage(int(damage*MIN_SCORED_LINE*enemy_dps))


func _on_EnemyTimer_timeout():
	enemy_turn()


func _on_PlayerTimer_timeout():
	if player_time > 0:
		player_time -= 1
		
		var formatted_time = str(player_time)
		if player_time < 10:
			formatted_time = "0" + formatted_time
			
		$MessageGroup/MessageLabel.text = "Your pick 0:" + formatted_time
		$MessageGroup/MessageAnimationPlayer.play("PlayerTimer")
	else:
		$PlayerTimer.stop()
		$GameTimer.start()


func _input(event):
	if $PlayerTimer.is_stopped():
		return
	
	if is_player_turn and not is_finished and event is InputEventMouseButton and not (event as InputEventMouseButton).is_pressed():
		if not remove_cell(event.position.x, event.position.y):
			return
		$PlayerManaBar.is_mana_damaged = false
		do_enemy_damage(int(player_dps))
		$PlayerTimer.stop()
		$GameTimer.start()
		$PlayerAvatar.turn_on()


func generate_matrix():
	for mx in range(N):
		play_matrix.append([])
		
		for my in range(N):
			var item = item_scene.instantiate()
			
			if Global.battle_info.status == "IN":
				item.set_type(Global.battle_info.c_play_matrix[mx][my])
			else: 
				item.set_type((randi() % M) + 1)
			
			item.position.x = game_area_x + item_size*mx + item_size/2
			item.position.y = game_area_y + item_size*my + item_size/2
			
			play_matrix[mx].append(item)
			add_child(play_matrix[mx][my])


func check_lines():
	var scored_lines = []
	
	for mx in range(N-MIN_SCORED_LINE+1):
		for my in range(N):
			var current_type = play_matrix[mx][my].get_type()
			var current_score = 0 
			
			for mxs in range(mx, N):
				var i_type = play_matrix[mxs][my].get_type()
				
				if current_type > 0 and current_type == i_type:
					current_score += 1
				else:
					current_type = 0
			
			if current_score >= MIN_SCORED_LINE:
				var check_result = {}
				check_result.score = current_score
				check_result.mx0 = mx
				check_result.my0 = my
				check_result.mx1 = mx+current_score-1
				check_result.my1 = my
				scored_lines.append(check_result)
	
	for mx in range(N):
		for my in range(N-MIN_SCORED_LINE+1):
			var current_type = play_matrix[mx][my].get_type()
			var current_score = 0 
			
			for mys in range(my, N):
				var i_type = play_matrix[mx][mys].get_type()
				
				if current_type > 0 and current_type == i_type:
					current_score += 1
				else:
					current_type = 0
			
			if current_score >= MIN_SCORED_LINE:
				var check_result = {}
				check_result.score = current_score
				check_result.mx0 = mx
				check_result.my0 = my
				check_result.mx1 = mx
				check_result.my1 = my+current_score-1
				scored_lines.append(check_result)
	
	return scored_lines
	
	
func remove_lines(scored_lines):
	fire_sound()
	for scored_line in scored_lines:
		for mxi in range(scored_line.mx0, scored_line.mx1+1):
			for myi in range(scored_line.my0, scored_line.my1+1):
				if play_matrix[mxi][myi] != null:
					play_matrix[mxi][myi].remove_with_animation()
					play_matrix[mxi][myi] = null


func remove_cell(mouse_x, mouse_y):
	var mx = (mouse_x - game_area_x) / item_size
	var my = (mouse_y - game_area_y) / item_size
	
	if mx < 0 or mx >= N or my < 0 or my >= N:
		return false
	
	if $PlayerSpellBox.selected_spell == null:
		$PlayerManaBar.set_restored(int(player_dps))
	
	if $PlayerSpellBox.selected_spell == "RegenSpaceSpell":
		regen_space()
	elif $PlayerSpellBox.selected_spell == "RandomLineSpell":
		random_lines(mx, my)
	else:
		remove_cell_m(mx, my)
	
	return true


func remove_cell_m(mx, my):
	fire_sound()
	if play_matrix[mx][my] != null:
		play_matrix[mx][my].remove_with_animation()
		play_matrix[mx][my] = null


func move_upper_lines():
	var priz = true
	while priz:
		priz = false
		for mxi in range(N):
			for myi in range(N-1):
				if play_matrix[mxi][myi+1] == null and play_matrix[mxi][myi] != null:
					# update matrix data
					play_matrix[mxi][myi+1] = play_matrix[mxi][myi]
					play_matrix[mxi][myi] = null
					priz = true
					# apply animation
					play_matrix[mxi][myi+1].go_down(game_area_y + item_size*(myi+1) + item_size/2)

	priz = true
	var empty_mx = -1
	var empty_my = -1
		
	while priz:
		priz = false
		
		# find last empty cell
		for mxi in range(N):
			for myi in range(N):
				if play_matrix[mxi][myi] == null:
					empty_mx = mxi
					empty_my = myi
					priz = true
		
		if priz:
			# create new item
			var item = item_scene.instantiate()
			item.set_type((randi() % M) + 1)
			item.position.x = game_area_x + item_size*empty_mx + item_size/2
			item.position.y = game_area_y - item_size*(N-empty_my+3) + item_size/2
			# update matrix data
			play_matrix[empty_mx][empty_my] = item
			add_child(item)
			# apply animation
			item.go_down(game_area_y + item_size*empty_my + item_size/2)	


func score_matrix_play():
	var scored_lines = check_lines()
	
	if scored_lines.size() > 0:
		remove_lines(scored_lines)
	
	return scored_lines

func check_turn_items():
	if randi() % 100 > 20:
		return
		
	print_debug("doing changing items")
	
	var turned_matrix_colors = []
	
	for mxi in range(N):
		turned_matrix_colors.append([])
		for myi in range(N):
			turned_matrix_colors[mxi].append(0)
	
	for mxi in range(N):
		for myi in range(N):
			turned_matrix_colors[myi][N-1-mxi] = play_matrix[mxi][myi].get_type()
	
	for mxi in range(N):
		for myi in range(N):
			if play_matrix[mxi][myi].get_type() != turned_matrix_colors[mxi][myi]:
				play_matrix[mxi][myi].change_type(turned_matrix_colors[mxi][myi])
	

func enemy_turn():
	$EnemyAvatar.turn_on()
	generate_current_enemy_spell()
	show_enemy_spell()
	
	var last_posible_point = {}
	last_posible_point.mx = randi() % N
	last_posible_point.my = randi() % N
	last_posible_point.score = 1
	
	var posible_point = {}
	posible_point.mx = randi() % N
	posible_point.my = randi() % N
	posible_point.score = 1
	
	for mxi in range(N):
		for myi in range(N):
			var current_score = check_point(mxi, myi)
			
			if current_score > posible_point.score:
				last_posible_point = posible_point
				posible_point.score = current_score
				posible_point.mx = mxi
				posible_point.my = myi
	
	if current_enemy_spell == "RandomLine":
		random_lines(posible_point.mx, posible_point.my)
	elif current_enemy_spell == "RegenSpace":
		regen_space()
	else:
		remove_cell_m(posible_point.mx, posible_point.my)
		do_player_damage(int(enemy_dps))
		
		if current_enemy_spell == "DoubleShot":
			remove_cell_m(last_posible_point.mx, last_posible_point.my)
			do_player_damage(int(enemy_dps))
	
	$EnemyTimer.stop()
	$GameTimer.start()


func check_point(mx0, my0):
	var play_matrix_v = []
	
	for mx in range(N):
		play_matrix_v.append([])
		for my in range(N):
			if mx == mx0 and my > 0 and my <= my0:
				play_matrix_v[mx].append(play_matrix[mx][my-1].get_type())
			elif mx == mx0 and my == 0:
				play_matrix_v[mx].append(0)
			else:
				play_matrix_v[mx].append(play_matrix[mx][my].get_type())
	
	var scores = 0
	
	for mx in range(N-MIN_SCORED_LINE+1):
		for my in range(N):
			var current_type = play_matrix_v[mx][my]
			var current_score = 0 
			
			for mxs in range(mx, N):
				var i_type = play_matrix_v[mxs][my]
				
				if current_type > 0 and current_type == i_type:
					current_score += 1
				else:
					current_type = 0
			
			if current_score >= MIN_SCORED_LINE:
				scores += current_score
	
	for mx in range(N):
		for my in range(N-MIN_SCORED_LINE+1):
			var current_type = play_matrix_v[mx][my]
			var current_score = 0 
			
			for mys in range(my, N):
				var i_type = play_matrix_v[mx][mys]
				
				if current_type > 0 and current_type == i_type:
					current_score += 1
				else:
					current_type = 0
			
			if current_score >= MIN_SCORED_LINE:
				scores += current_score
	
	return scores


func _on_MainBattle_enemy_won():
	$AudioLosePlayer.play()
	is_finished = true
	$UIControlGroup/PauseControl.hide()
	$MessageGroup/MessageLabel.hide()
	$MessageGroup/BigLabel.show()
	$MessageGroup/BigLabel.text = "You lose!"
	
	Global.player_info.position = Vector2.ZERO
	Global.battle_info.status = "L"
	Global.save_data()
	
	$FinishTimer.wait_time = 3
	$FinishTimer.start()


func _on_MainBattle_player_won():
	$AudioWinPlayer.play()
	is_finished = true
	$UIControlGroup/PauseControl.hide()
	$MessageGroup/MessageLabel.hide()
	$MessageGroup/BigLabel.show()
	$MessageGroup/BigLabel.text = "You win!!"
	
	Global.map_info.hiden_battle_entry.append(Global.battle_info.entity_name)
	Global.battle_info.status = "W"
	Global.player_info.position = Global.battle_info.entity_position
	Global.collect_awards()
	Global.save_data()
	
	show_win_rewards()


func _on_FinishTimer_timeout():
	get_tree().change_scene_to_file("res://src/WorldMap.tscn")


func check_spells():
	var mana_value = $PlayerManaBar.current_mana_value
	var new_visible_spells = []
	
	for spell_name in Global.player_info.spells:
		if $PlayerSpellBox.get_cost_by_spell(spell_name) <= mana_value:
			new_visible_spells.append(spell_name)
	
	$PlayerSpellBox.set_visible_spells(new_visible_spells) 


func do_enemy_damage(dv):
	if dv == 0:
		return
		
	$EnemyAvatar.damage()
	
	if $PlayerSpellBox.selected_spell == "HealSpell":
		print_debug("HealSpell ", dv)
		$PlayerHealthBar.set_heal(dv)
		$EnemyHealthBar.set_damage(dv)
		$PlayerManaBar.set_damage($PlayerSpellBox.get_cost_by_spell("HealSpell"))
	elif $PlayerSpellBox.selected_spell == "IncreaseDamageSpell":
		print_debug("IncreaseDamageSpell 2 * ", dv)
		$EnemyHealthBar.set_damage(2*dv)
		$PlayerManaBar.set_damage($PlayerSpellBox.get_cost_by_spell("IncreaseDamageSpell"))
	elif $PlayerSpellBox.selected_spell == "EnemySkipSpell":
		print_debug("EnemySkipSpell ", dv)
		$EnemyHealthBar.set_damage(dv)
		$PlayerManaBar.set_damage($PlayerSpellBox.get_cost_by_spell("EnemySkipSpell"))
	elif $PlayerSpellBox.selected_spell == "RandomLineSpell":
		print_debug("RandomLineSpell ", dv)
		$EnemyHealthBar.set_damage(dv)
		$PlayerManaBar.set_damage($PlayerSpellBox.get_cost_by_spell("RandomLineSpell"))
	elif $PlayerSpellBox.selected_spell == "ReflectDamageSpell":
		print_debug("ReflectDamageSpell ", dv)
		$EnemyHealthBar.set_damage(dv)
		$PlayerManaBar.set_damage($PlayerSpellBox.get_cost_by_spell("ReflectDamageSpell"))
	elif $PlayerSpellBox.selected_spell == "RegenSpaceSpell":
		print_debug("RegenSpaceSpell ", dv)
		$EnemyHealthBar.set_damage(dv)
		$PlayerManaBar.set_damage($PlayerSpellBox.get_cost_by_spell("RegenSpaceSpell"))
	else:
		print_debug("Damage ", dv)
		$EnemyHealthBar.set_damage(dv)


func do_player_damage(dv):
	if dv == 0:
		return
		
	$PlayerAvatar.damage()
	
	if $PlayerSpellBox.selected_spell == "ReflectDamageSpell":
		print_debug("ReflectDamageSpell ", dv)
		$EnemyHealthBar.set_damage(dv)
	elif current_enemy_spell == "StealBlood":
		print_debug("StealBlood ", dv)
		$EnemyHealthBar.set_heal(dv)
		$PlayerHealthBar.set_damage(dv)
	elif current_enemy_spell == "IncreaseDamage":
		print_debug("IncreaseDamage 2 * ", dv)
		$PlayerHealthBar.set_damage(2*dv)
	else:
		print_debug("Damage ", dv)
		$PlayerHealthBar.set_damage(dv)


func random_lines(mx, my):
	for i in range(N):
		play_matrix[mx][i].change_type((randi() % M) + 1)
		play_matrix[i][my].change_type((randi() % M) + 1)


func regen_space():
	for mx in range(N):
		for my in range(N):
			play_matrix[mx][my].change_type((randi() % M) + 1)


func generate_current_enemy_spell():
	if Global.battle_info.enemy_s_usage == 0:
		current_enemy_spell = ""
	elif (randi() % 100) < Global.battle_info.enemy_s_usage:
		current_enemy_spell = Global.battle_info.enemy_spells[randi() % Global.battle_info.enemy_spells.size()]


func show_enemy_spell():
	if current_enemy_spell == "":
		return
	
	var spell_res = ""
	
	for item_spell in Global.enemy_spells:
		if item_spell.name == current_enemy_spell:
			spell_res = item_spell.icon
	
	$EnemySpell/EnemySpellRect.texture = load(spell_res)
	$EnemySpell/EnemySpellRect.show()
	
	
func hide_enemy_spell():
	current_enemy_spell = ""
	$EnemySpell/EnemySpellRect.hide()
	
	
func show_win_rewards():
	if Global.battle_info.award.health > 0:
		rewards_messages.append("+ " + str(Global.battle_info.award.health) + " hp")
	
	if Global.battle_info.award.mana > 0:
		rewards_messages.append("+ " + str(Global.battle_info.award.mana) + " mana")
		
	if Global.battle_info.award.damage > 0:
		rewards_messages.append("+ " + str(int(100*Global.battle_info.award.damage)) + " % damage")

	var spell = Global.get_spell_by_name(Global.battle_info.award.spell)
	if spell != null:
		rewards_messages.append("New spell!")
		$PlayerSpellBox.set_visible_spells(Global.player_info.spells)
	
	print_debug(rewards_messages)
	$RewardTimer.start()
	
	
func _on_RewardTimer_timeout():
	if rewards_messages.size() > rewards_index:
		var new_message = rewards_messages[rewards_index]
		var reward_message_hint = message_hint.instantiate()
		reward_message_hint.z_index = 130
		reward_message_hint.position.x = 576
		reward_message_hint.position.y = 10
		add_child(reward_message_hint)
		reward_message_hint.set_reward_message(new_message)
		rewards_index += 1
	else:
		$RewardTimer.stop()
		$FinishTimer.wait_time = 3
		$FinishTimer.start()


func is_items_moving():
	for mx in range(N):
		for my in range(N):
			if (play_matrix[mx][my] == null) or (not play_matrix[mx][my].is_not_moving()):
				return true
	
	return false


func _on_PlayerSpellBox_spell_selected():
	if $PlayerSpellBox.selected_spell == null:
		return
		
	$AudioSelectSpellPlayer.play()
	
	var selected_spell = Global.get_spell_by_name($PlayerSpellBox.selected_spell)
	
	if selected_spell.description == null:
		return
	
	var spell_hint = message_hint.instantiate()
	spell_hint.z_index = 130
	spell_hint.position.x = 330
	spell_hint.position.y = 10
	add_child(spell_hint)
	spell_hint.set_reward_message(selected_spell.description)


func get_type_matrix():
	var res_map = []
	
	for mx in range(N):
		var line = []
		
		for my in range(N):
			line.append(play_matrix[mx][my].get_type())
			
		res_map.append(line)
	
	return res_map


func save_data():
	if Global.battle_info.status != "IN":
		Global.battle_info.status = "IN"
	
	Global.battle_info.c_enemy_health = $EnemyHealthBar.current_health_value
	Global.battle_info.c_player_health = $PlayerHealthBar.current_health_value
	Global.battle_info.c_player_mana = $PlayerManaBar.current_mana_value
	Global.battle_info.c_play_matrix = get_type_matrix()
	Global.save_data()



func _on_MessageAnimationPlayer_animation_finished(anim_name):
	if anim_name == "PlayerTimer" and not $PlayerTimer.is_stopped():
		$MessageGroup/MessageAnimationPlayer.play("PlayerTimer")


func fire_sound():
	$AudioFirePlayer.play()
	$FireSoundTimer.start()

func _on_FireSoundTimer_timeout():
	$AudioFirePlayer.stop()
