// Fictional stdin/stdout only: no real clipboard, preferences, toast, browser or paste access.
declare const Javy: { IO: { readSync(fd: number, data: Uint8Array): number; writeSync(fd: number, data: Uint8Array): number } };
export const Clipboard = {
  async read() {
    const buffer = new Uint8Array(65536);
    let used = 0;
    while (used < buffer.length) {
      const count = Javy.IO.readSync(0, buffer.subarray(used));
      if (!count) return { text: new TextDecoder().decode(buffer.subarray(0, used)) };
      used += count;
    }
    throw new Error("Fixture input must be smaller than 64 KiB");
  },
};
export async function update({ contents, error }: { contents?: string; error?: unknown }) {
  if (error) throw error;
  const bytes = new TextEncoder().encode(contents ?? "");
  for (let offset = 0; offset < bytes.length;) {
    const count = Javy.IO.writeSync(1, bytes.subarray(offset));
    if (!count) throw new Error("Short fixture write");
    offset += count;
  }
}
