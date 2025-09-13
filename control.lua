local Public = {}

local WARN_COLOR = { r = 255, g = 90, b = 54 }

local TICKS_PER_GUI_CHECK = 60

local function get_destination_choices(force, planet_name_to_exclude)
	local choices = {}

	for name, planet in pairs(game.planets) do
		if
			force.is_space_location_unlocked(name)
			-- or (
			-- 	planet.surface
			-- 	and not name == "nauvis"
			-- 	and settings.global["planet-hopper-can-launch-to-planets-with-surface"].value
			-- )
			and (not planet_name_to_exclude or name ~= planet_name_to_exclude)
			and not planet.prototype.hidden
		then
			table.insert(choices, {
				key = name,
				display_name = { "", "[space-location=" .. name .. "] ", { "space-location-name." .. name } },
			})
		end
	end

	return choices
end

local function is_silo(entity)
	return (entity.type == "rocket-silo" and entity.name == "planet-hopper-launcher")
	-- or (entity.name == "entity-ghost" and entity.ghost_name == "planet-hopper-launcher")
end

local GUI_KEY = "Planet-Hopper-destination"

local function update_gui_state(player, entity, planet)
	local relative = player.gui.relative

	if not relative[GUI_KEY] then
		local main_frame = relative.add({
			type = "frame",
			name = GUI_KEY,
			direction = "vertical",
			tags = {
				mod_version = script.active_mods["Planet-Hopper"],
			},
			anchor = {
				name = entity.name,
				gui = defines.relative_gui_type.rocket_silo_gui,
				position = defines.relative_gui_position.right,
			},
		})

		local titlebar_flow = main_frame.add({
			type = "flow",
			direction = "horizontal",
			drag_target = main_frame,
		})

		titlebar_flow.add({
			type = "label",
			caption = { "hopper.launch-menu" },
			style = "frame_title",
			ignored_by_interaction = true,
		})

		local drag_handle = titlebar_flow.add({
			type = "empty-widget",
			ignored_by_interaction = true,
			style = "draggable_space_header",
		})
		drag_handle.style.horizontally_stretchable = true
		drag_handle.style.height = 24
		drag_handle.style.right_margin = 4

		local content_frame = main_frame.add({
			type = "frame",
			name = "content",
			style = "inside_shallow_frame_with_padding_and_vertical_spacing",
			direction = "vertical",
		})

		content_frame.add({
			type = "list-box",
			name = "planet-hopper-destination-selector",
			items = {},
		})

		content_frame.add({
			type = "button",
			name = "planet-hopper-launch-button",
			style = "green_button",
			caption = { "hopper.launch" },
		})
	end

	local content_frame = relative[GUI_KEY].content
	local listbox = content_frame["planet-hopper-destination-selector"]
	local launch_button = content_frame["planet-hopper-launch-button"]

	local choices = get_destination_choices(player.force, planet and planet.name or nil)
	local enabled = false

	if planet then
		local current_option_index = 1
		for i = 1, #listbox.items do
			local current_item = listbox.items[i]

			if choices[current_option_index] then
				local expected_item = choices[current_option_index].display_name

				if current_item[2][1] ~= expected_item[2][1] then
					listbox.add_item(expected_item, i)
					current_option_index = current_option_index + 1
				else
					current_option_index = current_option_index + 1
				end
			end
		end
		while current_option_index <= #choices do
			listbox.add_item(choices[current_option_index].display_name)
			current_option_index = current_option_index + 1
		end

		enabled = #choices > 0
			and entity.rocket_silo_status == defines.rocket_silo_status.rocket_ready
			and listbox.selected_index > 0
			and player.controller_type == defines.controllers.character
			and not entity.frozen
	else
		listbox.clear_items()
	end

	local tooltip
	if not planet then
		tooltip = { "hopper.launch-only-from-planet-tooltip" }
	elseif #choices == 0 then
		tooltip = { "hopper.launch-no-destinations-tooltip" }
	elseif entity.rocket_silo_status ~= defines.rocket_silo_status.rocket_ready then
		tooltip = { "hopper.launch-not-ready-tooltip" }
	else
		tooltip = { "hopper.launch-tooltip" }
	end

	launch_button.enabled = enabled
	launch_button.style = enabled and "green_button" or "button"
	launch_button.tooltip = tooltip
end

script.on_event(defines.events.on_gui_opened, function(event)
	if event.gui_type ~= defines.gui_type.entity then
		return
	end

	local player = game.players[event.player_index]
	if not (player and player.valid) then
		return
	end

	local entity = event.entity
	if not (entity and entity.valid and is_silo(entity)) then
		return
	end

	if not (entity.surface and entity.surface.valid) then
		return
	end

	local relative = player.gui.relative

	local old_gui_key = "Planet-Hopper-override"
	if relative[old_gui_key] then
		relative[old_gui_key].destroy()
	end

	if relative[GUI_KEY] then
		relative[GUI_KEY].destroy()
	end

	update_gui_state(player, entity, entity.surface.planet)
end)

script.on_event(defines.events.on_gui_click, function(event)
	if not event.element or event.element.name ~= "planet-hopper-launch-button" then
		return
	end

	local player = game.players[event.player_index]
	if not (player and player.valid) then
		return
	end

	local character = player.character
	if not (character and character.valid) then
		return
	end

	local relative = player.gui.relative
	if not relative[GUI_KEY] then
		return
	end

	local destination_list = relative[GUI_KEY].content["planet-hopper-destination-selector"]
	if not destination_list or #destination_list.items == 0 then
		return
	end

	local selected_index = destination_list.selected_index
	if not selected_index then
		return
	end

	local destination_display_name = destination_list.items[selected_index]
	if not destination_display_name then
		return
	end

	local destination_name = destination_display_name[2]:match("%[space%-location=([^%]]+)%]")
	if not destination_name then
		return
	end

	local abort_interface_name = "Planet-Hopper-abort-" .. destination_name
	if
		remote.interfaces[abort_interface_name]
		and remote.interfaces[abort_interface_name]["should_abort"]
		and remote.call(abort_interface_name, "should_abort", character)
	then
		if remote.interfaces[abort_interface_name]["on_launch_aborted"] then
			remote.call(abort_interface_name, "on_launch_aborted", player)
		else
			player.print({ "hopper.launch-aborted-by-destination-mod" }, { color = WARN_COLOR })
		end

		return
	end

	if not game.surfaces[destination_name] then
		game.planets[destination_name].create_surface()
	end

	local silo = player.opened

	if
		not (
			silo
			and silo.valid
			and silo.type == "rocket-silo"
			and silo.rocket_silo_status == defines.rocket_silo_status.rocket_ready
		)
	then
		return
	end

	local inventories = {
		character.get_inventory(defines.inventory.character_ammo),
		character.get_inventory(defines.inventory.character_main),
		character.get_inventory(defines.inventory.character_trash),
	}

	local surface = player.surface

	for _, inventory in ipairs(inventories) do
		if inventory and inventory.valid then
			surface.spill_inventory({
				inventory = inventory,
				position = character.position,
			})
		end
	end

	local launch_result = silo.launch_rocket({
		type = defines.cargo_destination.surface,
		surface = game.surfaces[destination_name],
	}, character)

	if not launch_result then
		player.print({ "hopper.launch-failed-whisper" }, { color = WARN_COLOR })
	end

	player.opened = nil
end)

script.on_event(defines.events.on_tick, function(event)
	if event.tick % TICKS_PER_GUI_CHECK ~= 0 then
		return
	end

	for _, player in pairs(game.connected_players) do
		if player and player.valid then
			local entity = player.opened
			if
				player.opened_gui_type == defines.gui_type.entity
				and entity
				and entity.valid
				and is_silo(entity)
				and entity.surface
				and entity.surface.valid
			then
				local relative = player.gui.relative
				if relative[GUI_KEY] then
					update_gui_state(player, entity, entity.surface.planet)
				end
			end
		end
	end
end)

return Public
