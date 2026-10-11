/**
 * Every value allowed by the `cattle_livestock.category` CHECK constraint (verified against
 * LOCAL on 2026-10-10). Keep in sync with that constraint when a category is added.
 */
export const LIVESTOCK_CATEGORIES: readonly string[] = [
  'VACA', 'TORO', 'NOVILLO', 'NOVILLONA', 'BECERRA', 'BECERRO', 'BECERRO_TORETE',
  'BUFALA', 'BUFALO', 'BUCERRA', 'BUCERRO',
  'BORREGA', 'BORREGO',
  'CABALLO', 'YEGUA', 'POTRO', 'POTRANCA', 'CABALLO_CASTRADO'
];
