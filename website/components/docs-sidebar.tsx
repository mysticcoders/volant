// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
'use client';

import { usePathname } from 'next/navigation';

import { docGroups } from '@/app/docs/docs-nav';

export function DocsSidebar() {
  const pathname = usePathname();
  return (
    <aside className="docs-sidebar">
      <nav aria-label="Documentation">
        {docGroups.map((group) => (
          <div className="docs-sidebar-group" key={group.group}>
            <p>{group.group}</p>
            {group.links.map((link) => {
              const href = `/docs/${link.slug}`;
              const current = pathname === href;
              return (
                <a
                  key={link.slug}
                  href={href}
                  className={current ? 'current' : undefined}
                  aria-current={current ? 'page' : undefined}
                >
                  {link.title}
                </a>
              );
            })}
          </div>
        ))}
      </nav>
    </aside>
  );
}
