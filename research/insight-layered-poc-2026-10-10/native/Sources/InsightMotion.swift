import SwiftUI
import SpriteKit

enum LabZone:String,Identifiable {case quality="Контроль качества",carrier="Партия 024",packing="Отгрузка · рейс 02";var id:String{rawValue}}
@MainActor final class InsightDriver:ObservableObject {
    @Published var time=6.0
    @Published var playing = !UIAccessibility.isReduceMotionEnabled
    @Published var zoom=1.0
    @Published var selected:LabZone?
    @Published var layersOpen=false
    @Published var infoOpen=false
    @Published var showCarrier=true
    @Published var showActivity=true
    @Published var showLabels=true
    @Published var isActive=true
    let scene:InsightScene
    var frame:MotionFrame{MotionFrame.at(time)}
    init(){scene=InsightScene();scene.driver=self}
    func seek(_ value:Double){time=max(0,min(MotionFrame.duration-0.001,value));scene.setTime(time)}
}

@MainActor final class InsightScene:SKScene {
    weak var driver:InsightDriver?
    private let world=SKNode(),carrier=SKSpriteNode(),shadow=SKSpriteNode()
    private let beacon=SKShapeNode(ellipseOf:CGSize(width:3.4,height:2))
    private var labels:[LabZone:SKNode]=[:],spokes:[SKShapeNode]=[]
    private var elapsed=6.0,previous=0.0,published=0.0,currentZoom=1.0
    private var built=false
    private func pt(_ x:CGFloat,_ y:CGFloat)->CGPoint{CGPoint(x:x,y:1536-y)}
    override init(size:CGSize){super.init(size:size);scaleMode = .resizeFill;backgroundColor=UIColor(red:0.93,green:0.94,blue:0.95,alpha:1)}
    override convenience init(){self.init(size:CGSize(width:390,height:560))}
    required init?(coder:NSCoder){fatalError("Not supported")}
    override func didMove(to view:SKView){
        guard !built else{return};built=true;addChild(world)
        let texture=SKTexture(imageNamed:"architecture-base.png");texture.filteringMode = .linear
        let base=SKSpriteNode(texture:texture,size:CGSize(width:1024,height:1536));base.anchorPoint = .zero;world.addChild(base)
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:220,height:150))
        let shadowImage=renderer.image{context in
            let c=context.cgContext;c.translateBy(x:110,y:75);c.rotate(by:-0.46);c.scaleBy(x:1,y:0.3)
            let colors=[UIColor(red:0.05,green:0.08,blue:0.1,alpha:0.3).cgColor,UIColor(red:0.05,green:0.08,blue:0.1,alpha:0.12).cgColor,UIColor.clear.cgColor]
            let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,0.7,1])!
            c.drawRadialGradient(g,startCenter:.zero,startRadius:10,endCenter:.zero,endRadius:95,options:[])
        }
        shadow.texture=SKTexture(image:shadowImage);shadow.size=CGSize(width:220,height:150);shadow.zPosition=1;world.addChild(shadow)
        let vehicle=SKTexture(imageNamed:"tow-tractor.png");vehicle.filteringMode = .linear
        carrier.texture=vehicle;carrier.size=CGSize(width:218,height:218);carrier.anchorPoint=CGPoint(x:0.5,y:0.25);carrier.zPosition=2;carrier.name="carrier";world.addChild(carrier)
        let r=218.0/1280
        beacon.position=CGPoint(x:(973-640)*r,y:(960-213)*r);beacon.fillColor=UIColor(red:1,green:0.82,blue:0.36,alpha:1);beacon.strokeColor = .clear;carrier.addChild(beacon)
        for (x,y) in [(356.0,1009.0),(674,866),(898,733),(1120,650)] {
            let spoke=SKShapeNode();spoke.position=CGPoint(x:(x-640)*r,y:(960-y)*r);spoke.strokeColor=UIColor(red:0.78,green:0.81,blue:0.84,alpha:0.55);spoke.lineWidth=0.65;carrier.addChild(spoke);spokes.append(spoke)
        }
        makeLabel(.quality,at:pt(395,470));makeLabel(.packing,at:pt(816,928))
    }
    private func makeLabel(_ zone:LabZone,at p:CGPoint){
        let n=SKNode();n.position=p;n.zPosition=3;n.name=zone.id
        let bg=SKShapeNode(rectOf:CGSize(width:zone == .quality ? 259:198,height:64),cornerRadius:21);bg.position.y=32;bg.fillColor=zone == .quality ? UIColor(white:1,alpha:0.91):UIColor(red:0.08,green:0.17,blue:0.24,alpha:0.91);bg.strokeColor=UIColor(white:1,alpha:0.5);bg.lineWidth=1;bg.name=zone.id;n.addChild(bg)
        let title=SKLabelNode(fontNamed:"HelveticaNeue-Medium");title.text=zone == .quality ? "Контроль качества":"Отгрузка";title.fontSize=25;title.fontColor=zone == .quality ? UIColor(red:0.09,green:0.14,blue:0.2,alpha:1):.white;title.verticalAlignmentMode = .center;title.position.y=32;title.name=zone.id;n.addChild(title);labels[zone]=n;world.addChild(n)
    }
    func setTime(_ value:Double){elapsed=value;previous=0}
    override func update(_ currentTime:TimeInterval){
        guard built,let d=driver else{return};let dt=previous>0 ? min(0.06,currentTime-previous):0;previous=currentTime
        if d.playing && d.isActive && d.selected == nil && !d.layersOpen && !d.infoOpen {elapsed=(elapsed+dt).truncatingRemainder(dividingBy:MotionFrame.duration)}
        let f=MotionFrame.at(elapsed);carrier.position=pt(f.position.x,f.position.y);shadow.position=carrier.position;carrier.isHidden = !d.showCarrier;shadow.isHidden = !d.showCarrier;beacon.isHidden = !d.showActivity;beacon.alpha=0.35+0.65*pow((sin(elapsed*5)+1)/2,4)
        let angle=(f.position.x-360)/6
        for s in spokes {let p=CGMutablePath();for i in 0..<3 {let a=angle+Double(i)*Double.pi*2/3;p.move(to:.zero);p.addLine(to:CGPoint(x:2*cos(a),y:3*sin(a)))};s.path=p;s.isHidden = !d.showActivity}
        labels.values.forEach{$0.isHidden = !d.showLabels}
        currentZoom += (d.zoom-currentZoom)*(1-exp(-dt*5))
        let scale=min(size.width/1024,size.height/1536)*currentZoom;world.setScale(scale);world.position=CGPoint(x:(size.width-1024*scale)/2,y:(size.height-1536*scale)/2)
        if currentTime-published>0.1 {published=currentTime;d.time=elapsed}
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){
        guard let point=touches.first?.location(in:self) else{return}
        // Transparent canvas outside the actual sprite must not intercept taps.
        for node in nodes(at:point){if let name=node.name,let zone=LabZone(rawValue:name){driver?.selected=zone;return}}
        let local=carrier.convert(point,from:self)
        if !carrier.isHidden && local.x > -94 && local.x < 94 && local.y > -22 && local.y < 132 {driver?.selected = .carrier}
    }
}
