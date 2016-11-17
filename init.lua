-- The Flight School minetest mod allows players to earn fly privileges in game.
-- Copyright (C) 2016  John Cole
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

local load_time_start = os.clock()

---------------------
-- Data Management --
---------------------

local data_file = minetest.get_worldpath()..'flightschool.mt'

local function load_data()
	local file = io.open(data_file, "r")
	local data = {
		pos = {x = 0, y = 0, z = 0},
		aircraft = {},
	}
	if file then
		data = minetest.deserialize(file:read("*all"))
		file:close()
	end
	return data
end

local function write_data(data)
	local file = io.open(data_file, 'w')
	if file then
		file:write(minetest.serialize(data))
		file:close()
	end
end

local flightschool = load_data(data_file)
local requirements = {}

----------------------
-- Helper Functions --
----------------------

local function time_string(seconds)
	local time = math.floor(seconds)
	local timestring = "ask Foz"
	if time > 0 then
		timestring = ""
		if time%60 ~= 0 then
			timestring = time%60 .. "s"
		end
		time = math.floor(time/60)
		if time > 0 then
			if time%60 ~= 0 then
				timestring = time%60 .. "m " ..timestring
			end
			time = math.floor(time/60)
			if time > 0 then
				if time%24 ~= 0 then
					timestring = time%24 .. "h " ..timestring
				end
				time = math.floor(time/24)
				if time > 0 then
					timestring = time .. "d " .. timestring
				end
			end
		end
	end
	return timestring
end

local function get_stat(self,name)
	return stats.get_stat(name, self.stat)
end

local function stat_check(req, name)
	return req:get(name) >= req.value
end

local function parse_pos_string(string)
	local xs, ys, zs = string.match(string,
		'[( ]*([^(), ]+)[, ]+([^(), ]+)[, ]+([^(), ]+)[) ]*')
	local x = tonumber(xs)
	local y = tonumber(ys)
	local z = tonumber(zs)
	if x and y and z then
		return {x = x, y = y, z = z}
	end
	return nil
end

function is_in_aircraft(pos)
	for _,craft in pairs(flightschool.aircraft) do
		if vector.distance(pos, craft.gpos) < 2 then
			return craft
		end
	end
	return false
end

local function is_eligible(name)
	for _,req in ipairs(requirements) do
		if not stat_check(req, name) then return false end
	end
	return true
end

-------------------
-- Configuration --
-------------------

requirements = {
	{
		name   = 'Items Crafted',
		stat   = 'crafted',
		value  = 200,
		string = tostring,
		get    = get_stat,
	},
	{
		name   = 'Nodes Placed',
		stat   = 'placed_nodes',
		value  = 1000,
		string = tostring,
		get    = get_stat,
	},
	{
		name   = 'Nodes Dug',
		stat   = 'digged_nodes',
		value  = 1000,
		string = tostring,
		get    = get_stat,
	},
	{
		name   = 'Areas Claimed',
		stat   = 'land_claims',
		value  = 4,
		string = tostring,
		get    = get_stat,
	},
	{
		name   = 'Deaths',
		stat   = 'died',
		value  = 1,
		string = tostring,
		get    = get_stat,
	},
	{
		name   = 'Active Time',
		stat   = 'played_time',
		value  = 28800, -- seconds (8 hours)
		string = function(value) return time_string(value) end,
		get    = get_stat,
	},
	{
		name   = 'Account Age',
		stat   = 'first_login',
		value  = 5184000, -- seconds (60 days)
		string = function(value) return time_string(value) end,
		get    = function(self, name)
			local stat = stats.get_stat(name, self.stat)
			if stat > 0 then
				return os.time() - stats.get_stat(name, self.stat)
			else
				return 0
			end
		end,
	}
}

---------
-- GUI --
---------

local function user_form(name)
	local admin = minetest.check_player_privs(name, {server=true})
	local fs = 'size[12,7.5]'
	fs = fs..'label[0,0;Pre-Flight Checklist: '..name..']'

	if admin then	fs = fs..'button[9,-0.2;2,1;admin;Admin]'	end
	fs = fs..'button_exit[11,-0.2;1,1;exit;X]'

	fs = fs..'tableoptions[highlight=#1e1e1e]'
	fs = fs..'tablecolumns['..
		'text,align=right,padding=1;'..
		'text,align=left,padding=1;'..
		'color,span=1;'..
		'text,align=left,padding=1]'
	fs = fs..'table[0,0.7;11.8,5.9;stats;'..
		'Stat:,Need,#ffffff,Have,'
	for _,req in ipairs(requirements) do
		local is_met = stat_check(req, name)

		local stat = req.name
		local required = req.string(req.value)
		local color = is_met and '#00ff00' or '#ff0000'
		local value = req.string(req:get(name))
		fs = fs..stat..':,'..required..','..color..','..value..','
	end
	fs = fs..';]'

	fs = fs..'button[0,6.8;12,1;go;Go To Flight School]'
	return fs
end

local function admin_form()
	local fs = 'size[12,7.5]'
	fs = fs..'label[0,0;Flight School]'
	fs = fs..'button_exit[11,-0.2;1,1;exit;X]'

	fs = fs..'field[0.3,1.03;3.5,1;user;;]'
	fs = fs..'button[3.5,0.7;2.96,1;user_view;User View]'

	fs = fs..'field[7.3,1.03;3.5,1;pos;Position;'..
		minetest.pos_to_string(flightschool.pos)..']'
	fs = fs..'button[10.52,0.7;1.48,1;edit_pos;Edit]'

	fs = fs..'tableoptions[highlight=#1e1e1e]'
	fs = fs..'tablecolumns['..
		'text,align=right,padding=1;'..
		'text,align=left,padding=1;'..
		'text,align=left,padding=1;'..
		'color,span=1;'..
		'text,align=center,padding=1]'
	fs = fs..'table[0,1.7;11.8,4.7;stats;'..
		'Aircraft:,Ground Pos,Flight Pos,#ffffff,Remove,'
	for _,craft in ipairs(flightschool.aircraft) do
		fs = fs..
		minetest.formspec_escape(craft.name)..':,'..
		minetest.formspec_escape(minetest.pos_to_string(craft.gpos))..','..
		minetest.formspec_escape(minetest.pos_to_string(craft.fpos))..','..
		'#ff0000,X,'
	end
	fs = fs..';]'

	fs = fs..'field[0.3,7.1;3.5,1;name;Aircraft;]'
	fs = fs..'field[3.8,7.1;3.5,1;gpos;Ground Pos;]'
	fs = fs..'field[7.3,7.1;3.5,1;fpos;Flight Pos;]'
	fs = fs..'button[10.52,6.79;1.48,1;add;Add]'
	return fs
end

minetest.register_chatcommand('flightcheck', {
	description = "Launches a Pre-Flight Checklist",
	privs = {interact = true},
	func = function(name)
		minetest.show_formspec(name, 'flightschool:checklist', user_form(name))
	end
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= 'flightschool:checklist' then return end
	local name = player:get_player_name()
	if fields then

		if fields.go then
			minetest.sound_play('teleport', {to_player=name, gain = 0.1})
			player:setpos(flightschool.pos)
		end

		if fields.admin then
			if minetest.check_player_privs(name, {server=true}) then
				minetest.show_formspec(name, 'flightschool:admin', admin_form())
			end
		end

	end
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= 'flightschool:admin' then return end

	local name = player:get_player_name()
	if not minetest.check_player_privs(name, {server=true}) then
		minetest.kick_player(name, 'Privilege violation.')
	end

	if fields then
		local changes = false

		if fields.edit_pos then
			local pos = parse_pos_string(fields.pos)
			if pos then
				flightschool.pos = pos
				changes = true
			end
		end

		-- Remove Aircraft
		if fields.stats then
			local index, remove = string.match(fields.stats, 'CHG:([0-9]+):([0-9]+)')
			if tonumber(remove) == 5 then
				table.remove(flightschool.aircraft,index-1)
				changes = true
			end
		end

		-- Add Aircraft
		if fields.add then
			local gpos = parse_pos_string(fields.gpos)
			local fpos = parse_pos_string(fields.fpos)
			if fields.name ~= "" and gpos and fpos then
				table.insert(flightschool.aircraft,{
					name = fields.name,
					gpos = gpos,
					fpos = fpos,
				})
				changes = true
			end
		end

		if changes then
			write_data(flightschool)
		end

		-- Refresh form
		if not fields.quit then
			if fields.user_view then
				local formname = 'flightschool:checklist'
				local user = name
				if minetest.auth_table[fields.user] then
					user = fields.user
				end
				minetest.show_formspec(name, formname, user_form(user))
			else
				minetest.show_formspec(name, formname, admin_form())
			end
		end
	end
end)

-- Add airborn fly eligible players to a tracking list.
local airborn = {}
minetest.register_chatcommand('takeoff', {
	description = 'Teleports the player to an airborn copy of '..
		'the aircraft they are standing in.',
	privs = {interact = true},
	func = function(name)
		local player = minetest.get_player_by_name(name)
		local pos    = player:getpos()
		local aircraft = is_in_aircraft(pos)
		if aircraft then
			if is_eligible(name) then
				table.insert(airborn,{player = player, fpos = aircraft.fpos})
				minetest.sound_play('teleport', {to_player=name, gain = 0.1})
				player:setpos(aircraft.fpos)
				minetest.log('action',
					'Flight School: '..name..' joined flight school.')
				minetest.chat_send_player(name, 'You are now in flight school.')
			else
				minetest.chat_send_player(name, 'You\'re not ready to learn how to '..
					'fly. Please try again later.')
			end
		else
			minetest.chat_send_player(name, 'You must be in an aircraft to takeoff.')
		end
	end
})

-- Track fly elegible players in aircraft and grant them fly if they jump.
local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= 0.1 then
		timer=0
		for index,trainee in ipairs(airborn) do
			local name = trainee.player:get_player_name()
			local ppos = trainee.player:getpos()
			local fpos = trainee.fpos

			if not name or not ppos or not fpos then
				-- Invalid aircraft or the player left the game.
				table.remove(airborn,index)
				minetest.log('action',
					'Flight School: Removed '..(name or '')..' from flight school.')
				if name then
					minetest.chat_send_player(name, 'You are no longer in flight school.')
				end
			else

				local distance = vector.distance(ppos, fpos)
				if distance > 100 then
					-- Player teleported out of aircraft.
					table.remove(airborn,index)
					minetest.log('action',
						'Flight School: '..name..' left flight school.'..
						' fpos='..minetest.pos_to_string(fpos)..
						' ppos='..minetest.pos_to_string(ppos)..
						' distance='..math.floor(distance)..'.')
					minetest.chat_send_player(name, 'You are no longer in flight school.')
				elseif distance > 10 and ppos.y < fpos.y then
					-- Player jumped out of aircraft.
					table.remove(airborn,index)
					local privs = minetest.get_player_privs(name)
					privs.fly = true
					minetest.set_player_privs(name, privs)
					minetest.log('action',
						'Flight School: Granted fly privileges to '..name..'.')
					minetest.chat_send_player(name, 'You have been granted fly.')
				end

			end
		end
	end
end)

minetest.log(
	'action',
	string.format(
		'['..minetest.get_current_modname()..'] loaded in %.3fs',
		os.clock() - load_time_start
	)
)
