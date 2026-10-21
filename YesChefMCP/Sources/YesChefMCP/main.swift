import MCPServerKit
import YesChefMCPServer

@main
enum YesChefMCP {
  static func main() async {
    await YesChefMCPServer.make().run()
  }
}
