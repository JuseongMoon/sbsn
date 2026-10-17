import Foundation
import Testing
@testable import SBSNCore

@Test func appRoleRawValuesAreStable() {
    #expect(AppRole.allCases.map(\.rawValue) == ["customer", "photographer"])
}

@Test func appRoleRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(AppRole.photographer)
    #expect(try JSONDecoder().decode(AppRole.self, from: data) == .photographer)
}
