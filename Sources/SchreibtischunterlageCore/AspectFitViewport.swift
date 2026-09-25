public struct AspectFitViewport: Equatable, Sendable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double

    public init?(
        sourceWidth: Double,
        sourceHeight: Double,
        destinationWidth: Double,
        destinationHeight: Double
    ) {
        guard
            sourceWidth > 0,
            sourceHeight > 0,
            destinationWidth > 0,
            destinationHeight > 0
        else {
            return nil
        }

        let sourceAspectRatio = sourceWidth / sourceHeight
        let destinationAspectRatio = destinationWidth / destinationHeight

        if sourceAspectRatio > destinationAspectRatio {
            width = destinationWidth
            height = destinationWidth / sourceAspectRatio
            originX = 0
            originY = (destinationHeight - height) / 2
        } else {
            height = destinationHeight
            width = destinationHeight * sourceAspectRatio
            originX = (destinationWidth - width) / 2
            originY = 0
        }
    }
}

