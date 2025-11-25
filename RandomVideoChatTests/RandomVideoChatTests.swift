//
//  RandomVideoChatTests.swift
//  RandomVideoChatTests
//
//  Created by iMac on 2025/08/04.
//

import XCTest
@testable import RandomVideoChat

// MARK: - AppError Tests
final class AppErrorTests: XCTestCase {

    func testAuthenticationErrorDescription() {
        let error = AppError.authenticationFailed(underlying: nil)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("인증 실패") ?? false)
    }

    func testNetworkErrorDescription() {
        let error = AppError.networkUnavailable
        XCTAssertEqual(error.errorDescription, "네트워크에 연결할 수 없습니다")
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testMatchingErrorDescription() {
        let error = AppError.noUsersAvailable
        XCTAssertEqual(error.errorDescription, "현재 대기 중인 사용자가 없습니다")
    }

    func testServerErrorWithCode() {
        let error = AppError.serverError(statusCode: 500)
        XCTAssertTrue(error.errorDescription?.contains("500") ?? false)
    }

    func testErrorConversion() {
        let nsError = NSError(domain: "test", code: 1)
        let appError = nsError.asAppError

        if case .unknown = appError {
            // Expected
        } else {
            XCTFail("Expected unknown error type")
        }
    }

    func testInsufficientHeartsRecoverySuggestion() {
        let error = AppError.insufficientHearts
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion?.contains("하트") ?? false)
    }
}

// MARK: - DependencyContainer Tests
final class DependencyContainerTests: XCTestCase {

    func testSharedInstanceExists() {
        let container = DependencyContainer.shared
        XCTAssertNotNil(container)
    }

    func testEnvironmentDetection() {
        let container = DependencyContainer.shared

        #if DEBUG
        XCTAssertTrue(container.isDevelopment)
        XCTAssertEqual(container.environment, .development)
        #else
        XCTAssertFalse(container.isDevelopment)
        XCTAssertEqual(container.environment, .production)
        #endif
    }

    func testManagersAccessible() {
        let container = DependencyContainer.shared

        // Verify managers are accessible (not nil)
        XCTAssertNotNil(container.userManager)
        XCTAssertNotNil(container.matchingManager)
        XCTAssertNotNil(container.agoraManager)
        XCTAssertNotNil(container.contentModerationManager)
        XCTAssertNotNil(container.performanceMonitor)
        XCTAssertNotNil(container.imageCacheManager)
        XCTAssertNotNil(container.tokenService)
    }
}

// MARK: - User Model Tests
final class UserModelTests: XCTestCase {

    func testUserInitialization() {
        let user = User(uid: "test123", email: "test@example.com", displayName: "Test User")

        XCTAssertEqual(user.uid, "test123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertEqual(user.heartCount, 3) // 초기 하트 3개
        XCTAssertTrue(user.blockedUsers.isEmpty)
        XCTAssertNil(user.gender)
        XCTAssertNil(user.preferredGender)
    }

    func testUserDictionary() {
        let user = User(uid: "test123")
        let dict = user.dictionary

        XCTAssertEqual(dict["uid"] as? String, "test123")
        XCTAssertEqual(dict["heartCount"] as? Int, 3)
        XCTAssertNotNil(dict["createdAt"])
    }
}

// MARK: - Gender Tests
final class GenderTests: XCTestCase {

    func testGenderDisplayNames() {
        XCTAssertEqual(Gender.male.displayName, "남")
        XCTAssertEqual(Gender.female.displayName, "여")
    }

    func testGenderRawValues() {
        XCTAssertEqual(Gender.male.rawValue, "male")
        XCTAssertEqual(Gender.female.rawValue, "female")
    }

    func testGenderIcons() {
        XCTAssertEqual(Gender.male.icon, "person.fill")
        XCTAssertEqual(Gender.female.icon, "person.fill")
    }
}

// MARK: - Performance Tests
final class PerformanceTests: XCTestCase {

    func testAppLoggerPerformance() throws {
        measure {
            for _ in 0..<1000 {
                AppLogger.app.debug("Performance test message")
            }
        }
    }
}
