/** Mobile navigation toggle. Without JS the nav is simply always visible. */
export function initMenu(): void {
  const btn = document.querySelector<HTMLButtonElement>('.menu-toggle');
  const nav = document.getElementById('site-nav');
  if (!btn || !nav) return;
  btn.hidden = false;
  const setOpen = (open: boolean) => {
    btn.setAttribute('aria-expanded', String(open));
    nav.toggleAttribute('data-open', open);
    const label = btn.querySelector('.menu-toggle-label');
    if (label) label.textContent = open ? 'Close' : 'Menu';
  };
  btn.addEventListener('click', () => setOpen(btn.getAttribute('aria-expanded') !== 'true'));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && btn.getAttribute('aria-expanded') === 'true') {
      setOpen(false);
      btn.focus();
    }
  });
  window.matchMedia('(min-width: 1080px)').addEventListener('change', (mq) => {
    if (mq.matches) setOpen(false);
  });
}
