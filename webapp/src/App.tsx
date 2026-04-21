import { useState } from "react";
import { Library } from "./screens/Library";
import { CaptureModal } from "./screens/CaptureModal";
import { DetailModal } from "./screens/DetailModal";

export default function App() {
  const [captureOpen, setCaptureOpen] = useState(false);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [videoTime, setVideoTime] = useState<number | undefined>();
  const [reload, setReload] = useState(0);

  return (
    <>
      <Library
        onOpenDetail={(id, vt) => {
          setDetailId(id);
          setVideoTime(vt);
        }}
        onOpenCapture={() => setCaptureOpen(true)}
        reloadKey={reload}
      />

      {captureOpen && (
        <CaptureModal
          onClose={() => setCaptureOpen(false)}
          onSaved={() => {
            setCaptureOpen(false);
            setReload((r) => r + 1);
          }}
        />
      )}

      {detailId && (
        <DetailModal
          itemId={detailId}
          initialVideoTime={videoTime}
          onClose={() => {
            setDetailId(null);
            setVideoTime(undefined);
          }}
          onChanged={() => setReload((r) => r + 1)}
          onDeleted={() => {
            setDetailId(null);
            setVideoTime(undefined);
            setReload((r) => r + 1);
          }}
        />
      )}
    </>
  );
}
