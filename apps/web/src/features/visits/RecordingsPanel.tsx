// Purpose: Organize original visit recordings and provide clearly separated fictional sample access.
// Inputs: A visit and its saved recordings from Reva context.
// Outputs: Recording capture/detail dialogs and a sample tied only to its original fictional visit.
// Side effects: Explicit sample access reads bundled JSON and persists it through context; no microphone starts here.

import { useState } from 'react';
import { ChevronRight, Mic, Play } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import type { Visit, VisitRecording } from '../../core/models';
import { durationLabel, formatDate, uid } from '../../core/domain';
import { Badge, Button, Card } from '../../components/ui';
import { RecordingCapture } from './RecordingCapture';
import { RecordingDetail } from './RecordingDetail';

// MARK: - Visit recordings and explicit fictional sample loading
export function RecordingsPanel({ visit }: { visit: Visit }) {
  const { snapshot, mutate, reportError } = useReva();
  const [capturing, setCapturing] = useState(false);
  const [selected, setSelected] = useState<string | null>(() =>
    new URLSearchParams(window.location.hash.split('?')[1] ?? '').get('recording'),
  );
  const [sampleBusy, setSampleBusy] = useState(false);
  const recordings = (snapshot?.recordings ?? [])
    .filter((item) => item.visitID === visit.id)
    .slice()
    .reverse();
  const selectedRecording = recordings.find((item) => item.id === selected);
  async function sample() {
    setSampleBusy(true);
    try {
      const response = await fetch('/demo/sample-transcript.json');
      if (!response.ok) throw new Error('The fictional sample could not be loaded.');
      const value = (await response.json()) as VisitRecording;
      if (
        value.isSample !== true ||
        !Array.isArray(value.segments) ||
        !value.segments.length ||
        !snapshot?.visits.some((item) => item.id === value.visitID)
      )
        throw new Error(
          'The original fictional visit is unavailable. Restore the demo in Settings to explore it.',
        );
      const existing = snapshot.recordings.find((item) => item.isSample && item.visitID === value.visitID);
      let recordingID = existing?.id ?? uid();
      if (!existing)
        await mutate((draft) => {
          const current = draft.recordings.find((item) => item.isSample && item.visitID === value.visitID);
          if (current) recordingID = current.id;
          else draft.recordings.push({ ...value, id: recordingID, audioFilename: null, isSample: true });
        });
      if (value.visitID === visit.id) setSelected(recordingID);
      else
        window.location.hash = `#/visits/${encodeURIComponent(value.visitID)}?recording=${encodeURIComponent(recordingID)}`;
    } catch (failure) {
      reportError(failure);
    } finally {
      setSampleBusy(false);
    }
  }
  return (
    <Card className="stack recordings-panel">
      <div className="section-heading">
        <div>
          <h2>Recordings & visit memories</h2>
          <p className="muted small">Save the conversation and return to what was discussed.</p>
        </div>
        <Mic size={21} />
      </div>
      <Button onClick={() => setCapturing(true)}>
        <Mic size={17} /> Record or upload audio
      </Button>
      {recordings.length ? (
        <div className="record-list">
          {recordings.map((recording) => (
            <button
              className="record-row recording-row"
              key={recording.id}
              onClick={() => setSelected(recording.id)}
            >
              <span className="record-icon">
                <Play size={18} />
              </span>
              <span className="record-main">
                <strong>{recording.title}</strong>
                <span className="record-meta">
                  {formatDate(recording.createdAt)} · {durationLabel(recording.duration)}
                </span>
                <Badge tone={recording.isSample ? 'review' : 'neutral'}>
                  {recording.isSample
                    ? 'Fictional sample · no audio'
                    : recording.segments.length
                      ? 'Transcript available'
                      : 'Original audio saved'}
                </Badge>
              </span>
              <ChevronRight size={17} />
            </button>
          ))}
        </div>
      ) : (
        <p className="muted small">
          Your saved audio, reviewed transcripts, and visit memories will appear here.
        </p>
      )}
      <details className="sample-access">
        <summary>Explore a fictional sample</summary>
        <p className="small muted">
          This sample has no matching audio and belongs to the fictional September 8 visit. It will never be
          used as a transcript for your recordings.
        </p>
        <Button
          variant="secondary"
          onClick={() => {
            void sample();
          }}
          disabled={sampleBusy}
        >
          {sampleBusy ? 'Opening…' : 'Open fictional sample'}
        </Button>
      </details>
      {capturing && <RecordingCapture visit={visit} onClose={() => setCapturing(false)} />}
      {selectedRecording && (
        <RecordingDetail recording={selectedRecording} onClose={() => setSelected(null)} />
      )}
    </Card>
  );
}
