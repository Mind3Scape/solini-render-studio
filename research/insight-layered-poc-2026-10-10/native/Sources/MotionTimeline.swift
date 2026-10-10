import Foundation

struct MotionFrame {
    var position: CGPoint
    var stage: Int
    var title: String
    var progress: Double
    static let duration=40.0
    static let quality=CGPoint(x:360,y:1410)
    static let hidden=CGPoint(x:-300,y:1740)
    static let exit=CGPoint(x:1270,y:955)
    static func interpolate(_ a:CGPoint,_ b:CGPoint,_ t:Double)->CGPoint {
        let u=max(0,min(1,t)),s=u*u*u*(u*(u*6-15)+10)
        return CGPoint(x:a.x+(b.x-a.x)*s,y:a.y+(b.y-a.y)*s)
    }
    static func at(_ time:Double)->MotionFrame {
        let t=max(0,time.truncatingRemainder(dividingBy:duration))
        if t<5 { return .init(position:quality,stage:0,title:"Контроль пройден · 2 изделия",progress:t/5) }
        if t<29 { return .init(position:interpolate(quality,exit,(t-5)/24),stage:1,title:"Внутренняя логистика · рейс 02",progress:(t-5)/24) }
        if t<31 { return .init(position:exit,stage:2,title:"Партия передана на отгрузку",progress:1) }
        return .init(position:interpolate(hidden,quality,(t-31)/9),stage:0,title:"Следующая партия готовится к отправке",progress:(t-31)/9)
    }
}
