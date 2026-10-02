// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OmnieEdit",
    products: [
        .library(name: "OmnieDocumentKit", targets: ["OmnieDocumentKit"]),
        .library(name: "OmnieEditCore", targets: ["OmnieEditCore"]),
    ],
    targets: [
        .target(name: "OmnieDocumentKit"),
        .target(
            name: "OmnieEditCore",
            dependencies: ["OmnieDocumentKit"]
        ),
        .testTarget(
            name: "OmnieEditCoreTests",
            dependencies: ["OmnieEditCore", "OmnieDocumentKit"]
        ),
    ]
)
