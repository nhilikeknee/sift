import SwiftUI

/// Sits where the toast sits, while a batch runs. Says what is happening, how
/// far it has got, and that Esc stops it — the three things a progress bar is
/// for (D-41).
struct ProgressBanner: View {
    let progress: ProgressState
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s16) {
                Text(headline)
                    .textStyle(.label)
                // Work with nothing to count is work with nothing to stop
                // partway: an undo of a batch is one call, and offering to
                // interrupt it would be offering half a reversal.
                //
                // The spacer goes with the button. It is what holds Stop at the
                // far end of the rail, and left behind on its own it does the
                // one thing a spacer does — take every point it is offered —
                // so the banner went wider without the fixed width than with
                // it (D-285).
                if !progress.isIndeterminate {
                    Spacer(minLength: Tokens.Space.s16)
                    Button("Stop", action: stop)
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .textStyle(.strong)
                        .help("Stop (Esc)")
                }
            }
            if !progress.isIndeterminate {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Tokens.Surface.sunken)
                        Rectangle()
                            .fill(Tokens.Text.primary)
                            .frame(width: geo.size.width * min(max(progress.fraction, 0), 1))
                    }
                }
                .frame(height: Tokens.Border.ringWidth)
            }
        }
        // Wide enough to draw a rail on, and only when there is one. Work with
        // nothing to count draws no bar and no Stop, so the fixed width was
        // padding out one short sentence to 520 points: centered that read as a
        // banner and left-aligned it reads as a slab across the photograph.
        // With no bar it sizes to its content, which is what the toast beside
        // it in the same corner does (D-285).
        .frame(width: progress.isIndeterminate ? nil : Tokens.Layout.jumpSheet)
        .padding(.horizontal, Tokens.Space.s16)
        .padding(.vertical, Tokens.Space.s12)
        .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .shadow(color: Tokens.Elevation.overlay.color,
                radius: Tokens.Elevation.overlay.radius,
                y: Tokens.Elevation.overlay.y)
        .padding(.bottom, Tokens.Space.s32)
        .accessibilityElement(children: .combine)
        // The count is the value, not the label. A label is what the thing is
        // and a value is where it has got to, and a change to the second is
        // the one a screen reader passes on: counting to sixty inside the
        // label was counting where nothing was listening (D-343).
        .accessibilityLabel(progress.label)
        .accessibilityValue(reached)
    }

    /// A bar with no total draws no bar: a full one would read as finished and
    /// an empty one as stuck, and neither is what is happening.
    private var headline: String {
        progress.isIndeterminate ? "\(progress.label)…" : "\(progress.label) \(progress.done) of \(progress.total)"
    }

    /// What the bar says out loud. Work with nothing to count is under way and
    /// can say no more than that.
    private var reached: String {
        progress.isIndeterminate ? "under way" : "\(progress.done) of \(progress.total)"
    }
}
