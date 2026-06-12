// Unlike the layout (which keeps the AppShell sidebar mounted), a template
// remounts on every navigation — so each page swap inside the shell gets
// the subtle enter animation while the sidebar stays perfectly still.
export default function AppPageTemplate({
  children,
}: {
  children: React.ReactNode;
}) {
  return <div className="page-enter">{children}</div>;
}
