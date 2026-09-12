// Purpose: Expose the durable Reva store through the agreed React feature contract.
// Inputs: Child components and an optional injectable store for browser integration tests.
// Outputs: Reactive snapshot, feedback, connection values and bound store actions.
// Side effects: Initializes browser persistence once; subscriptions clean up on unmount.
import { createContext, useContext, useEffect, useRef, useSyncExternalStore, type ReactNode } from 'react';
import { RevaStore } from './store.ts';

// MARK: - One store instance survives React strict-effect retries without resetting persisted data.
const Context = createContext<RevaStore | null>(null);
export function RevaProvider({ children, store }: { children: ReactNode; store?: RevaStore }) {
  const instance = useRef<RevaStore | null>(null);
  if (!instance.current) instance.current = store ?? new RevaStore();
  useEffect(() => {
    void instance.current!.initialize();
  }, []);
  return <Context.Provider value={instance.current}>{children}</Context.Provider>;
}

// MARK: - Bound arrow actions remain safe when UI controls pass them directly as callbacks.
export function useReva() {
  const store = useContext(Context);
  if (!store) throw new Error('Reva features must render inside RevaProvider.');
  const state = useSyncExternalStore(store.subscribe, store.getState, store.getState);
  return {
    ...state,
    mutate: store.mutate,
    notify: store.notify,
    reportError: store.reportError,
    clearFeedback: store.clearFeedback,
    resetDemo: store.resetDemo,
    saveRecord: store.saveRecord,
    deleteRecord: store.deleteRecord,
    saveVisit: store.saveVisit,
    summarizeRecord: store.summarizeRecord,
    prepareVisit: store.prepareVisit,
    saveMemory: store.saveMemory,
    transcribeRecording: store.transcribeRecording,
    startCall: store.startCall,
    refreshCall: store.refreshCall,
    setConnectedAI: store.setConnectedAI,
    setToken: store.setToken,
    checkServer: store.checkServer,
    pushToServer: store.pushToServer,
    pullFromServer: store.pullFromServer,
  };
}
