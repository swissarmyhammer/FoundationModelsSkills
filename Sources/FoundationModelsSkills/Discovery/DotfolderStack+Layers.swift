import Foundation
import FoundationModelsExtras

extension DotfolderStack {
    /// The name the layer initializer gives the throwaway derived stack.
    ///
    /// `DotfolderStack.init(name:workingDirectory:...)` requires a safe
    /// dotfolder name, and the derived layers replace the layers that name
    /// would produce, thus the value is never part of a path the stack reads.
    private static let layerListPlaceholderName = "layers"

    /// Creates a stack over an explicit, ordered list of layers, lowest
    /// precedence first.
    ///
    /// `DotfolderStack` states no initializer that takes its layers, thus
    /// this one builds a stack over a placeholder name and the root
    /// directory, then replaces the derived layers with `layers`. Neither the
    /// name nor the working directory reaches disk: construction performs no
    /// I/O, and each lookup reads the layers only.
    ///
    /// - Parameter layers: The layers of the new stack, lowest precedence
    ///   first.
    internal init(layers: [Layer]) {
        self.init(
            name: Self.layerListPlaceholderName,
            workingDirectory: URL(fileURLWithPath: "/", isDirectory: true))
        self.layers = layers
    }
}
