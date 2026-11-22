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

import Foundation

/// The App Store identifiers for Coquille Pro, kept in one place.
///
/// While testing, these match `Coquille.storekit`. Before release they must match the
/// subscription group and product made in App Store Connect.
enum ProductIDs {
    /// The subscription group's ID. App Store Connect assigns this when the group is made.
    static let groupID = "21540000"
    /// The annual Coquille Pro subscription.
    static let annual = "coquille.pro.annual"
}
