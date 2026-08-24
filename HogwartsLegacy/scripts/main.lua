local config = require("config/config")
require("config/config_hands")
local uevrUtils = require("libs/uevr_utils")
local debugModule = require("libs/uevr_debug")
local configui = require("libs/configui")
local controllers = require("libs/controllers")
local animation = require("libs/animation")
local hands = require("libs/hands")
local flickerFixer = require("libs/flicker_fixer")
local wand = require("helpers/wand")
local mounts = require("helpers/mounts")
local decoupledYaw = require("helpers/decoupledyaw")
local input = require("helpers/input")
local gesturesModule = require("gestures/gestures")
local handAnimations = require("helpers/hand_animations")
require("helpers/crosshair")
--animation.setLogLevel(LogLevel.Debug)
--hands.setLogLevel(LogLevel.Debug)
-- flickerFixer.setLogLevel(LogLevel.Debug)
-- gesturesModule.setLogLevel(LogLevel.Debug)
--uevrUtils.setLogLevel(LogLevel.Debug)

local version = "1.08c"

local isInCinematic = false
local isInAlohomora = false
local isInAstronomyPuzzle = false

local isFP = true
local isInMenu = false
local isInMainMenu = false
local isInLoadingScreen = false
local isDisguisedAsProfBlack = false
local isWandDisabled = false
local isInGestureCooldown = false
local isGesturesDisabled = false
local enableVRCameraOffset = true

--decoupled yaw variables
local isDecoupledYawDisabled = true
local decoupledYawCurrentRot = 0
local alphaDiff = 0

local lastHMDDirection = nil
local lastHMDPosition = {}
local lastHMDRotation = {}

local lastWandTargetLocation = nil
local lastWandTargetDirection = nil
local lastWandPosition = nil

local phoenixCameraSettings = nil
local currentMediaPlayers = nil
local uiManager = nil

local debugHands = false
local cameraStackVal = true

local hideActorForNextCinematic = false

local g_isLeftHanded = false
local g_lastVolumetricFog = nil
local g_isPregame = true
local g_eulaClicked = false
local g_isShowingStartPageIntro = false
local g_fieldGuideUIManager = nil
local g_wandStyle = nil
local g_lastTabIndex = nil
local g_armState = nil

register_key_bind("F1", function()
    print("F1 pressed\n")
	--pawn:StartBulletTime(0.0, 50.0, false, 1.0, 0.4, 2.0)
end)

function UEVRReady(instance)
	print("UEVR is now ready\n")

	uevr.params.vr.recenter_view()
	--force Native Fix for native rendering
	if uevrUtils.getUEVRParam_int("VR_RenderingMethod") == 0 then uevr.params.vr.set_mod_value("VR_NativeStereoFix","true") end
	--force Ghosting fix for Synced Sequential rendering
	if uevrUtils.getUEVRParam_int("VR_RenderingMethod") == 1 then uevr.params.vr.set_mod_value("VR_GhostingFix","true") end
	--force Decoupled Pitch on and Decoupled Pitch UI Adjust off
	uevr.params.vr.set_decoupled_pitch_enabled(true)	
	uevr.params.vr.set_mod_value("VR_DecoupledPitchUIAdjust","false")
	
	config.init()
	configui.setLabel("versionTxt", "Hogwarts Legacy First Person Mod v" ..  version)
	initLevel()	
	preGameStateCheck()
	hookLateFunctions()
	checkStartPageIntro()
	
	if useCrossHair then
		createCrosshair()
	end
	
	if pawn.InCinematic == true then
		isInCinematic = true -- This makes the avatar in the intro screen be at the right position
	else
		--if injected in a game rather than at the loading screen
		updatePlayer()
	end
	
	--this has to be done here. When done with utils callback the function params dont get changed
	local prevRotation = {}
	uevr.params.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)	
		--print("Pre angle",view_index, rotation.x, rotation.y, rotation.z,"\n")
		--Fix for UEVR broken in Intro
		if rotation ~= nil and rotation.x == -90 and rotation.y == 90 and rotation.z == -90 and prevRotation.X ~= nil and prevRotation.Y ~= nil and prevRotation.Z ~= nil then
			rotation.x = prevRotation.X
			rotation.y = prevRotation.Y
			rotation.z = prevRotation.Z
		end
		prevRotation = {X=rotation.x, Y=rotation.y, Z=rotation.z}
		--End fix
				
		local success, response = pcall(function()		
			if isFP and (not isInCutscene()) and enableVRCameraOffset then
				if not isDecoupledYawDisabled then
					rotation.y = decoupledYawCurrentRot
				end
								
				local mountPawn = mounts.getMountPawn(pawn)
				if uevrUtils.validate_object(mountPawn) ~= nil and uevrUtils.validate_object(mountPawn.RootComponent) ~= nil and mountPawn.RootComponent.K2_GetComponentLocation ~= nil then
					local currentOffset = mounts.getMountOffset()
					temp_vec3f:set(currentOffset.X, currentOffset.Y, currentOffset.Z) -- the vector representing the offset adjustment
					temp_vec3:set(0, 0, 1) --the axis to rotate around
					local forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, rotation.y, temp_vec3)
					local pawnPos = mountPawn.RootComponent:K2_GetComponentLocation()					
					position.x = pawnPos.x + forwardVector.X
					position.y = pawnPos.y + forwardVector.Y
					position.z = pawnPos.z + forwardVector.Z
				end
			end
		end)
	end)
end


function initLevel()
	phoenixCameraSettings = nil
	currentMediaPlayers = nil
	uiManager = nil
	
	controllers.onLevelChange()
	controllers.createController(0)
	controllers.createController(1)
	controllers.createController(2) 
	
	-- Audio spatial fix: pin audio listener to HMD so spatialization uses
	-- head position/direction rather than right controller.
	local _hmdComp = controllers.getController(2)
	local _audioPC = uevr.api:get_player_controller(0)
	if _hmdComp ~= nil and _audioPC ~= nil then
		_audioPC:SetAudioListenerOverride(_hmdComp, uevrUtils.vector(0,0,0), uevrUtils.rotator(0,0,0))
	end
	
	wand.reset()
	gesturesModule.reset()
	hands.reset()
	--connectCube(0)
	
	flickerFixer.create()
	
	hookLevelFunctions()
end

-----------------------------------
-- Config Handlers
configui.onUpdate("locomotionMode", function(value)
	setLocomotionMode(value)
end)

configui.onUpdate("gestureMode", function(value)
	gestureMode = value
end)

configui.onUpdate("targetingMode", function(value)
	setTargetingMode(value)
end)

configui.onUpdate("controlMode", function(value)
	controlMode = value
end)

configui.onUpdate("useCrossHair", function(value)
	useCrossHair = value
	if useCrossHair then
		createCrosshair()
	end

end)

configui.onUpdate("snapAngle", function(value)
	snapAngle = value
end)

configui.onUpdate("smoothTurnSpeed", function(value)
	smoothTurnSpeed = value
end)

configui.onUpdate("useSnapTurn", function(value)
	useSnapTurn = value
	configui.hideWidget("snapAngle", not useSnapTurn)	
	configui.hideWidget("smoothTurnSpeed", useSnapTurn)	
end)

configui.onUpdate("useVolumetricFog", function(value)
	useVolumetricFog = value
	updateVolumetricFog()
end)

configui.onUpdate("manualHideWand", function(value)
	manualHideWand = value
end)

configui.onUpdate("isFP", function(value)
	isFP = value
	updatePlayer()
	if isFP then
		--connectWand()
		setLocomotionMode(locomotionMode)
        uevr.api:dispatch_custom_event("isFp", "1")
	else
		disconnectWand()
		disconnectHands()
		disableDecoupledYaw(true)
        uevr.api:dispatch_custom_event("isFp", "0")
	end
end)

configui.onUpdate("showHands", function(value)
	showHands = value
	disconnectWand()
	gesturesModule.reset()

	if showHands == false then
		disconnectHands()
	end
end)

configui.onUpdate("attachedUI", function(value)
	uevr.params.vr.set_mod_value("UI_FollowView", value and "true" or "false")
end)


-----------------------------------


-----------------------------------
-- Hand functions
local socketOffsetName = "Reference"
function getSocketOffset()
	return handSocketOffsets[socketOffsetName]
end
function createHands()
	--Professor black does not use default pawn mesh
	if isDisguisedAsProfBlack then
		hands.setOffset({X=0, Y=0, Z=0, Pitch=0, Yaw=0, Roll=0})	
		hands.create(pawn.Mesh, profParams, handAnimations)
		if hands.exists() then
			animation.pose("right_glove", "open_right")
			animation.pose("left_glove", "open_left")
		else
			uevrUtils.print("Prof Black hand creation failed", LogLevel.Warning)
		end
	else
		local components = {}
		hands.setOffset({X=0, Y=0, Z=0, Pitch=0, Yaw=-90, Roll=0})	
		for name, def in pairs(handParams) do
			components[name] = uevrUtils.getChildComponent(pawn.Mesh, name)
		end
		hands.create(components, handParams, handAnimations)
		if hands.exists() then
			animation.pose("right_hand", "open_right")
			animation.pose("right_glove", "open_right")
			animation.pose("left_hand", "open_left")
			animation.pose("left_glove", "open_left")

			socketOffsetName = "Reference"
			if not animation.hasBone(hands.getHandComponent(isLeftHanded and Handed.Left or Handed.Right), "SKT_Reference") then
				socketOffsetName = "Custom"
			end
		else
			uevrUtils.print("Hand creation failed", LogLevel.Warning)
		end
	end
	
end
-----------------------------------


-----------------------------------
-- Wand functions
function onWandVisibilityChange(isVisible)
	--uevrUtils.print("Wand visibility changed to " .. (isVisible and "visible" or "hidden"), LogLevel.Info)
	if hands.exists() then
		local handStr = isLeftHanded and "left" or "right"
		if isVisible then
			animation.pose(handStr.."_hand", "grip_"..handStr.."_weapon")
			animation.pose(handStr.."_glove", "grip_"..handStr.."_weapon")
		else
			animation.pose(handStr.."_hand", "open_"..handStr)
			animation.pose(handStr.."_glove", "open_"..handStr)
		end
	end
end

function updateWandVisibility()
	wand.updateVisibility(mounts.getMountPawn(pawn), isWandDisabled or g_isPregame or isInMenu or isInCinematic or not mounts.isWalking() )
end

function disconnectWand()
	wand.disconnect()
	wand.reset()
end

function disconnectHands()
	hands.destroyHands()
	hands.reset()
end

function wandCheck()
	--a varinha e do personagem, nao da montaria: montado numa criatura o pawn
	--controlado e a criatura, que nao tem GetWandStyle. Chamar direto no pawn
	--estourava todo frame e derrubava o resto do tick (uevr_utils.lua:1767).
	local characterPawn = mounts.getMountPawn(pawn)
	if uevrUtils.validate_object(characterPawn) ~= nil and characterPawn.GetWandStyle ~= nil then
		--print(pawn:IsWandEquipped(),pawn:GetWandStyle())
		local wandStyle = characterPawn:GetWandStyle():to_string()
		if g_wandStyle ~= wandStyle then
			if wandStyle == "ElderWand" then 
				isWandDisabled = false
				--connectWand()
				wand.holsterWand(characterPawn, true)
			end
			if g_wandStyle == "ElderWand" then 
				isWandDisabled = true
				disconnectWand()
			end
		end
		g_wandStyle = wandStyle
	end
end


function connectWand()	
	if showHands and hands.exists() then
		wand.connectToSocket(mounts.getMountPawn(pawn), hands.getHandComponent(isLeftHanded and Handed.Left or Handed.Right), "WandSocket", getSocketOffset())	
		local handStr = isLeftHanded and "left" or "right"
		animation.pose(handStr.."_hand", "grip_"..handStr.."_weapon")		
		animation.pose(handStr.."_glove", "grip_"..handStr.."_weapon")		
	else
		wand.connectToController(mounts.getMountPawn(pawn), isLeftHanded and 0 or 1)
	end
end
-----------------------------------


-----------------------------------
-- Player functions
function updatePlayer()
	setCharacterInFPSView(isFP) 
	hidePlayer(isFP)
end

function hidePlayer(state, force)
	if force == nil then force = false end
	--print("hidePlayer:  ", state,pawn,isInCinematic,"\n")
	if (not isInCinematic) or force then	
		local mountPawn = mounts.getMountPawn(pawn)			
		if uevrUtils.validate_object(mountPawn) ~= nil then
			local characterMesh = mountPawn.Mesh
			if uevrUtils.validate_object(characterMesh) ~= nil and characterMesh.SetVisibility ~= nil then
				characterMesh:SetVisibility(not state, true)
			else
				print("hidePlayer: Character mesh not valid\n")
			end
		else
			print("hidePlayer: Pawn not valid\n")
		end
	end
end
-----------------------------------


-----------------------------------
-- Camera Stack functions
function setCameraStackDisabled(cameraStack, state)
    if cameraStack ~= nil then
        for index, stack in pairs(cameraStack) do
            if uevrUtils.validate_object(stack) ~= nil and stack.SetDisabled ~= nil then
				--ExecuteInGameThread( function()
					stack:SetDisabled(state, true)
				--end)
            else
                print("Not valid CameraStack\n")
            end
        end
    end
end

function FindAllOf(name)
	return uevrUtils.find_all_instances(name, false)
end

function setCharacterInFPSView(val)
    PitchToTransformCurves = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_PitchToTransformCurves_Default.BP_PitchToTransformCurves_Default_C")
    AmbientCamAnim_Idle = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/AmbientMovement/BP_AmbientCamAnim_Idle.BP_AmbientCamAnim_Idle_C")
    AmbientCamAnim_Jog = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/AmbientMovement/BP_AmbientCamAnim_Jog.BP_AmbientCamAnim_Jog_C")
    AmbientCamAnim_Sprint = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/AmbientMovement/BP_AmbientCamAnim_Sprint.BP_AmbientCamAnim_Sprint_C")
    CameraStackBehaviorCollisionPrediction = FindAllOf("Class /Script/CameraStack.CameraStackBehaviorCollisionPrediction")
    OpenSpaceCameraStacks = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_AddCameraSpaceTranslation_OpenSpace.BP_AddCameraSpaceTranslation_OpenSpace_C")
	LookAtCameraStacks = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_AddCameraSpaceTranslation_LookAt.BP_AddCameraSpaceTranslation_LookAt_C")
	CombatCameraStacks = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_AddCameraSpaceTranslation_Combat.BP_AddCameraSpaceTranslation_Combat_C")
	MountChargeCameraStacks = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_AddCameraSpaceTranslation_MountCharge.BP_AddCameraSpaceTranslation_MountCharge_C")
	SwimmingCameraStacks = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_AddCameraSpaceTranslation_Swimming_OpenSpace.BP_AddCameraSpaceTranslation_Swimming_OpenSpace_C")
	BroomCameraStacks = FindAllOf("BlueprintGeneratedClass /Game/Data/Camera/Behaviors/BP_AddCameraSpaceTranslation_Broom_Boost_New.BP_AddCameraSpaceTranslation_Broom_Boost_New_C")
	--DefaultCameraStacks = FindAllOf("BP_AddCameraSpaceTranslation_Default_C")

    setCameraStackDisabled(PitchToTransformCurves, val)
    setCameraStackDisabled(AmbientCamAnim_Idle, val)
    setCameraStackDisabled(AmbientCamAnim_Jog, val)
    setCameraStackDisabled(AmbientCamAnim_Sprint, val)
    setCameraStackDisabled(CameraStackBehaviorCollisionPrediction, val)
    setCameraStackDisabled(OpenSpaceCameraStacks, val)
    setCameraStackDisabled(LookAtCameraStacks, val)
    setCameraStackDisabled(CombatCameraStacks, val)
    setCameraStackDisabled(MountChargeCameraStacks, val)
    setCameraStackDisabled(SwimmingCameraStacks, val)
    setCameraStackDisabled(BroomCameraStacks, val)
    --setCameraStackDisabled(DefaultCameraStacks, val)
end
-----------------------------------


function checkStartPageIntro()
	local startPageWidget = uevrUtils.find_first_of("Class /Script/Phoenix.StartPageWidget") 
	if startPageWidget ~= nil and startPageWidget:IsVisible() then
		g_isShowingStartPageIntro = true
	end
	print("Is showing page intro",g_isShowingStartPageIntro,"\n")
	if g_isShowingStartPageIntro then
		uevrUtils.fadeCamera(1.0, true, false, true, true)
	end
end

function toggleDecoupledYaw()
	disableDecoupledYaw(not isDecoupledYawDisabled)
end

function disableDecoupledYaw(val)
	-- MARCO: cada TROCA deste interruptor sai no log.txt. Com ele em true o modo
	-- Head/HMD para em SILENCIO. Nada de `debug` aqui -- a tabela nao existe no Lua
	-- do UEVR. Ver LEIAME_CORPO_VR.md ("Modo Head/HMD" e armadilha 1).
	if val ~= isDecoupledYawDisabled then
		uevrUtils.print("[yaw] decoupled yaw desligado=" .. tostring(val)
			.. ", locomotionMode=" .. tostring(locomotionMode), LogLevel.Error)
	end
	isDecoupledYawDisabled =  val
end

function onHandednessChanged(isLeftHanded)
	print("Is Left handed",isLeftHanded,"\n")
	disconnectWand()
	--connectWand()
end

function handednessCheck()
	if phoenixCameraSettings ~= nil then
		local val = getIsLeftHanded()
		if val ~= g_isLeftHanded then
			g_isLeftHanded = val
			onHandednessChanged(val)
		end
	end
end

function getIsLeftHanded()
	if phoenixCameraSettings == nil then
		phoenixCameraSettings = uevrUtils.find_first_of("Class /Script/Phoenix.PhoenixCameraSettings")
	end
	if phoenixCameraSettings ~= nil then
		return phoenixCameraSettings:GetGamepadSouthpaw()
	end
	return false
end

function isInCutscene()
	return isInCinematic or isInAlohomora or isInAstronomyPuzzle
end

function setLocomotionMode(mode)
	locomotionMode = mode
	print("Locomotion mode = ",locomotionMode,"\n")
	disableDecoupledYaw(locomotionMode == LocomotionMode.Manual)
end

function setTargetingMode(value)
	targetingMode = value
	local pc = uevr.api:get_player_controller(0)
	if pc ~= nil then
		pc:ActivateAutoTargetSense(targetingMode == TargetMode.Auto, true)
	end
end

function disguiseChanged(isDisguised)
	isDisguisedAsProfBlack = isDisguised
	disconnectWand()
	gesturesModule.reset()
	disconnectHands()

	isWandDisabled = isDisguisedAsProfBlack
end

function disguiseCheck()
	local result = false
	local mesh = uevrUtils.getValid(pawn,{"Mesh","SkeletalMesh"})
	if mesh ~= nil and mesh:get_full_name() == "SkeletalMesh /Game/RiggedObjects/Characters/Human/OneOff/Professor_PhineasBlack/SK_Professor_PhineasBlack_Master.SK_Professor_PhineasBlack_Master" then
		result = true
	end
	if isDisguisedAsProfBlack ~= result then
		disguiseChanged(result)
	end
end

local g_screenLocation = uevrUtils.vector_2(0,0)
local WidgetLayoutLibrary = nil
function moveMouse()
	if (isInMainMenu or (g_fieldGuideUIManager ~= nil and g_lastTabIndex ~= 0)) and configui.getValue("virtualMouse") == true then
		if WidgetLayoutLibrary == nil then WidgetLayoutLibrary = uevrUtils.find_default_instance("Class /Script/UMG.WidgetLayoutLibrary") end

		local playerController = uevr.api:get_player_controller(0)
		-- local locationX = 0
		-- local locationY = 0
		
		--zeros
		-- playerController:GetMousePosition(locationX, locationY)
		-- print("Before",locationX, locationY)
				
		--zeros
		-- WidgetLayoutLibrary:GetMousePositionScaledByDPI(playerController, locationX, locationY);
		-- print("In mouse 2",locationX, locationY)
		
		local currentMousePosition = WidgetLayoutLibrary:GetMousePositionOnViewport(uevrUtils.get_world())
		--print("In mouse",currentMousePosition.X, currentMousePosition.Y)

		--if configui.getValue("virtualMouse") == true then
			-- Converts to screen coordinates
			--bool ProjectWorldLocationToScreen(FVector WorldLocation, FVector2D& ScreenLocation, bool bPlayerViewportRelative)
		local distance = 1000
		local forwardVector = controllers.getControllerDirection(1) -- lastHMDDirection
		local worldLocation = forwardVector * distance

			-- local width, height
			-- playerController:GetViewportSize(width, height) --doesnt work
			-- print("WH",width, height)
			-- local size = WidgetLayoutLibrary:GetViewportSize(uevrUtils.get_world())
			-- print("Size",size.X, size.Y)
			
					
			-- --bool ProjectWorldToScreen(class APlayerController* Player, const FVector& WorldPosition, FVector2D& ScreenPosition, bool bPlayerViewportRelative);
			-- Statics:ProjectWorldToScreen(playerController, worldLocation, g_screenLocation, false)
			-- print("Statics",g_screenLocation.X, g_screenLocation.Y)

			-- playerController:ProjectWorldLocationToScreen(worldLocation, g_screenLocation, true)
			-- print("PC",g_screenLocation.X, g_screenLocation.Y)

		local bProjected = WidgetLayoutLibrary:ProjectWorldLocationToWidgetPosition(playerController, worldLocation, g_screenLocation, false)
			--print("WidgetLayoutLibrary",g_screenLocation.X, g_screenLocation.Y)

			--g_screenLocation.X = g_screenLocation.X / width
			--g_screenLocation.Y = g_screenLocation.Y / height
			--print("After 2",g_screenLocation.X, g_screenLocation.Y)

			-- Moves the mouse to that point
			playerController:SetMouseLocation(g_screenLocation.X, g_screenLocation.Y)
			--FEventReply SetMousePosition(FEventReply& Reply, FVector2D NewMousePosition);
		--end
	end
end

function preGameStateCheck()
	if uiManager == nil then 
		uiManager = uevrUtils.find_first_of("Class /Script/Phoenix.UIManager") 
	end
	g_isPregame = uiManager ~= nil and UEVR_UObjectHook.exists(uiManager) and uiManager.IsInPreGameplayState ~= nil and uiManager:IsInPreGameplayState()
end

function inPauseMode()
	if uiManager == nil then 
		uiManager = uevrUtils.find_first_of("Class /Script/Phoenix.UIManager") 
	end
	return uevrUtils.validate_object(uiManager) ~= nil and uiManager.InPauseMode ~= nil and uiManager:InPauseMode()
end

function disableUIFollowsView(val, force)
	if configui.getValue("attachedUI") == true then
		if val then
			uevr.params.vr.set_mod_value("UI_FollowView","false")
			uevr.params.vr.recenter_view()
			print("Turned off UI_FollowsView")
			if configui.getValue("attachedUI") == true and not (g_fieldGuideUIManager ~= nil and g_lastTabIndex == 6) then			 
				decoupledYawCurrentRot = lastHMDRotation.Yaw
			end
		else
			--only disable if not in loading screen and not on map screen
			if not isInLoadingScreen and not (g_fieldGuideUIManager ~= nil and g_lastTabIndex == 6) and (force == true or not isInMenu) then
				uevr.params.vr.set_mod_value("UI_FollowView","true")
				print("Turned on UI_FollowsView")
			end
		end
		isInGestureCooldown = true
		delay(1000, function() 
			isInGestureCooldown = false 
			gesturesModule.reset()
		end)
	end
end

function inMenuChanged(val)
	print("In Menu Changed to ",val)
	disableUIFollowsView(val, true)
	-- if configui.getValue("attachedUI") == true then
		-- if val then
			-- uevr.params.vr.set_mod_value("UI_FollowView","false")
			-- uevr.params.vr.recenter_view()
		-- else
			-- uevr.params.vr.set_mod_value("UI_FollowView","true")
		-- end
	-- end
	-- isInGestureCooldown = true
	-- delay(1000, function() 
		-- isInGestureCooldown = false 
		-- gesturesModule.reset()
	-- end)
	
	-- if val then
		-- print("Entered Menu")
		-- if configui.getValue("attachedUI") == true then
			-- uevr.params.vr.set_mod_value("UI_FollowView","false")
			-- uevr.params.vr.recenter_view()
			-- -- menuOffset = nil
			-- -- if g_fieldGuideUIManager ~= nil then
				-- -- print("Getting menu offset")
				-- -- menuOffset = lastHMDRotation.Yaw
				-- -- uevr.params.vr.recenter_view()
				-- -- -- delay(100, function()
					-- -- -- menuOffset = -( menuOffset + lastHMDRotation.Yaw)
					-- -- -- print(menuOffset)
				-- -- -- end)
			-- -- else
				-- -- uevr.params.vr.recenter_view()
			-- -- end
		-- end
		-- -- if configui.getValue("attachedUI") == true then			 
			-- -- print("HMD when entered menu",lastHMDRotation.Pitch, lastHMDRotation.Yaw, lastHMDRotation.Roll)
			-- -- print("Before prevRotation.Y", prevRotation.Y)
			-- -- print("Before decoupledYawCurrentRot", decoupledYawCurrentRot)
			-- -- -- local uiStartAngle = prevRotation.Y
			-- -- -- uevr.params.vr.set_mod_value("UI_FollowView","false")
			-- -- -- uevr.params.vr.recenter_view()
			-- -- delay(100, function()
			-- -- print("HMD after",lastHMDRotation.Pitch, lastHMDRotation.Yaw, lastHMDRotation.Roll)
			-- -- print("After prevRotation.Y", prevRotation.Y)
			-- -- print("After decoupledYawCurrentRot", decoupledYawCurrentRot)
				-- -- -- menuOffset = lastHMDRotation.Yaw
				-- -- -- print(uiStartAngle, prevRotation.Y,  menuOffset)
				-- -- -- print(menuOffset)
				-- -- --menuOffset = prevRotation.Y
			-- -- end)
			-- -- -- uevr.params.vr.get_pose(uevr.params.vr.get_hmd_index(), temp_vec3f, temp_quatf)
			-- -- -- --print("Quat", temp_quatf.X, temp_quatf.Y, temp_quatf.Z, temp_quatf.W)
			-- -- -- local quat = uevrUtils.quat(temp_quatf.X, temp_quatf.Y, temp_quatf.Z, temp_quatf.W)
			-- -- -- --void Quat_SetComponents(FQuat& Q, float X, float Y, float Z, float W);

			-- -- -- local rotator =  kismet_math_library:Quat_Rotator(quat)
			-- -- -- --print("Rot2", rotator.Roll, rotator.Pitch, rotator.Yaw )
			-- -- --menuOffset = rotator.Pitch
		-- -- end
	-- else
		-- print("Exited menu")
		-- if configui.getValue("attachedUI") == true then
			-- uevr.params.vr.set_mod_value("UI_FollowView","true")
			-- -- if menuOffset ~= nil then
				-- -- print("Final",decoupledYawCurrentRot, lastHMDRotation.Yaw, menuOffset, lastHMDRotation.Yaw - menuOffset)
				-- -- decoupledYawCurrentRot = lastHMDRotation.Yaw - menuOffset
			-- -- end
		-- end
		-- -- if configui.getValue("attachedUI") == true then			 
			-- -- --uevr.params.vr.set_mod_value("UI_FollowView","true")
			-- -- print("HMD when exited menu",lastHMDRotation.Pitch, lastHMDRotation.Yaw, lastHMDRotation.Roll)
			-- -- print("Now prevRotation.Y", prevRotation.Y)
			-- -- print("Now decoupledYawCurrentRot", decoupledYawCurrentRot)
			-- -- -- print(decoupledYawCurrentRot, prevRotation.Y,  menuOffset, (decoupledYawCurrentRot + menuOffset) % 360)
			-- -- --decoupledYawCurrentRot = lastHMDRotation.Yaw-- (decoupledYawCurrentRot + menuOffset) % 360 -- - (prevRotation.Y - menuOffset)
			-- -- --uevr.params.vr.recenter_view()
			-- -- -- doReset = true
			-- -- -- delay(100, function()
				-- -- -- uevr.params.vr.recenter_view()
				-- -- -- menuOffset = 0
				-- -- -- doReset = false
			-- -- -- end)
		-- -- end
	-- end
end

function inMenuMode()
	if uiManager == nil then 
		uiManager = uevrUtils.find_first_of("Class /Script/Phoenix.UIManager") 
	end
	return uevrUtils.validate_object(uiManager) ~= nil and uiManager.GetIsUIShown ~= nil and uiManager:GetIsUIShown()
end

function checkIsInMenu()
	local inMenu = inMenuMode()
	if inMenu ~= isInMenu then
		inMenuChanged(inMenu)
	end
	isInMenu = inMenu
	
	checkIsInMainMenu()
end

--The main menu is where you select which character to play
function inMainMenuChanged(newValue)
end

function inMainMenu()
	if uiManager == nil then 
		uiManager = uevrUtils.find_first_of("Class /Script/Phoenix.UIManager") 
	end
	return uevrUtils.validate_object(uiManager) ~= nil and uiManager.IsInFrontendLevel ~= nil and uiManager:IsInFrontendLevel()
end

function checkIsInMainMenu()
	local inMainMenu = inMainMenu()
	if inMainMenu ~= isInMainMenu then
		inMainMenuChanged(inMainMenu)
	end
	isInMainMenu = inMainMenu
end

function armStateChanged(armState)
	if not manualHideWand then
		if armState == ERightArmState.StopMotionOnly or armState == ERightArmState.EquipItem or armState == ERightArmState.HoldItem then
			wand.setVisibility(true)
			onWandVisibilityChange(true)
		end
		if armState == ERightArmState.UnEquipItem or armState == ERightArmState.HideItem then
			wand.setVisibility(false)
			onWandVisibilityChange(false)
		end
	else
		if armState == ERightArmState.UnEquipItem or armState == ERightArmState.HideItem then
			updateWandVisibility()
		end
	end
end

function updateArmState()
	--mesmo caso do wandCheck: o braco e do personagem. Sem esta guarda, montado
	--numa criatura isto estourava e matava o resto do on_pre_engine_tick.
	local characterPawn = mounts.getMountPawn(pawn)
	if uevrUtils.validate_object(characterPawn) == nil or characterPawn.GetRightArmState == nil then return end
	local armState = characterPawn:GetRightArmState(1)
	if armState ~= g_armState then
		armStateChanged(armState)
	end
	g_armState = armState
end

function updateVolumetricFog()
	if useVolumetricFog ~= nil and g_lastVolumetricFog ~= useVolumetricFog then 
		if useVolumetricFog then
			uevrUtils.set_cvar_int("r.VolumetricFog",1)
		else
			uevrUtils.set_cvar_int("r.VolumetricFog",0)
		end
	end
	g_lastVolumetricFog = useVolumetricFog
end

function solveAstronomyMinigame()
	pawn:CHEAT_SolveMinigame()
end

-----------------------------------
-- Media Player functions
local g_mediaPlayerFadeLock = false
function mediaPlayerCheck()
	--print("mediaPlayerCheck called\n")
	--local doUpdateMediaPlayers = false
	updateMediaPlayers()
	local mediaIsPlaying = false
	local spellUrlStr = ""
	local urlStr = ""
	if currentMediaPlayers == nil then
		print("No instances of 'BinkMediaPlayer' were found\n")
	else
		for Index, mp in pairs(currentMediaPlayers) do
			--print(mp)
			if uevrUtils.validate_object(mp) ~= nil then
				--print(mp.URL, mp:get_full_name(), mp:IsPlaying())
				local isPlaying = mp:IsPlaying()
				urlStr = mp.URL
				if isPlaying and isValidMedia(urlStr) then
					mediaIsPlaying = true
					--setProgressSpecificSettings(urlStr)
					print(urlStr, "\n")
				end
				if gestureMode == GestureMode.Spells and isPlaying and string.match(urlStr, "SpellPreviews") then
					spellUrlStr = urlStr
				end
			else
				--doUpdateMediaPlayers = true
			end
		end
	end

	if mediaIsPlaying and not g_mediaPlayerFadeLock then
		isPlayingMovie = true
		print("Media started\n")
		g_mediaPlayerFadeLock = true
		uevrUtils.fadeCamera(fadeDuration, true)
	end
	if not mediaIsPlaying and g_mediaPlayerFadeLock then
		isPlayingMovie = false
		print("Media stopped\n")
		g_mediaPlayerFadeLock = false
		uevrUtils.fadeCamera(fadeDuration, false,false,true)
	end
	
	if gestureMode == GestureMode.Spells then
		handleSpellMedia(spellUrlStr)
	end
	
	--if doUpdateMediaPlayers then updateMediaPlayers() end

end

--if the function returns false then this url should not trigger a camera fade
function isValidMedia(url)
	local isValid = true
	if string.match(url, "FMV_ArrestoMomentum" ) or string.match(url, "ATL_Tapestry_Ogre_1" ) or string.match(url, "ATL_DailyProphet" ) or string.match(url, "ATL_Portrait" ) or string.match(url, "SpellPreviews") or string.match(url, "FMV_Aim_Mode_1") or string.match(url, "FMV_AM_Finisher") or string.match(url, "FMV_AutoTargeting") or string.match(url, "FMV_AMPickUps_ComboMeter")  or string.match(url, "FMV_Talent_Core_StupefyStun") then
		isValid = false
	end
	return isValid
end

function updateMediaPlayers()
	currentMediaPlayers = FindAllOf("Class /Script/BinkMediaPlayer.BinkMediaPlayer")
end

local lastSpellMediaFileName = ""
function handleSpellMedia(fileName)
	if lastSpellMediaFileName ~= fileName then
		if fileName ~= "" then
			local spellName = getSpellNameFromFileName(fileName)
			if pawn ~= nil and UEVR_UObjectHook.exists(pawn) then
				gesturesModule.showGlyphForSpell(spellName, lastHMDDirection, pawn:K2_GetActorLocation())
			end
		else
			gesturesModule.hideGlyphs()
		end
		lastSpellMediaFileName = fileName
	end 
end

function getSpellNameFromFileName(fileName)
	local name = ""
	local tokens = uevrUtils.splitStr(fileName, "/")
	if #tokens > 0 then
		tokens = uevrUtils.splitStr(tokens[#tokens], ".")
		if #tokens > 0 then
			name = tokens[1]
			tokens = uevrUtils.splitStr(name, "_")
			if #tokens > 1 then
				name = tokens[2]
				if name == "BeastTool" then
					name = tokens[2] .. "_" .. tokens[3]
				end
			end
		end
	end
	return name
end
-----------------------------------

	

function handleFieldGuidePageChange(currentTabIndex)
	--print("Tab",currentTabIndex)
	if g_lastTabIndex == currentTabIndex then return end
	--When viewing the map in the field guide we need to turn off the VR camera hook so that the map can be shown correctly
	--delays are needed to make transitions smoother
	if currentTabIndex == 6 then
		delay(1300, function()
			enableVRCameraOffset = false
			uevrUtils.set_2D_mode(true)
		end)
	elseif currentTabIndex == 1 then
		--when on the gear screen dont offset the camera so that the avatar appears
		enableVRCameraOffset = false
		delay(300, function()
			uevrUtils.set_2D_mode(false)
		end)
	else
		if g_lastTabIndex == 1 then
			delay(500, function()
				enableVRCameraOffset = true
			end)
		else
			enableVRCameraOffset = true
		end
		delay(300, function()
			uevrUtils.set_2D_mode(false)
		end)
	end

	g_lastTabIndex = currentTabIndex

end

-- O body.lua consulta isto: no mapa e na tela de equipamento a camera do VR
-- nao pode ser mexida, senao o mapa e o avatar nao desenham.
function isVRCameraOffsetEnabled()
	return enableVRCameraOffset
end

function startCinematic()
	print("Cinematic started\n")
	if configui.getValue("fpCinematic") ~= true then
		if hideActorForNextCinematic then
			print("Hiding actor for cinematic")
			hidePlayer(isFP)
			hideActorForNextCinematic = false
		else
			delay(200, function()
				hidePlayer(false, true)
			end)
		end
		if manualHideWand then wand.holsterWand(pawn, true) end
		if showHands then
			hands.hideHands(true)
		end
	end
	disableUIFollowsView(true)
end

function endCinematic()
	print("Cinematic ended\n")
	if configui.getValue("fpCinematic") ~= true then
		if showHands then
			hands.hideHands(false)
		end
	end
	--if not isInMenu then
		disableUIFollowsView(false)
	--end
end

function checkCinematic()
	if uevrUtils.validate_object(pawn) ~= nil then
		if pawn.InCinematic ~= isInCinematic then
			if pawn.InCinematic then
				startCinematic()
			else
				endCinematic()
			end
		end
		isInCinematic = pawn.InCinematic 
	end
end

local g_shoulderGripOn = false
function handleBrokenControllers(pawn, state, isLeftHanded)
	local gripButton = XINPUT_GAMEPAD_RIGHT_SHOULDER
	if isLeftHanded then
		gripButton = XINPUT_GAMEPAD_LEFT_SHOULDER
	end
	if not g_shoulderGripOn and uevrUtils.isButtonPressed(state, gripButton)  then
		g_shoulderGripOn = true
		local headLocation = controllers.getControllerLocation(2)
		local handLocation = controllers.getControllerLocation(isLeftHanded and 0 or 1)
		if headLocation ~= nil and handLocation ~= nil then
			local distance = kismet_math_library:Vector_Distance(headLocation, handLocation)
			--print(distance,"\n")
			if distance < 30 then	
				if showHands then
					disconnectWand()
					gesturesModule.reset()
					disconnectHands()
				end
				if not isWandDisabled then
					wand.connectAltWand(pawn, isLeftHanded and 0 or 1)
				end
			end
		end
	elseif g_shoulderGripOn and uevrUtils.isButtonNotPressed(state, gripButton) then
		delay(1000, function()
			g_shoulderGripOn = false
		end)
	end

end

function on_lazy_poll()
	uevr.params.vr.set_snap_turn_enabled(false)
	
	-- ALTERADO (12/08/2026, 2a das duas mudancas nossas neste arquivo): so' suprime
	-- a orientacao de movimento do UEVR quando ESTE perfil esta' dirigindo, senao o
	-- giro seria aplicado duas vezes. Ver LEIAME_CORPO_VR.md, "Locomotion Head".
	local MovementOrientation =  uevrUtils.PositiveIntegerMask(uevr.params.vr:get_mod_value("VR_MovementOrientation"))
	if locomotionMode ~= LocomotionMode.Manual and (MovementOrientation == "1" or MovementOrientation == "2") then
		uevr.params.vr.set_mod_value("VR_MovementOrientation","0")
	end
	
	preGameStateCheck()
	updateMediaPlayers()
	mediaPlayerCheck()
	handednessCheck()
	disguiseCheck()
	wandCheck()
	updateVolumetricFog()
	
	if isFP and showHands and not isInCinematic and not hands.exists() then
		createHands()
	end

	if isFP and not isWandDisabled and not isInCinematic and not wand.isConnected() then --can be disabled when disguised as prof black or in deathly hollows level
		connectWand()
	end
	
	if isFP and manualHideWand then
		updateWandVisibility()
	end
	
	local pc = uevr.api:get_player_controller(0)
	if targetingMode == TargetMode.Manual and pc ~= nil then
		pc:ActivateAutoTargetSense(false, true)
	end
	
	--print("HMD",lastHMDRotation.Pitch, lastHMDRotation.Yaw, lastHMDRotation.Roll)
	-- --print("later",lastHMDPosition.X, lastHMDPosition.Y, lastHMDPosition.Z)
	-- uevr.params.vr.get_pose(uevr.params.vr.get_hmd_index(), temp_vec3f, temp_quatf)
	-- --print("Quat", temp_quatf.X, temp_quatf.Y, temp_quatf.Z, temp_quatf.W)
	-- local quat = uevrUtils.quat(temp_quatf.X, temp_quatf.Y, temp_quatf.Z, temp_quatf.W)
	    -- --void Quat_SetComponents(FQuat& Q, float X, float Y, float Z, float W);

	-- local rotator =  kismet_math_library:Quat_Rotator(quat)
	-- print("Pose", rotator.Roll, rotator.Pitch, rotator.Yaw )
	-- print("Diff", rotator.Pitch - lastHMDRotation.Yaw)
end

function on_level_change(level)
	g_wandStyle = nil
	isWandDisabled = false
	isGesturesDisabled = false
	print("Level changed " .. level:get_full_name())
	if level:get_full_name() == "Level /Game/Environment/DeathlyHallows_Dungeon/maps/DeathlyHallows_Dungeon.DeathlyHallows_Dungeon.PersistentLevel" then
		isWandDisabled = true
	end
	
	initLevel()
end

function on_pre_engine_tick(engine, delta)
	if configui.getValue("fpCinematic") ~= true then
		checkCinematic() 
	end

	local newLocomotionMode = mounts.updateMountLocomotionMode(pawn, locomotionMode)
	if newLocomotionMode ~= nil then 
		setLocomotionMode(newLocomotionMode)
	end
	
	checkIsInMenu()
		
	lastWandTargetLocation, lastWandTargetDirection, lastWandPosition = wand.getWandTargetLocationAndDirection(useCrossHair and not g_isPregame)

    if isFP == true and lastWandTargetLocation ~= nil then
        uevr.api:dispatch_custom_event("WandLocation", string.format("%f %f %f", lastWandTargetLocation.X, lastWandTargetLocation.Y, lastWandTargetLocation.Z))
    end
	
	if isFP and not isInCutscene() and uevrUtils.validate_object(pawn) ~= nil then
		if gestureMode == GestureMode.Spells and (not (g_isPregame or isInMenu or isGesturesDisabled or isInGestureCooldown or not mounts.isWalking())) then
			--print("Is wand equipped",pawn:IsWandEquipped(),"\n")
			gesturesModule.handleGestures(pawn, gestureMode, lastWandTargetDirection, lastWandPosition, delta)
		end
		
		if not isDecoupledYawDisabled then
			local targetDirection = nil
			if wand.isConnected() then targetDirection = lastWandTargetDirection else targetDirection = controllers.getControllerDirection(1) end
			alphaDiff = decoupledYaw.handleDecoupledYaw(pawn, alphaDiff, targetDirection, lastHMDDirection, locomotionMode)
		end
		
		local mountPawn = mounts.getMountPawn(pawn)
		if uevrUtils.validate_object(mountPawn) ~= nil and uevrUtils.validate_object(mountPawn.Mesh) ~= nil and mountPawn.Mesh.bVisible == true then 
			--print("Hiding mesh from tick\n")
			hidePlayer(isFP)
		end
		
		if useCrossHair then
			updateCrosshair(lastWandTargetDirection, lastWandTargetLocation)
		end
		
		updateArmState()

	end
	
	--monitor the field guide tab index on the tick since UEVR cant handle hooked functions correctly
	if g_fieldGuideUIManager ~= nil and g_fieldGuideUIManager.FieldGuideWidget ~= nil then
		--print(g_fieldGuideUIManager.FieldGuideWidget.CurrentTabIndex)
		handleFieldGuidePageChange(g_fieldGuideUIManager.FieldGuideWidget.CurrentTabIndex)
	end
	
	moveMouse()
	
	if uevrUtils.validate_object(pawn) ~= nil and pawn.Mesh ~= nil then
		--print(pawn.Mesh.BodyInstance.bLockRotation, pawn.Mesh.BodyInstance.bLockTranslation)
		pawn.Mesh.BodyInstance.bLockRotation = false
		pawn.Mesh.BodyInstance.bLockTranslation = false
	end

	
	-- if uevrUtils.validate_object(pawn) ~= nil then
		-- pawn:RestoreHealth() --invincibility
	-- end
end

--callback for on_post_calculate_stereo_view_offset
function on_post_calculate_stereo_view_offset(device, view_index, world_to_meters, position, rotation, is_double)
	if view_index == 1 then
		local success, response = pcall(function()		
			lastHMDDirection = kismet_math_library:GetForwardVector(rotation)
			if lastHMDDirection.Y ~= lastHMDDirection.Y then
				print("NAN error",rotation.x, rotation.y, rotation.z,"\n")
				lastHMDDirection = nil
			end
			--must make copy becomes invalid otherwise
			-- lastHMDPosition.X = position.X
			-- lastHMDPosition.Y = position.Y
			-- lastHMDPosition.Z = position.Z
			lastHMDRotation.Pitch = rotation.Pitch
			lastHMDRotation.Yaw = rotation.Yaw
			lastHMDRotation.Roll = rotation.Roll
			
			--print(lastHMDRotation.Pitch, lastHMDRotation.Yaw, lastHMDRotation.Roll)
			--print(lastHMDPosition.X, lastHMDPosition.Y, lastHMDPosition.Z)
		end)
		-- if success == false then
			-- uevrUtils.print("[on_post_calculate_stereo_view_offset] " .. response, LogLevel.Error)
		-- end
	end
end
	
function on_xinput_get_state(retval, user_index, state)
	local success, response = pcall(function()		
		if isFP and (not isInCutscene()) then
			local disableStickOverride = g_isPregame or isInMenu or mounts.isOnBroom() or (gestureMode == GestureMode.Spells and gesturesModule.isCastingSpell(pawn, "Spell_Wingardium"))
			decoupledYawCurrentRot = input.handleInput(state, decoupledYawCurrentRot, isDecoupledYawDisabled, locomotionMode, controlMode, g_isLeftHanded, snapAngle, smoothTurnSpeed, useSnapTurn, alphaDiff, disableStickOverride)
			
			if gestureMode == GestureMode.Spells then
				gesturesModule.handleInput(state, g_isLeftHanded)
			end
			
			if manualHideWand and not isWandDisabled and mounts.isWalking() then
				wand.handleInput(pawn, state, g_isLeftHanded)
			end
			
			if showHands then
				hands.handleInput(state, wand.isVisible())	
			end
			
			handleBrokenControllers(mounts.getMountPawn(pawn), state, g_isLeftHanded)	
		end
	end)
	-- if success == false then
		-- uevrUtils.print("[on_xinput_get_state] " .. response, LogLevel.Error)
	-- end

end

function hookLevelFunctions()
	--move the attack indicator in front of and further away from the hmd
	hook_function("BlueprintGeneratedClass /Game/Pawn/Player/BP_AttackIndicatorVFX.BP_AttackIndicatorVFX_C", "ReceiveIndicatorStart", false, nil,
		function(fn, obj, locals, result)
			if isFP then
				--print("ReceiveIndicatorStart bp\n")
				local components = obj.RootComponent.AttachParent.AttachChildren
				local niagaraClass = uevrUtils.get_class("Class /Script/Niagara.NiagaraComponent")
				for i, component in ipairs(components) do
					if component:is_a(niagaraClass) then
						--print("Got the niagara component")
						--component:DetachFromParent(true,false)
						local location = component:K2_GetComponentLocation()
						location = location + (lastHMDDirection * 300)
						component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
					end
				end
			end
		end
	, true)
	
	hook_function("BlueprintGeneratedClass /Game/Pawn/Shared/StateTree/BTT_Biped_PuzzleMiniGame.BTT_Biped_PuzzleMiniGame_C", "ReceiveExecute", false,
		function(fn, obj, locals, result)
			print("Alohomora:ReceiveExecute\n")
			isInAlohomora = true
			if manualHideWand then wand.setVisible(pawn, false) end
			disableDecoupledYaw(true)
		end
	, nil, true)

	hook_function("BlueprintGeneratedClass /Game/Pawn/Shared/StateTree/BTT_Biped_PuzzleMiniGame.BTT_Biped_PuzzleMiniGame_C", "ExitTask", false, nil,
		function(fn, obj, locals, result)
			print("Alohomora:ExitTask\n")
			isInAlohomora = false
			setLocomotionMode(locomotionMode)
		end
	, true)

end

-- only do this once 
local g_isLateHooked = false
function hookLateFunctions()
	if not g_isLateHooked then		

		hook_function("WidgetBlueprintGeneratedClass /Game/UI/Vendor/UI_BP_Vendor.UI_BP_Vendor_C", "OnIntroStarted", true, nil,
			function(fn, obj, locals, result)
				print("OnIntroStarted called for UI_BP_Vendor_C\n")
			end
		, true)

		hook_function("WidgetBlueprintGeneratedClass /Game/UI/Vendor/UI_BP_Vendor.UI_BP_Vendor_C", "OnOutroEnded", true, nil,
			function(fn, obj, locals, result)
				print("OnIntroStarted called for UI_BP_Vendor_C\n")
			end
		, true)

		hook_function("WidgetBlueprintGeneratedClass /Game/UI/LoadingScreen/UI_BP_NewLoadingScreen.UI_BP_NewLoadingScreen_C", "OnCurtainRaised", true, nil,
			function(fn, obj, locals, result)
				print("OnCurtainRaised called for UI_BP_NewLoadingScreen_C\n",isFP)
				updatePlayer()
			end
		, true)

		hook_function("WidgetBlueprintGeneratedClass /Game/UI/LoadingScreen/UI_BP_NewLoadingScreen.UI_BP_NewLoadingScreen_C", "OnIntroStarted", true, nil,
			function(fn, obj, locals, result)
				print("UI_BP_NewLoadingScreen_C:OnIntroStarted\n")
				isInLoadingScreen = true
				disableUIFollowsView(true)
				uevrUtils.fadeCamera(0.1, true, false, true, true)
			end
		, true)

		hook_function("WidgetBlueprintGeneratedClass /Game/UI/LoadingScreen/UI_BP_NewLoadingScreen.UI_BP_NewLoadingScreen_C", "OnOutroEnded", true, nil,
			function(fn, obj, locals, result)
				print("UI_BP_NewLoadingScreen_C:OnOutroEnded\n")
				isInLoadingScreen = false
				--if not isInMenu then
					disableUIFollowsView(false)
				--end
				if not g_isShowingStartPageIntro and not isInFadeIn then
					uevrUtils.fadeCamera(0.1, false, false, true, false)
				end
			end
		, true)

		--uevr is broken
		-- hook_function("WidgetBlueprintGeneratedClass /Game/UI/Menus/FieldGuide/UI_BP_FieldGuide.UI_BP_FieldGuide_C", "ChangeActivePage", false,
			-- function(fn, obj, locals, result)
				-- print("here")
			-- --debugModule.dump(obj)
				-- --print("Field guide page changed to ", obj.CurrentTabIndex, "\n")
				-- --handleFieldGuidePageChange(obj.CurrentTabIndex)	
			-- end
		-- , nil, true)


		hook_function("WidgetBlueprintGeneratedClass /Game/UI/Actor/UI_BP_Astronomy_minigame.UI_BP_Astronomy_minigame_C", "ConstellationImageLoaded", true, nil,
			function(fn, obj, locals, result)
				print("Astronomy MiniGame ConstellationImageLoaded\n")
				uevrUtils.set_2D_mode(true)
				disableDecoupledYaw(true)
				isInAstronomyPuzzle = true
				if manualHideWand then wand.setVisible(pawn, false) end
				
				--auto solve game unless we can find a solution for UEVR FOV locking
				obj:Solved()
				delay(3000, function()
					solveAstronomyMinigame()
				end)
			end
		, true)

		hook_function("WidgetBlueprintGeneratedClass /Game/UI/Actor/UI_BP_Astronomy_minigame.UI_BP_Astronomy_minigame_C", "OnOutroEnded", true, nil,
			function(fn, obj, locals, result)
				print("Astronomy MiniGame OnOutroEnded\n")
				setLocomotionMode(locomotionMode)
				uevrUtils.set_2D_mode(false)
				isInAstronomyPuzzle = false
			end
		, true)
		

		wand.registerLateHooks()

		if g_isPregame then		
			--using this to show a smooth transition between creating your avatar and starting the game
			hook_function("WidgetBlueprintGeneratedClass /Game/Levels/RootLevel.RootLevel_C", "UnloadAvatarCreatorLevel", true, nil,
				function(fn, obj, locals, result)
					print("RootLevel_C:UnloadAvatarCreatorLevel\n")
					setLocomotionMode(locomotionMode)
				end
			, true)
		
		end

		g_isLateHooked = true
	end

end

wand.registerHooks()

-- Praydog please get rid of the resource conflict BS
-- hook_function("Class /Script/Phoenix.WandTool", "OnRightArmStateChanged", false,
	-- function(fn, obj, locals, result)
		-- --print("OnRightArmStateChanged called")
		-- --print(locals.RightArmState, locals.LastRightArmState)
		-- if isFP then
			-- if not manualHideWand then
				-- if locals.RightArmState == ERightArmState.StopMotionOnly or locals.RightArmState == ERightArmState.EquipItem or locals.RightArmState == ERightArmState.HoldItem then
					-- wand.setVisibility(true)
					-- onWandVisibilityChange(true)
				-- end
				-- if locals.RightArmState == ERightArmState.UnEquipItem or locals.RightArmState == ERightArmState.HideItem then
					-- wand.setVisibility(false)
					-- onWandVisibilityChange(false)
				-- end
			-- else
				-- if locals.RightArmState == ERightArmState.UnEquipItem or locals.RightArmState == ERightArmState.HideItem then
					-- updateWandVisibility()
				-- end
			-- end
		-- end
	-- end
 -- ,nil, true)


hook_function("Class /Script/Engine.PlayerController", "ClientRestart", true, nil,
	function(fn, obj, locals, result)
		print("ClientRestart called\n")
		g_isShowingStartPageIntro = false
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "FieldGuideMenuStart", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:FieldGuideMenuStart\n")
		--debugModule.dump(obj)
		g_fieldGuideUIManager = obj
		uevrUtils.fadeCamera(1.0)
		enableVRCameraOffset = true
		disableDecoupledYaw(true)
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "IsDirectlyEnteringSubMenu", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:IsDirectlyEnteringSubMenu\n")
		g_fieldGuideUIManager = obj
		enableVRCameraOffset = true
		disableDecoupledYaw(true)
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "ExitFieldGuideWithReason", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:ExitFieldGuideWithReason\n")
		g_fieldGuideUIManager = nil
		uevrUtils.set_2D_mode(false)
		setLocomotionMode(locomotionMode)
		enableVRCameraOffset = true
		--always updating hands here until we can find a specific call for glove changes
		if showHands then
			disconnectWand()
			gesturesModule.reset()
			disconnectHands()
		end
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "MissionFailScreenLoaded", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:MissionFailScreenLoaded\n")
		uevrUtils.fadeCamera(1.0, true)
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeInBegin", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:OnFadeInBegin\n")
		uevrUtils.fadeCamera(0.1, true, false)
		isInFadeIn = true
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeInComplete", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:OnFadeInComplete",g_isShowingStartPageIntro,"\n")
		local success, response = pcall(function()
			if not g_isShowingStartPageIntro and not isPlayingMovie then
				--uevrUtils.fadeCamera(0.1, false, false, true)
				uevrUtils.stopFadeCamera()
			end
			hidePlayer(isFP)
			isInFadeIn = false
		end)
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeOutBegin", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:OnFadeOutBegin\n")
		uevrUtils.fadeCamera(0.1, true, false)
	end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeOutComplete", true, nil,
	function(fn, obj, locals, result)
		print("UIManager:OnFadeOutComplete\n")
		if not g_isShowingStartPageIntro and not isPlayingMovie and not isInFadeIn then
			uevrUtils.fadeCamera(1.8, false, false, true)
		end
		hidePlayer(isFP)
	end
, true)

hook_function("Class /Script/Phoenix.PhoenixGameInstance", "OnAcceptEULA", true, nil,
	function(fn, obj, locals, result)
		print("PhoenixGameInstance:OnAcceptEULA called\n")
		g_eulaClicked = true
	end
, true)

hook_function("Class /Script/Phoenix.StartPageWidget", "OnStartPageIntroStarted", true, nil,
	function(fn, obj, locals, result)
		print("StartPageWidget:OnStartPageIntroStarted\n")
		if not g_eulaClicked then
			g_isShowingStartPageIntro = true
			uevrUtils.fadeCamera(0.1, true, false, true, true)
		end
		g_eulaClicked = false
	end
, true)

hook_function("Class /Script/Phoenix.StartPageWidget", "OnStartPageOutroEnded", true, nil,
	function(fn, obj, locals, result)
		print("StartPageWidget:OnStartPageOutroEnded\n")
		g_isShowingStartPageIntro = false
		uevrUtils.fadeCamera(0.1, false, false, true, false)
	end
, true)

hook_function("Class /Script/Phoenix.PhoenixGameInstance", "NewGame", true, nil,
	function(fn, obj, locals, result)
		print("NewGame\n")
		g_isShowingStartPageIntro = false
		disableDecoupledYaw(true)
		enableVRCameraOffset = true
		uevrUtils.fadeCamera(1.0, false, false, true)
	end
, true)

hook_function("Class /Script/Phoenix.Player_AttackIndicator", "ReceiveIndicatorStart", true,
	function(fn, obj, locals, result)
		print("ReceiveIndicatorStart\n")
		local components = obj.RootComponent.AttachParent.AttachChildren
		for i, component in ipairs(components) do
			if component:is_a(M.get_class("Class /Script/Niagara.NiagaraComponent")) then
				print("Got the niagara component")
			end
		end
	end
, nil, true)


local tutorialInstance = nil
hook_function("Class /Script/Phoenix.TutorialSystem", "StartTutorial", true, nil,
	function(fn, obj, locals, result)
		tutorialInstance = obj
		--if we do it immediately then CurrentTutorialStepData still points to the previous tutorial
		delay(200, function() 
			local tutorialName = tutorialInstance.CurrentTutorialData.TutorialName:to_string()
			--debugModule.dump(tutorialInstance)
			print("TutorialName 1=",tutorialInstance.CurrentTutorialStepData.Title,"\n")
			print("TutorialName 2=",tutorialName,"\n")
			print("TutorialName 3=",tutorialInstance.CurrentTutorialStepData.Alias:to_string(),"\n")
			print("TutorialName 4=",tutorialInstance.CurrentTutorialStepData.Body,"\n")
			print("TutorialName 5=",tutorialInstance.CurrentTutorialStepData.BodyPC,"\n")
			print("StartTutorial modal=",tutorialInstance.CurrentTutorialStepData.Modal,"\n")
			print("StartTutorial PausesTheGame=",tutorialInstance.CurrentTutorialStepData.PausesTheGame,"\n")
						
			if tutorialName == "AutoTargetSetting" then
				hideActorForNextCinematic = true
			end
									
			if tutorialInstance.CurrentTutorialStepData.PausesTheGame then
				uevrUtils.fadeCamera(0.3, true)
			end
			
			-- if tutorialInstance.CurrentTutorialStepData.Body == "TUT_Display_SpellMiniGameAdvanced_desc" then
				-- hidePlayer(isFP)
			-- end
			
			--unhide robe hidden sometime during intro combat
			if tutorialInstance.CurrentTutorialStepData.Alias:to_string() == "SprintingTutorialStep1" then
				hidePlayer(false)
			end
			
			if tutorialName == "Healing" then
				fadeDuration = defaultFadeDuration
				setCharacterInFPSView(isFP) --need to do this in case we come directly from the dragon biting scene
				if isFP then setLocomotionMode(locomotionMode) end
				--if manualHideWand then wand.holsterWand(pawn, true) end
			end
					
		end)
	end
, true)

hook_function("Class /Script/Phoenix.TutorialSystem", "OnCurrentScreenOutroEnded", true, nil,
	function(fn, obj, locals, result)
		print("TutorialSystem:OnCurrentScreenOutroEnded\n")
		if uevrUtils.isFadeHardLocked() then
			uevrUtils.fadeCamera(0.1, false, false, true)
		end
		hidePlayer(isFP)
	end
, true)

hook_function("Class /Script/Phoenix.Biped_Player", "OnCharacterLoadComplete", true, nil,
	function(fn, obj, locals, result)
		print("OnCharacterLoadComplete called\n")
		--reset relevant globals
		isInCinematic = false
	end
, true)

hook_function("Class /Script/Phoenix.IntroBlueprintFunctionLibrary", "IntroStart", true, nil,
	function(fn, obj, locals, result)
		print("IntroBlueprintFunctionLibrary:IntroStart called\n")
		g_isShowingStartPageIntro = false
	end
, true)



-- ALTERADO (04/08/2026, 1a das duas mudancas nossas neste arquivo): sem o
-- callback o UEVRReady NUNCA roda com a uevrlib nova (ela se auto-inicializa no
-- require, antes desta funcao existir) e o perfil fica sem painel e sem
-- initLevel. Ver LEIAME_CORPO_VR.md, "Primeira linha alterada no main.lua".
uevrUtils.initUEVR(uevr, function() UEVRReady(uevr) end)


-- ECollisionChannel = {    
	-- ECC_WorldStatic = 0,
    -- ECC_WorldDynamic = 1,
    -- ECC_Pawn = 2,
    -- ECC_Visibility = 3,
    -- ECC_Camera = 4,
    -- ECC_PhysicsBody = 5,
    -- ECC_Vehicle = 6,
    -- ECC_Destructible = 7,
    -- ECC_EngineTraceChannel1 = 8,
    -- ECC_EngineTraceChannel2 = 9,
    -- ECC_EngineTraceChannel3 = 10,
    -- ECC_EngineTraceChannel4 = 11,
    -- ECC_EngineTraceChannel5 = 12,
    -- ECC_EngineTraceChannel6 = 13,
    -- ECC_GameTraceChannel1 = 14,
    -- ECC_GameTraceChannel2 = 15,
    -- ECC_GameTraceChannel3 = 16,
    -- ECC_GameTraceChannel4 = 17,
    -- ECC_GameTraceChannel5 = 18,
    -- ECC_GameTraceChannel6 = 19,
    -- ECC_GameTraceChannel7 = 20,
    -- ECC_GameTraceChannel8 = 21,
    -- ECC_GameTraceChannel9 = 22,
    -- ECC_GameTraceChannel10 = 23,
    -- ECC_GameTraceChannel11 = 24,
    -- ECC_GameTraceChannel12 = 25,
    -- ECC_GameTraceChannel13 = 26,
    -- ECC_GameTraceChannel14 = 27,
    -- ECC_GameTraceChannel15 = 28,
    -- ECC_GameTraceChannel16 = 29,
    -- ECC_GameTraceChannel17 = 30,
    -- ECC_GameTraceChannel18 = 31,
    -- ECC_OverlapAll_Deprecated = 32,
    -- ECC_MAX = 33,
-- }

-- ECollisionEnabled = {  
	-- NoCollision = 0,
	-- QueryOnly = 1,
	-- PhysicsOnly = 2,
	-- QueryAndPhysics = 3,
	-- ECollisionEnabled_MAX = 4,
-- }

-- ECollisionResponse = {
    -- ECR_Ignore = 0,
    -- ECR_Overlap = 1,
    -- ECR_Block = 2,
    -- ECR_MAX = 3,
-- }

-- function connectCube(hand)
	-- --local staticMesh = uevrUtils.getLoadedAsset("StaticMesh /Engine/BasicShapes/Cube.Cube")
	
	-- local staticMesh = uevrUtils.getLoadedAsset("StaticMesh /Game/Environment/Hogwarts/Meshes/Statues/SM_HW_Armor_Sword.SM_HW_Armor_Sword")
	-- local leftComponent = uevrUtils.createStaticMeshComponent("StaticMesh /Game/Environment/Hogwarts/Meshes/Statues/SM_HW_Armor_Sword.SM_HW_Armor_Sword")--"StaticMesh /Engine/BasicShapes/Cube.Cube")
	-- local leftConnected = controllers.attachComponentToController(0, leftComponent)
	
	-- -- uevrUtils.set_component_relative_transform(leftComponent, nil, nil, {X=0.03, Y=0.03, Z=0.03})
	-- uevrUtils.set_component_relative_transform(leftComponent, nil, {Pitch=140, Yaw=0, Roll=0}, nil, {X=0.9, Y=0.9, Z=0.9})
	-- leftComponent:SetCollisionEnabled(3, true)
	-- local fNameProfile =  leftComponent:GetCollisionProfileName()
	-- print("Component Profile Name ",fNameProfile:to_string(),"\n")
	-- print("Pawn capsule Profile Name ",pawn.CapsuleComponent:GetCollisionProfileName():to_string(),"\n")
	-- leftComponent:SetCollisionProfileName(fNameProfile, true)
	-- -- Component Profile Name 		Custom		
	-- -- Pawn capsule Profile Name 		PlayerCapsule		
    -- leftComponent:SetCollisionResponseToAllChannels(ECR_Overlap, true)
 	-- pawn.CapsuleComponent:IgnoreComponentWhenMoving(leftComponent, true)
    -- -- void SetCollisionResponseToChannel(TEnumAsByte<ECollisionChannel> Channel, TEnumAsByte<ECollisionResponse> NewResponse, bool bUpdateOverlaps);
    -- -- void SetCollisionResponseToAllChannels(TEnumAsByte<ECollisionResponse> NewResponse, bool bUpdateOverlaps);
    -- -- void SetCollisionProfileName(FName InCollisionProfileName, bool bUpdateOverlaps);
    -- -- void SetCollisionObjectType(TEnumAsByte<ECollisionChannel> Channel);
    -- -- void SetCollisionEnabled(TEnumAsByte<ECollisionEnabled::Type> NewType, bool bUpdateOverlaps);
    -- -- bool K2_IsQueryCollisionEnabled();
    -- -- bool K2_IsPhysicsCollisionEnabled();
    -- -- bool K2_IsCollisionEnabled();
    -- -- void IgnoreComponentWhenMoving(class UPrimitiveComponent* Component, bool bShouldIgnore);
    -- -- bool GetGenerateOverlapEvents();
    -- -- TEnumAsByte<ECollisionResponse> GetCollisionResponseToChannel(TEnumAsByte<ECollisionChannel> Channel);
    -- -- FName GetCollisionProfileName();
    -- -- TEnumAsByte<ECollisionChannel> GetCollisionObjectType();
    -- -- TEnumAsByte<ECollisionEnabled::Type> GetCollisionEnabled();
	
	

	-- -- local component = uevrUtils.create_component_of_class("Class /Script/OdysseyRuntime.ExtendedOdcRepulsorComponent")
	-- -- if component ~= nil then
		-- -- controllers.attachComponentToController(0, component)
	-- -- else
		-- -- print("ExtendedOdcRepulsorComponent not created\n")
	-- -- end

-- end
