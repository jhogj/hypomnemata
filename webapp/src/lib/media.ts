import { api, type Item } from "./api";

/** Extract thumbnail_path from meta_json if available. */
export function getThumbnailPath(item: Item): string | null {
  if (!item.meta_json) return null;
  try {
    const m = JSON.parse(item.meta_json);
    return m.thumbnail_path || null;
  } catch {
    return null;
  }
}

/** Check if the item has a playable video asset. */
export function getVideoUrl(item: Item): string | null {
  if (!item.asset_path) return null;
  if (/\.(mp4|webm|mkv|mov|m4v)$/i.test(item.asset_path)) {
    return api.assetUrl(item.asset_path);
  }
  return null;
}

/** Determine what image to show: direct image asset, or a thumbnail */
export function getPreviewImageUrl(item: Item): string | null {
  const hasImage = item.asset_path && ["image", "tweet", "article"].includes(item.kind);
  const showThumb = hasImage && /\.(png|jpe?g|gif|webp)$/i.test(item.asset_path || "");
  const thumbnailPath = getThumbnailPath(item);

  if (showThumb && item.asset_path) {
    return api.assetUrl(item.asset_path);
  }
  if (thumbnailPath) {
    return api.assetUrl(thumbnailPath);
  }
  return null;
}
