import Toybox.Graphics;
import Toybox.Lang;

//! The colour of each daily figure, the same as on the iPhone and the Apple
//! Watch (`MetricPalette.swift`): steps purple, minutes green, distance blue,
//! calories and the streak orange, the heart rate red.
//!
//! The brand's exact colours. AMOLED watches show them as they are; the
//! 64-colour memory-in-pixel ones (fēnix 7, Forerunner 255…) map each to the
//! nearest colour of their palette, which keeps the hues apart.

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
