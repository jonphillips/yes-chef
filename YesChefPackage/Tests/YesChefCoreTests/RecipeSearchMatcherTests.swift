import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeSearchMatcherTests {
    @Test
    func tokenizedMatcherFindsAllTokensAcrossFields() {
      expectNoDifference(
        RecipeSearchMatcher.matches(
          query: "Sous Vide pork",
          in: "Sous Vide indoor pulled pork"
        ),
        true
      )
      expectNoDifference(
        RecipeSearchMatcher.matches(
          query: "pork sous",
          in: "Sous Vide indoor pulled pork"
        ),
        true
      )
      expectNoDifference(
        RecipeSearchMatcher.matches(
          query: "sous por",
          in: "Sous Vide indoor pulled pork"
        ),
        true
      )
      expectNoDifference(
        RecipeSearchMatcher.matches(
          query: "sous grill",
          in: "Sous Vide indoor pulled pork"
        ),
        false
      )
    }

    @Test
    func tokenizedMatcherIsDiacriticInsensitiveAndMatchesEmptyQuery() {
      expectNoDifference(
        RecipeSearchMatcher.matches(query: "creme cafe", in: "Crème Brûlée", "Café Desserts"),
        true
      )
      expectNoDifference(
        RecipeSearchMatcher.matches(query: "   ", in: "Anything"),
        true
      )
    }
  }
}
