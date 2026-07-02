import SwiftUI

func gatedBinding(_ binding: Binding<Bool>, enabled: Bool) -> Binding<Bool> {
  Binding {
    enabled && binding.wrappedValue
  } set: { newValue in
    binding.wrappedValue = newValue
  }
}

func gatedBinding<Value>(_ binding: Binding<Value?>, enabled: Bool) -> Binding<Value?> {
  Binding {
    enabled ? binding.wrappedValue : nil
  } set: { newValue in
    binding.wrappedValue = newValue
  }
}
