extends SceneTree
## tests/test_*.gd の test_ で始まる関数を全部実行する。失敗があれば終了コード1。
##   godot --headless --path . -s res://tests/run_tests.gd


func _initialize() -> void:
	var total := 0
	var failed: Array[String] = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_base.gd":
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			total += 1
			failed.append("%s (読み込み失敗)" % f)
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			print("%s :: %s" % [f, name])
			var t: TestBase = script.new()
			t.call(name)
			if not t.failures.is_empty():
				failed.append("%s::%s (%s)" % [f, name, ", ".join(t.failures)])
	print("\n%d 件中 %d 件合格" % [total, total - failed.size()])
	for f in failed:
		print("  不合格: ", f)
	quit(1 if not failed.is_empty() or total == 0 else 0)
