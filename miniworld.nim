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

# GLSL 330 Fragment Shader with Reversed Elevation Tile Assignment
# Highest altitude (h = 1.0) -> Tiles 0 & 1
# Lowest altitude (h = 0.0) -> Tiles 12 & 13
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

// Sample tile from 2048x2048 atlas with 2px inset margin (508px usable out of 512px)
vec4 sampleTile(int tileID, vec2 localUV) {
    int col = tileID % 4;
    int row = tileID / 4;
    
    // Inset 2px from top/left, taking 4px total off width & height
    vec2 insetUV = (vec2(2.0) + localUV * 508.0) / 2048.0;
    vec2 tileOriginUV = vec2(float(col), float(row)) * 0.25;
    vec2 atlasUV = tileOriginUV + insetUV;
    
    return texture(texture0, atlasUV);
}

void main()
{
    // Grid coordinate (0.0 to 256.0) across terrain
    vec2 gridCoord = fragTexCoord * 256.0;

    // Organic noise wobble to smudge hard grid boundaries
    float noiseJitter = (hash(floor(gridCoord)) - 0.5) * 0.08;
    
    // Sample continuous height at this point (0.0 to 1.0)
    float h = clamp(texture(texture1, fragTexCoord).r + noiseJitter, 0.0, 1.0);

    // Continuous elevation index (0.0 at highest altitude, 6.0 at lowest altitude)
    float val = (1.0 - h) * 6.0;
    int pairA = int(floor(val));
    int pairB = min(pairA + 1, 6);
    float fracWeight = fract(val);

    // Local UV inside tile (0.0 to 1.0)
    vec2 tileUV = fract(gridCoord);

    // Spatial hash for picking between pair of tiles
    ivec2 cellPos = ivec2(floor(gridCoord));
    int offset = int(hash(vec2(cellPos)) * 2.0);

    // Reversed Tile Mapping:
    // Highest altitude (pairA = 0) -> Tiles 0 & 1
    // Lowest altitude (pairA = 6) -> Tiles 12 & 13
    int tileA = pairA * 2 + offset;
    int tileB = pairB * 2 + offset;

    vec4 colorA = sampleTile(tileA, tileUV);
    vec4 colorB = sampleTile(tileB, tileUV);

    // Smooth S-curve blend between neighboring tiles
    float blend = smoothstep(0.15, 0.95, fracWeight);
    vec4 texColor = mix(colorA, colorB, blend);

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

initWindow(1200, 800, "Nim Mini World - Vehicle Drive & Terrain Elevation")
setTargetFPS(60)

# Load heightmap image
let heightmapImg = loadImage("assets/heights01.png")

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
let vehicleScale = Vector3(x: 5.0, y: 5.0, z: 5.0)

# Vehicle State
var vehiclePos = Vector3(x: 0.0, y: 0.0, z: 0.0)
var vehicleYaw: float32 = 0.0 # Yaw angle in degrees
var vehicleSpeed: float32 = 0.0

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
  let fwd = Vector3(x: sin(yawRad), y: 0.0, z: cos(yawRad))

  vehiclePos.x += fwd.x * vehicleSpeed * dt
  vehiclePos.z += fwd.z * vehicleSpeed * dt

  # Clamp vehicle position within terrain bounds
  let margin = 10.0
  let minX = mapPos.x + margin
  let maxX = mapPos.x + mapSize.x - margin
  let minZ = mapPos.z + margin
  let maxZ = mapPos.z + mapSize.z - margin

  vehiclePos.x = clamp(vehiclePos.x, minX, maxX)
  vehiclePos.z = clamp(vehiclePos.z, minZ, maxZ)

  # Update vehicle height to rest on top of heightmap ground
  let groundHeight = getTerrainHeight(heightmapImg, mapPos, mapSize, vehiclePos.x, vehiclePos.z)
  vehiclePos.y = groundHeight

  # Camera Logic
  if useVehicleCam:
    const camDistance = 22.0
    const camHeight = 9.0
    
    # Position camera behind and a little above the vehicle, looking towards it
    camera.position = Vector3(
      x: vehiclePos.x - fwd.x * camDistance,
      y: vehiclePos.y + camHeight,
      z: vehiclePos.z - fwd.z * camDistance
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
  drawModel(Model(mapModel), mapPos, 1.0, White)

  # Draw Vehicle model positioned above heightmap ground (rotated 180° so front faces forward)
  let modelDrawYaw = vehicleYaw + 180.0
  drawModel(Model(vehicleModel), vehiclePos, Vector3(x: 0, y: 1, z: 0), modelDrawYaw, vehicleScale, White)
  
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

closeWindow()

