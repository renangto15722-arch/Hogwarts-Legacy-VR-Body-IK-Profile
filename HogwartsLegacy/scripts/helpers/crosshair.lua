local uevrUtils = require("libs/uevr_utils")

local crosshairActor = nil
local crosshairComponent = nil
local crosshairWidget = nil

function createCrosshair()
	destroyCrosshairComponent()
	destroyCrosshairWidget()
	createCrosshairWidget()
	createCrosshairComponent()
end

function updateCrosshair(wandDirection, wandTargetLocation)
	print("Here\n")
	if crosshairWidget ~= nil and UEVR_UObjectHook.exists(crosshairWidget) and crosshairWidget.HandleShowTargetReticule ~= nil then
		print("Updating crosshairWidget\n")
		local AimModeCircle = crosshairWidget.AimModeCircle
		if AimModeCircle ~= nil and AimModeCircle.SetVisibility ~= nil then
			AimModeCircle:SetVisibility(0)
		end
		--crosshairWidget:ShowCombatReticule(true);
		crosshairWidget:HandleShowTargetReticule(true)	
	end
	
	if wandDirection ~= nil and wandTargetLocation ~= nil and crosshairActor ~= nil and UEVR_UObjectHook.exists(crosshairActor) and crosshairActor.K2_SetActorLocationAndRotation ~= nil then
		--print("Updating crosshair\n")
		local distanceAdjustment = 30.0 --move the reticle closer to the wand so it doesnt disapear in walls etc
		temp_vec3f:set(-wandDirection.X,-wandDirection.Y,-wandDirection.Z) --use the inverse direction so it points toward us
		local rot = kismet_math_library:Conv_VectorToRotator(temp_vec3f)
		temp_vec3f:set(wandTargetLocation.X - (wandDirection.X * distanceAdjustment), wandTargetLocation.Y - (wandDirection.Y * distanceAdjustment), wandTargetLocation.Z - (wandDirection.Z * distanceAdjustment))
		crosshairActor:K2_SetActorLocationAndRotation(temp_vec3f, rot, false, reusable_hit_result, false)	
	else
		--print("Not updating crosshair\n")
	end
end


function createCrosshairWidget()
	--local Reticule_C = find_required_object("Class /Script/Phoenix.Reticule")
	-- local crosshairs = uevrUtils.find_all_instances("Class /Script/Phoenix.Reticule", false)--Reticule_C:get_objects_matching(false)
    -- for _, crosshair in ipairs(crosshairs) do
        -- if crosshair:GetOwningPlayerPawn() == pawn then
            -- crosshairWidget = crosshair
        -- end
    -- end

	if crosshairWidget ~= nil and UEVR_UObjectHook.exists(crosshairWidget) and crosshairComponent ~= nil then
		crosshairWidget:RemoveFromViewport()
		crosshairComponent:SetWidget(crosshairWidget)
	end
end

function destroyCrosshairWidget()
	crosshairWidget = nil
end

function createCrosshairComponent()
	--print("createCrosshairComponent called",pawn,crosshairWidget,"\n")
	if pawn ~= nil and UEVR_UObjectHook.exists(pawn) and pawn.K2_GetActorLocation ~= nil then
		print("Create crosshair component called\n")
		local pos = pawn:K2_GetActorLocation()
		if crosshairActor == nil then
			crosshairActor = uevrUtils.spawn_actor( nil, 1, nil)
		end
		if crosshairActor == nil then
			print("Failed to spawn crosshair actor\n")
		else
			temp_transform.Translation = pos
			temp_transform.Rotation.W = 1.0
			temp_transform.Scale3D = Vector3f.new(1.0, 1.0, 1.0)
			if crosshairComponent == nil then
				--local scene_component_c = find_required_object("Class /Script/Engine.SceneComponent")
				local crosshairComponent_c = uevrUtils.get_class("Class /Script/UMG.WidgetComponent")
				crosshairComponent = crosshairActor:AddComponentByClass(crosshairComponent_c, false, temp_transform, false)
				
			end
			if crosshairComponent == nil then
				print("Failed to add crosshair component\n")
			else

				-- Hogwarts Legacy specific
				if crosshairWidget ~= nil then
					-- Add crosshair widget to the widget component
					crosshairWidget:RemoveFromViewport()
					crosshairComponent:SetWidget(crosshairWidget)
				end
				crosshairComponent:SetVisibility(true)
				crosshairComponent:SetHiddenInGame(false)
				crosshairComponent:SetCollisionEnabled(0)
				crosshairComponent:SetRenderCustomDepth(true)
				crosshairComponent:SetCustomDepthStencilValue(100)
				crosshairComponent:SetCustomDepthStencilWriteMask(1)
				--crosshairComponent:SetRenderInDepthPass(false) -- Not in UE4

				crosshairComponent.BlendMode = 2

				--crosshairActor:FinishAddComponent(crosshairComponent, false, temp_transform)
				--crosshairComponent:SetWidget(crosshairWidget)
				crosshairComponent:SetTwoSided(true)

				print("Widget space: " .. tostring(crosshairComponent.Space).."\n")
				print("Widget draw size: X=" .. crosshairComponent.DrawSize.X .. ", Y=" .. crosshairComponent.DrawSize.Y .. "\n")
				print("Widget visibility: " .. tostring(crosshairComponent:IsVisible()).."\n")
			end

		end
	end
	if crosshairActor ~= nil and crosshairComponent ~= nil then
		print("Crosshair Component created\n")
		return true
	else
		print("Crosshair Component creation failed\n")
	end
	return false

end

function destroyCrosshairComponent()
    if crosshairActor ~= nil and UEVR_UObjectHook.exists(crosshairActor) then
        pcall(function() 
            if crosshairActor.K2_DestroyActor ~= nil then
                crosshairActor:K2_DestroyActor()
            end
        end)
    end

	crosshairActor = nil
	crosshairComponent = nil
end
