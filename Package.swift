// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BillyDesktop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BillyDesktop", targets: ["BillyDesktop"]),
        .library(name: "BillyCore", targets: ["BillyCore"]),
    ],
    targets: [
        // Reine Logik ohne AppKit: Befehle, Dateikategorien, Aufräumplan, Undo-Journal.
        .target(name: "BillyCore"),
        // macOS-App: Fenster, Sprites, Chat, Finder-Anbindung.
        .executableTarget(
            name: "BillyDesktop",
            dependencies: ["BillyCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "BillyCoreTests", dependencies: ["BillyCore"]),
    ]
)
