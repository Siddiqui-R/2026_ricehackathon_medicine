// Purpose: Verify page-owned brief requests stop on user cancellation, navigation and identity changes.
// Inputs: A minimal hook host and deferred synthetic provider responses.
// Outputs: Cancellation signals and protection against stale PDF/results or an older request unlocking a newer one.
// Side effects: Mocked React state/provider only; no browser, PDF export or paid request runs.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const host = vi.hoisted(() => ({
  states: [] as unknown[],
  refs: [] as { current: unknown }[],
  effects: [] as { deps?: unknown[]; cleanup?: () => void }[],
  state: 0,
  ref: 0,
  effect: 0,
}));
const fake = vi.hoisted(() => ({ token: 'workspace-one', generate: vi.fn(), pdf: vi.fn() }));
vi.mock('react', async (original) => ({
  ...(await original<typeof import('react')>()),
  useState<T>(initial: T | (() => T)) {
    const i = host.state++;
    if (!(i in host.states))
      host.states[i] = typeof initial === 'function' ? (initial as () => T)() : initial;
    return [
      host.states[i],
      (value: T) => {
        host.states[i] = value;
      },
    ];
  },
  useRef<T>(initial: T) {
    const i = host.ref++;
    return (host.refs[i] ??= { current: initial });
  },
  useEffect(effect: () => (() => void) | void, deps?: unknown[]) {
    const i = host.effect++,
      previous = host.effects[i];
    if (
      previous &&
      deps &&
      deps.length === previous.deps?.length &&
      deps.every((value, j) => Object.is(value, previous.deps![j]))
    )
      return;
    previous?.cleanup?.();
    host.effects[i] = { deps, cleanup: effect() || undefined };
  },
}));
vi.mock('../../core/RevaContext', () => ({
  useReva: () => ({ snapshot: null, token: fake.token, generateVisitBrief: fake.generate }),
}));
vi.mock('./briefPDF', () => ({ createBriefPDF: fake.pdf }));
import { VisitPreparation } from './VisitPreparation';

type Node = {
  type?: unknown;
  props: {
    children?: unknown;
    onSubmit?: (event: unknown) => void;
    onClick?: () => void;
    disabled?: boolean;
  };
};
function find(value: unknown, predicate: (node: Node) => boolean): Node | undefined {
  if (Array.isArray(value)) return value.map((item) => find(item, predicate)).find(Boolean);
  if (!value || typeof value !== 'object' || !('props' in value)) return;
  const node = value as Node;
  return predicate(node) ? node : find(node.props.children, predicate);
}
function render() {
  host.state = host.ref = host.effect = 0;
  return VisitPreparation({ initial: { type: 'Synthetic checkup', concern: '', questions: [] } });
}
function submit() {
  find(render(), (node) => node.type === 'form')!.props.onSubmit!({ preventDefault() {} });
}
function stop() {
  find(render(), (node) => node.props.children === 'Stop preparation')!.props.onClick!();
}
function unmount() {
  host.effects.forEach((effect) => effect.cleanup?.());
}
function deferred() {
  let resolve!: (value: unknown) => void;
  const promise = new Promise<unknown>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
beforeEach(() => {
  host.states = [];
  host.refs = [];
  host.effects = [];
  fake.token = 'workspace-one';
  vi.clearAllMocks();
});
afterEach(unmount);

describe('page-owned visit preparation', () => {
  it('stops an in-flight request without allowing its late result to affect a newer request', async () => {
    const first = deferred(),
      second = deferred();
    fake.generate.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    submit();
    const signal = fake.generate.mock.calls[0][1] as AbortSignal;
    stop();
    expect(signal.aborted).toBe(true);
    submit();
    first.resolve({ sources: [] });
    await Promise.resolve();
    expect(find(render(), (node) => node.type === 'fieldset')!.props.disabled).toBe(true);
    expect((fake.generate.mock.calls[1][1] as AbortSignal).aborted).toBe(false);
    expect(fake.pdf).not.toHaveBeenCalled();
  });
  it.each(['navigation', 'identity'])(
    'aborts on %s and discards a response returned afterward',
    async (change) => {
      const pending = deferred();
      fake.generate.mockReturnValueOnce(pending.promise);
      submit();
      const signal = fake.generate.mock.calls[0][1] as AbortSignal;
      if (change === 'navigation') unmount();
      else {
        fake.token = 'workspace-two';
        render();
      }
      expect(signal.aborted).toBe(true);
      pending.resolve({ sources: [] });
      await Promise.resolve();
      expect(fake.pdf).not.toHaveBeenCalled();
      if (change === 'identity')
        expect(find(render(), (node) => node.type === 'fieldset')!.props.disabled).toBe(false);
    },
  );
});
