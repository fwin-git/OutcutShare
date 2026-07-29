import Foundation

/// Pure math for the capture card's trim handles (fractions 0…1 of the
/// clip's duration).
enum TrimMath {
    /// The in-handle can move within [0, out - minGap]. When the gap can't
    /// fit, the handle pins to the range start.
    static func clampedIn(_ proposed: Double, out: Double, minGap: Double) -> Double {
        min(max(0, proposed), max(0, out - minGap))
    }

    /// The out-handle can move within [in + minGap, 1]. When the gap can't
    /// fit, the handle pins to the range end.
    static func clampedOut(_ proposed: Double, in inFraction: Double,
                           minGap: Double) -> Double {
        max(min(1, proposed), min(1, inFraction + minGap))
    }

    /// m:ss, or h:mm:ss from one hour up. Seconds are floored.
    static func timeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d",
                          total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
