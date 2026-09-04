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

# GLSL 330 Fragment Shader with Sun Directional Light, Ambient, & Specular Highlights
const FragmentShader = """
#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

out vec4 finalColor;

uniform vec4 colDiffuse;
uniform vec3 lightDir;
uniform vec4 lightColor;
uniform vec4 ambientLight;
uniform vec3 viewPos;

void main()
{
    vec3 normal = normalize(fragNormal);
    vec3 lightVec = normalize(lightDir);

    // Diffuse shading (Lambertian directional light)
    float diff = max(dot(normal, lightVec), 0.0);
    vec3 diffuse = diff * lightColor.rgb;

    // Specular highlight (Blinn-Phong)
    vec3 viewDir = normalize(viewPos - fragPosition);
    vec3 halfDir = normalize(lightVec + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 16.0);
    vec3 specular = spec * lightColor.rgb * 0.35;

    // Base color from model tint
    vec4 baseColor = colDiffuse * fragColor;

    // Combine ambient, diffuse, and specular highlights
    vec3 lightSum = ambientLight.rgb + diffuse + specular;
    finalColor = vec4(baseColor.rgb * lightSum, baseColor.a);
}
"""

initWindow(1200, 800, "Nim Mini World - 3D Heightmap with Sun Lighting")
setTargetFPS(60)

# Load heightmap image
let heightmapImg = loadImage("assets/heights01.png")

# Store height values in a 256x256 grid array (0 to 255)
var heightGrid: array[GridSize, array[GridSize, float32]]
for z in 0..<GridSize:
  for x in 0..<GridSize:
    let col = getImageColor(heightmapImg, int32(x), int32(z))
    heightGrid[x][z] = float32(col.r)

# Generate 3D heightmap mesh and load as a renderable Model
# Width: 256, Height scale: 50.0, Depth: 256
var mapMesh = genMeshHeightmap(heightmapImg, Vector3(x: GridSize.float32, y: 50.0, z: GridSize.float32))
var mapModel = loadModelFromMesh(mapMesh)

# Center map around world (0, 0, 0)
let mapPos = Vector3(x: -GridSize.float32 / 2.0, y: 0.0, z: -GridSize.float32 / 2.0)

# Load Lighting Shader
let shader = loadShaderFromMemory(VertexShader, FragmentShader)

# Get uniform locations
let locLightDir = getShaderLocation(shader, "lightDir")
let locLightColor = getShaderLocation(shader, "lightColor")
let locAmbient = getShaderLocation(shader, "ambientLight")
let locViewPos = getShaderLocation(shader, "viewPos")

# Set Sun light properties
var sunDirection = Vector3(x: 0.5, y: 1.0, z: 0.3)
var sunColor = Vector4(x: 1.0, y: 0.95, z: 0.8, w: 1.0)       # Warm sunlight
var ambientColor = Vector4(x: 0.25, y: 0.25, z: 0.35, w: 1.0)   # Cool sky ambient shadow fill

setShaderValue(shader, locLightDir, sunDirection)
setShaderValue(shader, locLightColor, sunColor)
setShaderValue(shader, locAmbient, ambientColor)

# Attach shader to map model material
Model(mapModel).materials[0].shader = shader

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
  # Draw 3D floor terrain model with sun light shader
  drawModel(Model(mapModel), mapPos, 1.0, Darkgreen)
  
  # Draw visual sun sphere in sky
  drawSphere(sunPos, 8.0, Yellow)
  
  drawGrid(20, 10.0)
  endMode3D()

  drawFPS(10, 10)
  drawText("Free Camera: WASD + Q/E + Mouse | Sun Lighting Enabled", 10, 35, 20, Darkgray)
  endDrawing()

closeWindow()
