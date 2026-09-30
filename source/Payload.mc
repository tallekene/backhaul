//-----------------------------------------------------------------------------
// Backhaul - https://github.com/tallekene/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;

//! Builds the JSON body of a webhook.
//!
//! The shape is documented in docs/PAYLOAD.md && versioned by the "schema"
//! field. Optional blocks are omitted entirely rather than sent as nulls, so a
//! receiver can treat "key present" as "watch had a value for this".
(:background)
class Payload {

    static const SCHEMA_VERSION = 1;

    static const EV_ACTIVITY  = "activity.completed";
    static const EV_GOAL      = "goal.reached";
    static const EV_STEPS     = "steps.milestone";
    static const EV_SLEEP     = "sleep.start";
    static const EV_WAKE      = "wake";
    static const EV_HEARTBEAT = "heartbeat";
    static const EV_TEST      = "test";

    //! Assemble an event.
    //!
    //! @param eventType One of the EV_* constants.
    //! @param data      Event-specific fields, or null for events that carry none.
    //!
    //! @return A dictionary ready to hand to makeWebRequest, minus the delivery
    //!         metadata that Dispatcher stamps on at send time.
    static function build(eventType as Lang.String, data as Lang.Dictionary or Null) as Lang.Dictionary {
        var moment = Time.now();
        var now = moment.value();
        var day = Gregorian.info(moment, Time.FORMAT_SHORT);

        var event = {
            "schema"       => SCHEMA_VERSION,
            "event"        => eventType,
            "id"           => eventId(eventType, now),
            "ts"           => now,
            "local_date"   => Lang.format("$1$-$2$-$3$", [day.year, (day.month as Lang.Number).format("%02d"), day.day.format("%02d")]),
            "utc_offset_s" => System.getClockTime().timeZoneOffset,
            "device"       => deviceBlock()
        };

        if (data != null) {
            event["data"] = data;
        }

        if (Config.includeHealth()) {
            var health = healthBlock();
            if (health.size() > 0) {
                event["health"] = health;
            }
        }

        if (Config.includeLocation()) {
            var loc = locationBlock();
            if (loc != null) {
                event["location"] = loc;
            }
        }

        return event;
    }

    //! A key the receiver can deduplicate on. Retries of the same event reuse
    //! it, so a receiver that processes an event twice (because our request
    //! succeeded but the response never made it back to the watch) can tell.
    hidden static function eventId(eventType as Lang.String, now as Lang.Number) as Lang.String {
        var salt = Math.rand() % 100000;
        return eventType + "-" + now.toString() + "-" + salt.format("%05d");
    }

    hidden static function deviceBlock() as Lang.Dictionary {
        var settings = System.getDeviceSettings();
        var stats    = System.getSystemStats();

        var device = {};

        var label = Config.deviceLabel();
        if (label.length() > 0) {
            device["label"] = label;
        }

        if (settings has :partNumber && settings.partNumber != null) {
            device["part_number"] = settings.partNumber;
        }
        if (settings has :monkeyVersion && settings.monkeyVersion != null) {
            var v = settings.monkeyVersion;
            device["ciq_version"] = v[0].toString() + "." + v[1].toString() + "." + v[2].toString();
        }
        if (settings has :phoneConnected) {
            device["phone_connected"] = settings.phoneConnected;
        }
        if (stats has :battery && stats.battery != null) {
            // One decimal is all the watch actually resolves.
            device["battery"] = Math.round(stats.battery * 10) / 10.0;
        }
        if (stats has :charging && stats.charging != null) {
            device["charging"] = stats.charging;
        }

        return device;
    }

    hidden static function healthBlock() as Lang.Dictionary {
        var health = {};

        if (!(ActivityMonitor has :getInfo)) {
            return health;
        }

        // No null guard: getInfo() is declared non-nullable, && the compiler
        // rejects the check as unreachable.
        var info = ActivityMonitor.getInfo();

        // Monkey C has no reflection: `has` can test for a field but there is
        // no way to read one by symbol, so each of these is spelled out.
        if (info has :steps && info.steps != null) {
            health["steps"] = info.steps;
        }
        if (info has :stepGoal && info.stepGoal != null) {
            health["step_goal"] = info.stepGoal;
        }
        if (info has :calories && info.calories != null) {
            health["calories"] = info.calories;
        }
        if (info has :distance && info.distance != null) {
            health["distance_cm"] = info.distance;
        }
        if (info has :floorsClimbed && info.floorsClimbed != null) {
            health["floors_climbed"] = info.floorsClimbed;
        }
        if (info has :floorsClimbedGoal && info.floorsClimbedGoal != null) {
            health["floors_goal"] = info.floorsClimbedGoal;
        }

        // activeMinutesDay is an object, not a scalar, so it needs unwrapping.
        if (info has :activeMinutesDay && info.activeMinutesDay != null) {
            var am = info.activeMinutesDay;
            if (am has :total && am.total != null) {
                health["active_minutes"] = am.total;
            }
        }

        // Heart rate is only meaningful when the optical sensor has a recent
        // reading; outside an activity it is frequently null.
        if (Activity has :getActivityInfo) {
            var act = Activity.getActivityInfo();
            if (act != null && act has :currentHeartRate && act.currentHeartRate != null) {
                health["heart_rate"] = act.currentHeartRate;
            }
        }

        return health;
    }

    hidden static function locationBlock() as Lang.Dictionary or Null {
        if (!(Position has :getInfo)) {
            return null;
        }

        var pos = Position.getInfo();
        if (pos == null || pos.accuracy == null || pos.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return null;
        }

        var loc = { "quality" => qualityName(pos.accuracy) };

        if (pos.position != null) {
            var deg = pos.position.toDegrees();
            loc["lat"] = deg[0];
            loc["lon"] = deg[1];
        }
        if (pos.altitude != null) {
            loc["altitude_m"] = Math.round(pos.altitude);
        }
        if (pos.speed != null) {
            loc["speed_mps"] = Math.round(pos.speed * 10) / 10.0;
        }
        if (pos.heading != null) {
            var deg = Math.round(pos.heading * 180 / Math.PI);
            while (deg < 0) {
                deg += 360;
            }
            loc["heading_deg"] = deg % 360;
        }

        return loc;
    }

    //! Deliberately reports the fix quality as a name rather than inventing a
    //! metre figure for it. Garmin gives four buckets && no error estimate;
    //! turning "poor" into "100 m" would be a number the receiver could not
    //! legitimately do arithmetic on.
    hidden static function qualityName(accuracy) as Lang.String {
        if (accuracy == Position.QUALITY_GOOD)       { return "good"; }
        if (accuracy == Position.QUALITY_USABLE)     { return "usable"; }
        if (accuracy == Position.QUALITY_POOR)       { return "poor"; }
        if (accuracy == Position.QUALITY_LAST_KNOWN) { return "last_known"; }
        return "unavailable";
    }
}
