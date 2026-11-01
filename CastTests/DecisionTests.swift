import XCTest
@testable import Cast

final class DecisionTests: XCTestCase {
    private func option() -> DecisionOption {
        DecisionOption(value: "actor:jump", description: "A grounded hop", command: CharacterCommand(characterIDs: [UUID()], action: "jump", direction: nil, distance: nil, speech: nil))
    }
    func testRequestUsesDecisionsAndOnlyOfferedChoices() throws {
        let request = try DecisionAPI.request(key: "test-only", context: "measured geometry", options: [.wait, option()])
        XCTAssertEqual(request.url?.path, "/v1/decisions")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        let questions = try XCTUnwrap(body["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.first?["type"] as? String, "choice")
        XCTAssertEqual((questions.first?["choices"] as? [[String: String]])?.map { $0["value"]! }, ["wait", "actor:jump"])
    }
    func testRefusalAndUnknownChoiceNeverBecomeActions() throws {
        let options: [DecisionOption] = [.wait, option()]
        for json in [#"{"answers":[{"type":"refusal","name":"next_action"}]}"#,
                     #"{"answers":[{"type":"choice","name":"next_action","choice":"invented"}]}"#,
                     #"{"answers":[{"type":"choice","name":"wrong_question","choice":"actor:jump"}]}"#] {
            XCTAssertNil(try DecisionAPI.selection(Data(json.utf8), options: options))
        }
        let data = Data(#"{"answers":[{"type":"choice","name":"next_action","choice":"actor:jump","confidence":0.8}]}"#.utf8)
        XCTAssertEqual(try DecisionAPI.selection(data, options: options)?.command?.action, "jump")
    }
    @MainActor func testCancelledOrStaleRequestCannotMoveCharacters() async throws {
        for cancel in [true, false] {
            let director = DecisionDirector()
            let offered = option()
            var revision = 1
            var executions = 0
            var continuation: CheckedContinuation<(Data, URLResponse), Error>?
            let started = expectation(description: "request started")
            director.key = { "test-only" }
            director.ready = { true }
            director.options = { [.wait, offered] }
            director.revision = { revision }
            director.execute = { _ in executions += 1; return "Started jump" }
            director.transport = { _ in
                try await withCheckedThrowingContinuation { pending in
                    continuation = pending; started.fulfill()
                }
            }
            director.observe("PLAY_TICK")
            await fulfillment(of: [started], timeout: 2)
            if cancel { director.cancel() } else { revision += 1 }
            continuation?.resume(returning: (Data(#"{"answers":[{"type":"choice","name":"next_action","choice":"actor:jump"}]}"#.utf8), HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/decisions")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(executions, 0)
        }
    }
    @MainActor func testSuccessfulDecisionExecutesAndErrorsAreVisible() async {
        for code in [200, 401, 429] {
            let director = DecisionDirector()
            let offered = option()
            var executions = 0
            let finished = expectation(description: "decision outcome")
            director.key = { "test-only" }; director.ready = { true }; director.revision = { 1 }
            director.options = { [.wait, offered] }
            director.execute = { _ in executions += 1; return "Started jump" }
            director.statusChanged = { status in
                if status.hasPrefix("AI chose") || status.hasPrefix("Decisions unavailable") { finished.fulfill() }
            }
            director.transport = { _ in
                (Data(#"{"answers":[{"type":"choice","name":"next_action","choice":"actor:jump"}]}"#.utf8), HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/decisions")!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            }
            director.observe("PLAY_TICK")
            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(executions, code == 200 ? 1 : 0)
        }
    }
}
