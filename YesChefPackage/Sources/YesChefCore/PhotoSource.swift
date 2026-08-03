import Foundation
import StructuredQueries

public enum PhotoSource: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case user
  case imported
  case extracted
}
