class_name Language
extends RefCounted
## Язык или наречие (LanguageSystem). У каждого народа — праязык; отрезанные
## от столицы края дают наречия (parent — язык-предок), а старое наречие
## становится отдельным языком. Цвет — для режима карты «Языки».

var id := -1
var name := ""
var race: RaceDef
var parent := -1
## Наречие (dialect) или самостоятельный язык.
var dialect := false
var born := 0
var color := Color.WHITE
var alive := true
## Сколько краёв говорит (пересчёт раз в год).
var regions := 0
