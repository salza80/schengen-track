import type { CachePolicyIds } from './cache-policies';

// Existing policies owned by SchengTrackProd in account 360298971790.
// Staging references these directly so either stack can deploy first.
export const productionCachePolicyIds: CachePolicyIds = {
  publicHtml: '72b154d4-e67c-428b-93e5-56cf5b370ed7',
  tripsIndex: '196b0f46-f88f-4639-85e8-fd645c10ebb0',
  calendarIndex: '3a5f65ee-694f-4063-b169-07c693e9d028',
  authenticatedUser: '8bee0629-5937-4612-a802-8e74b94bb06c',
  immutableAssets: '2573f299-8298-488b-84e1-b8e16456ddde',
  namedAsset: '15ad0c20-3504-45f6-a25a-5abee1c2ecf1',
};
