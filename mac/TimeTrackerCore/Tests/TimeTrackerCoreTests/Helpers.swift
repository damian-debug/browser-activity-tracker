import Foundation
@testable import TimeTrackerCore

// Shared fixtures for the conformance suite. These mirror the TypeScript test
// helpers so the ported assertions stay recognisably the same tests.

let chromeBundleID = "com.google.Chrome"

func browserSnapshot(
    url: String = "https://bubble.io/page?id=sampleapp&tab=Design",
    title: String = "sampleapp | Bubble Editor",
    bundleID: String = chromeBundleID
) -> ActivitySnapshot {
    ActivitySnapshot(bundleID: bundleID, appName: "Google Chrome", windowTitle: title, url: url)
}

func nativeSnapshot(
    bundleID: String = "com.microsoft.VSCode",
    appName: String = "Code",
    title: String? = nil,
    documentPath: String? = nil
) -> ActivitySnapshot {
    ActivitySnapshot(
        bundleID: bundleID, appName: appName,
        windowTitle: title, documentPath: documentPath
    )
}

func makeRule(
    type: ProjectRuleType,
    value: String,
    projectId: String,
    id: String? = nil,
    queryParamName: String? = nil,
    priority: Int = 0,
    enabled: Bool = true,
    defaultTagIds: [String]? = nil,
    defaultBillable: Bool? = nil
) -> ProjectRule {
    ProjectRule(
        id: id ?? "rule-\(type.rawValue)-\(value)",
        projectId: projectId,
        name: "test rule",
        type: type,
        value: value,
        queryParamName: queryParamName,
        priority: priority,
        enabled: enabled,
        defaultTagIds: defaultTagIds,
        defaultBillable: defaultBillable,
        createdAt: Date(unixMillis: 0),
        updatedAt: Date(unixMillis: 0)
    )
}

let referenceNow = Date(unixMillis: 1_700_000_000_000)
