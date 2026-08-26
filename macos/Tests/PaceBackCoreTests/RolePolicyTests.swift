import XCTest
@testable import PaceBackCore

final class RolePolicyTests: XCTestCase {
    func testUnder13RequiresCaregiverRoleAndDisablesFreeformAI() {
        let child = LocalProfile(alias: "Child", ageBand: .child6To12, actingRole: .guardian)

        XCTAssertTrue(RolePolicy.permits(.useGuidedSessions, profile: child))
        XCTAssertTrue(RolePolicy.permits(.askEvidence, profile: child))
        XCTAssertTrue(RolePolicy.permits(.manageCarePlan, profile: child))
        XCTAssertFalse(RolePolicy.permits(.useFreeformAI, profile: child))
        XCTAssertTrue(RolePolicy.requiresAdministrativeGate(.exportData, profile: child))
    }

    func testInvalidUnder13SelfManagedRoleIsFailClosed() {
        let invalid = LocalProfile(alias: "Child", ageBand: .youngChild0To5, actingRole: .selfManaged)

        for permission in ProfilePermission.allCases {
            XCTAssertFalse(RolePolicy.permits(permission, profile: invalid), "Unexpected permission: \(permission)")
        }
    }

    func testTeenCanUseToolsButCannotAdministerProfile() {
        let teen = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .teenUser)

        XCTAssertTrue(RolePolicy.permits(.useGuidedSessions, profile: teen))
        XCTAssertTrue(RolePolicy.permits(.simplifyDocuments, profile: teen))
        XCTAssertTrue(RolePolicy.permits(.askEvidence, profile: teen))
        XCTAssertTrue(RolePolicy.permits(.useFreeformAI, profile: teen))
        XCTAssertFalse(RolePolicy.permits(.importDocuments, profile: teen))
        XCTAssertFalse(RolePolicy.permits(.exportData, profile: teen))
        XCTAssertFalse(RolePolicy.permits(.deleteProfile, profile: teen))
        XCTAssertFalse(RolePolicy.permits(.changeSettings, profile: teen))
    }

    func testTeenGuardianCanAdministerWithGate() {
        let guardian = LocalProfile(alias: "Teen", ageBand: .teen13To17, actingRole: .guardian)

        XCTAssertTrue(RolePolicy.permits(.manageCarePlan, profile: guardian))
        XCTAssertTrue(RolePolicy.permits(.deleteProfile, profile: guardian))
        XCTAssertTrue(RolePolicy.requiresAdministrativeGate(.manageCarePlan, profile: guardian))
        XCTAssertTrue(RolePolicy.requiresAdministrativeGate(.deleteProfile, profile: guardian))
    }

    func testAdultCaregiverRequiresRevocableApproval() {
        let unapproved = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .caregiver,
            caregiverApproved: false
        )
        let approved = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .caregiver,
            caregiverApproved: true
        )

        XCTAssertFalse(RolePolicy.permits(.useGuidedSessions, profile: unapproved))
        XCTAssertFalse(RolePolicy.permits(.exportData, profile: unapproved))
        XCTAssertTrue(RolePolicy.permits(.useGuidedSessions, profile: approved))
        XCTAssertTrue(RolePolicy.permits(.askEvidence, profile: approved))
        XCTAssertTrue(RolePolicy.permits(.importDocuments, profile: approved))
        XCTAssertTrue(RolePolicy.permits(.exportData, profile: approved))
        XCTAssertFalse(RolePolicy.permits(.manageCarePlan, profile: approved))
        XCTAssertFalse(RolePolicy.permits(.deleteProfile, profile: approved))
        XCTAssertFalse(RolePolicy.permits(.changeSettings, profile: approved))
        XCTAssertFalse(RolePolicy.requiresAdministrativeGate(.exportData, profile: approved))

        let owner = LocalProfile(
            alias: "Adult",
            ageBand: .adult18To64,
            actingRole: .selfManaged,
            caregiverApproved: true
        )
        XCTAssertTrue(RolePolicy.permits(.deleteProfile, profile: owner))
        XCTAssertTrue(RolePolicy.permits(.changeSettings, profile: owner))
    }

    func testEvidenceQueryUsesOnlyAllAgesAndExactAgeScope() throws {
        let profile = LocalProfile(alias: "Older", ageBand: .olderAdult65Plus, actingRole: .selfManaged)
        let query = EvidenceQuery(question: "What should I track?", profile: profile)

        XCTAssertEqual(query.evidenceScope, [.allAges, .olderAdult65Plus])
        XCTAssertEqual(query.profileID, profile.id)
        XCTAssertEqual(query.ageBand, .olderAdult65Plus)
        XCTAssertEqual(query.maxOutputTokens, 500)

        let encoded = try JSONEncoder().encode(query)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["actingRole"] as? String, "selfManaged")
        XCTAssertEqual(object["careContext"] as? String, "dailyLiving")
        XCTAssertEqual(object["evidenceScope"] as? [String], ["allAges", "olderAdult65Plus"])
    }
}
