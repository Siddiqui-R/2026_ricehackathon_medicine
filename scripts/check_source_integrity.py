#!/usr/bin/env python3
"""Purpose: Run source-integrity regressions against production native domain code.
Inputs: Swift compiler/SDK and synthetic checked-in test fixtures.
Outputs: Named passes or a failing process; this does not verify cryptography or iOS UI.
Side effects: Writes ignored build files; no live network or application data changes.
"""

from check_optimization_fixes import configure_compiler, run_suite


# MARK: - Compile the same source-selection and date functions used by the app.
if __name__ == "__main__":
    run_suite(configure_compiler(), "SourceIntegrityChecks", [
        "Core/Models.swift", "Core/SymptomEntry.swift", "Core/SourceExcerpt.swift",
        "Core/ReportEngine.swift",
    ], include_audio_helper=False)
