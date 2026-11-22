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

/// Shows `content` for a learner with Coquille Pro, and a short offer in its place for
/// everyone else.
///
/// It gates a feature's screen, never the learner's own writing.
struct ProGate<Content: View>: View {

    @Environment(ProStore.self) private var pro
    let title: String
    let message: String
    @ViewBuilder let content: () -> Content
    @State private var showsPaywall = false

    var body: some View {
        if pro.grantsFeatures {
            content()
        } else {
            ContentUnavailableView {
                Label(title, systemImage: "lock")
            } description: {
                Text(message)
            } actions: {
                Button("See Coquille Pro") { showsPaywall = true }
                    .buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView(store: pro)
                    .tint(.brand)
            }
        }
    }
}
