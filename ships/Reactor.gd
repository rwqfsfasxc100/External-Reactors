extends "res://ships/Reactor.gd"

var thermalReactorPowerExternal = 1e+07

func _ready():
	thermalReactorPower = thermalReactorPower + thermalReactorPowerExternal
	
