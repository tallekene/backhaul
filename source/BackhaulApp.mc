//-----------------------------------------------------------------------------
// Backhaul - https://github.com/laemmlein/backhaul
// Distributed under the MIT Licence. See LICENSE.
//-----------------------------------------------------------------------------

using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

//! Entry point.
//!
//! The app itself does very little: it exists so that the user has somewhere to
//! see what is going on, and - crucially - so that the background events get
//! registered. Garmin will not let a background service register itself, which
//! is why the app has to be opened once after installing or changing settings
//! before anything is sent.
class BackhaulApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary or Null) as Void {
        EventRegistrar.sync();
    }

    function onStop(state as Lang.Dictionary or Null) as Void {
    }

    function getInitialView() {
        var view = new StatusView();
        return [view, new StatusDelegate(view)];
    }

    function getGlanceView() {
        return [new BackhaulGlanceView()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new BackhaulServiceDelegate()];
    }

    //! Settings edited on the phone arrive here. Re-reconciling immediately
    //! means turning an event off takes effect without the user having to
    //! remember to reopen the app.
    function onSettingsChanged() as Void {
        EventRegistrar.sync();
        WatchUi.requestUpdate();
    }
}
