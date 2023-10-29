@tool
extends EditorPlugin


const AUTOLOAD_NAME = "Console"


func _enter_tree():
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/Console/Console.gd")


func _exit_tree():
	remove_autoload_singleton(AUTOLOAD_NAME)
