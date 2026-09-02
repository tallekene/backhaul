//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Application;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

//! Reconciles the background event registrations with the user's settings.
//!
//! Registrations live in the system, not in the app: they survive the app being
//! closed (which is the entire point) and they survive it being updated. So
//! this has to be a reconcile against the current state rather than a set of
//! one-off calls, or a user who turns a setting off gets webhooks forever.
//!
//! This must run in the foreground application process. Calling it from a
//! glance or from the background service does nothing useful.
class EventRegistrar {

    //! Whether this device can run a background service at all. A handful of
    //! older watches in the compatible list cannot, and there is no point
    //! showing the user settings that will never do anything.
    static function isSupported() as Lang.Boolean {
        return System has :ServiceDelegate;
    }

    //! Bring every registration in line with the settings. Idempotent, and
    //! cheap enough to call on every app start and every settings change.
    static function sync() as Void {
        if (!isSupported()) {
            return;
        }

        var on = Config.isUsable();

        setActivity(on and Config.eventEnabled("ev_activity"));
        setGoals(   on and Config.eventEnabled("ev_goal"));
        setSteps(   on and Config.eventEnabled("ev_steps"));
        setSleep(   on and Config.eventEnabled("ev_sleep"));
        setWake(    on and Config.eventEnabled("ev_wake"));
        setTemporal(on and Config.needsTemporalEvent());
    }

    //! Tear everything down. Used when the user disables the app, so that an
    //! app left installed but switched off stops costing battery.
    static function unregisterAll() as Void {
        if (!isSupported()) {
            return;
        }
        setActivity(false);
        setGoals(false);
        setSteps(false);
        setSleep(false);
        setWake(false);
        setTemporal(false);
    }

    hidden static function setActivity(want as Lang.Boolean) as Void {
        if (!(Background has :registerForActivityCompletedEvent)) {
            return;
        }
        var have = Background.getActivityCompletedEventRegistered();
        if (want and !have) {
            Background.registerForActivityCompletedEvent();
        } else if (!want and have) {
            Background.deleteActivityCompletedEvent();
        }
    }

    hidden static function setGoals(want as Lang.Boolean) as Void {
        if (!(Background has :registerForGoalEvent)) {
            return;
        }
        // Built here rather than held as a class constant: Monkey C only
        // accepts literals in a `const`, and these are enum members.
        var goalTypes = [
            Application.GOAL_TYPE_STEPS,
            Application.GOAL_TYPE_FLOORS_CLIMBED,
            Application.GOAL_TYPE_ACTIVE_MINUTES
        ];

        for (var i = 0; i < goalTypes.size(); i += 1) {
            var goalType = goalTypes[i];
            var have = Background.getGoalEventRegistered(goalType);
            if (want and !have) {
                Background.registerForGoalEvent(goalType);
            } else if (!want and have) {
                Background.deleteGoalEvent(goalType);
            }
        }
    }

    hidden static function setSteps(want as Lang.Boolean) as Void {
        if (!(Background has :registerForStepsEvent)) {
            return;
        }
        var have = Background.getStepsEventRegistered();
        if (want and !have) {
            Background.registerForStepsEvent();
        } else if (!want and have) {
            Background.deleteStepsEvent();
        }
    }

    hidden static function setSleep(want as Lang.Boolean) as Void {
        if (!(Background has :registerForSleepEvent)) {
            return;
        }
        var have = Background.getSleepEventRegistered();
        if (want and !have) {
            Background.registerForSleepEvent();
        } else if (!want and have) {
            Background.deleteSleepEvent();
        }
    }

    hidden static function setWake(want as Lang.Boolean) as Void {
        if (!(Background has :registerForWakeEvent)) {
            return;
        }
        var have = Background.getWakeEventRegistered();
        if (want and !have) {
            Background.registerForWakeEvent();
        } else if (!want and have) {
            Background.deleteWakeEvent();
        }
    }

    hidden static function setTemporal(want as Lang.Boolean) as Void {
        if (!(Background has :registerForTemporalEvent)) {
            return;
        }

        var registered = Background.getTemporalEventRegisteredTime();

        if (!want) {
            if (registered != null) {
                Background.deleteTemporalEvent();
            }
            return;
        }

        var wanted = Config.heartbeatMinutes() * 60;

        // getTemporalEventRegisteredTime() hands back the Duration we last
        // registered, so compare the seconds rather than the objects. Only
        // re-register on a real change: re-registering resets the timer, and
        // doing that on every app start would starve the event on a watch the
        // user opens often.
        var current = null;
        if (registered != null and registered has :value) {
            current = registered.value();
        }

        if (current == null or current != wanted) {
            Background.registerForTemporalEvent(new Time.Duration(wanted));
        }
    }
}
