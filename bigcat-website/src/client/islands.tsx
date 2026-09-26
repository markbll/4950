import { createElement, type ComponentType } from 'react';
import type { IslandName } from '../components/Island';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyComponent = ComponentType<any>;
const loaders: Record<IslandName, () => Promise<{ default: AnyComponent }>> = {
  checkup: () => import('../islands/CheckupForm'),
  contact: () => import('../islands/ContactForm'),
  subscribe: () => import('../islands/SubscribeForm'),
};

function hydrate(el: HTMLElement): void {
    const name = el.dataset.island as IslandName;
    const load = loaders[name];
    if (!load) return;
    let props: Record<string, unknown> = {};
    try {
      props = JSON.parse(el.dataset.props ?? '{}') as Record<string, unknown>;
    } catch {
      /* ignore bad props */
    }
    Promise.all([load(), import('react-dom/client')])
      .then(([mod, { hydrateRoot }]) => {
        hydrateRoot(el, createElement(mod.default, props));
      })
      .catch(() => {
        /* chunk failed to load — static HTML remains */
      });
}

/**
 * Hydrate only the interactive islands; the rest of the page stays static
 * HTML. React is loaded on demand: immediately for islands near the top of
 * the page, and on approach / first interaction for ones further down (e.g.
 * the footer subscribe form), so most pages load almost no JS up front.
 */
export function hydrateIslands(): void {
  const els = [...document.querySelectorAll<HTMLElement>('[data-island]')];
  if (!els.length) return;
  const once = (el: HTMLElement) => {
    if (el.dataset.hydrating) return;
    el.dataset.hydrating = '1';
    hydrate(el);
  };
  const io =
    'IntersectionObserver' in window
      ? new IntersectionObserver(
          (entries) => {
            for (const e of entries) {
              if (e.isIntersecting) {
                io?.unobserve(e.target);
                once(e.target as HTMLElement);
              }
            }
          },
          { rootMargin: '400px' },
        )
      : null;
  for (const el of els) {
    if (!io) {
      once(el);
      continue;
    }
    io.observe(el);
    el.addEventListener('focusin', () => once(el), { once: true });
    el.addEventListener('pointerdown', () => once(el), { once: true });
  }
}
