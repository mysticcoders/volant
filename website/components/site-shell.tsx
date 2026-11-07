'use client';
import { Monitor, Moon, Sun } from 'lucide-react';
import { useState, type ReactNode } from 'react';
import { SiteFooter, SiteHeader } from '@/components/site-chrome';
import '@/app/home.css';

const appearances = [
  { value: 'system', label: 'System', icon: Monitor },
  { value: 'light', label: 'Light', icon: Sun },
  { value: 'dark', label: 'Dark', icon: Moon },
] as const;

/**
 * One icon button for the page's appearance. Each click moves to the next of System, Light and
 * Dark; the icon shows the current choice and the label names it and the one that comes next.
 */
export function AppearanceButton({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  const index = Math.max(0, appearances.findIndex((option) => option.value === value));
  const current = appearances[index];
  const next = appearances[(index + 1) % appearances.length];
  const Icon = current.icon;
  const label = `Appearance: ${current.label}. Switch to ${next.label}.`;
  return (
    <button type="button" className="home-appearance" onClick={() => onChange(next.value)} aria-label={label} title={label}>
      <Icon size={16} aria-hidden="true" />
    </button>
  );
}

/** The homepage's page frame for other pages: its colors and type (home.css), the header with the
 * appearance button, and the footer. Children render inside `<main id="main">`. */
export function SiteShell({ children, mainClassName }: { children: ReactNode; mainClassName?: string }) {
  const [appearance, setAppearance] = useState('system');
  return (
    <div className="home-refresh" data-theme={appearance}>
      <a className="skip" href="#main">Skip to content</a>
      <SiteHeader>
        <AppearanceButton value={appearance} onChange={setAppearance} />
      </SiteHeader>
      <main id="main" className={mainClassName}>{children}</main>
      <SiteFooter />
    </div>
  );
}
