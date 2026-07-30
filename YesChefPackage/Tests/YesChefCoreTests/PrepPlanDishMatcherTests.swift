import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct PrepPlanDishMatcherTests {
    @Test
    func suggestsOnlyOneUnambiguousDish() {
      let bavetteID = SampleUUIDSequence.uuid(15_010)
      let saladID = SampleUUIDSequence.uuid(15_011)
      let commaTitleID = SampleUUIDSequence.uuid(15_012)
      let candidates = [
        PrepPlanDishMatchCandidate(id: bavetteID, title: "Korean Bavette"),
        PrepPlanDishMatchCandidate(
          id: saladID,
          title: "Napa Cabbage, Cucumber & Scallion Salad (Korean)"
        ),
        PrepPlanDishMatchCandidate(id: commaTitleID, title: "Beans, Rice & Greens"),
      ]

      #expect(
        PrepPlanDishMatcher.suggestedSourceDish(
          serves: "  korean   bavette ",
          among: candidates
        ) == bavetteID
      )
      #expect(
        PrepPlanDishMatcher.suggestedSourceDish(
          serves: "Napa Cabbage, Cucumber & Scallion Salad",
          among: candidates
        ) == saladID
      )
      #expect(
        PrepPlanDishMatcher.suggestedSourceDish(
          serves: "Saturday's Korean Bavette",
          among: candidates
        ) == bavetteID
      )
      #expect(
        PrepPlanDishMatcher.suggestedSourceDish(
          serves: "Beans, Rice & Greens",
          among: candidates
        ) == commaTitleID
      )
      #expect(
        PrepPlanDishMatcher.suggestedSourceDish(
          serves: "Korean Bavette, Napa Cabbage, Cucumber & Scallion Salad",
          among: candidates
        ) == nil
      )
      #expect(
        PrepPlanDishMatcher.suggestedSourceDish(
          serves: "Soup (summer)",
          among: [
            PrepPlanDishMatchCandidate(id: SampleUUIDSequence.uuid(15_013), title: "Soup"),
            PrepPlanDishMatchCandidate(id: SampleUUIDSequence.uuid(15_014), title: "Soup (winter)"),
          ]
        ) == nil
      )
      #expect(PrepPlanDishMatcher.suggestedSourceDish(serves: "  ", among: candidates) == nil)
    }

    @Test
    func updatingPrepStepCanClearSourceDish() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_700_000)
      let menuID = SampleUUIDSequence.uuid(15_020)
      let stepID = SampleUUIDSequence.uuid(15_021)

      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Source Dish", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try PrepPlanStepRepository.create(
          PrepPlanStep(
            session: "Friday",
            task: "Salt the chicken",
            sourceDish: SampleUUIDSequence.uuid(15_022)
          ),
          for: menuID,
          in: db,
          now: now,
          uuid: { stepID }
        )
        try PrepPlanStepRepository.update(
          id: stepID,
          session: "Friday",
          task: "Salt the chicken",
          serves: "Friday's chicken",
          sourceDish: nil,
          in: db,
          now: now
        )
      }

      try database.read { db in
        let step = try #require(try PrepPlanStepRecord.find(stepID).fetchOne(db))
        #expect(step.sourceDish == nil)
      }
    }
  }
}
