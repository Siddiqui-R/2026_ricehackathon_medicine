#!/usr/bin/env python3
"""Purpose: Run native audit regressions against the production AppStore boundaries.
Inputs: Swift compiler and the checked-in synthetic AuditStateChecks harness.
Outputs: Named behavioral assertions or a nonzero compiler/assertion failure.
Side effects: Writes build/optimization-checks/AuditStateChecks and synthetic temporary files.
"""

from check_optimization_fixes import configure_compiler, run_suite


# MARK: - Production source coverage
# Reuse the compiler/SDK setup shared with the existing optimization checks.
SOURCES = [
    "Core/Models.swift", "Core/SymptomEntry.swift", "Core/LocalRepository.swift",
    "Core/ProviderContracts.swift", "Core/ReportEngine.swift", "Core/SourceExcerpt.swift",
    "Core/BookingEngine.swift", "State/AppStore.swift", "State/AppStore+Records.swift",
    "State/AppStore+Recordings.swift", "State/AppStore+Visits.swift", "State/AppStore+Bookings.swift",
    "State/AppStore+Providers.swift", "State/AppStore+AI.swift", "State/AppStore+Transcription.swift",
    "State/AppStore+LiveCalls.swift", "State/AppStore+Sync.swift",
]


# MARK: - Local regression execution
if __name__ == "__main__":
    run_suite(configure_compiler(), "AuditStateChecks", SOURCES)
