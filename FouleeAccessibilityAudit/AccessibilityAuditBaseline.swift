import XCTest

/// The audit findings already known when the audit reached CI (issue #602),
/// read from `AccessibilityAuditBaseline.json`: only a finding missing from it
/// fails a test. The same idea as Periphery's `.periphery.baseline.json`.
///
/// A finding is its screen, its kind and its element: what is wrong, and where.
/// Xcode's wording (« Contrast failed », « Contrast nearly passed ») is left
/// out — how far off a finding is does not make it a new one. Refresh the file
/// after fixing one: `tools/accessibility_audit.sh --record`.
enum AccessibilityAuditBaseline {
    /// The findings accepted on `screen`. Throws when the file is missing or
    /// unreadable, rather than accepting nothing and failing every screen.
    static func accepted(on screen: String) throws -> Set<String> {
        let url = try XCTUnwrap(
            Bundle(for: AccessibilityAuditTests.self)
                .url(forResource: "AccessibilityAuditBaseline", withExtension: "json"),
            "AccessibilityAuditBaseline.json is missing from the test bundle"
        )
        let file = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        return Set(file[screen] ?? [])
    }

    /// « contrast · J'ai bu »: the kind, then the element's identifier, or its
    /// label when it has none.
    @MainActor
    static func finding(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let element = issue.element.map { $0.identifier.isEmpty ? $0.label : $0.identifier } ?? ""
        return "\(name(of: issue.auditType)) · \(element)"
    }

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "type \(type.rawValue)"
        }
    }
}
