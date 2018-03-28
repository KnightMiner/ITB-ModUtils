local modApiExtHooks = {}

function modApiExtHooks:trackAndUpdatePawns(mission)
	if Board then
		if not GAME.trackedPawns then GAME.trackedPawns = {} end

		local tbl = extract_table(Board:GetPawns(TEAM_ANY))

		-- Store information about pawns which should remain on the board,
		-- we can use this data later.
		local onBoard = {}

		-- If any of the tracked pawns were removed from the board, reinsert
		-- them into the table, to process them correctly.
		for id, pd in pairs(GAME.trackedPawns) do
			-- Sometimes pawns are removed via Board:RemovePawn(), in which
			-- case we have no way to obtain their data anymore. Don't attempt
			-- to reinsert those.
			local pawn = Board:GetPawn(id)
			if not list_contains(tbl, id) and pawn then
				onBoard[id] = false
				table.insert(tbl, id)
			end
		end

		for i, id in pairs(tbl) do
			local pawn = Board:GetPawn(id)

			if not GAME.trackedPawns[id] then
				-- Pawn is not tracked yet
				-- Create a pawnData table for it
				GAME.trackedPawns[id] = {
					userdata = pawn,
					loc = pawn:GetSpace(),
					maxHealth = pawn:GetHealth(),
					curHealth = pawn:GetHealth(),
					dead = (pawn:GetHealth() == 0),
					player = pawn:IsPlayer() and pawn:IsMech(),
					selected = false
				}
			else
				-- Already tracked, update its data
				local pd = GAME.trackedPawns[id]
				local oldHealth = pd.curHealth
				pd.curHealth = pawn:GetHealth()
				local diff = pd.curHealth - oldHealth

				if diff < 0 then
					-- took damage
					for i, hook in ipairs(modApiExt.pawnDamagedHooks) do
						hook(mission, id, -diff)
					end
				elseif diff > 0 then
					-- healed
					for i, hook in ipairs(modApiExt.pawnHealedHooks) do
						hook(mission, id, diff)
					end
				end

				-- Deselection
				if pd.selected and not pawn:IsSelected() then
					pd.selected = false
					for i, hook in ipairs(modApiExt.pawnDeselectedHooks) do
						hook(mission,id)
					end
				end
			end
		end

		-- Process selection in another loop, so that callbacks always
		-- go Deselection -> Selection, instead of relying on pawn order in table
		for i, id in pairs(tbl) do
			local pd = GAME.trackedPawns[id]
			local pawn = Board:GetPawn(id)

			if pawn:IsSelected() and not pd.selected then
				pd.selected = true
				for i, hook in ipairs(modApiExt.pawnSelectedHooks) do
					hook(mission,id)
				end
			end
		end

		for id, pd in pairs(GAME.trackedPawns) do
			if not pd.dead and pd.curHealth == 0 then
				-- Dead non-player pawns are removed from the board, so we can just
				-- remove them from tracking since they're not going to come back
				-- to life. However, player pawns (mechs) stay on the board when
				-- dead. Don't remove them from the tracking table, since if we do
				-- that, they're going to get reinserted.
				-- Treat pawns not registered in the onBoard table as on board
				-- (they could've been placed on the board during this update,
				-- so they weren't tracked when that table was being built).
				local staysOnBoard = onBoard[id] or onBoard[id] == nil
				if staysOnBoard then
					pd.dead = true
				else
					-- if this pawn doesn't stay on the board when dead (eg. player mechs,
					-- and maybe some others?), then remove it from tracking table.
					GAME.trackedPawns[id] = nil
				end

				for i, hook in ipairs(modApiExt.pawnKilledHooks) do
					hook(mission,id)
				end
			end
		end
	end
end

function modApiExtHooks:trackAndUpdateBuildings(mission)
	if Board then
		if not GAME.trackedBuildings then GAME.trackedBuildings = {} end

		local tbl = extract_table(Board:GetBuildings())

		local w = Board:GetSize().x
		for i, point in pairs(tbl) do
			local idx = point.y * w + point.x
			if not GAME.trackedBuildings[idx] then
				-- Building not tracked yet
				GAME.trackedBuildings[idx] = {
					loc = point,
					destroyed = false,
					--maxHealth = -1, -- NO WAY TO FIND OUT
					--curHealth = -1, -- NO WAY TO FIND OUT
					--dummy = nil,
					--lastHealth = -1
				}
				--[[
				local id = Board:AddPawn("ModApi_Ext_Dummy", b.loc)
				b.dummy = Board:GetPawn(id)
				b.lastHealth = b.dummy:GetHealth()
				b.dummy:SetInvisible(true)
				]]--
			else
				-- Already tracked, update its data...
				-- ...if there were any
			end
		end

		for idx, bld in pairs(GAME.trackedBuildings) do
			if not bld.destroyed then
				--[[
				local pawnId = bld.dummy:GetId()
				local pawn = Board:GetPawn(pawnId)

				-- Putting shield on a building with an invisible dummy
				-- on top of it will put the shield on the dummy.
				-- But since the dummy is invisible, the shield is also
				-- invisible (sound shield plays, correct pop text is
				-- shown, and damage is correctly blocked)
				-- TODO: Idea: try to detect when the pawn is shielded,
				-- move it off the board, then programmatically put shield
				-- on the building is stood on? But there's no way to
				-- detect when the building's shield goes down...
				pawn:SetInvisible(not pawn:IsShield())

				local diff = pawn:GetHealth() - bld.lastHealth
				if diff < 0 then
					bld.lastHealth = pawn:GetHealth()

					-- Grid resist *groan*					
					if Board:IsDamaged(bld.loc) then
						for i, hook in ipairs(modApiExt.buildingDamagedHooks) do
							hook(mission, bld, -diff)
						end
					end
				end
				]]--

				if not Board:IsBuilding(bld.loc) then
					bld.destroyed = true
					--bld.dummy:Kill(true)
					--Board:RemovePawn(bld.dummy)

					for i, hook in ipairs(modApiExt.buildingDestroyedHooks) do
						hook(mission, bld)
					end

					bld.dummy = nil
				end
			end
		end
	end
end

function modApiExtHooks:resetTrackingTables()
	GAME.trackedBuildings = nil
	GAME.trackedPawns = nil
end

---------------------------------------------

modApiExtHooks.preMissionStart = function(mission)
end

modApiExtHooks.missionStart = function(mission)
	modApiExtHooks:resetTrackingTables(mission)
end

modApiExtHooks.missionEnd = function(mission, ret)
	modApiExtHooks:resetTrackingTables(mission)
end

modApiExtHooks.missionUpdate = function(mission)
	modApiExtHooks:trackAndUpdateBuildings(mission)
	modApiExtHooks:trackAndUpdatePawns(mission)
end

return modApiExtHooks
