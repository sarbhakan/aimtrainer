class_name SessionClock
extends RefCounted

var accumulated_us: int = 0
var resumed_us: int = 0
var running: bool = false


func start(now_us: int) -> void:
	accumulated_us = 0
	resumed_us = now_us
	running = true


func elapsed_s(now_us: int) -> float:
	return float(accumulated_us + (maxi(now_us - resumed_us, 0) if running else 0)) / 1000000.0


func pause(now_us: int) -> void:
	if running:
		accumulated_us += maxi(now_us - resumed_us, 0)
		running = false


func resume(now_us: int) -> void:
	if not running:
		resumed_us = now_us
		running = true
