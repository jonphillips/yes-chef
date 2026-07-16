import SwiftUI
import UIKit
import YesChefCore

struct RecipeReaderThumbnail: View {
  let photo: RecipeDetailPhoto
  let sideLength: CGFloat
  let action: () -> Void

  init(photo: RecipeDetailPhoto, sideLength: CGFloat, action: @escaping () -> Void) {
    self.photo = photo
    self.sideLength = sideLength
    self.action = action
  }

  var body: some View {
    if photo.isDisplayable {
      Button(action: action) {
        RecipePhotoFrame(photo: photo, aspectRatio: 1, variant: .thumbnail)
          .frame(width: sideLength, height: sideLength)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(photo.caption ?? "Recipe photo"))
      .accessibilityHint(Text("Opens photo gallery."))
    }
  }
}

struct RecipePhotoGallery: View {
  let photos: [RecipeDetailPhoto]
  let coverPhotoID: RecipePhoto.ID?
  let setCoverPhoto: (RecipePhoto.ID?) -> Void

  @State private var selectedPhotoID: RecipePhoto.ID?
  @State private var enlargedPhoto: RecipeDetailPhoto?

  private var selectedPhoto: RecipeDetailPhoto? {
    if let selectedPhotoID, let photo = photos.first(where: { $0.id == selectedPhotoID }) {
      return photo
    }
    return RecipePhotoCover.coverPhoto(coverPhotoID: coverPhotoID, from: photos)
  }

  var body: some View {
    if let selectedPhoto {
      VStack(alignment: .leading, spacing: 10) {
        Button {
          enlargedPhoto = selectedPhoto
        } label: {
          RecipePhotoFrame(
            photo: selectedPhoto,
            aspectRatio: selectedPhoto.displayAspectRatio,
            variant: .hero
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(selectedPhoto.caption ?? "Recipe photo"))
        .accessibilityHint(Text("Opens enlarged photo."))

        if let caption = selectedPhoto.caption {
          Text(caption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }

        RecipePhotoCoverControls(
          selectedPhotoID: selectedPhoto.id,
          coverPhotoID: coverPhotoID,
          setCoverPhoto: setCoverPhoto
        )

        if photos.count > 1 {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(photos) { photo in
                if photo.isDisplayable {
                  Button {
                    selectedPhotoID = photo.id
                  } label: {
                    RecipePhotoFrame(photo: photo, aspectRatio: 1, variant: .thumbnail)
                      .frame(width: 76, height: 76)
                      .overlay {
                        RoundedRectangle(cornerRadius: 8)
                          .stroke(
                            photo.id == selectedPhoto.id ? Color.accentColor : Color.clear,
                            lineWidth: 3
                          )
                      }
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel(Text(photo.caption ?? "Recipe photo"))
                }
              }
            }
            .padding(.vertical, 2)
          }
          .scrollIndicators(.hidden)
        }
      }
      .fullScreenCover(item: $enlargedPhoto) { photo in
        RecipePhotoFullScreenView(photo: photo)
      }
    }
  }
}

private struct RecipePhotoCoverControls: View {
  let selectedPhotoID: RecipePhoto.ID
  let coverPhotoID: RecipePhoto.ID?
  let setCoverPhoto: (RecipePhoto.ID?) -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        buttons
      }
      VStack(alignment: .leading, spacing: 8) {
        buttons
      }
    }
    .font(.callout)
  }

  @ViewBuilder
  private var buttons: some View {
    if coverPhotoID == selectedPhotoID {
      Label("Cover", systemImage: "checkmark.seal.fill")
        .foregroundStyle(.secondary)
    } else {
      Button {
        setCoverPhoto(selectedPhotoID)
      } label: {
        Label("Set as Cover", systemImage: "photo.badge.checkmark")
      }
      .buttonStyle(.bordered)
    }

    if coverPhotoID != nil {
      Button {
        setCoverPhoto(nil)
      } label: {
        Label("Use Automatic", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)
    }
  }
}

private struct RecipePhotoFullScreenView: View {
  @Environment(\.dismiss) private var dismiss
  let photo: RecipeDetailPhoto

  @State private var scale: CGFloat = 1
  @State private var baseScale: CGFloat = 1
  @State private var offset = CGSize.zero
  @State private var baseOffset = CGSize.zero

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black
          .ignoresSafeArea()

        if photo.isDisplayable {
          let imageSize = fittedImageSize(in: proxy.size)
          RecipePhotoImage(
            photoID: photo.id,
            checksum: photo.checksum,
            variant: .fullScreen,
            thumbnailData: photo.thumbnailData
          )
            .frame(width: imageSize.width, height: imageSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(in: proxy.size, imageSize: imageSize))
            .simultaneousGesture(magnifyGesture(in: proxy.size, imageSize: imageSize))
            .onTapGesture(count: 2) {
              doubleTap(in: proxy.size, imageSize: imageSize)
            }
            .accessibilityLabel(Text(photo.caption ?? "Recipe photo"))
        }
      }
    }
    .overlay(alignment: .topTrailing) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.largeTitle)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)
      .padding()
      .accessibilityLabel(Text("Close"))
    }
  }

  private func fittedImageSize(in containerSize: CGSize) -> CGSize {
    let available = CGSize(
      width: max(containerSize.width - 32, 1),
      height: max(containerSize.height - 32, 1)
    )
    let imageAspectRatio = photo.displayAspectRatio
    let availableAspectRatio = available.width / available.height
    if imageAspectRatio > availableAspectRatio {
      return CGSize(width: available.width, height: available.width / imageAspectRatio)
    } else {
      return CGSize(width: available.height * imageAspectRatio, height: available.height)
    }
  }

  private func dragGesture(in containerSize: CGSize, imageSize: CGSize) -> some Gesture {
    DragGesture()
      .onChanged { value in
        guard scale > 1 else {
          offset = .zero
          return
        }
        offset = clampedOffset(
          CGSize(
            width: baseOffset.width + value.translation.width,
            height: baseOffset.height + value.translation.height
          ),
          scale: scale,
          containerSize: containerSize,
          imageSize: imageSize
        )
      }
      .onEnded { _ in
        baseOffset = offset
      }
  }

  private func magnifyGesture(in containerSize: CGSize, imageSize: CGSize) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        scale = clampedScale(baseScale * value.magnification)
        offset = clampedOffset(
          offset,
          scale: scale,
          containerSize: containerSize,
          imageSize: imageSize
        )
      }
      .onEnded { _ in
        baseScale = scale
        baseOffset = offset
      }
  }

  private func doubleTap(in containerSize: CGSize, imageSize: CGSize) {
    withAnimation(.snappy) {
      if scale > 1 {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
      } else {
        scale = 2
        baseScale = 2
        offset = clampedOffset(
          offset,
          scale: scale,
          containerSize: containerSize,
          imageSize: imageSize
        )
        baseOffset = offset
      }
    }
  }

  private func clampedScale(_ proposedScale: CGFloat) -> CGFloat {
    min(max(proposedScale, 1), 4)
  }

  private func clampedOffset(
    _ proposedOffset: CGSize,
    scale: CGFloat,
    containerSize: CGSize,
    imageSize: CGSize
  ) -> CGSize {
    guard scale > 1 else { return .zero }
    let maximumX = max((imageSize.width * scale - containerSize.width) / 2, 0)
    let maximumY = max((imageSize.height * scale - containerSize.height) / 2, 0)
    return CGSize(
      width: min(max(proposedOffset.width, -maximumX), maximumX),
      height: min(max(proposedOffset.height, -maximumY), maximumY)
    )
  }
}

private extension RecipeDetailPhoto {
  var displayAspectRatio: CGFloat {
    guard kind == .referenceDocument else { return 16.0 / 10.0 }
    guard
      let pixelWidth,
      let pixelHeight,
      pixelWidth > 0,
      pixelHeight > 0
    else {
      return 3.0 / 4.0
    }
    return Swift.min(Swift.max(CGFloat(pixelWidth) / CGFloat(pixelHeight), 0.65), 1.4)
  }
}

private struct RecipePhotoFrame: View {
  let photo: RecipeDetailPhoto
  let aspectRatio: CGFloat
  var variant: RecipePhotoImageVariant = .thumbnail

  var body: some View {
    Color.clear
      .aspectRatio(aspectRatio, contentMode: .fit)
      .overlay {
        RecipePhotoImage(
          photoID: photo.id,
          checksum: photo.checksum,
          variant: variant,
          thumbnailData: photo.thumbnailData
        )
        .padding(1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }
}
