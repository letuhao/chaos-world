extends Control

## Tiny screen for the DLC example mod end-to-end test (ADR 0184). A test
## double, not a shipped surface: it gives the test a real scene path to
## register and reports itself through the standard `summary()` contract.


func summary() -> Dictionary:
	return {"dlc_example": true}
