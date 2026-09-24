local HighlightUI = script.Parent.TutorialManager.HighlightUI
local DialogUI = script.Parent.TutorialManager.TutorialDialogUI

local TutorialTypes = {}

export type Sequence = {
	Name : string,
	CurrentStep : number,
	Connections : { RBXScriptConnection },
	CurrentDialogUI : typeof(DialogUI),
	CurrentHighlightUI : typeof(HighlightUI),
	Segments : { ( ()->(), Sequence ) -> () },
	
	During : () -> ()?,
	Complete : () -> ()?,
}

return TutorialTypes