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

/// One set of lights: three bulb colours, and the colour of the wire and sockets.
///
/// It's always exactly three colours, because the Festivizer pattern works in threes: bulb 0 is
/// colour 0, bulb 1 colour 1, bulb 2 colour 2, bulb 3 colour 0 again, and so on.
///
/// RED and BLU match what the Festivizer puts on each team's weapons. Warm White and Pastel are
/// cozier extras.
struct Theme: Equatable {
    let id: String
    let name: String
    let colours: [RGB]
    let wire: RGB

    /// TF2's cable: almost black, with a hint of green.
    private static let festiveWire = RGB(0x232B24)

    static let blu = Theme(id: "blu", name: "BLU (green, light blue, yellow)",
                           colours: [RGB(0x7BE04B), RGB(0x7DD3F5), RGB(0xF5D53F)], wire: festiveWire)
    static let red = Theme(id: "red", name: "RED (green, yellow, red)",
                           colours: [RGB(0x7BE04B), RGB(0xF5D53F), RGB(0xF2432C)], wire: festiveWire)
    static let warmWhite = Theme(id: "warm", name: "Warm White",
                                 colours: [RGB(0xFFE3A8), RGB(0xFFD27F), RGB(0xFFEFCF)], wire: festiveWire)
    /// Fairy-light pastels on a cream wire.
    static let pastel = Theme(id: "pastel", name: "Pastel (pink, mint, butter)",
                              colours: [RGB(0xF4A6C1), RGB(0x9EDFC4), RGB(0xFBE09A)], wire: RGB(0xD8CFBF))

    static let all: [Theme] = [blu, red, warmWhite, pastel]

    /// Not a theme itself: "give each app its own theme".
    static let mixedID = "mixed"
}
