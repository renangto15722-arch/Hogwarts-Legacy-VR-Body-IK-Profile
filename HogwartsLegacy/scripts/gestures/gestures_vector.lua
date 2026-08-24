--Detect Vectors 
require("gestures/gesture_map")

local M = {}

local minPoints = 3  -- Minimum number of points to detect a vector
local maxDistanceDeviation = 12  -- Maximum allowed deviation from vector angle
local movementThreshold = 2  -- Minimum movement threshold to consider position as moving
local minAngleChange = 40 --The minimum change in vector angle to constitute a change of direction
local vector1 = nil
local vector2 = nil

local wasDetecting = false
local startForwardVector = nil
local points = {}
local vectors = {}

local debugEnabled = false

local function debug_print(str)
	if debugEnabled then 
		print(str)
	end
end

-- Function to calculate the dot product of two vectors
local function dotProduct(vector1, vector2)
    return vector1[1] * vector2[1] + vector1[2] * vector2[2] + vector1[3] * vector2[3]
end

-- Function to calculate the magnitude of a vector
local function magnitude(vector)
    return math.sqrt(vector[1]^2 + vector[2]^2 + vector[3]^2)
end

-- Function to calculate the cross product of two vectors
local function crossProduct(vector1, vector2)
    return {
        vector1[2] * vector2[3] - vector1[3] * vector2[2],
        vector1[3] * vector2[1] - vector1[1] * vector2[3],
        vector1[1] * vector2[2] - vector1[2] * vector2[1]
    }
end

-- Function to normalize a vector
local function normalize(vector)
    local mag = magnitude(vector)
    return {vector[1] / mag, vector[2] / mag, vector[3] / mag}
end

-- Function to perform matrix multiplication
local function matrixMultiply(matrix, vector)
    return {
        matrix[1][1] * vector[1] + matrix[1][2] * vector[2] + matrix[1][3] * vector[3],
        matrix[2][1] * vector[1] + matrix[2][2] * vector[2] + matrix[2][3] * vector[3],
        matrix[3][1] * vector[1] + matrix[3][2] * vector[2] + matrix[3][3] * vector[3]
    }
end

-- Function to rotate a vector around another vector using rotation matrix
local function rotateVector(vector, axis, angle)
    local axisNormalized = normalize(axis)
    local x, y, z = axisNormalized[1], axisNormalized[2], axisNormalized[3]
    local cosTheta = math.cos(angle)
    local sinTheta = math.sin(angle)

    local rotationMatrix = {
        {
            cosTheta + x * x * (1 - cosTheta),
            x * y * (1 - cosTheta) - z * sinTheta,
            x * z * (1 - cosTheta) + y * sinTheta
        },
        {
            y * x * (1 - cosTheta) + z * sinTheta,
            cosTheta + y * y * (1 - cosTheta),
            y * z * (1 - cosTheta) - x * sinTheta
        },
        {
            z * x * (1 - cosTheta) - y * sinTheta,
            z * y * (1 - cosTheta) + x * sinTheta,
            cosTheta + z * z * (1 - cosTheta)
        }
    }

    return matrixMultiply(rotationMatrix, vector)
end

-- -- Function to calculate the angle between a 3D vector and the x-axis in radians
-- local function signedAngleFromAxis(vector, axis)
    -- local axisNormalized = normalize(axis)
    -- local vectorNormalized = normalize(vector)
    -- local dotProd = dotProduct(axisNormalized, vectorNormalized)
    -- local angle = math.acos(dotProd)

    -- local crossProd = crossProduct(axisNormalized, vectorNormalized)

    -- -- Calculate the sign of the angle using the z-component of the cross product
    -- if crossProd[3] < 0 then
        -- angle = -angle
    -- end

    -- return angle
-- end

-- -- Function to calculate the angle between two vectors in radians, signed with respect to the z-axis
-- local function signedAngleBetweenVectors(vector1, vector2)
    -- local dotProd = dotProduct(vector1, vector2)
    -- local mag1 = magnitude(vector1)
    -- local mag2 = magnitude(vector2)
    -- local crossProd = crossProduct(vector1, vector2)
    -- local angle1 = math.acos(dotProd / (mag1 * mag2))

    -- -- Calculate the sign of the angle using the z-component of the cross product
    -- if crossProd[1] < 0 then
        -- angle = -angle1
	-- else
		-- angle = angle1
    -- end
	-- print("ss",dotProd, mag1, mag2, angle1, angle, crossProd[1], crossProd[2], crossProd[3], "\n")

    -- return angle
-- end

-- Function to calculate the angle between two vectors in radians
local function angleBetweenVectors(vector1, vector2)
    local dotProd = dotProduct(vector1, vector2)
    local mag1 = magnitude(vector1)
    local mag2 = magnitude(vector2)
    return math.acos(dotProd / (mag1 * mag2))
end


-- local function detectVectorIn3DSpace(points)
    -- local totalPoints = #points
    -- if totalPoints < minPoints then
        -- return false  -- Not enough points to detect a vector
    -- end

	-- local distances = {}
	-- local vector1 = nil
	-- local vector2 = nil
	-- for i = 1, totalPoints - 1 do
		-- local j = i + 1
		-- local dx = points[j].X - points[i].X
		-- local dy = points[j].Y - points[i].Y
		-- local dz = points[j].Z - points[i].Z

		-- if vector1 == nil then
			-- vector1 = {dx, dy, dz}
		-- else
			-- vector2 = {dx, dy, dz}
		-- end

		-- if vector2 ~= nil then
			-- local angle = angleBetweenVectors(vector1, vector2)
			-- -- Convert the angle from radians to degrees
			-- local angleInDegrees = math.deg(angle)

			-- --print("The angle between the vectors is: " .. angleInDegrees .. " degrees\n")
			-- if angleInDegrees > 60 then
				-- print("* Direction change detected\n")
				-- return true
			-- end
			-- vector1 = vector2
		-- end
	-- end

    -- return false
-- end

local function detectAngleChangeIn3DSpace(points)
    local totalPoints = #points
    if totalPoints < minPoints then
        return false  -- Not enough points to detect a vector
    end
	
	local j = totalPoints - 1
	local vector1 = {points[j].X - points[1].X, points[j].Y - points[1].Y, points[j].Z - points[1].Z}
	local vector2 = {points[j+1].X - points[j].X, points[j+1].Y - points[j].Y, points[j+1].Z - points[j].Z}
	local angle = angleBetweenVectors(vector1, vector2)
	-- Convert the angle from radians to degrees
	local angleInDegrees = math.deg(angle)
	--print("The angle between the vectors is: " .. angleInDegrees .. " degrees\n")
	if angleInDegrees > minAngleChange then
		debug_print("* Direction change detected\n")
		return true
	end
	
    return false
end


local function inRange(valueA, valueB, maxDeviation)
	--print(valueA, valueB, maxDeviation, "\n")
	if math.abs(valueA - valueB) < maxDeviation then
		return true
	end
	return false
end

						
local function addVectorToTable(x, y, z)
	if not (x == 0 and y == 0 and z == 0) then
		table.insert(vectors, {X = x, Y = y, Z = z})
	end
end

local function getVectorAngles(currentDirection)
	local results = {}

	if vector1 == nil then
		vector1 = Vector3f.new(0, 0, 0)
		vector2 = Vector3f.new(0, 0, 0)
	end 

	local totalVectors = #vectors
	debug_print("Detecting glyph with " .. totalVectors .. " vectors\n")
	if totalVectors > 0 then
		--calculate the initial angle in the z direction around the initial forward vector
		vector1:set(startForwardVector.X,startForwardVector.Y,startForwardVector.Z)
		vector2:set(vectors[1].X,vectors[1].Y,vectors[1].Z)
		local initialAngle = kismet_math_library:MakeRotFromXZ(vector1, vector2).Roll
		if initialAngle < 0 then initialAngle = initialAngle + 360 end
		debug_print("Initial Angle: " .. initialAngle .. "\n")
		table.insert(results, initialAngle)		
		
		for i = 1, totalVectors - 1 do
			local vector1 = {vectors[i].X, vectors[i].Y, vectors[i].Z}
			local vector2 = {vectors[i+1].X, vectors[i+1].Y, vectors[i+1].Z}	
			--get an angle between the normal of the two vectors and the direction the wand is pointing
			--base cw or ccw off of that angle
			local normal = crossProduct(vector1, vector2)
			local dirAngle = math.deg(angleBetweenVectors({currentDirection.X, currentDirection.Y, currentDirection.Z}, normal))
			if dirAngle ~= dirAngle then --got a Nan
				print("NAN",vector1[1],vector1[2],vector1[3],vector2[1],vector2[2],vector2[3], currentDirection.X, currentDirection.Y, currentDirection.Z,"\n")
			else
				local angle = angleBetweenVectors(vector1, vector2)
				if dirAngle < 90 or dirAngle > 270 then
					angle = -angle
				end
				local angleInDegrees = math.deg(angle)
				--print("The angle between the final vectors is: " , i, dirAngle, angle, angleInDegrees, " degrees\n")
				debug_print(" Angle " .. i .. ": " .. angleInDegrees .. " degrees\n")
				if angleInDegrees ~= nil then
					table.insert(results, angleInDegrees)
				end
			end
		end
		debug_print("Glyph detection found " .. #results .. " angles\n")
	end 
	return results
end

local function verifyCurrentAngles(currentDirection)
	local isValid = false
	local results = getVectorAngles(currentDirection)
	if #results > 0 then
		for i = 1, #glyphGestures do
			local gesture = glyphGestures[i] 
			local gestureAngles = gesture.angles
			local found = true
			for j = 1, #results do
				if #gestureAngles >= j then
					if not inRange(gestureAngles[j], results[j], maxDistanceDeviation) and not inRange(gestureAngles[j] + 360, results[j], maxDistanceDeviation) then
						found = false
						break
					end
				end
			end
			if found then
				isValid = true
				break
			end
		end
	end
	return isValid
end
							
local function finalizeDetection(currentDirection)
	local gestureID = ""
	
	if #points >= minPoints then
		addVectorToTable(points[#points].X - points[1].X, points[#points].Y - points[1].Y, points[#points].Z - points[1].Z)
	end
	local results = getVectorAngles(currentDirection)
	
	--this prevents single vector gestures. If single vector gestures are desired, set value to 0
	if #results > 1 then
		for i = 1, #glyphGestures do
			local gesture = glyphGestures[i] 
			local gestureAngles = gesture.angles
			if #results >= #gestureAngles then
				local found = true
				for j = 1, #gestureAngles do
					if not inRange(gestureAngles[j], results[j], maxDistanceDeviation) and not inRange(gestureAngles[j] + 360, results[j], maxDistanceDeviation) then
						found = false
						break
					end
				end
				if found then
					gestureID = gesture.id
					break
				end
			end
		end
	end
	if gestureID ~= "" then
		debug_print("### Gesture " .. gestureID .. " detected\n")
	else
		debug_print("No gesture detected\n")
	end

	M.reset()
	
	return gestureID

end

function M.updateGestureDetection(deltaTime, currentPosition, currentDirection, isDetecting)

	local gestureID = ""
	local angleChangeDetected = false
	local detectionFailed = false
	if wasDetecting and not isDetecting then
		gestureID = finalizeDetection(currentDirection)
	elseif isDetecting then
		if startForwardVector == nil then
			startForwardVector = currentDirection
		end
		-- Check if there's significant movement
		local validPoint = true
		if #points > 0 then
			local dx = currentPosition.X - points[#points].X
			local dy = currentPosition.Y - points[#points].Y
			local dz = currentPosition.Z - points[#points].Z
			local distanceMoved = math.sqrt(dx*dx + dy*dy + dz*dz)
			
			if distanceMoved < movementThreshold then
				validPoint = false -- Position not moving significantly, skip detection
			end
			--print("Position moved", distanceMoved, currentPosition.X, currentPosition.Y, currentPosition.Z, "\n")
		end
		if validPoint then
			-- Add the current position to the list
			table.insert(points, {X = currentPosition.X, Y = currentPosition.Y, Z = currentPosition.Z})

			angleChangeDetected = detectAngleChangeIn3DSpace(points)
			if angleChangeDetected then
				debug_print("Adding to vector list\n")
				local lastPointIndex =  #points - 2
				addVectorToTable(points[lastPointIndex].X - points[1].X, points[lastPointIndex].Y - points[1].Y, points[lastPointIndex].Z - points[1].Z)
				points = {}
				detectionFailed = not verifyCurrentAngles(currentDirection)
			end

			-- Limit the size of the points list to avoid memory overflow
			if #points > 100 then
				table.remove(points, 1)
			end
		end
	end
	wasDetecting = isDetecting
	
	return gestureID, angleChangeDetected, detectionFailed
end

function M.reset()
	wasDetecting = false
	startForwardVector = nil
	points = {}
	vectors = {}
end

return M