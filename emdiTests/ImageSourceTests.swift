import Foundation
import Testing
@testable import emdi

struct ImageSourceTests {
    private let document = URL(fileURLWithPath: "/Users/me/Notes/today.md")

    @Test func relativePathsUseTheDocumentFolder() {
        #expect(ImageSource.resolve("pics/cat.png", relativeTo: document)?.path == "/Users/me/Notes/pics/cat.png")
        #expect(ImageSource.resolve("../cat.png", relativeTo: document)?.path == "/Users/me/cat.png")
        #expect(ImageSource.resolve("my%20cat.png", relativeTo: document)?.path == "/Users/me/Notes/my cat.png")
        #expect(ImageSource.resolve("<my cat.png>", relativeTo: document)?.path == "/Users/me/Notes/my cat.png")
    }

    @Test func absoluteAndFileURLs() {
        #expect(ImageSource.resolve("/tmp/a.png", relativeTo: nil)?.path == "/tmp/a.png")
        #expect(ImageSource.resolve("file:///tmp/a.png", relativeTo: nil)?.path == "/tmp/a.png")
    }

    @Test func remoteAndUnsavedRelativeImagesAreNotLoaded() {
        #expect(ImageSource.resolve("https://example.com/a.png", relativeTo: document) == nil)
        #expect(ImageSource.resolve("a.png", relativeTo: nil) == nil)
    }
}
