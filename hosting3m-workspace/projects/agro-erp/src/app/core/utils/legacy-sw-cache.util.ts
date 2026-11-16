/** Cache created by the hand-written service worker that Angular's ngsw replaced (Refs #1087). */
export const LEGACY_SW_CACHE_NAMES: readonly string[] = ['agroerp-pwa-v2'];

/**
 * Best-effort removal of the legacy service-worker caches. Angular's worker only manages its own
 * `ngsw:` caches and never touches foreign ones, so without this the old cache would stay on the
 * device. Only exact legacy names are deleted; never fails the app start.
 */
export async function purgeLegacySwCaches(
  cacheStorage: Pick<CacheStorage, 'delete'> | undefined = typeof caches === 'undefined' ? undefined : caches,
): Promise<void> {
  if (!cacheStorage) return;
  await Promise.all(
    LEGACY_SW_CACHE_NAMES.map((name) => cacheStorage.delete(name).catch(() => false)),
  );
}
