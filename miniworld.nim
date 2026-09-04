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

# GLSL 330 Fragment Shader with Smooth Tile Edge Blending & Organic Noise Jitter
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

vec4 sampleTile(int tileID, vec2 localUV) {
    int col = tileID % 4;
    int row = tileID / 4;
    vec2 atlasUV = (vec2(col, row) + localUV) * 0.25;
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

    // Continuous elevation pair index (0.0 to 6.0)
    float val = (1.0 - h) * 6.0;
    int pairA = int(floor(val));
    int pairB = min(pairA + 1, 6);
    float fracWeight = fract(val);

    // Local UV inside tile (0.0 to 1.0)
    vec2 tileUV = fract(gridCoord);

    // Spatial hash for picking between pair of tiles
    ivec2 cellPos = ivec2(floor(gridCoord));
    int offset = int(hash(vec2(cellPos)) * 2.0);

    int tileA = (6 - pairA) * 2 + offset;
    int tileB = (6 - pairB) * 2 + offset;

    vec4 colorA = sampleTile(tileA, tileUV);
    vec4 colorB = sampleTile(tileB, tileUV);

    // Smooth S-curve blend (smoothstep) between neighboring tiles
    float blend = smoothstep(0.25, 0.75, fracWeight);
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

initWindow(1200, 800, "Nim Mini World - 3D Terrain with Blended Elevation Tiles")
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
# texture1 -> Metalness (heightMapTex)
Model(mapModel).materials[0].shader = shader
Model(mapModel).materials[0].maps[Albedo].texture = tilesetTex
Model(mapModel).materials[0].maps[Metalness].texture = heightMapTex

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
  # Draw 3D floor terrain model with blended tile shader
  drawModel(Model(mapModel), mapPos, 1.0, White)
  
  # Draw visual sun sphere in sky
  drawSphere(sunPos, 8.0, Yellow)
  
  drawGrid(20, 10.0)
  endMode3D()

  drawFPS(10, 10)
  drawText("Free Camera: WASD + Q/E + Mouse | Blended Tile Edges Active", 10, 35, 20, Darkgray)
  endDrawing()

closeWindow()
