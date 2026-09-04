import raylib, std/strformat

initWindow(100, 100, "Test")
let img = loadImage("assets/heights01.png")
echo fmt"Image format: {img.format}, width: {img.width}, height: {img.height}"
var minH = 255.0'f32
var maxH = 0.0'f32
for z in 0..<256:
  for x in 0..<256:
    let col = getImageColor(img, int32(x), int32(z))
    let h = float32(col.r)
    if h < minH: minH = h
    if h > maxH: maxH = h
echo fmt"minH: {minH}, maxH: {maxH}"
closeWindow()
