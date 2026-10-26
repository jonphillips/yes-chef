import Darwin
import MCPServerKit
import YesChefMCPServer

@main
enum YesChefMCP {
  static func main() async {
    _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_ON)
    await YesChefMCPServer.make().run()
  }
}
