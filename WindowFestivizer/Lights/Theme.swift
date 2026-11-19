import CoreGraphics

/// A colour written as hex (0xFFCC00), with helpers for shading it.
struct RGB: Equatable {
    var r: CGFloat, g: CGFloat, b: CGFloat

    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r; self.g = g; self.b = b
    }

    /// Blend towards `other` by `t` (0 = this colour, 1 = the other one).
    func mix(_ other: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func lighter(_ t: CGFloat) -> RGB { mix(RGB(0xFFFFFF), t) }
    func darker(_ t: CGFloat) -> RGB { mix(RGB(0x000000), t) }

    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// One set of lights: three bulb colours and the colour of the wire.
///
/// It's always exactly three colours, because the Festivizer pattern works in threes: bulb 0 is
/// colour 0, bulb 1 colour 1, bulb 2 colour 2, bulb 3 colour 0 again, and so on.
struct Theme: Equatable {
    let id: String
    let name: String
    let colours: [RGB]
    let wire: RGB

    /// The green, blue and yellow from the Festivizer tool demo.
    static let festivizer = Theme(id: "festivizer", name: "Festivizer (green, blue, yellow)",
                                  colours: [RGB(0x72FF5C), RGB(0x5CD3FF), RGB(0xFFE04D)], wire: RGB(0x1C251B))
    static let red = Theme(id: "red", name: "RED (red, amber, warm white)",
                           colours: [RGB(0xFF4234), RGB(0xFF9D2B), RGB(0xFFE6BD)], wire: RGB(0x2B1A16))
    static let blu = Theme(id: "blu", name: "BLU (blue, cyan, cool white)",
                           colours: [RGB(0x3D86FF), RGB(0x5FE4FF), RGB(0xE2F2FF)], wire: RGB(0x172029))
    static let classic = Theme(id: "classic", name: "Classic (red, green, gold)",
                               colours: [RGB(0xFF3A3A), RGB(0x38DD62), RGB(0xFFC63A)], wire: RGB(0x1B2318))

    static let all: [Theme] = [festivizer, red, blu, classic]

    /// Not a theme itself: "give each app its own theme".
    static let mixedID = "mixed"
}
