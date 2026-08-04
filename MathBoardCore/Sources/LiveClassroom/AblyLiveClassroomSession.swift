//
//  AblyLiveClassroomSession.swift
//  MathBoardCore - LiveClassroom module
//

import Ably
import Foundation

@MainActor
public protocol LiveClassroomSessioning: AnyObject {
    var onTeacherInkChunk: ((TeacherInkStrokeChunk) -> Void)? { get set }
    var onTeacherInkDrawingSnapshot: ((TeacherInkDrawingSnapshot) -> Void)? { get set }
    var onTeacherObjectSnapshot: ((TeacherObjectSnapshot) -> Void)? { get set }
    var onTeacherSlideManifestSnapshot: ((TeacherSlideManifestSnapshot) -> Void)? { get set }
    var lastErrorMessage: String? { get }

    func start()
    func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk)
    func publishTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot)
    func publishTeacherObjectSnapshot(_ snapshot: TeacherObjectSnapshot)
    func publishTeacherSlideManifestSnapshot(_ snapshot: TeacherSlideManifestSnapshot)
    func stop()
}

@MainActor
public final class AblyLiveClassroomSession: LiveClassroomSessioning {
    public var onTeacherInkChunk: ((TeacherInkStrokeChunk) -> Void)?
    public var onTeacherInkDrawingSnapshot: ((TeacherInkDrawingSnapshot) -> Void)?
    public var onTeacherObjectSnapshot: ((TeacherObjectSnapshot) -> Void)?
    public var onTeacherSlideManifestSnapshot: ((TeacherSlideManifestSnapshot) -> Void)?
    public private(set) var lastErrorMessage: String?

    private let configuration: LiveClassroomSessionConfiguration
    private let realtime: ARTRealtime
    private let inkChannel: ARTRealtimeChannel
    private let objectChannel: ARTRealtimeChannel
    private let slideChannel: ARTRealtimeChannel
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: LiveClassroomSessionConfiguration) {
        self.configuration = configuration
        let options = ARTClientOptions(key: configuration.apiKey)
        options.clientId = configuration.clientID
        self.realtime = ARTRealtime(options: options)
        self.inkChannel = realtime.channels.get(configuration.inkChannelName)
        self.objectChannel = realtime.channels.get(configuration.objectChannelName)
        self.slideChannel = realtime.channels.get(configuration.slideChannelName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    deinit {
        inkChannel.unsubscribe()
        objectChannel.unsubscribe()
        slideChannel.unsubscribe()
        realtime.close()
    }

    public func start() {
        guard configuration.role == .student else { return }
        subscribeToTeacherInk()
        subscribeToTeacherInkDrawingSnapshots()
        subscribeToTeacherObjects()
        subscribeToTeacherSlides()
        loadRecentTeacherInkHistory()
        loadRecentTeacherObjectHistory()
        loadRecentTeacherSlideHistory()
    }

    public func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) {
        guard configuration.role == .teacher else { return }
        publish(chunk, eventName: "teacher-ink", channel: inkChannel, fallbackError: "Teacher ink payload could not be encoded.")
    }

    public func publishTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) {
        guard configuration.role == .teacher else { return }
        publish(snapshot, eventName: "teacher-ink-drawing-snapshot", channel: inkChannel, fallbackError: "Teacher ink snapshot payload could not be encoded.")
    }

    public func publishTeacherObjectSnapshot(_ snapshot: TeacherObjectSnapshot) {
        guard configuration.role == .teacher else { return }
        publish(snapshot, eventName: "teacher-object-snapshot", channel: objectChannel, fallbackError: "Teacher object payload could not be encoded.")
    }

    public func publishTeacherSlideManifestSnapshot(_ snapshot: TeacherSlideManifestSnapshot) {
        guard configuration.role == .teacher else { return }
        publish(snapshot, eventName: "teacher-slide-manifest", channel: slideChannel, fallbackError: "Teacher slide payload could not be encoded.")
    }

    public func stop() {
        inkChannel.unsubscribe()
        objectChannel.unsubscribe()
        slideChannel.unsubscribe()
        realtime.close()
    }

    private func publish<T: Encodable>(_ value: T, eventName: String, channel: ARTRealtimeChannel, fallbackError: String) {
        do {
            let data = try encoder.encode(value)
            guard let payload = String(data: data, encoding: .utf8) else {
                lastErrorMessage = fallbackError
                return
            }
            channel.publish(eventName, data: payload) { [weak self] error in
                Task { @MainActor in
                    self?.lastErrorMessage = error?.message
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func subscribeToTeacherInk() {
        inkChannel.subscribe("teacher-ink") { [weak self] message in
            Task { @MainActor in
                self?.handleTeacherInkMessage(message)
            }
        }
    }

    private func subscribeToTeacherInkDrawingSnapshots() {
        inkChannel.subscribe("teacher-ink-drawing-snapshot") { [weak self] message in
            Task { @MainActor in
                self?.handleTeacherInkDrawingSnapshotMessage(message)
            }
        }
    }

    private func subscribeToTeacherObjects() {
        objectChannel.subscribe("teacher-object-snapshot") { [weak self] message in
            Task { @MainActor in
                self?.handleTeacherObjectMessage(message)
            }
        }
    }

    private func subscribeToTeacherSlides() {
        slideChannel.subscribe("teacher-slide-manifest") { [weak self] message in
            Task { @MainActor in
                self?.handleTeacherSlideMessage(message)
            }
        }
    }

    private func loadRecentTeacherInkHistory() {
        do {
            try inkChannel.history(nil) { [weak self] result, error in
                Task { @MainActor in
                    if let error {
                        self?.lastErrorMessage = error.message
                        return
                    }

                    for message in result?.items.reversed() ?? [] {
                        self?.handleTeacherInkHistoryMessage(message)
                    }
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func loadRecentTeacherObjectHistory() {
        do {
            try objectChannel.history(nil) { [weak self] result, error in
                Task { @MainActor in
                    if let error {
                        self?.lastErrorMessage = error.message
                        return
                    }

                    for message in result?.items.reversed() ?? [] {
                        self?.handleTeacherObjectMessage(message)
                    }
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func loadRecentTeacherSlideHistory() {
        do {
            try slideChannel.history(nil) { [weak self] result, error in
                Task { @MainActor in
                    if let error {
                        self?.lastErrorMessage = error.message
                        return
                    }

                    for message in result?.items.reversed() ?? [] {
                        self?.handleTeacherSlideMessage(message)
                    }
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleTeacherInkHistoryMessage(_ message: ARTMessage) {
        switch message.name {
        case "teacher-ink-drawing-snapshot":
            handleTeacherInkDrawingSnapshotMessage(message)
        case "teacher-ink":
            handleTeacherInkMessage(message)
        default:
            break
        }
    }

    private func handleTeacherInkMessage(_ message: ARTMessage) {
        guard let payload = message.data as? String,
              let data = payload.data(using: .utf8) else {
            return
        }

        do {
            let chunk = try decoder.decode(TeacherInkStrokeChunk.self, from: data)
            guard chunk.lessonCode == configuration.lessonCode else { return }
            onTeacherInkChunk?(chunk)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleTeacherInkDrawingSnapshotMessage(_ message: ARTMessage) {
        guard let payload = message.data as? String,
              let data = payload.data(using: .utf8) else {
            return
        }

        do {
            let snapshot = try decoder.decode(TeacherInkDrawingSnapshot.self, from: data)
            guard snapshot.lessonCode == configuration.lessonCode else { return }
            onTeacherInkDrawingSnapshot?(snapshot)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleTeacherObjectMessage(_ message: ARTMessage) {
        guard let payload = message.data as? String,
              let data = payload.data(using: .utf8) else {
            return
        }

        do {
            let snapshot = try decoder.decode(TeacherObjectSnapshot.self, from: data)
            guard snapshot.lessonCode == configuration.lessonCode else { return }
            onTeacherObjectSnapshot?(snapshot)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleTeacherSlideMessage(_ message: ARTMessage) {
        guard let payload = message.data as? String,
              let data = payload.data(using: .utf8) else {
            return
        }

        do {
            let snapshot = try decoder.decode(TeacherSlideManifestSnapshot.self, from: data)
            guard snapshot.lessonCode == configuration.lessonCode else { return }
            onTeacherSlideManifestSnapshot?(snapshot)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
