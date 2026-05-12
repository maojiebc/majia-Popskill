@testable import Popskill
import Testing

struct KeychainServiceTests {
    @Test
    func accountNameNormalizesWhitespaceAndCase() {
        #expect(KeychainService.accountName(for: "  WebDAV Password  ") == "webdav-password")
    }
}
