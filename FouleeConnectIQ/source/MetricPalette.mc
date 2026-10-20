import Toybox.Graphics;
import Toybox.Lang;

//! The colour of each daily figure, the same as on the iPhone and the Apple
//! Watch (`MetricPalette.swift`): steps purple, minutes green, distance blue,
//! calories and the streak orange, the
//! heart rate red.
//!
//! Three variants, one per kind of screen, picked at compile time by the
//! `excludeAnnotations` of monkey.jungle: the brand's exact colours on AMOLED,
//! the nearest system colours on memory-in-pixel screens (their palette has no
//! room for the brand's shades), white on the monochrome ones.

(:glance :amoled)
module MetricPalette {
    const STEPS = 0xBF5AF2;
    const MINUTES = 0x30D158;
    const DISTANCE = 0x0A84FF;
    const CALORIES = 0xFF9F0A;
    const STREAK = 0xFF9F0A;
    const HEART_RATE = 0xFF453A;
    const SECONDARY = Graphics.COLOR_LT_GRAY;
}

(:glance :mip)
module MetricPalette {
    const STEPS = Graphics.COLOR_PURPLE;
    const MINUTES = Graphics.COLOR_GREEN;
    const DISTANCE = Graphics.COLOR_BLUE;
    const CALORIES = Graphics.COLOR_ORANGE;
    const STREAK = Graphics.COLOR_ORANGE;
    const HEART_RATE = Graphics.COLOR_RED;
    const SECONDARY = Graphics.COLOR_LT_GRAY;
}

(:glance :mono)
module MetricPalette {
    const STEPS = Graphics.COLOR_WHITE;
    const MINUTES = Graphics.COLOR_WHITE;
    const DISTANCE = Graphics.COLOR_WHITE;
    const CALORIES = Graphics.COLOR_WHITE;
    const STREAK = Graphics.COLOR_WHITE;
    const HEART_RATE = Graphics.COLOR_WHITE;
    const SECONDARY = Graphics.COLOR_WHITE;
}
