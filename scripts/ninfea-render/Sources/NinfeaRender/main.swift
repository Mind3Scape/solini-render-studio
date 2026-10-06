import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Metal
import RifeMetal
import UniformTypeIdentifiers

enum RenderError: Error { case failed(String) }
let width = 1024
let height = 1536
let fps: Int32 = 30
let duration = 30.0
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let preview = CommandLine.arguments.contains("--preview")
let work = root.appendingPathComponent("ios/.build/ninfea-v2")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
func log(_ text: String) { print(text); fflush(stdout) }
func read(_ path: URL) throws -> CGImage {
  guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw RenderError.failed("Cannot read \(path.path)")
  }
  return image
}
func write(_ image: CGImage, _ path: URL) throws {
  guard let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    throw RenderError.failed("Cannot write \(path.path)")
  }
  CGImageDestinationAddImage(dest, image, nil)
  guard CGImageDestinationFinalize(dest) else { throw RenderError.failed("PNG write failed") }
}
func smooth(_ t: Double) -> Double { let x = min(1,max(0,t)); return x*x*(3-2*x) }

struct Uniforms { var time: Float; var zoom: Float; var pad0: Float = 0; var pad1: Float = 0 }

final class LayerRenderer {
  let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let target: MTLTexture
  private var textures: [MTLTexture] = []
  init() throws {
    guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else {
      throw RenderError.failed("Metal GPU required")
    }
    device=d; queue=q
    let shader = try String(contentsOf: Bundle.module.url(forResource:"Layers",withExtension:"metal")!)
    let lib = try d.makeLibrary(source:shader,options:nil)
    let pd = MTLRenderPipelineDescriptor()
    pd.vertexFunction=lib.makeFunction(name:"layerVertex")
    pd.fragmentFunction=lib.makeFunction(name:"layerFragment")
    pd.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline=try d.makeRenderPipelineState(descriptor:pd)
    let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
    td.usage = [.renderTarget,.shaderRead]
    td.storageMode = .shared
    guard let t=d.makeTexture(descriptor:td) else { throw RenderError.failed("Render target failed") }
    target=t
    let base=root.appendingPathComponent("ios/Salini/Resources/ninfea-interior.png")
    let assets=root.appendingPathComponent("research/ninfea-cinema-2026-10-06/v2/assets")
    for path in [base,base,assets.appendingPathComponent("water-pool.png"),
                 assets.appendingPathComponent("foliage-rear.png"),
                 assets.appendingPathComponent("foliage-front.png"),
                 assets.appendingPathComponent("climbing-vine.png")] {
      textures.append(try texture(read(path)))
    }
  }
  private func texture(_ image: CGImage) throws -> MTLTexture {
    // Explicit premultiplication makes alpha handling deterministic across loaders.
    var data=[UInt8](repeating:0,count:width*height*4)
    try data.withUnsafeMutableBytes { buffer in
      guard let ctx=CGContext(data:buffer.baseAddress,width:width,height:height,
        bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
      else { throw RenderError.failed("Texture context failed") }
      ctx.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
    }
    let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
    td.usage = .shaderRead; td.storageMode = .shared
    guard let tex=device.makeTexture(descriptor:td) else { throw RenderError.failed("Texture allocation failed") }
    data.withUnsafeBytes { tex.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,
                                      withBytes:$0.baseAddress!,bytesPerRow:width*4) }
    return tex
  }
  func render(time: Double, water: CGImage) throws -> CGImage {
    textures[1]=try texture(water)
    let pass=MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture=target
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    guard let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:pass)
    else { throw RenderError.failed("GPU command failed") }
    var u=Uniforms(time:Float(time),zoom:1+0.025*Float(smooth(time/27)))
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0)
    for (i,tex) in textures.enumerated() { encoder.setFragmentTexture(tex,index:i) }
    encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
    encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
    if let error=command.error { throw error }
    var bytes=[UInt8](repeating:0,count:width*height*4)
    bytes.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,bytesPerRow:width*4,
      from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
    let data=Data(bytes)
    guard let provider=CGDataProvider(data:data as CFData),let image=CGImage(width:width,height:height,
      bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
      bitmapInfo:[.byteOrder32Little,CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue)],
      provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {
      throw RenderError.failed("Frame readback failed")
    }
    return image
  }
}

final class MovieWriter {
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private var frame: Int64 = 0
  init(url: URL) throws {
    // Never silently replace an earlier render. The caller chooses a fresh output.
    writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
    input=AVAssetWriterInput(mediaType:.video,outputSettings:[
      AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,
      AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:6_000_000,
        AVVideoExpectedSourceFrameRateKey:30,AVVideoMaxKeyFrameIntervalKey:30,
        AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel],
      AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2]
    ])
    input.expectsMediaDataInRealTime=false
    adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
      kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,
      kCVPixelBufferIOSurfacePropertiesKey as String:[:]
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? RenderError.failed("Cannot start movie") }
    writer.startSession(atSourceTime:.zero)
  }
  func append(_ image: CGImage) throws {
    while !input.isReadyForMoreMediaData {
      if writer.status == .failed { throw writer.error! }
      Thread.sleep(forTimeInterval:0.002)
    }
    var buffer: CVPixelBuffer?
    guard let pool=adaptor.pixelBufferPool,
      CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer)==kCVReturnSuccess,let buffer else {
      throw RenderError.failed("Movie pixel buffer failed")
    }
    CVPixelBufferLockBaseAddress(buffer,[])
    guard let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,
      bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),
      space:CGColorSpace(name:CGColorSpace.sRGB)!,
      bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue)
    else { throw RenderError.failed("Movie context failed") }
    ctx.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
    CVPixelBufferUnlockBaseAddress(buffer,[])
    guard adaptor.append(buffer,withPresentationTime:CMTime(value:frame,timescale:fps)) else {
      throw writer.error ?? RenderError.failed("Frame append failed")
    }
    frame += 1
  }
  func finish() throws {
    input.markAsFinished()
    let signal=DispatchSemaphore(value:0)
    writer.finishWriting { signal.signal() }
    signal.wait()
    guard writer.status == .completed else { throw writer.error ?? RenderError.failed("Movie finalize failed") }
  }
}

let start=Date()
let renderer=try LayerRenderer()
log("GPU: \(renderer.device.name). RIFE 4.26 HQ, 1024×1536.")
let rife=try RifeInterpolator(configuration:.bundled(qualityTier:.hq,preferredDevice:renderer.device))
let assetRoot=root.appendingPathComponent("research/ninfea-cinema-2026-10-06/v2/assets")
let frames=try [root.appendingPathComponent("ios/Salini/Resources/ninfea-interior.png")]
  .adding(contentsOf:["water-20","water-50","water-75","water-pool"].map { assetRoot.appendingPathComponent($0+".png") })
  .map(read)
let levels:[Double]=[0,0.2,0.5,0.75,1]
var inferenceCount=0
func compose(_ time: Double) throws -> CGImage {
  let level=smooth((time-2)/8)
  let water: CGImage
  if level<=0 { water=frames[0] }
  else if level>=1 { water=frames[4] }
  else {
    let i=(0..<4).first { level<=levels[$0+1] }!
    let t=Float((level-levels[i])/(levels[i+1]-levels[i]))
    if t<0.001 { water=frames[i] }
    else if t>0.999 { water=frames[i+1] }
    else {
      water=try rife.interpolate(previous:frames[i],current:frames[i+1],timesteps:[t])[0]
      inferenceCount += 1
    }
  }
  return try renderer.render(time:time,water:water)
}

if preview {
  for time in [0.0,4,7,10,14,18,21,24,29] {
    try autoreleasepool {
      try write(compose(time),work.appendingPathComponent(String(format:"preview-%02.0f.png",time)))
      log("Preview \(time)s")
    }
  }
} else {
  let output=work.appendingPathComponent("ninfea-film-\(Int(Date().timeIntervalSince1970)).mp4")
  let movie=try MovieWriter(url:output)
  var previous=try compose(0)
  let samples=Int(duration*15)
  for n in 1...samples {
    try autoreleasepool {
      let current=try compose(Double(n)/15)
      // The master is composed at 15fps. RIFE estimates an actual flow-based
      // in-between for EVERY pair, including the independent botanical growth.
      let mid=try rife.interpolate(previous:previous,current:current)
      inferenceCount += 1
      try movie.append(previous)
      try movie.append(mid)
      previous=current
    }
    if n%15==0 { log("Rendered \(n/15)/30s · \(Int(Date().timeIntervalSince(start)))s elapsed") }
  }
  try movie.finish()
  try write(previous,work.appendingPathComponent("poster-v2.png"))
  let metadata:[String:Any]=["gpu":renderer.device.name,"rife":"4.26 HQ",
    "rife_metal_revision":"1fef4869a44fca32848102b9f6a774a20eb50db6",
    "width":width,"height":height,"fps":fps,"duration":duration,
    "frames":samples*2,"inferences":inferenceCount,"elapsed_seconds":Date().timeIntervalSince(start),
    "output":output.path]
  let data=try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys])
  try data.write(to:work.appendingPathComponent("render.json"))
  log("DONE \(output.path)")
}

extension Array {
  func adding(contentsOf other: [Element]) -> [Element] { self + other }
}
