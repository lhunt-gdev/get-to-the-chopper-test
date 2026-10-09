class_name SaveFile
extends RefCounted
## Writing the game's saves to the device (user://; on the web, the browser's storage) so a write
## that fails part way (the app closed, the disk full) never leaves a broken or half-written save:
## the new text goes to "<path>.tmp" first and only then replaces the save, in one rename. A write
## that fails is a warning, never an error that stops the game; the save before it stays as it was.
## Used by Progress (unlocks, cleared marks, best times), RunLog (the route map's discoveries) and
## Settings.

## The side file a save is written to before it replaces the save.
const TMP := ".tmp"


## Writes `text` to `path` safely (see the top). True if it's on the device now.
static func write_text(path: String, text: String) -> bool:
	if path == "":
		return false
	var tmp := path + TMP
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveFile: could not write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	var stored := f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	if not stored or err != OK:
		push_warning("SaveFile: could not write %s (%s)" % [tmp, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	# (Some file systems won't rename over a file: the old save goes first. If the game stops right
	# here, read_text() finds the new one in the .tmp.)
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	push_warning("SaveFile: could not replace %s; the new save is in %s" % [path, tmp])
	return false


## The save at `path` as text: "" if there's none. If the save itself is missing but its .tmp is
## there (a write stopped between its two steps), that's the newest save, so it's read instead.
static func read_text(path: String) -> String:
	if path == "":
		return ""
	for p in [path, path + TMP]:
		if FileAccess.file_exists(p):
			return FileAccess.get_file_as_string(p)
	return ""


## Whether there's a save at `path` (or its .tmp: see read_text).
static func exists(path: String) -> bool:
	return path != "" and (FileAccess.file_exists(path) or FileAccess.file_exists(path + TMP))
