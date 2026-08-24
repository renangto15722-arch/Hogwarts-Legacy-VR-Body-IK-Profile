--Flick detection

local M = {}

local timeWindow = 0.1  -- Time window in seconds to detect flick
local flickDetected = false
local motionActive = false
local directions = {}
local maxDirections = 20  -- Maximum number of direction vectors to store
local elapsedTime = 0
local inCooldown = false

-- Function to calculate the cross product of two vectors
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

-- Function to calculate the angle between two vectors in radians, signed with respect to the z-axis
local function signedAngleBetweenVectors(vector1, vector2)
    local dotProd = dotProduct(vector1, vector2)
    local mag1 = magnitude(vector1)
    local mag2 = magnitude(vector2)
    local crossProd = crossProduct(vector1, vector2)
    local angle = math.acos(dotProd / (mag1 * mag2))

    -- -- Calculate the sign of the angle using the z-component of the cross product
	local signedAngle = angle
    if crossProd[1] < 0 then
        signedAngle = -angle
    end
	--print("Flick angle", math.deg(angle) , math.deg(signedAngle), dotProd, mag1, mag2, crossProd[1], crossProd[2], crossProd[3], "\n")

    return math.deg(angle)
end

function M.updateGestureDetection(deltaTime, directionVector, flickThreshold)
	if inCooldown then return false, false end
	local gestureDetected = false
	local upDirection = false
    -- Normalize the direction vector
    local magnitude = math.sqrt(directionVector.X^2 + directionVector.Y^2 + directionVector.Z^2)
    if magnitude > 0 then
        directionVector = {X = directionVector.X / magnitude, Y = directionVector.Y / magnitude, Z = directionVector.Z / magnitude}
    end

    -- Add the direction vector to the list with the elapsed time
    elapsedTime = elapsedTime + deltaTime
    table.insert(directions, {X = directionVector.X, Y = directionVector.Y, Z = directionVector.Z, time = elapsedTime})

    -- Remove old direction vectors outside the time window
    while #directions > 0 and elapsedTime - directions[1].time > timeWindow do
        table.remove(directions, 1)
    end

    -- Check if the number of stored direction vectors is sufficient
    if #directions > 1 then
        -- Calculate the dot product between the first and last direction vectors
        local dotProduct = directions[1].X * directions[#directions].X +
                           directions[1].Y * directions[#directions].Y +
                           directions[1].Z * directions[#directions].Z

        -- Calculate the angle between the direction vectors
        local angle = math.acos(dotProduct) * (180 / math.pi)
		

        if angle > flickThreshold then
            -- Check if a flick was not already detected in this motion
            if not flickDetected then
                flickDetected = true
                motionActive = true
                --print("Flick gesture detected!\n")
				-- if directions[#directions].Z - directions[1].Z > 0 then
					-- upDirection = true
				-- end
				if signedAngleBetweenVectors({0,0,1}, {directionVector.X,directionVector.Y,directionVector.Z}) < 30 then
					--print("Yank gesture detected\n")
					upDirection = true
				else
					--print("Flick gesture detected\n")
				end
				
				-- signedAngleBetweenVectors({0,0,1}, {directionVector.X,directionVector.Y,directionVector.Z})
				-- signedAngleBetweenVectors({0,1,0}, {directionVector.X,directionVector.Y,directionVector.Z})
				-- signedAngleBetweenVectors({1,0,0}, {directionVector.X,directionVector.Y,directionVector.Z})
                -- print("Angle: " .. angle .. " degrees, isUp " , upDirection , "\n")
				-- local crossProd = crossProduct({0,0,1}, {directionVector.X,directionVector.Y,directionVector.Z})
				-- print("A",crossProd[1],crossProd[2],crossProd[3],"\n")
				-- crossProd = crossProduct({0,1,0}, {directionVector.X,directionVector.Y,directionVector.Z})
				-- print("B",crossProd[1],crossProd[2],crossProd[3],"\n")
				-- crossProd = crossProduct({1,0,0}, {directionVector.X,directionVector.Y,directionVector.Z})
				-- print("C",crossProd[1],crossProd[2],crossProd[3],"\n")


				gestureDetected = true
            end
        else
            motionActive = false
        end
    end

    -- Limit the size of the directions list to avoid memory overflow
    if #directions > maxDirections then
        table.remove(directions, 1)
    end

    -- Reset flickDetected if the motion is no longer active
    if not motionActive and flickDetected then
        flickDetected = false
    end
	
	return gestureDetected, upDirection
end

function M.reset()
	directions = {}
	flickDetected = true
	motionActive = false
	elapsedTime = 0
	inCooldown = true
	delay(2000, function()
		inCooldown = false
	end)
end

return M