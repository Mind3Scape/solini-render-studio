import SwiftUI
import SpriteKit

enum LabZone: String, Identifiable, CaseIterable {
    case quality = "Контроль", carrier = "Партия 024", packing = "Упаковка"
    var id: String { rawValue }
}

@MainActor final class InsightDriver: ObservableObject {
    @Published var time = 5.0
    @Published var playing = !UIAccessibility.isReduceMotionEnabled
    @Published var follow = true
    @Published var zoom = 1.0
    @Published var selected: LabZone?
    @Published var layersOpen = false
    @Published var showCarrier = true
    @Published var showShadows = true
    @Published var showActivity = true
    @Published var showRoute = true
    @Published var onlyPlate = false
    @Published var isActive = true
    @Published var infoOpen = false
    let scene: InsightScene
    var frame: MotionFrame { MotionFrame.at(time) }
    init() { scene = InsightScene(); scene.driver = self }
    func seek(_ value: Double) { time = max(0,min(MotionFrame.duration-0.001,value));scene.setTime(time) }
    func togglePlayback() { playing.toggle() }
}

@MainActor final class InsightScene: SKScene {
    weak var driver: InsightDriver?
    private let world = SKNode()
    private let carrier = SKSpriteNode()
    private let shadow = SKSpriteNode()
    private let route = SKShapeNode()
    private let beacon = SKShapeNode(circleOfRadius:2)
    private let scanner = SKShapeNode()
    private var spokes:[SKShapeNode] = []
    private var labels:[LabZone:SKNode] = [:]
    private var loadedTexture:SKTexture!
    private var emptyTexture:SKTexture!
    private var elapsed = 5.0
    private var previous = 0.0
    private var published = 0.0
    private var cameraPoint = CGPoint(x:720,y:500)
    private var currentZoom = 1.0
    private var previousPoint = MotionFrame.quality
    private var wheelDistance = 0.0
    private var built = false
    private func pt(_ x: CGFloat,_ y: CGFloat)->CGPoint { CGPoint(x:x,y:1024-y) }
    override init(size: CGSize) { super.init(size:size);scaleMode = .resizeFill;backgroundColor = UIColor(red:0.88,green:0.89,blue:0.86,alpha:1) }
    override convenience init() { self.init(size:CGSize(width:390,height:530)) }
    required init?(coder:NSCoder){fatalError("Not supported")}
    override func didMove(to view:SKView) {
        guard !built else{return};built = true
        addChild(world)
        let texture = SKTexture(imageNamed:"workshop.png");texture.filteringMode = .linear
        let room = SKSpriteNode(texture:texture,size:CGSize(width:1536,height:1024));room.anchorPoint = .zero;room.position = .zero;room.zPosition = 0;world.addChild(room)
        loadedTexture = SKTexture(imageNamed:"carrier-loaded.png");emptyTexture = SKTexture(imageNamed:"carrier-empty.png")
        loadedTexture.filteringMode = .linear;emptyTexture.filteringMode = .linear
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:300,height:200))
        let shadowImage = renderer.image { context in
            let c=context.cgContext; let colors=[UIColor(white:0.12,alpha:0.50).cgColor,UIColor(white:0.12,alpha:0.15).cgColor,UIColor(white:0.12,alpha:0).cgColor]
            let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,0.6,1])!
            c.translateBy(x:150,y:100);c.rotate(by:0.49);c.scaleBy(x:1,y:0.47)
            c.drawRadialGradient(g,startCenter:.zero,startRadius:0,endCenter:.zero,endRadius:120,options:[])
        }
        shadow.texture = SKTexture(image:shadowImage);shadow.size = CGSize(width:300,height:200);shadow.zPosition = 2;world.addChild(shadow)
        let rp=CGMutablePath();rp.move(to:pt(536,475));rp.addLine(to:pt(1440,976));route.path=rp;route.lineWidth=1.5;route.strokeColor=UIColor(red:0.21,green:0.37,blue:0.32,alpha:0.23);route.zPosition=1;world.addChild(route)
        carrier.texture=loadedTexture;carrier.size=CGSize(width:227,height:227);carrier.anchorPoint=CGPoint(x:0.5,y:0.245);carrier.zPosition=3;carrier.name="carrier";world.addChild(carrier)
        beacon.fillColor=UIColor(red:1,green:0.78,blue:0.30,alpha:1);beacon.strokeColor = .clear;beacon.glowWidth=3;beacon.position=CGPoint(x:227*0.404,y:227*0.210);carrier.addChild(beacon)
        for _ in 0..<2 {let s=SKShapeNode();s.strokeColor=UIColor(white:0.84,alpha:0.65);s.lineWidth=0.8;s.zPosition=5;carrier.addChild(s);spokes.append(s)}
        // Foreground geometry mask restores only station pixels above the moving cart.
        let crop=SKCropNode();crop.zPosition=4
        let path=CGMutablePath();let vertices:[CGPoint]=[pt(215,70),pt(510,55),pt(577,175),pt(574,321),pt(537,345),pt(501,355),pt(476,337),pt(449,306),pt(274,345),pt(222,323)]
        path.addLines(between:vertices);path.closeSubpath();let mask=SKShapeNode(path:path);mask.fillColor = .white;mask.strokeColor = .clear;crop.maskNode=mask
        let fg=SKSpriteNode(texture:texture,size:CGSize(width:1536,height:1024));fg.anchorPoint = .zero;crop.addChild(fg);world.addChild(crop)
        let scanCrop=SKCropNode();scanCrop.zPosition=5;let sp=CGMutablePath();sp.addLines(between:[pt(325,235),pt(365,218),pt(406,222),pt(397,245),pt(367,254)]);sp.closeSubpath();let sm=SKShapeNode(path:sp);sm.fillColor = .white;sm.strokeColor = .clear;scanCrop.maskNode=sm
        scanner.strokeColor=UIColor(red:0.88,green:1,blue:1,alpha:0.6);scanner.lineWidth=1.4;scanner.glowWidth=0.8;scanCrop.addChild(scanner);world.addChild(scanCrop)
        makeLabel(.quality,"Контроль",at:pt(520,323));makeLabel(.packing,"Упаковка",at:pt(1190,405));makeLabel(.carrier,"Партия 024",at:pt(523,280))
    }
    private func makeLabel(_ zone:LabZone,_ title:String,at position:CGPoint){
        let node=SKNode();node.position=position;node.zPosition=10;node.name=zone.id
        let bg=SKShapeNode(rectOf:CGSize(width:158,height:43),cornerRadius:14);bg.fillColor=UIColor(white:1,alpha:0.94);bg.strokeColor=UIColor(white:1,alpha:0.95);bg.lineWidth=1;bg.name=zone.id;node.addChild(bg)
        let text=SKLabelNode(fontNamed:"HelveticaNeue-Medium");text.text=title;text.fontSize=16;text.fontColor=UIColor(red:0.14,green:0.25,blue:0.25,alpha:1);text.verticalAlignmentMode = .center;text.name=zone.id;node.addChild(text);labels[zone]=node;world.addChild(node)
    }
    func setTime(_ value:Double){elapsed=value;previousPoint=MotionFrame.at(value).position;previous=0}
    override func update(_ currentTime:TimeInterval){
        guard built,let d=driver else{return}
        let dt=previous>0 ? min(0.06,currentTime-previous):0;previous=currentTime
        if d.playing && d.isActive {elapsed=(elapsed+dt).truncatingRemainder(dividingBy:MotionFrame.duration)}
        let f=MotionFrame.at(elapsed)
        let distance=hypot(f.position.x-previousPoint.x,f.position.y-previousPoint.y);if distance<80 {wheelDistance += distance*(f.loaded ? 1:-1)};previousPoint=f.position
        carrier.texture=f.loaded ? loadedTexture:emptyTexture;carrier.position=pt(f.position.x,f.position.y);shadow.position=pt(f.position.x+5,f.position.y-16)
        carrier.isHidden=d.onlyPlate || !d.showCarrier;shadow.isHidden=d.onlyPlate || !d.showCarrier || !d.showShadows;route.isHidden=d.onlyPlate || !d.showRoute;scanner.isHidden=d.onlyPlate || !d.showActivity;beacon.isHidden = !d.showActivity
        beacon.alpha=0.25+0.75*pow((sin(elapsed*5)+1)/2,4)
        for (index,s) in spokes.enumerated(){let hub=index==0 ? CGPoint(x:97,y:607):CGPoint(x:665,y:1020);let center=CGPoint(x:(hub.x/1254-0.5)*227,y:(0.755-hub.y/1254)*227);let p=CGMutablePath();for spoke in 0..<3 {let angle=wheelDistance/10+Double(spoke)*Double.pi*2/3;p.move(to:center);p.addLine(to:CGPoint(x:center.x+4*cos(angle),y:center.y+7*sin(angle)))};s.path=p;s.isHidden = !d.showActivity}
        let x=330+(sin(elapsed*1.15)+1)/2*73;let p=CGMutablePath();p.move(to:pt(x,217));p.addLine(to:pt(x+4,257));scanner.path=p
        labels[.carrier]?.position=pt(f.position.x,f.position.y-150)
        for (zone,label) in labels {label.isHidden=d.onlyPlate || (zone == .carrier && !d.showCarrier)}
        currentZoom += (d.zoom-currentZoom)*(1-exp(-dt*5))
        var target=CGPoint(x:750,y:500)
        if d.follow && size.width<700 {target.x=max(650,min(1050,f.position.x));target.y=max(480,min(650,f.position.y-30))}
        cameraPoint.x += (target.x-cameraPoint.x)*(1-exp(-dt*1.1));cameraPoint.y += (target.y-cameraPoint.y)*(1-exp(-dt*1.1))
        let scale=max(size.width/1536,size.height/1024)*currentZoom
        world.setScale(scale);let desired=CGPoint(x:size.width/2-cameraPoint.x*scale,y:size.height*0.5-(1024-cameraPoint.y)*scale)
        world.position=CGPoint(x:max(size.width-1536*scale,min(0,desired.x)),y:max(size.height-1024*scale,min(0,desired.y)))
        if currentTime-published>0.1 {published=currentTime;d.time=elapsed}
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){
        guard let p=touches.first?.location(in:self) else{return}
        for node in nodes(at:p) {if let name=node.name {if name=="carrier" {driver?.selected = .carrier;return};if let zone=LabZone(rawValue:name){driver?.selected=zone;return}}}
    }
}
