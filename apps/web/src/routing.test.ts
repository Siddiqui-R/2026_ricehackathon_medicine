import { describe, expect, it } from 'vitest';
import { readWorkspaceRoute } from './routing';

describe('workspace route recovery', () => {
  it.each(['', '#/', '#/summary', '#/records', '#/profile', '#/settings', '#/visits', '#/recording'])(
    'preserves the supported route %s',
    (hash) => expect(readWorkspaceRoute(hash).section).not.toBe('not-found'),
  );
  it.each(['records', 'visits', 'recordings'])('preserves %s details and query parameters', (section) => {
    const route = readWorkspaceRoute(`#/${section}/example%20id?source=original`);
    expect(route.section).toBe(section);
    expect(route.id).toBe('example id');
    expect(route.query.get('source')).toBe('original');
  });
  it.each([
    '#/hospital',
    '#/records/example/extra',
    '#/profile/extra',
    '#/summary/extra',
    '#/recording/extra',
    '#/recordings',
    '#/records/%E0%A4%A',
    '#unexpected',
  ])('recovers from invalid or malformed route %s without opening another page', (hash) => {
    expect(readWorkspaceRoute(hash).section).toBe('not-found');
  });
});
