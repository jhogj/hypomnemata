import { useRef, useState } from "react";
import { api, type Item } from "../lib/api";

interface Props {
  item: Item;
  onClick: (videoTime?: number) => void;
}

const KIND_LABEL: Record<Item["kind"], string> = {
  image: "imagem",
  article: "artigo",
  video: "vídeo",
  tweet: "tweet",
  bookmark: "bookmark",
  note: "nota",
  pdf: "pdf",
};

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "short" });
}

/** Extract thumbnail_path from meta_json if available. */
function getThumbnailPath(item: Item): string | null {
  if (!item.meta_json) return null;
  try {
    const m = JSON.parse(item.meta_json) as { thumbnail_path?: string };
    return m.thumbnail_path || null;
  } catch {
    return null;
  }
}

/** Check if the item has a playable video asset. */
function getVideoUrl(item: Item): string | null {
  if (!item.asset_path) return null;
  if (/\.(mp4|webm|mkv|mov|m4v)$/i.test(item.asset_path)) {
    return api.assetUrl(item.asset_path);
  }
  return null;
}

export function Card({ item, onClick }: Props) {
  const [playing, setPlaying] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  const hasImage = item.asset_path && ["image", "tweet"].includes(item.kind);
  const showThumb = hasImage && /\.(png|jpe?g|gif|webp)$/i.test(item.asset_path || "");
  const thumbnailPath = getThumbnailPath(item);
  const videoUrl = getVideoUrl(item);
  const isVideoKind = item.kind === "video" || (item.kind === "tweet" && videoUrl != null);

  // Determine what image to show: direct image asset, or a thumbnail
  const cardImageUrl = showThumb
    ? api.assetUrl(item.asset_path!)
    : thumbnailPath
      ? api.assetUrl(thumbnailPath)
      : null;

  // Can this card play inline?
  const canPlay = isVideoKind && videoUrl != null;

  function handlePlayClick(e: React.MouseEvent) {
    e.stopPropagation();
    setPlaying(true);
  }

  function handleCardClick() {
    // Capture currentTime from the inline player before opening the modal.
    let videoTime: number | undefined;
    if (playing && videoRef.current) {
      videoTime = videoRef.current.currentTime;
      videoRef.current.pause();
    }
    setPlaying(false);
    onClick(videoTime);
  }

  return (
    <button
      type="button"
      onClick={handleCardClick}
      className="group mb-4 w-full break-inside-avoid overflow-hidden rounded border border-paper-border bg-paper-card text-left shadow-sm transition-shadow hover:shadow-md"
    >
      {playing && videoUrl ? (
        /* Inline video player — click on the video interacts with controls, not the card */
        <div onClick={(e) => e.stopPropagation()}>
          <video
            ref={videoRef}
            src={videoUrl}
            controls
            autoPlay
            className="block w-full"
          />
        </div>
      ) : cardImageUrl ? (
        <div className="relative">
          <img
            src={cardImageUrl}
            alt={item.title || ""}
            className="block w-full"
            loading="lazy"
          />
          {canPlay ? (
            <div
              className="absolute inset-0 flex cursor-pointer items-center justify-center"
              onClick={handlePlayClick}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-black/60 text-white shadow-lg backdrop-blur-sm transition-transform group-hover:scale-110">
                <svg
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  className="ml-0.5 h-5 w-5"
                >
                  <path d="M8 5v14l11-7z" />
                </svg>
              </div>
            </div>
          ) : (!showThumb && thumbnailPath) ? (
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-black/60 text-white shadow-lg backdrop-blur-sm transition-transform group-hover:scale-110">
                <svg
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  className="ml-0.5 h-5 w-5"
                >
                  <path d="M8 5v14l11-7z" />
                </svg>
              </div>
            </div>
          ) : null}
        </div>
      ) : item.download_status === "pending" ? (
        <div className="flex h-32 items-center justify-center border-b border-paper-border bg-paper-tag text-sm text-paper-mid">
          <svg className="mr-2 h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          Baixando...
        </div>
      ) : (
        <div className="flex h-32 items-center justify-center border-b border-paper-border bg-paper-tag text-sm text-paper-mid">
          {KIND_LABEL[item.kind]}
        </div>
      )}
      <div className="p-3">
        {item.title && (
          <div className="mb-1 line-clamp-2 text-sm font-medium text-paper-ink">
            {item.title}
          </div>
        )}
        <div className="flex items-center justify-between text-xs text-paper-mid">
          <span>{formatDate(item.captured_at)}</span>
          {item.tags[0] && (
            <span className="rounded-full bg-paper-tag px-2 py-0.5 text-[10px]">
              {item.tags[0]}
            </span>
          )}
        </div>
      </div>
    </button>
  );
}
