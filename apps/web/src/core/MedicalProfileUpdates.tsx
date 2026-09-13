// Purpose: Attach automatic medical-profile updates to the current mounted workspace.
// Inputs: The workspace store and its child views.
// Outputs: A reactive update status for profile UI.
// Side effects: Starts and stops the report observer and retries when connectivity returns.
import { createContext, useContext, useEffect, useRef, useSyncExternalStore, type ReactNode } from 'react';
import { MedicalProfileAutomation, type ProfileHost } from './profileAutomation';

// MARK: - Provider lifetime prevents requests from surviving account changes or unmount.
const Context = createContext<MedicalProfileAutomation | null>(null);
export function MedicalProfileUpdates({ store, children }: { store: ProfileHost; children: ReactNode }) {
  const instance = useRef<MedicalProfileAutomation | null>(null);
  if (!instance.current) instance.current = new MedicalProfileAutomation(store);
  useEffect(() => {
    const automation = instance.current!;
    automation.start();
    window.addEventListener('online', automation.retry);
    window.addEventListener('focus', automation.retry);
    return () => {
      automation.stop();
      window.removeEventListener('online', automation.retry);
      window.removeEventListener('focus', automation.retry);
    };
  }, []);
  return <Context.Provider value={instance.current}>{children}</Context.Provider>;
}
export function useMedicalProfileUpdate() {
  const automation = useContext(Context);
  if (!automation) throw new Error('Medical profile updates require a workspace.');
  return useSyncExternalStore(automation.subscribe, automation.getState, automation.getState);
}
