//! Pure, platform-independent recognition of a three-finger tap.

/// A three-finger gesture must finish within this time.
pub const TAP_TIMEOUT_MS: f64 = 220.0;
/// Largest allowed movement of the three-finger centroid in MultitouchSupport's
/// normalized (0...1) coordinate space.
pub const MAX_MOVEMENT: f32 = 0.020;
/// Minimum interval between generated middle clicks.
pub const DEBOUNCE_MS: f64 = 180.0;
/// Fingers rarely leave a physical trackpad in the exact same hardware frame.
/// Allow a short spread between the first and last release.
pub const MAX_RELEASE_SPREAD_MS: f64 = 80.0;
/// Upward mouse travel required while the middle button is held.
pub const MOUSE_SWIPE_UP_THRESHOLD: f64 = 80.0;
/// Largest movement still treated as a normal middle click.
pub const MOUSE_CLICK_SLOP: f64 = 8.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

#[derive(Debug, Default)]
pub struct TapRecognizer {
    started_at: Option<f64>,
    reached_three: bool,
    start_center: Point,
    max_movement: f32,
    release_started_at: Option<f64>,
    invalid: bool,
    last_click_at: Option<f64>,
}

#[derive(Debug, Default)]
pub struct MouseSwipeRecognizer {
    active: bool,
    accumulated_x: f64,
    accumulated_up: f64,
    max_distance: f64,
    triggered: bool,
}

impl MouseSwipeRecognizer {
    pub fn begin(&mut self) {
        self.active = true;
        self.accumulated_x = 0.0;
        self.accumulated_up = 0.0;
        self.max_distance = 0.0;
        self.triggered = false;
    }

    /// Observes relative pointer movement, with positive `delta_up` meaning an
    /// upward movement. Returns true once when the gesture crosses its
    /// threshold with a predominantly vertical direction.
    pub fn observe(&mut self, delta_x: f64, delta_up: f64) -> bool {
        if !self.active || self.triggered {
            return false;
        }

        self.accumulated_x += delta_x;
        self.accumulated_up += delta_up;
        self.max_distance = self.max_distance.max(
            (self.accumulated_x * self.accumulated_x + self.accumulated_up * self.accumulated_up)
                .sqrt(),
        );

        if self.accumulated_up >= MOUSE_SWIPE_UP_THRESHOLD
            && self.accumulated_up >= self.accumulated_x.abs()
        {
            self.triggered = true;
            return true;
        }
        false
    }

    /// Finishes the candidate and returns true when it should be replayed as a
    /// normal middle click.
    pub fn finish(&mut self) -> bool {
        let should_click = self.active && !self.triggered && self.max_distance <= MOUSE_CLICK_SLOP;
        self.reset();
        should_click
    }

    pub fn cancel(&mut self) {
        self.reset();
    }

    fn reset(&mut self) {
        *self = Self::default();
    }
}

impl Default for Point {
    fn default() -> Self {
        Self { x: 0.0, y: 0.0 }
    }
}

impl TapRecognizer {
    /// Cancels the in-progress gesture while keeping it blocked until release.
    pub fn cancel(&mut self) {
        if self.started_at.is_some() {
            self.invalid = true;
        }
    }

    /// Processes one contact frame. `timestamp` must be monotonic and expressed
    /// in seconds (the unit supplied by MultitouchSupport).
    ///
    /// Returns true exactly once when a qualifying gesture has completely ended.
    pub fn observe(&mut self, timestamp: f64, contacts: &[Point]) -> bool {
        match contacts.len() {
            0 => self.finish(timestamp),
            3 => self.observe_three(timestamp, contacts),
            1 | 2 => {
                self.begin_if_needed(timestamp);
                if self.reached_three && self.release_started_at.is_none() {
                    self.release_started_at = Some(timestamp);
                }
                false
            }
            _ => {
                self.begin_if_needed(timestamp);
                // Remember a fourth touch even if the device skipped directly
                // from two contacts to four in adjacent frames.
                self.invalid = true;
                false
            }
        }
    }

    fn observe_three(&mut self, timestamp: f64, contacts: &[Point]) -> bool {
        self.begin_if_needed(timestamp);
        let center = centroid(contacts);
        if self.release_started_at.is_some() {
            // A finger returning after release began is not a tap.
            self.invalid = true;
            return false;
        }
        if !self.reached_three {
            self.reached_three = true;
            self.start_center = center;
            self.max_movement = 0.0;
            return false;
        }

        let dx = center.x - self.start_center.x;
        let dy = center.y - self.start_center.y;
        self.max_movement = self.max_movement.max((dx * dx + dy * dy).sqrt());
        false
    }

    fn begin_if_needed(&mut self, timestamp: f64) {
        if self.started_at.is_none() {
            self.started_at = Some(timestamp);
            self.reached_three = false;
            self.max_movement = 0.0;
            self.release_started_at = None;
            self.invalid = false;
        }
    }

    fn finish(&mut self, timestamp: f64) -> bool {
        let Some(started_at) = self.started_at.take() else {
            return false;
        };

        let elapsed_ms = (timestamp - started_at) * 1_000.0;
        let passed = self.reached_three
            && !self.invalid
            && (0.0..=TAP_TIMEOUT_MS).contains(&elapsed_ms)
            && self.release_started_at.is_none_or(|release_started_at| {
                (0.0..=MAX_RELEASE_SPREAD_MS)
                    .contains(&((timestamp - release_started_at) * 1_000.0))
            })
            && self.max_movement <= MAX_MOVEMENT
            && self
                .last_click_at
                .is_none_or(|last| (timestamp - last) * 1_000.0 >= DEBOUNCE_MS);

        if passed {
            self.last_click_at = Some(timestamp);
        }
        self.reached_three = false;
        self.max_movement = 0.0;
        self.release_started_at = None;
        self.invalid = false;
        passed
    }
}

fn centroid(contacts: &[Point]) -> Point {
    debug_assert_eq!(contacts.len(), 3);
    let (x, y) = contacts
        .iter()
        .fold((0.0, 0.0), |(x, y), point| (x + point.x, y + point.y));
    Point {
        x: x / contacts.len() as f32,
        y: y / contacts.len() as f32,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const THREE: [Point; 3] = [
        Point { x: 0.3, y: 0.3 },
        Point { x: 0.5, y: 0.5 },
        Point { x: 0.7, y: 0.7 },
    ];

    #[test]
    fn recognizes_a_short_stationary_three_finger_tap() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &THREE));
        assert!(!recognizer.observe(1.1, &THREE));
        assert!(recognizer.observe(1.15, &[]));
    }

    #[test]
    fn rejects_taps_that_move_too_far() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &THREE));
        let moved = [
            Point { x: 0.4, y: 0.3 },
            Point { x: 0.6, y: 0.5 },
            Point { x: 0.8, y: 0.7 },
        ];
        assert!(!recognizer.observe(1.1, &moved));
        assert!(!recognizer.observe(1.15, &[]));
    }

    #[test]
    fn rejects_four_fingers_and_accepts_a_quick_sequential_release() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &THREE));
        assert!(!recognizer.observe(1.05, &[Point::default(); 4]));
        assert!(!recognizer.observe(1.1, &[]));

        assert!(!recognizer.observe(2.0, &THREE));
        assert!(!recognizer.observe(2.05, &[Point::default(); 2]));
        assert!(recognizer.observe(2.1, &[]));
    }

    #[test]
    fn rejects_a_release_spread_that_is_too_long() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &THREE));
        assert!(!recognizer.observe(1.05, &[Point::default(); 2]));
        assert!(!recognizer.observe(1.14, &[]));
    }

    #[test]
    fn rejects_a_finger_returning_during_release() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &THREE));
        assert!(!recognizer.observe(1.05, &[Point::default(); 2]));
        assert!(!recognizer.observe(1.07, &THREE));
        assert!(!recognizer.observe(1.1, &[]));
    }

    #[test]
    fn rejects_a_two_finger_tap_while_another_finger_is_held() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &[Point::default()]));
        assert!(!recognizer.observe(2.0, &THREE));
        assert!(!recognizer.observe(2.1, &[]));
    }

    #[test]
    fn rejects_four_fingers_even_if_the_first_three_frame_was_skipped() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &[Point::default(); 2]));
        assert!(!recognizer.observe(1.02, &[Point::default(); 4]));
        assert!(!recognizer.observe(1.04, &THREE));
        assert!(!recognizer.observe(1.1, &[]));
    }

    #[test]
    fn allows_fingers_to_arrive_across_adjacent_frames() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &[THREE[0]]));
        assert!(!recognizer.observe(1.02, &THREE[..2]));
        assert!(!recognizer.observe(1.04, &THREE));
        assert!(recognizer.observe(1.15, &[]));
    }

    #[test]
    fn rejects_slow_and_debounced_taps() {
        let mut recognizer = TapRecognizer::default();
        assert!(!recognizer.observe(1.0, &THREE));
        assert!(!recognizer.observe(1.23, &[]));

        assert!(!recognizer.observe(2.0, &THREE));
        assert!(recognizer.observe(2.1, &[]));
        assert!(!recognizer.observe(2.15, &THREE));
        assert!(!recognizer.observe(2.2, &[]));
    }

    #[test]
    fn mouse_swipe_triggers_at_eighty_points_but_not_seventy_nine() {
        let mut recognizer = MouseSwipeRecognizer::default();
        recognizer.begin();
        assert!(!recognizer.observe(0.0, 79.0));
        assert!(recognizer.observe(0.0, 1.0));
    }

    #[test]
    fn mouse_swipe_rejects_downward_and_horizontal_dominant_motion() {
        let mut recognizer = MouseSwipeRecognizer::default();
        recognizer.begin();
        assert!(!recognizer.observe(0.0, -120.0));
        assert!(!recognizer.finish());

        recognizer.begin();
        assert!(!recognizer.observe(81.0, 80.0));
        assert!(!recognizer.finish());
    }

    #[test]
    fn mouse_swipe_triggers_only_once_until_reset() {
        let mut recognizer = MouseSwipeRecognizer::default();
        recognizer.begin();
        assert!(recognizer.observe(0.0, 80.0));
        assert!(!recognizer.observe(0.0, 80.0));
        assert!(!recognizer.finish());

        recognizer.begin();
        assert!(recognizer.observe(0.0, 80.0));
    }

    #[test]
    fn mouse_swipe_preserves_only_clicks_inside_the_slop() {
        let mut recognizer = MouseSwipeRecognizer::default();
        recognizer.begin();
        assert!(!recognizer.observe(4.0, 4.0));
        assert!(recognizer.finish());

        recognizer.begin();
        assert!(!recognizer.observe(9.0, 0.0));
        assert!(!recognizer.finish());
    }

    #[test]
    fn mouse_swipe_cancel_clears_the_candidate() {
        let mut recognizer = MouseSwipeRecognizer::default();
        recognizer.begin();
        assert!(!recognizer.observe(0.0, 40.0));
        recognizer.cancel();
        assert!(!recognizer.observe(0.0, 40.0));
        assert!(!recognizer.finish());
    }
}
