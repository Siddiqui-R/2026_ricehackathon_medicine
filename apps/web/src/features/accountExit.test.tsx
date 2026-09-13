// Purpose: Ensure account actions respect an unsaved recording before server credentials or data change.
// Inputs: Synthetic account cards, mocked form state and a recording workspace-exit decision.
// Outputs: Regression assertions for cancelled and allowed logout, all-session revoke and account deletion.
// Side effects: No auth requests; callbacks run only mocked store actions.

import { Children, isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const mocks = vi.hoisted(() => ({
  states: [] as unknown[],
  index: 0,
  allow: vi.fn(),
  logout: vi.fn(),
  logoutAll: vi.fn(),
  deleteAccount: vi.fn(),
}));
vi.mock('react', async (original) => ({
  ...(await original<typeof import('react')>()),
  useState: (initial: unknown) => [mocks.states[mocks.index++] ?? initial, vi.fn()],
}));
vi.mock('../core/RevaContext', () => ({
  useReva: () => ({
    accountUser: {
      name: 'Synthetic Tester',
      email: 'synthetic@example.test',
      createdAt: '2026-09-12T00:00:00Z',
    },
    account: {},
    syncStatus: 'saved',
    busy: false,
    logout: mocks.logout,
    logoutAll: mocks.logoutAll,
    deleteAccount: mocks.deleteAccount,
  }),
}));
vi.mock('./visits/RecordingSession', () => ({
  useRecordingSession: () => ({ allowWorkspaceExit: mocks.allow }),
}));
import { AccountCard, DeleteAccountCard } from './AccountSettings';
function nodes(tree: ReactNode): Record<string, unknown>[] {
  const values: Record<string, unknown>[] = [];
  Children.forEach(tree, (child) => {
    if (!isValidElement<{ children?: ReactNode }>(child)) return;
    values.push(child.props);
    values.push(...nodes(child.props.children));
  });
  return values;
}
function textContent(tree: ReactNode): string {
  return Children.toArray(tree)
    .map((child) =>
      isValidElement<{ children?: ReactNode }>(child) ? textContent(child.props.children) : String(child),
    )
    .join('');
}
const run = vi.fn((action: () => Promise<void>) => {
  void action();
});
beforeEach(() => {
  vi.clearAllMocks();
  mocks.index = 0;
  mocks.states = [];
  mocks.allow.mockReturnValue(false);
});

// MARK: - The guard runs before run() can trigger account revocation or deletion
describe('account recording exit guards', () => {
  it.each(['Log out', 'Log out everywhere'])(
    'keeps credentials when an active recording blocks %s',
    (label) => {
      mocks.states = [true];
      const tree = AccountCard({ working: false, run });
      const choices = nodes(tree).filter(
        (node) => node.onClick && textContent(node.children as ReactNode).trim() === label,
      );
      const action = choices[choices.length - 1].onClick as () => void;
      action();
      expect(mocks.allow).toHaveBeenCalledOnce();
      expect(run).not.toHaveBeenCalled();
      expect(mocks.logout).not.toHaveBeenCalled();
      expect(mocks.logoutAll).not.toHaveBeenCalled();
    },
  );
  it('allows ordinary sign out after the recording exit is approved', () => {
    mocks.allow.mockReturnValue(true);
    const button = nodes(AccountCard({ working: false, run })).find(
      (node) => node.onClick && Array.isArray(node.children) && node.children.includes('Log out'),
    )!;
    (button.onClick as () => void)();
    expect(mocks.logout).toHaveBeenCalledOnce();
  });
  it('guards validated account deletion before server data is removed', () => {
    mocks.states = ['synthetic@example.test', 'Synthetic1!'];
    const form = nodes(DeleteAccountCard({ working: false, run })).find((node) => node.onSubmit)!;
    const submit = form.onSubmit as (event: { preventDefault: () => void }) => void;
    submit({ preventDefault: vi.fn() });
    expect(mocks.allow).toHaveBeenCalledOnce();
    expect(mocks.deleteAccount).not.toHaveBeenCalled();
    mocks.allow.mockReturnValue(true);
    submit({ preventDefault: vi.fn() });
    expect(mocks.deleteAccount).toHaveBeenCalledWith('Synthetic1!');
  });
});
