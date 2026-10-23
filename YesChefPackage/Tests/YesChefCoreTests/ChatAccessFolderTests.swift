import Foundation
import Testing
import YesChefCore

struct ChatAccessFolderTests {
  @Test func resolvesProductionInboxAndProcessedFolders() {
    let container = URL(fileURLWithPath: "/tmp/ubiquity", isDirectory: true)
    let folder = ChatAccessFolder(containerURL: container)

    #expect(folder.url.path == "/tmp/ubiquity/MCP")
    #expect(folder.inboxURL.path == "/tmp/ubiquity/MCP/Inbox")
    #expect(folder.processedURL.path == "/tmp/ubiquity/MCP/Inbox/Processed")
  }

  @Test func resolvesDevelopmentFolder() {
    let container = URL(fileURLWithPath: "/tmp/ubiquity", isDirectory: true)

    #expect(ChatAccessFolder(containerURL: container, isDevelopment: true).url.path == "/tmp/ubiquity/MCP-Dev")
  }
}
