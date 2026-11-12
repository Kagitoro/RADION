class_name DeckHost
extends Node3D
## A place with a DJ deck and two music channels: the house Party or the Nightclub.
## DJStation works only through this API, so both venues share one controller.

## Physical deck the controller and laptop are mounted on.
var deck := Node3D.new()
## Two deck channels (A and B).
var music: Array[AudioStreamPlayer] = []
var music_bus := -1
var music_gain := 1.0
var fader: Tween
## Index of the channel that plays the built-in playlist.
var playing := 0
## Index into track_titles() of the current built-in track.
var track := 0
var track_time := 0.0

## Built-in playlist titles.
func track_titles() -> Array:
	return []

## Tempo of each built-in track, same order as track_titles().
func track_bpm() -> Array:
	return []

## True when the player stands close enough to use the deck.
func near_deck() -> bool:
	return false

func box(_parent: Node3D, _at: Vector3, _size: Vector3, _tint: Color) -> void:
	push_error("DeckHost.box() must be overridden")

func cylinder(_parent: Node3D, _at: Vector3, _radius: float, _height: float, _tint: Color) -> MeshInstance3D:
	push_error("DeckHost.cylinder() must be overridden")
	return null
