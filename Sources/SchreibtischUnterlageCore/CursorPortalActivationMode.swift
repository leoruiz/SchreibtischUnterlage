public enum CursorPortalActivationMode: String, CaseIterable, Sendable {
    case singleClick
    case doubleClick

    public func shouldActivate(clickCount: Int) -> Bool {
        switch self {
        case .singleClick:
            return clickCount == 1
        case .doubleClick:
            return clickCount == 2
        }
    }
}
