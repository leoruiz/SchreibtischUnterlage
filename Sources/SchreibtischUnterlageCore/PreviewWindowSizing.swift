import CoreGraphics

public enum PreviewWindowSizing {
    public static func initialContentSize(
        sourceSize: CGSize,
        availableSize: CGSize
    ) -> CGSize? {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            availableSize.width > 0,
            availableSize.height > 0
        else {
            return nil
        }

        let availableWidth = availableSize.width * 0.8
        let availableHeight = availableSize.height * 0.9
        let scale = min(
            availableWidth / sourceSize.width,
            availableHeight / sourceSize.height
        )

        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }

    public static func contentSizePreservingWidth(
        sourceSize: CGSize,
        currentContentSize: CGSize,
        availableSize: CGSize
    ) -> CGSize? {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            currentContentSize.width > 0,
            availableSize.width > 0,
            availableSize.height > 0
        else {
            return nil
        }

        let aspectRatio = sourceSize.width / sourceSize.height
        var width = min(currentContentSize.width, availableSize.width)
        var height = width / aspectRatio

        if height > availableSize.height {
            height = availableSize.height
            width = height * aspectRatio
        }

        return CGSize(width: width, height: height)
    }
}
