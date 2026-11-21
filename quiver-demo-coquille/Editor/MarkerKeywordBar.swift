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

/// The keywords that could finish the review marker being typed, shown under the editor.
/// Once a keyword is finished, its description takes the place of the list.
struct MarkerKeywordBar: View {

    let model: EditorModel

    var body: some View {
        let keywords = model.offeredMarkerKeywords
        let description = model.markerDescription
        if !keywords.isEmpty || description != nil {
            VStack(spacing: 0) {
                Divider()
                if !keywords.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(keywords, id: \.self) { keyword in
                                Button(keyword) { model.completeMarker(with: keyword) }
                                    .font(.plexMono(14, relativeTo: .callout))
                                    .accessibilityLabel("Marker: \(keyword)")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    .buttonStyle(.bordered)
                } else if let description {
                    Text(description)
                        .font(.plexMono(14, relativeTo: .callout))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
    }
}
