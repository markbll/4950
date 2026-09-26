import { createContext, useContext, type ReactNode } from 'react';

export type IslandName = 'checkup' | 'contact' | 'subscribe';

export interface RenderCollector {
  islands: Set<IslandName>;
}

export const RenderContext = createContext<RenderCollector | null>(null);

/**
 * Server-rendered wrapper for an interactive "island". The client entry finds
 * [data-island] elements and hydrates only those, so most pages ship almost
 * no JavaScript.
 */
export function Island<P extends object>({ name, props, children }: { name: IslandName; props: P; children: ReactNode }) {
  const ctx = useContext(RenderContext);
  ctx?.islands.add(name);
  return (
    <div data-island={name} data-props={JSON.stringify(props)}>
      {children}
    </div>
  );
}
