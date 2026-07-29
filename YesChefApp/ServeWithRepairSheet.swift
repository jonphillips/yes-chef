import Foundation
import SwiftUI
import UIKit
import YesChefCore

struct ServeWithRepairPresentation: Identifiable, Equatable {
  let recipeID: Recipe.ID
  let recipeTitle: String
  private let rawData: Data

  var id: Recipe.ID { recipeID }

  var initialText: String {
    String(data: rawData, encoding: .utf8) ?? rawData.base64EncodedString()
  }

  var showsBase64Fallback: Bool {
    String(data: rawData, encoding: .utf8) == nil
  }

  init?(error: ServeWithCodingError, recipe: Recipe) {
    guard error.recipeID == recipe.id, let rawData = recipe.serveWith else { return nil }
    self.recipeID = recipe.id
    self.recipeTitle = recipe.title
    self.rawData = rawData
  }
}

struct ServeWithRepairSheet: View {
  let presentation: ServeWithRepairPresentation
  let save: (String) throws -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draftText: String
  @State private var errorMessage: String?

  init(
    presentation: ServeWithRepairPresentation,
    save: @escaping (String) throws -> Void
  ) {
    self.presentation = presentation
    self.save = save
    _draftText = State(initialValue: presentation.initialText)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Text("Serve With for \(presentation.recipeTitle) could not be read. Edit the raw stored data below; it will be saved only if it decodes as a complete Serve With list.")
          .foregroundStyle(.secondary)

        if presentation.showsBase64Fallback {
          Text("The stored bytes are not UTF-8, so they are shown as Base64. Replace them with complete Serve With JSON before saving.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Raw Serve With Data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              UIPasteboard.general.string = presentation.initialText
            } label: {
              Label("Copy", systemImage: "doc.on.doc")
            }
            .font(.caption)
          }
          TextEditor(text: $draftText)
            .fontDesign(.monospaced)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }
      .padding()
      .navigationTitle("Repair Serve With")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { saveButtonTapped() }
        }
      }
    }
    .presentationDetents([.large])
  }

  private func saveButtonTapped() {
    do {
      try save(draftText)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
