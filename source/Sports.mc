//-----------------------------------------------------------------------------
// Backhaul - https://github.com/tallekene/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Lang;

//! Human-readable names for the FIT sport && sub-sport enumerations.
//!
//! The raw integer always travels alongside the name, so a receiver that cares
//! about correctness can map it itself against the FIT profile. This table is a
//! convenience for the common cases && deliberately is not exhaustive:
//! anything past the end comes through as "sport_<n>", which is still
//! unambiguous.
//!
//! Stored as arrays indexed by the enum value rather than dictionaries. Both
//! enumerations are contiguous from zero, an array is a good deal cheaper in
//! the background process's memory budget, && Monkey C will not accept a
//! dictionary literal as a `const` anyway.
(:background)
class Sports {

    hidden static var SPORT_NAMES = [
        "generic", "running", "cycling", "transition", "fitness_equipment",
        "swimming", "basketball", "soccer", "tennis", "american_football",
        "training", "walking", "cross_country_skiing", "alpine_skiing",
        "snowboarding", "rowing", "mountaineering", "hiking", "multisport",
        "paddling", "flying", "e_biking", "motorcycling", "boating", "driving",
        "golf", "hang_gliding", "horseback_riding", "hunting", "fishing",
        "inline_skating", "rock_climbing", "sailing", "ice_skating",
        "sky_diving", "snowshoeing", "snowmobiling", "stand_up_paddleboarding",
        "surfing", "wakeboarding", "water_skiing", "kayaking", "rafting",
        "windsurfing", "kitesurfing", "tactical", "jumpmaster", "boxing",
        "floor_climbing"
    ];

    hidden static var SUB_SPORT_NAMES = [
        "generic", "treadmill", "street", "trail", "track", "spin",
        "indoor_cycling", "road", "mountain", "downhill", "recumbent",
        "cyclocross", "hand_cycling", "track_cycling", "indoor_rowing",
        "elliptical", "stair_climbing", "lap_swimming", "open_water",
        "flexibility_training", "strength_training", "warm_up", "match",
        "exercise", "challenge", "indoor_skiing", "cardio_training",
        "indoor_walking", "e_bike_fitness", "bmx", "casual_walking",
        "speed_walking"
    ];

    static function sportName(id) as Lang.String {
        return lookup(SPORT_NAMES, id, "sport");
    }

    static function subSportName(id) as Lang.String {
        return lookup(SUB_SPORT_NAMES, id, "sub_sport");
    }

    hidden static function lookup(names as Lang.Array, id, prefix as Lang.String) as Lang.String {
        if (id == null) {
            return "unknown";
        }

        var i = null;
        try {
            i = id.toNumber();
        } catch (ex) {
            return prefix + "_unknown";
        }

        if (i == null || i < 0 || i >= names.size()) {
            return prefix + "_" + id.toString();
        }
        return names[i];
    }
}
