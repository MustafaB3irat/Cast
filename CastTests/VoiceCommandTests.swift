import XCTest
@testable import Cast

@MainActor final class VoiceCommandTests: XCTestCase {
    private let character = CastCharacter.defaults[0]

    private func command(_ action: String) -> CharacterCommand {
        CharacterCommand(characterIDs: [character.id], action: action, direction: nil, distance: nil, speech: nil)
    }
    private func completed(_ actions: [CharacterCommand], id: String = "r1", status: String = "completed") throws -> [String: Any] {
        let data = try JSONEncoder().encode(CommandBatch(actions: actions))
        return ["type": "response.done", "response": ["id": id, "status": status, "output": [[
            "type": "function_call", "name": "act", "call_id": "c-" + id,
            "arguments": String(decoding: data, as: UTF8.self)
        ]]]]
    }
    private func director() -> LiveDirector {
        let voice = LiveDirector()
        voice.eventSink = { _ in }
        voice.updateRoster([character])
        voice.commandReady = { _ in true }
        return voice
    }

    func testOnlyCompletedResponseExecutesAndDuplicateIsIgnored() async throws {
        let voice = director()
        var actions: [String] = []
        let executed = expectation(description: "executed")
        voice.execute = { command in actions.append(command.action); executed.fulfill(); return "Started wave" }
        voice.handle(["type": "response.function_call_arguments.done", "name": "act"])
        XCTAssertTrue(actions.isEmpty)
        let event = try completed([command("wave")])
        voice.handle(event)
        await fulfillment(of: [executed], timeout: 1)
        voice.handle(event)
        await Task.yield()
        XCTAssertEqual(actions, ["wave"])
    }

    func testCancelledResponseNeverExecutes() async throws {
        let voice = director()
        var count = 0
        voice.execute = { _ in count += 1; return "Started" }
        voice.handle(try completed([command("wave")], status: "cancelled"))
        await Task.yield()
        XCTAssertEqual(count, 0)
    }

    func testSameCharacterActionsWaitInsteadOfOverwriting() async throws {
        let voice = director()
        var ready = false
        var actions: [String] = []
        let first = expectation(description: "wave")
        let second = expectation(description: "jump")
        voice.commandReady = { _ in ready }
        voice.execute = { command in
            actions.append(command.action)
            if command.action == "wave" { first.fulfill() } else { second.fulfill() }
            return "Started " + command.action
        }
        voice.handle(try completed([command("wave"), command("jump")]))
        await fulfillment(of: [first], timeout: 1)
        XCTAssertEqual(actions, ["wave"])
        ready = true
        await fulfillment(of: [second], timeout: 1)
        XCTAssertEqual(actions, ["wave", "jump"])
    }

    func testStopCancelsQueuedActionAndNewSpeechAllowsNextCommand() async throws {
        let voice = director()
        var actions: [String] = []
        let first = expectation(description: "first")
        let next = expectation(description: "new command")
        voice.commandReady = { _ in false }
        voice.execute = { command in
            actions.append(command.action)
            if command.action == "wave" { first.fulfill() }
            if command.action == "inspect" { next.fulfill() }
            return "Started " + command.action
        }
        voice.handle(try completed([command("wave"), command("jump")]))
        await fulfillment(of: [first], timeout: 1)
        voice.stopSpeech()
        voice.handle(["type": "input_audio_buffer.speech_started"])
        voice.handle(["type": "input_audio_buffer.speech_stopped"])
        voice.handle(try completed([command("inspect")], id: "r2"))
        await fulfillment(of: [next], timeout: 1)
        XCTAssertEqual(actions, ["wave", "inspect"])
    }

    func testRejectionIsVisibleAndFollowUpCannotRepeatTools() async throws {
        let voice = director()
        let replied = expectation(description: "tool result follow-up")
        var events: [[String: Any]] = []
        voice.execute = { _ in "Jump needs a stable scanned surface" }
        voice.eventSink = { event in
            events.append(event)
            if event["type"] as? String == "response.create" { replied.fulfill() }
        }
        voice.handle(try completed([command("jump")]))
        await fulfillment(of: [replied], timeout: 1)
        XCTAssertEqual(voice.commandResult, "Jump needs a stable scanned surface")
        let followup = try XCTUnwrap(events.last?["response"] as? [String: Any])
        XCTAssertEqual(followup["tool_choice"] as? String, "none")
        XCTAssertEqual((events.first?["item"] as? [String: Any])?["output"] as? String, voice.commandResult)
    }

    func testLateOldCompletionDoesNotDiscardNewResponse() async throws {
        let voice = director()
        var actions: [String] = []
        let executed = expectation(description: "new response executes")
        voice.execute = { command in actions.append(command.action); executed.fulfill(); return "Started" }
        voice.handle(["type": "response.created", "response": ["id": "old"]])
        voice.handle(["type": "input_audio_buffer.speech_started"])
        voice.handle(["type": "response.created", "response": ["id": "new"]])
        voice.handle(try completed([command("wave")], id: "old"))
        voice.handle(try completed([command("inspect")], id: "new"))
        await fulfillment(of: [executed], timeout: 1)
        XCTAssertEqual(actions, ["inspect"])
    }
    func testTextOnlyReplyDoesNotLeaveCommandStuckInterpreting() {
        let voice = director()
        voice.handle(["type": "input_audio_buffer.speech_started"])
        voice.handle(["type": "conversation.item.input_audio_transcription.completed", "transcript": "Who is this?"])
        voice.handle(["type": "response.done", "response": ["id": "clarification", "status": "completed", "output": []]])
        XCTAssertEqual(voice.heardText, "Who is this?")
        XCTAssertEqual(voice.commandResult, "No action selected · see latest response")
    }

}
