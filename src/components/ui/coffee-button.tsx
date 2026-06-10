// Buy Me a Coffee button, styled with the app's butter token so it reads
// as the BMC brand button while sitting naturally in the palette.
// Used in the app sidebar and the homepage footer.
export function CoffeeButton({ className = "" }: { className?: string }) {
  return (
    <a
      href="https://buymeacoffee.com/abmd"
      target="_blank"
      rel="noopener noreferrer"
      className={`inline-flex items-center justify-center gap-2 rounded-full px-4 py-2.5 text-[13px] font-bold text-ink shadow-sm transition-opacity hover:opacity-85 ${className}`}
      style={{ background: "var(--color-butter)" }}
    >
      <span aria-hidden>☕</span> Buy me a coffee
    </a>
  );
}
