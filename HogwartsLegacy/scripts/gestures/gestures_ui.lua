local uevrUtils = require("libs/uevr_utils")

local M = {}

local lengthToScaleRatio = 0.0034
local currentBeamComponent = nil
local beamActors = {}
local glyphActors = {}
local startPosition = nil
local nextPosition = nil

local function crossProduct(vector1, vector2)
    return {
        vector1[2] * vector2[3] - vector1[3] * vector2[2],
        vector1[3] * vector2[1] - vector1[1] * vector2[3],
        vector1[1] * vector2[2] - vector1[2] * vector2[1]
    }
end

local function rotateVector(upVec, forwardVec, angle)
    -- Convert angle to radians
    local radAngle = math.rad(angle)

    -- Normalize the forward vector
    local forwardMag = math.sqrt(forwardVec[1]^2 + forwardVec[2]^2 + forwardVec[3]^2)
    local fx, fy, fz = forwardVec[1]/forwardMag, forwardVec[2]/forwardMag, forwardVec[3]/forwardMag

    -- Calculate the rotation matrix components
    local cosTheta = math.cos(radAngle)
    local sinTheta = math.sin(radAngle)
    local oneMinusCosTheta = 1 - cosTheta

    -- Construct the rotation matrix
    local rotationMatrix = {
        {
            cosTheta + fx^2 * oneMinusCosTheta,
            fx * fy * oneMinusCosTheta - fz * sinTheta,
            fx * fz * oneMinusCosTheta + fy * sinTheta
        },
        {
            fy * fx * oneMinusCosTheta + fz * sinTheta,
            cosTheta + fy^2 * oneMinusCosTheta,
            fy * fz * oneMinusCosTheta - fx * sinTheta
        },
        {
            fz * fx * oneMinusCosTheta - fy * sinTheta,
            fz * fy * oneMinusCosTheta + fx * sinTheta,
            cosTheta + fz^2 * oneMinusCosTheta
        }
    }

    -- Rotate the up vector using the rotation matrix
    local ux, uy, uz = upVec[1], upVec[2], upVec[3]
    local wx = rotationMatrix[1][1] * ux + rotationMatrix[1][2] * uy + rotationMatrix[1][3] * uz
    local wy = rotationMatrix[2][1] * ux + rotationMatrix[2][2] * uy + rotationMatrix[2][3] * uz
    local wz = rotationMatrix[3][1] * ux + rotationMatrix[3][2] * uy + rotationMatrix[3][3] * uz

    -- Return the rotated vector
    return {wx, wy, wz}
end

function M.spawnBeamAtWandPosition(wandTipPosition)
	local endPos = wandTipPosition

	local baseActor = uevrUtils.spawn_actor(uevrUtils.get_transform(endPos), 1, nil)	
	local static_mesh_component_c = uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent")
	
	--The globe thing
	-- local baseComponent = baseActor:AddComponentByClass(static_mesh_component_c, true, temp_transform, false)
	-- temp_vec3f:set(0.01,0.01,0.01)
	-- baseComponent:SetWorldScale3D(temp_vec3f)

	-- local staticMesh = uevr.api:find_uobject("StaticMesh /Game/VFX/Meshes/ParticleMeshes/SM_Eropio_Proj.SM_Eropio_Proj") 
	-- baseComponent:SetStaticMesh(staticMesh, true)
	-- baseComponent:SetCollisionEnabled(false,false)

	local beamScale = 0.3
	--local beamTransform = StructObject.new(ftransform_c)
	local beamTransform = uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/CoreUObject.Transform")

	beamTransform.Translation = endPos
	beamTransform.Rotation.W = 1.0
	beamTransform.Scale3D = Vector3f.new(beamScale, beamScale, beamScale/2)

	local beamComponent = baseActor:AddComponentByClass(static_mesh_component_c, true, beamTransform, false)
	local staticMesh = uevr.api:find_uobject("StaticMesh /Game/VFX/Meshes/Static/VFX_SM_LightPillar_NoSides.VFX_SM_LightPillar_NoSides") 
	beamComponent:SetStaticMesh(staticMesh, true)
	beamComponent:SetCollisionEnabled(false,false)
	beamComponent:SetVisibility(false,false)
	
	currentBeamComponent = beamComponent
	
	table.insert(beamActors, baseActor)
end

function M.updateBeam(wandTipPosition)
	if wandTipPosition ~= nil and currentBeamComponent ~= nil then
		local startPosition = currentBeamComponent:K2_GetComponentLocation()		
		local endPosition = wandTipPosition
		
		local rotator = kismet_math_library:FindLookAtRotation(startPosition, endPosition)
		local roll = rotator.Roll
		rotator.Roll = 90 - rotator.Pitch
		rotator.Yaw = rotator.Yaw - 90
		rotator.Pitch = roll
		currentBeamComponent:K2_SetWorldRotation(rotator, false, reusable_hit_result, false)
		
		local distance = kismet_math_library:Vector_Distance(startPosition, endPosition)
		local scale =  currentBeamComponent:K2_GetComponentScale()
		scale.Z = distance * lengthToScaleRatio
		currentBeamComponent:SetRelativeScale3D(scale)
		currentBeamComponent:SetVisibility(distance > 1,false)
	end
end

local function drawGlyphStroke(position, nextPosition, length)
	local baseActor = uevrUtils.spawn_actor(uevrUtils.get_transform(position), 1, nil)
	local static_mesh_component_c = uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent")

	local beamScale = 0.3
	--local beamTransform = StructObject.new(ftransform_c)
	local beamTransform = uevrUtils.get_reuseable_struct_object("ScriptStruct /Script/CoreUObject.Transform")
	beamTransform.Translation = position
	beamTransform.Rotation.W = 1.0
	beamTransform.Scale3D = Vector3f.new(beamScale, beamScale, beamScale)

	local vectorComponent = baseActor:AddComponentByClass(static_mesh_component_c, true, beamTransform, false)
	staticMesh = uevr.api:find_uobject("StaticMesh /Game/VFX/Meshes/Static/VFX_SM_LightPillar_NoSides.VFX_SM_LightPillar_NoSides") 
	vectorComponent:SetStaticMesh(staticMesh, true)
	vectorComponent:SetCollisionEnabled(false,false)
	
	local rotator = kismet_math_library:FindLookAtRotation(position, nextPosition)
	local roll = rotator.Roll
	rotator.Roll = 90 - rotator.Pitch
	rotator.Yaw = rotator.Yaw - 90
	rotator.Pitch = roll
	vectorComponent:K2_SetWorldRotation(rotator, false, reusable_hit_result, false)
	
	local scale =  vectorComponent:K2_GetComponentScale()
	scale.Z = length * lengthToScaleRatio
	vectorComponent:SetRelativeScale3D(scale)

	table.insert(glyphActors, baseActor)
end


local offsetRight = -40 -- -70
local offsetForward = 230
local offsetUp = 30
-- local angles = {30, 145, -145 ,145}
-- local lengths = {40 , 40, 80 ,40}
function M.drawGlyph(angles, lengths, forwardVector, position)
	
	if lengths == nil then
		lengths = {}
		for i = 1, #angles do
			lengths[i] = 30
		end
	end
	if startPosition == nil then
		startPosition = Vector3f.new(0, 0, 0)
		nextPosition = Vector3f.new(0, 0, 0)
	end 
	forwardVector.Z = 0
	position.Z = position.Z + offsetUp
	local pos = position + (forwardVector * offsetForward)	
	local rightVector = crossProduct({forwardVector.X,forwardVector.Y,forwardVector.Z},{0,0,1})
	startPosition:set(pos.X - (rightVector[1] * offsetRight), pos.Y - (rightVector[2] * offsetRight), pos.Z - (rightVector[3] * offsetRight))
	
	local currentAngle = 0
	local minX = position.X --make all glyphs center aligned
	local maxX = position.X 
	local minY = position.Y 
	local maxY = position.Y 
	local maxZ = position.Z --make all glyphs top aligned
	local vectors = {}
	for index, angle in pairs(angles) do
		currentAngle = currentAngle + angle
		--0 and 360 angles cause rendering issues gimballock?
		if currentAngle == 0 then currentAngle = 1 end
		if currentAngle == 360 then currentAngle = 359 end
		
		--rotate a straight up vector by an angle around the forward vector's axis
		local upVector = rotateVector({0,0,1}, {-forwardVector.X,-forwardVector.Y,-forwardVector.Z}, currentAngle) 
		vectors[index] = { {startPosition.X, startPosition.Y, startPosition.Z}, {startPosition.X + (upVector[1] * lengths[index]),startPosition.Y + (upVector[2] * lengths[index]),startPosition.Z + (upVector[3] * lengths[index])} }
		
		if vectors[index][1][1] > maxX then maxX = vectors[index][1][1] end 
		if vectors[index][2][1] > maxX then maxX = vectors[index][2][1] end 
		if vectors[index][1][1] < minX then minX = vectors[index][1][1] end 
		if vectors[index][2][1] < minX then minX = vectors[index][2][1] end 
		if vectors[index][1][2] > maxY then maxY = vectors[index][1][2] end 
		if vectors[index][2][2] > maxY then maxY = vectors[index][2][2] end 
		if vectors[index][1][2] < minY then minY = vectors[index][1][2] end 
		if vectors[index][2][2] < minY then minY = vectors[index][2][2] end 
		if vectors[index][1][3] > maxZ then maxZ = vectors[index][1][3] end 
		if vectors[index][2][3] > maxZ then maxZ = vectors[index][2][3] end 
		
		startPosition:set(vectors[index][2][1], vectors[index][2][2], vectors[index][2][3])
	end
	
	local xOffset = position.X - ((maxX + minX) / 2)
	local yOffset = position.Y - ((maxY + minY) / 2)
	local zOffset = position.Z - maxZ
	for index = 1, #vectors do
		startPosition:set(vectors[index][1][1] + xOffset, vectors[index][1][2] + yOffset, vectors[index][1][3] + zOffset)
		nextPosition:set(vectors[index][2][1] + xOffset, vectors[index][2][2] + yOffset, vectors[index][2][3] + zOffset)
		drawGlyphStroke(startPosition, nextPosition, lengths[index])
	end

end


local function clearActors(actors)
	for index, actor in pairs(actors) do
		if actor ~= nil then
			local components = actor:K2_GetComponentsByClass(static_mesh_component_c)
			if components ~= nil then
				for index, component in pairs(components) do
					if component ~= nil then
						--component:SetVisibility(false, true)
						actor:K2_DestroyComponent(component)
					end
				end
			end 
			actor:K2_DestroyActor()
		end
	end
end

--not working
function M.fadeBeams(scale)
	for index, actor in pairs(beamActors) do
		if actor ~= nil then
			local components = actor:K2_GetComponentsByClass(static_mesh_component_c)
			if components ~= nil then
				for index, component in pairs(components) do
					if component ~= nil then
						--component:SetVisibility(false, true)
						local cScale =  component:K2_GetComponentScale()
						cScale.X = cScale.X * scale
						cScale.Y = cScale.Y * scale
						component:SetRelativeScale3D(scale)
					end
				end
			end 
		end
	end
end

function M.clearBeams()
	clearActors(beamActors)
	currentBeamComponent = nil
	beamActors = {}
end


function M.clearGlyphs()
	clearActors(glyphActors)
	glyphActors = {}
end

return M