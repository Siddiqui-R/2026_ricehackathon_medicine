// Purpose: Validate only optional date/title provenance added to synchronized records and recordings.
// Inputs: Structurally validated snapshot arrays containing untrusted optional metadata.
// Outputs: A boolean acceptance decision without rewriting, inferring or adding timestamps.
// Side effects: None. Missing/null fields and unrelated legacy snapshot content remain accepted.

// MARK: - Bounded ISO calendar dates and instants, including explicit numeric offsets
export function validMetadataDate(value) {
  if (typeof value !== "string" || value.length > 40) return false;
  const match =
    /^(\d{4})-(\d{2})-(\d{2})(?:T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d))?$/.exec(
      value,
    );
  if (!match || match[0] !== value) return false;
  const [, yearText, monthText, dayText] = match;
  const year = Number(yearText),
    month = Number(monthText),
    day = Number(dayText);
  if (year < 1 || month < 1 || month > 12) return false;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return (
    day >= 1 && day <= days[month - 1] && Number.isFinite(Date.parse(value))
  );
}

// MARK: - Optional provenance metadata is typed without tightening the rest of a snapshot
export function validSnapshotMetadata(snapshot) {
  const optionalEnum = (value, choices) =>
    value == null || choices.includes(value);
  const optionalDate = (value) => value == null || validMetadataDate(value);
  return (
    snapshot.records.every(
      (record) =>
        optionalEnum(record.dateSource, [
          "document",
          "observed",
          "recorded",
          "added",
        ]) && optionalDate(record.summaryGeneratedAt),
    ) &&
    snapshot.recordings.every(
      (recording) =>
        optionalEnum(recording.titleSource, ["user", "date", "ai"]) &&
        ["capturedAt", "savedAt", "aiSummaryGeneratedAt"].every((field) =>
          optionalDate(recording[field]),
        ),
    )
  );
}
