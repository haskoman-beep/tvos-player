import Testing

// Temporary: proves that a red core test stops the CI build (Task 1.1 step 6). Reverted in the next commit.
@Test func ciGateMustStopBuild() {
    #expect(Bool(false))
}
