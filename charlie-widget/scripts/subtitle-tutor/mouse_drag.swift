// Test helper: synthesize a left-button drag (screen points, top-left origin).
//   swiftc -O scripts/subtitle-tutor/mouse_drag.swift -o /tmp/mouse_drag && /tmp/mouse_drag x1 y1 x2 y2
// Needs Accessibility permission for the terminal.
import CoreGraphics; import Foundation
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(15000) }
func drag(_ a: CGPoint, _ b: CGPoint) {
  post(.mouseMoved, a); post(.leftMouseDown, a)
  for i in 1...20 { let f = CGFloat(i)/20; post(.leftMouseDragged, CGPoint(x: a.x+(b.x-a.x)*f, y: a.y+(b.y-a.y)*f)) }
  post(.leftMouseUp, b)
}
let v = CommandLine.arguments.dropFirst().compactMap { Double($0) }
drag(CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3]))
