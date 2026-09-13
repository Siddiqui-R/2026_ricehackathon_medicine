// Purpose: Keep saved recording playback, transcription and summaries in the full-page recording flow.
// Inputs: A bookmarkable recording ID and the active workspace snapshot.
// Outputs: A source-preserving recording review page or a clear missing-recording state.
// Side effects: Delegates connected work and corrections to the shared recording detail component.

import { ArrowLeft } from 'lucide-react';
import { Card, EmptyState, PageHeading } from '../../components/ui';
import { useReva } from '../../core/RevaContext';
import { demoLabel } from '../../core/presentation';
import { RecordingDetail } from './RecordingDetail';

// MARK: - Full-page review shares the same original-audio and transcript behavior as saved visit details
export function SavedRecordingPage({ id }: { id: string }) {
  const { snapshot } = useReva();
  const recording = snapshot?.recordings.find((item) => item.id === id);
  if (!recording)
    return (
      <Card>
        <EmptyState title="Recording not found">
          <a className="text-link" href="#/summary">
            Return to overview
          </a>
        </EmptyState>
      </Card>
    );
  const visit = snapshot?.visits.find((item) => item.id === recording.visitID);
  return (
    <div className="recording-review-page stack">
      <a
        className="text-link back-link"
        href={visit ? `#/visits/${encodeURIComponent(visit.id)}` : '#/summary'}
      >
        <ArrowLeft size={16} /> {visit ? 'Back to visit' : 'Back to overview'}
      </a>
      <PageHeading
        title={demoLabel(recording.title, recording.isSample)}
        description="Your original conversation, with a transcript and notes you can return to."
      />
      <Card>
        <RecordingDetail key={id} recording={recording} embedded onClose={() => {}} />
      </Card>
    </div>
  );
}
