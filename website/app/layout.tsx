import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  metadataBase: new URL('https://usevolant.com'),
  alternates: { canonical: 'https://usevolant.com/' },
  title: 'Volant — Your Mac. Your agents. One shortcut away.',
  description:
    'Keep work moving with a native Mac launcher for apps, answers, notes, and agents. Local notes, encrypted clipboard history, and AI context you choose.',
  icons: { icon: '/favicon.svg' },
  openGraph: {
    type: 'website',
    url: 'https://usevolant.com/',
    siteName: 'Volant',
    title: 'Volant — Your Mac. Your agents. One shortcut away.',
    description:
      'Your apps, answers, notes, and agents. A native, open-source Mac launcher that keeps work moving.',
    images: [
      {
        url: '/images/social-card.png',
        width: 1280,
        height: 640,
        alt: 'Volant: Your Mac. Your agents. One shortcut away.',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Volant — Your Mac. Your agents. One shortcut away.',
    description:
      'Your apps, answers, notes, and agents. A native, open-source Mac launcher that keeps work moving.',
    images: ['/images/social-card.png'],
  },
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
