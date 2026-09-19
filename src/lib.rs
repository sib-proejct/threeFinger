//! C ABI exported to the small Swift menu-bar application.

use std::sync::{Mutex, OnceLock};

mod gesture;
mod mouse;
mod multitouch;

use gesture::{AutoScrollEngine, MouseSwipeRecognizer};

static MOUSE_SWIPE_RECOGNIZER: OnceLock<Mutex<MouseSwipeRecognizer>> = OnceLock::new();
static AUTO_SCROLL_ENGINE: OnceLock<Mutex<AutoScrollEngine>> = OnceLock::new();

fn mouse_swipe_recognizer() -> &'static Mutex<MouseSwipeRecognizer> {
    MOUSE_SWIPE_RECOGNIZER.get_or_init(|| Mutex::new(MouseSwipeRecognizer::default()))
}

fn auto_scroll_engine() -> &'static Mutex<AutoScrollEngine> {
    AUTO_SCROLL_ENGINE.get_or_init(|| Mutex::new(AutoScrollEngine::default()))
}

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

/// Begins tracking a physical middle-button gesture.
#[no_mangle]
pub extern "C" fn tmc_mouse_gesture_begin() {
    let mut recognizer = mouse_swipe_recognizer()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    recognizer.begin();
}

/// Observes relative mouse movement. `delta_up` is positive when moving up.
/// Returns a gesture action code:
/// - 0: None
/// - 1: Mission Control (Up)
/// - 2: Next Space / Desktop (Left)
/// - 3: Previous Space / Desktop (Right)
#[no_mangle]
pub extern "C" fn tmc_mouse_gesture_observe(delta_x: f64, delta_up: f64) -> i32 {
    let mut recognizer = mouse_swipe_recognizer()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    recognizer.observe(delta_x, delta_up) as i32
}

/// Ends tracking. Returns 1 when the input should be replayed as a click.
#[no_mangle]
pub extern "C" fn tmc_mouse_gesture_end() -> i32 {
    let mut recognizer = mouse_swipe_recognizer()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    i32::from(recognizer.finish())
}

/// Cancels an in-progress middle-button gesture.
#[no_mangle]
pub extern "C" fn tmc_mouse_gesture_cancel() {
    let mut recognizer = mouse_swipe_recognizer()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    recognizer.cancel();
}

/// Starts a new middle-button automatic-scroll session.
#[no_mangle]
pub extern "C" fn tmc_auto_scroll_begin() {
    let mut engine = auto_scroll_engine()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    engine.begin();
}

/// Computes whole-pixel scroll deltas for one timer frame.
/// Positive offsets point right/down. Horizontal output uses the opposite sign;
/// vertical output uses the same sign. Null output pointers are allowed.
#[no_mangle]
pub extern "C" fn tmc_auto_scroll_step(
    offset_x: f64,
    offset_y: f64,
    elapsed_seconds: f64,
    out_x: *mut i32,
    out_y: *mut i32,
) {
    let mut engine = auto_scroll_engine()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let (delta_x, delta_y) = engine.step(offset_x, offset_y, elapsed_seconds);
    unsafe {
        if let Some(out_x) = out_x.as_mut() {
            *out_x = delta_x;
        }
        if let Some(out_y) = out_y.as_mut() {
            *out_y = delta_y;
        }
    }
}

/// Ends automatic scrolling and clears fractional state.
#[no_mangle]
pub extern "C" fn tmc_auto_scroll_end() {
    let mut engine = auto_scroll_engine()
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    engine.end();
}
