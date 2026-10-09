class_name CharacterRoster
extends Resource
## Every playable character, in character-select order.

const PATH := "res://resources/characters/character_roster.tres"
## Online co-op squad size.
const MAX_PLAYERS := 4

@export var characters: Array[CharacterDefinition] = []


func find(id: StringName) -> CharacterDefinition:
	for c in characters:
		if c.id == id:
			return c
	return null


static func load_default() -> CharacterRoster:
	return load(PATH) as CharacterRoster
