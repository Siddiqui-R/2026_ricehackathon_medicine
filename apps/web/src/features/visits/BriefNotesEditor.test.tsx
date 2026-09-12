// Purpose: Reproduce brief editor rerenders while preparation or another editor publishes newer values.
// Inputs: The real React editor, an isolated store, and synthetic user input in jsdom.
// Outputs: Assertions that unchanged questions survive and competing edits remain unsaved.
// Side effects: Test DOM and memory repository only; dialog methods are stubbed, with no live providers.
// @vitest-environment jsdom

import { webcrypto } from 'node:crypto';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { RevaProvider, useReva } from '../../core/RevaContext';
import { RevaStore } from '../../core/store';
import { MemoryRepository, transport } from '../../core/__tests__/fixtures';
import { BriefNotesEditor } from './VisitBrief';

let root: Root;
let container: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  vi.stubGlobal('crypto', webcrypto);
  Object.defineProperties(HTMLDialogElement.prototype, {
    showModal: {
      configurable: true,
      value: function (this: HTMLDialogElement) {
        this.open = true;
      },
    },
    close: {
      configurable: true,
      value: function (this: HTMLDialogElement) {
        this.open = false;
      },
    },
  });
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
function CurrentEditor({ onClose }: { onClose: () => void }) {
  const { snapshot } = useReva();
  return <BriefNotesEditor visit={snapshot!.visits[0]} onClose={onClose} />;
}
async function typeInto(index: number, text: string) {
  const input = container.querySelectorAll('textarea')[index];
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!.call(input, text);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
async function renderEditor(questions: string[] = []) {
  const store = new RevaStore(new MemoryRepository(), () => transport());
  await store.initialize();
  await store.mutate((draft) => {
    draft.visits[0].questions = questions;
    draft.visits[0].report = null;
  });
  const onClose = vi.fn();
  await act(async () =>
    root.render(
      <RevaProvider store={store}>
        <CurrentEditor onClose={onClose} />
      </RevaProvider>,
    ),
  );
  return { store, onClose };
}

// MARK: - Actual mount state must outlive changing visit props
describe('brief notes editor rerender races', () => {
  it('saves notes after preparation rerenders the open editor without clearing generated questions', async () => {
    const { store, onClose } = await renderEditor();
    await typeInto(1, 'Notes typed before preparation finished.');
    await act(async () => store.prepareVisit(store.getState().snapshot!.visits[0].id));
    const generated = [...store.getState().snapshot!.visits[0].questions];
    expect(generated.length).toBeGreaterThan(0);
    expect(container.querySelectorAll('textarea')[0].value).toBe('');
    await act(async () => {
      container
        .querySelector('form')!
        .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    });
    const saved = store.getState().snapshot!.visits[0];
    expect(saved.questions).toEqual(generated);
    expect(saved.report!.questions).toEqual(generated);
    expect(saved.notes).toBe('Notes typed before preparation finished.');
    expect(saved.report!.notes).toBe(saved.notes);
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('shows a conflict without overwriting any field after competing notes update live props', async () => {
    const { store, onClose } = await renderEditor();
    await typeInto(0, 'My unsaved question?');
    await typeInto(1, 'My unsaved notes.');
    await act(async () =>
      store.mutate((draft) => {
        draft.visits[0].notes = 'Newer notes from another editor.';
      }),
    );
    const before = structuredClone(store.getState().snapshot!);
    await act(async () => {
      container
        .querySelector('form')!
        .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    });
    expect(store.getState().snapshot).toEqual(before);
    expect(container.querySelector('[role="alert"]')!.textContent).toContain(
      'changed while this editor was open',
    );
    expect(onClose).not.toHaveBeenCalled();
  });

  it('keeps untouched question wording byte-for-byte when saving only notes', async () => {
    const questions = ['  Keep this spacing?  ', 'Keep a question with\nan intentional line break?'];
    const { store } = await renderEditor(questions);
    await typeInto(1, 'Only notes changed.');
    await act(async () => {
      container
        .querySelector('form')!
        .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    });
    expect(store.getState().snapshot!.visits[0].questions).toEqual(questions);
    expect(store.getState().snapshot!.visits[0].notes).toBe('Only notes changed.');
  });
});
