--[[
Note:  most of the "meat" of the loading, transformations, interpolation etc. is going on is in libs/Spriter.lua


Copyright (c) 2014, Hardcrawler Games LLC

This library is free software; you can redistribute it and/or modify it
under the terms of the MIT license. See LICENSE for details.

I haven't actually read the MIT license.  I think it's permissive and stuff.  Send me a keg of Newcastle beer if this makes you rich.
--]]

local Spriter = require("libs/Spriter")

local spriterDatas = {}
local spriterDataIndex = 1
local spriterData

local directories = {"GreyGuy"}

local screenWidth = 800
local screenHeight = 600

local fullscreen = false
local inverted = false
local debug = false
local currentAnimation = 1
local interpolation = true 
--For off-screen rendering and flipping (see below
local canvas

function love.keypressed(key)

	--Flip animation
        if key == "i" then
		inverted = not inverted
	end

	--Toggle bones
        if key == "b" then
		debug = not debug
	end

	--Load next spriter file loaded from directories array above
        if key == "l" then
		spriterDataIndex = spriterDataIndex + 1
		if spriterDataIndex > # spriterDatas then
			spriterDataIndex = 1
		end
		spriterData = spriterDatas[ spriterDataIndex ] 
		local animationNames = spriterData:getAnimationNames()
		currentAnimation = 1
		spriterData:setCurrentAnimationName( animationNames[1] )
	end

	--Next animation of current spriterData render
        if key == "n" then
		local animationNames = spriterData:getAnimationNames()
		currentAnimation = currentAnimation + 1
		if currentAnimation > # animationNames then
			currentAnimation = 1
		end
		--Set the first animation found as the active animation
		spriterData:setCurrentAnimationName( animationNames[currentAnimation] )
	end

	--Toggle interpolation
	if key == "p" then
		interpolation = not interpolation
		if interpolation then
			spriterData:setInterpolation( false )
		else
			spriterData:setInterpolation( true )
		end
	end

	--Toggle Fullscreen
        if key == "f" then
                local width, height, flags = love.window.getMode( )
                if fullscreen then
                        love.window.setMode( width, height, {fullscreen=false} )
                        fullscreen = false
                else
                        love.window.setMode( width, height, {fullscreen=true} )
                        fullscreen = true
                end
        end
end

--Called once when program is first loaded
function love.load()
	love.window.setMode( screenWidth, screenHeight )

	--I am using canvases to support flipping spriter animations after rendering regularly.
	--A more fancy-pants approach could be used to render the animations backwards, but this was easier
	--If your video card doesn't support canvases and non-power-of-two canvases, this won't work.
	assert(love.graphics.isSupported("canvas"), "This graphics card does not support canvases.")
	assert(love.graphics.isSupported("npot"), "This graphics card does not support non power-of-two canvases.") 

	 canvas = love.graphics.newCanvas(screenWidth, screenHeight)

	--Load spriterData for all directories specified above
	for i = 1, # directories do
		local directory = directories[i]
		spriterData = Spriter:loadSpriter( "", directory )
		assert(spriterData, "nil spriterData")

		local animationNames = spriterData:getAnimationNames()
		--Set the first animation found as the active animation
		spriterData:setCurrentAnimationName( animationNames[1] )
		spriterDatas[ # spriterDatas + 1 ] = spriterData
	end
	spriterData = spriterDatas[ spriterDataIndex ]
end


--Convert spriter coordinates to Love-style coordinates.  
--0,0 is center of screen positive y moves up from center of screen
local function spriterToScreen( x, y )
	local centerx = love.graphics:getWidth() / 2
	local centery = love.graphics:getHeight() / 2

	x = centerx + x
	y = centery - y

	return x, y
end

--Called once per game "tick" with number of seconds elapsed since last game tick -- generally a floating point like .02114321 or something
function love.update( dt )
	--spriterData must be called with dt (delta time) as floating point seconds -- NOT MILLISECONDS -- for animation to update
	spriterData:update( dt )
end


--Debugging function - draw bones.  NOTE:  bones currently not interpolated
local function drawDebugInfo()
	local frameData = spriterData:getFrameData()

	local currentColor = 1
	local colors = {
		{r=255,g=0,b=0},
		{r=0,g=255,b=0},
		{r=0,g=0,b=255},
		{r=255,g=255,b=0},
	}

	local testImage 
	--This loop is to draw the corners of the image for image rotation debugging
	--It is very noisy and spewy, so I only turn it on when I need to debug 
	--[[
	for i = 1, # frameData do
		local imageData = frameData[i]
		if imageData.dataType == "image" then
			local x, y = spriterToScreen( imageData.x, imageData.y ) 

			local corners = {
				{x=x, y=y},
				{x=x+imageData.image:getWidth(), y=y},
				{x=x+imageData.image:getWidth(), y=y+imageData.image:getHeight()},
				{x=x, y=y+imageData.image:getHeight()},
			}
			local pivotx = corners[1].x
			local pivoty = corners[1].y

			for cornerIndex = 1, # corners do
				local x, y = corners[cornerIndex].x, corners[cornerIndex].y
				local tlx, tly = Spriter:rotatePoint( x, y, -imageData.angle, pivotx, pivoty )

				love.graphics.setColor(colors[currentColor].r, colors[currentColor].g, colors[currentColor].b)
				currentColor = currentColor + 1
				if currentColor > # colors then
					currentColor = 1
				end
				love.graphics.circle( "fill", tlx, tly, 3, 100 )
			end
			love.graphics.setColor(255, 255, 255)
			love.graphics.setColor(255, 255, 255)
		end
	end
	--]]

	--Bone render for debugging
	currentColor = 1
	for i = 1, # frameData do
		local data = frameData[i]
		if data.dataType == "bone" then
			local r = colors[currentColor].r
			local g = colors[currentColor].g
			local b = colors[currentColor].b
			currentColor = currentColor + 1
			if currentColor > # colors then
				currentColor = 1
			end

			love.graphics.setColor(r, g, b)
			local startx, starty = spriterToScreen( data.x, data.y )
			local x2, y2 = spriterToScreen( data.x2, data.y2 )

			love.graphics.circle( "fill", x2, y2, 3, 100 )
			love.graphics.line(startx,starty, x2,y2)
			love.graphics.setColor(255, 255, 255)
			love.graphics.circle( "fill", startx, starty, 5, 100 )
		end
	end
end --drawDebugInfo


--General purpose rescale function.  It should be built into every language.  I should get this tattood on my arm.
--I have been copy/pasting this function from the Cylindrix C source for almost 20 years.
local function rescale( val, min0, max0, min1, max1 )
	return (((val - min0) / (max0 - min0)) * (max1 - min1)) + min1
end


--Called once per "tick" after update
function love.draw()
	local frameData = spriterData:getFrameData()

	--Draw onto off-screen canvas for flipping
	--I'm sure there's an algorithmic solution to flipping the animation, but
	--This was easier to me initially
	--I'm not sure how to cleanly build a bounding rect to create a good canvas size, so I'm just doing screen w/h for now
	--All graphics operations from this point forward render to canvas instead of screen
	love.graphics.setCanvas(canvas)
	--Duh
	canvas:clear()
	--I believe this is the default, but whatever.
	love.graphics.setBlendMode('alpha')

	--Loop through framedata and render images (bones are also in array)
	for i = 1, # frameData do
		local imageData = frameData[i]
		if imageData.dataType == "image" then
			local x, y = spriterToScreen( imageData.x, imageData.y ) 

			love.graphics.setColor(255, 255, 255)
			--Not 100% sure why I have to flip angle here...From what I can tell, bones rotate counter-clockwise like Love and everything else expects.
			--print("Drawing scale: " .. imageData.scale_x .. ", " .. imageData.scale_y )
			--Not sure if I am crazy, but it seems the image rotations are inverted from the bone rotations
			local width, height = imageData.image:getWidth(), imageData.image:getHeight()
			
			--Pivot data is stored as 0-1, but actually represents an offset of 0-width or 0-height for rotation purposes
			local pivotX = imageData.pivotX or 0
			local pivotY = imageData.pivotY or 1
			--Rescape pivot data from 0,1 to 0,w/h
			pivotX = rescale( pivotX, 0, 1, 0, imageData.image:getWidth() )
			--Love2D has Y inverted from Spriter behavior -- pivotY is height - pivotY value
			pivotY = imageData.image:getHeight() - rescale( pivotY, 0, 1, 0, imageData.image:getHeight() )

			love.graphics.draw(imageData.image, x, y, -imageData.angle, imageData.scale_x, imageData.scale_y, pivotX, pivotY)
			--love.graphics.draw(imageData.image, x, y, -imageData.angle)
		end
	end

	--Draw bones if debug boolean set
	if debug then
		drawDebugInfo()
	end

	--Turn off canvas.  Graphics operations now apply to screen
	love.graphics.setCanvas()

	-- The rectangle from the Canvas was already alpha blended.
	-- Use the premultiplied blend mode when drawing the Canvas itself to prevent another blending.
	love.graphics.setBlendMode('premultiplied')

	--I'm sure there's a more elegant way to handle this, but I'm being lazy.
	--Handle flips by rendering with -1 x scaling
	if not inverted then
		love.graphics.draw(canvas, 0, 0)
	else
		--Need to offset x position due to scaling
		love.graphics.draw(canvas, 800, 0, 0, -1, 1)
	end

	--Turn default back on
	love.graphics.setBlendMode('alpha')

	
	local instructions = {
		"F : Toggle full screen",
		"I : Invert animation",
		"B : Toggle Bones",
		"N : Next Animation",
		"P : Toggle interpolation",
		"L : Load another spriter file"
	}

	local y = 100
	for i = 1, #instructions do
		local instruction = instructions[i]
		love.graphics.print( instruction, 10, y)
		y = y + 30
	end
end
