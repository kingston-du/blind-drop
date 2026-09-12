import SwiftUI

extension View {
    /// Puts the keyboard away when this view goes, and the counterpart to `defaultFocus`.
    ///
    /// **Every sheet in this app worked hard on the way up and nothing on the way down.**
    /// `NextCueSheet` carries three separate requests for its keyboard and a paragraph arguing
    /// each of them, because raising a keyboard *with* a presentation rather than a beat after it
    /// is genuinely fiddly. None of those sheets ever resigned the field, so closing one — by its
    /// button, by `dismiss()`, or by dragging it down — left the field first responder and the
    /// keyboard standing over whatever was behind (owner, 2026-09-11).
    ///
    /// **It is a backstop, not the whole fix.** `onDisappear` runs as the presentation is already
    /// leaving, which is late: it covers the drag, which has no other hook, but a sheet that
    /// dismisses itself should resign *before* it asks to be dismissed, so the keyboard travels
    /// with the sheet instead of chasing it. So the call sites do both — an explicit
    /// `focused = false` on each programmatic path, and this on the view. Setting a `FocusState`
    /// that is already `false` is a no-op, which is what lets the two coexist without either
    /// having to know whether the other ran.
    ///
    /// Takes the binding rather than being written inline at each site so that the reason lives
    /// in one place, and so a future sheet gets the behaviour by naming it rather than by
    /// remembering a paragraph.
    func resigningFocus(_ focus: FocusState<Bool>.Binding) -> some View {
        onDisappear { focus.wrappedValue = false }
    }
}
