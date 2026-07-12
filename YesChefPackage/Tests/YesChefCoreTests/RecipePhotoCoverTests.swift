import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct RecipePhotoCoverTests {
  @Test
  func overrideWins() {
    let recipeID = SampleUUIDSequence.uuid(20)
    let automaticPhoto = Self.photo(
      id: SampleUUIDSequence.uuid(21),
      recipeID: recipeID,
      kind: .hero,
      sortOrder: 0
    )
    let manualPhoto = Self.photo(
      id: SampleUUIDSequence.uuid(22),
      recipeID: recipeID,
      kind: .gallery,
      sortOrder: 1,
      pixelWidth: 300,
      pixelHeight: 300
    )

    let cover = RecipePhotoCover.coverPhoto(
      coverPhotoID: manualPhoto.id,
      from: [automaticPhoto, manualPhoto]
    )

    expectNoDifference(cover?.id, manualPhoto.id)
  }

  @Test
  func nilFallsBackToDisplaySortKey() {
    let recipeID = SampleUUIDSequence.uuid(30)
    let lowResolutionHero = Self.photo(
      id: SampleUUIDSequence.uuid(31),
      recipeID: recipeID,
      kind: .hero,
      sortOrder: 0,
      pixelWidth: 300,
      pixelHeight: 300
    )
    let highResolutionGallery = Self.photo(
      id: SampleUUIDSequence.uuid(32),
      recipeID: recipeID,
      kind: .gallery,
      sortOrder: 1
    )

    let cover = RecipePhotoCover.coverPhoto(
      coverPhotoID: nil,
      from: [lowResolutionHero, highResolutionGallery]
    )

    expectNoDifference(cover?.id, highResolutionGallery.id)
  }

  @Test
  func danglingOverrideFallsBackToDisplaySortKey() {
    let recipeID = SampleUUIDSequence.uuid(40)
    let firstPhoto = Self.photo(
      id: SampleUUIDSequence.uuid(41),
      recipeID: recipeID,
      kind: .gallery,
      sortOrder: 1
    )
    let automaticPhoto = Self.photo(
      id: SampleUUIDSequence.uuid(42),
      recipeID: recipeID,
      kind: .hero,
      sortOrder: 2
    )

    let cover = RecipePhotoCover.coverPhoto(
      coverPhotoID: SampleUUIDSequence.uuid(999),
      from: [firstPhoto, automaticPhoto]
    )

    expectNoDifference(cover?.id, automaticPhoto.id)
  }

  @Test
  func setCoverPhotoBumpsRecipeModifiedDate() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(50)
    let coverPhotoID = SampleUUIDSequence.uuid(51)
    let createdAt = Date(timeIntervalSinceReferenceDate: 802_050_000)
    let setAt = createdAt.addingTimeInterval(60)
    let clearedAt = createdAt.addingTimeInterval(120)

    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Photo Test", dateCreated: createdAt, dateModified: createdAt)
      }
      .execute(db)
      try RecipePhoto.insert {
        RecipePhoto(
          id: coverPhotoID,
          recipeID: recipeID,
          imageDataReference: "recipePhotos/\(coverPhotoID.uuidString)",
          displayData: Data([0]),
          kind: .gallery,
          sortOrder: 0,
          dateCreated: createdAt
        )
      }
      .execute(db)

      try RecipeRepository.setCoverPhotoID(coverPhotoID, recipeID: recipeID, in: db, now: setAt)
      let setRecipe = try #require(try Recipe.find(recipeID).fetchOne(db))
      expectNoDifference(setRecipe.coverPhotoID, coverPhotoID)
      expectNoDifference(setRecipe.dateModified, setAt)

      try RecipeRepository.setCoverPhotoID(nil, recipeID: recipeID, in: db, now: clearedAt)
      let clearedRecipe = try #require(try Recipe.find(recipeID).fetchOne(db))
      expectNoDifference(clearedRecipe.coverPhotoID, nil)
      expectNoDifference(clearedRecipe.dateModified, clearedAt)
    }
  }

  @Test
  func saveRemovingUserHeroPhotoClearsCoverAndDeletesPhoto() throws {
    @Dependency(\.defaultDatabase) var database
    let createdAt = Date(timeIntervalSinceReferenceDate: 802_370_000)
    let modifiedAt = Date(timeIntervalSinceReferenceDate: 802_370_100)
    let photoID = SampleUUIDSequence.uuid(670)
    let processedPhoto = RecipePhotoProcessor.process(
      sourceData: Data([0x01, 0x02, 0x03, 0x04]),
      sourcePath: "Original.jpg",
      kind: .hero
    )
    var uuids = SampleUUIDSequence(start: 671)

    try database.write { db in
      let recipeID = try RecipeRepository.save(
        draft: RecipeEditorDraft(
          title: "Remove Photo Soup",
          ingredientText: "1 onion",
          instructionText: "Cook.",
          pendingPhotos: [
            RecipeEditorPhotoDraft(
              id: photoID,
              processedPhoto: processedPhoto,
              originalSourcePath: "Original.jpg",
              kind: .hero,
              source: .user
            )
          ]
        ),
        in: db,
        now: createdAt,
        uuid: { uuids.next() }
      )
      try RecipeRepository.setCoverPhotoID(photoID, recipeID: recipeID, in: db, now: createdAt)

      var editDraft = RecipeEditorDraft(
        detail: try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
      )
      editDraft.removesHeroPhoto = true
      _ = try RecipeRepository.save(draft: editDraft, in: db, now: modifiedAt, uuid: { uuids.next() })

      let updatedRecipe = try #require(try Recipe.find(recipeID).fetchOne(db))
      expectNoDifference(updatedRecipe.coverPhotoID, nil)
      expectNoDifference(try RecipePhoto.where { $0.recipeID.eq(recipeID) }.fetchAll(db), [])
    }
  }

  private static func photo(
    id: RecipePhoto.ID,
    recipeID: Recipe.ID,
    kind: RecipePhotoKind,
    sortOrder: Int,
    pixelWidth: Int = 1600,
    pixelHeight: Int = 1200
  ) -> RecipePhoto {
    RecipePhoto(
      id: id,
      recipeID: recipeID,
      imageDataReference: id.uuidString,
      displayData: Data([0]),
      thumbnailData: Data([0]),
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      kind: kind,
      sortOrder: sortOrder,
      dateCreated: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
  }
}
