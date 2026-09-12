// Purpose: Coordinate main tabs, first-run onboarding, and shared error presentation.
// Inputs: AppStore and the persisted hasSeenWelcome preference.
// Outputs: Summary, Records, Visits, and Medical profile navigation stacks.
// Side effects: Updates the welcome preference and tab state; explicit recovery restores the fictional demo.

import SwiftUI

// MARK: - RootView
/// Coordinate main tabs, first-run onboarding, and shared error presentation.
struct RootView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var welcome = false
    @State private var confirmRestore = false
    @State private var selectedTab: RevaTab = .summary
    @State private var recordsGeneration = 0
    // MARK: - Rendering and navigation
    var body: some View {
        Group {
            if let error = store.startupError {
                ContentUnavailableView {
                    Label("Your data needs attention", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Restore fictional demo") { confirmRestore = true }.buttonStyle(
                        .borderedProminent)
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        SummaryView(
                            showAllRecords: {
                                recordsGeneration += 1
                                selectedTab = .records
                            }, showMedicalProfile: { selectedTab = .medicalProfile })
                    }.tabItem { Label("Summary", systemImage: "heart.text.square") }.tag(RevaTab.summary)
                    NavigationStack { RecordsView() }.id(recordsGeneration).tabItem {
                        Label("Records", systemImage: "folder")
                    }.tag(RevaTab.records)
                    NavigationStack { VisitsView() }.tabItem { Label("Visits", systemImage: "calendar") }.tag(
                        RevaTab.visits)
                    NavigationStack { MedicalProfileView() }.tabItem {
                        Label("Medical profile", systemImage: "person.text.rectangle")
                    }.tag(RevaTab.medicalProfile)
                }
                .background {
                    if #available(iOS 26.0, *) {
                        NativeTabLensBehavior(selection: $selectedTab)
                    }
                }
            }
        }
        .alert(
            "Something needs attention",
            isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .confirmationDialog(
            "Restore the fictional demo and replace your local changes?", isPresented: $confirmRestore,
            titleVisibility: .visible
        ) {
            Button("Restore demo", role: .destructive) { store.perform { try store.resetDemo() } }
        }
        .sheet(isPresented: $welcome) {
            WelcomeView {
                hasSeenWelcome = true
                welcome = false
            }
        }
        .onAppear { if !hasSeenWelcome { welcome = true } }
    }
}

// MARK: - RevaTab
/// Keep tab-selection identities scoped to root navigation.
private enum RevaTab: Int, CaseIterable { case summary, records, visits, medicalProfile }

// MARK: - Native tab lens interaction

/// Own tab input while keeping UIKit's native glass, icons, labels, and accessibility.
@available(iOS 26.0, *)
private struct NativeTabLensBehavior: UIViewRepresentable {
    @Binding var selection: RevaTab

    func makeUIView(context: Context) -> NativeTabLensController { NativeTabLensController() }

    func updateUIView(_ view: NativeTabLensController, context: Context) {
        view.onSelect = { index in
            guard let tab = RevaTab(rawValue: index), tab != selection else { return }
            selection = tab
        }
    }

    static func dismantleUIView(_ view: NativeTabLensController, coordinator: ()) { view.detach() }
}

@available(iOS 26.0, *)
private final class NativeTabLensController: UIView, UIGestureRecognizerDelegate {
    var onSelect: ((Int) -> Void)?

    private weak var tabBar: UITabBar?
    private weak var lens: UIView?
    private weak var content: UIView?
    private weak var selectionGesture: UIGestureRecognizer?
    private var nativeSelectionWasEnabled = true
    private var dragGesture: UILongPressGestureRecognizer?
    private var hoverGesture: UIHoverGestureRecognizer?
    private var pointerInteractions: [(UIPointerInteraction, Bool)] = []
    private var updateLink: UIUpdateLink?
    private var itemFrames: [CGRect] = []
    private var anchor: Int?
    private var pointerX: CGFloat = 0
    private var isDragging = false
    private var isHovering = false
    private var restingAnchor = 0
    private var settleUntil: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard window != nil else { return }
        let link = UIUpdateLink(view: self)
        link.addAction(to: .beforeCATransactionCommit) { [weak self] _, _ in
            guard let self else { return }
            if !self.hasValidAttachment {
                self.clearAttachment()
                self.attachIfAvailable()
            }
            self.updateHeldLens()
        }
        link.isEnabled = true
        updateLink = link
    }

    func detach() {
        updateLink?.isEnabled = false
        clearAttachment()
        updateLink = nil
    }

    private var hasValidAttachment: Bool {
        guard let tabBar, tabBar.window === window, let lens, let content,
            let platter = lens.superview, content.superview === platter,
            platter.superview === tabBar, selectionGesture?.view === tabBar,
            dragGesture?.view === tabBar
        else { return false }
        return true
    }

    private func clearAttachment() {
        isDragging = false
        isHovering = false
        selectionGesture?.isEnabled = nativeSelectionWasEnabled
        if let dragGesture {
            dragGesture.removeTarget(self, action: #selector(trackSelection(_:)))
            dragGesture.view?.removeGestureRecognizer(dragGesture)
        }
        if let hoverGesture {
            hoverGesture.removeTarget(self, action: #selector(trackHover(_:)))
            hoverGesture.view?.removeGestureRecognizer(hoverGesture)
        }
        for (interaction, enabled) in pointerInteractions { interaction.isEnabled = enabled }
        pointerInteractions = []
        dragGesture = nil
        hoverGesture = nil
        updateLink?.requiresContinuousUpdates = false
        tabBar?.setNeedsLayout()
        anchor = nil
        selectionGesture = nil
        tabBar = nil
        lens = nil
        content = nil
        itemFrames = []
    }

    private func attachIfAvailable() {
        guard let window, let bar = Self.findTabBar(in: window),
            bar.items?.count == RevaTab.allCases.count
        else { return }

        // UIKit has no public held-lens sizing API. Require the observed native layout,
        // using public view geometry only, and leave the system behavior intact if it changes.
        for platter in bar.subviews {
            let groups = platter.subviews.filter {
                $0.subviews.count == RevaTab.allCases.count && $0.subviews.allSatisfy { $0 is UIControl }
            }
            guard groups.count == 2, let group = groups.first else { continue }
            let frames = Self.frames(in: group, relativeTo: platter)
            guard frames.count == RevaTab.allCases.count else { continue }
            let candidates = platter.subviews.filter { candidate in
                !groups.contains(where: { $0 === candidate }) && !candidate.subviews.isEmpty
                    && frames.contains {
                        abs($0.minX - candidate.frame.minX) < 0.5
                            && abs($0.minY - candidate.frame.minY) < 0.5
                            && abs($0.width - candidate.frame.width) < 0.5
                            && abs($0.height - candidate.frame.height) < 0.5
                    }
            }
            let gestures = (bar.gestureRecognizers ?? []).filter {
                !($0 is UILongPressGestureRecognizer) && !($0 is UIHoverGestureRecognizer)
                    && !($0 is UITapGestureRecognizer)
            }
            guard candidates.count == 1, gestures.count == 1 else { continue }
            tabBar = bar
            lens = candidates[0]
            content = group
            itemFrames = frames
            selectionGesture = gestures[0]
            nativeSelectionWasEnabled = gestures[0].isEnabled
            // The native recognizer follows the pointer freely. Only our gesture may move the lens.
            gestures[0].isEnabled = false
            let drag = UILongPressGestureRecognizer(target: self, action: #selector(trackSelection(_:)))
            drag.minimumPressDuration = 0
            drag.allowableMovement = .greatestFiniteMagnitude
            drag.cancelsTouchesInView = true
            drag.delaysTouchesBegan = true
            drag.delegate = self
            bar.addGestureRecognizer(drag)
            dragGesture = drag
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(trackHover(_:)))
            bar.addGestureRecognizer(hover)
            hoverGesture = hover
            pointerInteractions = bar.interactions.compactMap { interaction in
                guard let pointer = interaction as? UIPointerInteraction else { return nil }
                return (pointer, pointer.isEnabled)
            }
            for (pointer, _) in pointerInteractions { pointer.isEnabled = false }
            return
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let platter = lens?.superview else { return false }
        return platter.bounds.contains(touch.location(in: platter))
    }

    @objc private func trackSelection(_ gesture: UIGestureRecognizer) {
        guard gesture === dragGesture, let bar = tabBar, let lens, let platter = lens.superview,
            let content, content.superview === platter
        else { return }
        let frames = Self.frames(in: content, relativeTo: platter)
        guard frames.count == RevaTab.allCases.count else {
            anchor = nil
            isDragging = false
            isHovering = false
            updateLink?.requiresContinuousUpdates = false
            return
        }
        pointerX = gesture.location(in: platter).x

        switch gesture.state {
        case .began:
            itemFrames = frames
            isDragging = true
            isHovering = false
            restingAnchor = visualSelection(in: bar)
            // A press on another tab starts rooted on that tab, just like native tapping.
            anchor = NativeTabLensGeometry.pressedAnchor(
                at: pointerX, selected: restingAnchor, frames: frames)
            commitAnchor()
            updateLink?.requiresContinuousUpdates = true
        case .changed:
            advanceAnchor()
            commitAnchor()
        case .ended:
            // Some event sources provide an endpoint without intermediate move events.
            advanceAnchor()
            commitAnchor()
            isDragging = false
            settleUntil = CACurrentMediaTime() + 0.25
        case .cancelled, .failed:
            guard isDragging else { return }
            anchor = restingAnchor
            commitAnchor()
            isDragging = false
            isHovering = false
            settleUntil = CACurrentMediaTime() + 0.25
        default:
            break
        }
    }

    private func visualSelection(in bar: UITabBar) -> Int {
        let index = bar.items?.firstIndex(where: { $0 === bar.selectedItem }) ?? 0
        return bar.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? RevaTab.allCases.count - 1 - index : index
    }

    private func commitAnchor() {
        guard let anchor, let bar = tabBar else { return }
        let index =
            bar.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? RevaTab.allCases.count - 1 - anchor : anchor
        onSelect?(index)
    }

    @objc private func trackHover(_ gesture: UIHoverGestureRecognizer) {
        guard !isDragging, let bar = tabBar, let content, let platter = lens?.superview else { return }
        itemFrames = Self.frames(in: content, relativeTo: platter)
        anchor = visualSelection(in: bar)
        pointerX = gesture.location(in: platter).x
        isHovering = gesture.state == .began || gesture.state == .changed
        settleUntil = CACurrentMediaTime() + 0.25
        updateLink?.requiresContinuousUpdates = true
    }

    private func advanceAnchor() {
        guard let anchor else { return }
        self.anchor = NativeTabLensGeometry.anchor(at: pointerX, current: anchor, frames: itemFrames)
    }

    private func updateHeldLens() {
        guard let anchor, let lens, itemFrames.indices.contains(anchor), lens.window === window else {
            return
        }
        let held = isDragging || isHovering
        guard held || CACurrentMediaTime() < settleUntil else {
            self.anchor = nil
            updateLink?.requiresContinuousUpdates = false
            return
        }
        let frame =
            held
            ? NativeTabLensGeometry.heldFrame(for: itemFrames[anchor], pointerX: pointerX)
            : itemFrames[anchor]
        UIView.performWithoutAnimation {
            lens.bounds = CGRect(origin: .zero, size: frame.size)
            lens.center = CGPoint(x: frame.midX, y: frame.midY)
            lens.layoutIfNeeded()
        }
        // Native continuous selection is disabled: pointer motion has one geometry owner.
    }

    private static func frames(in group: UIView, relativeTo platter: UIView) -> [CGRect] {
        group.subviews.compactMap { view in
            guard view is UIControl, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
            return view.convert(view.bounds, to: platter)
        }.sorted { $0.minX < $1.minX }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden { return bar }
        return view.subviews.lazy.compactMap { findTabBar(in: $0) }.first
    }
}

// MARK: - Anchored lens geometry

private enum NativeTabLensGeometry {
    static func pressedAnchor(at x: CGFloat, selected: Int, frames: [CGRect]) -> Int? {
        if frames.indices.contains(selected), (frames[selected].minX...frames[selected].maxX).contains(x) {
            return selected
        }
        return frames.indices.first { (frames[$0].minX...frames[$0].maxX).contains(x) }
            ?? frames.indices.min { abs(frames[$0].midX - x) < abs(frames[$1].midX - x) }
    }

    /// Hysteresis keeps a pointer near a boundary from rapidly switching back and forth.
    static func anchor(at x: CGFloat, current: Int, frames: [CGRect]) -> Int {
        guard frames.indices.contains(current) else { return current }
        var index = current
        while index + 1 < frames.count && x > (frames[index].midX + frames[index + 1].midX) / 2 + 5 {
            index += 1
        }
        while index > 0 && x < (frames[index].midX + frames[index - 1].midX) / 2 - 5 {
            index -= 1
        }
        return index
    }

    /// Grow only the dragged edge; the opposite edge and vertical center stay rooted.
    static func heldFrame(for item: CGRect, pointerX: CGFloat) -> CGRect {
        var frame = item.insetBy(dx: 2, dy: 1)
        let pull = pointerX - item.midX
        let stretch = min(abs(pull) * 0.22, 8)
        if pull < 0 { frame.origin.x -= stretch }
        frame.size.width += stretch
        return frame
    }
}
