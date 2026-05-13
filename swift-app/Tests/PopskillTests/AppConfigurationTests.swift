@testable import Popskill
import Testing

struct AppConfigurationTests {
    @Test
    func sparkleConfigurationRequiresFeedURLAndPublicKey() {
        let ready = SparkleConfiguration(infoDictionary: [
            "SUFeedURL": " https://updates.example.com/appcast.xml ",
            "SUPublicEDKey": " public-key "
        ])

        #expect(ready.feedURL == "https://updates.example.com/appcast.xml")
        #expect(ready.publicEDKey == "public-key")
        #expect(ready.isReady)

        let missingKey = SparkleConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.com/appcast.xml"
        ])

        #expect(!missingKey.isReady)
    }
}
