// Purpose: Keep saved-recording transcription and analysis visible while the user navigates.
// Inputs: The workspace processing queue, named job stages, and retry/dismiss actions.
// Outputs: A compact source-recording link, honest progress state, and a list of additional jobs.
// Side effects: Delegates retry/dismiss to the shared queue; navigating never owns or stops processing.

import {
  AlertCircle,
  Check,
  ChevronDown,
  ChevronRight,
  Clock3,
  LoaderCircle,
  RotateCcw,
  X,
} from 'lucide-react';
import { useRecordingProcessing, type RecordingJob } from '../core/RecordingProcessingUpdates';
import '../styles/recording-processing.css';

export type RecordingProcessingJob = RecordingJob;
const stageLabels: Record<RecordingProcessingJob['stage'], string> = {
  queued: 'Queued for processing',
  transcribing: 'Transcribing audio',
  analyzing: 'Preparing summary',
  waiting: 'Waiting to continue',
  failed: 'Needs attention',
  complete: 'Ready to review',
};
const running = (job: RecordingProcessingJob) => job.stage === 'transcribing' || job.stage === 'analyzing';

// MARK: - The indicator observes the app-scoped queue rather than starting a second worker
export function RecordingProcessingIndicator({ placement }: { placement: 'sidebar' | 'compact' }) {
  const processing = useRecordingProcessing();
  return <RecordingProcessingStatus {...processing} placement={placement} />;
}

export function RecordingProcessingStatus({
  jobs,
  retry,
  dismiss,
  placement = 'sidebar',
}: {
  jobs: readonly RecordingProcessingJob[];
  retry: (id: string) => void;
  dismiss: (id: string) => void;
  placement?: 'sidebar' | 'compact';
}) {
  if (!jobs.length) return null;
  const primary =
    jobs.find(running) ??
    jobs.find((job) => job.stage === 'queued') ??
    jobs.find((job) => job.stage === 'failed' || job.stage === 'waiting') ??
    jobs.at(-1)!;
  const remaining = jobs.filter((job) => job.id !== primary.id);
  const queued = jobs.filter((job) => job.stage === 'queued' && job.id !== primary.id).length;
  return (
    <section
      className={`processing-indicator processing-indicator-${placement}`}
      aria-label="Recording processing"
    >
      <div className="processing-current">
        <JobStatus job={primary} retry={retry} dismiss={dismiss} />
      </div>
      {remaining.length > 0 && (
        <details className="processing-queue">
          <summary>
            <span>
              {queued
                ? `${queued} queued`
                : `${remaining.length} more recording${remaining.length === 1 ? '' : 's'}`}
            </span>
            <ChevronDown size={13} aria-hidden="true" />
          </summary>
          <ul
            aria-label="Other recording jobs"
            onClick={(event) => {
              if ((event.target as HTMLElement).closest('a'))
                event.currentTarget.closest('details')?.removeAttribute('open');
            }}
          >
            {remaining.map((job) => (
              <li key={job.id}>
                <JobStatus job={job} retry={retry} dismiss={dismiss} />
              </li>
            ))}
          </ul>
        </details>
      )}
    </section>
  );
}

// MARK: - Every stage links to the saved recording, including partially completed or failed jobs
function JobStatus({
  job,
  retry,
  dismiss,
}: {
  job: RecordingProcessingJob;
  retry: (id: string) => void;
  dismiss: (id: string) => void;
}) {
  const active = running(job);
  const needsHelp = job.stage === 'failed' || job.stage === 'waiting';
  const Icon = active
    ? LoaderCircle
    : job.stage === 'complete'
      ? Check
      : job.stage === 'failed'
        ? AlertCircle
        : Clock3;
  return (
    <div className={`processing-job is-${job.stage}`}>
      <a
        className="processing-job-link"
        href={`#/recordings/${encodeURIComponent(job.id)}`}
        aria-label={`Open ${job.title}: ${stageLabels[job.stage]}`}
        title={`${job.title} · ${stageLabels[job.stage]}`}
      >
        <span className={`processing-job-symbol${active ? ' is-running' : ''}`} aria-hidden="true">
          <Icon size={18} />
        </span>
        <span className="processing-job-copy">
          <strong>{job.title}</strong>
          <span className="processing-stage" role="status" aria-live="polite" aria-atomic="true">
            <span className="sr-only">{job.title}: </span>
            {stageLabels[job.stage]}
          </span>
        </span>
        <ChevronRight className="processing-job-arrow" size={14} aria-hidden="true" />
      </a>
      {needsHelp && job.message && (
        <p className="processing-job-message" title={job.message}>
          {job.message}
        </p>
      )}
      {(needsHelp || job.stage === 'complete') && (
        <div className="processing-job-actions">
          {needsHelp ? (
            !job.retryAt && (
              <button
                type="button"
                onClick={() => retry(job.id)}
                aria-label={`Retry processing ${job.title}`}
              >
                <RotateCcw size={12} aria-hidden="true" /> Try again
              </button>
            )
          ) : (
            <a href={`#/recordings/${encodeURIComponent(job.id)}`}>View recording</a>
          )}
          {job.stage === 'complete' && (
            <button
              type="button"
              className="processing-dismiss"
              onClick={() => dismiss(job.id)}
              aria-label={`Dismiss processing status for ${job.title}`}
              title="Dismiss status"
            >
              <X size={14} aria-hidden="true" />
            </button>
          )}
        </div>
      )}
    </div>
  );
}
