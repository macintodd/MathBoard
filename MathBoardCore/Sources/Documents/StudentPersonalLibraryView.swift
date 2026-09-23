//
//  StudentPersonalLibraryView.swift
//  MathBoardCore — Documents module
//
//  Grid viewer for a student's personal clip library. iOS only.
//

#if os(iOS)
import SwiftUI

struct StudentPersonalLibraryView: View {
    @State private var clips: [StudentClip] = []
    @State private var confirmDeleteClip: StudentClip?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    ContentUnavailableView(
                        "No Clips Yet",
                        systemImage: "scissors.badge.ellipsis",
                        description: Text("Use the Extract tool on your canvas to save items to your personal library.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(clips) { clip in
                                StudentClipThumbnailView(clip: clip)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            confirmDeleteClip = clip
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("My Clips")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { clips = StudentPersonalLibraryStore.shared.loadClips() }
            .confirmationDialog(
                "Delete this clip?",
                isPresented: Binding(
                    get: { confirmDeleteClip != nil },
                    set: { if !$0 { confirmDeleteClip = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let clip = confirmDeleteClip {
                        StudentPersonalLibraryStore.shared.deleteClip(clip)
                        clips = StudentPersonalLibraryStore.shared.loadClips()
                        confirmDeleteClip = nil
                    }
                }
            }
        }
    }
}

private struct StudentClipThumbnailView: View {
    let clip: StudentClip
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear {
                if let data = StudentPersonalLibraryStore.shared.imageData(for: clip) {
                    image = UIImage(data: data)
                }
            }
    }
}
#endif
