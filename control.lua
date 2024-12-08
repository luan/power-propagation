local propagation = {}

-- Check if an entity can participate in power network
function propagation.should_extend_power(entity)
  if not (entity and entity.valid) then
    return false
  end

  -- Check if entity has an electric energy source
  local prototype = entity.prototype
  if not prototype then
    return false
  end
  return false
    or (settings.startup["power-propagation-through-powered-buildings"].value and prototype.electric_energy_source_prototype ~= nil)
    or (settings.startup["power-propagation-through-walls"].value and prototype.type == "wall")
    or (
      settings.startup["power-propagation-through-rails"].value
      and prototype.subgroup
      and prototype.subgroup.name == "train-transport"
    )
end

-- Connect nearby entities to a pole
function propagation.connect_nearby_entities_to_pole(pole)
  if not (pole and pole.valid) then
    return
  end

  -- Find nearby entities that should extend power
  local nearby_entities = pole.surface.find_entities_filtered({
    position = pole.position,
    radius = pole.prototype.get_supply_area_distance(pole.quality),
  })

  for _, entity in pairs(nearby_entities) do
    if propagation.should_extend_power(entity) then
      -- Remove any existing power poles for this entity
      propagation.remove_power_poles(entity)
      -- Create new power extender
      propagation.place_power_poles(entity)
    end
  end
end

-- Connect two poles together
function propagation.connect_poles(pole1, pole2)
  if not (pole1 and pole1.valid and pole2 and pole2.valid) then
    return
  end

  -- Get the copper wire connection points
  local connector1 = pole1.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  local connector2 = pole2.get_wire_connector(defines.wire_connector_id.pole_copper, true)

  -- Connect the poles
  connector1.connect_to(connector2, false)
end

function propagation.connect_pole_to_nearby_poles(entity, surface, pole)
  -- Store the pole's position
  storage.pole_positions = storage.pole_positions or {}
  storage.pole_positions[entity.unit_number] = storage.pole_positions[entity.unit_number] or {}
  table.insert(storage.pole_positions[entity.unit_number], { x = entity.position.x, y = entity.position.y })

  -- Find ALL poles within maximum possible range
  local nearby_poles = surface.find_entities_filtered({
    type = "electric-pole",
    position = entity.position,
    radius = 64, -- Large enough to catch everything
  })

  -- For invisible poles, connect to both regular poles and other invisible poles
  if pole.name:sub(1, 27) == "power-propagation-invisible" then
    local my_range = pole.prototype.get_supply_area_distance(pole.quality)

    -- First connect to regular poles
    for _, nearby_pole in pairs(nearby_poles) do
      if nearby_pole ~= pole and nearby_pole.name:sub(1, 27) ~= "power-propagation-invisible" then
        local distance =
          math.sqrt((entity.position.x - nearby_pole.position.x) ^ 2 + (entity.position.y - nearby_pole.position.y) ^ 2)

        -- Use combined range for regular pole connections too
        local pole_range = nearby_pole.prototype.get_supply_area_distance(nearby_pole.quality)
        local combined_range = my_range + pole_range

        if distance <= combined_range then
          propagation.connect_poles(pole, nearby_pole)
        end
      end
    end

    -- Then connect to other invisible poles
    for _, nearby_pole in pairs(nearby_poles) do
      if nearby_pole ~= pole and nearby_pole.name:sub(1, 27) == "power-propagation-invisible" then
        local distance =
          math.sqrt((entity.position.x - nearby_pole.position.x) ^ 2 + (entity.position.y - nearby_pole.position.y) ^ 2)

        -- Use combined range for invisible pole connections
        local combined_range = my_range + nearby_pole.prototype.get_supply_area_distance(nearby_pole.quality)

        if distance <= combined_range then
          propagation.connect_poles(pole, nearby_pole)
        end
      end
    end
  end
end

-- Create an invisible power pole
function propagation.create_power_extender(surface, entity)
  -- No need for power propagation if the surface has a global electric network
  if surface.has_global_electric_network then
    return nil
  end
  if not entity.unit_number then
    return nil
  end
  local entity_width = entity.prototype.collision_box.right_bottom.x - entity.prototype.collision_box.left_top.x
  local entity_height = entity.prototype.collision_box.right_bottom.y - entity.prototype.collision_box.left_top.y
  local size = math.max(math.ceil(entity_width), math.ceil(entity_height))
  if size < 1 then
    return nil
  end
  local pole_type = "power-propagation-invisible-pole-" .. size

  -- Create a hidden electric pole
  local pole = surface.create_entity({
    name = pole_type,
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false,
  })
  if not pole then
    return nil
  end
  propagation.connect_pole_to_nearby_poles(entity, surface, pole)
  return pole
end

-- Remove power poles owned by an entity
function propagation.remove_power_poles(entity)
  if not (entity and entity.valid) then
    return
  end
  if not entity.unit_number then
    return
  end

  -- Get the stored pole positions for this entity
  local positions = storage.pole_positions[entity.unit_number]
  if not positions then
    return
  end
  local entity_width = entity.prototype.collision_box.right_bottom.x - entity.prototype.collision_box.left_top.x
  local entity_height = entity.prototype.collision_box.right_bottom.y - entity.prototype.collision_box.left_top.y
  local pole_type = "power-propagation-invisible-pole-" .. math.max(math.ceil(entity_width), math.ceil(entity_height))

  -- Find and remove all poles at the stored positions
  for _, pos in pairs(positions) do
    local poles = entity.surface.find_entities_filtered({
      name = pole_type,
      position = pos,
      radius = 0.1,
    })
    if poles and #poles > 0 then
      local pole = poles[1]
      if pole.valid then
        pole.destroy()
      end
    end
  end

  -- Clear the stored positions
  storage.pole_positions[entity.unit_number] = nil
end

-- Place power poles for an entity
function propagation.place_power_poles(entity)
  if not (entity and entity.valid and propagation.should_extend_power(entity)) then
    return
  end

  return propagation.create_power_extender(entity.surface, entity)
end

-- Refresh power poles for all entities
function propagation.refresh_all_power_poles()
  -- First remove all existing power poles
  local pole_types = {}
  for i = 1, 30 do
    table.insert(pole_types, "power-propagation-invisible-pole-" .. i)
  end
  for _, surface in pairs(game.surfaces) do
    for _, pole_type in pairs(pole_types) do
      local poles = surface.find_entities_filtered({ name = pole_type })
      for _, pole in pairs(poles) do
        if pole.valid then
          pole.destroy()
        end
      end
    end
  end

  -- Clear stored positions
  storage.pole_positions = {}

  -- Add new poles for all entities
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities()
    for _, entity in pairs(entities) do
      if entity.valid and propagation.should_extend_power(entity) then
        propagation.place_power_poles(entity)
      end
    end
  end
end

function propagation.on_entity_moved(entity)
  if entity and entity.valid then
    propagation.remove_power_poles(entity)
    propagation.place_power_poles(entity)
  end
end

function propagation.on_dolly_moved_entity(event)
  propagation.on_entity_moved(event.moved_entity)
end

-- Initialize storage table
script.on_init(function()
  storage.pole_positions = {}
  propagation.refresh_all_power_poles()

  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("PickerDollies", "dolly_moved_entity_id"), propagation.on_dolly_moved_entity)
  end
end)

script.on_load(function()
  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("PickerDollies", "dolly_moved_entity_id"), propagation.on_dolly_moved_entity)
  end
end)

-- Handle settings changes
script.on_configuration_changed(function(data)
  if data.mod_startup_settings_changed or data.mod_changes["power-propagation"] ~= nil then
    propagation.refresh_all_power_poles()
  end
end)

script.on_event(defines.events.script_raised_teleported, function(event)
  propagation.on_entity_moved(event.entity)
end)

-- Event handlers for when an entity is created
local entity_creation_events = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_revive,
  defines.events.script_raised_built,
}

for _, event in pairs(entity_creation_events) do
  script.on_event(event, function(event_data)
    local entity = event_data.entity
    if not (entity and entity.valid) then
      return
    end

    if entity.type == "electric-pole" then
      -- If a power pole was placed, check for nearby entities to connect
      propagation.connect_nearby_entities_to_pole(entity)

      -- Also check for any nearby extenders that should connect to this pole
      local nearby_extenders = entity.surface.find_entities_filtered({
        type = "electric-pole",
        position = entity.position,
        radius = 64, -- Large enough to catch everything
      })

      for _, extender in pairs(nearby_extenders) do
        if extender.name:sub(1, 27) == "power-propagation-invisible" then
          local distance =
            math.sqrt((entity.position.x - extender.position.x) ^ 2 + (entity.position.y - extender.position.y) ^ 2)

          -- Check if the pole is within the extender's range
          local pole_range = entity.prototype.get_supply_area_distance(entity.quality)
          local extender_range = extender.prototype.get_supply_area_distance(extender.quality)
          local combined_range = pole_range + extender_range

          if distance <= combined_range then
            propagation.connect_poles(entity, extender)
          end
        end
      end
    else
      -- For other entities, handle as before
      propagation.place_power_poles(entity)
    end
  end)
end

-- Event handlers for when an entity is removed
local entity_removal_events = {
  defines.events.on_entity_died,
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.script_raised_destroy,
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.script_raised_destroy,
}

for _, event in pairs(entity_removal_events) do
  script.on_event(event, function(event_data)
    if event_data.entity and event_data.entity.valid then
      propagation.remove_power_poles(event_data.entity)
    end
  end)
end
