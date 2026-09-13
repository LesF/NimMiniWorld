import raylib

proc makeOrientationMatrix(right, up, fwd: Vector3): Matrix =
  # Matrix columns: X axis = right, Y axis = up, Z axis = fwd
  result = Matrix(
    m0: right.x, m4: up.x, m8: fwd.x, m12: 0.0,
    m1: right.y, m5: up.y, m9: fwd.y, m13: 0.0,
    m2: right.z, m6: up.z, m10: fwd.z, m14: 0.0,
    m3: 0.0,     m7: 0.0,  m11: 0.0,   m15: 1.0
  )

proc main() =
  initWindow(100, 100, "Test Orient Matrix")
  var m = makeOrientationMatrix(Vector3(x: 1, y: 0, z: 0), Vector3(x: 0, y: 1, z: 0), Vector3(x: 0, y: 0, z: 1))
  echo "Orientation Matrix: ", m

main()
closeWindow()
