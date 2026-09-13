import raylib

var v1 = Vector3(x: 1, y: 0, z: 0)
var v2 = Vector3(x: 0, y: 1, z: 0)

echo "v1 + v2: ", v1 + v2
echo "v1 - v2: ", v1 - v2
echo "v1 * 2.0: ", v1 * 2.0
echo "cross: ", cross(v1, v2)
echo "dot: ", dot(v1, v2)
echo "normalize: ", normalize(v1)
echo "length: ", length(v1)
