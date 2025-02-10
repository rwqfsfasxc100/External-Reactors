extends Node2D

export  var repairReplacementPrice = 5000000
export  var repairReplacementTime = 48
export  var repairFixPrice = 250000
export  var repairFixTime = 48

export  var action = "power_reactor_toggle"

export  var thermalReactorPowerExternal = 1e+07
export  var electricConversion = 0.7
export  var power = 1.5e+06
export  var minElectric = 50000.0
export  var targetTemperature = 2500.0
export  var coolingTemperature = 3200.0
export  var shutdownTemperature = 4500.0
export  var meltdownTemperature = 5000.0

export  var backupPower = 15000.0
export  var backupWindup = 1.0

export  var mass = 30000

var temperature = 0

export  var heatsinkSpecificHeat = 10000.0
export  var canExplode = true

export (PackedScene) var boomParticle
export  var boomPerSecond = 1024
export  var boomCount = 128
export  var boomSpeed = 1500
export  var boomOffset = 256
export  var curieRadiationFactor = 2.51e-08
export  var radiationFactor = 2e-09

export  var systemName = "SYSTEM_EXTERIOR_STELLARATOR"
export  var accelerationFail = 450

var enabled = true
var ignited = 0

export (PackedScene) var explosionBlueprint

func getTuneables():
	return {}

export  var reactorPitch = 5

export  var bootTime = 0.3
export  var coolTime = 1.0
	
export  var startJolt = 50000
export  var startJoltExtra = 100000

export  var damageCoilsCapacity = 15000
export  var damageCoilsThreshold = 600

export  var damageCoolantCapacity = 50000
export  var damageCoolantThreshold = 200

export  var damageLaserCapacity = 20000
export  var damageLaserThreshold = 4000

export  var reactorRadius = 150
export  var reactorMinRadius = 120
	
func getStatus():
	var dmg = max(max(getCondition("coils"), getCondition("coolant")), getCondition("lasers"))
	return 100 - clamp(100 * (dmg), 0, 100)

func getCondition(type):
	return ship.getSystemDamage(name, type) / getDamageCapacity(type)

func getDamageCapacity(type):
	match (type):
		"coils":
			return damageCoilsCapacity * ship.getCrewAdjustedJuryRigFactorForSystem(name, type)
		"coolant":
			return damageCoolantCapacity * ship.getCrewAdjustedJuryRigFactorForSystem(name, type)
		"lasers":
			return damageLaserCapacity * ship.getCrewAdjustedJuryRigFactorForSystem(name, type)

func getDamage():
	return [
		{"type":"coils", "maxRaw":damageCoilsCapacity, "max":getDamageCapacity("coils"), "current":ship.getSystemDamage(name, "coils"), "name":"DAMAGE_COILS"}, 
		{"type":"coolant", "maxRaw":damageCoolantCapacity, "max":getDamageCapacity("coolant"), "current":ship.getSystemDamage(name, "coolant"), "name":"DAMAGE_COOLANT"}, 
		{"type":"lasers", "maxRaw":damageLaserCapacity, "max":getDamageCapacity("lasers"), "current":ship.getSystemDamage(name, "lasers"), "name":"DAMAGE_LASERS"}, 
	];
	
func getStartJolt()->float:
	return lerp(startJolt + startJoltExtra, startJolt, getCondition("lasers"))
	
func getPower():
	return ignited

var ship
var exploding = false
var thermal = 0

func heatUp():
	thermal = targetTemperature * heatsinkSpecificHeat
	ignited = 1
	
var turbineConsumption = 0.0
var hullNode
var backupState = 0.0
func _ready():
	internalCapacitor = startJolt
	ship = get_parent().get_parent()
	ship.connect("damageImpact", self, "_on_impact")
	ship.connect("damageAcceleration", self, "_on_stress")
	ship.connect("damageThermal", self, "_on_thermal")
	ship.connect("damageEMP", self, "_on_emp")
	
	if ship.ageWithSeed:
		ageIfNeeded()
	if ship.preheat:
		heatUp()
		if ship.isPlayerControlled():
			playerEngineSound.play()
	else :
		thermal = 0
	var pin = $ReactorPhysics / PinJoint2D
	
	pin.node_b = pin.get_path_to(ship)
	ship.excludeBodyFromPhysics($ReactorPhysics)
	hullNode = ship.get_node_or_null("Hull")
	
		
func _on_stress(power, delta):
	var dmg = max(0, power - damageCoilsThreshold) * (delta * 60)
	if dmg > 0:
		
		ship.changeSystemDamage(name, "coils", dmg, getDamageCapacity("coils"))
	if randf() < (power - accelerationFail) / accelerationFail:
		emergencyShutdown = true
	
func _on_impact(power, point, delta):
	var localPoint = global_transform.affine_inverse().xform(point)
	var distance = max(reactorMinRadius, localPoint.length() - reactorRadius)
	var dmg = max(0, power * 100 / (distance * distance) - damageCoolantThreshold * delta * 60.0)
	if dmg > 0:
		ship.changeSystemDamage(name, "coolant", dmg, getDamageCapacity("coolant"))

var pflux = 0
func _on_thermal(power, point, delta):
	var distance = max(reactorMinRadius, (point - global_position).length() - reactorRadius) / reactorMinRadius
	var h = max(0, power * 10 / (distance * distance))
	if h > 0:
		pflux += h
	
var emergencyShutdown = false
func _on_emp(power, point, delta):
	pass
	
	
	
	
	
func initExplosion():
	if ship.cutscene:
		return 
	var ei = explosionBlueprint.instance()
	Tool.deferCallInPhysics(self, "add_child", [ei])
	if ship.isPlayerControlled():
		CurrentGame.emit_signal("gameOver")
	ship.playerControlled = false
	ship.cutscene = true
	ship.autopilot = false
	
func explode():
	exploding = true
	ship.vanish([self])
	ship.angular_velocity = 0
		
func explodeCleanup():
	
	Tool.remove(ship)

func getDEC()->float:
	return lerp(0.1, 0.7, getCondition("coils"))

func getWasteHeat()->float:
	return lerp(0.5, 0.05, getCondition("coolant"))

func drawThermal(power):
	if power > 0 and ignited:
		var waste = power * getWasteHeat()
		thermal += waste
		return power
	else :
		return 0

func getOutput():
	return ignited

onready var playerEngineSound = $EngineSound
onready var playerIgnition = $Ignition
onready var fountain = $ReactorPhysics / Fountain
onready var fountainLight = $ReactorPhysics / FountainLight

export  var telegraphTimeLimit = 8.0
var telegraphTime = 0.0

var internalCapacitor = startJolt

var fried = false
var curie = false
func _physics_process(delta):
	if ship.frozen:
		return 
	if exploding:
		if boomCount > 0:
			var push = boomPerSecond * delta
			for i in range(push):
				var p = boomParticle.instance()
				var v = Vector2(randf() - 0.5, randf() - 0.5).normalized() * boomSpeed
				p.linear_velocity = ship.linear_velocity + v
				p.rotation = randf() * 2 * PI
				p.position = v.normalized() * boomOffset
				add_child(p)
				boomCount -= 1
	else :
		if temperature > meltdownTemperature:
			telegraphTime = clamp(telegraphTime + delta, 0, telegraphTimeLimit)
			if telegraphTime >= telegraphTimeLimit:
				if canExplode:
					initExplosion()
				else :
					fried = true
		if pflux > 0:
			thermal += pflux * delta
			pflux = 0
		var ttd = max(0, (temperature - damageLaserThreshold)) * delta
		if ttd > 0 and not ship.cutscene:
			
			ship.changeSystemDamage(name, "lasers", ttd, getDamageCapacity("lasers"))
		
		var t4 = pow(temperature, 4)
		var radiation = radiationFactor * t4
		
		if temperature > coolingTemperature or curie:
			radiation += curieRadiationFactor * t4
			curie = true
			
		if temperature < targetTemperature:
			curie = false
			
		thermal = max(thermal - radiation * delta, 0)
		temperature = thermal / heatsinkSpecificHeat

		if (emergencyShutdown or not enabled) and ignited > 0:
			ignited = clamp(ignited - delta / coolTime, 0, 1)
			if ignited == 0:
				playerEngineSound.stop()
			
		if temperature < coolingTemperature and ignited == 0:
			emergencyShutdown = false
			
		var balance = clamp(ship.capacitor - ship.powerBalance, minElectric * delta, power * delta)
		if enabled and ignited >= 1 and balance > 0:
			var dec = getDEC()
			var t = drawThermal(balance / dec) * dec
			ship.drawEnergy( - t)
		
		if enabled and ignited < 1:
			ship.drawEnergy( - backupPower * delta * max(backupState - 1, 0))
			backupState = clamp(backupState + delta / backupWindup, 0, 2)
		else :
			backupState = clamp(backupState - delta / backupWindup, 0, 2)
			
		if enabled and ignited < 1 and not emergencyShutdown:
			var fullJolt = getStartJolt()
			var fullJoltWithMargin = 1.1 * fullJolt
			var draw = max(0, fullJoltWithMargin - internalCapacitor)
			var charge = ship.drawEnergy(draw)
			internalCapacitor += charge
			var jolt = fullJolt * delta / bootTime
			if internalCapacitor >= fullJoltWithMargin or (ignited > 0 and internalCapacitor > jolt):
				var got = max(0, min(internalCapacitor, jolt))
				internalCapacitor -= got
				if got > jolt * 0.9:
					ignited = clamp(ignited + delta / bootTime, 0, 1)
					
					if ship.isPlayerControlled():
						if not playerEngineSound.playing:
							playerEngineSound.play()
						if ignited >= 1:
							playerIgnition.play()
					
			
var aged = false
func ageIfNeeded():
	if not aged:
		aged = true
		var sd = ship.ageWithSeed + name.hash()
		var dmg = CurrentGame.ageToDamageWithSeed(ship.getAgeYears(), sd, 3, ship.damageLimit)
		
		ship.changeSystemDamage(name, "coils", float(damageCoilsCapacity) * dmg[0], damageCoilsCapacity)
		ship.changeSystemDamage(name, "lasers", float(damageLaserCapacity) * dmg[1], damageLaserCapacity)
		ship.changeSystemDamage(name, "coolant", float(damageCoolantCapacity) * dmg[2], damageCoolantCapacity)
			
var emittedTime = 0
func _process(delta):
	if ignited > 0:
		playerEngineSound.pitch_scale = max(ignited * reactorPitch * Engine.time_scale, 0.1)
		
	
	var c = K2RGB.toModulatedRGB(temperature)
		
	fountainLight.energy = c.a * 2
	c.a = 1.0
	fountainLight.color = c
	fountain.modulate = c
	
	if curie:
		fountain.emitting = true
		emittedTime = min(emittedTime + delta, fountain.lifetime)
	else :
		fountain.emitting = false
		emittedTime = max(0, emittedTime - delta)
		
	fountainLight.energy = clamp(temperature - 3500 / 3500, 0, 2) * (emittedTime / fountain.lifetime)
	
