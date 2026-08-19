//! Runtime binding for the unsupported MultitouchSupport private framework.
//!
//! No private framework is linked into the final executable: its symbols are
//! resolved only while the engine is enabled. The ABI below follows the widely
//! used reverse-engineered `MTTouch` layout; only normalized x/y are read.

use std::{
    ffi::{c_char, c_int, c_schar, c_void},
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Mutex, OnceLock,
    },
};

use crate::{
    gesture::{Point, TapRecognizer},
    mouse,
};

const FRAMEWORK_PATH: &[u8] =
    b"/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport\0";
const RTLD_LAZY: c_int = 0x1;
const RTLD_LOCAL: c_int = 0x4;

#[repr(C)]
struct MTTouch {
    _frame: i32,
    _timestamp: f64,
    _path_index: i32,
    state: u32,
    _finger_id: i32,
    _hand_id: i32,
    normalized_x: f32,
    normalized_y: f32,
    _normalized_velocity_x: f32,
    _normalized_velocity_y: f32,
    _rest: [u8; 48],
}

const MT_TOUCH_STATE_MAKE_TOUCH: u32 = 3;
const MT_TOUCH_STATE_TOUCHING: u32 = 4;
// Apple's built-in trackpads support far fewer simultaneous contacts than
// this. Keep an explicit upper bound before making a slice from a pointer
// supplied by an unsupported, private ABI.
const MAX_CONTACTS_PER_FRAME: usize = 32;

type DeviceRef = *mut c_void;
type FrameCallback = unsafe extern "C" fn(DeviceRef, *const MTTouch, usize, f64, usize);
type CreateDefaultFn = unsafe extern "C" fn() -> DeviceRef;
type RegisterFrameCallbackFn = unsafe extern "C" fn(DeviceRef, FrameCallback) -> c_schar;
type UnregisterFrameCallbackFn = unsafe extern "C" fn(DeviceRef, FrameCallback) -> c_schar;
type DeviceStartFn = unsafe extern "C" fn(DeviceRef, c_int) -> c_int;
type DeviceStopFn = unsafe extern "C" fn(DeviceRef) -> c_int;
type DeviceReleaseFn = unsafe extern "C" fn(DeviceRef);

#[link(name = "System")]
extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}

pub const STATUS_RUNNING: i32 = 1;
pub const STATUS_FRAMEWORK_UNAVAILABLE: i32 = -1;
pub const STATUS_SYMBOL_UNAVAILABLE: i32 = -2;
pub const STATUS_DEVICE_UNAVAILABLE: i32 = -3;
pub const STATUS_DEVICE_START_FAILED: i32 = -4;
pub const STATUS_CALLBACK_REGISTER_FAILED: i32 = -5;

static RUNNING: AtomicBool = AtomicBool::new(false);
static ACTIVE_CONTACTS: AtomicUsize = AtomicUsize::new(0);
static FRAME_COUNT: AtomicU64 = AtomicU64::new(0);
static MIDDLE_CLICK_COUNT: AtomicU64 = AtomicU64::new(0);
static BINDINGS: OnceLock<Result<Bindings, i32>> = OnceLock::new();
static ENGINE: OnceLock<Mutex<Option<Engine>>> = OnceLock::new();
static RECOGNIZER: OnceLock<Mutex<TapRecognizer>> = OnceLock::new();

struct Bindings {
    // Keep the handle alive for the application's lifetime. Closing a private
    // framework immediately after callback deregistration can race a queued
    // callback on some macOS versions.
    _framework_handle: *mut c_void,
    create: CreateDefaultFn,
    register: RegisterFrameCallbackFn,
    unregister: UnregisterFrameCallbackFn,
    start: DeviceStartFn,
    stop: DeviceStopFn,
    release: DeviceReleaseFn,
}

unsafe impl Send for Bindings {}
unsafe impl Sync for Bindings {}

impl Bindings {
    unsafe fn load() -> Result<Self, i32> {
        let handle = dlopen(FRAMEWORK_PATH.as_ptr().cast(), RTLD_LAZY | RTLD_LOCAL);
        if handle.is_null() {
            return Err(STATUS_FRAMEWORK_UNAVAILABLE);
        }

        let create = symbol::<CreateDefaultFn>(handle, b"MTDeviceCreateDefault\0")
            .ok_or(STATUS_SYMBOL_UNAVAILABLE)?;
        let register =
            symbol::<RegisterFrameCallbackFn>(handle, b"MTRegisterContactFrameCallback\0")
                .ok_or(STATUS_SYMBOL_UNAVAILABLE)?;
        let unregister =
            symbol::<UnregisterFrameCallbackFn>(handle, b"MTUnregisterContactFrameCallback\0")
                .ok_or(STATUS_SYMBOL_UNAVAILABLE)?;
        let start =
            symbol::<DeviceStartFn>(handle, b"MTDeviceStart\0").ok_or(STATUS_SYMBOL_UNAVAILABLE)?;
        let stop =
            symbol::<DeviceStopFn>(handle, b"MTDeviceStop\0").ok_or(STATUS_SYMBOL_UNAVAILABLE)?;
        let release = symbol::<DeviceReleaseFn>(handle, b"MTDeviceRelease\0")
            .ok_or(STATUS_SYMBOL_UNAVAILABLE)?;

        Ok(Self {
            _framework_handle: handle,
            create,
            register,
            unregister,
            start,
            stop,
            release,
        })
    }
}

struct Engine {
    bindings: &'static Bindings,
    device: DeviceRef,
}

unsafe impl Send for Engine {}

impl Engine {
    unsafe fn new() -> Result<Self, i32> {
        let bindings = bindings()?;

        let device = (bindings.create)();
        if device.is_null() {
            return Err(STATUS_DEVICE_UNAVAILABLE);
        }

        if (bindings.register)(device, contact_frame_callback) == 0 {
            (bindings.release)(device);
            return Err(STATUS_CALLBACK_REGISTER_FAILED);
        }
        if (bindings.start)(device, 0) != 0 {
            let _ = (bindings.unregister)(device, contact_frame_callback);
            (bindings.release)(device);
            return Err(STATUS_DEVICE_START_FAILED);
        }

        Ok(Self { bindings, device })
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        unsafe {
            let _ = (self.bindings.stop)(self.device);
            let _ = (self.bindings.unregister)(self.device, contact_frame_callback);
            (self.bindings.release)(self.device);
        }
    }
}

fn bindings() -> Result<&'static Bindings, i32> {
    BINDINGS
        .get_or_init(|| unsafe { Bindings::load() })
        .as_ref()
        .map_err(|status| *status)
}

unsafe fn symbol<T: Copy>(handle: *mut c_void, name: &'static [u8]) -> Option<T> {
    let raw = dlsym(handle, name.as_ptr().cast());
    (!raw.is_null()).then(|| std::mem::transmute_copy(&raw))
}

pub fn start() -> i32 {
    let engine = ENGINE.get_or_init(|| Mutex::new(None));
    let mut engine = engine.lock().unwrap_or_else(|e| e.into_inner());
    if RUNNING.load(Ordering::Acquire) {
        return STATUS_RUNNING;
    }

    {
        let mut recognizer = recognizer().lock().unwrap_or_else(|e| e.into_inner());
        *recognizer = TapRecognizer::default();
    }
    ACTIVE_CONTACTS.store(0, Ordering::Release);
    FRAME_COUNT.store(0, Ordering::Release);
    MIDDLE_CLICK_COUNT.store(0, Ordering::Release);
    // MTDeviceStart may synchronously deliver its first frame, so callbacks
    // must be accepted before entering the private framework.
    RUNNING.store(true, Ordering::Release);

    match unsafe { Engine::new() } {
        Ok(new_engine) => {
            *engine = Some(new_engine);
            STATUS_RUNNING
        }
        Err(status) => {
            RUNNING.store(false, Ordering::Release);
            status
        }
    }
}

pub fn stop() {
    if !RUNNING.swap(false, Ordering::AcqRel) {
        return;
    }
    ACTIVE_CONTACTS.store(0, Ordering::Release);
    if let Some(engine) = ENGINE.get() {
        let mut engine = engine.lock().unwrap_or_else(|e| e.into_inner());
        drop(engine.take());
    }
    let mut recognizer = recognizer().lock().unwrap_or_else(|e| e.into_inner());
    *recognizer = TapRecognizer::default();
}

pub fn is_running() -> bool {
    RUNNING.load(Ordering::Acquire)
}

pub fn active_contact_count() -> usize {
    ACTIVE_CONTACTS.load(Ordering::Acquire)
}

pub fn frame_count() -> u64 {
    FRAME_COUNT.load(Ordering::Acquire)
}

pub fn middle_click_count() -> u64 {
    MIDDLE_CLICK_COUNT.load(Ordering::Acquire)
}

pub fn cancel_gesture() {
    let mut recognizer = recognizer().lock().unwrap_or_else(|e| e.into_inner());
    recognizer.cancel();
}

pub fn record_physical_middle_click() {
    MIDDLE_CLICK_COUNT.fetch_add(1, Ordering::Relaxed);
}

fn recognizer() -> &'static Mutex<TapRecognizer> {
    RECOGNIZER.get_or_init(|| Mutex::new(TapRecognizer::default()))
}

unsafe extern "C" fn contact_frame_callback(
    _device: DeviceRef,
    touches: *const MTTouch,
    count: usize,
    timestamp: f64,
    _frame: usize,
) {
    if !RUNNING.load(Ordering::Acquire) || (count != 0 && touches.is_null()) {
        return;
    }

    FRAME_COUNT.fetch_add(1, Ordering::Relaxed);

    if count > MAX_CONTACTS_PER_FRAME {
        ACTIVE_CONTACTS.store(0, Ordering::Release);
        let mut recognizer = recognizer().lock().unwrap_or_else(|e| e.into_inner());
        recognizer.cancel();
        return;
    }

    let result = std::panic::catch_unwind(|| {
        let all_touches = if count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(touches, count) }
        };
        let points: Vec<Point> = all_touches
            .iter()
            .filter(|touch| {
                matches!(
                    touch.state,
                    MT_TOUCH_STATE_MAKE_TOUCH | MT_TOUCH_STATE_TOUCHING
                )
            })
            .map(|touch| Point {
                x: touch.normalized_x,
                y: touch.normalized_y,
            })
            .collect();

        ACTIVE_CONTACTS.store(points.len(), Ordering::Release);

        let mut recognizer = recognizer().lock().unwrap_or_else(|e| e.into_inner());
        recognizer.observe(timestamp, &points)
    });

    if matches!(result, Ok(true)) && RUNNING.load(Ordering::Acquire) {
        mouse::post_middle_click();
        MIDDLE_CLICK_COUNT.fetch_add(1, Ordering::Relaxed);
    }
}

#[allow(dead_code)]
fn _assert_touch_layout() {
    debug_assert_eq!(std::mem::size_of::<MTTouch>(), 96);
    debug_assert_eq!(std::mem::offset_of!(MTTouch, normalized_x), 32);
}
