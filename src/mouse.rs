//! Middle-click generation through the public Core Graphics API.

use std::ffi::c_void;

#[repr(C)]
#[derive(Clone, Copy)]
struct CGPoint {
    x: f64,
    y: f64,
}

type CGEventRef = *mut c_void;

#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn CGEventCreate(source: *const c_void) -> CGEventRef;
    fn CGEventGetLocation(event: CGEventRef) -> CGPoint;
    fn CGEventCreateMouseEvent(
        source: *const c_void,
        mouse_type: u32,
        mouse_cursor_position: CGPoint,
        mouse_button: u32,
    ) -> CGEventRef;
    fn CGEventSetIntegerValueField(event: CGEventRef, field: u32, value: i64);
    fn CGEventPost(tap: u32, event: CGEventRef);
    fn CFRelease(cf: *const c_void);
}

const KCG_HID_EVENT_TAP: u32 = 0;
const KCG_EVENT_OTHER_MOUSE_DOWN: u32 = 25;
const KCG_EVENT_OTHER_MOUSE_UP: u32 = 26;
const KCG_MOUSE_BUTTON_CENTER: u32 = 2;
const KCG_EVENT_SOURCE_USER_DATA: u32 = 42;
/// "3FMC", shared with the Swift input tap to avoid processing our own events.
const SYNTHETIC_EVENT_MARKER: i64 = 0x3346_4D43;

/// Posts a down/up pair at the current pointer location. macOS may require the
/// user to allow this app in Privacy & Security > Accessibility.
pub fn post_middle_click() {
    unsafe {
        let current = CGEventCreate(std::ptr::null());
        if current.is_null() {
            return;
        }
        let location = CGEventGetLocation(current);
        CFRelease(current);

        for event_type in [KCG_EVENT_OTHER_MOUSE_DOWN, KCG_EVENT_OTHER_MOUSE_UP] {
            let event = CGEventCreateMouseEvent(
                std::ptr::null(),
                event_type,
                location,
                KCG_MOUSE_BUTTON_CENTER,
            );
            if !event.is_null() {
                CGEventSetIntegerValueField(
                    event,
                    KCG_EVENT_SOURCE_USER_DATA,
                    SYNTHETIC_EVENT_MARKER,
                );
                CGEventPost(KCG_HID_EVENT_TAP, event);
                CFRelease(event);
            }
        }
    }
}
