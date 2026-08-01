//
//  FirebaseMathtivityCatalogService.swift
//  Library
//
//  Reads the online JSON mathtivity catalog from Firestore and downloads the
//  selected JSON payload from Firebase Storage.
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation
import WidgetEngine

@MainActor
public struct FirebaseMathtivityCatalogService: MathtivityCatalogProviding {
    private static let collectionName = "mathtivityCatalog"
    private static let defaultJSONMaxSize: Int64 = 1 * 1024 * 1024
    private static let defaultThumbnailMaxSize: Int64 = 5 * 1024 * 1024

    private var firestore: Firestore
    private var storage: Storage

    public init(
        firestore: Firestore = Firestore.firestore(),
        storage: Storage = Storage.storage()
    ) {
        self.firestore = firestore
        self.storage = storage
    }

    public func fetchPublishedCatalog(limit: Int = 80) async throws -> [MathtivityCatalogItem] {
        let bundledItems = JSONMathtivityCatalog.bundledEntries.compactMap(MathtivityCatalogItem.init(bundledEntry:))

        let snapshot: QuerySnapshot
        do {
            try await Self.ensureAuthenticatedAccess()
            snapshot = try await getDocuments(
                from: firestore
                    .collection(Self.collectionName)
                    .whereField("isPublished", isEqualTo: true)
                    .limit(to: limit)
            )
        } catch {
            return bundledItems
        }

        let onlineItems = snapshot.documents.compactMap { document in
            var data = document.data()
            if let timestamp = data["updatedAt"] as? Timestamp {
                data["updatedAt"] = timestamp.dateValue()
            }
            return MathtivityCatalogItem(id: document.documentID, firestoreData: data)
        }
        .sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        let bundledIDs = Set(bundledItems.map(\.id))
        return bundledItems + onlineItems.filter { !bundledIDs.contains($0.id) }
    }

    public func downloadMathtivity(_ item: MathtivityCatalogItem) async throws -> DownloadedMathtivityCatalogItem {
        if let bundledResourceName = item.bundledResourceName,
           let bundledEntry = JSONMathtivityCatalog.bundledEntries.first(where: { $0.resourceName == bundledResourceName }),
           let source = JSONMathtivityCatalog.source(for: bundledEntry) {
            return DownloadedMathtivityCatalogItem(item: item, jsonSource: source)
        }

        try await Self.ensureAuthenticatedAccess()
        let jsonData = try await getData(
            from: storage.reference(withPath: item.jsonStoragePath),
            maxSize: Self.defaultJSONMaxSize
        )
        guard let jsonSource = String(data: jsonData, encoding: .utf8) else {
            throw MathtivityCatalogError.invalidJSONText
        }

        let thumbnailData: Data?
        if let thumbnailStoragePath = item.thumbnailStoragePath,
           !thumbnailStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            thumbnailData = try? await getData(
                from: storage.reference(withPath: thumbnailStoragePath),
                maxSize: Self.defaultThumbnailMaxSize
            )
        } else {
            thumbnailData = nil
        }

        return DownloadedMathtivityCatalogItem(
            item: item,
            jsonSource: jsonSource,
            thumbnailPNGData: thumbnailData
        )
    }

    private static func ensureAuthenticatedAccess() async throws {
        guard FirebaseApp.app() != nil else {
            throw MathtivityCatalogError.firebaseNotConfigured
        }
        if let currentUserID = Auth.auth().currentUser?.uid, !currentUserID.isEmpty {
            return
        }
        _ = try await Auth.auth().signInAnonymously()
    }

    private func getDocuments(from query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let snapshot else {
                    continuation.resume(throwing: MathtivityCatalogError.missingCatalog)
                    return
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func getData(from reference: StorageReference, maxSize: Int64) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            reference.getData(maxSize: maxSize) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: MathtivityCatalogError.missingStorageObject)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

public enum MathtivityCatalogError: LocalizedError, Sendable {
    case firebaseNotConfigured
    case missingCatalog
    case missingStorageObject
    case invalidJSONText
    case invalidJSONMathtivity([String])

    public var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase is not configured. Confirm GoogleService-Info.plist is included in the MathBoard app target."
        case .missingCatalog:
            return "MathBoard could not read the online mathtivity catalog."
        case .missingStorageObject:
            return "MathBoard could not download that mathtivity."
        case .invalidJSONText:
            return "That mathtivity is not valid UTF-8 JSON text."
        case let .invalidJSONMathtivity(errors):
            return "That mathtivity did not pass the JSON widget test contract: \(errors.joined(separator: " "))"
        }
    }
}
