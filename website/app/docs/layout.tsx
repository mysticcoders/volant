import { DocsSidebar } from '@/components/docs-sidebar';
import { SiteFooter, SiteHeader } from '@/components/site-chrome';

export default function DocsLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <SiteHeader />
      <div className="docs-shell wrap">
        <DocsSidebar />
        <main id="main" className="docs-main">
          {children}
        </main>
      </div>
      <SiteFooter />
    </>
  );
}
