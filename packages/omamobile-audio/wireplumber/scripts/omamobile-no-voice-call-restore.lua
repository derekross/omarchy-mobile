-- SPDX-License-Identifier: MIT
-- Never restore the AoC card's "Voice Call" profile at startup.
--
-- WirePlumber stores a profile the user picked (pactl set-card-profile) and
-- restores it when the card appears. "Voice Call" routes the top amplifier
-- alone as the earpiece (omamobile-earpiece@on), so a stored "Voice Call"
-- left media on the handset level with the bottom speaker muted at every
-- boot (2026-10-31, device/cheetah NOTES). A call selects the profile itself
-- and selects HiFi again when it ends; at startup the card always gets the
-- profile WirePlumber would pick with nothing stored.

log = Log.open_topic ("s-device")

SimpleEventHook {
  name = "omamobile/no-voice-call-restore",
  after = "device/find-stored-profile",
  before = { "device/find-preferred-profile", "device/find-best-profile", "device/apply-profile" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    local profile = event:get_data ("selected-profile")
    if not profile or profile.name ~= "Voice Call" then
      return
    end
    local device = event:get_subject ()
    if device.properties["api.alsa.card.name"] ~= "google,aoc-snd-card" then
      return
    end
    log:info (device, "not restoring the stored 'Voice Call' profile")
    event:set_data ("selected-profile", nil)
  end
}:register ()
