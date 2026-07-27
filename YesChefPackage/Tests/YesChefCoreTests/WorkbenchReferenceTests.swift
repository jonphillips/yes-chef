import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchReferenceTests {
    @Test
    func fetchedURLReducesReadableContentAndStoresOnlyTheReducedReference() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 842_000_000)
      let url = try #require(URL(string: "https://example.com/technique/stock?utm_source=newsletter#method"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { fetchedURL in
          expectNoDifference(fetchedURL, url)
          return Self.referenceHTML
        },
        renderHTML: { _ in nil }
      )
      let reduced = try await WorkbenchReferenceCapture.reduce(.url(url), using: client)
      let workbenchID = SampleUUIDSequence.uuid(39_000)
      let referenceID = SampleUUIDSequence.uuid(39_001)

      try await database.write { db in
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Stock research",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        let storedReferenceID = try WorkbenchReferenceRepository.store(
          workbenchID: workbenchID,
          label: "Better stock",
          content: reduced,
          in: db,
          now: now,
          uuid: { referenceID }
        )

        expectNoDifference(storedReferenceID, referenceID)
        let reference = try #require(try WorkbenchReference.find(referenceID).fetchOne(db))
        expectNoDifference(reference.sourceURL, "https://example.com/technique/stock")
        expectNoDifference(reference.captureKind, .urlFetch)
        expectNoDifference(reference.reductionStatus, .complete)
        expectNoDifference(
          reference.reducedText,
          "Why gelatin matters\n\nSimmer chicken wings gently for a silkier stock."
        )
        expectNoDifference(try WorkbenchReferenceRepository.references(for: workbenchID, in: db), [reference])
        expectNoDifference(try Workbench.find(workbenchID).fetchOne(db)?.dateModified, now)
      }
    }

    @Test
    func workbenchDetailIncludesReferencesInCreationOrder() async throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 842_050_000)
      let workbenchID = SampleUUIDSequence.uuid(39_050)
      let firstReferenceID = SampleUUIDSequence.uuid(39_051)
      let secondReferenceID = SampleUUIDSequence.uuid(39_052)

      try await database.write { db in
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Reference order",
            sortOrder: 0,
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        try WorkbenchReference.insert {
          WorkbenchReference(
            id: secondReferenceID,
            workbenchID: workbenchID,
            label: "Second",
            captureKind: .urlFetch,
            reducedText: "Second extract.",
            reductionStatus: .complete,
            dateCreated: createdAt.addingTimeInterval(1),
            dateModified: createdAt.addingTimeInterval(1)
          )
        }
        .execute(db)
        try WorkbenchReference.insert {
          WorkbenchReference(
            id: firstReferenceID,
            workbenchID: workbenchID,
            label: "First",
            captureKind: .urlFetch,
            reducedText: "First extract.",
            reductionStatus: .complete,
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)

        let rows = try WorkbenchReferenceListRequest(workbenchID: workbenchID).fetch(db)
        expectNoDifference(rows.map(\.id), [firstReferenceID, secondReferenceID])
        expectNoDifference(rows.map(\.label), ["First", "Second"])

        let context = try #require(try WorkbenchChatContextRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(context.references.map(\.label), ["First", "Second"])
        #expect(context.compareHandoffPrompt().contains("First extract."))
        #expect(context.experimentsHandoffPrompt().contains("Second extract."))
      }
    }

    @Test
    func captureKindBuildsTheReplacementConfirmationMessage() {
      expectNoDifference(
        WorkbenchReferenceCaptureKind.browserCapture.replacementConfirmationMessage,
        "This replaces the durable captured content extract. It may be less complete than the current one."
      )
    }

    @Test
    func chatContextRequestReloadsReferenceMaterialAfterAWrite() async throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 842_075_000)
      let workbenchID = SampleUUIDSequence.uuid(39_075)
      let referenceID = SampleUUIDSequence.uuid(39_076)

      try await database.write { db in
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Live context",
            sortOrder: 0,
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        let initialContext = try #require(try WorkbenchChatContextRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(initialContext.references, [])

        _ = try WorkbenchReferenceRepository.store(
          workbenchID: workbenchID,
          label: "Fresh technique",
          content: WorkbenchReferenceReducedContent(
            sourceURL: "https://example.com/live-context",
            captureKind: .urlFetch,
            reducedText: "New reference material.",
            reductionStatus: .complete,
            isThin: true
          ),
          in: db,
          now: createdAt.addingTimeInterval(1),
          uuid: { referenceID }
        )

        let reloadedContext = try #require(try WorkbenchChatContextRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(reloadedContext.references.map(\.label), ["Fresh technique"])
        #expect(reloadedContext.serialized(for: .frontierPreferred).contains("New reference material."))
      }
    }

    @Test
    func browserCapturedHTMLUsesTheSameReducerWithoutFetching() async throws {
      let url = try #require(URL(string: "https://example.com/technique/captured"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in throw WebRecipeCaptureClientError.unimplementedFetch },
        renderHTML: { _ in nil }
      )

      let reduced = try await WorkbenchReferenceCapture.reduce(
        .capturedHTML(html: Self.referenceHTML, sourceURL: url),
        using: client
      )

      expectNoDifference(reduced.sourceURL, url.absoluteString)
      expectNoDifference(reduced.captureKind, .browserCapture)
      #expect(reduced.isThin)
      expectNoDifference(
        reduced.reducedText,
        "Why gelatin matters\n\nSimmer chicken wings gently for a silkier stock."
      )
    }

    @Test
    func pastedTextKeepsItsDistinctCaptureKind() async throws {
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in throw WebRecipeCaptureClientError.unimplementedFetch },
        renderHTML: { _ in nil }
      )

      let reduced = try await WorkbenchReferenceCapture.reduce(
        .pastedText(text: Self.referenceHTML, sourceURL: nil),
        using: client
      )

      expectNoDifference(reduced.captureKind, .pastedText)
    }

    @Test
    func refreshUpdatesTheCachedExtractWithoutReplacingTheSyncedReference() async throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 842_100_000)
      let refreshedAt = createdAt.addingTimeInterval(60)
      let url = try #require(URL(string: "https://example.com/technique/refresh"))
      let initialClient = WebRecipeCaptureClient(
        fetchHTML: { _ in "<main><p>Initial extraction.</p></main>" },
        renderHTML: { _ in nil }
      )
      let refreshedClient = WebRecipeCaptureClient(
        fetchHTML: { _ in "<main><p>Refreshed extraction.</p></main>" },
        renderHTML: { _ in nil }
      )
      let initialContent = try await WorkbenchReferenceCapture.reduce(.url(url), using: initialClient)
      let refreshedContent = try await WorkbenchReferenceCapture.reduce(.url(url), using: refreshedClient)
      let workbenchID = SampleUUIDSequence.uuid(39_100)
      let referenceID = SampleUUIDSequence.uuid(39_101)

      try await database.write { db in
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Refresh research",
            sortOrder: 0,
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        let storedReferenceID = try WorkbenchReferenceRepository.store(
          workbenchID: workbenchID,
          label: "Technique",
          content: initialContent,
          in: db,
          now: createdAt,
          uuid: { referenceID }
        )

        expectNoDifference(storedReferenceID, referenceID)

        try WorkbenchReferenceRepository.refresh(
          referenceID: referenceID,
          content: refreshedContent,
          in: db,
          now: refreshedAt
        )

        let reference = try #require(try WorkbenchReference.find(referenceID).fetchOne(db))
        expectNoDifference(reference.id, referenceID)
        expectNoDifference(reference.dateCreated, createdAt)
        expectNoDifference(reference.dateModified, refreshedAt)
        expectNoDifference(reference.reducedText, "Refreshed extraction.")
        expectNoDifference(try Workbench.find(workbenchID).fetchOne(db)?.dateModified, refreshedAt)
      }
    }

    @Test
    func reducerRejectsPagesWithoutReadableContent() async throws {
      let url = try #require(URL(string: "https://example.com/empty"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in "<html><script>window.tracker = true</script></html>" },
        renderHTML: { _ in nil }
      )

      await #expect(throws: WorkbenchReferenceCaptureError.noReadableContent) {
        try await WorkbenchReferenceCapture.reduce(
          .url(url),
          using: client
        )
      }
    }

    @Test
    func URLCaptureUsesRenderedFallbackForPublicJavaScriptPages() async throws {
      let url = try #require(URL(string: "https://example.com/technique/rendered"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in "<html><body><script>renderApp()</script></body></html>" },
        renderHTML: { renderedURL in
          expectNoDifference(renderedURL, url)
          return "<main><h2>Rendered technique</h2><p>Use a low flame.</p></main>"
        }
      )

      let reduced = try await WorkbenchReferenceCapture.reduce(.url(url), using: client)

      expectNoDifference(reduced.captureKind, .urlFetch)
      expectNoDifference(reduced.reducedText, "Rendered technique\n\nUse a low flame.")
    }

    @Test
    func URLCaptureUsesRenderedFallbackForThinRawContent() async throws {
      let url = try #require(URL(string: "https://example.com/technique/teaser"))
      let completeBody = String(repeating: "Full reference detail. ", count: 100)
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in "<main><p>Short teaser.</p></main>" },
        renderHTML: { renderedURL in
          expectNoDifference(renderedURL, url)
          return "<main><h2>Complete technique</h2><p>\(completeBody)</p></main>"
        }
      )

      let reduced = try await WorkbenchReferenceCapture.reduce(.url(url), using: client)

      #expect(!reduced.isThin)
      #expect(reduced.reducedText.hasPrefix("Complete technique\n\nFull reference detail."))
    }

    @Test
    func thinURLCaptureKeepsTheLongerRawExtractOverAShortRenderedFallback() async throws {
      let url = try #require(URL(string: "https://example.com/technique/complete-raw"))
      let rawBody = String(repeating: "Real article detail. ", count: 65)
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in "<main><p>\(rawBody)</p></main>" },
        renderHTML: { _ in "<main><p>Please enable JavaScript.</p></main>" }
      )

      let reduced = try await WorkbenchReferenceCapture.reduce(.url(url), using: client)

      expectNoDifference(reduced.reducedText, rawBody.trimmingCharacters(in: .whitespaces))
      #expect(reduced.isThin)
    }

    @Test
    func reducerAvoidsNestedBlockDuplicatesAndKeepsUncoveredProseStructured() throws {
      let nestedBlocks = try #require(
        WorkbenchReferenceReadabilityReducer.reduce(
          html: "<main><ul><li><p>Alpha step.</p></li></ul><blockquote><p>Beta quote.</p></blockquote></main>"
        )
      )
      expectNoDifference(nestedBlocks.text, "Alpha step.\n\nBeta quote.")

      let bareDiv = try #require(
        WorkbenchReferenceReadabilityReducer.reduce(
          html: "<main><h2>Heading</h2><div>All of the real body prose lives in a bare div here.</div></main>"
        )
      )
      expectNoDifference(bareDiv.text, "Heading\n\nAll of the real body prose lives in a bare div here.")

      let articleWithStrayText = try #require(
        WorkbenchReferenceReadabilityReducer.reduce(
          html: "<main><h1>Why gelatin matters</h1><div>By A Cook</div><p>First paragraph of real prose.</p><p>Second paragraph of real prose.</p><figcaption>A pot of stock.</figcaption><h2>The method</h2><p>Simmer gently.</p></main>"
        )
      )
      expectNoDifference(
        articleWithStrayText.text,
        "Why gelatin matters\n\nBy A Cook\n\nFirst paragraph of real prose.\n\nSecond paragraph of real prose.\n\nA pot of stock.\n\nThe method\n\nSimmer gently."
      )
    }

    @Test
    func reducerCapsLongExtractsWithAnExplicitTruncationNotice() throws {
      let longParagraph = String(repeating: "Technique detail. ", count: 20_000)
      let reduced = try #require(
        WorkbenchReferenceReadabilityReducer.reduce(html: "<main><h2>Long read</h2><p>\(longParagraph)</p></main>")
      )

      expectNoDifference(reduced.status, .truncated)
      #expect(!reduced.isThin)
      #expect(reduced.text.utf8.count <= WorkbenchReferenceReadabilityReducer.maximumExtractUTF8ByteCount)
      #expect(reduced.text.hasPrefix("Long read\n\n"))
      #expect(reduced.text.contains("[Reference extract truncated. Open the source for the remaining text.]"))

      let unbrokenParagraph = String(
        repeating: "x",
        count: WorkbenchReferenceReadabilityReducer.maximumExtractUTF8ByteCount + 1
      )
      let unbroken = try #require(
        WorkbenchReferenceReadabilityReducer.reduce(html: "<main><p>\(unbrokenParagraph)</p></main>")
      )
      #expect(unbroken.text.utf8.count <= WorkbenchReferenceReadabilityReducer.maximumExtractUTF8ByteCount)

      let emojiParagraph = String(
        repeating: "🍲",
        count: WorkbenchReferenceReadabilityReducer.maximumExtractUTF8ByteCount
      )
      let emoji = try #require(
        WorkbenchReferenceReadabilityReducer.reduce(html: "<main><p>\(emojiParagraph)</p></main>")
      )
      #expect(emoji.text.utf8.count <= WorkbenchReferenceReadabilityReducer.maximumExtractUTF8ByteCount)
    }

    @Test
    func storeDetectsDuplicateURLsAndRefreshPreservesAnExistingURL() async throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 842_200_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let workbenchID = SampleUUIDSequence.uuid(39_200)
      let referenceID = SampleUUIDSequence.uuid(39_201)
      let duplicateID = SampleUUIDSequence.uuid(39_202)
      let initialContent = WorkbenchReferenceReducedContent(
        sourceURL: "https://example.com/technique/dedupe",
        captureKind: .urlFetch,
        reducedText: "Original reference.",
        reductionStatus: .complete,
        isThin: true
      )
      let refreshedContent = WorkbenchReferenceReducedContent(
        sourceURL: nil,
        captureKind: .browserCapture,
        reducedText: "Authenticated refreshed reference.",
        reductionStatus: .complete,
        isThin: true
      )

      try await database.write { db in
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Dedupe research",
            sortOrder: 0,
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        _ = try WorkbenchReferenceRepository.store(
          workbenchID: workbenchID,
          label: "Original",
          content: initialContent,
          in: db,
          now: createdAt,
          uuid: { referenceID }
        )
        try WorkbenchReference.insert {
          WorkbenchReference(
            id: duplicateID,
            workbenchID: workbenchID,
            sourceURL: initialContent.sourceURL,
            label: "Duplicate",
            captureKind: .urlFetch,
            reducedText: "Duplicate reference.",
            reductionStatus: .complete,
            dateCreated: updatedAt,
            dateModified: updatedAt
          )
        }
        .execute(db)

        #expect(
          throws: WorkbenchReferenceRepositoryError.duplicateSourceURL(referenceID),
          performing: {
            _ = try WorkbenchReferenceRepository.store(
              workbenchID: workbenchID,
              label: "Updated",
              content: initialContent,
              in: db,
              now: updatedAt,
              uuid: { SampleUUIDSequence.uuid(39_203) }
            )
          }
        )
        #expect(
          throws: WorkbenchReferenceRepositoryError.duplicateSourceURL(duplicateID),
          performing: {
            try WorkbenchReferenceRepository.refresh(
              referenceID: referenceID,
              content: initialContent,
              in: db,
              now: updatedAt
            )
          }
        )
        try WorkbenchReferenceRepository.refresh(
          referenceID: referenceID,
          content: refreshedContent,
          in: db,
          now: updatedAt
        )

        let references = try WorkbenchReferenceRepository.references(for: workbenchID, in: db)
        expectNoDifference(references.map(\.id), [referenceID, duplicateID])
        expectNoDifference(references[0].label, "Original")
        expectNoDifference(references[0].sourceURL, initialContent.sourceURL)
        expectNoDifference(references[0].captureKind, .browserCapture)
        #expect(try WorkbenchReference.find(duplicateID).fetchOne(db) != nil)
        #expect(
          throws: WorkbenchReferenceRepositoryError.emptyLabel,
          performing: {
            _ = try WorkbenchReferenceRepository.store(
              workbenchID: workbenchID,
              label: "  \n",
              content: initialContent,
              in: db,
              now: updatedAt,
              uuid: { SampleUUIDSequence.uuid(39_204) }
            )
          }
        )

        let deletedAt = updatedAt.addingTimeInterval(60)
        try WorkbenchReferenceRepository.delete(referenceID: referenceID, in: db, now: deletedAt)
        #expect(try WorkbenchReference.find(referenceID).fetchOne(db) == nil)
        expectNoDifference(
          try Workbench.find(workbenchID).fetchOne(db)?.dateModified,
          deletedAt
        )
      }
    }

    @Test
    func updatingAReferenceLabelPreservesTheCapturedExtractAndStableID() async throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 842_250_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let workbenchID = SampleUUIDSequence.uuid(39_250)
      let referenceID = SampleUUIDSequence.uuid(39_251)
      let content = WorkbenchReferenceReducedContent(
        sourceURL: "https://example.com/reference",
        captureKind: .browserCapture,
        reducedText: "Authenticated captured extract.",
        reductionStatus: .complete,
        isThin: true
      )

      try await database.write { db in
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Label edit",
            sortOrder: 0,
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        _ = try WorkbenchReferenceRepository.store(
          workbenchID: workbenchID,
          label: "Original label",
          content: content,
          in: db,
          now: createdAt,
          uuid: { referenceID }
        )

        try WorkbenchReferenceRepository.updateLabel(
          referenceID: referenceID,
          label: "Updated label",
          in: db,
          now: updatedAt
        )

        let reference = try #require(try WorkbenchReference.find(referenceID).fetchOne(db))
        expectNoDifference(reference.id, referenceID)
        expectNoDifference(reference.label, "Updated label")
        expectNoDifference(reference.reducedText, content.reducedText)
        expectNoDifference(reference.captureKind, .browserCapture)
        expectNoDifference(reference.dateCreated, createdAt)
        expectNoDifference(reference.dateModified, updatedAt)
      }
    }

    private static let referenceHTML = """
    <html>
      <body>
        <header>Magazine navigation</header>
        <nav>Recipes Techniques Equipment</nav>
        <main>
          <h1>Why gelatin matters</h1>
          <p>Simmer chicken wings gently for a silkier stock.</p>
          <div class="cookie-banner">Accept cookies</div>
        </main>
        <footer>Copyright</footer>
      </body>
    </html>
    """
  }
}
