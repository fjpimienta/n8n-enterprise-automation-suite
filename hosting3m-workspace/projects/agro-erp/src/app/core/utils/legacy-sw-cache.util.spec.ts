import { describe, expect, it, vi } from 'vitest';
import { LEGACY_SW_CACHE_NAMES, purgeLegacySwCaches } from './legacy-sw-cache.util';

describe('purgeLegacySwCaches', () => {
  it('deletes only the legacy cache names', async () => {
    const del = vi.fn().mockResolvedValue(true);
    await purgeLegacySwCaches({ delete: del });
    expect(del.mock.calls.map((c) => c[0])).toEqual([...LEGACY_SW_CACHE_NAMES]);
    expect(LEGACY_SW_CACHE_NAMES).toContain('agroerp-pwa-v2');
    expect(del).not.toHaveBeenCalledWith(expect.stringMatching(/^ngsw:/));
  });

  it('does not throw when a deletion rejects', async () => {
    const del = vi.fn().mockRejectedValue(new Error('denied'));
    await expect(purgeLegacySwCaches({ delete: del })).resolves.toBeUndefined();
  });

  it('is a no-op without CacheStorage', async () => {
    await expect(purgeLegacySwCaches(undefined)).resolves.toBeUndefined();
  });
});
