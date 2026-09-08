// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CWhisper",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperSwift", targets: ["WhisperSwift"])
    ],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            exclude: [
                "ggml-cpp.h",
                "ggml-metal/ggml-metal.metal",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_USE_METAL"),
                .define("GGML_METAL_EMBED_LIBRARY"),
                .define("GGML_USE_ACCELERATE"),
                .define("ACCELERATE_NEW_LAPACK"),
                .define("ACCELERATE_LAPACK_ILP64"),
                .define("NDEBUG"),
                .headerSearchPath("."),
                .headerSearchPath("ggml-headers"),
                .headerSearchPath("ggml-cpu"),
                .headerSearchPath("ggml-cpu/llamafile"),
                .headerSearchPath("ggml-cpu/amx"),
                .headerSearchPath("ggml-metal"),
                .unsafeFlags(["-O3", "-fno-objc-arc", "-Wno-shorten-64-to-32", "-Wno-unused-function", "-Wno-unused-variable", "-Wno-ambiguous-macro"]),
            ],
            cxxSettings: [
                .define("GGML_USE_METAL"),
                .define("GGML_METAL_EMBED_LIBRARY"),
                .define("GGML_USE_ACCELERATE"),
                .define("ACCELERATE_NEW_LAPACK"),
                .define("ACCELERATE_LAPACK_ILP64"),
                .define("NDEBUG"),
                .headerSearchPath("."),
                .headerSearchPath("ggml-headers"),
                .headerSearchPath("ggml-cpu"),
                .headerSearchPath("ggml-cpu/llamafile"),
                .headerSearchPath("ggml-cpu/amx"),
                .headerSearchPath("ggml-metal"),
                .unsafeFlags(["-O3", "-std=c++17", "-Wno-shorten-64-to-32", "-Wno-unused-function", "-Wno-unused-variable"]),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "WhisperSwift",
            dependencies: ["CWhisper"],
            path: "Sources/WhisperSwift"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
