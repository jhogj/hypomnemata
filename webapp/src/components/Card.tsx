import { api, type Item } from "../lib/api";

interface Props {
  item: Item;
  onClick: () => void;
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

export function Card({ item, onClick }: Props) {
  const hasImage = item.asset_path && ["image", "tweet"].includes(item.kind);
  const showThumb = hasImage && /\.(png|jpe?g|gif|webp)$/i.test(item.asset_path || "");

  return (
    <button
      type="button"
      onClick={onClick}
      className="group mb-4 w-full break-inside-avoid overflow-hidden rounded border border-paper-border bg-paper-card text-left shadow-sm transition-shadow hover:shadow-md"
    >
      {showThumb ? (
        <img
          src={api.assetUrl(item.asset_path!)}
          alt={item.title || ""}
          className="block w-full"
          loading="lazy"
        />
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
