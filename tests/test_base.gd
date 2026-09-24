class_name TestBase
extends RefCounted
## テストの共通部品。失敗は failures に貯め、run_tests.gd が集計する。

var failures: Array[String] = []


func assert_near(actual: float, expected: float, tolerance: float, what: String) -> void:
	var ok := absf(actual - expected) <= tolerance
	print("    %s %s: %.3f (期待 %.3f ±%.3f)" % ["OK " if ok else "NG ", what, actual, expected, tolerance])
	if not ok:
		failures.append(what)


func assert_true(cond: bool, what: String) -> void:
	print("    %s %s" % ["OK " if cond else "NG ", what])
	if not cond:
		failures.append(what)
