class Parser:
	static func read(buffer: PackedByteArray) -> Variant:
		var buffer_size := buffer.size()
		if buffer_size < 2:
			return null

		var packet_type := buffer[0] >> 4
		var flags := buffer[0] & 0x0F

		var header_offset := 1
		var payload_size := 0

		for i in 4:
			if header_offset + i >= buffer_size:
				return null # End of buffer reached

			var byte := buffer[header_offset]
			payload_size += (byte & 0x7F) * pow(0x80, i)
			header_offset += 1
			if not (byte & 0x80):
				break

		if buffer_size < header_offset + payload_size:
			return null # We dont have enough bytes in buffer to parse the whole packet

		var header_size := header_offset
		return {
			type=packet_type,
			flags=flags,
			header_size=header_size,
			payload_size=payload_size,
			packet_size=header_size + payload_size,
			payload=buffer.slice(header_offset, header_offset + payload_size)
		}

class Builder:
	var _packet_type: int
	var _control_flags: int
	var _payload_stream := StreamPeerBuffer.new()

	func _init(packet_type: int, control_flags:=0):
		_packet_type = packet_type
		_control_flags = control_flags
		_payload_stream.big_endian = true

	func build() -> PackedByteArray:
		var buffer := PackedByteArray()
		buffer.append(_packet_type << 4 | _control_flags & 0x0F)
		buffer.append(0)

		var payload_size := _payload_stream.get_size()
		var offset := 1

		while payload_size > 0x7F:
			buffer[offset] = (payload_size & 0x7F) | 0x80
			payload_size >>= 7
			offset += 1
			if offset + 1 > buffer.size():
				buffer.append(0)

		buffer[offset] = payload_size
		buffer.append_array(_payload_stream.data_array)

		return buffer

	func push(type: String, value: Variant) -> Builder:
		var method_name := "put_%s" % type

		if has_method(method_name):
			self[method_name].callv([value])
		else:
			_payload_stream[method_name].callv([value])

		return self

	func pop(type: String) -> Variant:
		var method_name := "get_%s" % type

		if has_method(method_name):
			return self[method_name].call()

		return _payload_stream[method_name].call()

	func put_str(value: String) -> void:
		_payload_stream.put_u16(value.length())
		_payload_stream.put_data(value.to_utf8_buffer())

	func get_str() -> String:
		return _payload_stream.get_utf8_string(_payload_stream.get_u16())
