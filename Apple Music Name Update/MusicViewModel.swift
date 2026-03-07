//
//  MusicViewModel.swift
//  Apple Music Name Update
//
//  Created by Edward zhu on 3/4/26.
//

import Foundation
import MusicKit
import Observation

struct iTunesResponse: Codable {
  let resultCount: Int
  let results: [iTunesTrack]
}

struct iTunesTrack: Codable, Identifiable {
  var id: Int { trackId }
  let trackId: Int
  let trackName: String?
  let artistName: String?
}

struct SongMatch: Identifiable {
  let id: String
  let persistentID: String?
  var localTitle: String
  var jpTitle: String?
  var jpArtist: String?
  var artist: String
  var status: MatchStatus = .pending
}

enum MatchStatus: Equatable {
  case pending, completed, failed
}

@Observable
class MusicViewModel {
  struct SongPlayParameters: Codable {
    let isLibrary: Bool?
    let catalogId: MusicItemID?
    let musicKit_persistentID: String
  }

  var songs: [SongMatch] = []
  var progress: Double = 0.0
  var isRunning = false

  var isAuthorized = false

  func requestPermissionAndFetch() async {
    let status = await MusicAuthorization.request()
    self.isAuthorized = status == .authorized

    if isAuthorized {
      await fetchLocalTracks()
    }
  }

  private func fetchLocalTracks() async {
    do {
      let request = MusicLibraryRequest<Song>()
      let response = try await request.response()

      for song in response.items {
        let data = try JSONEncoder().encode(song.playParameters)
        let params = try JSONDecoder().decode(
          SongPlayParameters.self,
          from: data
        )

        let persistentID = Int(params.musicKit_persistentID)!
        let hexPersistentID = String(format: "%016llX", persistentID)

        let songId = params.catalogId?.rawValue
        if songId == nil {
          print(
            "Song \(song.title) does not have a catalog ID. Skip."
          )
          continue
        }
        songs.append(
          SongMatch(
            id: songId!,
            persistentID: hexPersistentID,
            localTitle: song.title,
            artist: song.artistName
          )
        )
      }
    } catch {
      print("error: \(error)")
    }
  }

  func fetchJPNames() async {
    if songs.isEmpty {
      print("No Songs, return.")
      return
    }
    isRunning = true
    let batchSize = 20
    for i in stride(from: 0, to: songs.count, by: batchSize) {
      let endIndex = min(i + batchSize, songs.count)

      await fetchJPNamesBatch(start: i, end: endIndex)
      progress = Double(endIndex) / Double(songs.count)
    }
    isRunning = false
  }

  private func fetchJPNamesBatch(start: Int, end: Int) async {
    let songIds = songs[start..<end].map(\.id)
    var songIdIndexMap: [String: Int] = [:]
    for i in start..<end {
      songIdIndexMap[songs[i].id] = i
    }

    let idString = songIds.joined(separator: ",")
    let urlString =
      "https://itunes.apple.com/lookup?id=\(idString)&country=JP"
    guard let url = URL(string: urlString) else {
      return
    }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      let response = try JSONDecoder().decode(
        iTunesResponse.self,
        from: data
      )
      for track in response.results {
        print("Fetching for \(track.id)...")
        if let index = songIdIndexMap[String(track.trackId)] {
          print("\(track.id): \(track.trackName ?? "unknown")...")
          songs[index].jpTitle = track.trackName
          songs[index].jpArtist = track.artistName
          songs[index].status = .completed
        } else {
          print("Cannot find song for trackId: \(track.trackId)")
        }
      }
      for i in start..<end {
        if songs[i].status == .pending {
          print("Failed to fetch title and artist for song at index: \(i)")
          songs[i].status = .failed
        }
      }
    } catch {
      print("Failed to fetch iTunes lookup data: \(error)")
    }
  }

  func applyJPTitleArtist(for song: SongMatch) {
    guard let newTitle = song.jpTitle, let newArtist = song.jpArtist,
      let persistentID = song.persistentID
    else {
      return
    }

    let scriptSource = """
      tell application "Music"
          try
              set targetTrack to (first track of library playlist 1 whose persistent ID is "\(persistentID)")
              set name of targetTrack to "\(newTitle)"
              set artist of targetTrack to "\(newArtist)"
              return "Success"
          on error errStr
              return "Error: " & errStr
          end try
      end tell
      """

    if let script = NSAppleScript(source: scriptSource) {
      var error: NSDictionary?
      let result = script.executeAndReturnError(&error)
      if let error = error {
        print("Script error: \(error)")
      } else {
        print("Script result: \(result)")
        if let index = self.songs.firstIndex(where: {
          $0.persistentID == song.persistentID
        }) {
          self.songs[index].localTitle = song.jpTitle ?? song.localTitle
          self.songs[index].artist = song.jpArtist ?? song.artist
          self.songs[index].status = .completed
        }
      }
    }
  }
}
