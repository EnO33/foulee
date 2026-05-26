import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        compatibleXcodeVersions: ["26.0", "26.1"],
        swiftVersion: "6.2"
    )
)
