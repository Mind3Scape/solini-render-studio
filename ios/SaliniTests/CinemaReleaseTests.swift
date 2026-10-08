import AVFoundation
import UIKit
import XCTest

@testable import Salini

/// The collection films are adopted only through `CollectionCinemaAssets.releases`: explicit,
/// unique files whose measured loop length, frame and poster proportions are checked here.
final class CinemaReleaseTests: XCTestCase {
  func testNinfeaLeadsAndEveryCollectionHasExactlyOneRelease() {
    XCTAssertEqual(CollectionGallery.stories.map(\.id), CollectionCinemaAssets.allCases.map(\.rawValue),
                   "Gallery order follows the releases, Ninfea first")
    XCTAssertEqual(CollectionGallery.stories.first?.id, "ninfea")
    XCTAssertEqual(Set(CollectionCinemaAssets.releases.keys), Set(CollectionCinemaAssets.allCases))
    var files = Set<String>()
    for collection in CollectionCinemaAssets.allCases {
      let r = collection.release
      XCTAssertFalse(r.version.isEmpty, collection.name)
      XCTAssertFalse(r.source.isEmpty, collection.name)
      XCTAssertNotEqual(r.intro, r.loop, "\(collection.name): the reveal and the loop are different files")
      for name in [r.intro, r.loop] {
        XCTAssertTrue(name.hasPrefix(collection.rawValue + "-"), "\(name) belongs to \(collection.name)")
        XCTAssertTrue(files.insert(name).inserted, "\(name) is used by one collection only")
      }
      XCTAssertNotEqual(r.intro, "ninfea-film-v2", "The rejected layer-warp film never ships")
    }
  }

  func testReleasedFilesMatchTheirMeasuredLoopAndKeepProportions() async throws {
    for collection in CollectionCinemaAssets.allCases {
      let r = collection.release
      let introURL = try XCTUnwrap(collection.introURL, "\(r.intro).mp4 in bundle")
      let loopURL = try XCTUnwrap(collection.loopURL, "\(r.loop).mp4 in bundle")
      let intro = AVURLAsset(url: introURL)
      let loop = AVURLAsset(url: loopURL)
      // Every async load happens before the assertions: no `await` inside an autoclosure.
      let introTracks = try await intro.loadTracks(withMediaType: .video)
      let loopTracks = try await loop.loadTracks(withMediaType: .video)
      let audioTracks = try await loop.loadTracks(withMediaType: .audio)
      let introTrack = try XCTUnwrap(introTracks.first, collection.name)
      let loopTrack = try XCTUnwrap(loopTracks.first, collection.name)
      let size = try await loopTrack.load(.naturalSize)
      let introSize = try await introTrack.load(.naturalSize)
      let rate = Double(try await loopTrack.load(.nominalFrameRate))
      let seconds = try await loop.load(.duration).seconds
      XCTAssertEqual(size, introSize, "\(collection.name): the handoff never reframes")
      XCTAssertEqual(Int((seconds * rate).rounded()), r.loopFrames, "\(collection.name): loop length as measured")
      XCTAssertTrue(audioTracks.isEmpty, "\(collection.name): silent loop")
      // Posters are shown before/instead of playback with the same aspect fill: same proportions.
      let videoAspect = size.width / size.height
      for posterName in [r.startPoster, r.finalPoster] {
        let poster = try XCTUnwrap(UIImage(named: posterName), posterName)
        XCTAssertEqual(poster.size.width / poster.size.height, videoAspect, accuracy: 0.01,
                       "\(posterName) has the film's proportions — nothing is stretched")
      }
    }
  }
}
