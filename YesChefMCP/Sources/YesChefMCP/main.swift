import ChatAccessKit
import Darwin
import Foundation
import MCPServerKit
import YesChefMCPServer

@main
enum YesChefMCP {
  static func main() async {
    _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_ON)
    do {
      let isDevelopment = try ChatAccessHelperFolder.isDevelopment(arguments: CommandLine.arguments)
      await YesChefMCPServer.make(isDevelopment: isDevelopment).run()
    } catch {
      FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}
