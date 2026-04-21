import { type Item } from "../lib/api";
import { getPreviewImageUrl } from "../lib/media";
import { HoverPreview } from "./HoverPreview";

interface Props {
  items: Item[];
  onClick: (item: Item) => void;
  onDelete: (item: Item) => void;
}

const KIND_LABEL: Record<Item["kind"], string> = {
  image: "Imagem",
  article: "Artigo",
  video: "Vídeo",
  tweet: "Tweet",
  bookmark: "Bookmark",
  note: "Nota",
  pdf: "PDF",
};

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function getSourceDomain(url: string | null): string {
  if (!url) return "Upload manual";
  try {
    return new URL(url).hostname.replace("www.", "");
  } catch {
    return url;
  }
}

export function ListView({ items, onClick, onDelete }: Props) {
  return (
    <div className="w-full pb-8">
      <div className="min-w-full divide-y divide-paper-border overflow-hidden rounded-md border border-paper-border bg-paper-card shadow-sm">
        <div className="grid grid-cols-[100px_minmax(200px,_1fr)_200px_150px_60px] items-center bg-paper-tag px-4 py-3 text-xs font-semibold text-paper-mid uppercase tracking-wider">
          <div>Tipo</div>
          <div>Título / Conteúdo</div>
          <div>Origem</div>
          <div>Data</div>
          <div className="text-right">Ação</div>
        </div>
        <div className="divide-y divide-paper-border">
          {items.map((item) => {
            const previewUrl = getPreviewImageUrl(item);
            
            return (
              <HoverPreview key={item.id} imageUrl={previewUrl}>
                <div
                  onClick={() => onClick(item)}
                  className="group grid cursor-pointer grid-cols-[100px_minmax(200px,_1fr)_200px_150px_60px] items-center px-4 py-3 text-sm text-paper-ink transition-colors hover:bg-paper-tag/50"
                >
                  <div className="font-medium text-paper-mid">
                    {KIND_LABEL[item.kind]}
                  </div>
                  <div className="truncate pr-4">
                    {item.title ||
                      item.note ||
                      item.body_text?.slice(0, 100) ||
                      "Sem título"}
                  </div>
                  <div className="truncate text-paper-mid pr-4">
                    {getSourceDomain(item.source_url)}
                  </div>
                  <div className="text-paper-mid">
                    {formatDate(item.captured_at)}
                  </div>
                  <div className="text-right">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onDelete(item);
                      }}
                      className="opacity-0 transition-opacity hover:text-red-500 group-hover:opacity-100"
                      title="Excluir"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                        className="h-4 w-4 ml-auto"
                      >
                        <path
                          fillRule="evenodd"
                          d="M8.75 1A2.75 2.75 0 006 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 10.23 1.482l.149-.022.841 10.518A2.75 2.75 0 007.596 19h4.807a2.75 2.75 0 002.742-2.53l.841-10.52.149.023a.75.75 0 00.23-1.482A41.03 41.03 0 0014 4.193V3.75A2.75 2.75 0 0011.25 1h-2.5zM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4zM8.58 7.72a.75.75 0 00-1.5.06l.3 7.5a.75.75 0 101.5-.06l-.3-7.5zm4.34.06a.75.75 0 10-1.5-.06l-.3 7.5a.75.75 0 101.5.06l.3-7.5z"
                          clipRule="evenodd"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
              </HoverPreview>
            );
          })}
        </div>
      </div>
    </div>
  );
}
