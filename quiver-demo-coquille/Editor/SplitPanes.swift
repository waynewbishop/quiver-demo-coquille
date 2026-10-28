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

#if os(macOS)
import SwiftUI

/// Two panes side by side with a divider the learner drags to resize them.
///
/// The trailing pane's share of the width is a binding, so the caller decides whether
/// it persists. Double-clicking the divider restores the default split.
struct SplitPanes<Leading: View, Trailing: View>: View {

    let showsTrailing: Bool
    @Binding var trailingFraction: Double
    private let leading: Leading
    private let trailing: Trailing

    /// The design's split: 60% French, 40% English.
    static var defaultFraction: Double { 0.4 }
    /// Neither pane gets narrower than this while dragging.
    private static var minimumPaneWidth: Double { 280 }
    /// How far the divider steps with the accessibility adjust actions.
    private static var adjustmentStep: Double { 0.05 }
    private static var coordinateSpace: String { "SplitPanes" }

    /// Creates the split; `trailing` is shown only while `showsTrailing` is true.
    init(
        showsTrailing: Bool,
        trailingFraction: Binding<Double>,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.showsTrailing = showsTrailing
        self._trailingFraction = trailingFraction
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                leading
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsTrailing {
                    handle(totalWidth: width)
                    trailing
                        .frame(width: width * clamped(trailingFraction, totalWidth: width))
                        .frame(maxHeight: .infinity)
                }
            }
            .coordinateSpace(.named(Self.coordinateSpace))
        }
    }

    /// The one-point divider, with a wider invisible strip that takes the drag.
    private func handle(totalWidth: Double) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
                            .onChanged { drag in
                                trailingFraction = clamped((totalWidth - drag.location.x) / totalWidth, totalWidth: totalWidth)
                            }
                    )
                    .onTapGesture(count: 2) { trailingFraction = Self.defaultFraction }
            }
            .accessibilityElement()
            .accessibilityLabel("Pane divider")
            .accessibilityValue("English \(Int((trailingFraction * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: trailingFraction = clamped(trailingFraction + Self.adjustmentStep, totalWidth: totalWidth)
                case .decrement: trailingFraction = clamped(trailingFraction - Self.adjustmentStep, totalWidth: totalWidth)
                @unknown default: break
                }
            }
    }

    /// Keeps both panes at least `minimumPaneWidth` wide, or splits evenly when they can't be.
    private func clamped(_ fraction: Double, totalWidth: Double) -> Double {
        guard totalWidth > 2 * Self.minimumPaneWidth else { return 0.5 }
        let limit = Self.minimumPaneWidth / totalWidth
        return min(max(fraction, limit), 1 - limit)
    }
}
#endif
