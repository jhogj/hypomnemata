interface Props {
  name: string;
  onClick?: () => void;
  active?: boolean;
}

export function Tag({ name, onClick, active }: Props) {
  const cls = active
    ? "bg-paper-accent text-paper-card border-paper-accent"
    : "bg-paper-tag text-paper-mid border-paper-border hover:bg-paper-card";
  return (
    <button
      type="button"
      onClick={onClick}
      className={`inline-flex items-center rounded-full border px-3 py-0.5 text-xs transition-colors ${cls}`}
    >
      {name}
    </button>
  );
}
