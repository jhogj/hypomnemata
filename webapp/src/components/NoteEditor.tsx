import { useState, useRef, useEffect } from "react";
import { api, type ItemSummary } from "../lib/api";
import { MentionsInput, Mention, SuggestionDataItem } from "react-mentions";

interface Props {
  value: string;
  onChange: (val: string) => void;
  knownLinks: ItemSummary[];
  onNavigate?: (id: string) => void;
}

export function NoteEditor({ value, onChange, knownLinks, onNavigate }: Props) {
  const [isEditing, setIsEditing] = useState(false);
  const [localTitles, setLocalTitles] = useState<Record<string, string>>({});
  const containerRef = useRef<HTMLDivElement>(null);

  // Fecha o modo de edição quando clicar fora
  useEffect(() => {
    if (!isEditing) return;
    function handleClickOutside(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsEditing(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [isEditing]);

  function renderReadMode() {
    if (!value) return <span className="text-paper-mid opacity-60">Clique para adicionar uma nota...</span>;

    const parts = [];
    const regex = /\[\[([a-f0-9\-]{36})(?:\|([^\]]*))?\]\]/gi;
    let lastIndex = 0;
    let match;

    while ((match = regex.exec(value)) !== null) {
      if (match.index > lastIndex) {
        parts.push(value.slice(lastIndex, match.index));
      }
      const id = match[1];
      const titleOverride = match[2];
      
      const known = knownLinks.find(l => l.id === id);
      const title = titleOverride || known?.title || localTitles[id] || "Link (Salvar para carregar)";

      parts.push(
        <span 
          key={match.index}
          className="inline-flex cursor-pointer items-center rounded bg-paper-accent/10 px-1.5 py-0.5 text-xs font-medium text-paper-accent hover:bg-paper-accent/20"
          title={id}
          onClick={(e) => {
            e.stopPropagation();
            if (onNavigate) onNavigate(id);
          }}
        >
          ↗ {title}
        </span>
      );
      lastIndex = regex.lastIndex;
    }
    if (lastIndex < value.length) {
      parts.push(value.slice(lastIndex));
    }

    return <div className="whitespace-pre-wrap font-sans text-sm text-paper-ink">{parts}</div>;
  }

  async function fetchMentions(query: string, callback: (data: SuggestionDataItem[]) => void) {
    if (!query) return;
    try {
      const res = await api.search(query);
      const items = res.items.slice(0, 5).map((it) => ({
        id: it.id,
        display: it.title || "Sem título",
        kind: it.kind,
      }));
      callback(items);
    } catch (e) {
      callback([]);
    }
  }

  return (
    <div className="relative" ref={containerRef}>
      {!isEditing ? (
        <div 
          onClick={() => setIsEditing(true)}
          className="min-h-[5rem] cursor-text rounded-md border border-paper-border bg-paper-bg p-3 hover:border-paper-accent/50"
        >
          {renderReadMode()}
        </div>
      ) : (
        <div className="relative">
          <MentionsInput
            value={value}
            onChange={(_e, newValue) => onChange(newValue)}
            className="mentions-editor"
            placeholder="Digite [[ para conectar outro item..."
            autoFocus
          >
            <Mention
              trigger="[["
              markup="[[__id__|__display__]]"
              displayTransform={(_id, display) => `↗ ${display}`}
              data={fetchMentions}
              onAdd={(id, display) => {
                setLocalTitles((prev) => ({ ...prev, [String(id)]: display }));
              }}
              style={{
                backgroundColor: 'rgba(199, 164, 117, 0.2)',
                borderRadius: '4px',
                padding: '0 2px',
              }}
              renderSuggestion={(suggestion: any, _search, highlightedDisplay) => (
                <div className="flex w-full flex-col gap-0.5 px-3 py-2 truncate">
                  <div className="font-medium text-paper-ink truncate">{highlightedDisplay}</div>
                  <div className="text-[10px] text-paper-mid opacity-70 uppercase tracking-wider">{suggestion.kind}</div>
                </div>
              )}
            />
          </MentionsInput>
        </div>
      )}
    </div>
  );
}
