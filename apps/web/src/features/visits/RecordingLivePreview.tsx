// Purpose: Keep the live conversation just below capture controls, without moving the page as it grows.
import { useEffect, useRef } from 'react';
import { emptyLiveTranscript, type LiveTranscript } from './liveTranscription';

export function RecordingLivePreview({ transcript = emptyLiveTranscript }: { transcript?: LiveTranscript }) {
  const panel = useRef<HTMLDivElement>(null);
  const following = useRef(true);
  const { status, committed, partial } = transcript;
  useEffect(() => {
    if (following.current && panel.current) panel.current.scrollTop = panel.current.scrollHeight;
  }, [committed, partial]);
  const caption =
    status === 'connecting'
      ? 'Connecting live transcript…'
      : status === 'unavailable'
        ? 'Live transcript unavailable. Your audio is kept for transcription after saving.'
        : status === 'paused'
          ? 'Live transcript paused'
          : status === 'stopped'
            ? 'Live preview · Final transcript follows after saving'
            : status === 'listening'
              ? 'Listening…'
              : 'Live transcript will appear here';
  return (
    <section className="recording-live-preview" aria-label="Live transcript">
      <p className="recording-live-caption" role="status">
        {caption}
      </p>
      {(committed || partial) && (
        <div
          ref={panel}
          className="recording-live-text"
          tabIndex={0}
          role="region"
          aria-label="Live transcript preview"
          onScroll={() => {
            const element = panel.current;
            if (element)
              following.current = element.scrollHeight - element.scrollTop - element.clientHeight < 24;
          }}
        >
          {committed && <span>{committed}</span>}
          {partial && (
            <span className="recording-live-partial">
              {committed ? '\n' : ''}
              {partial}
            </span>
          )}
        </div>
      )}
    </section>
  );
}
