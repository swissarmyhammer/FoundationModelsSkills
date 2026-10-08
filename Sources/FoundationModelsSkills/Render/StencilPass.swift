import Foundation
import FoundationModelsExtras

/// Pass 3 of the render pipeline: Stencil, which the stenciled stack of
/// `FoundationModelsExtras` runs.
///
/// This pass holds no Stencil work of its own. For each render it makes a
/// stenciled stack over the layer roots of the host, gives it the variables
/// of that render, and calls `render(_:in:)` with the layer that won the
/// skill. The stack takes the trust from that layer -- a `.defaults` layer
/// renders trusted, and each other layer, a marketplace layer included,
/// renders untrusted -- it scopes the `{% include %}` partials to that layer
/// plus the local layers, and it gives each `.quarantined` span to Stencil
/// as a value, never as template text. Thus a `{{ x }}` inside a value that
/// pass 1 or pass 2 spliced in comes out as it stands, and the whole text is
/// still ONE template, under ONE set of the limits of an untrusted render.
///
/// The variables are the schema work of the skill format, thus they stay
/// here: the process environment, and above it the named arguments of the
/// `arguments:` frontmatter list. The stack puts both above its own
/// well-known values (`working_directory`, `date`, `hostname` and
/// `dotfolder_name`), which gives the lookup ladder of a render.
public struct StencilPass: RenderPass {
    /// Makes the stenciled stack of one render, over the layers of this pass
    /// and the variables of that render.
    ///
    /// The public initializer gives the plain factory, which reads the
    /// well-known values of the machine at the time of each render. A test
    /// gives a factory that pins those values, so that `{{ date }}` and
    /// `{{ hostname }}` do not depend on the clock or on the machine.
    typealias StackFactory = @Sendable (DotfolderStack, [String: String]) -> StenciledDotfolderStack

    /// The host-supplied layer roots that an `{% include %}` of a render
    /// resolves a partial against, ordered lowest precedence first.
    ///
    /// The SAME roots the skill itself was discovered over, thus a later root's `_partials/<name>`
    /// shadows an earlier root's
    /// copy.
    public var layers: [DotfolderStack.Layer]

    /// The environment values that a render interpolates, below the named
    /// arguments of the skill.
    ///
    /// The stenciled stack keeps the process environment out, thus the
    /// registry reads it one time and gives it here. Empty by default, so
    /// that a caller which states no environment renders no host value.
    public var environment: [String: String]

    /// Makes the stenciled stack of one render.
    private let makeStack: StackFactory

    /// Creates a `StencilPass`.
    ///
    /// - Parameters:
    ///   - layers: The host-supplied layer roots to resolve an
    ///     `{% include %}` against, lowest precedence first. Defaults to
    ///     empty (no partial resolution).
    ///   - environment: The environment values to interpolate, below the
    ///     named arguments. Defaults to empty.
    public init(layers: [DotfolderStack.Layer] = [], environment: [String: String] = [:]) {
        self.init(layers: layers, environment: environment) { base, variables in
            StenciledDotfolderStack(base: base, variables: variables)
        }
    }

    /// Creates a `StencilPass` over a factory of the caller.
    ///
    /// The seam a test uses to pin the well-known values of each render.
    ///
    /// - Parameters:
    ///   - layers: The host-supplied layer roots to resolve an
    ///     `{% include %}` against, lowest precedence first.
    ///   - environment: The environment values to interpolate, below the
    ///     named arguments.
    ///   - makeStack: Makes the stenciled stack of one render.
    init(
        layers: [DotfolderStack.Layer], environment: [String: String],
        makeStack: @escaping StackFactory
    ) {
        self.layers = layers
        self.environment = environment
        self.makeStack = makeStack
    }

    /// Renders `text` as ONE Stencil template, with the trust and the
    /// partial scope of `request.winningLayer`.
    ///
    /// - Parameters:
    ///   - text: The input text -- the output of pass 2 for a body render,
    ///     and the output of pass 1 for a metadata render, since this pass
    ///     always runs last in both pass-sets.
    ///   - request: The render request this pass runs under. `winningLayer`
    ///     gives the trust and the partial scope, and `arguments` with
    ///     `argumentNames` give the named arguments of the skill.
    /// - Returns: The rendered text as one `.quarantined` span: each byte of
    ///   it is the output of this pass, which no later pass may scan.
    /// - Throws: The render failure of the stenciled stack, when Stencil
    ///   cannot parse or render the template, when the checks of an
    ///   untrusted render refuse it, or when a `.quarantined` span sits
    ///   inside an open Stencil delimiter.
    public func render(_ text: QuarantinedText, request: RenderRequest) throws -> QuarantinedText {
        let stack = makeStack(DotfolderStack(layers: layers), variables(for: request))
        let rendered = try stack.render(text, in: request.winningLayer)
        return QuarantinedText(spans: [.quarantined(rendered)])
    }

    /// The variables of one render: the environment values, and above them
    /// the named arguments of the skill.
    ///
    /// - Parameter request: The render request that gives the arguments.
    /// - Returns: The merged variables, ready for the stenciled stack.
    private func variables(for request: RenderRequest) -> [String: String] {
        var variables = environment
        for (name, value) in Self.namedArguments(for: request) {
            variables[name] = value
        }
        return variables
    }

    /// Pairs each *distinct* name of `request.argumentNames` with its
    /// positional value, tokenized and indexed the same way the `.named`
    /// branch of `ArgumentSubstitution` resolves `$name` -- thus `$name`
    /// (pass 1) and `{{ name }}` (this pass) always agree on which supplied
    /// argument a declared name refers to, a name past the supplied argument
    /// count and a name declared more than one time included.
    ///
    /// `ArgumentSubstitution` resolves `$name` with
    /// `argumentNames.firstIndex(of: name)` -- always the *first* occurrence
    /// of that name, whatever later positions repeat it -- thus a repeated
    /// name here is paired one time only, at the position of its first
    /// occurrence, and not one time for each occurrence (which would let a
    /// later entry of the same key overwrite the first with the value of a
    /// different position). A name with no supplied value pairs with `""`,
    /// exactly as `ArgumentSubstitution` substitutes `$name` in that case --
    /// each declared name is always a variable of the render, thus none can
    /// fall through to an environment value or a well-known value of the
    /// same key (the lookup ladder would otherwise give out host
    /// state that a skill author never supplied).
    ///
    /// - Parameter request: The render request that gives `arguments` and
    ///   `argumentNames`.
    /// - Returns: `(name, value)` pairs, one for each distinct name of
    ///   `request.argumentNames`, in first-occurrence order; empty when
    ///   `argumentNames` is empty.
    private static func namedArguments(for request: RenderRequest) -> [(name: String, value: String)] {
        guard !request.argumentNames.isEmpty else { return [] }
        let positionalArguments = ArgumentSubstitution.shellStyleTokens(
            request.arguments.joined(separator: " "))
        var seenNames: Set<String> = []
        return request.argumentNames.enumerated().compactMap { index, name in
            guard seenNames.insert(name).inserted else { return nil }
            return (name: name, value: positionalArguments[safe: index] ?? "")
        }
    }
}
