local range = settings.startup["power-propagation-range"].value

local invisible_pole = table.deepcopy(data.raw["electric-pole"]["small-electric-pole"])
invisible_pole.name = "power-propagation-invisible-pole"
invisible_pole.flags = {
  "not-blueprintable",
  "not-deconstructable",
  "placeable-off-grid",
  "not-on-map",
  "hide-alt-info",
  "not-selectable-in-game",
  "not-upgradable",
  "not-in-kill-statistics",
  "not-flammable",
  "not-repairable",
}
invisible_pole.selection_box = nil
invisible_pole.collision_box = nil
invisible_pole.collision_mask = { layers = {} }

invisible_pole.pictures = {
  layers = {
    {
      filename = "__core__/graphics/empty.png",
      priority = "high",
      width = 1,
      height = 1,
      direction_count = 1,
    },
  },
}

-- Add connection points for the wires
invisible_pole.connection_points = {
  {
    wire = {
      copper = { 0, 0 },
      red = { 0, 0 },
      green = { 0, 0 },
    },
    shadow = {
      copper = { 0, 0 },
      red = { 0, 0 },
      green = { 0, 0 },
    },
  },
}

-- Set coverage based on spacing
invisible_pole.supply_area_distance = 0.5 -- Defined in each prototype below 1..n
invisible_pole.maximum_wire_distance = 1 -- Manually connected in control.lua
invisible_pole.draw_copper_wires = false
invisible_pole.draw_circuit_wires = false
invisible_pole.auto_connect_up_to_n_wires = 0

for i = 1, 30 do
  local pole = table.deepcopy(invisible_pole)
  pole.name = "power-propagation-invisible-pole-" .. i
  pole.supply_area_distance = 0.5 + i * 0.5 + range * 0.5
  data:extend({ pole })
end
