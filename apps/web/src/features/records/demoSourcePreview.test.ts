import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { seed } from '../../core/__tests__/fixtures';
import { demoSourcePreview, loadDemoSourcePreview } from './demoSourcePreview';

describe('bundled source presentation', () => {
  it('verifies every preview and limits replacement to its exact bundled record', async () => {
    for (const record of seed().records) {
      const entry = demoSourcePreview(record)!;
      expect(entry).toBeDefined();
      const bytes = await readFile(
        new URL(`../../../assets/source-previews/${record.sourceFilename}`, import.meta.url),
      );
      expect(bytes.length).toBe(entry.bytes);
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(entry.sha256);
      expect(demoSourcePreview({ ...record, isDemo: false })).toBeUndefined();
      expect(demoSourcePreview({ ...record, id: 'imported-record' })).toBeUndefined();
      expect(demoSourcePreview({ ...record, sourceFilename: 'my-upload.pdf' })).toBeUndefined();
    }
  });
  it('rejects stale or unexpected assets instead of substituting another document', async () => {
    const record = seed().records[0];
    const source = demoSourcePreview(record)!;
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('wrong document')));
    try {
      await expect(loadDemoSourcePreview(record.sourceFilename!, source)).rejects.toThrow(
        'could not be verified',
      );
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
