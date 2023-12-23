extends Node

const CONSOLE_BACKGROUND_RESOURCE	:= preload("res://addons/Console/ConsoleBackground.tres")
const CONSOLE_FONT_RESOURCE			:= preload("res://addons/Console/consola.ttf")

const PROMPT_TEXT 				:= "┫▶ "
const MAX_CHAR_COUNT_PER_LINE	:= 180
const ACTIVATION_KEY			:= KEY_QUOTELEFT
const FONT_SIZE					:= 32
const OUTPUT_DEFAULT_TEXT_COLOR	:= Color(1.0, 0.6, 0.0)
const COMMAND_LINE_TEXT_COLOR	:= Color(1.0, 0.5, 0.0)

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
var last_command_result_as_string	:= ""
var last_command_result_as_table	: TableContent


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
	# output.modulate = command_line_text_color
	output.add_theme_stylebox_override("normal", CONSOLE_BACKGROUND_RESOURCE)
	output.add_theme_font_override("normal_font", CONSOLE_FONT_RESOURCE)
	output.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	output.add_theme_font_override("bold_font", CONSOLE_FONT_RESOURCE)
	output.add_theme_color_override("default_color", OUTPUT_DEFAULT_TEXT_COLOR)
	output.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	control.add_child(output)

	input.anchor_top = 0.9
	input.anchor_bottom = 1.0
	input.anchor_right = 1.0
	input.text = PROMPT_TEXT
	input.set_caret_column(PROMPT_TEXT.length())
	input.add_theme_stylebox_override("normal", CONSOLE_BACKGROUND_RESOURCE)
	input.add_theme_font_override("font", CONSOLE_FONT_RESOURCE)
	input.add_theme_color_override("font_color", COMMAND_LINE_TEXT_COLOR)
	input.add_theme_font_size_override("font_size", FONT_SIZE)
	input.text_changed.connect(_on_command_changed)
	control.add_child(input)

	control.visible = false
	process_mode = PROCESS_MODE_ALWAYS

	var help_command := register_command("?", _help, "Show command list or command information", true, false)
	var help_command_parameter := help_command.add_parameter_info(ParameterType.STRING, "command_name")
	
	register_command("exit", _exit, "Exit the game", false, false)
	help_command_parameter.register_value("exit")
	
	register_command("clear", _clear_output, "Clear the output window", false, false)
	help_command_parameter.register_value("clear")
	
	register_command("close", _close, "Close the console", false, false)
	help_command_parameter.register_value("close")
	
	register_command("pause", _pause_game, "Pause the game", false, true)
	help_command_parameter.register_value("pause")
	
	register_command("resume", _resume_game, "Resume the game", false, true)
	help_command_parameter.register_value("resume")


func _input(event : InputEvent):
	if event is InputEventKey:
		if event.get_physical_keycode_with_modifiers() == ACTIVATION_KEY:
			if event.pressed:
				_toggle()
			get_tree().get_root().set_input_as_handled()
		if control.visible and event.pressed:
			if event.get_physical_keycode_with_modifiers() == KEY_ENTER:
				_submit_command(input.text.substr(PROMPT_TEXT.length()))
				get_tree().get_root().set_input_as_handled()
			if event.get_physical_keycode_with_modifiers() == KEY_TAB:
				_fill_command()
				get_tree().get_root().set_input_as_handled()
			elif event.get_physical_keycode_with_modifiers() == KEY_UP:
				_show_command_history_backward()
				get_tree().get_root().set_input_as_handled()
			elif event.get_physical_keycode_with_modifiers() == KEY_DOWN:
				_show_command_history_foreward()
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


func _submit_command(command_line : String):
	
	input.text = PROMPT_TEXT
	input.set_caret_column(PROMPT_TEXT.length())
	
	cur_parameter_index = -1
	suggested_parameter_value_index = -1

	var split_line := command_line.split(" ")
	var command_name := split_line[0].to_lower()
	var succeeded := true
	var result_msg := ""

	if commands.has(command_name):
		command_history.append(command_name)
		command_history_index = -1
		var command : Command = commands[command_name]
		if command._parameters_infos.size() != (split_line.size() - 1):
			if not command._optional_parameters:
				result_msg = command_name +  " must be called with " + str(command._parameters_infos.size()) + " parameters"
				succeeded = false
			elif split_line.size() != 1:
				result_msg = command_name + " must be called with " + str(command._parameters_infos.size()) + " parameters or 0 parameters"
				succeeded = false
		if succeeded:
			for i in range(1, split_line.size()):
				var parameter_info := command._parameters_infos[i - 1]
				if not parameter_info.validate(split_line[i]):
					result_msg = "invalid parameter " + split_line[i] + " (" + str(i) + "). Parameter (" + str(i) + ") should be of type " + ParameterType.keys()[parameter_info._type].to_lower()
					succeeded = false
			if succeeded:
				var result = null
				match split_line.size() - 1:
					0: result = command._function.call()
					1: result = command._function.call(command._parameters_infos[0].value(split_line[1]))
					2: result = command._function.call(command._parameters_infos[0].value(split_line[1]), command._parameters_infos[1].value(split_line[2]))
					3: result = command._function.call(command._parameters_infos[0].value(split_line[1]), command._parameters_infos[1].value(split_line[2]), command._parameters_infos[2].value(split_line[3]))
					_: result_msg = "currently console cannot manage " + str(command._parameters_infos.size()) + " parameters"
				if result != null:
					assert(typeof(result) == TYPE_BOOL)
					if not result:
						succeeded = false
	else:
		succeeded = false
		result_msg = "unknown command"

	if succeeded:
		output.append_text(" ▶ " + command_line + " ▶ ✔️")
	else:
		output.append_text(" ▶ " + command_line + " ▶ ❌ ▶ " + (last_command_result_as_string if not last_command_result_as_string.is_empty() else result_msg))
	output.newline()

	if not last_command_result_as_string.is_empty() and succeeded:
		output.append_text(last_command_result_as_string)
		output.newline()
	if last_command_result_as_table != null:
		# content row count + top line + bottom line
		var row_count := last_command_result_as_table._row_count + 2
		# content col count + content col count - 1 for intermadiate vertical lines between column + left line + right line => which can be simplified by result below
		var col_count := last_command_result_as_table._col_count * 2 + 1
		output.push_table(col_count)
		var text_index := 0
		for i in row_count:
			for j in col_count:
				output.push_cell()
				if i == 0:
					if j == 0:
						output.append_text("┌")
					elif j == col_count - 1:
						output.append_text("┐")
					elif j % 2 == 0:
						output.append_text("┬")
					else:
						for k in last_command_result_as_table._max_text_length:
							output.append_text("─")
				elif i == row_count - 1:
					if j == 0:
						output.append_text("└")
					elif j == col_count - 1:
						output.append_text("┘")
					elif j % 2 == 0:
						output.append_text("┴")
					else:
						for k in last_command_result_as_table._max_text_length:
							output.append_text("─")
				else:
					if j == 0 or j == col_count - 1 or j % 2 == 0:
						output.append_text("│")
					else:
						output.append_text(last_command_result_as_table._cells[text_index])
						text_index += 1
				output.pop()
		output.pop()
		output.newline()
	
	last_command_result_as_string = ""
	last_command_result_as_table = null


func _on_command_changed():
	suggested_commands.clear()
	suggested_command_index = -1


func _toggle():
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


func _fill_command():
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


func _show_command_history_backward():
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


func _show_command_history_foreward():
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


# API COMMANDS =================================================================


func register_command(command_name : String, function : Callable, description : String = "none", optional_parameters : bool = false, show_validation : bool = true) -> Command:
	commands[command_name] = Command.new(function, description, optional_parameters, show_validation)
	sorted_commands.append(command_name)
	sorted_commands.sort()
	if commands.has("?"):
		var help_command : Command = commands["?"]
		if help_command._parameters_infos.size() == 1:
			help_command._parameters_infos[0].register_value(command_name)
	return commands[command_name]


func set_command_result_as_string(str : String):
	last_command_result_as_string = str
	
	
func set_command_result_as_table(table : TableContent):
	last_command_result_as_table = table
	

# DEFAULT COMMANDS =============================================================


func _exit() -> bool:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()
	return true


func _clear_output() -> bool:
	output.clear()
	return true


func _close() -> bool:
	_toggle()
	return true


func _help(command_name : String = "") -> bool:
	if command_name == "":
		var table = TableContent.new(2, sorted_commands.size())
		for i in sorted_commands.size():
			table.set_cell(sorted_commands[i], 0, i)
			table.set_cell(commands[sorted_commands[i]]._description, 1, i)
		set_command_result_as_table(table)
		return true
	if commands.has(command_name):
		var command : Command = commands[command_name]		
		if command._parameters_infos.is_empty():
			var table = TableContent.new(2, 1)
			table.set_cell(command_name, 0, 0)
			table.set_cell(command._description, 1, 0)
			set_command_result_as_table(table)
		else:
			var row_count = command._parameters_infos.size() + 2 # the header and one for "parameters"
			for parameter in command._parameters_infos:
				row_count += parameter._values.size()
			var table = TableContent.new(2, row_count)
			table.set_cell(command_name, 0, 0)
			table.set_cell(command._description, 1, 0)
			table.set_cell("   Parameters:", 1, 1)
			var row_index = 2
			var parameter_index = 1
			for parameter in command._parameters_infos:
				table.set_cell("      " + str(parameter_index) + ". " + parameter._name + ": " + ParameterType.keys()[parameter._type].to_lower(), 1, row_index)
				row_index += 1
				parameter_index += 1
				for value in parameter._values:
					table.set_cell("         ▸ " + value, 1, row_index)
					row_index += 1
			set_command_result_as_table(table)
		return true
	set_command_result_as_string("unknown command " + command_name)
	return false


func _pause_game() -> bool:
	pause_game_on = true
	return true


func _resume_game() -> bool:
	pause_game_on = false
	return true
