import AppKit
// Optical simplification of the approved wing's outer contour; coordinates run top-down.
let path = CGMutablePath()
path.move(to: CGPoint(x:3,y:5))
path.addCurve(to:CGPoint(x:15.7,y:15.4),control1:CGPoint(x:8.5,y:5.5),control2:CGPoint(x:12.4,y:8.8))
path.addCurve(to:CGPoint(x:29,y:9.6),control1:CGPoint(x:20.5,y:9.5),control2:CGPoint(x:25,y:8.6))
path.addCurve(to:CGPoint(x:22.2,y:20.2),control1:CGPoint(x:27,y:11.4),control2:CGPoint(x:24.5,y:17.2))
path.addCurve(to:CGPoint(x:13,y:27),control1:CGPoint(x:20.4,y:22.6),control2:CGPoint(x:16.3,y:25.2))
path.addCurve(to:CGPoint(x:10.9,y:19.5),control1:CGPoint(x:13.4,y:23.9),control2:CGPoint(x:12.5,y:21.6))
path.addCurve(to:CGPoint(x:3,y:5),control1:CGPoint(x:6.6,y:14.8),control2:CGPoint(x:3.8,y:10.4))
path.closeSubpath()
let out = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
for size in [16,32] {
 var box=CGRect(x:0,y:0,width:size,height:size)
 let context=CGContext(out.appendingPathComponent("VeyWing-\(size).pdf") as CFURL,mediaBox:&box,nil)!
 context.beginPDFPage(nil)
 context.translateBy(x:0,y:CGFloat(size)); context.scaleBy(x:CGFloat(size)/32,y:-CGFloat(size)/32)
 context.addPath(path);context.setFillColor(NSColor.black.cgColor);context.fillPath()
 context.endPDFPage();context.closePDF()
}
let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:800,pixelsHigh:320,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let context=NSGraphicsContext(bitmapImageRep:rep)!.cgContext
for row in 0..<2 {
 context.setFillColor((row==0 ? NSColor.white : NSColor(calibratedWhite:0.09,alpha:1)).cgColor)
 context.fill(CGRect(x:0,y:row*160,width:800,height:160))
 for (i,size) in [16,32,64,96].enumerated() {
  context.saveGState();context.translateBy(x:CGFloat(50+i*180),y:CGFloat(row*160+120))
  context.scaleBy(x:CGFloat(size)/32,y:-CGFloat(size)/32)
  context.addPath(path);context.setFillColor((row==0 ? NSColor.black : NSColor.white).cgColor);context.fillPath();context.restoreGState()
 }
}
try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("template-proof.png"))
