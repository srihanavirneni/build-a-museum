local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ButtonPadService = require(ServerScriptService.Server.Modules.Utils.ButtonPadService)
local VisitorTypes = require(ServerScriptService.Server.Modules.Visitors.VisitorTypes)

local MuseumAssetTemplate = ServerStorage.Assets.Museums.StarterMuseum
local PlotIndicatorUI = ReplicatedStorage.UI.BillboardGUI.PlotIndicatorUI
local PlotDisplayUI = ReplicatedStorage.UI.SurfaceGUI.PlotDisplayUI
local VisitorStatusUI = ReplicatedStorage.UI.SurfaceGUI.VisitorStatusUI
local BoxAreaDisplayUI = ReplicatedStorage.UI.SurfaceGUI.BoxAreaDisplayUI

local PlotTypes = {}

export type Order = {
	Player : Player,
	BoxId : number,
	BoxInstanceId : string,
	MaxDeliveryTime : number,
	DeliveryTimeLeft : number,
	Connections : { RBXScriptConnection },
	SkipTimePrompt : ProximityPrompt,
	Delivered : boolean,
	OrderModel : Model
}

type ConveyorBox = {
	InstanceId : string,
	BoxName : string,
	ExpirationTime : number
}
export type BoxSpawner = {
	Plot : Plot,
	Owner : Player,
	Model : typeof(MuseumAssetTemplate),
	Connections : { RBXScriptConnection },
	CurrentBoxes : { ConveyorBox },
	CurrentOrders : { Order },
	BoxLimit : number,
	BoxAreaDisplayUI : typeof(BoxAreaDisplayUI),
	ConveyorLuck : number,
}

export type Plot = {
	Index : number,
	Model : typeof(MuseumAssetTemplate),
	Owner : Player?,
	
	VisitorSpawner : VisitorTypes.VisitorSpawner,
	BoxSpawner : BoxSpawner,

	LikeDebounce : boolean,
	LikePrompt : ProximityPrompt,
	DisplayUI : typeof(PlotDisplayUI),
	VisitorStatusUI : typeof(VisitorStatusUI),
	PlotIndicatorUI : typeof(PlotIndicatorUI),
	
	CollectAllPad : ButtonPadService.ButtonPad,
	
	TierSpawnsFolder : Folder,
	Tier : number,
}

return PlotTypes
