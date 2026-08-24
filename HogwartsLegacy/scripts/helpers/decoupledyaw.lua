require("config/config")

local M = {}

local HandVector = nil
local HmdVector  = nil

function setTargetingCameraRotation(pawn, lastWandTargetDirection)
	local wandTarget = lastWandTargetDirection --getWandTargetDirection()
	if wandTarget ~= nil and pawn.SetPhoenixCameraRotation ~= nil then		
		--translate UpVector coordinates to worldspace rotation for rotator
		local rotYaw = 0
		if wandTarget.Y >= 0 then
			rotYaw = -(math.asin(wandTarget.X/math.sqrt(wandTarget.X^2+wandTarget.Y^2)))*180/math.pi
		else
			rotYaw = (180+(math.asin(wandTarget.X/math.sqrt(wandTarget.X^2+wandTarget.Y^2)))*180/math.pi)
		end
		
		local rotPitch = math.atan(wandTarget.Z/math.sqrt(wandTarget.X^2+wandTarget.Y^2))*180/math.pi
		temp_vec3f:set(rotPitch,rotYaw+90,0)
		if temp_vec3f.Y ~= temp_vec3f.Y then
			--print("NAN\n")
		else
			pawn:SetPhoenixCameraRotation(temp_vec3f)
		end
	end

end

function M.handleDecoupledYaw(pawn, alphaDiff, lastWandTargetDirection, lastHMDDirection, locomotionMode)
	
	setTargetingCameraRotation(pawn, lastWandTargetDirection)

	if HandVector == nil then
		HandVector = Vector3f.new(0.0,0.0,0.0)
		HmdVector  = Vector3f.new(0.0,0.0,0.0)
	end	
	if locomotionMode == LocomotionMode.Head then 		
		if lastHMDDirection ~= nil and lastWandTargetDirection ~= nil then
			HandVector:set(lastWandTargetDirection.X,lastWandTargetDirection.Y,lastWandTargetDirection.Z)
			HmdVector:set(lastHMDDirection.X,lastHMDDirection.Y,lastHMDDirection.Z)
			local Alpha1
			local Alpha2
			
			if HandVector.x ~= 0 and HandVector.y ~= 0 or  HandVector.x ~= nil or HandVector.y ~= nil  then						
				if HandVector.x >=0 and HandVector.y>=0 then	
					Alpha1 =math.pi/2-math.asin( HandVector.x/ math.sqrt(HandVector.y^2+HandVector.x^2))
				elseif HandVector.x <0 and HandVector.y>=0 then
					Alpha1 =math.pi/2-math.asin( HandVector.x/ math.sqrt(HandVector.y^2+HandVector.x^2))
				elseif HandVector.x <0 and HandVector.y<0 then
					Alpha1 =math.pi+math.pi/2+math.asin( HandVector.x/ math.sqrt(HandVector.y^2+HandVector.x^2))
				elseif HandVector.x >=0 and HandVector.y<0 then
					Alpha1 =3/2*math.pi+math.asin( HandVector.x/ math.sqrt(HandVector.y^2+HandVector.x^2))
				end
			else 
				Alpha1 = math.pi
			end
			
			if HmdVector.x ~=0 and HmdVector.y ~=0 or HmdVector.x ~=nil or HmdVector.y ~= nil then					
				if HmdVector.x >=0 and HmdVector.y>=0 then	
					Alpha2 =math.pi/2-math.asin( HmdVector.x/ math.sqrt(HmdVector.y^2+HmdVector.x^2))
				elseif HmdVector.x <0 and HmdVector.y>=0 then
					Alpha2 =math.pi/2-math.asin( HmdVector.x/ math.sqrt(HmdVector.y^2+HmdVector.x^2))
				elseif HmdVector.x <0 and HmdVector.y<0 then
					Alpha2 =math.pi+math.pi/2+math.asin( HmdVector.x/ math.sqrt(HmdVector.y^2+HmdVector.x^2))
				elseif HmdVector.x >=0 and HmdVector.y<0 then
					Alpha2 =3/2*math.pi+math.asin( HmdVector.x/ math.sqrt(HmdVector.y^2+HmdVector.x^2))
				end
			else
				Alpha2 = math.pi
			end
			
			alphaDiff = Alpha2-Alpha1
		end
	end
	return alphaDiff
end

return M