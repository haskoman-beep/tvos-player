// Bauwächter: `FelCurveFoldResult` gibt es in AetherEngine 7.71.2 nur mit dem Trait „DolbyVisionFelCurves“
// (Video/FelCurves/FelCurveFoldRun.swift steht ganz unter `#if DolbyVisionFelCurves`). Kommt der Trait
// nicht an, bricht der Bau hier ab, statt still eine Engine ohne FEL-Kurven auszuliefern.
@_spi(Diagnostics) import AetherEngine

typealias FelBuildGuard = FelCurveFoldResult
