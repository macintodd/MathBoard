//
//  AblyLiveClassroomSession.swift
//  MathBoardCore - LiveClassroom module
//

import Ably
import Foundation

@MainActor
public protocol LiveClassroomSessioning: AnyObject {
    var onTeacherInkChunk: ((TeacherInkStrokeChunk) -> Void)? { get set }
    var lastErrorMessage: String? { get }

    func start()
    func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk)
    func stop()
}

@MainActor
public final class AblyLiveClassroomSession: LiveClassroomSessioning {
    public var onTeacherInkChunk: ((TeacherInkStrokeChunk) -> Void)?
    public private(set) var lastErrorMessage: String?

    private let configuration: LiveClassroomSessionConfiguration
    private let realtime: ARTRealtime
    private let channel: ARTRealtimeChannel
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: LiveClassroomSessionConfiguration) {
        self.configuration = configuration
        let options = ARTClientOptions(key: configuration.apiKey)
        options.clientId = configuration.clientID
        self.realtime = ARTRealtime(options: options)
        self.channel = realtime.channels.get(configuration.inkChannelName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    deinit {
        channel.unsubscribe()
        realtime.close()
    }

    public func start() {
        guard configuration.role == .student else { return }
        subscribeToTeacherInk()
        loadRecentTeacherInkHistory()
    }

    public func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) {
        guard configuration.role == .teacher else { return }

        do {
            let data = try encoder.encode(chunk)
            guard let payload = String(data: data, encoding: .utf8) else {
                lastErrorMessage = "Teacher ink payload could not be encoded."
                return
            }
            channel.publish("teacher-ink", data: payload) { [weak self] error in
                Task { @MainActor in
                    self?.lastErrorMessage = error?.message
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func stop() {
        channel.unsubscribe()
        realtime.close()
    }

    private func subscribeToTeacherInk() {
        channel.subscribe("teacher-ink") { [weak self] message in
            Task { @MainActor in
                self?.handleTeacherInkMessage(message)
            }
        }
    }

    private func loadRecentTeacherInkHistory() {
        do {
            try channel.history(nil) { [weak self] result, error in
                Task { @MainActor in
                    if let error {
                        self?.lastErrorMessage = error.message
                        return
                    }

                    for message in result?.items.reversed() ?? [] {
                        self?.handleTeacherInkMessage(message)
                    }
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
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
}
