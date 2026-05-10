//
//  NotificationCategoryUseCases.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// Use cases for registering and removing notification categories and actions.
public final class NotificationCategoryUseCases {

    private let TAG = "NotificationCategoryUseCases"
    private let repository: NotificationRepository
    private var registeredCategories: [NotificationCategory] = []

    public init(repository: NotificationRepository) {
        Log.d(TAG, "init")
        self.repository = repository
    }

    // MARK: - Use Cases

    /// Registers a notification category (overwrites any existing category with the same id).
    ///
    /// - Parameters:
    ///   - category: The category to register.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func registerCategory(
        _ category: NotificationCategory,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "registerCategory called with id: \(category.id)")
        guard !category.id.isEmpty, category.id.count <= 64 else {
            let error = NotificationDomainError.invalidCategory(reason: "id must be 1-64 characters")
            Log.e(TAG, "registerCategory validation failed: \(error.errorMessage)")
            completion(.failure(error))
            return
        }
        registeredCategories = registeredCategories.filter { $0.id != category.id }
        registeredCategories.append(category)
        repository.setCategories(registeredCategories)
        completion(.success(()))
    }

    /// Removes the category with the given identifier.
    ///
    /// - Parameters:
    ///   - identifier: The category identifier to remove.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func removeCategory(
        identifier: String,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "removeCategory called with identifier: \(identifier)")
        guard !identifier.isEmpty else {
            let error = NotificationDomainError.invalidCategory(reason: "identifier must not be empty")
            Log.e(TAG, "removeCategory validation failed: \(error.errorMessage)")
            completion(.failure(error))
            return
        }
        registeredCategories = registeredCategories.filter { $0.id != identifier }
        repository.setCategories(registeredCategories)
        completion(.success(()))
    }
}
