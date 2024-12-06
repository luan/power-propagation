-- Check if an entity can participate in power network
local function should_extend_power(entity)
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

-- Connect two poles together
local function connect_poles(pole1, pole2)
  if not (pole1 and pole1.valid and pole2 and pole2.valid) then
    return
  end

  -- Get the copper wire connection points
  local connector1 = pole1.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  local connector2 = pole2.get_wire_connector(defines.wire_connector_id.pole_copper, true)

  -- Connect the poles
  connector1.connect_to(connector2, false)
end

-- Check if position is within any pole's supply area
local function is_powered_position(surface, position)
  local nearby_poles = surface.find_entities_filtered({
    type = "electric-pole",
    position = position,
    radius = 32, -- Maximum possible supply area in vanilla
  })

  for _, pole in pairs(nearby_poles) do
    if pole.valid then
      local distance = ((position.x - pole.position.x) ^ 2 + (position.y - pole.position.y) ^ 2) ^ 0.5
      local supply_area = pole.prototype.get_supply_area_distance(pole.quality)
      if distance <= supply_area then
        return true
      end
    end
  end

  return false
end

local function connect_pole_to_nearby_poles(entity, surface, pole)
  -- Store the pole's position
  storage.pole_positions = storage.pole_positions or {}
  storage.pole_positions[entity.unit_number] = storage.pole_positions[entity.unit_number] or {}
  table.insert(storage.pole_positions[entity.unit_number], { x = entity.position.x, y = entity.position.y })

  -- Connect to nearby poles
  local nearby_poles = surface.find_entities_filtered({
    type = "electric-pole",
    position = entity.position,
    radius = 32, -- Maximum possible supply area in van
  })

  for _, nearby_pole in pairs(nearby_poles) do
    local distance = math.max(
      math.abs(entity.position.x - nearby_pole.position.x),
      math.abs(entity.position.y - nearby_pole.position.y)
    ) - pole.prototype.get_supply_area_distance(pole.quality)
    if distance <= nearby_pole.prototype.get_supply_area_distance(nearby_pole.quality) and nearby_pole ~= pole then
      connect_poles(pole, nearby_pole)
    end
  end
end

-- Create an invisible power pole
local function create_power_extender(surface, entity)
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
  connect_pole_to_nearby_poles(entity, surface, pole)
  return pole
end

-- Remove power poles owned by an entity
local function remove_power_poles(entity)
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
local function place_power_poles(entity)
  if not (entity and entity.valid and should_extend_power(entity)) then
    return
  end

  create_power_extender(entity.surface, entity)
end

-- Refresh power poles for all entities
local function refresh_all_power_poles()
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
      if entity.valid and should_extend_power(entity) then
        place_power_poles(entity)
      end
    end
  end
end

local function on_entity_moved(entity)
  if entity and entity.valid then
    remove_power_poles(entity)
    place_power_poles(entity)
  end
end

local function on_dolly_moved_entity(event)
  on_entity_moved(event.moved_entity)
end

-- Initialize storage table
script.on_init(function()
  storage.pole_positions = {}
  refresh_all_power_poles()

  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("PickerDollies", "dolly_moved_entity_id"), on_dolly_moved_entity)
  end
end)

script.on_load(function()
  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("PickerDollies", "dolly_moved_entity_id"), on_dolly_moved_entity)
  end
end)

-- Handle settings changes
script.on_configuration_changed(function(data)
  if data.mod_startup_settings_changed or data.mod_changes["power-propagation"] ~= nil then
    refresh_all_power_poles()
  end
end)

script.on_event(defines.events.script_raised_teleported, function(event)
  on_entity_moved(event.entity)
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
    if event_data.entity and event_data.entity.valid then
      place_power_poles(event_data.entity)
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
      remove_power_poles(event_data.entity)
    end
  end)
end
