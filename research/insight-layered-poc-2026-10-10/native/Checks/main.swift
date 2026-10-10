import Foundation
func check(_ v:@autoclosure()->Bool,_ message:String){precondition(v(),message)}
func distance(_ a:CGPoint,_ b:CGPoint)->Double{hypot(a.x-b.x,a.y-b.y)}
func outside(_ p:CGPoint)->Bool{p.x+110<0 || p.x-110>1024 || p.y-170>1536}
for b in [0.0,5.0,29.0,40.0] {let a=MotionFrame.at(b==0 ? 40-0.0001:b-0.0001),c=MotionFrame.at(b+0.0001);check(distance(a.position,c.position)<0.001,"Discontinuity at \(b)")}
for t in stride(from:0.0,to:40.0,by:1.0/120){let f=MotionFrame.at(t),next=MotionFrame.at(t+1.0/120);check((0...1).contains(f.progress),"Progress out of bounds");check((0...2).contains(f.stage),"Stage out of bounds");check(abs(f.position.y-(1590-0.5*f.position.x))<0.001,"Vehicle leaves road axis");if distance(f.position,next.position)>3{check(outside(f.position)&&outside(next.position),"Visible loop reset")}else{check(next.position.x>=f.position.x-0.001,"Vehicle moves backwards")}}
for t in stride(from:0.0,to:5.0,by:0.1){check(distance(MotionFrame.at(t).position,MotionFrame.quality)==0,"Vehicle drifts while stopped")}
check(MotionFrame.at(16).stage==1,"Action stage mismatched")
check(MotionFrame.at(30).stage==2,"Dispatch dwell mismatched")
print("PASS: road alignment, forward-only travel, smooth stops/loop join, offscreen-only reset, valid progress/stages, 120Hz trajectory")
