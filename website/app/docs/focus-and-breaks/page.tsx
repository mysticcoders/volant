// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Focus and Breaks — Volant docs',
  description:
    'Block distracting apps and websites while you work on one goal, and get reminded to step away with Breaks.',
  alternates: { canonical: 'https://usevolant.com/docs/focus-and-breaks' },
};

export default function FocusAndBreaks() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Focus and Breaks
      </p>
      <h1>Focus and Breaks</h1>
      <p className="docs-lede">
        Focus keeps distracting apps and websites out of reach while you work
        on one thing. Breaks reminds you to step away. Both are new in 0.4.0.
      </p>

      <h2>Start a Focus session</h2>
      <p>
        Type <code>focus</code> and choose <strong>Start Focus Session</strong>.
        Set a goal, a length (15 to 90 minutes, or until you end it) and what
        to block: apps, websites, or ready-made categories such as Social Media,
        News, Video and Streaming, Shopping, Messaging and Mail. Volant
        remembers the setup, so next time <strong>Start with Last Setup</strong>{' '}
        or <code>focus 25m write the newsletter</code> starts at once. You can
        also set a <strong>Toggle Focus Session</strong> shortcut in Settings →
        Keyboard Shortcuts.
      </p>
      <p>
        While a session runs, <code>focus</code> offers Pause, Resume, Complete,
        Edit and End. A session keeps running if Volant restarts.
      </p>

      <h2>What blocking does</h2>
      <ul>
        <li>
          <strong>Apps</strong> on your list are hidden as soon as they come to
          the front. Volant never quits them, so nothing you were doing is lost.
        </li>
        <li>
          <strong>Websites</strong> are blocked in Safari, Google Chrome, Brave,
          Brave Origin and Vivaldi. When the browser in front shows a blocked
          site, Volant swaps the tab for a blank page, and puts the page back
          when you snooze it, pause or end the session. A site blocks its
          subdomains too: <code>x.com</code> also blocks{' '}
          <code>mobile.x.com</code>. Firefox can&rsquo;t be supported, because
          it doesn&rsquo;t let other apps read its tabs.
        </li>
        <li>
          A reminder shows what was blocked and your goal, with{' '}
          <strong>Snooze 3 Minutes</strong> for just that app or site. Change
          the snooze length in Settings → General → Focus.
        </li>
      </ul>
      <div className="docs-note">
        <p>
          Volant checks only the browser in front, about once a second, so a
          blocked page can appear briefly before it&rsquo;s blanked. A blocked
          site in a background tab is caught when you switch to it. Focus is
          separate from macOS Focus and doesn&rsquo;t silence notifications.
        </p>
      </div>

      <h2>Where the timer shows</h2>
      <p>
        On a MacBook with a camera notch, the session sits around the notch: the
        time on one side, and the controls when you rest the pointer on it.
        Reminders drop out of the notch. On other screens it shows as a small
        floating bar you can drag anywhere. Choose <strong>Show In</strong> from
        its menu to pick the notch, the floating bar or the menu bar.
      </p>

      <h2>Breaks</h2>
      <p>
        Breaks is off until you turn it on in Settings → General → Breaks or
        with <code>break</code> in the launcher. By default it suggests a
        5-minute break after every 45 minutes, with a heads-up a minute before
        that offers Postpone and Skip.
      </p>
      <ul>
        <li>
          <strong>Active time</strong> counts only the time you&rsquo;re at
          your Mac; being away for a full break counts as taking one.{' '}
          <strong>Clock time</strong> keeps a fixed rhythm instead.
        </li>
        <li>
          <strong>Gentle</strong> shows a small reminder, <strong>Standard</strong>{' '}
          covers every display with a countdown, and <strong>Strict</strong>{' '}
          asks you to hold Skip for a few seconds. There&rsquo;s always a way
          out, and the overlay never outlives Volant.
        </li>
        <li>
          A break waits while your camera or microphone is in use, so it
          won&rsquo;t interrupt a call, and a running Focus session pauses for
          the break.
        </li>
      </ul>

      <h2>Privacy</h2>
      <p>
        Volant asks macOS once per browser for permission to read its current
        tab. Addresses are compared on your Mac while a session blocks
        websites, and are never saved, logged or synced; only the address of a
        tab Volant blanked is kept, in memory, to put it back. Breaks reads how
        long your Mac has been idle and whether a camera or microphone is in
        use, never what they capture. See{' '}
        <a href="/docs/privacy-and-security">Privacy and security</a>.
      </p>

      <DocFooterNav {...adjacentDocs('focus-and-breaks')} />
    </>
  );
}
