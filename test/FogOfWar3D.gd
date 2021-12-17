extends Area
class_name Foobar

# this is my
# multilined docstring
# docstring!

const BELOW_GROUND = -3
# const CAMERA_DISTANCE = 30
var vertices: PoolVector3Array
const DEBUG = false

export(float, 7, 500) var max_triangle_size = 150
export var material: Material


var geometry: ImmediateGeometry
var dirty: bool = true  # to force first rendering

func outer_func():
	pass


class TriangulatedPolygon:


	# Polygon that has been divided into triangles.

	func _init(z: float, indices: PoolIntArray, vertices: PoolVector2Array):
		self.z = z
		print(self.z)
		self.indices = indices
		self.vertices = vertices

	func chop_triangle(ii1: int, ii2: int, ii3: int) -> void:
		# Divides a triangle into two smaller triangles.
		# The original triangle is divided along the longest side
		# to make the new triangles are as equilateral as possible.
		# The parameters ii1, ii2, and ii3 are the indices within
		# self.indices, the values of which in turn act as indices for self.vertices.
		# Chopping a triangle appends two new indices to self.indices
		# and one new vertex to self.vertices.
		var vertices_size = self.vertices.size()  # for assertion
		var indices_size = self.indices.size()  # for assertion
		var i1: int = self.indices[ii1]
		var i2: int = self.indices[ii2]
		var i3: int = self.indices[ii3]
		var v1: Vector2 = self.vertices[i1]
		var v2: Vector2 = self.vertices[i2]
		var v3: Vector2 = self.vertices[i3]
		var s1: float = v1.distance_to(v2)
		var s2: float = v2.distance_to(v3)
		var s3: float = v3.distance_to(v1)
		# look for the longest side of the triangle to divide it at.
		# this ensures more or less evenly sized triangles, instead of
		# very long, very flat triangles where it looks very weird when
		# one vertex from the long side is removed.
		# This can be achieved by rotating the indices of the vertices around,
		# which adds at most one level of recursion.
		if s3 >= s1 and s3 >= s2:
			chop_triangle(ii3, ii1, ii2)
		elif s2 >= s1 and s2 >= s3:
			chop_triangle(ii2, ii3, ii1)
		else:
			# s1 (between v1 and v2) is longest side
			var halfway = v1 + (v2 - v1) * 0.5
			# assert(Geometry.is_point_in_polygon(halfway, self.vertices))
			self.vertices.append(halfway)
			# assert new poly does not exist yet
			var i4 = self.vertices.size() - 1
			self.indices[ii2] = i4  # move one of the vertex indices to point to the new vertex
			self.indices.append(i2)
			self.indices.append(i3)
			self.indices.append(i4)
		assert(self.vertices.size() == vertices_size + 1)
		assert(self.indices.size() == indices_size + 3)

	var z: float
	var indices: PoolIntArray
	var vertices: PoolVector2Array

	func chop(max_triangle_area: float):
		# Chops all triangles up into smaller triangles that have at most max_size area.
		# FIXME: this can actually run in O(n) when directly re-checking the triangles we have just created instead of reiterating the whole array
		var repeat: bool = true
		while repeat:
			repeat = false
			var i = 0
			while i < self.indices.size():
				var i1 = self.indices[i]
				var i2 = self.indices[i + 1]
				var i3 = self.indices[i + 2]
				if (
					TriangulatedPolygon.triangle_area(
						self.vertices[i1], self.vertices[i2], self.vertices[i3]
					)
					> max_triangle_area
				):
					self.chop_triangle(i, i + 1, i + 2)
					repeat = true
				i += 3

	func to_polygon3d(camera: Camera) -> PoolVector3Array:
		# Projects the triangulated polygon2d into 3d space.
		var vertices_3d = PoolVector3Array()
		for i in self.indices:
			#camera.transform.y
			vertices_3d.append(
				camera.project_position(self.vertices[i], camera.transform.origin.y - self.z)
			)  # FIXME: constant

		return vertices_3d

	func to_coloured_triangles(camera: Camera) -> Array:  # if ImmediateGeometry
		# Debug only! Causes heavy frame drop.
		var triangles = []
		var i = 0
		var z = camera.transform.origin.y - self.z
		while i < indices.size() - 3:
			var g = ImmediateGeometry.new()
			var material: SpatialMaterial = SpatialMaterial.new()
			material.albedo_color = TriangulatedPolygon.get_random_colour()
			g.material_override = material
			g.begin(Mesh.PRIMITIVE_TRIANGLES)
			g.add_vertex(camera.project_position(self.vertices[self.indices[i]], z * 1.2))
			g.add_vertex(camera.project_position(self.vertices[self.indices[i + 1]], z * 1.2))
			g.add_vertex(camera.project_position(self.vertices[self.indices[i + 2]], z * 1.2))
			g.end()
			triangles.append(g)
			i += 3
		return triangles

	static func get_random_colour() -> Color:
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		return Color(rng.randf(), rng.randf(), rng.randf(), 0.7)

	static func triangle_area(v1: Vector2, v2: Vector2, v3: Vector2) -> float:
		# Calculates the area of a triangle.
		# https://www.cuemath.com/geometry/area-of-triangle-in-coordinate-geometry/
		return 0.5 * abs(v1.x * (v2.y - v3.y) + v2.x * (v3.y - v1.y) + v3.x * (v1.y - v2.y))

	static func from_polygon2d(z: float, polygon2d: PoolVector2Array, max_triangle_area: float) -> TriangulatedPolygon:
		# Creates a triangulated and chopped version of the passed polygon2d, where each
		# triangle has an area of at most max_triangle_area.
		var triangle_indices = Geometry.triangulate_polygon(polygon2d)
		if triangle_indices.size() == 0:
			pass  # FIXME: check for empty triangulation array coming from Geometry.triangulate_polygon
		var tp: TriangulatedPolygon = TriangulatedPolygon.new(z, triangle_indices, polygon2d)
		assert(tp.indices.size() % 3 == 0)
		tp.chop(max_triangle_area)
		assert(tp.indices.size() % 3 == 0)  # still!
		return tp


func polygon2d_to_fog(camera: Camera, polygon2d: PoolVector2Array) -> PoolVector3Array:
	# Initial conversion of the 2D polygon to 3D vertices.
	print(self.transform.origin)
	var tp = TriangulatedPolygon.from_polygon2d(
		self.transform.origin.y, polygon2d, self.max_triangle_size
	)
	if DEBUG:
		for t in tp.to_coloured_triangles(camera):
			add_child(t)
	self.vertices = tp.to_polygon3d(camera)
	return self.vertices


func uncover(camera: Camera, polygon: PoolVector2Array) -> void:
	# FIXME: use index structure to point to vertices in 2d space
	for i in range(self.vertices.size()):
		var u = camera.unproject_position(self.vertices[i])
		if Geometry.is_point_in_polygon(u, polygon):
			self.vertices[i].y = BELOW_GROUND
			self.dirty = true


func update_geometry() -> void:
	# Updates the fog from the geometry.
	if self.dirty:
		self.geometry.clear()
		self.geometry.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in self.vertices:
			self.geometry.add_vertex(v)

		self.geometry.end()
		self.dirty = false


func _ready():
	self.geometry = ImmediateGeometry.new()
	self.geometry.material_override = self.material
	var polygon = $Polygon2D.polygon
	var camera = get_viewport().get_camera()  # $"../ViewportContainer/Viewport/Camera"
	self.polygon2d_to_fog(camera, polygon)
	add_child(self.geometry)


func _process(_delta):
	# pass
	# FIXME: only update every unth milliseconds
	update_geometry2()