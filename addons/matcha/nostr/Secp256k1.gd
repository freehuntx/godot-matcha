# WORK IN PROGRESS! NOSTR NOT IMPLEMENTED YET!

# Ported from: https://github.com/lionello/secp256k1-js

class_name Secp256k1 extends RefCounted

func uint256(x, base:=-1):
	if base != -1:
		push_error("Base not implemented!")
		return

	return Big.new(x)

func _init():
	print(uint256(7).toString())
	print(uint256("79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798".hex_decode()).toString())
