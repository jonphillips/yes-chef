import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MakeAheadPlanTests {
    @Test
    func parseDropsMalformedElementsButKeepsUsableSteps() {
      let plan = MakeAheadPlanClient.parse(
        """
        Here is the JSON:
        {
          "steps": [
            {
              "when": "2 days before",
              "task": "Make the sauce and refrigerate it.",
              "why": "The flavor improves after resting."
            },
            {
              "when": "Morning of"
            },
            {
              "when": "Before serving",
              "task": "Warm the sauce gently."
            }
          ]
        }
        """
      )

      expectNoDifference(
        plan,
        MakeAheadPlan(
          steps: [
            MakeAheadStep(
              when: "2 days before",
              task: "Make the sauce and refrigerate it.",
              why: "The flavor improves after resting."
            ),
            MakeAheadStep(
              when: "Before serving",
              task: "Warm the sauce gently."
            ),
          ]
        )
      )
    }

    @Test
    func renderedPlanFlattensForRecipeStorage() {
      let plan = MakeAheadPlan(
        steps: [
          MakeAheadStep(when: "Day before", task: "Toast the nuts.", why: "They stay crisp once cooled."),
          MakeAheadStep(when: "Just before dinner", task: "Dress the salad."),
        ]
      )

      expectNoDifference(
        plan.rendered(),
        """
        Day before: Toast the nuts.
        Why: They stay crisp once cooled.

        Just before dinner: Dress the salad.
        """
      )
    }

    @Test
    func recipeChatContextSerializesRecipeDetail() throws {
      let now = Date(timeIntervalSinceReferenceDate: 820_000_000)
      let recipeID = SampleUUIDSequence.uuid(600)
      let ingredientSectionID = SampleUUIDSequence.uuid(601)
      let instructionSectionID = SampleUUIDSequence.uuid(602)
      let detail = RecipeDetailData(
        recipe: Recipe(
          id: recipeID,
          title: "Tomato Tart",
          summary: "A weeknight tart.",
          servingsText: "4 servings",
          prepTimeMinutes: 20,
          cookTimeMinutes: 35,
          totalTimeMinutes: 55,
          dateCreated: now,
          dateModified: now,
          makeAhead: "Day before: Make the pastry."
        ),
        ingredientSections: [
          IngredientSection(id: ingredientSectionID, recipeID: recipeID, name: "Filling", sortOrder: 0)
        ],
        ingredientLines: [
          IngredientLine(
            id: SampleUUIDSequence.uuid(603),
            recipeID: recipeID,
            sectionID: ingredientSectionID,
            originalText: "2 tomatoes",
            sortOrder: 0
          )
        ],
        instructionSections: [
          InstructionSection(id: instructionSectionID, recipeID: recipeID, name: nil, sortOrder: 0)
        ],
        instructionSteps: [
          InstructionStep(
            id: SampleUUIDSequence.uuid(604),
            recipeID: recipeID,
            sectionID: instructionSectionID,
            text: "Bake until browned.",
            sortOrder: 0
          )
        ],
        notes: [
          RecipeNote(
            id: SampleUUIDSequence.uuid(605),
            recipeID: recipeID,
            text: "Use ripe tomatoes.",
            noteType: .general,
            dateCreated: now,
            dateModified: now
          )
        ]
      )

      let context = RecipeChatContext.recipe(RecipeChatRecipeContext(detail: detail))

      expectNoDifference(
        context.serialized(),
        """
        The user is looking at this recipe:
        - Title: Tomato Tart
        - Summary: A weeknight tart.
        - Servings: 4 servings
        - Prep time: 20 minutes
        - Cook time: 35 minutes
        - Total time: 55 minutes
        Ingredients:
        - Filling:
          - 2 tomatoes
        Instructions:
        - Bake until browned.
        Notes:
        - Use ripe tomatoes.
        Current make-ahead section:
        Day before: Make the pastry.
        """
      )
    }

    @Test
    func applyMakeAheadPlanReplacesFieldAndClearUndoRemovesIt() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 821_000_000)
      let modifiedAt = now.addingTimeInterval(60)
      let clearedAt = now.addingTimeInterval(120)
      let recipeID = SampleUUIDSequence.uuid(620)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Braised Beans",
            dateCreated: now,
            dateModified: now,
            makeAhead: "Old plan"
          )
        }
        .execute(db)

        try RecipeRepository.applyMakeAheadPlan(
          MakeAheadPlan(
            steps: [
              MakeAheadStep(when: "Day before", task: "Cook the beans.", why: "They reheat well.")
            ]
          ),
          to: recipeID,
          in: db,
          now: modifiedAt
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(
          recipe.makeAhead,
          """
          Day before: Cook the beans.
          Why: They reheat well.
          """
        )
        expectNoDifference(recipe.dateModified, modifiedAt)
      }

      try database.write { db in
        try RecipeRepository.clearMakeAhead(recipeID: recipeID, in: db, now: clearedAt)
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.makeAhead, nil)
        expectNoDifference(recipe.dateModified, clearedAt)
      }
    }

    @Test
    func editorSavePreservesExistingMakeAheadSection() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 822_000_000)
      let savedAt = now.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(640)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Soup",
            dateCreated: now,
            dateModified: now,
            makeAhead: "Morning of: Chop the vegetables."
          )
        }
        .execute(db)

        var draft = RecipeEditorDraft()
        draft.id = recipeID
        draft.title = "Better Soup"
        draft.dateCreated = now

        try RecipeRepository.save(
          draft: draft,
          in: db,
          now: savedAt,
          uuid: { SampleUUIDSequence.uuid(641) }
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.title, "Better Soup")
        expectNoDifference(recipe.makeAhead, "Morning of: Chop the vegetables.")
      }
    }
  }
}
