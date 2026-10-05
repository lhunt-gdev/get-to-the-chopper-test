class_name Typer
extends Node
## Types texts out one after another (the end screen: user, "the text in this screen to type in"),
## a letter at a time on real time, a typed for each (spaces silently): each entry its text, the
## seconds per letter and how to show n letters of it. finish() shows them all at once.
signal typed

## Seconds before it starts, and the pause between texts.
var delay := 0.0
const GAP := 0.12
var _entries: Array = []
var _i := 0
var _n := 0
var _wait := 0.0
var _started := false

## Show n letters of a label (centred ones keep still as they fill).
static func label_setter(l: Label) -> Callable:
	l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	return func(n: int) -> void: l.visible_characters = n

func add(text: String, per_letter: float, show: Callable) -> void:
	_entries.append([text, per_letter, show])
	show.call(0)

## How long it all takes to type (s), from its start.
func length() -> float:
	var s := delay
	for e in _entries:
		s += String(e[0]).length() * float(e[1]) + GAP
	return s

func _ready() -> void:
	_wait = delay

func _process(delta: float) -> void:
	if _i >= _entries.size():
		return
	_wait -= delta / maxf(Engine.time_scale, 0.01)
	while _wait <= 0.0 and _i < _entries.size():
		var e: Array = _entries[_i]
		var text: String = e[0]
		_n += 1
		(e[2] as Callable).call(_n)
		if text[_n - 1] != " ":
			typed.emit()
		_wait += float(e[1])
		if _n >= text.length():
			_i += 1
			_n = 0
			_wait += GAP

func finish() -> void:
	while _i < _entries.size():
		var e: Array = _entries[_i]
		(e[2] as Callable).call(String(e[0]).length())
		_i += 1
	_n = 0

func is_done() -> bool:
	return _i >= _entries.size()
