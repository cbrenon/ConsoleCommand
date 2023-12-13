extends Node

const CONSOLE_BACKGROUND_RESOURCE	:= preload("res://addons/Console/ConsoleBackground.tres")
const CONSOLE_FONT_RESOURCE			:= preload("res://addons/Console/consola.ttf")

const PROMPT_TEXT := "> "

enum ParameterType { UNKNOWN, INT, FLOAT, BOOL, STRING }

class CommandParameterInfo:
	var _name : String
	var _type : ParameterType = ParameterType.UNKNOWN
	var _values : Array[String]
	
	func _init(type : ParameterType, name : String):
		_name = name
		_type = type
	
	func register_value(value : String):
		_values.append(value)
		
	func validate(parameter : String) -> bool:
		if _type != ParameterType.UNKNOWN and _type != ParameterType.STRING:
			var value = str_to_var(parameter)
			match _type:
				ParameterType.INT:
					return is_instance_of(value, TYPE_INT)
				ParameterType.FLOAT:
					return is_instance_of(value, TYPE_FLOAT)
				ParameterType.BOOL:
					return is_instance_of(value, TYPE_BOOL)
		return true

	func value(str : String):
		if _type != ParameterType.UNKNOWN and _type != ParameterType.STRING:
			return str_to_var(str)
		return str
		

class Command:
	var _function : Callable
	var _description : String
	var _parameters_infos : Array[CommandParameterInfo]
	var _optional_parameters : bool
	var _show_validation : bool

	func _init(fnc : Callable, desc : String, optional_parameters : bool, show_validation : bool):
		_function = fnc
		_description = desc
		_optional_parameters = optional_parameters
		_show_validation = show_validation
		
	func add_parameter_info(type : ParameterType, name : String) -> CommandParameterInfo:
		var parameter_info := CommandParameterInfo.new(type, name)
		_parameters_infos.append(parameter_info)
		return parameter_info


class TableContent:
	var _cells : Array[String]
	var _col_count := 0
	var _row_count := 0
	var _has_title := false
	var _max_text_length := 0

	func _init(col_count : int, row_count : int, has_title : bool = false):
		assert(col_count > 0)
		assert(row_count > 0)
		_cells.resize(col_count * row_count)
		_col_count = col_count
		_row_count = row_count
		_has_title = has_title

	func set_cell(text : String, col_index : int, row_index : int):
		assert(row_index < _row_count)
		assert(col_index < _col_count)
		_cells[col_index + row_index * _col_count] = text
		if text.length() > _max_text_length:
			_max_text_length = text.length()


# API PROPERTIES ===============================================================


var activation_key	:= KEY_QUOTELEFT
var font_size		:= 32


# INTERNAL PROPERTIES ==========================================================

@onready var control				:= Control.new()
@onready var output     			:= RichTextLabel.new()
@onready var input      			:= TextEdit.new()

var commands                		:= {}
var sorted_commands         		:= []
var suggested_commands      		:= []
var suggested_command_index 		:= -1
var suggested_parameter_value_index	:= -1
var command_history         		:= []
var command_history_index   		:= -1
var pause_game_on					:= false
var cur_parameter_index				:= -1


# FUNCTIONS ====================================================================


func _ready():

	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 3
	add_child(canvas_layer)

	control.anchor_bottom = 1.0
	control.anchor_right = 1.0
	canvas_layer.add_child(control)

	output.anchor_bottom = 0.9
	output.anchor_right = 1.0
	output.scroll_following = true
	output.bbcode_enabled = true
	output.add_theme_stylebox_override("normal", CONSOLE_BACKGROUND_RESOURCE)
	output.add_theme_font_override("normal_font", CONSOLE_FONT_RESOURCE)
	output.add_theme_font_size_override("normal_font_size", font_size)
	output.add_theme_font_override("bold_font", CONSOLE_FONT_RESOURCE)
	output.add_theme_font_size_override("bold_font_size", font_size)
	control.add_child(output)

	input.anchor_top = 0.9
	input.anchor_bottom = 1.0
	input.anchor_right = 1.0
	input.text = PROMPT_TEXT
	input.set_caret_column(PROMPT_TEXT.length())
	input.add_theme_stylebox_override("normal", CONSOLE_BACKGROUND_RESOURCE)
	input.add_theme_font_override("font", CONSOLE_FONT_RESOURCE)
	input.add_theme_color_override("font_color", Color.GREEN)
	input.add_theme_font_size_override("font_size", font_size)
	input.text_changed.connect(on_command_changed)
	control.add_child(input)

	control.visible = false
	process_mode = PROCESS_MODE_ALWAYS

	var help_command := register_command("?", help, "Show command list or command information", true, false)
	var help_command_parameter := help_command.add_parameter_info(ParameterType.STRING, "command_name")
	
	register_command("exit", exit, "Exit the game", false, false)
	help_command_parameter.register_value("exit")
	
	register_command("clear", clear_output, "Clear the output window", false, false)
	help_command_parameter.register_value("clear")
	
	register_command("close", close, "Close the console", false, false)
	help_command_parameter.register_value("close")
	
	register_command("pause", pause_game, "Pause the game", false, true)
	help_command_parameter.register_value("pause")
	
	register_command("resume", resume_game, "Resume the game", false, true)
	help_command_parameter.register_value("resume")


func _input(event : InputEvent):
	if event is InputEventKey:
		if event.get_physical_keycode_with_modifiers() == activation_key:
			if event.pressed:
				toggle()
			get_tree().get_root().set_input_as_handled()
		if control.visible and event.pressed:
			if event.get_physical_keycode_with_modifiers() == KEY_ENTER:
				submit_command(input.text.substr(PROMPT_TEXT.length()))
				get_tree().get_root().set_input_as_handled()
			if event.get_physical_keycode_with_modifiers() == KEY_TAB:
				fill_command()
				get_tree().get_root().set_input_as_handled()
			elif event.get_physical_keycode_with_modifiers() == KEY_UP:
				show_command_history_backward()
				get_tree().get_root().set_input_as_handled()
			elif event.get_physical_keycode_with_modifiers() == KEY_DOWN:
				show_command_history_foreward()
				get_tree().get_root().set_input_as_handled()
			elif event.get_physical_keycode_with_modifiers() == KEY_SPACE:
				if input.get_caret_column() != 0 and input.text[input.get_caret_column() - 1] != ' ':
					cur_parameter_index += 1
				else:
					get_tree().get_root().set_input_as_handled()
			elif event.get_physical_keycode_with_modifiers() == KEY_BACKSPACE:
				if input.get_caret_column() <= PROMPT_TEXT.length():
					get_tree().get_root().set_input_as_handled()
				elif input.text[input.get_caret_column() - 1] == ' ':
					cur_parameter_index -= 1


func submit_command(command_line : String):
	
	const MAX_CHAR_COUNT_PER_LINE := 100;
	output.append_text("[color=green]┫" + command_line + "┣[/color]")
	for i in range(command_line.length(), MAX_CHAR_COUNT_PER_LINE):
		output.append_text("[color=green]━[/color]")
	output.newline()
	output.newline()
	
	input.text = PROMPT_TEXT
	input.set_caret_column(PROMPT_TEXT.length())
	
	cur_parameter_index = -1
	suggested_parameter_value_index = -1

	var split_line := command_line.split(" ")
	var command_name := split_line[0].to_lower()

	if commands.has(command_name):
		command_history.append(command_name)
		command_history_index = -1
		var command : Command = commands[command_name]
		if command._parameters_infos.size() != (split_line.size() - 1):
			if not command._optional_parameters:
				output_error(command_name + " must be called with " + str(command._parameters_infos.size()) + " parameters:")
				output.newline()
				help(command_name)
				output.newline()
				return
			elif split_line.size() != 1:
				output_error(command_name + " must be called with " + str(command._parameters_infos.size()) + " parameters or 0 parameters:")
				output.newline()
				help(command_name)
				output.newline()
				return
		for i in range(1, split_line.size()):
			var parameter_info := command._parameters_infos[i - 1]
			if not parameter_info.validate(split_line[i]):
				output_error("Invalide parameter " + split_line[i] + " (" + str(i) + ").")
				output_error("Parameter should be of type " + ParameterType.keys()[parameter_info._type].to_lower() + ":")
				output.newline()
				help(command_name)
				output.newline()
				return
		var result = null
		match split_line.size() - 1:
			0: result = command._function.call()
			1: result = command._function.call(command._parameters_infos[0].value(split_line[1]))
			2: result = command._function.call(command._parameters_infos[0].value(split_line[1]), command._parameters_infos[1].value(split_line[2]))
			3: result = command._function.call(command._parameters_infos[0].value(split_line[1]), command._parameters_infos[1].value(split_line[2]), command._parameters_infos[2].value(split_line[3]))
			_: output_error("Currently console cannot manage " + str(command._parameters_infos.size()) + " parameters")
		if result != null:
			assert(typeof(result) == TYPE_BOOL)
			if not result:
				output_error("\"" + command_line + "\" failed")
			elif command._show_validation:
				output_message("\"" + command_line + "\" succeeded")
	else:
		output_error("Unknown command: " + command_name)
	output.newline()


func on_command_changed():
	suggested_commands.clear()
	suggested_command_index = -1


func toggle():
	control.visible = !control.visible
	if control.visible:
		get_tree().paused = true
		input.grab_focus()
	else:
		suggested_commands.clear()
		suggested_command_index = -1
		input.text = PROMPT_TEXT
		input.set_caret_column(PROMPT_TEXT.length())
		cur_parameter_index = -1
		suggested_parameter_value_index = -1
		if not pause_game_on:
			get_tree().paused = false


func fill_command():
	if cur_parameter_index == -1:
		if suggested_command_index == -1:
			for command in sorted_commands:
				if command.contains(input.text.substr(PROMPT_TEXT.length())) and not suggested_commands.has(command):
					suggested_commands.append(command)
		if suggested_commands.size() > 0:
			suggested_command_index += 1
			if suggested_command_index >= suggested_commands.size():
				suggested_command_index = 0
			input.text = PROMPT_TEXT + suggested_commands[suggested_command_index]
			input.set_caret_column(input.text.length())
	else:
		var split_line := input.text.substr(PROMPT_TEXT.length()).split(" ")
		var command_name := split_line[0].to_lower()
		if commands.has(command_name):
			var command : Command = commands[command_name]
			if command._parameters_infos[cur_parameter_index]._values.size() > 0:
				suggested_parameter_value_index += 1
				if suggested_parameter_value_index >= command._parameters_infos[cur_parameter_index]._values.size():
					suggested_parameter_value_index = 0
				input.text = PROMPT_TEXT + command_name + " " + command._parameters_infos[cur_parameter_index]._values[suggested_parameter_value_index]
				input.set_caret_column(input.text.length())
				pass


func show_command_history_backward():
	if command_history.size() > 0:
		if command_history_index == -1:
			command_history_index = command_history.size() - 1
		else:
			command_history_index -= 1
		if command_history_index < 0:
			command_history_index = -1
			input.text = PROMPT_TEXT
			input.set_caret_column(PROMPT_TEXT.length())
		else:
			input.text = PROMPT_TEXT + command_history[command_history_index]
			input.set_caret_column(input.text.length())


func show_command_history_foreward():
	if command_history.size() > 0:
		if command_history_index == -1:
			command_history_index = 0
		else:
			command_history_index += 1
		if command_history_index >= command_history.size():
			command_history_index = -1
			input.text = PROMPT_TEXT
			input.set_caret_column(PROMPT_TEXT.length())
		else:
			input.text = PROMPT_TEXT + command_history[command_history_index]
			input.set_caret_column(input.text.length())


func output_error(message : String):
	output.append_text("[color=green][/color][color=red]" + message + "[/color]")
	output.newline()


func output_message(message : String):
	output.append_text("[color=green]" + message + "[/color]")
	output.newline()


func output_table(content : TableContent):
	
	# content row count + top line + bottom line
	var row_count := content._row_count + 2
	# content col count + content col count - 1 for intermadiate vertical lines between column + left line + right line => which can be simplified by result below
	var col_count := content._col_count * 2 + 1
	output.push_table(col_count)
	var text_index := 0
	for i in row_count:
		for j in col_count:
			output.push_cell()
			if i == 0:
				if j == 0:
					output.append_text("[color=green]┌[/color]")
				elif j == col_count - 1:
					output.append_text("[color=green]┐[/color]")
				elif j % 2 == 0:
					output.append_text("[color=green]┬[/color]")
				else:
					for k in content._max_text_length:
						output.append_text("[color=green]─[/color]")
			elif i == row_count - 1:
				if j == 0:
					output.append_text("[color=green]└[/color]")
				elif j == col_count - 1:
					output.append_text("[color=green]┘[/color]")
				elif j % 2 == 0:
					output.append_text("[color=green]┴[/color]")
				else:
					for k in content._max_text_length:
						output.append_text("[color=green]─[/color]")
			else:
				if j == 0:
					output.append_text("[color=green]│[/color]")
				elif j == col_count - 1:
					output.append_text("[color=green]│[/color]")
				elif j % 2 == 0:
					output.append_text("[color=green]│[/color]")
				else:
					output.append_text("[color=green]" + content._cells[text_index] + "[/color]")
					text_index += 1
			output.pop()
	output.pop()
	output.newline()


func register_command(command_name : String, function : Callable, description : String = "none", optional_parameters : bool = false, show_validation : bool = true) -> Command:
	commands[command_name] = Command.new(function, description, optional_parameters, show_validation)
	sorted_commands.append(command_name)
	sorted_commands.sort()
	if commands.has("?"):
		var help_command : Command = commands["?"]
		if help_command._parameters_infos.size() == 1:
			help_command._parameters_infos[0].register_value(command_name)
	return commands[command_name]


# DEFAULT COMMANDS =============================================================


func exit() -> bool:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()
	return true


func clear_output() -> bool:
	output.clear()
	return true


func close() -> bool:
	toggle()
	return true


func help(command_name : String = "") -> bool:
	if command_name == "":
		var table = TableContent.new(2, sorted_commands.size())
		for i in sorted_commands.size():
			table.set_cell(sorted_commands[i], 0, i)
			table.set_cell(commands[sorted_commands[i]]._description, 1, i)
		output_table(table)
		return true
	if commands.has(command_name):
		var command : Command = commands[command_name]
		output_message(command._description)
		if command._parameters_infos.size() > 0:
			output_message("\tParameters:")
			var index := 1
			for parameter in command._parameters_infos:
				output_message("\t\t" + str(index) + ": " + parameter._name + " (" + ParameterType.keys()[parameter._type].to_lower() + ")")
				if parameter._values.size() > 0:
					var choices_list : String = parameter._values[0]
					for i in range(1, parameter._values.size()):
						choices_list += ", " + parameter._values[i]
					output_message("\t\t\tvalues: " + choices_list)
		return true
	output_error("Unknown command " + command_name)
	return false


func pause_game() -> bool:
	pause_game_on = true
	return true


func resume_game() -> bool:
	pause_game_on = false
	return true
