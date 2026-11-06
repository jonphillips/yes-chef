import ChatAccessKit
import Foundation
import MCPServerKit
import YesChefMCPServer

@main
enum YesChefMCP {
  static func main() async {
    ChatAccessHelperProcess.enableDatalessMaterialization()
    do {
      let isDevelopment = try ChatAccessHelperFolder.isDevelopment(arguments: CommandLine.arguments)
      await YesChefMCPServer.make(isDevelopment: isDevelopment).run()
    } catch {
      FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}
