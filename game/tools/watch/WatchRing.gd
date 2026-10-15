## The Watch's ring buffer (pass 80, lane WATCH): the newest `capacity` numbers, oldest first by index, with their sum
## kept as they come and go (the measured speed's half-second buckets, the panel's frame cost). Tools only.
extends RefCounted

var capacity := 1
var _buf := PackedFloat64Array()
var _head := 0
var _count := 0
var _sum := 0.0


func _init(cap: int = 16) -> void:
	capacity = maxi(cap, 1)
	_buf.resize(capacity)
	_buf.fill(0.0)


## Adds `v`; the oldest number goes when the ring is full.
func push(v: float) -> void:
	if _count == capacity:
		_sum -= _buf[_head]
	else:
		_count += 1
	_buf[_head] = v
	_sum += v
	_head = (_head + 1) % capacity


func size() -> int:
	return _count


func is_empty() -> bool:
	return _count == 0


func sum() -> float:
	return _sum


## The mean of what it holds (0 when empty).
func mean() -> float:
	return _sum / float(_count) if _count > 0 else 0.0


## The i-th number, 0 the oldest held (0.0 past the end).
func at(i: int) -> float:
	if i < 0 or i >= _count:
		return 0.0
	var start := (_head - _count + capacity) % capacity
	return _buf[(start + i) % capacity]


## The newest number (0.0 when empty).
func last() -> float:
	return at(_count - 1)


## The sum of the newest `n` numbers.
func sum_newest(n: int) -> float:
	var s := 0.0
	for i in range(maxi(_count - n, 0), _count):
		s += at(i)
	return s


func clear() -> void:
	_buf.fill(0.0)
	_head = 0
	_count = 0
	_sum = 0.0
