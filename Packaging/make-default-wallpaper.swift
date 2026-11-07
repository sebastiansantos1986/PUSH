// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import AppKit
let width=2560,height=1440
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let rect=NSRect(x:0,y:0,width:width,height:height)
NSGradient(starting:NSColor(red:0.025,green:0.045,blue:0.10,alpha:1),ending:NSColor(red:0.06,green:0.15,blue:0.27,alpha:1))!.draw(in:rect,angle:20)
NSColor(red:0.12,green:0.42,blue:0.68,alpha:0.18).setFill();NSBezierPath(ovalIn:NSRect(x:1100,y:-780,width:2100,height:2100)).fill()
NSColor.white.withAlphaComponent(0.04).setStroke()
for x in stride(from:0,to:width,by:160){let p=NSBezierPath();p.move(to:NSPoint(x:x,y:0));p.line(to:NSPoint(x:x,y:height));p.lineWidth=1;p.stroke()}
for y in stride(from:0,to:height,by:160){let p=NSBezierPath();p.move(to:NSPoint(x:0,y:y));p.line(to:NSPoint(x:width,y:y));p.lineWidth=1;p.stroke()}
func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight,_ color:NSColor){(value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color])}
NSColor(red:0.20,green:0.65,blue:0.95,alpha:0.18).setFill();NSBezierPath(roundedRect:NSRect(x:1240,y:1010,width:650,height:68),xRadius:34,yRadius:34).fill()
text("PUSH  /  SOFTWARE UPDATE",1275,1026,26,.semibold,NSColor(red:0.45,green:0.80,blue:1,alpha:1))
text("Your Mac needs",1240,838,88,.bold,.white)
text("an update.",1240,730,88,.bold,.white)
text("Save your work and follow the PUSH reminder.",1245,624,32,.regular,.white.withAlphaComponent(0.72))
text("Keeping your Mac current helps keep your work secure.",1245,568,27,.regular,.white.withAlphaComponent(0.48))
NSColor(red:0.24,green:0.68,blue:1,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:1245,y:499,width:90,height:6),xRadius:3,yRadius:3).fill()
text("PUSH",1245,132,24,.bold,.white.withAlphaComponent(0.45))
NSGraphicsContext.restoreGraphicsState()
let data=bitmap.representation(using:.png,properties:[:])!
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
