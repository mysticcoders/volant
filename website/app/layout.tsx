import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  metadataBase: new URL('https://usevolant.com'),
  alternates: { canonical: 'https://usevolant.com/' },
  title: 'Volant — A little less friction. A lot more flow.',
  description:
    'A focused Mac utility for Live Markdown notes, app launching, reusable snippets, and local encrypted clipboard history. Local first and in development.',
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
