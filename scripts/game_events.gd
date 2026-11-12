extends Node
## Global signal bus (autoload "GameEvents").
## Systems announce things here instead of reaching into the HUD directly.

## A short status message for the player (shown by the HUD).
signal notice_requested(text: String)

func notify(text: String) -> void:
	notice_requested.emit(text)

## Something the HUD shows (selection, held item, plan state) has changed.
signal hud_refresh_requested

func refresh_hud() -> void:
	hud_refresh_requested.emit()
