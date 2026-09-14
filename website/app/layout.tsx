import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  metadataBase: new URL('https://usevolant.com'),
  alternates: { canonical: 'https://usevolant.com/' },
  title: 'Volant — Your Mac. Your agents. One shortcut away.',
  description:
    'A keyboard-first workspace for your Mac and coding agents. App launching, Herdr pane status, ACP conversations, Live Notes, encrypted clipboard history, and snippets. In development.',
  icons: { icon: '/favicon.svg' },
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="dark">
      <body>{children}</body>
    </html>
  );
}
