import Foundation

/// Named and numeric HTML entity decoding. Covers the entities that actually turn
/// up in prose; anything unrecognised is left verbatim rather than dropped.
enum HTMLEntities {
    static func decode(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var out = ""
        out.reserveCapacity(input.count)
        var cursor = input.startIndex

        while let ampersand = input[cursor...].firstIndex(of: "&") {
            out += input[cursor..<ampersand]

            // Entities are short; cap the search window so a bare "&" is cheap.
            let windowEnd = input.index(ampersand, offsetBy: 12, limitedBy: input.endIndex) ?? input.endIndex
            guard let semicolon = input[ampersand..<windowEnd].firstIndex(of: ";") else {
                out.append("&")
                cursor = input.index(after: ampersand)
                continue
            }

            let body = String(input[input.index(after: ampersand)..<semicolon])
            if let replacement = resolve(body) {
                out += replacement
            } else {
                out += input[ampersand...semicolon]
            }
            cursor = input.index(after: semicolon)
        }

        out += input[cursor...]
        return out
    }

    private static func resolve(_ body: String) -> String? {
        guard !body.isEmpty else { return nil }

        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }

        return named[body]
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·", "bull": "•",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "sbquo": "‚", "bdquo": "„", "dagger": "†", "Dagger": "‡", "prime": "′", "Prime": "″",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶", "deg": "°",
        "plusmn": "±", "times": "×", "divide": "÷", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup1": "¹", "sup2": "²", "sup3": "³", "micro": "µ", "permil": "‰",
        "cent": "¢", "pound": "£", "yen": "¥", "euro": "€", "curren": "¤",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔", "crarr": "↵",
        "hArr": "⇔", "rArr": "⇒", "lArr": "⇐", "minus": "−", "lowast": "∗",
        "ne": "≠", "le": "≤", "ge": "≥", "asymp": "≈", "equiv": "≡", "infin": "∞",
        "sum": "∑", "prod": "∏", "radic": "√", "int": "∫", "part": "∂", "nabla": "∇",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ",
        "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ",
        "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ",
        "Lambda": "Λ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å",
        "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
        "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "ntilde": "ñ",
        "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "yuml": "ÿ",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å",
        "AElig": "Æ", "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë",
        "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï", "Ntilde": "Ñ",
        "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø",
        "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "szlig": "ß",
        "iexcl": "¡", "iquest": "¿", "shy": "\u{00AD}", "zwj": "\u{200D}", "zwnj": "\u{200C}",
    ]
}
