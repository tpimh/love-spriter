--[[
 Copyright (c) 2014, Hardcrawler Games LLC

This library is free software; you can redistribute it and/or modify it
under the terms of the MIT license. See LICENSE for details.

I haven't actually read the MIT license.  I think it's permissive and stuff.  Send me a keg of Newcastle beer if this makes you rich.

id/references Note:
This parser is adding 1 to all id/parent/etc values and references because of Lua 1 based tables
From looking at the data, I am assuming that the ID in the data is a 1:1 mapping to C-style 0-indexed arrays
The re-mapping is not 100% necessary, but in Lua it is a LOT easier for things to be 1-based.  It is not worth it to maintain 0-indexed arrays

usage:
local Spriter = require("libs/Spriter")
--Animation filename assumed to be animationDirectory/animationDirectory.scon
local spriterData = Spriter:loadSpriter("./", "animationDirectory")

Note: loadSpriter is primary entry point to class.
--]]

--Spriter files are "scml" (xml) or "scon" (json).  We will use the dkjson library to load json "scon" files
local json = require("libs/dkjson")


local Spriter = {}

----------------------------------------------------------------------------
--Skip this block.  It's just for debugging
--printTable For debugging of data structure:
--Table print that won't recurse into self-referential keys
--Based on naming convention prefix "cyc" to denote cyclic
----------------------------------------------------------------------------
local function printf(fmt, ...)
        return print(string.format(fmt, ...))
end
--Note, I got this printTable off of a programming forum, but can't remember where
--I customized with "cyc" exception
local function printTable(table, indent)

  indent = indent or 4;

  if indent > 16 then
        printf("%s ...(maxdepth)", string.rep('  ', indent));
  	return
  end

  local keys = {};

  print(string.rep('  ', indent)..'{');
  indent = indent + 1;
  for k, v in pairs(table) do

    local key = k;
    if (type(key) == 'string') then
      if not (string.match(key, '^[A-Za-z_][0-9A-Za-z_]*$')) then
        key = "['"..key.."']";
      end
    elseif (type(key) == 'number') then
      key = "["..key.."]";
    end

    if (type(v) == 'table') then
      if (next(v)) then
        printf("%s%s =", string.rep('  ', indent), tostring(key));
	if string.find(key, "cyc") then
		local id = "(nil)"
		if v.id then
			id = v.id
		end
		if v.name then
			id = v.name
		end
			
		printf("%s(cyclic reference id: '" .. id .. "')", string.rep('  ', indent+1))
	else
		printTable(v, indent);
	end
      else
        printf("%s%s = {},", string.rep('  ', indent), tostring(key));
      end 
    elseif (type(v) == 'string') then
      printf("%s%s = %s,", string.rep('  ', indent), tostring(key), "'"..v.."'");
    else
      printf("%s%s = %s,", string.rep('  ', indent), tostring(key), tostring(v));
    end
  end
  indent = indent - 1;
  print(string.rep('  ', indent)..'}');
end --printTable
--So main can use it
Spriter.printTable = printTable

--End of Skip this block.
----------------------------------------------------------------------------


--Dig through data structure, ensure files exist, load images, and store references within data structure
function Spriter:loadFilesAndFolders()
	for i = 1, # self.folder do

		local files = self.folder[i].file
		for j = 1, # files do
			local file = files[j]

			--Parse out filename without path and store it
			local dir, filename, extension = string.match(file.name, "(.-)([^/]-([^%.]+))$")
			file.filename = filename

			--FIXME COUPLING - store LOVE image reference in image object
			local image = love.graphics.newImage( self.path .. "/" .. file.name)
			assert(image, "nil image!")
			file.image = image
		end
	end

	return files, folders
end --loadFilesAndFolders

--Recurse through data structure and add 1 to all c-style 0-indexed references so they are Lua-style 1-indexed tables
function Spriter:updateIds( spriterData )
	for k, v in pairs( spriterData ) do
		if k == "id" or k == "parent" or k == "obj" or k == "file" or k == "folder" or k == "key" or k == "timeline" then
			if type(v) == "number" then
				spriterData[k] = v + 1
			end
		end
		if type(v) == "table" then
			self:updateIds( v )
		end
	end
end --updateIds

--Recurse through data structure and convert all angles from degrees to radians
--Who uses degrees these days?  Sheesh.  Actually, I prefer degrees.  But math libraries don't.  Sad face.
function Spriter:anglesToRadians( spriterData )
	for k, v in pairs( spriterData ) do
		if k == "angle"  then
			if type(v) == "number" then
				spriterData[k] = (spriterData[k] * 0.0174532925) 
			end
		end
		if type(v) == "table" then
			self:anglesToRadians( v )
		end
	end
end --updateIds


--Create "next" references in mainline keys so we can easily access the next key from the data structure 
function Spriter:createKeyReferences()
	for animationIndex = 1, # self.entity[1].animation do
		local animation = self.entity[1].animation[animationIndex]
		local keys = animation.mainline.key
		for keyIndex = 1, # keys do
			local key = keys[keyIndex]
			--Last mainline's "next" keyframe is the first frame
			if keyIndex == # keys then
				key.cycNextKey = keys[ 1 ]
			else
				key.cycNextKey = keys[ keyIndex + 1 ]
			end
		end
	end
end --createKeyReferences

--Map timeline/key reference pairs within data structure to actual object references
function Spriter:updateTimelineReferences()
	--I believe that the only timeline references are in the mainlines of the animations
	--NOTE: hard-coding for 1 entity
	for i = 1, # self.entity[1].animation do
		local animation = self.entity[1].animation[i]
		assert(animation, "nil animation on index " .. i)
		local mainline = animation.mainline
		assert(animation.mainline, "nil mainline on animation " .. i)
		for keyIndex = 1, # mainline.key do
			local key = mainline.key[keyIndex]
			assert(key, "Key " .. tostring(keyIndex) .. " not found")
			for boneRefIndex = 1, # key.bone_ref do
				local boneRef = key.bone_ref[boneRefIndex]
				assert(boneRef, "Key " .. tostring(keyIndex) .. " boneRef " .. tostring(boneRefIndex) .. " has no boneref")
				boneRef.cycKey, boneRef.boneName = self:getTimelineKeyById( i, boneRef.timeline, boneRef.key )
				boneRef.cycBone = self:getBoneByName( boneRef.boneName )
				--Copy values so we don't have to dig into the key during animation
				boneRef.scale_x = boneRef.cycKey.bone.scale_x
				boneRef.scale_y = boneRef.cycKey.bone.scale_y
				boneRef.angle = boneRef.cycKey.bone.angle
				boneRef.x = boneRef.cycKey.bone.x
				boneRef.y = boneRef.cycKey.bone.y
			end
			for objectRefIndex = 1, # key.object_ref do
				local objectRef = key.object_ref[objectRefIndex]
				assert(objectRef, "Key " .. tostring(keyIndex) .. " objectRef " .. tostring(objectRefIndex) .. " has no objectref")
				objectRef.cycKey = self:getTimelineKeyById( i, objectRef.timeline, objectRef.key  )
				assert(objectRef.cycKey, "objectRef " .. tostring(objectRefIndex) .. " has no key")
				--Copy values so we don't have to dig into the key during animation
				objectRef.scale_x = objectRef.cycKey.object.scale_x
				objectRef.scale_y = objectRef.cycKey.object.scale_y
				objectRef.x = objectRef.cycKey.object.x
				objectRef.y = objectRef.cycKey.object.y
				objectRef.angle = objectRef.cycKey.object.angle
			end
		end
	end
end --updateTimelineReferences

--Map parent references to actual data structure references 
--Note: according to Spriter forum, ALL parent references are indices into object_ref
--Huzzah for documentation!
function Spriter:updateParentReferences()
	--I believe that the only parent references are in the mainlines of the animations to bone_ref objects
	--NOTE: hard-coding for 1 entity
	for i = 1, # self.entity[1].animation do
		local animation = self.entity[1].animation[i]
		assert(animation, "nil animation on index " .. i)
		local mainline = animation.mainline
		assert(animation.mainline, "nil mainline on animation " .. i)
		for keyIndex = 1, # mainline.key do
			local key = mainline.key[keyIndex]
			assert(key, "Key " .. tostring(keyIndex) .. " not found")
			for boneRefIndex = 1, # key.bone_ref do
				local boneRef = key.bone_ref[boneRefIndex]
				assert(boneRef, "Key " .. tostring(keyIndex) .. " boneRef " .. tostring(boneRefIndex) .. " has no boneref")
				if boneRef.parent then
					boneRef.cycParentBoneRef = self:getBoneRefById( i, keyIndex, boneRef.parent )
				end
			end
			for objectRefIndex = 1, # key.object_ref do
				local objectRef = key.object_ref[objectRefIndex]
				assert(objectRef, "Key " .. tostring(keyIndex) .. " objectRef " .. tostring(objectRefIndex) .. " has no objectref")
				if objectRef.parent then
					objectRef.cycParentBoneRef = self:getBoneRefById( i, keyIndex, objectRef.parent )
				end
			end
		end
	end
end --updateParentReferences

--Map file id references to data structure references for the actual file data
--I made this recursive to match all possible cases, but in retrospect, it looks like only timeline keys have images.
function Spriter:updateFileReferences( node )
	node = node or self

	if node.file and node.folder then
		node.cycFile = self:getFileById( node.folder, node.file )
	end

	for k, v in pairs( node ) do
		if type(v) == "table" then
			self:updateFileReferences( v )
		end
	end
end --updateFileReferences


--Get folder by index.  Die if invalid folder index
--I am assuming that the folder index in the lua array *should* be the same as its id
--Note:  **I make this assumption globally throughout this parser**
function Spriter:getFolderByIndex( index )
	local folder = self.folder[index]
	assert(folder)
	return folder
end


--Read the name of the function.  This and then next several "get" methods basically dig 
--Through the data structure for what you're looking for and die if they can't find it
function Spriter:getTimelineById( animationID, timelineID )
	assert(animationID, "animationID has no value")
	assert(timelineID, "timelineID has no value")

	--NOTE: hard-coding for 1 entity
	local animation = self.entity[1].animation[animationID]
	assert(animation, "Animation " .. tostring(animationID) .. " not found")
	local timeline = animation.timeline[timelineID]
	assert(timeline, "Timeline " .. tostring(timelineID) .. " not found")

	return timeline
end

--See comments above
function Spriter:getTimelineKeyById( animationID, timelineID, keyID )
	assert(animationID, "animationID has no value")
	assert(timelineID, "timelineID has no value")

	--NOTE: hard-coding for 1 entity
	local animation = self.entity[1].animation[animationID]
	assert(animation, "Animation " .. tostring(animationID) .. " not found")
	local timeline = animation.timeline[timelineID]
	assert(timeline, "Timeline " .. tostring(timelineID) .. " not found")
	local key = timeline.key[keyID]
	assert(key, "Key " .. tostring(keyID) .. " not found")

	return key, timeline.name
end

--The timelines refer to bones by name, which doesn't quite match the paradigm of id/index, so
--We provide this helper function to grab bones by name
function Spriter:getBoneByName( boneName )
	local obj_info = self.entity[1].obj_info
	for i = 1, # obj_info do
		if obj_info[i].type == "bone" and obj_info[i].name == boneName then
			return obj_info[i]
		end
	end
	assert(false, "Bone '" .. tostring(boneName) .. "' not found")
end

--See comments above
function Spriter:getBoneRefById( animationID, keyID, boneRefID )
	assert(animationID, "animationID has no value")
	assert(keyID, "animationID has no value")
	assert(boneRefID, "boneRefID has no value")

	--NOTE: hard-coding for 1 entity
	local animation = self.entity[1].animation[animationID]
	assert(animation, "Animation " .. tostring(animationID) .. " not found")
	local mainline = animation.mainline;
	assert(mainline, "Mainline not found")
	local key = mainline.key[keyID];
	assert(key, "Key " .. tostring(keyID) .. " not found")
	local boneRef = key.bone_ref[boneRefID]

	return boneRef
end


--See comments above
function Spriter:getFileById( folderID, fileID )

	local folder = self.folder[folderID]
	assert(folder, "Folder " .. tostring(folderID) .. " not found")
	local file = folder.file[fileID]
	assert(file, "File " .. tostring(fileID) .. " not found")

	return file
end

--The actual user code will most likely (sanely) use animation names rather than indices into the array
--This method is for them
function Spriter:getAnimationByName( animationName )
	for i = 1, # self.entity[1].animation do
		local animation = self.entity[1].animation[i]
		if animation.name == animationName then
			return animation
		end
	end
	
	assert(false, "Unable to find animation '" .. tostring(animationName) .. "'")
end --animationName

--Apply all timeline transformations to heirarchy - no need to compute every frame
--NOTE:  this method is deprecated.  My previous approach was incorrect.  I'm leaving this here temporarily in case I need to reference it
function Spriter:applyTransformations()
	for animationIndex = 1, # self.entity[1].animation do
		local animation = self.entity[1].animation[animationIndex]
		assert(animation, "Animation " .. tostring(animationIndex) .. " not found")

		local timeline = animation.timeline
		assert(timeline, "Animation timeline " .. tostring(animationName) .. " not found")
		local mainline = animation.mainline
		assert(mainline, "Animation mainline " .. tostring(animationName) .. " not found")
		for keyIndex = 1, # mainline.key do
			local key = mainline.key[keyIndex]
			assert(key, "Animation key[1] " .. tostring(keyIndex) .. " not found")

			--Apply all transformations through bone_ref heirarchy
			for boneRefIndex = 1, # key.bone_ref do
				local boneRef = key.bone_ref[boneRefIndex]

				--Create "blank" transformations to avoid Lua complaining about adding etc. nil values
				boneRef.x = boneRef.x or 0
				boneRef.y = boneRef.y or 0
				boneRef.angle = boneRef.angle or 0
				boneRef.scale_x = boneRef.scale_x or 1
				boneRef.scale_y = boneRef.scale_y or 1
				local parent = boneRef.cycParentBoneRef
				if parent then
					--Multiply our scale by parent's scale
					boneRef.scale_x = boneRef.scale_x * parent.scale_x
					boneRef.scale_y = boneRef.scale_y * parent.scale_y

					--Add our rotation to parent's rotation
					boneRef.angle = boneRef.angle + parent.angle

					--Our position gets multiplied by *parent* scale
					boneRef.x = boneRef.x * parent.scale_x
					boneRef.y = boneRef.y * parent.scale_y

					--Translate our x, y by parent's translation
					boneRef.x = boneRef.x + parent.x
					boneRef.y = boneRef.y + parent.y 

					--Now rotate our x, y by our parents rotation *around its x,y*
					boneRef.x, boneRef.y = self:rotatePoint( boneRef.x, boneRef.y, parent.angle, parent.x, parent.y )
				else
					--We still need scale unparented objects 
					boneRef.x = boneRef.x * boneRef.scale_x
					boneRef.y = boneRef.y * boneRef.scale_y
				end
			end --for through bone_ref
			--Apply all transformations through object_ref heirarchy
			for objectRefIndex = 1, # key.object_ref do
				local objectRef = key.object_ref[objectRefIndex]
				--Create "blank" transformations to avoid Lua complaining about adding etc. nil values
				objectRef.x = objectRef.x or 0
				objectRef.y = objectRef.y or 0
				objectRef.angle = objectRef.angle or 0
				objectRef.scale_x = objectRef.scale_x or 1
				objectRef.scale_y = objectRef.scale_y or 1
				local parent = objectRef.cycParentBoneRef
				if parent then
					local filename = objectRef.cycKey.object.cycFile.name

					--Multiply our scale by parent's scale
					objectRef.scale_x = objectRef.scale_x * parent.scale_x
					objectRef.scale_y = objectRef.scale_y * parent.scale_y
					--Add our rotation to parent's rotation
					objectRef.angle = objectRef.angle + parent.angle

					--Our position gets multiplied by *parent* scale
					objectRef.x = objectRef.x * parent.scale_x
					objectRef.y = objectRef.y * parent.scale_y

					--Translate our x, y by parent's translation
					objectRef.x = objectRef.x + parent.x
					objectRef.y = objectRef.y + parent.y 

					--Now rotate our x, y by our parents rotation *around its x,y*
					objectRef.x, objectRef.y = self:rotatePoint( objectRef.x, objectRef.y, parent.angle, parent.x, parent.y )
				else
					--We still need scale unparented objects 
					objectRef.x = objectRef.x * objectRef.scale_x
					objectRef.y = objectRef.y * objectRef.scale_y
				end
			end --for through object_ref
		end --for through mainline keys
	end --for through animatins

end

--Helper function: rotate point px, py around center cx,cy.  If cx, cy not passed, rotate around origin
--FUNCTION EXPECTS RADIANS
function Spriter:rotatePoint( px, py, angle, cx, cy )
	cx = cx or 0
	cy = cy or 0

	local s = math.sin(angle)
	local c = math.cos(angle)

	px = px - cx;
	py = py - cy;

	local xnew = (px * c) - (py * s)
	local ynew = (px * s) + (py * c)

	--translate point back:
	px = xnew + cx;
	py = ynew + cy;

	--To avoid crazy scientific notation prints during debugging
	local function round(num, idp)
		local mult = 10^(idp or 2)
		return math.floor(num * mult + 0.5) / mult
	end
	px = round(px,5)
	py = round(py,5)

	return px, py
end --rotatePoint

--For debugging - distance between two points
function Spriter:pointDistance( x1, y1, x2, y2 )
	local xd = x2-x1
	local yd = y2-y1
	local distance = math.sqrt(xd*xd + yd*yd)
	return distance
end


--Set the animation referenced by animationName as the current animation
--Die is animationName is not a valid animation.  
function Spriter:setCurrentAnimationName( animationName, animationType, inTransition )

	--Unless this animation change was initiated by a transition, override any existing transitions
	if not self.inTransition then
		self.transitions = {}
	end
	self:setTime( 0 )
	self.looped = nil
	--Used for emitting key changes
	self.currentKeyIndex = nil

	self.stopped = nil
	self.animationType = animationType or "looping"
	local animation = self:getAnimationByName( animationName )
	assert(animation, "Animation " .. tostring(animationName) .. " not found")
	self.animationName = animationName
end
function Spriter:getCurrentAnimationName()
	return self.animationName 
end

function Spriter:setInterpolation( interpolation )
	self.interpolation = interpolation
end
function Spriter:getInterpolation()
	return self.interpolation
end

function Spriter:start()
	self.stopped = nil
end

function Spriter:stop()
	self.stopped = true
end

--Get a reference to the current animation
function Spriter:getCurrentAnimation()
	local animationName = self.animationName
	assert(animationName, "nil animationName")

	local animation = self:getAnimationByName( animationName )
	assert(animation, "Animation " .. tostring(animationName) .. " not found")
	return animation
end

--Get a reference to the current mainline key, chosed based on dt updates and current animation value
function Spriter:getCurrentMainlineKey()
	local animation = self:getCurrentAnimation()
	local time = self:getTime()
	local milliseconds = time * 1000

	local mainline = animation.mainline
	assert(mainline, "Animation mainline not found")

	local currentKey = mainline.key[1]
	local currentKeyIndex = 1


	for keyIndex = 1, # mainline.key do
		local key = mainline.key[keyIndex]
		if key.time then
			if milliseconds > key.time then
				currentKey = key
				currentKeyIndex = keyIndex
			end
		end
	end

	if not self.currentKeyIndex or currentKeyIndex ~= self.currentKeyIndex then
		self.currentKeyIndex = currentKeyIndex
		self:keyChanged( currentKeyIndex )
	end

	return currentKey, currentKeyIndex
end

--Rescale time elapsed vs duration to min1, max1 (x, y angle, or whatever)
local function rescale( val, min0, max0, min1, max1 )
	return (((val - min0) / (max0 - min0)) * (max1 - min1)) + min1
end

--Given a bone at position x,y pointing at angle angle with length length, return the x, y of the other end of the bone
function Spriter:getBoneEndpoint( x, y, angle, length )
	local x2, y2 = x, y
	--By convention, bone is a ray of length cycBone.w pointed in direction boneRef.angle
	local length = length
	--Rotate a ray centered at origin on the x axies to be a ray that points at the specified angle
	local x2, y2 = self:rotatePoint( length, 0, angle, 0, 0 )

	--Translate this ray by the bone position
	x2 = x2 + x
	y2 = y2 + y

	return x2, y2
end --getBoneEndpoint

--Special interpolation function for angles.  Need to be smart enough to "loop" around the 0 degree mark to
--Find nearby angles rather than take the long way around.  i.e. rotating from 10 degrees to 350 degrees should
--Go DOWN from 10 to 0, then down 360 to 350.  NOT a linear interpolation from 10 and increasing to 350
--Based on http://stackoverflow.com/questions/2708476/rotation-interpolation
local function lerpAngle( a1, a2, amount )
	local radians360 = 6.28318531	
	local radians180 = 3.14159265
	local degree = 0.0174532925

	local difference = math.abs(a2 - a1);
	if difference > radians180 then
		-- We need to add on to one of the values.
		if a2 > a1 then
			--We'll add it on to start...
			a1 = a1 + radians360
		else
			--Add it on to end.
			a2 = a2 + radians360;
		end
	end

	--Interpolate it.
	local value = (a1 + ((a2 - a1) * amount));

	--Wrap it..
	local rangeZero = radians360

	if value >= 0 and value <= radians360 then
		return value
	end

	return value % rangeZero
end --lerpAngle


--object_ref indices are not necessarily consistent among keyframes.  Nor are the images that the "actual"
--object references (they can be swapped out).  The only reliable way I was able to see if two object refs on
--Separate keyframes were the same "object" was to compare the timeline value.  id is just its position in the array, so it's useless
local function getNextObjectRef( objectRef, objectRefIndex, nextKey )
	if nextKey.object_ref[objectRefIndex] then
		if objectRef.timeline == nextKey.object_ref[objectRefIndex].timeline then
			return nextKey.object_ref[objectRefIndex]
		end
		
	end
	for i = 1, #nextKey.object_ref do
		if objectRef.timeline == nextKey.object_ref[i].timeline then
			return nextKey.object_ref[i]
		end
	end

	return nil
end --getNextObjectRef


--Build one frame of data that is the current "state" of the rig, with interpolation behaviors
--Defined for the next timeline key
function Spriter:buildFrameData()
	local animation = self:getCurrentAnimation()

	local timeline = animation.timeline
	assert(timeline, "Animation timeline " .. tostring(animationName) .. " not found")
	local mainline = animation.mainline
	assert(mainline, "Animation mainline " .. tostring(animationName) .. " not found")
	local key, keyIndex = self:getCurrentMainlineKey()
	assert(key, "Animation key[1] " .. tostring(animationName) .. " not found")
	--Alias time because we (stupidly) override the key reference with a local below
	local currentKeyTime = key.time
	local nextKey = key.cycNextKey
	assert(nextKey, "Unable to load nextKey")

	local frameData = {}

	--Loop for bone ref frames (images)
	for boneRefIndex = 1, # key.bone_ref do
		local boneRef = key.bone_ref[boneRefIndex]
		local key = boneRef.cycKey


		local boneData = {
			dataType = "bone",
			x = boneRef.x or 0,
			y = boneRef.y or 0,
			boneLength = boneRef.cycBone.w or 0,
			scale_x = boneRef.scale_x or 1,
			scale_y = boneRef.scale_y or 1,
			angle = boneRef.angle or 0,
		}

		--Note -- we are not creating a frame if the bone_ref on the next key is null.  This might be premature?
		--Should we create a "static" frame?
		if nextKey.bone_ref[boneRefIndex] then
			local xNext = nextKey.bone_ref[boneRefIndex].x or 0
			local yNext = nextKey.bone_ref[boneRefIndex].y or 0
			local angleNext = nextKey.bone_ref[boneRefIndex].angle or 0
			local currentSpin = boneRef.cycKey.spin
			if not currentSpin then currentSpin = 0 end 

			assert(xNext and yNext and angleNext, "nil next key value")

			local angle1, angle2 = boneData.angle, angleNext

			local nextTime = nextKey.time

			local duration
			if currentKeyTime and nextTime then
				--If both keys have time, duration is distance between keys
				duration = nextTime - currentKeyTime
			elseif not currentKeyTime and nextTime then
				--If current key does not have a time, it's first, duration is next key's time
				duration = nextTime
			elseif currentKeyTime and not nextTime then
				--If next key does not have a time, we're looping.  Duration is total anim length minus current key's start time
				duration = animation.length - currentKeyTime 
			else
				print(tostring(currentKeyTime) .. ", " .. tostring(nextTime))
				assert(false, "Neither key has a time.  This should not happen")
			end
			assert(duration, "Invalid duration value")

			--Key time is milliseconds, interpolation expects seconds
			duration = duration / 1000
		
			boneData.angleStart = boneData.angle
			boneData.xStart = boneData.x
			boneData.yStart = boneData.y
			boneData.xNext = xNext
			boneData.yNext = yNext
			boneData.angleNext = angleNext
			boneData.duration = duration

			local elapsed = self:getTime()
			if currentKeyTime then
				elapsed = elapsed - (currentKeyTime/1000)
			end

			boneData.x = rescale( elapsed, 0, boneData.duration, boneData.xStart, boneData.xNext ) 
			boneData.y = rescale( elapsed, 0, boneData.duration, boneData.yStart, boneData.yNext ) 
			local angleAmount = rescale( elapsed, 0, boneData.duration, 0, 1 )
			boneData.angle = lerpAngle( boneData.angleStart, boneData.angleNext, angleAmount ) 


			--Interpolation behavior
			--[[
			local that = self
			boneData.update = function(self, dt) 
				self.elapsed = self.elapsed + dt
				self.x = rescale( self.elapsed, 0, self.duration, self.xStart, self.xNext ) 
				self.y = rescale( self.elapsed, 0, self.duration, self.yStart, self.yNext ) 
				local angleAmount = rescale( self.elapsed, 0, self.duration, 0, 1 )
				self.angle = lerpAngle( self.angleStart, self.angleNext, angleAmount ) 
				local x2, y2 = that:getBoneEndpoint( self.x, self.y, self.angle, self.scale_x * self.boneLength, self.angle )
				self.x2 = x2
				self.y2 = y2
			end
			--]]

		end --if next one has data
		frameData[ # frameData + 1 ] = boneData




		local parent = frameData[ boneRef.parent ]
		if parent then
			--Multiply our scale by parent's scale
			boneData.scale_x = boneData.scale_x * parent.scale_x
			boneData.scale_y = boneData.scale_y * parent.scale_y

			--Add our rotation to parent's rotation
			boneData.angle = boneData.angle + parent.angle

			--Our position gets multiplied by *parent* scale
			boneData.x = boneData.x * parent.scale_x
			boneData.y = boneData.y * parent.scale_y

			--Translate our x, y by parent's translation
			boneData.x = boneData.x + parent.x
			boneData.y = boneData.y + parent.y 

			--Now rotate our x, y by our parents rotation *around its x,y*
			boneData.x, boneData.y = self:rotatePoint( boneData.x, boneData.y, parent.angle, parent.x, parent.y )
		else
			--We still need scale unparented objects 
			boneData.x = boneData.x * boneData.scale_x
			boneData.y = boneData.y * boneData.scale_y
		end

		local x2, y2 = self:getBoneEndpoint( boneData.x, boneData.y, boneData.angle, boneData.scale_x * boneData.boneLength, boneData.angle )
		boneData.x2 = x2
		boneData.y2 = y2

	end --for















	--Loop for object ref frames (images)
	for objectRefIndex = 1, # key.object_ref do
		local objectRef = key.object_ref[objectRefIndex]
		local key = objectRef.cycKey
		local object = key.object
		local file = object.cycFile
		local image = file.image --Love2D image handle

		--Optionally, images can pivot rotations from a non-standard point (default is bottom right corner {top right in Love coords})
		local pivotX, pivotY
		if object.pivot_x then
			pivotX = object.pivot_x
		else
			pivotX = file.pivot_x
		end
		if object.pivot_y then
			pivotY = object.pivot_y
		else
			pivotY = file.pivot_y
		end

		local imageData = {
			dataType = "image",
			image = image,
			x = objectRef.x or 0,
			y = objectRef.y or 0,
			pivotX = pivotX,
			pivotY = pivotY,
			scale_x = objectRef.scale_x or 1,
			scale_y = objectRef.scale_y or 1,
			angle = objectRef.angle or 0,
		}

		local parent = frameData[ objectRef.parent ]
		if parent then
			local filename = objectRef.cycKey.object.cycFile.name

			--Multiply our scale by parent's scale
			imageData.scale_x = imageData.scale_x * parent.scale_x
			imageData.scale_y = imageData.scale_y * parent.scale_y
			--Add our rotation to parent's rotation
			imageData.angle = imageData.angle + parent.angle

			--Our position gets multiplied by *parent* scale
			imageData.x = imageData.x * parent.scale_x
			imageData.y = imageData.y * parent.scale_y

			--Translate our x, y by parent's translation
			imageData.x = imageData.x + parent.x
			imageData.y = imageData.y + parent.y 

			--Now rotate our x, y by our parents rotation *around its x,y*
			imageData.x, imageData.y = self:rotatePoint( imageData.x, imageData.y, parent.angle, parent.x, parent.y )
		else
			--We still need scale unparented objects 
			imageData.x = imageData.x * imageData.scale_x
			imageData.y = imageData.y * imageData.scale_y
		end

		

		local nextObjectRef = getNextObjectRef( objectRef, objectRefIndex, nextKey )
		--If there is no keyframe for us in the next key, do no interpolation
		if not nextObjectRef then
			nextObjectRef = {
				x = objectRef.x,
				y = objectRef.y,
				angle = objectRef.angle,
			}
		else
			--print(objectRef.timeline .. " - " .. nextObjectRef.timeline)
		end


		--Note -- we are not creating a frame if the object_ref on the next key is null.  This might be premature?
		--Should we create a "static" frame?
		local xNext = nextObjectRef.x or 0
		local yNext = nextObjectRef.y or 0
		local angleNext = nextObjectRef.angle or 0
		local currentSpin = objectRef.cycKey.spin
		if not currentSpin then currentSpin = 0 end 

		assert(xNext and yNext and angleNext, "nil next key value")

		local angle1, angle2 = imageData.angle, angleNext

		local nextTime = nextKey.time

		local duration
		if currentKeyTime and nextTime then
			--If both keys have time, duration is distance between keys
			duration = nextTime - currentKeyTime
		elseif not currentKeyTime and nextTime then
			--If current key does not have a time, it's first, duration is next key's time
			duration = nextTime
		elseif currentKeyTime and not nextTime then
			--If next key does not have a time, we're looping.  Duration is total anim length minus current key's start time
			duration = animation.length - currentKeyTime 
		else
			print(tostring(currentKeyTime) .. ", " .. tostring(nextTime))
			assert(false, "Neither key has a time.  This should not happen")
		end
		assert(duration, "Invalid duration value")

		--Key time is milliseconds, interpolation expects seconds
		duration = duration / 1000
	
		imageData.angleStart = imageData.angle
		imageData.xStart = imageData.x
		imageData.yStart = imageData.y
		imageData.xNext = xNext
		imageData.yNext = yNext
		imageData.angleNext = angleNext
		imageData.elapsed = 0
		imageData.duration = duration

		--Interpolation behavior
		--[[
		imageData.update = function(self, dt) 
			self.elapsed = self.elapsed + dt
			self.x = rescale( self.elapsed, 0, self.duration, self.xStart, self.xNext ) 
			self.y = rescale( self.elapsed, 0, self.duration, self.yStart, self.yNext ) 
			local angleAmount = rescale( self.elapsed, 0, self.duration, 0, 1 )
			self.angle = lerpAngle( self.angleStart, self.angleNext, angleAmount ) 
		end
		--]]

		frameData[ # frameData + 1 ] = imageData

	end --for

	return frameData
end --buildFrameData

--Get current frame data, or build it if it does not exist
function Spriter:getFrameData()
	if self.stopped and self.lastFrameData then
		return self.lastFrameData
	end

	local animation = self:getCurrentAnimation()

	local timeline = animation.timeline
	assert(timeline, "Animation timeline " .. tostring(animationName) .. " not found")
	local mainline = animation.mainline
	assert(mainline, "Animation mainline " .. tostring(animationName) .. " not found")
	local key = self:getCurrentMainlineKey()
	assert(key, "Animation key[1] " .. tostring(animationName) .. " not found")

	local frameData = self.currentFrameData
	--[[
	--Rebuild frameData when our mainline key changes, or when one does not exist
	if not self.currentFrameData or (self.currentMainlineKey and self.currentMainlineKey ~= key) then
		frameData = self:buildFrameData()	
		self.currentMainlineKey = key
		self.currentFrameData = frameData
	end
	--]]
	frameData = self:buildFrameData()	
	
	self.lastFrameData = frameData
	return frameData
end --getFrameData

function Spriter:getTime()
	if not self.time then
		self.time = 0
	end
	return self.time
end

function Spriter:setTime( time )
	self.time = time
end


--Push a transition onto the stack (first in, first out)
--Transitions are animations that we wish to switch to after the current animation finishes
function Spriter:pushTransition( transition )
	self.transitions[ # self.transitions + 1 ] = transition
end

function Spriter:updateTransition()
	if # self.transitions > 0 then
		local transition = self.transitions[1]
		--Transitions can allow a certain number of loops before switching
		if transition.loopCount and transition.loopCount > 0 then
			transition.loopCount = transition.loopCount - 1
		else
			table.remove( self.transitions, 1 )
			local animationType = "loop"
			local inTransition = true
			self:setCurrentAnimationName( transition.animationName, animationType, inTransition )
		end
	end
end

--Do nothing by default - intended for "inheriting" class to react
function Spriter:animationLooped()
	self:updateTransition()
end

--Do nothing by default - intended for "inheriting" class to react
function Spriter:animationStopped()
	self:updateTransition()
end

--Do nothing by default - intended for "inheriting" class to react
function Spriter:animationStarted()

end

--Do nothing by default - intended for "inheriting" class to react
function Spriter:keyChanged( keyIndex )

end

--Add delta time to the current time tracking.  Figure out if our animation stopped or looped and notify listeners
function Spriter:incrementTime( dt )
	local time = self:getTime()

	if time == 0 then
		self:animationStarted()
	elseif self.looped then
		self.looped = nil
		self:animationStarted()
	end

	time = time + dt

	local animation = self:getCurrentAnimation()
	local animationName = self:getCurrentAnimationName()

	local milliseconds = time * 1000

	if milliseconds > animation.length then
		local remainder = milliseconds % animation.length 
		time = remainder / 1000
                --Force a rebuild of frame data - avoid "infinite interpolation bug"
		self.currentFrameData = nil
		if self.animationType == "looping" then
			self:animationLooped()
			--Let ourselves know on next update that we looped for animationStarted signal
			self.looped = true
		elseif self.animationType == "once" then
			self.stopped = true
			self:animationStopped()
		end
	end

	--This is kind of a hack...it is possible the above events resulted in an animation switch,
	--If so, emit the animationStarted signal (won't trigger by above code block)
	--Thinking this may need to go in setCurrentAnimationName
	if animationName ~= self:getCurrentAnimationName() then
		self:animationStarted()
	end

	self:setTime( time )
end

--Called once per Love2D "tick."  dt is a delta of time elapsed since last update call.  dt is a float - Number of seconds elapsed
function Spriter:update( dt )
	--Allow user to "freeze" animation
	if self.stopped then
		return
	end

	--[[
	--Can turn interpolation on and off for debug (or other nefarious) purposes
	if self:getInterpolation() then
		local frameDatas = self:getFrameData()
		for i = 1, #frameDatas do
			local frameData = frameDatas[i]
			if frameData.update then
				frameData:update( dt )
			end
		end
	end
	--]]

	self:incrementTime( dt )
end --getFrameData

--Get list of animation names we can use with setCurrentAnimationName
function Spriter:getAnimationNames()
	local animationNames = {}

	for i = 1, # self.entity[1].animation do
		local animation = self.entity[1].animation[i]
		animationNames[ # animationNames + 1 ] = animation.name
	end
	return animationNames
end

--Load a spriter file and return an object that can be used to animate and render this data
--NOTE:  the object returned has Spriter set as a metatable reference, so the spriterData returned
--Essentially "inherits" all of the methods in Spriter
--All of the "self" references used in the above Spriter methods are expected to be referring to a valid spriterData
--Object loaded from a .scon file
function Spriter:loadSpriter( path, directory )

	--All spriter assets are expected to be relative to path/directory
	self.path = path .. "/" .. directory

	--By convention, we will assume filename is animationDirectory/animationDirectory.scon
	local filename = path .. "/" .. directory .. "/" .. directory .. ".scon"	
	assert(love.filesystem.isFile( filename ), "File " .. filename .. " not found")

	--Load file contents into string
	local contents, size = love.filesystem.read( filename )
	assert(size, "Error loading file")

	--.scon file is json, parse the json into a Lua data structure
	local spriterData, pos, err = json.decode (contents, 1, nil)
	assert( not err, "Parse error!")

	--Quasi "inheritance" of Spriter "class" so spriterData can call methods on itself
	setmetatable(spriterData, {__index = function (table, key) return Spriter[key] end } )

	--Boolean for debugging switch on/off of interpolation
	spriterData.interpolation = true

	--Array of animation transitions -- see usage above
	spriterData.transitions = {}

	--Change 0-index id, parent etc. references to 1-indexed for Lua
	spriterData:updateIds( spriterData )

	--Spriter stores angles as degrees, convert to radians
	spriterData:anglesToRadians( spriterData )

	--Use Love functions to load image references, store handle to loaded graphic in folder/file structure of spriterData
	spriterData:loadFilesAndFolders()
	--Update all objects in spriterData that contain folder/file IDs to reference the actual data in the spriterData object
	spriterData:updateFileReferences()
	--Create ->next references in mainline keys so we can easily access the next key from the data structure 
	spriterData:createKeyReferences()
	--Update all objects in spriterData that contain timeline IDs to reference the actual data in the spriterData object
	spriterData:updateTimelineReferences()
	--Update all objects in spriterData that parent IDs to reference the actual data in the spriterData object
	spriterData:updateParentReferences()
	--NOTE:  this method is deprecated.  My previous approach was incorrect.  I'm leaving this here temporarily in case I need to reference it
--	spriterData:applyTransformations()


	return spriterData
end --loadSpriter

--[[
usage:
local Spriter = require("libs/Spriter")
--Animation filename assumed to be animationDirectory/animationDirectory.scon
local spriterData = Spriter:loadSpriter("./", "animationDirectory")
--]]
return Spriter
