//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Package Collection Generator open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift Package Collection Generator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Package Collection Generator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
@testable import PackageCollectionGenerator
import PackageCollections
@testable import TestUtilities
import TSCBasic
import TSCUtility
import XCTest

final class PackageCollectionGenerateTests: XCTestCase {
    typealias Model = JSONPackageCollectionModel.V1

    func test_help() throws {
        XCTAssert(try executeCommand(command: "package-collection-generate --help")
            .stdout.contains("USAGE: package-collection-generate <input-path> <output-path> [--working-directory-path <working-directory-path>] [--revision <revision>] [--verbose]"))
    }

    func test_endToEnd() throws {
        try withTemporaryDirectory(prefix: "PackageCollectionToolTests", removeTreeOnDeinit: true) { tmpDir in
            // TestRepoOne has tags [0.1.0]
            let repoOneArchivePath = AbsolutePath(#file).parentDirectory.appending(components: "Inputs", "TestRepoOne.tgz")
            try systemQuietly(["tar", "-x", "-v", "-C", tmpDir.pathString, "-f", repoOneArchivePath.pathString])

            // TestRepoTwo has tags [0.1.0, 0.2.0]
            let repoTwoArchivePath = AbsolutePath(#file).parentDirectory.appending(components: "Inputs", "TestRepoTwo.tgz")
            try systemQuietly(["tar", "-x", "-v", "-C", tmpDir.pathString, "-f", repoTwoArchivePath.pathString])

            // TestRepoThree has tags [1.0.0]
            let repoThreeArchivePath = AbsolutePath(#file).parentDirectory.appending(components: "Inputs", "TestRepoThree.tgz")
            try systemQuietly(["tar", "-x", "-v", "-C", tmpDir.pathString, "-f", repoThreeArchivePath.pathString])

            let jsonEncoder = JSONEncoder()
            if #available(macOS 10.15, *) {
                #if os(macOS)
                jsonEncoder.outputFormatting = [.withoutEscapingSlashes]
                #else
                jsonEncoder.outputFormatting = [.sortedKeys]
                #endif
            }

            // Prepare input.json
            let input = PackageCollectionGeneratorInput(
                name: "Test Package Collection",
                overview: "A few test packages",
                keywords: ["swift packages"],
                packages: [
                    PackageCollectionGeneratorInput.Package(
                        url: URL(string: "https://package-collection-tests.com/repos/TestRepoOne.git")!,
                        summary: "Package Foo"
                    ),
                    PackageCollectionGeneratorInput.Package(
                        url: URL(string: "https://package-collection-tests.com/repos/TestRepoTwo.git")!,
                        summary: "Package Foo & Bar"
                    ),
                    PackageCollectionGeneratorInput.Package(
                        url: URL(string: "https://package-collection-tests.com/repos/TestRepoThree.git")!,
                        summary: "Package Baz",
                        versions: ["1.0.0"]
                    ),
                ]
            )
            let inputData = try jsonEncoder.encode(input)
            let inputFilePath = tmpDir.appending(component: "input.json")
            try localFileSystem.writeFileContents(inputFilePath, bytes: ByteString(inputData))

            // Where to write the generated collection
            let outputFilePath = tmpDir.appending(component: "package-collection.json")
            // `tmpDir` is where we extract the repos so use it as the working directory so we won't actually doing any cloning
            let workingDirectoryPath = tmpDir

            XCTAssert(try executeCommand(command: "package-collection-generate --verbose \(inputFilePath.pathString) \(outputFilePath.pathString) --working-directory-path \(workingDirectoryPath.pathString)")
                .stdout.contains("Package collection saved to \(outputFilePath.pathString)"))

            let expectedPackages = [
                Model.Collection.Package(
                    url: URL(string: "https://package-collection-tests.com/repos/TestRepoOne.git")!,
                    summary: "Package Foo",
                    versions: [
                        Model.Collection.Package.Version(
                            version: "0.1.0",
                            packageName: "TestPackageOne",
                            targets: [.init(name: "Foo", moduleName: "Foo")],
                            products: [.init(name: "Foo", type: .library(.automatic), targets: ["Foo"])],
                            toolsVersion: "5.2.0",
                            minimumPlatformVersions: [.init(name: "macos", version: "10.15")]
                        ),
                    ]
                ),
                Model.Collection.Package(
                    url: URL(string: "https://package-collection-tests.com/repos/TestRepoTwo.git")!,
                    summary: "Package Foo & Bar",
                    versions: [
                        Model.Collection.Package.Version(
                            version: "0.2.0",
                            packageName: "TestPackageTwo",
                            targets: [
                                .init(name: "Bar", moduleName: "Bar"),
                                .init(name: "Foo", moduleName: "Foo"),
                            ],
                            products: [
                                .init(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
                                .init(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                            ],
                            toolsVersion: "5.2.0"
                        ),
                        Model.Collection.Package.Version(
                            version: "0.1.0",
                            packageName: "TestPackageTwo",
                            targets: [.init(name: "Bar", moduleName: "Bar")],
                            products: [.init(name: "Bar", type: .library(.automatic), targets: ["Bar"])],
                            toolsVersion: "5.2.0"
                        ),
                    ]
                ),
                Model.Collection.Package(
                    url: URL(string: "https://package-collection-tests.com/repos/TestRepoThree.git")!,
                    summary: "Package Baz",
                    versions: [
                        Model.Collection.Package.Version(
                            version: "1.0.0",
                            packageName: "TestPackageThree",
                            targets: [.init(name: "Baz", moduleName: "Baz")],
                            products: [.init(name: "Baz", type: .library(.automatic), targets: ["Baz"])],
                            toolsVersion: "5.2.0"
                        ),
                    ]
                ),
            ]

            let jsonDecoder = JSONDecoder()
            jsonDecoder.dateDecodingStrategy = .iso8601

            // Assert the generated package collection
            let collectionData = try localFileSystem.readFileContents(outputFilePath).contents
            let packageCollection = try jsonDecoder.decode(Model.Collection.self, from: Data(collectionData))
            XCTAssertEqual(input.name, packageCollection.name)
            XCTAssertEqual(input.overview, packageCollection.overview)
            XCTAssertEqual(input.keywords, packageCollection.keywords)
            XCTAssertEqual(expectedPackages, packageCollection.packages)
        }
    }
}
