// Offline motion proof using the same three raster layers as the interactive page.
// This renders a video asset; it does not drive a browser or capture app UI.
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let out=root.appendingPathComponent("motion-proof.mp4")
let width=1280, height=854, fps=30, seconds=42
func load(_ name:String)->CGImage { let s=CGImageSourceCreateWithURL(root.appendingPathComponent("assets/"+name).appendingPathExtension("png") as CFURL,nil)!; return CGImageSourceCreateImageAtIndex(s,0,nil)! }
let room=load("workshop"), loaded=load("carrier-loaded"), empty=load("carrier-empty")
func smooth(_ a:Double)->Double { let t=max(0,min(1,a));return t*t*t*(t*(t*6-15)+10) }
func interpolate(_ a:CGPoint,_ b:CGPoint,_ t:Double)->CGPoint { CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t) }
let hidden=CGPoint(x:350,y:280), station=CGPoint(x:523,y:441), exitPoint=CGPoint(x:1800,y:1150)
func state(_ t:Double)->(CGPoint,Bool,String,String) {
 if t<3.5{return(interpolate(hidden,station,smooth(t/3.5)),true,"Выход из зоны контроля","01  КОНТРОЛЬ")}
 if t<8.5{return(station,true,"Проверка поверхности","01  КОНТРОЛЬ")}
 if t<21{return(interpolate(station,exitPoint,smooth((t-8.5)/12.5)),true,"Партия направляется на упаковку","02  ПЕРЕМЕЩЕНИЕ")}
 if t<24.5{return(exitPoint,false,"Изделия переданы на упаковку","03  УПАКОВКА")}
 if t<37{return(interpolate(exitPoint,hidden,smooth((t-24.5)/12.5)),false,"Пустая платформа возвращается","03  ВОЗВРАТ")}
 return(hidden,false,"Подготовка следующего цикла","01  КОНТРОЛЬ")
}
func image(_ c:CGContext,_ im:CGImage,_ r:CGRect){c.saveGState();c.translateBy(x:r.minX,y:r.maxY);c.scaleBy(x:1,y:-1);c.draw(im,in:CGRect(origin:.zero,size:r.size));c.restoreGState()}
func text(_ c:CGContext,_ value:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor,weight:NSFont.Weight = .regular){
 c.saveGState();c.textMatrix=CGAffineTransform(scaleX:1,y:-1);c.textPosition=CGPoint(x:x,y:y)
 let line=CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color]));CTLineDraw(line,c);c.restoreGState()
}
func draw(_ c:CGContext,_ t:Double){
 c.saveGState();c.translateBy(x:0,y:CGFloat(height));c.scaleBy(x:CGFloat(width)/1536,y:-CGFloat(height)/1024)
 image(c,room,CGRect(x:0,y:0,width:1536,height:1024));let(p,cargo,title,phase)=state(t)
 c.saveGState();c.setStrokeColor(CGColor(red:0.20,green:0.36,blue:0.32,alpha:0.21));c.setLineWidth(1.6);c.setLineDash(phase:0,lengths:[4,8]);c.move(to:CGPoint(x:536,y:475));c.addLine(to:CGPoint(x:1440,y:976));c.strokePath();c.restoreGState()
 c.saveGState();c.translateBy(x:p.x+5,y:p.y-16);c.rotate(by:0.49);c.scaleBy(x:1,y:0.47)
 let cs=CGColorSpaceCreateDeviceRGB();let g=CGGradient(colorsSpace:cs,colors:[CGColor(red:0.14,green:0.15,blue:0.12,alpha:0.50),CGColor(red:0.14,green:0.15,blue:0.12,alpha:0.15),CGColor(red:0.14,green:0.15,blue:0.12,alpha:0)] as CFArray,locations:[0,0.6,1])!
 c.drawRadialGradient(g,startCenter:.zero,startRadius:0,endCenter:.zero,endRadius:108,options:[]);c.restoreGState()
 let size:CGFloat=227,x=p.x-size*0.5,y=p.y-size*0.755
 image(c,cargo ? loaded:empty,CGRect(x:x,y:y,width:size,height:size))
 let travel=hypot(p.x-hidden.x,p.y-hidden.y)*(cargo ? 1:-1)
 for hub in [CGPoint(x:97,y:607),CGPoint(x:665,y:1020)] {
  let center=CGPoint(x:x+hub.x/1254*size,y:y+hub.y/1254*size)
  c.setStrokeColor(CGColor(gray:0.84,alpha:0.65));c.setLineWidth(0.8)
  for spoke in 0..<3 {let angle=travel/10+Double(spoke)*Double.pi*2/3;c.move(to:center);c.addLine(to:CGPoint(x:center.x+4*cos(angle),y:center.y+7*sin(angle)));c.strokePath()}
 }
 let beacon=CGPoint(x:x+size*0.904,y:y+size*0.545);let pulse=0.35+0.65*pow((sin(t*5)+1)/2,4)
 c.setFillColor(CGColor(red:1,green:0.75,blue:0.25,alpha:pulse*0.8));c.fillEllipse(in:CGRect(x:beacon.x-1.7,y:beacon.y-1.2,width:3.4,height:2.4))
 c.saveGState();c.beginPath();let points:[CGPoint]=[.init(x:215,y:70),.init(x:510,y:55),.init(x:577,y:175),.init(x:574,y:321),.init(x:537,y:345),.init(x:501,y:355),.init(x:476,y:337),.init(x:449,y:306),.init(x:274,y:345),.init(x:222,y:323)]
 c.addLines(between:points);c.closePath();c.clip();image(c,room,CGRect(x:0,y:0,width:1536,height:1024));c.restoreGState()
 c.saveGState();c.addLines(between:[.init(x:325,y:235),.init(x:365,y:218),.init(x:406,y:222),.init(x:397,y:245),.init(x:367,y:254)]);c.closePath();c.clip();let q=(sin(t*1.15)+1)/2;c.setStrokeColor(CGColor(red:0.88,green:1,blue:1,alpha:0.6));c.setLineWidth(1.2);c.move(to:CGPoint(x:330+q*73,y:217));c.addLine(to:CGPoint(x:334+q*73,y:257));c.strokePath();c.restoreGState()
 // Caption band belongs to the proof video, not to the product UI.
 c.setFillColor(CGColor(red:0.95,green:0.96,blue:0.94,alpha:0.95));c.addPath(CGPath(roundedRect:CGRect(x:38,y:840,width:1460,height:145),cornerWidth:22,cornerHeight:22,transform:nil));c.fillPath()
 text(c,"SALINI INSIGHT  /  "+phase,65,875,13,NSColor(calibratedRed:0.27,green:0.40,blue:0.37,alpha:1),weight:.medium)
 text(c,title,65,914,27,NSColor(calibratedRed:0.1,green:0.19,blue:0.2,alpha:1),weight:.medium)
 text(c,"Фиксированный ракурс · отдельные слои · демонстрационный процесс",65,944,14,.secondaryLabelColor)
 text(c,String(format:"%02d / 42",Int(t)),1390,877,14,.secondaryLabelColor)
 c.setFillColor(CGColor(red:0.77,green:0.83,blue:0.79,alpha:1));c.fill(CGRect(x:65,y:963,width:1400,height:2));c.setFillColor(CGColor(red:0.22,green:0.42,blue:0.38,alpha:1));c.fill(CGRect(x:65,y:963,width:1400*t/42,height:2))
 c.restoreGState()
}
let colorSpace=CGColorSpaceCreateDeviceRGB()
let data=UnsafeMutableRawPointer.allocate(byteCount:width*height*4,alignment:64)
defer {data.deallocate()}
let context=CGContext(data:data,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
for frame in 0..<(fps*seconds) {
 autoreleasepool {
  draw(context,Double(frame)/Double(fps))
  if [150,390,930].contains(frame) {
   let url=root.appendingPathComponent("frame-\(frame/fps).png")
   let dst=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
   CGImageDestinationAddImage(dst,context.makeImage()!,nil);CGImageDestinationFinalize(dst)
  }
  FileHandle.standardOutput.write(Data(bytesNoCopy:data,count:width*height*4,deallocator:.none))
 }
 if frame%300==0 {FileHandle.standardError.write(Data("rendered \(frame)/\(fps*seconds)\n".utf8))}
}
