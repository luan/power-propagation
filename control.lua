local propagation = {}
local pole_prefix = "power-propagation-invisible-pole-"
local rail_types = {
  ["legacy-straight-rail"] = true,
  ["legacy-curved-rail"] = true,
  ["straight-rail"] = true,
  ["half-diagonal-rail"] = true,
  ["curved-rail-a"] = true,
  ["curved-rail-b"] = true,
  ["elevated-straight-rail"] = true,
  ["elevated-half-diagonal-rail"] = true,
  ["elevated-curved-rail-a"] = true,
  ["elevated-curved-rail-b"] = true,
  ["rail-ramp"] = true,
  ["rail-support"] = true,
}

local function extends_power(prototype)
  return (
    settings.startup["power-propagation-through-powered-buildings"].value
    and prototype.electric_energy_source_prototype ~= nil
  )
    or (settings.startup["power-propagation-through-walls"].value and prototype.type == "wall")
    or (settings.startup["power-propagation-through-rails"].value and rail_types[prototype.type] == true)
end

-- Check if an entity can participate in power network
function propagation.should_extend_power(entity)
  return entity and entity.valid and extends_power(entity.prototype)
end

-- Connect two poles together
function propagation.connect_poles(pole1, pole2)
  if not (pole1.valid and pole2.valid) or pole1 == pole2 or pole1.force ~= pole2.force then
    return
  end

  local dx = pole1.position.x - pole2.position.x
  local dy = pole1.position.y - pole2.position.y
  local reach = pole1.prototype.get_supply_area_distance(pole1.quality)
    + pole2.prototype.get_supply_area_distance(pole2.quality)
  if dx * dx + dy * dy > reach * reach then
    return
  end

  local connector1 = pole1.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  local connector2 = pole2.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  if connector1 and connector2 and not connector1.is_connected_to(connector2) then
    connector1.connect_to(connector2, false)
  end
end

function propagation.connect_pole_to_nearby_poles(pole)
  local nearby_poles = pole.surface.find_entities_filtered({
    type = "electric-pole",
    force = pole.force,
    position = pole.position,
    radius = 64, -- Supports poles with up to 64 tiles of combined supply range; widen for longer-range modded poles.
  })
  for _, nearby_pole in pairs(nearby_poles) do
    propagation.connect_poles(pole, nearby_pole)
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
  -- Only 30 extender sizes are defined; support larger entities when more sizes are added.
  if size < 1 or size > 30 then
    return nil
  end
  local pole_type = pole_prefix .. size

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
  pole.destructible = false
  storage.poles[entity.unit_number] = pole
  propagation.connect_pole_to_nearby_poles(pole)
  return pole
end

-- Remove power poles owned by an entity
function propagation.remove_power_poles(entity)
  if not (entity and entity.valid and entity.unit_number) then
    return
  end
  local pole = storage.poles[entity.unit_number]
  if pole and pole.valid then
    pole.destroy()
  end
  storage.poles[entity.unit_number] = nil
end

-- Place power poles for an entity
function propagation.place_power_poles(entity)
  if not (entity and entity.valid and propagation.should_extend_power(entity)) then
    return
  end

  local pole = storage.poles[entity.unit_number]
  if pole and pole.valid then
    return pole
  end
  return propagation.create_power_extender(entity.surface, entity)
end

-- Refresh power poles for all entities
function propagation.refresh_all_power_poles()
  -- First remove all existing power poles
  local pole_types = {}
  for i = 1, 30 do
    pole_types[i] = pole_prefix .. i
  end
  for _, surface in pairs(game.surfaces) do
    for _, pole in pairs(surface.find_entities_filtered({ name = pole_types })) do
      pole.destroy()
    end
  end

  storage.pole_positions = nil -- Drop the position-only storage from versions before 1.5.2.
  storage.poles = {}

  local types = {}
  for _, prototype in pairs(prototypes.entity) do
    if extends_power(prototype) then
      types[prototype.type] = true
    end
  end
  local eligible_types = {}
  for type in pairs(types) do
    eligible_types[#eligible_types + 1] = type
  end
  if #eligible_types == 0 then
    return
  end

  for _, surface in pairs(game.surfaces) do
    if not surface.has_global_electric_network then
      for _, entity in pairs(surface.find_entities_filtered({ type = eligible_types })) do
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

local function on_entity_created(entity)
  if not (entity and entity.valid) then
    return
  end

  if entity.type == "electric-pole" then
    local nearby_extenders = entity.surface.find_entities_filtered({
      type = "electric-pole",
      force = entity.force,
      position = entity.position,
      radius = 64, -- Supports poles with up to 64 tiles of combined supply range; widen for longer-range modded poles.
    })

    for _, extender in pairs(nearby_extenders) do
      if extender.name:sub(1, #pole_prefix) == pole_prefix then
        propagation.connect_poles(entity, extender)
      end
    end
  else
    propagation.place_power_poles(entity)
  end
end

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_revive,
  defines.events.script_raised_built,
}, function(event)
  on_entity_created(event.entity)
end)

script.on_event(defines.events.on_entity_cloned, function(event)
  local entity = event.destination
  if entity.name:sub(1, #pole_prefix) == pole_prefix then
    entity.destroy() -- The cloned owner creates its own extender instead.
  else
    on_entity_created(entity)
  end
end)

script.on_event({
  defines.events.on_entity_died,
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.script_raised_destroy,
}, function(event)
  propagation.remove_power_poles(event.entity)
end)
