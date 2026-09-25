import CoreGraphics

public enum PreviewWindowSizing {
    public static func initialContentSize(
        sourceSize: CGSize,
        availableSize: CGSize,
        maximumSize: CGSize = CGSize(width: 1800, height: 1125)
    ) -> CGSize? {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            availableSize.width > 0,
            availableSize.height > 0,
            maximumSize.width > 0,
            maximumSize.height > 0
        else {
            return nil
        }

        let availableWidth = min(
            availableSize.width * 0.7,
            maximumSize.width
        )
        let availableHeight = min(
            availableSize.height * 0.8,
            maximumSize.height
        )
        let scale = min(
            availableWidth / sourceSize.width,
            availableHeight / sourceSize.height
        )

        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }
}

