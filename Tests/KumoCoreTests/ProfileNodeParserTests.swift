import XCTest
@testable import KumoCoreKit

final class ProfileNodeParserTests: XCTestCase {
    func testParsesNodesFromMinimalProxiesArray() throws {
        let yaml = """
        proxies:
          - name: HK 01
            type: ss
            server: hk-01.example.com
            port: 8388
            cipher: aes-128-gcm
            password: secret
          - name: JP 02
            type: vmess
            server: 198.51.100.42
            port: 443
            uuid: deadbeef
        """

        let nodes = try ProfileNodeParser.parseNodes(yaml: yaml)

        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes["HK 01"]?.server, "hk-01.example.com")
        XCTAssertEqual(nodes["HK 01"]?.port, 8388)
        XCTAssertEqual(nodes["JP 02"]?.server, "198.51.100.42")
        XCTAssertEqual(nodes["JP 02"]?.port, 443)
    }

    func testIgnoresMalformedEntries() throws {
        let yaml = """
        proxies:
          - name: ok
            server: ok.example.com
          - name: missing-server
          - server: missing-name.example.com
          - "not-a-dict"
          - name: empty-server
            server: "   "
        """

        let nodes = try ProfileNodeParser.parseNodes(yaml: yaml)
        XCTAssertEqual(nodes.keys.sorted(), ["ok"])
        XCTAssertEqual(nodes["ok"]?.server, "ok.example.com")
    }

    func testReturnsEmptyForMissingProxiesKey() throws {
        let yaml = """
        proxy-groups:
          - name: Select
            type: select
            proxies: [DIRECT]
        rules:
          - MATCH,DIRECT
        """
        XCTAssertEqual(try ProfileNodeParser.parseNodes(yaml: yaml), [:])
    }

    func testReturnsEmptyForBlankInput() throws {
        XCTAssertEqual(try ProfileNodeParser.parseNodes(yaml: ""), [:])
        XCTAssertEqual(try ProfileNodeParser.parseNodes(yaml: "   \n\n"), [:])
    }

    func testTrimsServerWhitespace() throws {
        let yaml = """
        proxies:
          - name: padded
            server: "  padded.example.com  "
        """
        XCTAssertEqual(try ProfileNodeParser.parseNodes(yaml: yaml)["padded"]?.server, "padded.example.com")
    }

    func testParsesPortFromString() throws {
        let yaml = """
        proxies:
          - name: string-port
            server: sp.example.com
            port: "1080"
        """
        XCTAssertEqual(try ProfileNodeParser.parseNodes(yaml: yaml)["string-port"]?.port, 1080)
    }

    // MARK: - parseProxyGroups

    func testParsesProxyGroupsWithNodePlaceholders() throws {
        let yaml = """
        proxies:
          - name: HK 01
            type: ss
            server: hk-01.example.com
            port: 8388
        proxy-groups:
          - name: Manual
            type: select
            proxies:
              - HK 01
              - JP 02
              - DIRECT
          - name: Auto
            type: url-test
            proxies:
              - HK 01
              - JP 02
            url: https://www.gstatic.com/generate_204
            interval: 300
        """

        let groups = try ProfileNodeParser.parseProxyGroups(yaml: yaml)

        XCTAssertEqual(groups.map(\.name), ["Auto", "Manual"]) // sorted
        XCTAssertEqual(groups.first(where: { $0.name == "Manual" })?.proxies.map(\.name), ["HK 01", "JP 02", "DIRECT"])
        XCTAssertEqual(groups.first(where: { $0.name == "Auto" })?.proxies.map(\.name), ["HK 01", "JP 02"])

        let manual = try XCTUnwrap(groups.first(where: { $0.name == "Manual" }))
        XCTAssertNil(manual.selectedProxyName, "Selection is mihomo runtime state — should be nil for preview")
        XCTAssertNil(manual.testURL)
        for node in manual.proxies {
            XCTAssertNil(node.delay, "Delay is unknown until the core measures it")
            XCTAssertNil(node.type)
            XCTAssertNil(node.detectedCountry)
        }
    }

    func testParseProxyGroupsIgnoresMissingNameOrProxies() throws {
        let yaml = """
        proxy-groups:
          - name: ok
            proxies: [DIRECT]
          - type: select          # missing name
            proxies: [DIRECT]
          - name: empty
            proxies: []           # no nodes -> dropped
          - name: blank
            proxies:
              - "   "             # whitespace-only entries skipped
          - "not-a-dict"
        """
        let groups = try ProfileNodeParser.parseProxyGroups(yaml: yaml)
        XCTAssertEqual(groups.map(\.name), ["ok"])
        XCTAssertEqual(groups.first?.proxies.map(\.name), ["DIRECT"])
    }

    func testParseProxyGroupsReturnsEmptyWhenKeyMissing() throws {
        let yaml = """
        proxies: []
        rules:
          - MATCH,DIRECT
        """
        XCTAssertEqual(try ProfileNodeParser.parseProxyGroups(yaml: yaml), [])
    }

    func testParseProxyGroupsReturnsEmptyForBlankInput() throws {
        XCTAssertEqual(try ProfileNodeParser.parseProxyGroups(yaml: ""), [])
        XCTAssertEqual(try ProfileNodeParser.parseProxyGroups(yaml: "\n\n"), [])
    }
}
