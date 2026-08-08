extends SceneTree
# Loads every script and the main scene; fails if anything doesn't compile.
# Run:  godot --headless --path . -s tests/compile_check.gd

func _initialize() -> void:
	var ok := true
	var files: Array[String] = []
	var dir := DirAccess.open("res://scripts")
	for f in dir.get_files():
		if f.ends_with(".gd"):
			files.append("res://scripts/" + f)
	files.append("res://scenes/main.tscn")
	for f in files:
		var res: Resource = load(f)
		if res == null:
			ok = false
			printerr("LOAD FAILED: " + f)
		elif res is GDScript and not (res as GDScript).can_instantiate():
			ok = false
			printerr("COMPILE FAILED: " + f)
		else:
			print("ok: " + f)
	print("COMPILE_OK" if ok else "COMPILE_FAIL")
	quit(0 if ok else 1)
