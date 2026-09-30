//-----------------------------------------------------------------------------
// Backhaul - https://github.com/tallekene/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Application.Properties;
using Toybox.Communications;
using Toybox.Lang;

//! Read-through access to the application settings.
//!
//! Every getter reads Properties on demand rather than caching. The background
//! service is a separate process that is torn down after each event, so a cache
//! would buy nothing there, && in the foreground it would go stale the moment
//! the user changed a setting from the phone.
(:background, :glance)
class Config {

    //! Garmin refuses to schedule a temporal event more often than this.
    static const MIN_HEARTBEAT_MINUTES = 5;

    //! Read a property, falling back if it is unset or the key is unknown.
    //!
    //! Properties.getValue() throws rather than returning null for a key that
    //! is not in properties.xml, which can happen when a user upgrades from an
    //! older version whose settings have not been re-synced from the phone yet.
    hidden static function raw(key as Lang.String) {
        try {
            return Properties.getValue(key);
        } catch (ex) {
            return null;
        }
    }

    static function getString(key as Lang.String) as Lang.String {
        var v = raw(key);
        if (v == null) {
            return "";
        }
        // toString() rather than an `instanceof Lang.String` cast: the phone
        // settings editor has been known to hand back a Number for a field the
        // user typed digits into.
        return v.toString();
    }

    static function getBool(key as Lang.String, fallback as Lang.Boolean) as Lang.Boolean {
        var v = raw(key);
        if (v == null) {
            return fallback;
        }
        return (v == true);
    }

    static function getNumber(key as Lang.String, fallback as Lang.Number) as Lang.Number {
        var v = raw(key);
        if (v == null) {
            return fallback;
        }
        var n = null;
        try {
            n = v.toNumber();
        } catch (ex) {
            return fallback;
        }
        if (n == null) {
            return fallback;
        }
        return n;
    }

    //! Master switch, plus the one setting without which nothing can work.
    static function isUsable() as Lang.Boolean {
        return getBool("enabled", true) && (url().length() > 0);
    }

    static function url() as Lang.String {
        var u = getString("webhook_url");
        if (u.length() == 0) {
            return u;
        }

        // Trailing spaces survive the phone's settings editor and makeWebRequest
        // rejects the URL without saying why, so trim both ends.
        //
        // Written as scan-then-slice rather than repeated substring calls in a
        // compound condition: the original crashed on device with Out of Bounds
        // because the guard's second operand was evaluated on an empty string.
        var first = 0;
        var last  = u.length();

        while (first < last) {
            if (!u.substring(first, first + 1).equals(" ")) {
                break;
            }
            first += 1;
        }
        while (last > first) {
            if (!u.substring(last - 1, last).equals(" ")) {
                break;
            }
            last -= 1;
        }

        return u.substring(first, last);
    }

    static function deviceLabel() as Lang.String {
        return getString("device_label");
    }

    static function eventEnabled(name as Lang.String) as Lang.Boolean {
        // Activity && goal default on, the noisier ones default off.
        if (name.equals("ev_activity") || name.equals("ev_goal")) {
            return getBool(name, true);
        }
        return getBool(name, false);
    }

    static function heartbeatMinutes() as Lang.Number {
        var m = getNumber("heartbeat_minutes", 60);
        if (m < MIN_HEARTBEAT_MINUTES) {
            m = MIN_HEARTBEAT_MINUTES;
        }
        if (m > 1440) {
            m = 1440;
        }
        return m;
    }

    //! True when a background temporal event is needed at all: either the user
    //! wants heartbeats, or the retry queue needs a periodic chance to drain.
    static function needsTemporalEvent() as Lang.Boolean {
        return eventEnabled("ev_heartbeat") or getBool("queue_enabled", true);
    }

    static function includeLocation() as Lang.Boolean {
        return getBool("include_location", false);
    }

    static function includeHealth() as Lang.Boolean {
        return getBool("include_health", true);
    }

    static function queueEnabled() as Lang.Boolean {
        return getBool("queue_enabled", true);
    }

    //! HTTP headers for every request: content type, plus whichever of the two
    //! optional auth mechanisms the user configured.
    static function headers() as Lang.Dictionary {
        var h = { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON };

        var token = getString("auth_token");
        if (token.length() > 0) {
            h["Authorization"] = "Bearer " + token;
        }

        var hn = getString("header_name");
        var hv = getString("header_value");
        // Length checks rather than .equals(""): comparing against an empty
        // string literal is a known crash-on-device / fine-in-simulator trap.
        if (hn.length() > 0 && hv.length() > 0) {
            h[hn] = hv;
        }

        return h;
    }
}
