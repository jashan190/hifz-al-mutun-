import Testing
@testable import HifzAlMutun

@Suite struct MockSpeechSourceTests {
    @Test func emitsScriptedFragments() async throws {
        let mock = MockSpeechSource(script: [
            .init(text: "يقول", isFinal: false),
            .init(text: "يقول راجي", isFinal: true),
        ])
        var got: [String] = []
        try await mock.start()
        for await f in mock.fragments { got.append(f.text) }
        #expect(got == ["يقول", "يقول راجي"])
    }
}
