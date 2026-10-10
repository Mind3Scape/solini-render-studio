import Foundation

struct MotionFrame {
    var position: CGPoint
    var loaded: Bool
    var stage: Int
    var title: String
    var progress: Double
    static let duration = 42.0
    static let hidden = CGPoint(x:350,y:280)
    static let quality = CGPoint(x:523,y:441)
    static let exit = CGPoint(x:1800,y:1150)
    static func interpolate(_ a:CGPoint,_ b:CGPoint,_ t:Double) -> CGPoint {
        let u = max(0,min(1,t)); let s = u*u*u*(u*(u*6-15)+10)
        return CGPoint(x:a.x+(b.x-a.x)*s,y:a.y+(b.y-a.y)*s)
    }
    static func at(_ time: Double) -> MotionFrame {
        let t = max(0,time.truncatingRemainder(dividingBy:duration))
        if t<3.5 { return .init(position:interpolate(hidden,quality,t/3.5),loaded:true,stage:0,title:"Выход из зоны контроля",progress:t/8.5) }
        if t<8.5 { return .init(position:quality,loaded:true,stage:0,title:"Проверка поверхности",progress:t/8.5) }
        if t<21 { return .init(position:interpolate(quality,exit,(t-8.5)/12.5),loaded:true,stage:1,title:"Партия направляется на упаковку",progress:(t-8.5)/12.5) }
        if t<24.5 { return .init(position:exit,loaded:false,stage:2,title:"Передано на упаковку",progress:(t-21)/3.5) }
        if t<37 { return .init(position:interpolate(exit,hidden,(t-24.5)/12.5),loaded:false,stage:2,title:"Пустая платформа возвращается",progress:1) }
        return .init(position:hidden,loaded:false,stage:0,title:"Подготовка следующего цикла",progress:0)
    }
}
