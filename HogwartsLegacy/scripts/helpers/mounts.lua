require("config/config")
local uevrUtils = require("libs/uevr_utils")

local M = {}

local mountType = 6 --see EMountTypes in Phoenix_enums
local isFlying = false

function M.getIsFlying()
	return isFlying
end

function M.getMountType()
	return mountType
end

function M.isWalking()
	return mountType == 6
end

function M.isOnBroom()
	return mountType == 0
end

function M.getMountPawn(pawn)
	local mountPawn = nil
	if uevrUtils.validate_object(pawn) ~= nil then
		mountPawn = pawn
		if mountType >= 2 and mountType <= 5 and pawn.GetMountComponent ~= nil then
			local mountComponent = pawn:GetMountComponent()
			if mountComponent ~= nil then
				mountPawn = mountComponent.RiderCharacter
			end
		end
	end
	return mountPawn
end

function M.getMountOffset()
	local currentOffset = playerOffset --grounded avatar
	if mountType == 0 then --broom flying
		currentOffset = broomMountOffset
	elseif mountType == 2 then --Graphorn
		currentOffset = graphornMountOffset
	elseif mountType == 4 then --Hippogriff
		if isFlying then
			currentOffset = hippogriffFlyingMountOffset
		else
			currentOffset = hippogriffMountOffset
		end
	end	
	return currentOffset
end

function M.getMountInfo(pawn)
	local isFlying = false
	local mountType = 6
	if uevrUtils.validate_object(pawn) ~= nil then
		if pawn.GetMountComponent ~= nil then
			local mountComponent = pawn:GetMountComponent()
			if mountComponent ~= nil and mountComponent.IsFlying ~= nil then
				mountType = mountComponent:GetMountHandler().CreatureMountType
				isFlying = mountComponent:IsFlying()
			end
		else
			if pawn.GetIsOnAMountOrInTransition ~= nil and pawn:GetIsOnAMountOrInTransition() then
				isFlying = true
				mountType = 0 --broom
			end
		end
		-- local rot = {}
		-- pawn:GetActorEyesViewPoint(temp_vec3f, rot)
		-- print("Eyes",temp_vec3f.X,temp_vec3f.Y,temp_vec3f.Z,"\n")
		--void GetActorEyesViewPoint(FVector& OutLocation, FRotator& OutRotation)
		--GetMountComponent
		--IsActivePlayerMount
		--IsControlled
		--IsBotControlled
		--IsMoveInputIgnored
		--IsPawnControlled
		--IsPlayerControlled
		--BP_Graphorn_Creature
	end
	return mountType, isFlying
end

local g_walkingLocomotionMode = nil
function M.updateMountLocomotionMode(pawn, locomotionMode)
	local newLocomotionMode = nil
	local lastMountType = mountType
	mountType, isFlying = M.getMountInfo(pawn)
	if lastMountType ~= mountType then
		--animal mounts need to use locomotion mode 0
		if mountType >=2 and mountType <= 5 then 
			g_walkingLocomotionMode = locomotionMode
			newLocomotionMode = LocomotionMode.Manual
			--setLocomotionMode(0)
		end
		--after dismounting animal mounts, set locomotion mode back to what it was before mounting
		if mountType == 6 and g_walkingLocomotionMode ~= nil then
			--setLocomotionMode(g_walkingLocomotionMode)
			newLocomotionMode = g_walkingLocomotionMode
			g_walkingLocomotionMode = nil
		end
	end	
	return newLocomotionMode
end

return M