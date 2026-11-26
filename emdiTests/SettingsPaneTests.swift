import SwiftUI
import Testing
@testable import emdi

struct SettingsPaneTests {
    /// The sidebar's `List(selection:)` only selects rows whose `id` has the selection's type (`SettingsPane?`).
    /// With a `String` id, clicks in the sidebar did nothing.
    @Test func sidebarRowsAreTaggedWithThePaneItself() {
        for pane in SettingsPane.allCases {
            #expect(type(of: pane.id) == SettingsPane.self)
            #expect(pane.id == pane)
        }
    }
}
