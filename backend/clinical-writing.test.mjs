// Purpose: Protect strict generated-prose checks without damaging clinical terms or original evidence.
// Inputs: Fictional text and the two server policy literals.
// Outputs: Assertions for prohibited wording, accepted medical notation and cross-server policy parity.
// Side effects: Reads the Swift helper; no source records, provider calls or persisted values are changed.

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  CLINICAL_WRITING_POLICY,
  ClinicalWritingError,
  validateGeneratedClinicalText,
} from "./clinical-writing.mjs";

// MARK: - Generated style violations fail without an error that repeats medical content
test("generated em and en dashes are rejected without rewriting the supplied text", () => {
  for (const input of [
    "Symptoms lasted 2–3 minutes.",
    "The report lists asthma—status unspecified.",
  ]) {
    assert.throws(
      () => validateGeneratedClinicalText(input, "summary"),
      (error) => {
        assert.ok(error instanceof ClinicalWritingError);
        assert.equal(error.violation, "unsupported-dash");
        assert.equal(error.field, "summary");
        assert.ok(!error.message.includes(input));
        return true;
      },
    );
  }
});

test("sentence-opening boilerplate is rejected, including curly apostrophes", () => {
  for (const input of [
    "As an AI, I cannot diagnose.",
    "As an AI language model, I can provide a summary.",
    "Here is a comprehensive overview of the record.",
    "Here’s a summary of the discussion.",
    "It’s worth noting that the patient reported nausea.",
    "The report lists asthma. In conclusion, this is useful context.",
    "Rest assured, your health journey is in good hands.",
  ])
    assert.throws(
      () => validateGeneratedClinicalText(input),
      ClinicalWritingError,
    );
});

test("clinical words, attribution, hyphens, units and negative values remain valid", () => {
  for (const input of [
    "Dr. Foster documented no significant interval change in overall function.",
    "The record lists levothyroxine 50 µg daily and a beta-blocker; the dose is not documented.",
    "The report records −1.2 and an HbA1c of 6.1%; interpretation is not supplied.",
    "The patient reported symptoms lasting 2 to 3 minutes.",
    "As an AI consultant, the patient reported prolonged desk work.",
  ])
    assert.doesNotThrow(() => validateGeneratedClinicalText(input));
});

test("generated themes reject source narration while preserving clinical qualifiers", () => {
  for (const input of [
    "The transcript discusses sock changing frequency and hygiene topics.",
    "The recording mentions poor general hygiene.",
    "The report describes possible foot fungus.",
    "Sock changes were discussed in the conversation.",
    "Care notes: this document covers hygiene.",
  ]) {
    assert.throws(() => validateGeneratedClinicalText(input, "careNotes"), (error) => {
      assert.equal(error.violation, "source-framing");
      assert.equal(error.field, "careNotes");
      assert.ok(!error.message.includes(input));
      return true;
    });
  }
  for (const input of [
    "Frequent sock changes to prevent foot fungus, poor general hygiene",
    "Sock-changing frequency and hygiene",
    "Patient-reported difficulty with foot hygiene; possible fungal infection",
    "Question about whether more frequent sock changes could help",
    "September 1 report: no allergies; September 2 report: penicillin allergy (conflicting documentation)",
  ]) assert.doesNotThrow(() => validateGeneratedClinicalText(input));
});

test("original evidence is outside generated-prose style validation", () => {
  const evidence = Object.freeze({
    excerpt:
      "The source says: ‘Symptoms lasted 2–3 minutes—duration estimated.’",
  });
  const before = evidence.excerpt;
  validateGeneratedClinicalText(
    "The patient estimated symptoms lasted 2 to 3 minutes.",
  );
  assert.equal(evidence.excerpt, before);
});

test("Node and Swift carry the same writing criteria and boilerplate pattern", async () => {
  const swift = await readFile(
    new URL(
      "../server/Sources/RevaServer/Providers/ClinicalWriting.swift",
      import.meta.url,
    ),
    "utf8",
  );
  const literal = swift.match(
    /static let policy = """\n([\s\S]*?)\n\s*"""/u,
  )?.[1];
  assert.ok(literal);
  assert.equal(
    literal
      .split("\n")
      .map((line) => line.replace(/^ {8}/u, ""))
      .join("\n")
      .trim(),
    CLINICAL_WRITING_POLICY.trim(),
  );
  const node = await readFile(
    new URL("./clinical-writing.mjs", import.meta.url),
    "utf8",
  );
  const nodePattern = node.match(/const boilerplate =\s*\/([^\n]+)\/iu;/u)?.[1];
  const swiftPattern = swift.match(
    /private static let boilerplate =\s*#"([^\n]+)"#/u,
  )?.[1];
  assert.ok(nodePattern);
  assert.equal(swiftPattern, nodePattern);
  assert.equal(
    swift.match(/private static let sourceFraming =\s*#"([^\n]+)"#/u)?.[1],
    node.match(/const sourceFraming =\s*\/([^\n]+)\/iu;/u)?.[1],
  );
});
