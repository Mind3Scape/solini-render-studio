import AppKit
let size=NSSize(width:1024,height:1024)
let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
NSColor(red:0.065,green:0.067,blue:0.078,alpha:1).setFill();NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
let logo=NSImage(contentsOfFile:"Salini/Resources/salini-logo.png")!
logo.draw(in:NSRect(x:180,y:378,width:664,height:269))
NSGraphicsContext.restoreGraphicsState()
let folder=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("AppIcon.png"))
try "{\"images\":[{\"filename\":\"AppIcon.png\",\"idiom\":\"universal\",\"platform\":\"ios\",\"size\":\"1024x1024\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to:folder.appendingPathComponent("Contents.json"),atomically:true,encoding:.utf8)
