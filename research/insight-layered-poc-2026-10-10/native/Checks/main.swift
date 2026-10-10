import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x-b.x, a.y-b.y) }

for boundary in [0.0, 3.5, 8.5, 21.0, 24.5, 37.0, 42.0] {
    let before=MotionFrame.at(boundary == 0 ? 42-0.0001:boundary-0.0001)
    let after=MotionFrame.at(boundary+0.0001)
    check(distance(before.position,after.position)<0.001, "Position discontinuity at \(boundary)")
}
for t in stride(from:0.0,to:42.0,by:1.0/120) {
    let f=MotionFrame.at(t)
    check(f.position.x.isFinite && f.position.y.isFinite,"Invalid position")
    check((0...1).contains(f.progress),"Invalid stage progress")
    check((0...2).contains(f.stage),"Invalid stage")
    let next=MotionFrame.at(t+1.0/120)
    check(distance(f.position,next.position)<2.7,"Unexpected frame jump")
    if f.loaded != next.loaded {
        check(f.position.x>1536+114 || distance(f.position,MotionFrame.hidden)<0.001,"Visible cargo swap")
    }
}
for t in stride(from:3.5,to:8.5,by:0.1) {
    check(distance(MotionFrame.at(t).position,MotionFrame.quality) == 0,"Moving during inspection")
}
check(MotionFrame.at(23).loaded == false,"Offscreen unloading state")
check(MotionFrame.at(31).loaded == false,"Return still loaded")
check(MotionFrame.at(42.01).loaded == true,"Loop has no next load")
print("PASS: continuous position/zero-speed joins, 120Hz trajectory, bounded progress, hidden cargo switches, inspection stop, empty return, loop restart")
