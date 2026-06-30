import SwiftUI
import WebExtractorKit
import WebKit

struct BrowserStack: View {
  let model: BrowserModel
  let onCapture: (WebPage) async -> Void

  var body: some View {
    NavigationStack {
      BrowserWorkspaceView(model: model, onCapture: onCapture)
    }
  }
}

struct BrowserWorkspaceView: View {
  let model: BrowserModel
  let onCapture: (WebPage) async -> Void

  var body: some View {
    WebBrowserView(
      page: model.page,
      initialURL: nil,
      onNavigate: { model.recordRecent($0) },
      accessory: { page in
        BrowserCaptureAccessory(
          page: page,
          isCapturing: model.isCapturing,
          onCapture: onCapture
        )
      },
      home: { open in
        BrowserHome(recents: model.recents, onOpen: open)
      }
    )
    .navigationTitle("Browser")
    .safeAreaInset(edge: .top, spacing: 0) {
      if let notice = model.notice {
        BrowserNoticeBanner(message: notice) {
          model.noticeDismissButtonTapped()
        }
      }
    }
    .task(id: model.notice) {
      guard model.notice != nil else { return }
      try? await Task.sleep(for: .seconds(5))
      model.noticeDismissButtonTapped()
    }
  }
}

private struct BrowserCaptureAccessory: View {
  let page: WebPage
  let isCapturing: Bool
  let onCapture: (WebPage) async -> Void

  var body: some View {
    Button {
      Task { await captureButtonTapped() }
    } label: {
      if isCapturing {
        ProgressView()
      } else {
        Label("Capture", systemImage: "plus.circle")
      }
    }
    .disabled(isCapturing || page.url == nil || page.isLoading)
  }

  private func captureButtonTapped() async {
    await onCapture(page)
  }
}

private struct BrowserHome: View {
  let recents: [URL]
  let onOpen: (URL) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        BrowserHomeSection(title: "Favorite Sites") {
          ForEach(BrowserFavoriteSite.allCases) { site in
            BrowserHomeRow(
              title: site.title,
              subtitle: site.host,
              systemImage: site.systemImage
            ) {
              onOpen(site.url)
            }
          }
        }

        if !recents.isEmpty {
          BrowserHomeSection(title: "Recent") {
            ForEach(recents, id: \.absoluteString) { url in
              BrowserHomeRow(
                title: url.displayTitle,
                subtitle: url.absoluteString,
                systemImage: "clock"
              ) {
                onOpen(url)
              }
            }
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 720, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(.background)
  }
}

private struct BrowserHomeSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      VStack(spacing: 0) {
        content()
      }
      .background(.thinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

private struct BrowserHomeRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .frame(width: 28)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.body)
            .foregroundStyle(.primary)
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)

    Divider()
      .padding(.leading, 54)
  }
}

private struct BrowserNoticeBanner: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.circle")
        .foregroundStyle(.secondary)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }
}

private enum BrowserFavoriteSite: CaseIterable, Identifiable {
  case seriousEats
  case foodAndWine
  case bonAppetit
  case nytCooking
  case cooksIllustrated
  case americasTestKitchen
  case milkStreet

  var id: Self { self }

  var title: String {
    switch self {
    case .seriousEats: "Serious Eats"
    case .foodAndWine: "Food & Wine"
    case .bonAppetit: "Bon Appetit"
    case .nytCooking: "NYT Cooking"
    case .cooksIllustrated: "Cook's Illustrated"
    case .americasTestKitchen: "America's Test Kitchen"
    case .milkStreet: "Milk Street"
    }
  }

  var url: URL {
    switch self {
    case .seriousEats:
      URL(string: "https://www.seriouseats.com")!
    case .foodAndWine:
      URL(string: "https://www.foodandwine.com")!
    case .bonAppetit:
      URL(string: "https://www.bonappetit.com")!
    case .nytCooking:
      URL(string: "https://cooking.nytimes.com")!
    case .cooksIllustrated:
      URL(string: "https://www.cooksillustrated.com")!
    case .americasTestKitchen:
      URL(string: "https://www.americastestkitchen.com")!
    case .milkStreet:
      URL(string: "https://www.177milkstreet.com")!
    }
  }

  var host: String {
    url.host() ?? url.absoluteString
  }

  var systemImage: String {
    switch self {
    case .nytCooking, .cooksIllustrated, .americasTestKitchen, .milkStreet:
      "lock.open"
    case .seriousEats, .foodAndWine, .bonAppetit:
      "globe"
    }
  }
}

private extension URL {
  var displayTitle: String {
    host() ?? absoluteString
  }
}
