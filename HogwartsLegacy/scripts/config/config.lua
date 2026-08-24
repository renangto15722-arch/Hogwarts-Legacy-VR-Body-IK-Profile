require("config/enum")
local configui = require("libs/configui")

local M = {}

--[[
Locomotion Mode
LocomotionMode.Manual = Default game mode
LocomotionMode.Head   = Head/HMD based direction mode
LocomotionMode.Hand   = Hand/Controller direction mode
]]--
locomotionMode = LocomotionMode.Head

--[[
Target Mode
TargetMode.Manual = Manual targeting
TargetMode.Auto = Auto targeting
]]--
targetingMode = TargetMode.Auto

--[[	
Controller Mode
ControllerMode.Basic = Basic control mode
ControllerMode.Advanced = Enhanced control mode (Spells can be cast with right trigger + right thumbstick)
]]--
controlMode = ControllerMode.Advanced

--[[
Gesture Mode
GestureMode.None = No gestures
GestureMode.Spells = Spells can be cast by drawing glyphs. Wrist flick casts previous spell
]]--
gestureMode = GestureMode.None

--[[
Use Crosshair 
true = Show Crosshair
false = No crosshair
]]--
useCrossHair = false

--[[
Manual hide wand 
false = Default gameplay method. Wand is hidden after some period of disuse
true = Wand will only hide when you holster it by putting your hand down to your side and pressing grip
]]--
manualHideWand = true

--[[
Show Hands 
false = No hands will be shown
true = Hands will be visible
]]--
showHands = true

--[[
Player offset 
X - Positive values forward, Negative values backward
Y - Positive values right, Negative values left
Z - Positive values up, Negative values down
]]--
playerOffset = {X=19, Y=-3, Z=70}

--[[
Broom Mount offset 
X - Positive values forward, Negative values backward
Y - Positive values right, Negative values left
Z - Positive values up, Negative values down
]]--
broomMountOffset = {X=-15, Y=0, Z=75}

--[[
Graphorn Mount offset 
X - Positive values forward, Negative values backward
Y - Positive values right, Negative values left
Z - Positive values up, Negative values down
]]--
graphornMountOffset = {X=0, Y=0, Z=40}

--[[
Hippogriff Mount offset 
X - Positive values forward, Negative values backward
Y - Positive values right, Negative values left
Z - Positive values up, Negative values down
]]--
hippogriffMountOffset = {X=0, Y=0, Z=30}

--[[
Hippogriff FlyingMount offset 
X - Positive values forward, Negative values backward
Y - Positive values right, Negative values left
Z - Positive values up, Negative values down
]]--
hippogriffFlyingMountOffset = {X=30, Y=0, Z=30}

--[[
Use Volumetric Fog 
true = Turn on in-game fog
false = Turn off in-game fog
]]--
useVolumetricFog = false

--[[
Use Snap Turn 
true = Turn on snap turn
false = Turn off snap turn
]]--
useSnapTurn = true

--[[
Snap Angle
The angle to turn when snap turn is on
]]--
snapAngle = 30

--[[
Smooth Turn Speed
The speed (from 1 to 100) to turn when snap turn is off
]]--
smoothTurnSpeed = 50

wandAimOffset = 0.0

local configDefinition = {
	{
		panelLabel = "Hogwarts Config", 
		saveFile = "config_hogwarts", 
		layout = 
		{
			{
				widgetType = "text",
				id = "versionTxt",
				label = "First Person Mod"
			},
			{
				widgetType = "combo",
				id = "locomotionMode",
				selections = {"Game","Head/HMD","Hand/Controller"},
				label = "Locomotion Mode",
				initialValue = locomotionMode
			},
			{
				widgetType = "combo",
				id = "targetingMode",
				selections = {"Manual targeting","Auto targeting"},
				label = "Target Mode",
				initialValue = targetingMode
			},
			{
				widgetType = "combo",
				id = "controlMode",
				selections = {"Basic control mode","Enhanced control mode"},
				label = "Controller Mode",
				initialValue = controlMode
			},
			{
				widgetType = "combo",
				id = "gestureMode",
				selections = {"No gestures", "Spells can also be cast with gestures"},
				label = "Gesture Mode",
				initialValue = gestureMode
			},
			{
				widgetType = "checkbox",
				id = "useSnapTurn",
				label = "Use Snap Turn",
				initialValue = useSnapTurn
			},
			{
				widgetType = "slider_int",
				id = "snapAngle",
				label = "Snap Turn Angle",
				speed = 1.0,
				range = {2, 180},
				initialValue = snapAngle
			},
			{
				widgetType = "slider_int",
				id = "smoothTurnSpeed",
				label = "Smooth Turn Speed",
				speed = 1.0,
				range = {1, 100},
				initialValue = smoothTurnSpeed
			},
			{
				widgetType = "checkbox",
				id = "showHands",
				label = "Show Hands",
				initialValue = showHands
			},
			{
				widgetType = "checkbox",
				id = "manualHideWand",
				label = "Manual Hide Wand",
				initialValue = manualHideWand
			},
			-- {
				-- widgetType = "slider_float",
				-- id = "wandAimOffset",
				-- label = "Wand Aim Adjustment",
				-- speed = 0.1,
				-- range = {-10, 10},
				-- initialValue = 0.0
			-- },
			{
				widgetType = "checkbox",
				id = "isFP",
				label = "First Person View",
				initialValue = true
			},
			{
				widgetType = "checkbox",
				id = "fpCinematic",
				label = "First Person Cinematics",
				initialValue = false
			},
			{
				widgetType = "checkbox",
				id = "useVolumetricFog",
				label = "Enable Volumetric Fog",
				initialValue = useVolumetricFog
			},
			{
				widgetType = "checkbox",
				id = "useCrossHair",
				label = "Use crosshair",
				initialValue = useCrossHair,
				isHidden = true
			},
			{
				widgetType = "checkbox",
				id = "virtualMouse",
				label = "Cursor follows controller",
				initialValue = false
			},
			{
				widgetType = "checkbox",
				id = "attachedUI",
				label = "Attach UI to View",
				initialValue = false
			}
		}
	}
}

function M.init()
	configui.create(configDefinition)	
	M.loadSettings()
end

function M.loadSettings()
	isFP = configui.getValue("isFP")
	setLocomotionMode(configui.getValue("locomotionMode"))
	gestureMode = configui.getValue("gestureMode")
	controlMode = configui.getValue("controlMode")
	targetingMode = configui.getValue("targetingMode")
	showHands = configui.getValue("showHands")
	manualHideWand = configui.getValue("manualHideWand")
	useCrossHair = configui.getValue("useCrossHair")
	useVolumetricFog = configui.getValue("useVolumetricFog")
	useSnapTurn = configui.getValue("useSnapTurn")
	snapAngle = configui.getValue("snapAngle")
	smoothTurnSpeed = configui.getValue("smoothTurnSpeed")
	--wandAimOffset = configui.getValue("wandAimOffset")
	configui.hideWidget("snapAngle", not useSnapTurn)	
	configui.hideWidget("smoothTurnSpeed", useSnapTurn)	
	
	print("Is First Person Mode:", isFP, "\n")
	print("Locomotion Mode:", locomotionMode, "\n")
	print("Targeting Mode:", targetingMode, "\n")
	print("Gesture Mode:", gestureMode, "\n")
	print("Control Mode:", controlMode, "\n")
	print("Show Hands:", showHands, "\n")
	print("Manual Hide Wand:", manualHideWand, "\n")
	print("Crosshair visible:", useCrossHair, "\n")
	print("Show Fog:", useVolumetricFog, "\n")
	print("First Person Cinematics:", configui.getValue("fpCinematic"), "\n")
	print("Use Snap Turn:", useSnapTurn, "\n")
	print("Snap Angle:", snapAngle, "\n")
	print("Smooth Turn Speed:", smoothTurnSpeed, "\n")

end

-- configui.onUpdate("wandAimOffset", function(value)
	-- wandAimOffset = value
-- end)

return M