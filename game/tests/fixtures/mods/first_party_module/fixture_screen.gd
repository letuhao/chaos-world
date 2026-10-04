extends Control

## Tiny fixture screen for the mods system end-to-end test (ADR 0184). A test
## double, not a shipped surface: it gives the test a real scene path to
## register and reports itself through the standard `summary()` contract.


func summary() -> Dictionary:
	return {"fixture": true}
