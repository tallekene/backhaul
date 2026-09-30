//-----------------------------------------------------------------------------
// Backhaul - https://github.com/tallekene/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Application;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;

//! Where the watch tells us something happened.
//!
//! This runs in its own short-lived process with a much smaller memory budget
//! than the foreground app, which is why everything it touches is tagged
//! (:background). Each callback must end in exactly one Background.exit(), and
//! only after the HTTP round trip has finished - exiting early kills the
//! request in flight.
(:background)
class BackhaulServiceDelegate extends System.ServiceDelegate {

    hidden var mDispatcher as Dispatcher or Null;

    function initialize() {
        ServiceDelegate.initialize();
    }

    //! Fired the moment an activity is saved or discarded, for any activity,
    //! including ones recorded by other Connect IQ apps.
    function onActivityCompleted(
        activity as { :sport as Activity.Sport, :subSport as Activity.SubSport }
    ) as Void {
        if (!enabled("ev_activity")) {
            return;
        }

        var sport    = activity[:sport];
        var subSport = activity[:subSport];

        fire(Payload.EV_ACTIVITY, {
            "sport"          => sport,
            "sport_name"     => Sports.sportName(sport),
            "sub_sport"      => subSport,
            "sub_sport_name" => Sports.subSportName(subSport)
        });
    }

    //! One of the daily goals was met. Registered per goal type, so goalType
    //! tells us which.
    function onGoalReached(goalType as Application.GoalType) as Void {
        if (!enabled("ev_goal")) {
            return;
        }

        fire(Payload.EV_GOAL, {
            "goal"      => goalType,
            "goal_name" => goalName(goalType)
        });
    }

    //! Every thousand steps. Off by default: on a busy day this is a lot of
    //! webhooks && a measurable amount of battery.
    function onSteps() as Void {
        if (!enabled("ev_steps")) {
            return;
        }

        var steps = null;
        if (ActivityMonitor has :getInfo) {
            var info = ActivityMonitor.getInfo();
            if (info != null && info has :steps) {
                steps = info.steps;
            }
        }

        fire(Payload.EV_STEPS, { "steps" => steps });
    }

    //! The watch decided the user went to sleep.
    function onSleepTime() as Void {
        if (!enabled("ev_sleep")) {
            return;
        }
        fire(Payload.EV_SLEEP, null);
    }

    //! ...and woke up again.
    function onWakeTime() as Void {
        if (!enabled("ev_wake")) {
            return;
        }
        fire(Payload.EV_WAKE, null);
    }

    //! The periodic tick. Does double duty: it sends the heartbeat if the user
    //! asked for one, && it is the only thing that ever gets a second go at
    //! events that were queued while the watch was offline.
    function onTemporalEvent() as Void {
        if (!Config.isUsable()) {
            done();
            return;
        }

        if (Config.eventEnabled("ev_heartbeat")) {
            fire(Payload.EV_HEARTBEAT, null);
            return;
        }

        mDispatcher = new Dispatcher(method(:done));
        mDispatcher.drain();
    }

    //! Build && hand off an event, or exit immediately if the app is not
    //! configured well enough to send anything.
    hidden function fire(eventType as Lang.String, data as Lang.Dictionary or Null) as Void {
        if (!Config.isUsable()) {
            done();
            return;
        }

        mDispatcher = new Dispatcher(method(:done));
        mDispatcher.dispatch(Payload.build(eventType, data));
    }

    //! Callback for Dispatcher. Public because method() needs it to be.
    function done() as Void {
        Background.exit(null);
    }

    //! An event type the user switched off still wakes this process, so it has
    //! to be shut down again straight away.
    hidden function enabled(key as Lang.String) as Lang.Boolean {
        if (Config.eventEnabled(key)) {
            return true;
        }
        done();
        return false;
    }

    hidden function goalName(goalType) as Lang.String {
        if (goalType == Application.GOAL_TYPE_STEPS)          { return "steps"; }
        if (goalType == Application.GOAL_TYPE_FLOORS_CLIMBED) { return "floors_climbed"; }
        if (goalType == Application.GOAL_TYPE_ACTIVE_MINUTES) { return "active_minutes"; }
        return "goal_" + goalType.toString();
    }
}
