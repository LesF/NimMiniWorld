import raylib

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

# GLSL 330 Fragment Shader
# Raylib automatically binds:
# texture0 -> material.maps[Albedo] (tileset01.png)
# texture1 -> material.maps[Metalness] (tileMapTex)
const FragmentShader = """
#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

out vec4 finalColor;

uniform sampler2D texture0;    // tileset01.png (2048x2048 atlas)
uniform sampler2D texture1;    // 256x256 tile ID map (R channel = tileID)
uniform vec4 colDiffuse;
uniform vec3 lightDir;
uniform vec4 lightColor;
uniform vec4 ambientLight;
uniform vec3 viewPos;

void main()
{
    // Grid coordinate (0.0 to 256.0) across terrain
    vec2 gridCoord = fragTexCoord * 256.0;

    // Local UV inside the tile (0.0 to 1.0)
    vec2 tileUV = fract(gridCoord);

    // Look up tileID from texture1 (fetch R channel scaled by 255)
    ivec2 cellPos = clamp(ivec2(floor(gridCoord)), ivec2(0), ivec2(255));
    int tileID = int(texelFetch(texture1, cellPos, 0).r * 255.0 + 0.5);

    // Calculate atlas UV (4x4 tileset -> 0.25 scale per tile)
    int col = tileID % 4;
    int row = tileID / 4;
    vec2 atlasUV = (vec2(col, row) + tileUV) * 0.25;

    // Sample texture atlas
    vec4 texColor = texture(texture0, atlasUV);

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

# Deterministic hash to pick between pair of tiles (0 or 1 offset)
proc tileHash(x, z: int): int =
  var h = (x.uint32 * 374761393'u32) + (z.uint32 * 668265263'u32)
  h = (h xor (h shr 13)) * 1274126177'u32
  return int(h and 0x7FFFFFFF'u32)

initWindow(1200, 800, "Nim Mini World - 3D Terrain with Elevation Tile Atlas")
setTargetFPS(60)

# Load heightmap image
let heightmapImg = loadImage("assets/heights01.png")

# Store height values and calculate min/max heights
var heightGrid: array[GridSize, array[GridSize, float32]]
var minH = 255.0'f32
var maxH = 0.0'f32

for z in 0..<GridSize:
  for x in 0..<GridSize:
    let h = float32(getImageColor(heightmapImg, int32(x), int32(z)).r)
    heightGrid[x][z] = h
    if h < minH: minH = h
    if h > maxH: maxH = h

let rangeH = if maxH > minH: (maxH - minH) else: 1.0'f32

# Build 256x256 tile map image mapping elevation to 7 tile pairs
var tileMapImg = genImageColor(GridSize.int32, GridSize.int32, Black)
for z in 0..<GridSize:
  for x in 0..<GridSize:
    let h = heightGrid[x][z]
    let normH = clamp((h - minH) / rangeH, 0.0, 1.0)
    
    # Map normalized elevation [0..1] into 7 pairs (0..6)
    # pair 0 (lowest) -> tiles 12 & 13
    # pair 6 (highest) -> tiles 0 & 1
    var pairIdx = int(normH * 7.0)
    if pairIdx > 6: pairIdx = 6
    
    let baseTile = (6 - pairIdx) * 2
    let offset = tileHash(x, z) mod 2
    let tileId = uint8(baseTile + offset)
    
    imageDrawPixel(tileMapImg, x.int32, z.int32, Color(r: tileId, g: 0, b: 0, a: 255))

# Create GPU texture for tile map and set Point filtering (no blur between tile IDs)
var tileMapTex = loadTextureFromImage(tileMapImg)
setTextureFilter(tileMapTex, Point)

# Load 4x4 tileset texture atlas
var tilesetTex = loadTexture("assets/tileset01.png")
genTextureMipmaps(tilesetTex)
setTextureFilter(tilesetTex, Trilinear)

# Generate 3D heightmap mesh and load as a Model
var mapMesh = genMeshHeightmap(heightmapImg, Vector3(x: GridSize.float32, y: 50.0, z: GridSize.float32))
var mapModel = loadModelFromMesh(mapMesh)

# Center map around world (0, 0, 0)
let mapPos = Vector3(x: -GridSize.float32 / 2.0, y: 0.0, z: -GridSize.float32 / 2.0)

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
# texture0 -> Albedo (tilesetTex)
# texture1 -> Metalness (tileMapTex)
Model(mapModel).materials[0].shader = shader
Model(mapModel).materials[0].maps[Albedo].texture = tilesetTex
Model(mapModel).materials[0].maps[Metalness].texture = tileMapTex

# Position sun indicator in sky
let sunPos = Vector3(x: 120.0, y: 240.0, z: 70.0)

var camera = Camera3D(
  position: Vector3(x: 0, y: 90, z: 170),
  target: Vector3(x: 0, y: 0, z: 0),
  up: Vector3(x: 0, y: 1, z: 0),
  fovy: 45.0,
  projection: Perspective
)

disableCursor()

while not windowShouldClose():
  updateCamera(camera, Free)

  # Pass camera view position to shader for specular highlights
  setShaderValue(shader, locViewPos, camera.position)

  beginDrawing()
  clearBackground(Raywhite)
  
  beginMode3D(camera)
  # Draw 3D floor terrain model with elevation tile map shader
  drawModel(Model(mapModel), mapPos, 1.0, White)
  
  # Draw visual sun sphere in sky
  drawSphere(sunPos, 8.0, Yellow)
  
  drawGrid(20, 10.0)
  endMode3D()

  drawFPS(10, 10)
  drawText("Free Camera: WASD + Q/E + Mouse | Elevation Tile Atlas Active", 10, 35, 20, Darkgray)
  endDrawing()

closeWindow()
