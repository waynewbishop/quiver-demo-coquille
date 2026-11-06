// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import SwiftUI
import CoreText

/// The bundled IBM Plex fonts, used as in the design: Plex Mono for the French and
/// labels, Plex Sans for the English. The fonts ship under the SIL Open Font License
/// (`IBMPlex-OFL.txt`).
enum AppFonts {

    /// Registers the bundled fonts for this process, so no Info.plist entry is needed.
    ///
    /// A font that fails to register falls back to the system font, which keeps the
    /// app fully usable, so the result isn't surfaced.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Text sizes and line spacing for the two languages.
///
/// On the Mac the French and English lines are both 34 points tall, so the
/// translation lines up beside the sentence it came from.
enum Typography {
    #if os(macOS)
    static let frenchSize = 17.0
    static let frenchLineSpacing = 12.0
    static let englishSize = 16.0
    static let englishLineSpacing = 13.0
    #else
    static let frenchSize = 20.0
    static let frenchLineSpacing = 8.0
    static let englishSize = 17.0
    static let englishLineSpacing = 6.0
    #endif
}

extension Font {

    /// The weights bundled for each Plex family.
    enum PlexWeight {
        case regular
        case medium
    }

    /// IBM Plex Mono at `size`, scaling with Dynamic Type like `style`.
    static func plexMono(_ size: Double, weight: PlexWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight == .regular ? "IBMPlexMono" : "IBMPlexMono-Medm", size: size, relativeTo: style)
    }

    /// IBM Plex Sans at `size`, scaling with Dynamic Type like `style`.
    static func plexSans(_ size: Double, weight: PlexWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight == .regular ? "IBMPlexSans" : "IBMPlexSans-Medm", size: size, relativeTo: style)
    }
}
