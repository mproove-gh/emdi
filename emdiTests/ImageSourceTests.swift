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

struct ImageDropTests {
    private let document = URL(fileURLWithPath: "/Users/me/Notes/today.md")

    @Test func dropsUseRelativePaths() {
        #expect(ImageSource.markdown(forImageAt: URL(fileURLWithPath: "/Users/me/Notes/pics/cat.png"), relativeTo: document)
                == "![cat](pics/cat.png)")
        #expect(ImageSource.markdown(forImageAt: URL(fileURLWithPath: "/Users/me/Desktop/dog.jpg"), relativeTo: document)
                == "![dog](../Desktop/dog.jpg)")
    }

    @Test func dropsOnUnsavedDocumentsOrOtherVolumesUseAbsolutePaths() {
        #expect(ImageSource.markdown(forImageAt: URL(fileURLWithPath: "/Users/me/a.png"), relativeTo: nil) == "![a](/Users/me/a.png)")
        #expect(ImageSource.markdown(forImageAt: URL(fileURLWithPath: "/Volumes/USB/b.png"), relativeTo: document)
                == "![b](/Volumes/USB/b.png)")
    }

    @Test func pathsWithSpacesUseAngleBrackets() {
        let url = URL(fileURLWithPath: "/Users/me/Notes/my cat (1).png")
        #expect(ImageSource.markdown(forImageAt: url, relativeTo: document) == "![my cat (1)](<my cat (1).png>)")
        #expect(ImageSource.resolve("<my cat (1).png>", relativeTo: document)?.path == url.path)
    }
}
