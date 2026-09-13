import raylib
import std/math

const GridSize = 256

proc `+`(a, b: Vector3): Vector3 = Vector3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
proc `-`(a, b: Vector3): Vector3 = Vector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
proc `*`(v: Vector3, s: float32): Vector3 = Vector3(x: v.x * s, y: v.y * s, z: v.z * s)
proc `/`(v: Vector3, s: float32): Vector3 = Vector3(x: v.x / s, y: v.y / s, z: v.z / s)

proc dot(a, b: Vector3): float32 = a.x * b.x + a.y * b.y + a.z * b.z

proc cross(a, b: Vector3): Vector3 =
  Vector3(
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x
  )

proc length(v: Vector3): float32 = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

proc normalize(v: Vector3): Vector3 =
  let len = v.length
  if len > 0.00001f: v / len else: Vector3(x: 0, y: 1, z: 0)

proc mix(a, b: Vector3, t: float32): Vector3 =
  a * (1.0f - t) + b * t

# Function to sample ground height from heightmap at arbitrary world (X, Z) coordinates
proc getTerrainHeight(img: Image, mapPos: Vector3, mapSize: Vector3, worldX, worldZ: float32): float32 =
  let localX = worldX - mapPos.x
  let localZ = worldZ - mapPos.z
  
  let normX = clamp(localX / mapSize.x, 0.0, 1.0)
  let normZ = clamp(localZ / mapSize.z, 0.0, 1.0)
  
  let imgX = normX * (img.width.float32 - 1.0)
  let imgZ = normZ * (img.height.float32 - 1.0)
  
  let x0 = imgX.int32
  let z0 = imgZ.int32
  let x1 = min(x0 + 1, img.width - 1)
  let z1 = min(z0 + 1, img.height - 1)
  
  let tx = imgX - x0.float32
  let tz = imgZ - z0.float32
  
  let c00 = getImageColor(img, x0, z0).r.float32
  let c10 = getImageColor(img, x1, z0).r.float32
  let c01 = getImageColor(img, x0, z1).r.float32
  let c11 = getImageColor(img, x1, z1).r.float32
  
  let top = c00 * (1.0 - tx) + c10 * tx
  let bottom = c01 * (1.0 - tx) + c11 * tx
  let h = top * (1.0 - tz) + bottom * tz
  
  result = mapPos.y + (h / 255.0) * mapSize.y

proc main() =
  initWindow(1200, 800, "Slope Vehicle Test")
  setTargetFPS(60)

  let heightmapImg = loadImage("assets/heights02.png")
  let mapSize = Vector3(x: GridSize.float32, y: 50.0, z: GridSize.float32)
  var mapMesh = genMeshHeightmap(heightmapImg, mapSize)
  var mapModel = loadModelFromMesh(mapMesh)
  let mapPos = Vector3(x: -GridSize.float32 / 2.0, y: 0.0, z: -GridSize.float32 / 2.0)

  var vehicleModel = loadModel("assets/vehicle-truck.glb")
  let vehicleScale = Vector3(x: 5.0, y: 5.0, z: 5.0)

  # Position vehicle on a slope (e.g. x: 50, z: 50)
  var vehiclePos = Vector3(x: 50.0, y: 0.0, z: 50.0)
  var vehicleYaw: float32 = 45.0
  var currentNormal = Vector3(x: 0.0, y: 1.0, z: 0.0)

  var camera = Camera3D(
    position: Vector3(x: 50, y: 65, z: 85),
    target: Vector3(x: 50, y: 35, z: 50),
    up: Vector3(x: 0, y: 1, z: 0),
    fovy: 45.0,
    projection: Perspective
  )

  for frame in 0..<10:
    let yawRad = vehicleYaw * (PI / 180.0)
    let flatFwd = Vector3(x: sin(yawRad), y: 0.0, z: cos(yawRad))
    let flatRight = Vector3(x: cos(yawRad), y: 0.0, z: -sin(yawRad))

    # Base probe dimensions (half length and half width)
    let halfL = 4.0f
    let halfW = 2.5f

    # Sample 4 base corner positions
    let posFL = vehiclePos + flatFwd * halfL - flatRight * halfW
    let posFR = vehiclePos + flatFwd * halfL + flatRight * halfW
    let posBL = vehiclePos - flatFwd * halfL - flatRight * halfW
    let posBR = vehiclePos - flatFwd * halfL + flatRight * halfW

    let hFL = getTerrainHeight(heightmapImg, mapPos, mapSize, posFL.x, posFL.z)
    let hFR = getTerrainHeight(heightmapImg, mapPos, mapSize, posFR.x, posFR.z)
    let hBL = getTerrainHeight(heightmapImg, mapPos, mapSize, posBL.x, posBL.z)
    let hBR = getTerrainHeight(heightmapImg, mapPos, mapSize, posBR.x, posBR.z)

    # Average height at base
    vehiclePos.y = (hFL + hFR + hBL + hBR) * 0.25f

    # 3D base corner vectors
    let pFL = Vector3(x: posFL.x, y: hFL, z: posFL.z)
    let pFR = Vector3(x: posFR.x, y: hFR, z: posFR.z)
    let pBL = Vector3(x: posBL.x, y: hBL, z: posBL.z)
    let pBR = Vector3(x: posBR.x, y: hBR, z: posBR.z)

    # Ground normal calculation from base triangles
    let n1 = cross(pFL - pBL, pFR - pBL)
    let n2 = cross(pBR - pFR, pBL - pFR)
    let targetNormal = normalize(n1 + n2)

    currentNormal = normalize(mix(currentNormal, targetNormal, 0.5f))

    # Build orientation basis
    let upVec = currentNormal
    let fwdProj = flatFwd - upVec * dot(flatFwd, upVec)
    let vFwd = normalize(fwdProj)
    let vRight = normalize(cross(upVec, vFwd))

    # Truck GLB model matrix (model faces -Z)
    let mRight = vRight * -1.0f
    let mFwd = vFwd * -1.0f

    Model(vehicleModel).transform = Matrix(
      m0: mRight.x, m4: upVec.x, m8: mFwd.x, m12: 0.0,
      m1: mRight.y, m5: upVec.y, m9: mFwd.y, m13: 0.0,
      m2: mRight.z, m6: upVec.z, m10: mFwd.z, m14: 0.0,
      m3: 0.0,      m7: 0.0,     m11: 0.0,    m15: 1.0
    )

    beginDrawing()
    clearBackground(Raywhite)
    beginMode3D(camera)
    drawModel(Model(mapModel), mapPos, 1.0f, Lightgray)
    drawModel(Model(vehicleModel), vehiclePos, 5.0f, White)
    
    # Draw corner probe spheres to visualize base sampling
    drawSphere(pFL, 0.5, Red)
    drawSphere(pFR, 0.5, Green)
    drawSphere(pBL, 0.5, Blue)
    drawSphere(pBR, 0.5, Yellow)
    endMode3D()

    if frame == 5:
      takeScreenshot("slope_test.png")

    endDrawing()

main()
closeWindow()
