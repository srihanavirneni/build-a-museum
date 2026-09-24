local ServerStorage = game:GetService("ServerStorage")

local VisitorNPCTemplate = ServerStorage.Assets.VisitorNPCTemplate
local MuseumAssetsFolder = ServerStorage.Assets.Museums

local VisitorTypes = {}

export type VisitorSpawner = {
	Player : Player,
	PlotModel : typeof(MuseumAssetsFolder.StarterMuseum),
	SpawnPart : BasePart,
	VisitorLimit : number,
	VisitorSpawnRate : number,
	Visitors : { Visitor },
	Connections : {RBXScriptConnection},
	BestItem : string, -- instance id
	ItemLuxuryIndices : { Model }, -- sorted
	Exclusives : { Model },
}
export type Visitor = {
	Id : string,
	VisitorSpawner : VisitorSpawner,
	NPCModel : typeof(VisitorNPCTemplate),
	Connections : { RBXScriptConnection },
	LookedTargets : { Model },
	FocusingObjectValue : ObjectValue,
	
	LuxuryPreference : number,
	AttentionSpan : number,
	ViewCount : number,
	
	ShouldDestroy : boolean,
	DestroyTask : thread,
	Task : thread,
	
	IsTalking : boolean?,
	Destroying : boolean?,
}

return VisitorTypes