import Foundation
import Testing
import YesChefCore

struct ChatAccessFolderTests {
  @Test func resolvesProductionFolderAndProbeFolder() {
    let container = URL(fileURLWithPath: "/tmp/ubiquity", isDirectory: true)
    let folder = ChatAccessFolder(containerURL: container)

    #expect(folder.url.path == "/tmp/ubiquity/MCP")
    #expect(folder.probeURL.path == "/tmp/ubiquity/MCP/Probe")
  }

  @Test func resolvesDevelopmentFolder() {
    let container = URL(fileURLWithPath: "/tmp/ubiquity", isDirectory: true)

    #expect(ChatAccessFolder(containerURL: container, isDevelopment: true).url.path == "/tmp/ubiquity/MCP-Dev")
  }
}
