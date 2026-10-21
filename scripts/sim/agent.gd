class_name Agent
extends RefCounted
## Гонец (этап 12.B): посол с предложением сделки или лазутчик с тайным
## поручением. Идёт по карте из столицы своего государства в столицу чужого
## (профиль «envoy»; за море — через гавань); дело решается, когда он дошёл
## (AgentSystem). Не дошёл за MAX_DAYS — поручение пропало.

var id := -1
## &"envoy" — посольство (сделка DealSystem), &"spy" — тайная операция (SpySystem).
var kind: StringName = &"envoy"
var from := -1
var to := -1
## Вид сделки (envoy) или id операции (spy).
var task: StringName = &""
var m := Mover.new(-1, &"envoy")
var cell: int:
	get:
		return m.cell
	set(v):
		m.cell = v
		m.prev_cell = v
var born := 0
var alive := true
