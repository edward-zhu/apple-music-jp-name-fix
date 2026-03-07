//
//  ContentView.swift
//  Apple Music Name Update
//
//  Created by Edward Zhu on 3/3/26.
//

import MusicKit
import SwiftUI

struct ContentView: View {
  @State private var viewModel = MusicViewModel()

  var body: some View {
    NavigationStack {
      VStack {
        if viewModel.isRunning {
          ProgressView(value: viewModel.progress) {
            Text("Processing... \(Int(viewModel.progress * 100))%")
          }
          .padding()
        }
        List(viewModel.songs) { song in
          HStack {
            VStack(alignment: .leading) {
              Text(song.localTitle)
                .font(.headline)
              Text(song.artist)
                .font(.subheadline)
              Text(song.id)
              Text(song.persistentID ?? "No Persistent ID")
              if let jpTitle = song.jpTitle,
                let jpArtist = song.jpArtist
              {
                Text("🇯🇵 \(jpTitle) - \(jpArtist)")
                  .foregroundColor(.blue).font(
                    .subheadline
                  )
              }
            }
            Spacer()
            if song.jpTitle != nil
              && (song.jpTitle != song.localTitle
                || song.jpArtist != song.artist)
            {
              Button("Update to Music Library") {
                viewModel.applyJPTitleArtist(for: song)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
            }
            statusIcon(song.status)
          }
        }
      }
    }
    .navigationTitle("Apple Music ID Updater")
    .toolbar {
      Button("Fetch JP iTunes Store") {
        Task {
          await viewModel.fetchJPNames()
        }
      }
    }
    .onAppear {
      Task {
        await viewModel.requestPermissionAndFetch()
      }
    }
  }

  @ViewBuilder
  func statusIcon(_ status: MatchStatus) -> some View {
    switch status {
    case .completed:
      Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
    case .pending: Image(systemName: "hourglass")
    case .failed:
      Image(systemName: "exclamationmark.circle.fill").foregroundColor(
        .red
      )
    }
  }
}

#Preview {
  ContentView()
}
