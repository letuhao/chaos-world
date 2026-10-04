extends Control

## Tiny fixture screen for the ScreenRegistry / ScreenStack seam tests (ADR 0184).
## A test double, not a shipped surface: it gives a test a real scene path to
## register and mount, and reports itself through the standard `summary()`
## contract so a test can assert identity without reading pixels.


func summary() -> Dictionary:
	return {"fixture": true}
