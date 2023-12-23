extends RefCounted

var _listeners := {} # Holds listener arrays

func emit(name: String, args:=[]):
	if not name in _listeners: return # Skip if no listeners exist
	_listeners[name] = _listeners[name].filter(func(e): return e.fn.get_object() != null) # Remove null instances
	for e in _listeners[name]: # Iterate callbacks
		e.fn.callv(args) # Call callback
	_listeners[name] = _listeners[name].filter(func(e): return not e.once) # Remove "once" listeners

func once(name: String, fn: Callable) -> Callable:
	return on(name, fn, true)

func on(name: String, fn: Callable, once:=false) -> Callable:
	if not name in _listeners: _listeners[name] = [] # Create listeners array if not exist
	_listeners[name].append({ "fn": fn, "once": once }) # Add listener function
	return off.bind(name, fn, once) # Create unregister callback as result

func off(name: String, fn: Callable, once:=false) -> void:
	if not name in _listeners: return # Skip if no listeners exist
	_listeners[name] = _listeners[name].filter(func(e): return e.fn != fn and e.once != once) # Remove the specific listener
