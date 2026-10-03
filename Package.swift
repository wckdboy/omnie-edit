// swift-tools-version: 5.9
// Package dependencies are kept at the repository root so Xcode and SwiftPM
// build the same source graph.
import PackageDescription

let package = Package(
    name: "OmnieEdit",
    platforms: [
        .iOS("18.0"),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OmnieDocumentKit", targets: ["OmnieDocumentKit"]),
        .library(name: "OmnieEditCore", targets: ["OmnieEditCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/simonbs/Runestone.git", from: "0.5.2"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", from: "0.1.0"),
        .package(url: "https://github.com/ibrahimcetin/SwiftGitX.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "OmnieDocumentKit"),
        .target(
            name: "OmnieEditCore",
            dependencies: [
                "OmnieDocumentKit",
                .product(name: "SwiftGitX", package: "SwiftGitX", condition: .when(platforms: [.iOS])),
                .product(name: "Runestone", package: "Runestone", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterBashRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterCSSRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterHTMLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterJavaScriptRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterJSONRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterMarkdownRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterPythonRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterSwiftRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterTOMLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterTypeScriptRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterYAMLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "OmnieEditCoreTests",
            dependencies: ["OmnieEditCore", "OmnieDocumentKit"]
        ),
    ]
)
