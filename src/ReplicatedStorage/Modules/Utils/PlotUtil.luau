local PlotUtil = {}
PlotUtil.GRID_SIZE = 4

function PlotUtil.IsGridAligned(buildRegion : Model, pos : Vector3, rot : number, sizeX : number, sizeZ : number)
	sizeX = sizeX or 1
	sizeZ = sizeZ or 1
	rot = rot or 0
	local grid = PlotUtil.GRID_SIZE
	
	local rotatedX, rotatedZ = sizeX, sizeZ
	if rot % 180 ~= 0 then
		rotatedX, rotatedZ = sizeZ, sizeX
	end

	local anchorPos = buildRegion.AlignmentAnchor.Position
	
	local offsetX = (rotatedX % 2 == 0) and (grid / 2) or 0
	local offsetZ = (rotatedZ % 2 == 0) and (grid / 2) or 0
	
	local localX = pos.X - anchorPos.X - offsetX
	local localZ = pos.Z - anchorPos.Z - offsetZ
	
	local alignedX = math.abs(localX / grid - math.round(localX / grid)) < 1e-4
	local alignedZ = math.abs(localZ / grid - math.round(localZ / grid)) < 1e-4

	return alignedX and alignedZ
end

function PlotUtil.SnapToGrid(buildRegion : Model, pos : Vector3, rot : number, sizeX : number, sizeZ : number)
	rot = rot or 0
	sizeX = sizeX or 1
	sizeZ = sizeZ or 1
	
	if rot % 180 ~= 0 then
		local temp = sizeZ
		sizeZ = sizeX
		sizeX = temp
	end
	
	local alignmentAnchorPart = buildRegion.AlignmentAnchor
	local anchorPos = alignmentAnchorPart.Position
	
	local offsetX = (sizeX % 2 == 0) and (PlotUtil.GRID_SIZE / 2) or 0
	local offsetZ = (sizeZ % 2 == 0) and (PlotUtil.GRID_SIZE / 2) or 0
	
	local diff = pos - anchorPos
	
	return Vector3.new(
		math.round((diff.X) / PlotUtil.GRID_SIZE) * PlotUtil.GRID_SIZE + anchorPos.X + offsetX,
		pos.Y,
		math.round((diff.Z) / PlotUtil.GRID_SIZE) * PlotUtil.GRID_SIZE + anchorPos.Z + offsetZ
	)
end

function PlotUtil.WithinBounds(buildRegion : Model, objectSize : Vector3, worldCF : CFrame)
	local regionCF, regionSize = buildRegion:GetBoundingBox()
	local objectCF = regionCF:ToObjectSpace(worldCF)

	local cornerPoints = {}
	for _, x in {-1, 1} do
		for _, z in {-1, 1} do
			table.insert(cornerPoints, objectCF:PointToWorldSpace(
				Vector3.new(x * objectSize.X / 2, 0, z * objectSize.Z / 2)
				))
		end
	end

	for _, corner in pairs(cornerPoints) do
		if math.abs(corner.X) > regionSize.X / 2 or math.abs(corner.Z) > regionSize.Z / 2 then
			return false
		end
	end

	local topBoundY = buildRegion.PrimaryPart.Position.Y + regionSize.Y + 25
	local bottomBoundY = buildRegion.PrimaryPart.Position.Y - buildRegion.PrimaryPart.Size.Y/2 - 10
	if worldCF.Position.Y >= topBoundY or worldCF.Position.Y <= bottomBoundY then
		return false
	end

	return true
end

function PlotUtil.NotIntersectingObjects(buildRegion: Model, objectsFolder: Folder, interiorFolder : Folder, objectSize: Vector3, worldCF: CFrame)
	local objectCF = buildRegion:GetPivot():ToObjectSpace(worldCF)
	local objectBoundingBoxes = {}
	
	for _, object in objectsFolder:GetChildren() do
		local boundingBoxPart : BasePart = object:FindFirstChild("BoundingBox")
		if boundingBoxPart then
			table.insert(objectBoundingBoxes, boundingBoxPart)
		end
	end

	local params = OverlapParams.new()
	params:AddToFilter(objectBoundingBoxes)
	params:AddToFilter(interiorFolder)
	params.FilterType = Enum.RaycastFilterType.Include

	local parts = workspace:GetPartBoundsInBox(worldCF, objectSize, params)

	return #parts == 0
end

return PlotUtil