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

import Quiver

nonisolated extension LogisticRegression {

    /// Whether the coefficients fit the model: one per feature, plus the intercept when
    /// there is one, and every one a finite number.
    ///
    /// Prediction reads the coefficients by position, so a model file with too few would
    /// crash on its first word. The language pack rejects such a file when it loads instead.
    var hasUsableCoefficients: Bool {
        coefficients.count == featureCount + (hasIntercept ? 1 : 0)
            && coefficients.allSatisfy(\.isFinite)
    }
}
