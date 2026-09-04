import raylib

initWindow(100, 100, "Test Shader Map")
let img = loadImage("assets/heights01.png")
var tileMapImg = genImageColor(256, 256, Black)

for z in 0..<256:
  for x in 0..<256:
    let h = float32(getImageColor(img, int32(x), int32(z)).r)
    let normH = clamp((h - 13.0) / (255.0 - 13.0), 0.0, 1.0)
    var pairIdx = int(normH * 7.0)
    if pairIdx > 6: pairIdx = 6
    let baseTile = (6 - pairIdx) * 2
    let tileId = uint8(baseTile)
    imageDrawPixel(tileMapImg, x.int32, z.int32, Color(r: tileId, g: 0, b: 0, a: 255))

# Check some pixel values in tileMapImg:
for i in 0..<5:
  let c = getImageColor(tileMapImg, int32(i*50), int32(i*50))
  echo "Sample pixel (", i*50, ",", i*50, "): tileID = ", c.r

closeWindow()
