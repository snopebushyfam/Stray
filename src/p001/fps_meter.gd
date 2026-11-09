## Frame-rate meter for the optional on-screen FPS display (R9.1). Pure logic: feed it frame
## deltas; it reports the current rate (last ~0.5 s) and a moving average over `window_s`
## (default 10 s). Used by fps_overlay.gd; measures the device it runs on, nothing else.
class_name StrayFpsMeter
extends RefCounted

var window_s: float = 10.0
var current_s: float = 0.5
var _deltas: Array[float] = []
var _sum: float = 0.0


func _init(p_window_s: float = 10.0, p_current_s: float = 0.5) -> void:
	window_s = p_window_s
	current_s = p_current_s


## Adds one frame's duration (seconds). Non-positive values are ignored.
func add_frame(delta: float) -> void:
	if delta <= 0.0:
		return
	_deltas.append(delta)
	_sum += delta
	while _deltas.size() > 1 and _sum - _deltas[0] >= window_s:
		_sum -= _deltas.pop_front()


## Frames per second over the whole window (moving average); 0 without data.
func average_fps() -> float:
	return float(_deltas.size()) / _sum if _sum > 0.0 else 0.0


## Frames per second over the most recent `current_s` seconds.
func current_fps() -> float:
	var t := 0.0
	var n := 0
	for i in range(_deltas.size() - 1, -1, -1):
		t += _deltas[i]
		n += 1
		if t >= current_s:
			break
	return float(n) / t if t > 0.0 else 0.0


## Seconds of data currently in the window.
func covered_seconds() -> float:
	return _sum


func reset() -> void:
	_deltas.clear()
	_sum = 0.0
