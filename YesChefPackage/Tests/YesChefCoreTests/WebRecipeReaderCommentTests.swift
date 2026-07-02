import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeReaderCommentTests {
    @Test
    func nytCookingCommentsExtractTextAndHelpfulCountsWithoutOwners() throws {
      let comments = RecipeReaderCommentExtractor.extract(
        html: try fixtureHTML("nyt-comments"),
        sourceURL: URL(string: "https://cooking.nytimes.com/recipes/1021776-lemony-white-bean-soup-with-turkey-and-greens")
      )

      expectNoDifference(comments.count, 76)
      expectNoDifference(
        Array(comments.prefix(5)),
        [
          RawComment(
            text: #"You never need to be without that pesky "1 Tbsp. of tomato paste." Open a can at both ends and remove the lid from one end. Using the other lid, push out approximately a tablespoonful of paste, slice it off and lay it on a sheet of waxed paper on a small cutting board or flat tray; repeat until you've used it all. Place the rounds of paste in the freezer and, when frozen solid, store in a zipper bag with the air sucked out. Voila, small portions of tomato paste on demand."#,
            helpfulCount: 6300
          ),
          RawComment(
            text: "I don’t throw away the tasty stalks of the greens, whether those be kale, collard or what ever I might have on hand. Instead, after stripping the leaves, I dice the stalks into 1/4” bits and sauté them with the onion. The extra cooking time renders them soft and they add to the overall flavor of the dish.",
            helpfulCount: 2735
          ),
          RawComment(
            text: #"I'm always confused by "bunch of greens." One store near me sells a bundle of kale that will feed 2 or 3 people when cooked, while another store sells bunches large enough to feed 5 or 6. It would be clearer if recipes used a different measuring system, like how many leaves or cups of chopped greens."#,
            helpfulCount: 2621
          ),
          RawComment(
            text: "It's just navy bean soup. It reminded me of Saturday night growing up (in the 60's). Mom would make something like this in the afternoon before the sitter came. At 7:30 she would descend the staircase ready for a night out drenched in Chanel #5 and a fur stole. Dad would be in his suit and trying to steal a bite off us kids, which we heartily rebuffed. Off they would go to go dancing. We were left with bean soup and the sitter. Oh, and fake wrestling on the TV at 10:00pm!",
            helpfulCount: 2165
          ),
          RawComment(
            text: "Suggestion. Just as beer can add depth to a chili, so a half-cup or so of white wine, added at the same time as the stock, will add brightness and interest here.",
            helpfulCount: 1907
          ),
        ]
      )
      expectNoDifference(comments.contains { $0.text == "Ada" || $0.text == "Ben" }, false)
    }

    @Test
    func unsupportedHostsReturnNoComments() throws {
      let comments = RecipeReaderCommentExtractor.extract(
        html: try fixtureHTML("nyt-comments"),
        sourceURL: URL(string: "https://www.nytimes.com/recipes/1021776-lemony-white-bean-soup-with-turkey-and-greens")
      )

      expectNoDifference(comments, [])
    }

    private func fixtureHTML(_ name: String) throws -> String {
      try String(contentsOf: fixtureURL.appendingPathComponent("\(name).html"), encoding: .utf8)
    }

    private var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/WebRecipeCapture/SanitizedSites", isDirectory: true)
    }
  }
}
