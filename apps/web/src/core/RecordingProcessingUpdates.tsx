// Purpose: Keep background recording work alive independently of routed workspace views.
// Inputs: One workspace store and persisted processing markers on consented recordings.
// Outputs: Reactive progress and explicit retry/dismiss actions.
// Side effects: Owns processor lifetime and connectivity listeners; cancels on workspace exit.
import { createContext, useContext, useEffect, useRef, useSyncExternalStore, type ReactNode } from 'react';
import {
  RecordingProcessingAutomation,
  type RecordingProcessingHost,
  type RecordingJob,
} from './recordingProcessing';
const Context = createContext<RecordingProcessingAutomation | null>(null);
const empty: RecordingJob[] = [];
const noopSubscribe = () => () => {};
export function RecordingProcessingUpdates({
  store,
  children,
}: {
  store: RecordingProcessingHost;
  children: ReactNode;
}) {
  const instance = useRef<RecordingProcessingAutomation | null>(null);
  if (!instance.current) instance.current = new RecordingProcessingAutomation(store);
  useEffect(() => {
    const processor = instance.current!;
    processor.start();
    window.addEventListener('online', processor.wake);
    return () => {
      processor.stop();
      window.removeEventListener('online', processor.wake);
    };
  }, []);
  return <Context.Provider value={instance.current}>{children}</Context.Provider>;
}
export function useRecordingProcessing() {
  const processor = useContext(Context);
  const jobs = useSyncExternalStore(
    processor?.subscribe ?? noopSubscribe,
    processor?.getState ?? (() => empty),
    () => empty,
  );
  return {
    jobs,
    retry: processor?.retry ?? (() => {}),
    reprocess: processor?.reprocess ?? (() => {}),
    dismiss: processor?.dismiss ?? (() => {}),
  };
}
export type { RecordingJob } from './recordingProcessing';
