import CoreGraphics

public enum PreviewCoordinateMapper {
    public static func displayLocalPoint(
        previewPoint: CGPoint,
        previewSize: CGSize,
        sourceSize: CGSize,
        displaySize: CGSize
    ) -> CGPoint? {
        guard
            let viewport = AspectFitViewport(
                sourceWidth: sourceSize.width,
                sourceHeight: sourceSize.height,
                destinationWidth: previewSize.width,
                destinationHeight: previewSize.height
            ),
            displaySize.width > 0,
            displaySize.height > 0
        else {
            return nil
        }

        let maximumX = viewport.originX + viewport.width
        let maximumY = viewport.originY + viewport.height
        guard
            previewPoint.x >= viewport.originX,
            previewPoint.x < maximumX,
            previewPoint.y >= viewport.originY,
            previewPoint.y < maximumY
        else {
            return nil
        }

        let normalizedX = (previewPoint.x - viewport.originX) / viewport.width
        let normalizedY = (previewPoint.y - viewport.originY) / viewport.height

        return CGPoint(
            x: clampToDisplay(normalizedX * displaySize.width, extent: displaySize.width),
            y: clampToDisplay(
                (1 - normalizedY) * displaySize.height,
                extent: displaySize.height
            )
        )
    }

    private static func clampToDisplay(
        _ value: CGFloat,
        extent: CGFloat
    ) -> CGFloat {
        min(max(value, 0), max(extent - 0.5, 0))
    }
}

