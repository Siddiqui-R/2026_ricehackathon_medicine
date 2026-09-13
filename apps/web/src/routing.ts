// Parse only the supported workspace routes; invalid bookmarks get a recovery screen.
export function readWorkspaceRoute(value: string) {
  const hash = value.replace(/^#/u, '') || '/summary';
  const queryStart = hash.indexOf('?');
  const path = (queryStart < 0 ? hash : hash.slice(0, queryStart)).replace(/\/+$/u, '') || '/';
  const query = new URLSearchParams(queryStart < 0 ? '' : hash.slice(queryStart + 1));
  const parts = path === '/' ? ['summary'] : path.slice(1).split('/');
  let section = parts[0];
  let id: string | undefined = parts[1];
  const detailRoute = ['records', 'visits', 'recordings'].includes(section);
  const known = ['summary', 'records', 'visits', 'recording', 'recordings', 'profile', 'settings'];
  if (
    !path.startsWith('/') ||
    !known.includes(section) ||
    parts.length > 2 ||
    (parts.length === 2 && (!detailRoute || !id)) ||
    (section === 'recordings' && !id)
  )
    section = 'not-found';
  try {
    id = id ? decodeURIComponent(id) : undefined;
  } catch {
    section = 'not-found';
    id = undefined;
  }
  return { section, id, query, hash };
}
