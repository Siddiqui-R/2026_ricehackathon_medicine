// Purpose: Verify browser evidence and source invariants against native-generated synthetic expectations.
// Inputs: Checked-in fictional records, native signature golden values and deliberate source edits.
// Outputs: Assertions for selection, exact citations, staleness, versions and transcript reconciliation.
// Side effects: Test memory and Web Crypto only.
import { describe, expect, it } from 'vitest';
import evidence from '../../../public/demo/expected-evidence.json';
import {
  generateReport,
  localExcerpt,
  makeSymptomRecord,
  reportIsStale,
  reportSignature,
  selectedRecords,
  validateSnapshot,
} from '../domain.ts';
import { confirmBooking, reconcileMemory, upsertRecord } from '../mutations.ts';
import { sample, seed } from './fixtures.ts';

// MARK: - Golden signatures were emitted by the actual Swift ReportEngine on this same seed.
describe('native evidence compatibility', () => {
  it('matches every native fixture signature exactly', async () => {
    const data = seed(),
      expected = [
        '527ef9c5bd17610165587b1ee17ef5e78a6d5937922ece737eed0c7830855e11',
        '296a24acd853c35b53a9864894170716ba93650899330020e4aabc6e43f9dcb3',
        '9868130528caaa4118306c0c7c825c3ab6dad7d33a6e1857df1a97cb05cffde3',
      ];
    expect(await Promise.all(data.visits.map((visit) => reportSignature(visit, data.records)))).toEqual(
      expected,
    );
  });
  it.each(evidence.scenarios)('retains requested sources and real pages for $id', async (scenario) => {
    const data = seed(),
      visit = data.visits.find((item) => item.id === scenario.visitID)!;
    const report = await generateReport(visit, data.records);
    scenario.mustInclude.forEach((id) => expect(report.selectedRecordIDs).toContain(id));
    scenario.mustExclude.forEach((id) => expect(report.selectedRecordIDs).not.toContain(id));
    scenario.sourceChecks.forEach((check) => {
      const source = report.sections
        .flatMap((section) => section.sources)
        .find((item) => item.recordID === check.recordID)!;
      expect(source.page).toBe(check.page);
      expect(source.excerpt).toContain(check.contains);
      expect(source.sourceVersion).toBe(data.records.find((record) => record.id === check.recordID)!.version);
    });
  });
  it('preserves original quotes and uncertainty without fixture wrapper text', async () => {
    const data = seed(),
      report = await generateReport(data.visits[0], data.records);
    const section = report.sections.find((item) =>
      item.sources.some((source) => source.recordID === 'demo-record-symptom-diary'),
    )!;
    expect(section.body).toContain('Needs review:');
    expect(section.body).toContain('September 0[unclear], 2026');
    expect(section.sources[0].excerpt).not.toContain('SYNTHETIC DEMO');
    expect(section.sources[0].excerpt).not.toContain('Invented for Reva');
    expect(localExcerpt('first\nsecond')).toBe('first\nsecond');
  });
  it('keeps explicit pins, full candidate-pool staleness and cleared question authority', async () => {
    const data = seed(),
      visit = data.visits[1];
    visit.pinnedRecordIDs.push('demo-record-ear-infection');
    visit.questions = [];
    expect(selectedRecords(visit, data.records).map((record) => record.id)).toContain(
      'demo-record-ear-infection',
    );
    visit.report = await generateReport(visit, data.records);
    expect(visit.report.questions).toHaveLength(3);
    expect(await reportIsStale(visit, data.records)).toBe(false);
    visit.questions = [];
    visit.notes = 'My own notes';
    const updated = await generateReport(visit, data.records);
    expect(updated.questions).toEqual([]);
    expect(updated.notes).toBe('My own notes');
    data.records.push({ ...data.records[0], id: 'new-independent-record' });
    expect(await reportIsStale(visit, data.records)).toBe(true);
  });
  it('uses page zero for transcript sources and finds a relevant deeper passage', async () => {
    const data = seed(),
      visit = data.visits[1],
      record = data.records[0];
    record.text =
      Array.from({ length: 30 }, (_, i) => `Unrelated introduction ${i}`).join('\n') +
      '\nImplant location: RIGHT TIBIA\nExact retained source.';
    record.pageTexts = undefined;
    visit.pinnedRecordIDs = [record.id];
    const report = await generateReport(visit, [record]),
      source = report.sections.flatMap((section) => section.sources)[0];
    expect(source.page).toBe(0);
    expect(source.excerpt).toContain('Exact retained source.');
    expect(source.excerpt).not.toContain('introduction 0');
  });
});

// MARK: - Edits affect source versions only when evidence changes, and memories retain source identity.
describe('durable domain edits', () => {
  it('rejects stale record saves while keeping notes-only edits out of the source version', () => {
    const data = seed(),
      record = data.records[0],
      version = record.version;
    upsertRecord(data, { ...record, notes: 'Personal notes' }, version);
    expect(data.records[0].version).toBe(version);
    upsertRecord(data, { ...data.records[0], text: record.text + '\nCorrected source' }, version);
    expect(data.records[0].version).toBe(version + 1);
    expect(() => upsertRecord(data, record, version)).toThrow('changed or was deleted');
  });
  it('corrects words by segment ID and updates one linked memory without losing separate notes', () => {
    const data = seed(),
      recording = sample();
    data.recordings = [recording];
    reconcileMemory(data, recording.id);
    const memory = data.records.find((record) => record.sourceRecordingID === recording.id)!;
    const oldVersion = memory.version;
    memory.notes = 'Preserve my separate notes';
    const correction = Object.fromEntries(recording.segments.map((segment) => [segment.id, segment.text]));
    correction[recording.segments[0].id] = 'Reviewed fictional words.';
    reconcileMemory(data, recording.id, correction);
    const updated = data.records.find((record) => record.id === memory.id)!;
    expect(updated.version).toBe(oldVersion + 1);
    expect(updated.notes).toBe('Preserve my separate notes');
    expect(updated.text).toContain('[0:00–0:12] Narrator (Synthetic): Reviewed fictional words.');
    expect(data.records.filter((record) => record.sourceRecordingID === recording.id)).toHaveLength(1);
    expect(() => reconcileMemory(data, recording.id, { wrong: 'new' })).toThrow('changed');
  });
  it('does not create an unrequested memory when correcting an unsaved transcript', () => {
    const data = seed(),
      recording = sample();
    data.recordings = [recording];
    reconcileMemory(
      data,
      recording.id,
      Object.fromEntries(recording.segments.map((segment) => [segment.id, segment.text])),
    );
    expect(data.records.some((record) => record.sourceRecordingID === recording.id)).toBe(false);
  });
  it('projects symptom observations by their timezone and rejects impossible dates', () => {
    const entry = {
      symptom: 'Nausea',
      observedAt: '2026-09-08T02:30:00Z',
      timeZone: 'America/Chicago',
      duration: '2 minutes',
      details: 'While resting',
      triggers: '',
      whatHelped: '',
      severity: 'mild',
    };
    const record = makeSymptomRecord(entry);
    expect(record.date).toBe('2026-09-07');
    expect(record.isDemo).toBe(false);
    expect(record.text).toContain('Self-reported by the user.');
    expect(record.text).toContain('Occurred at: 2026-09-08T02:30:00Z (America/Chicago)');
    expect(() => makeSymptomRecord({ ...entry, observedAt: '2026-02-30T02:30:00Z' })).toThrow(
      'valid occurrence',
    );
  });
  it('fails malformed data while allowing intentionally stale deleted-source citations', async () => {
    const data = seed();
    data.visits[0].report = await generateReport(data.visits[0], data.records);
    data.records = [];
    expect(validateSnapshot(data)).toBe(data);
    const invalid = seed();
    invalid.records[0].sourceFilename = '../secret';
    expect(() => validateSnapshot(invalid)).toThrow('sourceFilename');
    invalid.records[0].sourceFilename = 'valid.pdf';
    invalid.records.push(invalid.records[0]);
    expect(() => validateSnapshot(invalid)).toThrow('records.id');
  });
  it('never turns a provider call result into a confirmed appointment', () => {
    const data = seed(),
      visit = data.visits[0];
    data.bookings = [
      {
        id: 'live',
        visitID: visit.id,
        clinic: 'Fictional',
        phone: '+13125550123',
        reason: 'Fictional',
        earliest: visit.date,
        latest: visit.date,
        timeZone: visit.timeZone,
        preferences: '',
        status: 'proposed',
        scenario: '',
        createdAt: visit.date,
        isLive: true,
      },
    ];
    expect(() => confirmBooking('live', data)).toThrow('simulated');
    expect(data.bookings[0].confirmedVisitID).toBeUndefined();
  });
});
