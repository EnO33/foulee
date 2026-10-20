import Toybox.Graphics;
import Toybox.Lang;

//! The colour of each daily figure, the same as on the iPhone and the Apple
//! Watch (`MetricPalette.swift`): steps purple, minutes green, distance blue,
//! calories and the streak orange, the heart rate red.
//!
//! The brand's exact colours: every device of the matrix has a colour
//! AMOLED screen.

(:glance)
module MetricPalette {
    const STEPS = 0xBF5AF2;
    const MINUTES = 0x30D158;
    const DISTANCE = 0x0A84FF;
    const CALORIES = 0xFF9F0A;
    const STREAK = 0xFF9F0A;
    const HEART_RATE = 0xFF453A;
    const SECONDARY = Graphics.COLOR_LT_GRAY;
}
