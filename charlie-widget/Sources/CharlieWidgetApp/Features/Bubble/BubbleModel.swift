import Foundation

struct Bubble: Identifiable {
    let id: String
    let agentLetter: String
    var isWarm: Bool
    var position: CGPoint
    var velocity: CGPoint
    let size: CGFloat
}
