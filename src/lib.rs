//! C ABI exported to the small Swift menu-bar application.

mod gesture;
mod mouse;
mod multitouch;

/// Starts the global three-finger-tap listener.
///
/// Returns `1` on success, otherwise a negative `tmc_status_*` error code.
#[no_mangle]
pub extern "C" fn tmc_start() -> i32 {
    multitouch::start()
}

/// Stops the listener. Safe to call more than once.
#[no_mangle]
pub extern "C" fn tmc_stop() {
    multitouch::stop();
}

/// Returns `1` while the listener is active and `0` otherwise.
#[no_mangle]
pub extern "C" fn tmc_is_running() -> i32 {
    i32::from(multitouch::is_running())
}

/// Returns the current number of active trackpad contacts.
#[no_mangle]
pub extern "C" fn tmc_active_contact_count() -> u32 {
    multitouch::active_contact_count() as u32
}

/// Returns the number of raw contact frames received since the engine started.
#[no_mangle]
pub extern "C" fn tmc_frame_count() -> u64 {
    multitouch::frame_count()
}

/// Returns the number of generated middle clicks since the engine started.
#[no_mangle]
pub extern "C" fn tmc_middle_click_count() -> u64 {
    multitouch::middle_click_count()
}

/// Cancels tap recognition for the current contact sequence.
#[no_mangle]
pub extern "C" fn tmc_cancel_gesture() {
    multitouch::cancel_gesture();
}

/// Records a physical three-finger click converted by the Swift event tap.
#[no_mangle]
pub extern "C" fn tmc_record_physical_middle_click() {
    multitouch::record_physical_middle_click();
}
