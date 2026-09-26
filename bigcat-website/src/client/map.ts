/** Lazy Google Map: inject the iframe when the placeholder nears the viewport, or on click. */
export function initMaps(): void {
  const maps = document.querySelectorAll<HTMLElement>('.map-embed[data-map-src]');
  if (!maps.length) return;
  const load = (el: HTMLElement) => {
    if (el.dataset.loaded) return;
    el.dataset.loaded = '1';
    const iframe = document.createElement('iframe');
    iframe.src = el.dataset.mapSrc!;
    iframe.title = el.dataset.mapTitle ?? 'Map';
    iframe.loading = 'lazy';
    iframe.referrerPolicy = 'no-referrer-when-downgrade';
    iframe.setAttribute('allowfullscreen', '');
    el.querySelector('.map-placeholder')?.replaceWith(iframe);
  };
  const io =
    'IntersectionObserver' in window
      ? new IntersectionObserver(
          (entries) => {
            for (const e of entries) {
              if (e.isIntersecting) {
                load(e.target as HTMLElement);
                io?.unobserve(e.target);
              }
            }
          },
          { rootMargin: '200px' },
        )
      : null;
  maps.forEach((el) => {
    el.querySelector('.map-load')?.addEventListener('click', () => load(el));
    io?.observe(el);
  });
}
