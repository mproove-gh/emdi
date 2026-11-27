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

    @Test func pastedImagesGetATimestampedNameThatIsFree() {
        let folder = URL(fileURLWithPath: "/tmp/doc/images")
        var components = DateComponents(year: 2026, month: 3, day: 4, hour: 5, minute: 6, second: 7)
        components.timeZone = .current
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(ImageSource.pastedImageURL(in: folder, date: date) { _ in false }.lastPathComponent == "image-20260304-050607.png")
        let taken: Set<String> = ["image-20260304-050607.png", "image-20260304-050607-2.png"]
        #expect(ImageSource.pastedImageURL(in: folder, date: date) { taken.contains($0.lastPathComponent) }
            .lastPathComponent == "image-20260304-050607-3.png")
    }

    @Test func pastedImagesGoInAFolderNamedAfterTheDocument() {
        #expect(ImageSource.imagesFolder(for: URL(fileURLWithPath: "/a/My notes.md")).path == "/a/My notes_images")
        #expect(ImageSource.imagesFolder(for: URL(fileURLWithPath: "/a/readme.markdown")).lastPathComponent == "readme_images")
    }

    @Test func filesOtherAppsKeepForAWhileAreTransient() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(ImageSource.isTransient(URL(fileURLWithPath: "/Users/me/Library/Application Support/CleanShot/media/x.png"), home: home))
        #expect(ImageSource.isTransient(URL(fileURLWithPath: "/private/var/folders/ab/T/shot.png"), home: home))
        #expect(ImageSource.isTransient(URL(fileURLWithPath: "/tmp/shot.png"), home: home))
        #expect(!ImageSource.isTransient(URL(fileURLWithPath: "/Users/me/Pictures/cat.png"), home: home))
        #expect(!ImageSource.isTransient(URL(fileURLWithPath: "/Users/me/LibraryBooks/cat.png"), home: home))
    }

    @Test func copiesKeepTheNameAndAvoidTakenOnes() {
        let folder = URL(fileURLWithPath: "/a/doc_images")
        let file = URL(fileURLWithPath: "/tmp/CleanShot 1@2x.png")
        #expect(ImageSource.copyURL(for: file, in: folder) { _ in false }.lastPathComponent == "CleanShot 1@2x.png")
        #expect(ImageSource.copyURL(for: file, in: folder) { $0.lastPathComponent == "CleanShot 1@2x.png" }
            .lastPathComponent == "CleanShot 1@2x-2.png")
    }
}
