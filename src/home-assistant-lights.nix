{
  # A single apartment-wide colour-temperature slider for the Zigbee bulbs
  # (src/home-assistant.nix, ZHA). Moving the slider retunes every bulb that is
  # currently on; a bulb that is switched on later is brought to the slider's
  # value, so the lights never drift apart. Lights that are off stay off.
  systems.tower.modules = [
    (
      { ... }:
      let
        # Every tunable-white light (ZHA entity ids). All share the IKEA
        # TRADFRI WS range of 2202-4000 K. Add new bulbs here.
        lights = [
          "light.ikea_of_sweden_tradfri_bulb_e14_ws_globe_470lm"
          "light.ikea_of_sweden_tradfri_bulb_e14_ws_globe_470lm_2"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm_2"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm_3"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm_4"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm_5"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm_6"
          "light.ikea_of_sweden_tradfri_bulb_e27_ws_globe_1055lm_7"
          "light.ikea_of_sweden_tradfribulbe27wsglobeopal1055lm"
        ];
        slider = "input_number.light_color_temperature";
        lightsOn = "${builtins.toJSON lights} | select('is_state', 'on') | list";
      in
      {
        services.home-assistant.config = {
          # No `initial`, so the last value is restored across restarts.
          input_number.light_color_temperature = {
            name = "Light temperature";
            icon = "mdi:thermometer-lines";
            min = 2202;
            max = 4000;
            step = 50;
            unit_of_measurement = "K";
            mode = "slider";
          };

          automation = [
            {
              id = "light_color_temperature";
              alias = "Apply light temperature";
              mode = "parallel";
              triggers = [
                {
                  trigger = "state";
                  entity_id = slider;
                  id = "slider";
                }
                {
                  trigger = "state";
                  entity_id = lights;
                  from = "off";
                  to = "on";
                  id = "light_on";
                }
              ];
              # Nothing to retune if the slider moves while every light is off.
              conditions = [
                {
                  condition = "template";
                  value_template = "{{ trigger.id == 'light_on' or (${lightsOn}) | length > 0 }}";
                }
              ];
              actions = [
                {
                  action = "light.turn_on";
                  target.entity_id = ''
                    {% if trigger.id == 'light_on' %}
                      {{ [trigger.entity_id] }}
                    {% else %}
                      {{ ${lightsOn} }}
                    {% endif %}
                  '';
                  data = {
                    color_temp_kelvin = "{{ states('${slider}') | int }}";
                    transition = 1;
                  };
                }
              ];
            }
          ];
        };
      }
    )
  ];
}
