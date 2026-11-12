class_name ErrorCollector
extends Logger
## Records every engine/script error raised while the tests run, so a crash
## inside a test function fails the run instead of being silently skipped.

var errors: Array[String] = []
var _mutex := Mutex.new()

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if not rationale.is_empty() else code
	_mutex.lock()
	errors.append("%s (%s:%d %s)" % [text, file.get_file(), line, function])
	_mutex.unlock()

func take() -> Array[String]:
	_mutex.lock()
	var result := errors.duplicate()
	errors.clear()
	_mutex.unlock()
	return result
