extends RefCounted
class_name GameMode

enum Value { BOOT, EXPLORATION, DIALOGUE, CUTSCENE, MENU, TRANSITION, PAUSED }

const ACTION_MOVE := &"move"
const ACTION_SPRINT := &"sprint"
const ACTION_INTERACT := &"interact"
const ACTION_DIALOGUE_ADVANCE := &"dialogue_advance"
const ACTION_DIALOGUE_CHOOSE := &"dialogue_choose"
const ACTION_MENU := &"menu"
