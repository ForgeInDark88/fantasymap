extends SceneTree
## Пересобрать docs/REFERENCE.md из данных игры (Reference.to_markdown).
##   godot --headless --path . -s res://tests/gen_reference.gd


func _initialize() -> void:
	var f := FileAccess.open(Reference.DOC, FileAccess.WRITE)
	f.store_string(Reference.to_markdown())
	f.close()
	print("docs/REFERENCE.md: разделов %d" % Reference.sections().size())
	quit(0)
