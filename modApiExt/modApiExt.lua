local modApiExt = {}

--[[
	Load the ext API's modules through this function to ensure that they can
	access other modules via self keyword.
--]]
function modApiExt:loadModule(path)
	local m = require(path)
	setmetatable(m, self)
	return m
end

function modApiExt:scheduleHook(msTime, fn)
	modApi:scheduleHook(msTime, fn)
end

function modApiExt:runLater(f)
	modApi:runLater(f)
end

function modApiExt:clearHooks()
	local endswith = function(str, suffix)
		return suffix == "" or string.sub(str,-string.len(suffix)) == suffix
	end

	-- too lazy to update this function with new hooks every time
	for k, v in pairs(self) do
		if type(v) == "table" and endswith(k, "Hooks") then
			self[k] = {}
		end
	end
end

--[[
	Returns true if this instance of modApiExt is the most recent one
	out of all registered instances.
--]]
function modApiExt:isMostRecent()
	assert(modApiExt_internal)
	assert(modApiExt_internal.extObjects)

	local v = self.version
	for _, extObj in ipairs(modApiExt_internal.extObjects) do
		if v ~= extObj.version and modApi:isVersion(v, extObj.version) then
			return false
		end
	end

	return true
end

--[[
	Returns the most recent registered instance of modApiExt.
--]]
function modApiExt:getMostRecent()
	assert(modApiExt_internal)
	return modApiExt_internal:getMostRecent()
end

function modApiExt:getParentPath(path)
	return path:sub(0, path:find("/[^/]*$"))
end

--[[
	Initializes the modApiExt object by loading available modules and setting
	up hooks.

	modulesDir - path to the directory containing all modules, with a forward
	             slash (/) at the end
--]]
function modApiExt:init(modulesDir)
	self.__index = self
	self.modulesDir = modulesDir or self.modulesDir
	self.version = require(self.modulesDir.."init").version

	local minv = "2.2.3"
	if not modApi:isVersion(minv) then
		error("modApiExt could not be loaded because version of the mod loader is out of date. "
			..string.format("Installed version: %s, required: %s", modApi.version, minv))
	end

	require(self.modulesDir.."internal"):init(self)
	table.insert(modApiExt_internal.extObjects, self)

	require(self.modulesDir.."global")

	local hooks = require(self.modulesDir.."hooks")
	for k, v in pairs(hooks) do
		self[k] = v
	end

	self.vector =   self:loadModule(self.modulesDir.."vector")
	self.string =   self:loadModule(self.modulesDir.."string")
	self.board =    self:loadModule(self.modulesDir.."board")
	self.weapon =   self:loadModule(self.modulesDir.."weapon")
	self.pawn =     self:loadModule(self.modulesDir.."pawn")
	self.dialog =   self:loadModule(self.modulesDir.."dialog")

	return self
end

function modApiExt:load(mod, options, version)
	-- We're already loaded. Bail.
	if self.loaded then return end

	self.owner = {
		id = mod.id,
		name = mod.name,
		version = mod.version
	}

	-- clear out previously registered hooks, since we're reloading.
	self:clearHooks()

	local hooks = self:loadModule(self.modulesDir.."alter")
	self.board:__init()

	modApi:addMissionStartHook(hooks.missionStart)
	modApi:addMissionEndHook(hooks.missionEnd)

	modApi:addPostLoadGameHook(function()
		if self:getMostRecent() == self then
			if Board then
				Board.gameBoard = true
			end

			if modApiExt_internal.mission then
				-- modApiExt_internal.mission is only updated in missionUpdateHook,
				-- and reset back to nil when we're not in-game.
				-- So if it's available, we must be loading from inside of a mission,
				-- which only happens when the player uses reset turn.
				modApiExt_internal.fireResetTurnHooks(modApiExt_internal.mission)
			else
				modApiExt_internal.fireGameLoadedHooks(GetCurrentMission())
				self.dialog:triggerRuledDialog("GameLoad")
			end
		end
	end)

	modApi:scheduleHook(20, function()
		-- Execute on roughly the next frame.
		-- This allows us to reset the loaded flag after all other
		-- mods are done loading.
		self.loaded = false

		table.insert(
			modApi.missionUpdateHooks,
			list_indexof(modApiExt_internal.extObjects, self),
			hooks.missionUpdate
		)

		if self:getMostRecent() == self then
			self.board:__load()

			if hooks.overrideAllSkills then
				-- Make sure the most recent version overwrites all others
				dofile(self.modulesDir.."global.lua")
				hooks:overrideAllSkills()

				-- Ensure backwards compatibility
				self:addSkillStartHook(function(mission, pawn, skill, p1, p2)
					if skill == "Move" then
						self.dialog:triggerRuledDialog("MoveStart", { main = pawn:GetId() })
						modApiExt_internal.fireMoveStartHooks(mission, pawn, p1, p2)
					end
				end)
				self:addSkillEndHook(function(mission, pawn, skill, p1, p2)
					if skill == "Move" then
						self.dialog:triggerRuledDialog("MoveEnd", { main = pawn:GetId() })
						modApiExt_internal.fireMoveEndHooks(mission, pawn, p1, p2)
					end
				end)
			end

			modApi:addVoiceEventHook(hooks.voiceEvent)

			modApiExt_internal.fireMostRecentResolvedHooks(self)
		end
	end)

	self.loaded = true
end

modApiExt.modulesDir = modApiExt:getParentPath(...)

return modApiExt
