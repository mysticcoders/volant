export type DocLink = {
  slug: string;
  title: string;
  summary: string;
};

export type DocGroup = {
  group: string;
  links: DocLink[];
};

export const docGroups: DocGroup[] = [
  {
    group: 'START HERE',
    links: [
      {
        slug: 'getting-started',
        title: 'Getting started',
        summary:
          'Install Volant, summon it for the first time, and find your configuration.',
      },
      {
        slug: 'configuration',
        title: 'Configuration',
        summary:
          'Every key in config.json, matching the example that ships inside the app.',
      },
    ],
  },
  {
    group: 'EVERYDAY USE',
    links: [
      {
        slug: 'launcher',
        title: 'The launcher',
        summary:
          'Search apps, files, and contacts, calculate and convert, and join today’s meetings.',
      },
      {
        slug: 'calculator',
        title: 'The calculator',
        summary:
          'Arithmetic, percentages, units, time zones, dates, colors and currency, answered as you type.',
      },
      {
        slug: 'notes',
        title: 'Notes',
        summary:
          'A floating Markdown window with live styling, backed by ordinary .md files.',
      },
      {
        slug: 'clipboard-and-snippets',
        title: 'Clipboard and snippets',
        summary:
          'Encrypted clipboard history, reusable snippets, and the placeholders they expand.',
      },
      {
        slug: 'system-control',
        title: 'System control',
        summary:
          'Audio, connectivity, keep-awake, Settings, and upcoming system commands.',
      },
      {
        slug: 'shortcuts',
        title: 'Apple Shortcuts',
        summary:
          'Run a saved shortcut from a quicklink, optionally passing typed text.',
      },
    ],
  },
  {
    group: 'GOING FURTHER',
    links: [
      {
        slug: 'agents',
        title: 'Agents',
        summary:
          'Herdr questions, coding agents, API and local models, and context you choose.',
      },
      {
        slug: 'importing-from-raycast',
        title: 'Importing from Raycast',
        summary:
          'Bring snippets, quicklinks, aliases, hotkeys, and notes across from an export.',
      },
      {
        slug: 'extensions',
        title: 'Extensions',
        summary:
          'A sandboxed WebAssembly spike with a deliberately unstable API.',
      },
      {
        slug: 'privacy-and-security',
        title: 'Privacy and security',
        summary:
          'Sandboxing, permissions, encryption, and what never leaves your Mac.',
      },
    ],
  },
];

export const allDocLinks: DocLink[] = docGroups.flatMap((group) => group.links);

export function adjacentDocs(slug: string) {
  const index = allDocLinks.findIndex((link) => link.slug === slug);
  return {
    previous: index > 0 ? allDocLinks[index - 1] : undefined,
    next:
      index >= 0 && index < allDocLinks.length - 1
        ? allDocLinks[index + 1]
        : undefined,
  };
}
