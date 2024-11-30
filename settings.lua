data:extend({
  {
    type = "int-setting",
    name = "power-propagation-range",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0,
    maximum_value = 10,
    order = "a",
  },
  {
    type = "bool-setting",
    name = "power-propagation-through-walls",
    setting_type = "startup",
    default_value = false,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "power-propagation-through-rails",
    setting_type = "startup",
    default_value = false,
    order = "c",
  },
})
