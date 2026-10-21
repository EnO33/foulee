import Toybox.Lang;

//! The `water` message (ADR 0009, D8): a glass drunk, noted at the watch,
//! which cannot write to Santé. The phone writes it there with `id` in its
//! metadata and skips an id it already wrote, so a glass sent again after a
//! lost acknowledgement is never counted twice.
//!
//! The keys are the contract with `GarminWaterGlass` on the phone.
module WaterMessage {

    const MESSAGE_TYPE = "water";
    const SCHEMA_VERSION = 1;

    //! A glass of `milliliters` drunk at `at` (epoch seconds). `nonce` tells
    //! apart two glasses noted in the same second.
    function glass(at as Number, milliliters as Number, nonce as Number) as Dictionary<String, Number or String> {
        return {
            "t" => MESSAGE_TYPE,
            "v" => SCHEMA_VERSION,
            "id" => at.format("%d") + "-" + nonce.format("%d"),
            "at" => at,
            "ml" => milliliters
        };
    }
}
