import { useState, useRef, useEffect } from "react";
import { api, type Item, type ItemSummary } from "../lib/api";

interface Props {
  value: string;
  onChange: (val: string) => void;
  knownLinks: ItemSummary[];
}

export function NoteEditor({ value, onChange, knownLinks }: Props) {
  const [isEditing, setIsEditing] = useState(false);
  const [query, setQuery] = useState<{ text: string; cursorIndex: number } | null>(null);
  const [results, setResults] = useState<Item[]>([]);
  const [localTitles, setLocalTitles] = useState<Record<string, string>>({});
  const textareaRef = useRef<HTMLTextAreaElement>(null);

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

  function handleChange(e: React.ChangeEvent<HTMLTextAreaElement>) {
    const val = e.target.value;
    onChange(val);

    const cursor = e.target.selectionStart;
    const textBeforeCursor = val.slice(0, cursor);
    const match = textBeforeCursor.match(/\[\[([^\]]*)$/);
    if (match) {
      setQuery({ text: match[1], cursorIndex: cursor });
    } else {
      setQuery(null);
    }
  }

  useEffect(() => {
    if (!query) {
      setResults([]);
      return;
    }
    const timer = setTimeout(async () => {
      try {
        const res = await api.search(query.text);
        setResults(res.items.slice(0, 5));
      } catch (e) {}
    }, 300);
    return () => clearTimeout(timer);
  }, [query?.text]);

  function insertLink(item: Item) {
    if (!query || !textareaRef.current) return;
    
    setLocalTitles(prev => ({ ...prev, [item.id]: item.title || "Sem título" }));
    
    const before = value.slice(0, query.cursorIndex - query.text.length - 2);
    const after = value.slice(query.cursorIndex);
    const insert = `[[${item.id}]]`;
    
    onChange(before + insert + after);
    setQuery(null);
    
    setTimeout(() => {
      textareaRef.current?.focus();
    }, 10);
  }

  return (
    <div className="relative">
      {!isEditing ? (
        <div 
          onClick={() => setIsEditing(true)}
          className="min-h-[5rem] cursor-text rounded-md border border-paper-border bg-paper-bg p-3 hover:border-paper-accent/50"
        >
          {renderReadMode()}
        </div>
      ) : (
        <div className="relative">
          <textarea
            ref={textareaRef}
            value={value}
            onChange={handleChange}
            autoFocus
            onBlur={() => setTimeout(() => { if (!query) setIsEditing(false) }, 200)}
            rows={5}
            className="w-full resize-y rounded-md border border-paper-accent bg-paper-bg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-paper-accent"
          />
          {query && results.length > 0 && (
            <div className="absolute z-10 mt-1 w-full rounded-md border border-paper-border bg-paper-card py-1 shadow-xl">
              {results.map(res => (
                <button
                  key={res.id}
                  type="button"
                  onMouseDown={(e) => { e.preventDefault(); insertLink(res); }}
                  className="block w-full px-3 py-1.5 text-left text-xs text-paper-ink hover:bg-paper-tag"
                >
                  <div className="font-medium truncate">{res.title || "Sem título"}</div>
                  <div className="text-[10px] text-paper-mid opacity-70 uppercase tracking-wider">{res.kind}</div>
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
