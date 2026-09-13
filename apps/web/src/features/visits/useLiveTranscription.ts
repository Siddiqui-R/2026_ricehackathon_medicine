// Purpose: Keep live captions with the shared recording session, across page navigation.
import { useEffect, useRef, useState } from 'react';
import { emptyLiveTranscript, LiveTranscription } from './liveTranscription';

export function useLiveTranscription(loadToken: (signal: AbortSignal) => Promise<string>) {
  const [transcript, setTranscript] = useState(emptyLiveTranscript);
  const client = useRef<LiveTranscription | null>(null);
  const loader = useRef(loadToken);
  loader.current = loadToken;
  if (!client.current) client.current = new LiveTranscription(setTranscript);
  useEffect(() => () => client.current?.dispose(), []);
  return {
    transcript,
    start: (stream: MediaStream) => {
      void client.current!.start(stream, (signal) => loader.current(signal));
    },
    resume: (stream: MediaStream) => {
      void client.current!.start(stream, (signal) => loader.current(signal));
    },
    pause: () => client.current!.stop('paused'),
    stop: () => client.current!.stop(),
    reset: () => client.current!.reset(),
    dispose: () => client.current!.dispose(),
  };
}
