import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeLabelHarvestTests {
    @Test
    func microdataHarvestsPublisherCategoriesCuisineAndKeywords() {
      let page = WebRecipePageParser.parse(html: """
        <article itemscope itemtype="https://schema.org/Recipe">
          <h1 itemprop="name">Brothy Beans</h1>
          <span itemprop="recipeCategory">Beans, Dinner</span>
          <span itemprop="recipeCuisine">Italian</span>
          <meta itemprop="keywords" content="one pot, beans">
          <li itemprop="recipeIngredient">1 pound dried beans</li>
          <li itemprop="recipeInstructions">Simmer until tender.</li>
        </article>
        """)

      expectNoDifference(page.categoryNames, ["Beans", "Dinner", "Cuisine > Italian"])
      expectNoDifference(page.tagNames, ["one pot", "beans"])
    }
  }
}
