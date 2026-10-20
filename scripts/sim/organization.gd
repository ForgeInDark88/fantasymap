class_name Organization
extends RefCounted
## Международная организация (OrgSystem) по описанию OrgDef: члены, основатель,
## для священного союза — общая вера. id = индекс в World.orgs.

var id := -1
var def: OrgDef
var name := ""
var members := PackedInt32Array()
var founder := -1
var founded_year := 0
## Вера священного союза (-1 — не важна).
var faith := -1
var alive := true
## Вышедшие и исключённые: id → год, до которого им не вернуться.
var banned: Dictionary[int, int] = {}
