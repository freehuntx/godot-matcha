# Generate an random string with a certain length
static func gen_id(len:=20, charset:="0123456789aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ") -> String:
	var word: String
	var n_char = len(charset)
	for i in range(len):
		word += charset[randi()% n_char]
	return word

# Create an signal for async code
static func create_signal(executor=null) -> Signal:
	var node := Node.new()
	node.add_user_signal("completed")
	var sig := Signal(node, "completed")
	sig.connect(func(_val=null): node.queue_free(), CONNECT_ONE_SHOT)
	if executor != null: executor.call(func (val=null): sig.emit(val))
	return sig

static func string_to_id(string: String) -> int:
	var buffer := string.sha256_buffer()
	var id := 0
	for i in range(buffer.size()):
		id += buffer[i] * i
	return id
