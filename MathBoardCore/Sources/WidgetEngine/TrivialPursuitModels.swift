//
//  TrivialPursuitModels.swift
//  WidgetEngine
//
//  Runtime game engine for the Trivial Pursuit Party widget.
//  Teacher hosts the game locally; live sync is a future phase.
//

import Foundation
import Observation

// MARK: - Game Phase

enum TrivialPursuitGamePhase: Equatable {
    case setup
    case categoryPick(activePlayerIndex: Int)
    case questionActive(categoryID: String, questionIndex: Int, activePlayerIndex: Int)
    case questionResult(categoryID: String, questionIndex: Int, winnerPlayerIndex: Int?, activePlayerIndex: Int)
    case gameWon(playerIndex: Int)
}

// MARK: - Player

struct TrivialPursuitGamePlayer: Identifiable, Equatable {
    var id: String
    var name: String
    var earnedCategoryIDs: Set<String>

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
        self.earnedCategoryIDs = []
    }
}

// MARK: - Game Engine

@Observable
final class TrivialPursuitGameEngine {
    var players: [TrivialPursuitGamePlayer] = []
    var phase: TrivialPursuitGamePhase = .setup
    var setupPlayerNames: [String] = ["", "", "", ""]
    private(set) var usedQuestionIndices: [String: Set<Int>] = [:]

    let document: ActivityWidgetDocument

    var categories: [TrivialPursuitCategory] {
        document.categories ?? []
    }

    init(document: ActivityWidgetDocument) {
        self.document = document
    }

    // MARK: - Setup

    func configurePlayers(from participants: [WidgetClassroomParticipant]) {
        let earnedCategoriesByPlayerID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.earnedCategoryIDs) })
        let uniqueParticipants = participants.reduce(into: [WidgetClassroomParticipant]()) { result, participant in
            guard !participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.contains(where: { $0.id == participant.id }) else { return }
            result.append(participant)
        }
        guard !uniqueParticipants.isEmpty else { return }
        players = uniqueParticipants.map { participant in
            var player = TrivialPursuitGamePlayer(id: participant.id, name: participant.displayName)
            player.earnedCategoryIDs = earnedCategoriesByPlayerID[participant.id] ?? []
            return player
        }
        setupPlayerNames = players.map(\.name)
    }

    func applyEarnedCategoryIDs(_ earnedCategoryIDsByParticipantID: [String: [String]]) {
        for index in players.indices {
            players[index].earnedCategoryIDs = Set(earnedCategoryIDsByParticipantID[players[index].id] ?? [])
        }
    }

    var earnedCategoryIDsByParticipantID: [String: [String]] {
        Dictionary(uniqueKeysWithValues: players.map { player in
            (player.id, player.earnedCategoryIDs.sorted())
        })
        .filter { !$0.value.isEmpty }
    }

    func startGame() {
        if !players.isEmpty {
            usedQuestionIndices = [:]
            phase = .categoryPick(activePlayerIndex: 0)
            return
        }

        let validNames = setupPlayerNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard validNames.count >= 2 else { return }
        players = validNames.map { TrivialPursuitGamePlayer(name: $0) }
        usedQuestionIndices = [:]
        phase = .categoryPick(activePlayerIndex: 0)
    }

    func addSetupPlayer() {
        guard setupPlayerNames.count < 8 else { return }
        setupPlayerNames.append("")
    }

    func removeLastSetupPlayer() {
        guard setupPlayerNames.count > 2 else { return }
        setupPlayerNames.removeLast()
    }

    var canStartGame: Bool {
        setupPlayerNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 2
    }

    // MARK: - Category Pick

    func pickCategory(_ categoryID: String, activePlayerIndex: Int) {
        guard let category = categories.first(where: { $0.id == categoryID }),
              !category.questions.isEmpty else { return }

        var used = usedQuestionIndices[categoryID] ?? []
        if used.count >= category.questions.count {
            used = []
            usedQuestionIndices[categoryID] = []
        }

        let available = category.questions.indices.filter { !used.contains($0) }
        guard let questionIndex = available.randomElement() else { return }
        phase = .questionActive(categoryID: categoryID, questionIndex: questionIndex, activePlayerIndex: activePlayerIndex)
    }

    // MARK: - Award & Advance

    func awardWedge(toPlayerIndex playerIndex: Int?, forCategoryID categoryID: String, questionIndex: Int, activePlayerIndex: Int) {
        if let playerIndex, playerIndex < players.count {
            players[playerIndex].earnedCategoryIDs.insert(categoryID)
        }
        var used = usedQuestionIndices[categoryID] ?? []
        used.insert(questionIndex)
        usedQuestionIndices[categoryID] = used

        if let playerIndex, players[playerIndex].earnedCategoryIDs.count == categories.count {
            phase = .gameWon(playerIndex: playerIndex)
        } else {
            phase = .questionResult(
                categoryID: categoryID,
                questionIndex: questionIndex,
                winnerPlayerIndex: playerIndex,
                activePlayerIndex: activePlayerIndex
            )
        }
    }

    func advanceTurn(winnerPlayerIndex: Int?, currentActivePlayerIndex: Int) {
        let nextActivePlayerIndex: Int
        if let winner = winnerPlayerIndex {
            nextActivePlayerIndex = winner
        } else {
            nextActivePlayerIndex = (currentActivePlayerIndex + 1) % max(players.count, 1)
        }
        phase = .categoryPick(activePlayerIndex: nextActivePlayerIndex)
    }

    // MARK: - Reset

    func resetGame() {
        players = []
        usedQuestionIndices = [:]
        phase = .setup
    }

    // MARK: - Helpers

    func question(forCategoryID categoryID: String, at index: Int) -> TrivialPursuitQuestion? {
        guard let category = categories.first(where: { $0.id == categoryID }),
              category.questions.indices.contains(index) else { return nil }
        return category.questions[index]
    }

    func category(forID id: String) -> TrivialPursuitCategory? {
        categories.first { $0.id == id }
    }
}
