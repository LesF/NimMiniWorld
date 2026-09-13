import raylib
import std/math

const GridSize = 256

# GLSL 330 Vertex Shader
const VertexShader = """
#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;

out vec3 fragPosition;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;

void main()
{
    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));

    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
"""

# GLSL 330 Fragment Shader with Reversed Elevation Tile Assignment & Neighbor Tile Blending
const FragmentShader = """
#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

out vec4 finalColor;

uniform sampler2D texture0;    // tileset01.png (2048x2048 atlas)
uniform sampler2D texture1;    // 256x256 normalized heightmap texture
uniform vec4 colDiffuse;
uniform vec3 lightDir;
uniform vec4 lightColor;
uniform vec4 ambientLight;
uniform vec3 viewPos;

// Pseudo-random noise for organic edge smudging/jitter
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Sample tile from 2048x2048 atlas using explicit screen-space gradients to avoid derivative seam artifacts
vec4 sampleTile(int tileID, vec2 localUV, vec2 uvGradX, vec2 uvGradY) {
    int col = tileID % 4;
    int row = tileID / 4;
    
    // Inset 2px from top/left, taking 4px total off width & height
    vec2 insetUV = (vec2(2.0) + localUV * 508.0) / 2048.0;
    vec2 tileOriginUV = vec2(float(col), float(row)) * 0.25;
    vec2 atlasUV = tileOriginUV + insetUV;
    
    return textureGrad(texture0, atlasUV, uvGradX, uvGradY);
}

// Evaluates the blended elevation tile color for a specific grid cell
vec4 getCellColor(ivec2 cell, vec2 tileUV, vec2 uvGradX, vec2 uvGradY) {
    // Sample height at cell center
    vec2 cellTexCoord = (vec2(cell) + vec2(0.5)) / 256.0;
    
    // Organic noise wobble per cell
    float noiseJitter = (hash(vec2(cell)) - 0.5) * 0.08;
    
    float h = clamp(texture(texture1, cellTexCoord).r + noiseJitter, 0.0, 1.0);

    float val = (1.0 - h) * 6.0;
    int pairA = int(floor(val));
    int pairB = min(pairA + 1, 6);
    float fracWeight = fract(val);

    int offset = int(hash(vec2(cell)) * 2.0);

    int tileA = pairA * 2 + offset;
    int tileB = pairB * 2 + offset;

    vec4 colorA = sampleTile(tileA, tileUV, uvGradX, uvGradY);
    vec4 colorB = sampleTile(tileB, tileUV, uvGradX, uvGradY);

    float blend = smoothstep(0.15, 0.95, fracWeight);
    return mix(colorA, colorB, blend);
}

void main()
{
    // Grid coordinate (0.0 to 256.0) across terrain
    vec2 gridCoord = fragTexCoord * 256.0;
    vec2 tileUV = fract(gridCoord);

    // Explicit gradients for texture sampling to eliminate mipmap seam artifacts across tile boundaries
    vec2 uvGradX = dFdx(fragTexCoord * 63.5);
    vec2 uvGradY = dFdy(fragTexCoord * 63.5);

    // 4-corner bilinear neighbor blending across grid cells
    vec2 p = gridCoord - vec2(0.5);
    ivec2 ipos = ivec2(floor(p));
    vec2 f = fract(p);
    vec2 w = smoothstep(0.0, 1.0, f);

    vec4 c00 = getCellColor(ipos + ivec2(0, 0), tileUV, uvGradX, uvGradY);
    vec4 c10 = getCellColor(ipos + ivec2(1, 0), tileUV, uvGradX, uvGradY);
    vec4 c01 = getCellColor(ipos + ivec2(0, 1), tileUV, uvGradX, uvGradY);
    vec4 c11 = getCellColor(ipos + ivec2(1, 1), tileUV, uvGradX, uvGradY);

    vec4 c0 = mix(c00, c10, w.x);
    vec4 c1 = mix(c01, c11, w.x);
    vec4 texColor = mix(c0, c1, w.y);

    // Lighting calculation
    vec3 normal = normalize(fragNormal);
    vec3 lightVec = normalize(lightDir);

    float diff = max(dot(normal, lightVec), 0.0);
    vec3 diffuse = diff * lightColor.rgb;

    vec3 viewDir = normalize(viewPos - fragPosition);
    vec3 halfDir = normalize(lightVec + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 16.0);
    vec3 specular = spec * lightColor.rgb * 0.25;

    vec3 lightSum = ambientLight.rgb + diffuse + specular;
    finalColor = vec4(texColor.rgb * colDiffuse.rgb * lightSum, texColor.a * colDiffuse.a);
}
"""

# Vector3 Math Helpers for 3D Surface Normal & Basis Calculations
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
  initWindow(1200, 800, "Nim Mini World - Vehicle Drive & Terrain Elevation")
  setTargetFPS(60)

  # Load heightmap image
  let heightmapImg = loadImage("assets/heights02.png")

  # Create GPU heightmap texture (texture1) with Bilinear filtering for smooth transitions
  var heightMapTex = loadTextureFromImage(heightmapImg)
  setTextureFilter(heightMapTex, Bilinear)

  # Load 4x4 tileset texture atlas (texture0)
  var tilesetTex = loadTexture("assets/tileset01.png")
  genTextureMipmaps(tilesetTex)
  setTextureFilter(tilesetTex, Trilinear)

  # Generate 3D heightmap mesh and load as a Model
  let mapSize = Vector3(x: GridSize.float32, y: 50.0, z: GridSize.float32)
  var mapMesh = genMeshHeightmap(heightmapImg, mapSize)
  var mapModel = loadModelFromMesh(mapMesh)

  # Center map around world (0, 0, 0)
  let mapPos = Vector3(x: -GridSize.float32 / 2.0, y: 0.0, z: -GridSize.float32 / 2.0)

  # Load Vehicle Model
  var vehicleModel = loadModel("assets/vehicle-truck.glb")

  # Vehicle State
  var vehiclePos = Vector3(x: 0.0, y: 0.0, z: 0.0)
  var vehicleYaw: float32 = 0.0 # Yaw angle in degrees
  var vehicleSpeed: float32 = 0.0
  var currentNormal = Vector3(x: 0.0, y: 1.0, z: 0.0) # Vehicle surface orientation normal

  const MaxForwardSpeed = 30.0
  const MaxReverseSpeed = -15.0
  const Acceleration = 40.0
  const Friction = 25.0
  const TurnSpeed = 130.0 # degrees per second

  # Initial position on terrain height
  vehiclePos.y = getTerrainHeight(heightmapImg, mapPos, mapSize, vehiclePos.x, vehiclePos.z)

  # Load Shader
  let shader = loadShaderFromMemory(VertexShader, FragmentShader)

  # Get uniform locations
  let locLightDir = getShaderLocation(shader, "lightDir")
  let locLightColor = getShaderLocation(shader, "lightColor")
  let locAmbient = getShaderLocation(shader, "ambientLight")
  let locViewPos = getShaderLocation(shader, "viewPos")

  # Set Sun light properties
  var sunDirection = Vector3(x: 0.5, y: 1.0, z: 0.3)
  var sunColor = Vector4(x: 1.0, y: 0.95, z: 0.8, w: 1.0)
  var ambientColor = Vector4(x: 0.25, y: 0.25, z: 0.35, w: 1.0)

  setShaderValue(shader, locLightDir, sunDirection)
  setShaderValue(shader, locLightColor, sunColor)
  setShaderValue(shader, locAmbient, ambientColor)

  # Attach shader & textures to map model material
  Model(mapModel).materials[0].shader = shader
  Model(mapModel).materials[0].maps[Albedo].texture = tilesetTex
  Model(mapModel).materials[0].maps[Metalness].texture = heightMapTex

  # Position sun indicator in sky
  let sunPos = Vector3(x: 120.0, y: 240.0, z: 70.0)

  var camera = Camera3D(
    position: Vector3(x: 0, y: 20, z: 30),
    target: Vector3(x: 0, y: 0, z: 0),
    up: Vector3(x: 0, y: 1, z: 0),
    fovy: 45.0,
    projection: Perspective
  )

  var useVehicleCam = true

  disableCursor()

  while not windowShouldClose():
    let dt = getFrameTime()

    # Toggle camera mode with 'C' key
    if isKeyPressed(C):
      useVehicleCam = not useVehicleCam
      if not useVehicleCam:
        enableCursor()
      else:
        disableCursor()

    # Keyboard Controls for Vehicle
    var accelerating = false

    if isKeyDown(W) or isKeyDown(Up):
      accelerating = true
      vehicleSpeed += Acceleration * dt
      if vehicleSpeed > MaxForwardSpeed:
        vehicleSpeed = MaxForwardSpeed

    if isKeyDown(S) or isKeyDown(Down):
      accelerating = true
      vehicleSpeed -= Acceleration * dt
      if vehicleSpeed < MaxReverseSpeed:
        vehicleSpeed = MaxReverseSpeed

    if not accelerating:
      if vehicleSpeed > 0.0:
        vehicleSpeed -= Friction * dt
        if vehicleSpeed < 0.0: vehicleSpeed = 0.0
      elif vehicleSpeed < 0.0:
        vehicleSpeed += Friction * dt
        if vehicleSpeed > 0.0: vehicleSpeed = 0.0

    if isKeyDown(A) or isKeyDown(Left):
      let dir = if vehicleSpeed >= 0.0: 1.0 else: -1.0
      vehicleYaw += TurnSpeed * dt * dir

    if isKeyDown(D) or isKeyDown(Right):
      let dir = if vehicleSpeed >= 0.0: 1.0 else: -1.0
      vehicleYaw -= TurnSpeed * dt * dir

    # Update vehicle movement position
    let yawRad = vehicleYaw * (PI / 180.0)
    let flatFwd = Vector3(x: sin(yawRad), y: 0.0, z: cos(yawRad))
    let flatRight = Vector3(x: cos(yawRad), y: 0.0, z: -sin(yawRad))

    vehiclePos.x += flatFwd.x * vehicleSpeed * dt
    vehiclePos.z += flatFwd.z * vehicleSpeed * dt

    # Clamp vehicle position within terrain bounds
    let margin = 10.0
    let minX = mapPos.x + margin
    let maxX = mapPos.x + mapSize.x - margin
    let minZ = mapPos.z + margin
    let maxZ = mapPos.z + mapSize.z - margin

    vehiclePos.x = clamp(vehiclePos.x, minX, maxX)
    vehiclePos.z = clamp(vehiclePos.z, minZ, maxZ)

    # Base probe dimensions around vehicle chassis
    let halfL = 4.0f
    let halfW = 2.5f

    # Sample 4 base corner probe locations around vehicle footprint
    let posFL = vehiclePos + flatFwd * halfL - flatRight * halfW
    let posFR = vehiclePos + flatFwd * halfL + flatRight * halfW
    let posBL = vehiclePos - flatFwd * halfL - flatRight * halfW
    let posBR = vehiclePos - flatFwd * halfL + flatRight * halfW

    let hFL = getTerrainHeight(heightmapImg, mapPos, mapSize, posFL.x, posFL.z)
    let hFR = getTerrainHeight(heightmapImg, mapPos, mapSize, posFR.x, posFR.z)
    let hBL = getTerrainHeight(heightmapImg, mapPos, mapSize, posBL.x, posBL.z)
    let hBR = getTerrainHeight(heightmapImg, mapPos, mapSize, posBR.x, posBR.z)

    # Average height beneath vehicle base
    vehiclePos.y = (hFL + hFR + hBL + hBR) * 0.25f

    # 3D base corner vectors
    let pFL = Vector3(x: posFL.x, y: hFL, z: posFL.z)
    let pFR = Vector3(x: posFR.x, y: hFR, z: posFR.z)
    let pBL = Vector3(x: posBL.x, y: hBL, z: posBL.z)
    let pBR = Vector3(x: posBR.x, y: hBR, z: posBR.z)

    # Calculate ground surface normal from base corner vectors
    let n1 = cross(pFL - pBL, pFR - pBL)
    let n2 = cross(pBR - pFR, pBL - pFR)
    var targetNormal = normalize(n1 + n2)
    if targetNormal.y < 0.1f: targetNormal = Vector3(x: 0.0, y: 1.0, z: 0.0)

    # Smooth normal transition for vehicle suspension damping
    currentNormal = normalize(mix(currentNormal, targetNormal, min(dt * 12.0f, 1.0f)))

    # Construct vehicle orientation basis
    let upVec = currentNormal
    let fwdProj = flatFwd - upVec * dot(flatFwd, upVec)
    let vFwd = normalize(fwdProj)
    let vRight = normalize(cross(upVec, vFwd))

    # Apply 3D rotation transform matrix to vehicle model (model faces -Z)
    let mRight = vRight * -1.0f
    let mFwd = vFwd * -1.0f

    Model(vehicleModel).transform = Matrix(
      m0: mRight.x, m4: upVec.x, m8: mFwd.x, m12: 0.0,
      m1: mRight.y, m5: upVec.y, m9: mFwd.y, m13: 0.0,
      m2: mRight.z, m6: upVec.z, m10: mFwd.z, m14: 0.0,
      m3: 0.0,      m7: 0.0,     m11: 0.0,    m15: 1.0
    )

    # Camera Logic
    if useVehicleCam:
      const camDistance = 22.0
      const camHeight = 9.0
      
      # Position camera behind and a little above the vehicle, looking towards it
      camera.position = Vector3(
        x: vehiclePos.x - flatFwd.x * camDistance,
        y: vehiclePos.y + camHeight,
        z: vehiclePos.z - flatFwd.z * camDistance
      )
      camera.target = Vector3(
        x: vehiclePos.x,
        y: vehiclePos.y + 2.5,
        z: vehiclePos.z
      )
      camera.up = Vector3(x: 0, y: 1, z: 0)
    else:
      updateCamera(camera, Free)

    # Pass camera view position to shader for specular highlights
    setShaderValue(shader, locViewPos, camera.position)

    beginDrawing()
    clearBackground(Raywhite)
    
    beginMode3D(camera)
    # Draw 3D floor terrain model with blended tile shader
    drawModel(Model(mapModel), mapPos, 1.0f, White)

    # Draw Vehicle model positioned on terrain with base orientation matrix applied
    drawModel(Model(vehicleModel), vehiclePos, 5.0f, White)
    
    # Draw visual sun sphere in sky
    drawSphere(sunPos, 8.0, Yellow)
    
    drawGrid(20, 10.0)
    endMode3D()

    drawFPS(10, 10)
    
    if useVehicleCam:
      drawText("Vehicle Controls: W/S (Forward/Reverse) | A/D (Steer Left/Right)", 10, 35, 20, Darkgray)
      drawText("Camera pinned behind vehicle. Press 'C' to toggle Free Camera", 10, 60, 18, Maroon)
    else:
      drawText("Free Camera Active: WASD + Mouse | Press 'C' to pin camera to Vehicle", 10, 35, 20, Darkgray)

    drawText("Vehicle Pos: (" & $vehiclePos.x.int & ", " & $vehiclePos.y.int & ", " & $vehiclePos.z.int & ") | Yaw: " & $vehicleYaw.int & " deg", 10, 85, 18, Darkgray)
    
    if isKeyPressed(P):
      takeScreenshot("vehicle_preview.png")

    endDrawing()

main()
closeWindow()

