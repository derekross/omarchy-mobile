-- SPDX-License-Identifier: MIT
-- Never restore a card's "Voice Call" profile at startup.
--
-- WirePlumber stores a profile the user picked (pactl set-card-profile) and
-- restores it when the card appears. On cheetah "Voice Call" routes the top
-- amplifier alone as the earpiece (omamobile-earpiece@on), so a stored
-- "Voice Call" left media on the handset level with the bottom speaker muted
-- at every boot (2026-10-31, device/cheetah NOTES). A call selects the
-- profile itself and selects HiFi again when it ends. When the stored
-- profile is a Voice Call one, this hook picks the best profile that isn't,
-- as find-best-profile would with nothing stored. (Setting the selection
-- back to nil doesn't clear it, so the hook chooses a profile itself.)

cutils = require ("common-utils")
log = Log.open_topic ("s-device")

SimpleEventHook {
  name = "omamobile/no-voice-call-restore",
  after = { "device/find-stored-profile" },
  before = { "device/apply-profile" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    local stored = event:get_data ("selected-profile")
    if not stored or not string.find (stored.name, "^Voice Call") then
      return
    end
    local device = event:get_subject ()
    if device.properties["device.api"] ~= "alsa" then
      return
    end
    local best = nil
    for p in device:iterate_params ("EnumProfile") do
      local profile = cutils.parseParam (p, "EnumProfile")
      if profile.available ~= "no" and profile.name ~= "off" and
          not string.find (profile.name, "^Voice Call") and
          (not best or profile.priority > best.priority) then
        best = profile
      end
    end
    if best then
      log:notice (device, string.format (
          "not restoring the stored '%s' profile; selecting '%s'", stored.name, best.name))
      event:set_data ("selected-profile", best)
    end
  end
}:register ()
